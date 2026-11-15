"""Zigbee2MQTT client for the Quickshell office panel.

Watches a fixed list of devices on the MQTT broker and reports them to its
parent as JSON lines; takes commands for the light and the blind as JSON lines
on stdin. Times are UTC, ISO 8601 with milliseconds and "Z".

Usage: desk-mqtt [--devices FILE] [--config FILE] [--read-only]

--devices: JSON list of {"id", "kind", "label"}, kind light, blind or socket.
--config: JSON {"host", "port"?, "base", "topics": {id: friendly name}}, the
    broker and the Zigbee2MQTT names, which live outside the repository.
--read-only: subscribe only; every valid command is refused ("read-only").

stdout:
  {"event": "config", "state": "ok", "read_only": bool,
      "devices": [{"id", "kind", "label"}]}
  {"event": "config", "state": "missing" | "invalid", "error": str}
      Nothing else follows but command refusals ("not-configured") and exit.
  {"event": "broker", "state": "connecting" | "up" | "down", "since": t,
      "ever_up": bool, "last_attempt": t?, "error": str?}
      "since" is when this process saw the state begin. "down" is sent
      again after each failed attempt (every 10 s) with its "last_attempt".
  {"event": "bridge", "state": "online" | "offline", "since": t?}
      Zigbee2MQTT's bridge/state, first sent when it is received (unknown
      until then). "since" is null when the state came from a retained
      message (its start is not known).
  {"event": "synced"}
      Retained messages for this connection have arrived (1 s after the
      subscription was acknowledged); a device still with "values": null
      has nothing retained.
  {"event": "device", "id", "kind", "label", "values": {...} | null,
      "last_seen": str?, "received": t?, "retained": bool?,
      "availability": "online" | "offline" | null, "availability_since": t?,
      "definition": {"matches": bool, "properties": [...]} | null}
      Sent whole on every change. values holds only state and brightness
      (light); state, position, motor_state and running (blind); state and
      power (socket). last_seen is Zigbee2MQTT's, received this process's.
      definition comes from bridge/devices: whether the device is of its
      kind and which of those properties it exposes.
  {"event": "command", "id": N, "state": "pending", "device", "action",
      "value"?, "at": t}
  {"event": "command", "id": N, "state": "confirmed" | "not-confirmed"}
  {"event": "command", "id": N | null, "state": "refused", "reason": str}
  {"event": "bad-input", "line": str}, {"event": "exit"}

stdin: {"id": N, "device": "light", "action": "on" | "off"}
       {"id": N, "device": "light", "action": "brightness", "value": 1..254}
       {"id": N, "device": "blind", "action": "open" | "close" | "stop"}
       {"id": N, "device": "blind", "action": "position", "value": 0..100}

A command is published once, at QoS 0, to <base>/<light or blind>/set and
never retried. It is confirmed by the first non-retained state message from
that device within 5 s that shows the result (see confirms()). A brightness
command also switches the light on. Sockets have no command at all. When
stdin closes the process disconnects and exits.
"""

import argparse
import json
import sys
import threading
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

DEVICES = "@devices@"
CONFIG = "@config@"

RETRY_SECONDS = 10
CONFIRM_SECONDS = 5
SYNC_SECONDS = 1

KEYS = {
    "light": ("state", "brightness"),
    "blind": ("state", "position", "motor_state", "running"),
    "socket": ("state", "power"),
}
# The expose type in bridge/devices that a device of each kind must have.
EXPOSE_TYPE = {"light": "light", "blind": "cover", "socket": "switch"}
# The only kinds that can be published to, and every command each takes:
# action -> (min, max) of its value, or None for no value.
COMMANDS = {
    "light": {"on": None, "off": None, "brightness": (1, 254)},
    "blind": {"open": None, "close": None, "stop": None, "position": (0, 100)},
}

LOCK = threading.Lock()


def now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def emit(**obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def state_of(payload):
    """The "state" of an availability or bridge/state payload: JSON or plain."""
    text = payload.decode(errors="replace").strip()
    try:
        value = json.loads(text)
    except ValueError:
        return text
    return value.get("state") if isinstance(value, dict) else None


def set_payload(kind, action, value):
    if kind == "light":
        if action == "brightness":
            return {"state": "ON", "brightness": value}
        return {"state": action.upper()}
    if action == "position":
        return {"position": value}
    return {"state": action.upper()}


def confirms(kind, action, value, values):
    """Whether a device's reported values show that a command took effect."""
    state = values.get("state")
    if kind == "light":
        if action == "brightness":
            return state == "ON" and values.get("brightness") == value
        return state == action.upper()
    motor = values.get("motor_state")
    if action == "open":
        return motor == "opening" or state == "OPEN"
    if action == "close":
        return motor == "closing" or state == "CLOSE"
    if action == "stop":
        return motor == "stopped" or state == "STOP"
    return values.get("position") == value or motor in ("opening", "closing")


def load_devices(path):
    with open(path) as f:
        devices = json.load(f)
    for d in devices:
        if d.get("kind") not in KEYS or not isinstance(d.get("id"), str):
            raise ValueError("bad device list")
    return devices


def valid_name(name):
    if not isinstance(name, str):
        return False
    return "+" not in name and "#" not in name and "" not in name.split("/")


def load_config(path, devices):
    """Returns (config, None), or (None, ("missing" | "invalid", error)).
    Errors name keys only, never values."""
    try:
        with open(path) as f:
            config = json.load(f)
    except FileNotFoundError:
        return None, ("missing", "no config file")
    except (OSError, ValueError) as e:
        return None, ("invalid", f"unreadable: {type(e).__name__}")
    if not isinstance(config, dict):
        return None, ("invalid", "not an object")
    if not isinstance(config.get("host"), str) or not config["host"]:
        return None, ("invalid", "host")
    port = config.get("port", 1883)
    if not isinstance(port, int) or isinstance(port, bool) or not 0 < port < 65536:
        return None, ("invalid", "port")
    if not valid_name(config.get("base")):
        return None, ("invalid", "base")
    topics = config.get("topics")
    if not isinstance(topics, dict):
        return None, ("invalid", "topics")
    for d in devices:
        name = topics.get(d["id"])
        if not valid_name(name) or name.split("/")[0] == "bridge":
            return None, ("invalid", f"topics.{d['id']}")
    names = [topics[d["id"]] for d in devices]
    if len(set(names)) != len(names):
        return None, ("invalid", "topics: a name is used twice")
    return {"host": config["host"], "port": port, "base": config["base"], "topics": topics}, None


def expose_properties(exposes):
    for e in exposes:
        if "property" in e:
            yield e["property"]
        yield from expose_properties(e.get("features", []))


class Device:
    def __init__(self, spec, name):
        self.id = spec["id"]
        self.kind = spec["kind"]
        self.label = spec.get("label", self.id)
        self.name = name
        self.values = None
        self.last_seen = None
        self.received = None
        self.retained = None
        self.availability = None
        self.availability_since = None
        self.definition = None

    def report(self):
        emit(event="device", id=self.id, kind=self.kind, label=self.label,
             values=self.values, last_seen=self.last_seen, received=self.received,
             retained=self.retained, availability=self.availability,
             availability_since=self.availability_since, definition=self.definition)


class Desk:
    def __init__(self, config, devices, read_only):
        self.base = config["base"]
        self.read_only = read_only
        self.devices = {d["id"]: Device(d, config["topics"][d["id"]]) for d in devices}
        self.by_topic = {}
        for d in self.devices.values():
            self.by_topic[f"{self.base}/{d.name}"] = (d, "state")
            self.by_topic[f"{self.base}/{d.name}/availability"] = (d, "availability")
        self.bridge = "unknown"
        self.bridge_since = None
        self.broker = "connecting"
        self.broker_since = now()
        self.ever_up = False
        self.pending = {}  # command id -> (device, action, value)
        self.sync_mid = None
        self.sync_timer = None

        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, clean_session=True)
        self.client.reconnect_delay_set(RETRY_SECONDS, RETRY_SECONDS)
        self.client.on_connect = self.on_connect
        self.client.on_connect_fail = self.on_connect_fail
        self.client.on_disconnect = self.on_disconnect
        self.client.on_subscribe = self.on_subscribe
        self.client.on_message = self.on_message
        self.config = config

    def start(self):
        self.report_broker()
        for d in self.devices.values():
            d.report()
        self.stopping = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        # The first connection is made here rather than by paho's
        # retry_first_connection, which waits twice (20 s) after the first
        # failure. Once connected, loop_forever retries every RETRY_SECONDS.
        while True:
            try:
                self.client.connect(self.config["host"], self.config["port"], keepalive=30)
                break
            except OSError:
                with LOCK:
                    self.set_broker("down", last_attempt=now())
            if self.stopping.wait(RETRY_SECONDS):
                return
        self.client.loop_forever()

    def stop(self):
        self.stopping.set()
        self.client.disconnect()
        self.thread.join(5)

    def report_broker(self, **extra):
        emit(event="broker", state=self.broker, since=self.broker_since,
             ever_up=self.ever_up, **extra)

    def set_broker(self, state, **extra):
        if state != self.broker:
            self.broker = state
            self.broker_since = now()
        self.report_broker(**extra)

    def on_connect(self, client, userdata, flags, reason, properties):
        with LOCK:
            if reason.is_failure:
                self.set_broker("down", last_attempt=now(), error=str(reason))
                return
            self.ever_up = True
            self.set_broker("up")
            topics = [f"{self.base}/bridge/state", f"{self.base}/bridge/devices"]
            topics += list(self.by_topic)
            self.sync_mid = client.subscribe([(t, 0) for t in topics])[1]

    def on_connect_fail(self, client, userdata):
        with LOCK:
            self.set_broker("down", last_attempt=now())

    def on_disconnect(self, client, userdata, flags, reason, properties):
        with LOCK:
            if self.sync_timer:
                self.sync_timer.cancel()
            if self.broker == "up" and not self.stopping.is_set():
                self.set_broker("down")

    def on_subscribe(self, client, userdata, mid, reasons, properties):
        with LOCK:
            if mid != self.sync_mid:
                return
            # Mosquitto queues the retained messages before the SUBACK but
            # writes them after it, so the SUBACK alone does not mean they
            # are in.
            self.sync_timer = threading.Timer(SYNC_SECONDS, self.synced)
            self.sync_timer.daemon = True
            self.sync_timer.start()

    def synced(self):
        with LOCK:
            if self.broker == "up":
                emit(event="synced")

    def on_message(self, client, userdata, msg):
        with LOCK:
            if msg.topic == f"{self.base}/bridge/state":
                self.on_bridge(msg)
            elif msg.topic == f"{self.base}/bridge/devices":
                self.on_definitions(msg.payload)
            elif msg.topic in self.by_topic:
                device, what = self.by_topic[msg.topic]
                if what == "availability":
                    self.on_availability(device, msg)
                else:
                    self.on_state(device, msg)

    def on_bridge(self, msg):
        state = state_of(msg.payload)
        if state not in ("online", "offline"):
            return
        if state != self.bridge:
            self.bridge_since = None if msg.retain else now()
        elif not msg.retain and self.bridge_since is None:
            self.bridge_since = now()
        self.bridge = state
        emit(event="bridge", state=self.bridge, since=self.bridge_since)

    def on_availability(self, device, msg):
        state = state_of(msg.payload)
        if state not in ("online", "offline"):
            return
        if state != device.availability:
            device.availability_since = None if msg.retain else now()
        device.availability = state
        device.report()

    def on_state(self, device, msg):
        try:
            payload = json.loads(msg.payload)
        except ValueError:
            return
        if not isinstance(payload, dict):
            return
        values = dict(device.values or {})
        for key in KEYS[device.kind]:
            if key in payload:
                values[key] = payload[key]
        device.values = values
        if isinstance(payload.get("last_seen"), str):
            device.last_seen = payload["last_seen"]
        device.received = now()
        device.retained = bool(msg.retain)
        device.report()
        if msg.retain:
            return
        for cid, (d, action, value) in list(self.pending.items()):
            if d is device and confirms(d.kind, action, value, values):
                del self.pending[cid]
                emit(event="command", id=cid, state="confirmed")

    def on_definitions(self, payload):
        try:
            entries = json.loads(payload)
        except ValueError:
            return
        if not isinstance(entries, list):
            return
        found = {e.get("friendly_name"): e for e in entries if isinstance(e, dict)}
        for device in self.devices.values():
            exposes = ((found.get(device.name) or {}).get("definition") or {}).get("exposes")
            if not isinstance(exposes, list):
                definition = None
            else:
                matches = any(e.get("type") == EXPOSE_TYPE[device.kind] for e in exposes)
                properties = set(expose_properties(exposes))
                definition = {"matches": matches,
                              "properties": [k for k in KEYS[device.kind] if k in properties]}
            if definition != device.definition:
                device.definition = definition
                device.report()

    def command(self, cid, device_id, action, value):
        """Checks and sends one parsed command; returns a refusal reason or None."""
        device = self.devices.get(device_id)
        if device is None:
            return "unknown-device"
        if device.kind not in COMMANDS:
            return "watch-only"
        if action not in COMMANDS[device.kind]:
            return "bad-input"
        limits = COMMANDS[device.kind][action]
        if (limits is None) != (value is None):
            return "bad-input"
        if limits is not None and not limits[0] <= value <= limits[1]:
            return "bad-value"
        if self.read_only:
            return "read-only"
        if self.broker != "up":
            return "broker-down"
        if self.bridge != "online":
            return "bridge-offline"
        if device.availability == "offline":
            return "device-offline"
        # A device list or config that names the wrong device must not turn
        # a light or blind command into a write to something else.
        if not (device.definition and device.definition["matches"]):
            return "type-unconfirmed"
        self.send(device, set_payload(device.kind, action, value))
        self.pending[cid] = (device, action, value)
        extra = {} if value is None else {"value": value}
        emit(event="command", id=cid, state="pending", device=device.id, action=action,
             at=now(), **extra)
        timer = threading.Timer(CONFIRM_SECONDS, self.expire, (cid,))
        timer.daemon = True
        timer.start()
        return None

    def send(self, device, payload):
        # The only publish in this program.
        assert device.kind in COMMANDS and not self.read_only
        self.client.publish(f"{self.base}/{device.name}/set", json.dumps(payload), qos=0)

    def expire(self, cid):
        with LOCK:
            if self.pending.pop(cid, None) is not None:
                emit(event="command", id=cid, state="not-confirmed")


def parse(line):
    """Returns (id, device, action, value) or raises ValueError(id)."""
    msg = json.loads(line)
    if not isinstance(msg, dict):
        raise ValueError(None)
    cid = msg.get("id")
    if not isinstance(cid, int) or isinstance(cid, bool):
        raise ValueError(None)
    if not set(msg) <= {"id", "device", "action", "value"}:
        raise ValueError(cid)
    device, action, value = msg.get("device"), msg.get("action"), msg.get("value")
    if not isinstance(device, str) or not isinstance(action, str):
        raise ValueError(cid)
    if value is not None and (not isinstance(value, int) or isinstance(value, bool)):
        raise ValueError(cid)
    return cid, device, action, value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--devices", default=DEVICES)
    parser.add_argument("--config", default=CONFIG)
    parser.add_argument("--read-only", action="store_true")
    args = parser.parse_args()

    devices = load_devices(args.devices)
    config, problem = load_config(args.config, devices)
    desk = None
    with LOCK:
        if problem:
            emit(event="config", state=problem[0], error=problem[1])
        else:
            emit(event="config", state="ok", read_only=args.read_only,
                 devices=[{"id": d["id"], "kind": d["kind"], "label": d.get("label", d["id"])}
                          for d in devices])
            desk = Desk(config, devices, args.read_only)
            desk.start()

    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            cid, device, action, value = parse(line)
        except json.JSONDecodeError:
            with LOCK:
                emit(event="bad-input", line=line.strip())
            continue
        except ValueError as e:
            with LOCK:
                emit(event="command", id=e.args[0], state="refused", reason="bad-input")
            continue
        with LOCK:
            reason = desk.command(cid, device, action, value) if desk else "not-configured"
            if reason:
                emit(event="command", id=cid, state="refused", reason=reason)

    if desk:
        desk.stop()
    with LOCK:
        emit(event="exit")


if __name__ == "__main__":
    main()
