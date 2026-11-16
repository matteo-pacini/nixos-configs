"""BlueZ pairing agent for the Quickshell Bluetooth panel.

Exports org.bluez.Agent1 on the system bus, registers it as BlueZ's default
agent (capability KeyboardDisplay) and talks to its parent over JSON lines.
The parent must answer every request; nothing is accepted here.

stdout: {"event": "ready", "capability": ...}
        {"event": "request", "id": N, "method": ..., "device": ..., ...}
            id is null for DisplayPasskey and DisplayPinCode, which need no
            answer. Extra fields: passkey (six digits as a string), entered,
            pincode, uuid.
        {"event": "cancel", "ids": [...]}   BlueZ withdrew the open request(s).
        {"event": "rssi", "device": ..., "rssi": n}   signal strength in dBm,
            as BlueZ reports it while it scans.
        {"event": "links", "device": ..., "transports": [{"uuid", "state"}],
            "control": bool, "network": bool, "calls": ...}   what is set up
            with the device: its media transports (A2DP, LE Audio; state
            idle, pending or active), whether media control (AVRCP) and
            network (PAN) are connected, and calls: "active" while a call's
            audio runs through this computer, "connected" while the
            hands-free link is up with no call audio, "none" otherwise or
            while PipeWire's telephony service (org.pipewire.Telephony on
            the session bus, run by WirePlumber) is not there. Sent for
            every device at start and again whenever one of these changes.
        {"event": "released"}, {"event": "exit"}
        {"event": "stale-answer", "id": N}, {"event": "bad-input", "line": ...}
stdin:  {"id": N, "accept": true|false, "passkey": int?, "pin": str?}

A request with no answer stays open until BlueZ gives up (60 s) and calls
Cancel. When stdin closes the agent unregisters and exits; if the process
dies instead, BlueZ drops the agent on its own.
"""

import asyncio
import json
import sys

from dbus_fast import BusType, DBusError, Message, MessageType
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, dbus_method

PATH = "/org/brightfalls/desk/agent"
CAPABILITY = "KeyboardDisplay"


def emit(**obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Agent(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.Agent1")
        self.last_id = 0
        self.pending = {}

    async def ask(self, method, device, **extra):
        self.last_id += 1
        rid = self.last_id
        fut = asyncio.get_running_loop().create_future()
        self.pending[rid] = fut
        emit(event="request", id=rid, method=method, device=device, **extra)
        try:
            answer = await fut
        finally:
            self.pending.pop(rid, None)
        if not answer.get("accept"):
            raise DBusError("org.bluez.Error.Rejected", "Rejected by user")
        return answer

    def answer(self, msg):
        fut = self.pending.get(msg.get("id"))
        if fut is None or fut.done():
            emit(event="stale-answer", id=msg.get("id"))
            return
        fut.set_result(msg)

    @dbus_method()
    def Release(self):
        emit(event="released")

    @dbus_method()
    async def RequestPinCode(self, device: "o") -> "s":
        return str((await self.ask("RequestPinCode", device))["pin"])

    @dbus_method()
    def DisplayPinCode(self, device: "o", pincode: "s"):
        emit(event="request", id=None, method="DisplayPinCode", device=device, pincode=pincode)

    @dbus_method()
    async def RequestPasskey(self, device: "o") -> "u":
        return int((await self.ask("RequestPasskey", device))["passkey"])

    @dbus_method()
    def DisplayPasskey(self, device: "o", passkey: "u", entered: "q"):
        emit(event="request", id=None, method="DisplayPasskey", device=device,
             passkey=f"{passkey:06d}", entered=entered)

    @dbus_method()
    async def RequestConfirmation(self, device: "o", passkey: "u"):
        await self.ask("RequestConfirmation", device, passkey=f"{passkey:06d}")

    @dbus_method()
    async def RequestAuthorization(self, device: "o"):
        await self.ask("RequestAuthorization", device)

    @dbus_method()
    async def AuthorizeService(self, device: "o", uuid: "s"):
        await self.ask("AuthorizeService", device, uuid=uuid)

    @dbus_method()
    def Cancel(self):
        emit(event="cancel", ids=list(self.pending))
        for fut in self.pending.values():
            if not fut.done():
                fut.set_result({"accept": False})


def rssi_of(props):
    value = props.get("RSSI")
    return None if value is None else value.value


TELEPHONY = "org.pipewire.Telephony"
TELEPHONY_PATH = "/org/pipewire/Telephony"


class Links:
    """Per device: media transports, whether AVRCP and PAN are up, and the
    hands-free link PipeWire holds for it."""

    DEVICE = "org.bluez.Device1"
    TRANSPORT = "org.bluez.MediaTransport1"
    CONTROL = "org.bluez.MediaControl1"
    NETWORK = "org.bluez.Network1"
    # One object per hands-free link whose setup (the AT handshake) is done,
    # removed when the link goes; the transport's State is "active" while
    # call audio (SCO) runs.
    GATEWAY = "org.pipewire.Telephony.AudioGateway1"
    GATEWAY_TRANSPORT = "org.pipewire.Telephony.AudioGatewayTransport1"

    def __init__(self):
        self.transports = {}  # transport path -> {"device", "uuid", "state"}
        self.control = {}     # device path -> bool
        self.network = {}
        self.addresses = {}   # device path -> address, upper case
        self.gateways = {}    # telephony object path -> {"address", "state"}

    def calls(self, device):
        address = self.addresses.get(device)
        states = [g["state"] for g in self.gateways.values()
                  if address is not None and g["address"] == address]
        if "active" in states:
            return "active"
        return "connected" if states else "none"

    def emit(self, device):
        transports = [{"uuid": t["uuid"], "state": t["state"]}
                      for t in self.transports.values() if t["device"] == device]
        emit(event="links", device=device, transports=transports,
             control=self.control.get(device, False), network=self.network.get(device, False),
             calls=self.calls(device))

    def device_of(self, address):
        return next((p for p, a in self.addresses.items() if a == address), None)

    def added(self, path, interfaces):
        """Takes one object's interfaces; returns the device it changed, or None."""
        if self.TRANSPORT in interfaces:
            props = interfaces[self.TRANSPORT]
            device = props["Device"].value
            self.transports[path] = {"device": device, "uuid": props["UUID"].value,
                                     "state": props["State"].value}
            return device
        changed = None
        # A device and its AVRCP and PAN interfaces share one object.
        if self.DEVICE in interfaces and "Address" in interfaces[self.DEVICE]:
            self.addresses[path] = interfaces[self.DEVICE]["Address"].value.upper()
            if self.calls(path) != "none":
                changed = path
        for name, table in ((self.CONTROL, self.control), (self.NETWORK, self.network)):
            if name in interfaces and "Connected" in interfaces[name]:
                table[path] = interfaces[name]["Connected"].value
                changed = path
        return changed

    def removed(self, path, interfaces):
        if self.DEVICE in interfaces:
            self.addresses.pop(path, None)
        if self.TRANSPORT in interfaces and path in self.transports:
            return self.transports.pop(path)["device"]
        changed = None
        for name, table in ((self.CONTROL, self.control), (self.NETWORK, self.network)):
            if name in interfaces and table.pop(path, None) is not None:
                changed = path
        return changed

    def changed(self, path, interface, props):
        if interface == self.TRANSPORT and path in self.transports and "State" in props:
            self.transports[path]["state"] = props["State"].value
            return self.transports[path]["device"]
        if interface in (self.CONTROL, self.NETWORK) and "Connected" in props:
            (self.control if interface == self.CONTROL else self.network)[path] = props["Connected"].value
            return path
        return None

    # The telephony side. Each returns the BlueZ device path it changed, or
    # None while BlueZ has not reported a device with that address.

    def gateway_added(self, path, interfaces):
        if self.GATEWAY not in interfaces:
            return None
        address = interfaces[self.GATEWAY]["Address"].value.upper()
        state = interfaces.get(self.GATEWAY_TRANSPORT, {}).get("State")
        self.gateways[path] = {"address": address, "state": state.value if state else "idle"}
        return self.device_of(address)

    def gateway_removed(self, path):
        gateway = self.gateways.pop(path, None)
        return self.device_of(gateway["address"]) if gateway else None

    def gateway_changed(self, path, props):
        if path not in self.gateways or "State" not in props:
            return None
        self.gateways[path]["state"] = props["State"].value
        return self.device_of(self.gateways[path]["address"])

    def gateways_gone(self):
        """The telephony service left the bus: returns the devices it had links for."""
        devices = {self.device_of(g["address"]) for g in self.gateways.values()}
        self.gateways.clear()
        return [d for d in devices if d is not None]


LINKS = Links()
# Running reloads of the telephony objects; asyncio keeps only weak references.
TASKS = set()


def on_signal(msg):
    if msg.message_type != MessageType.SIGNAL:
        return
    device = None
    if msg.member == "PropertiesChanged":
        interface, props = msg.body[0], msg.body[1]
        if interface == "org.bluez.Device1":
            rssi = rssi_of(props)
            if rssi is not None:
                emit(event="rssi", device=msg.path, rssi=rssi)
        else:
            device = LINKS.changed(msg.path, interface, props)
    elif msg.member == "InterfacesAdded":
        rssi = rssi_of(msg.body[1].get("org.bluez.Device1", {}))
        if rssi is not None:
            emit(event="rssi", device=msg.body[0], rssi=rssi)
        device = LINKS.added(msg.body[0], msg.body[1])
    elif msg.member == "InterfacesRemoved":
        device = LINKS.removed(msg.body[0], msg.body[1])
    if device is not None:
        LINKS.emit(device)


async def add_matches(bus, rules):
    for rule in rules:
        await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                               interface="org.freedesktop.DBus", member="AddMatch",
                               signature="s", body=[rule]))


async def load_gateways(bus):
    reply = await bus.call(Message(destination=TELEPHONY, path=TELEPHONY_PATH,
                                   interface="org.freedesktop.DBus.ObjectManager",
                                   member="GetManagedObjects"))
    # Not running (an error reply): NameOwnerChanged says when it is.
    if reply.message_type != MessageType.METHOD_RETURN:
        return
    for path, interfaces in reply.body[0].items():
        device = LINKS.gateway_added(path, interfaces)
        if device is not None:
            LINKS.emit(device)


def on_session_signal(bus, msg):
    if msg.message_type != MessageType.SIGNAL:
        return
    devices = []
    if msg.member == "NameOwnerChanged" and msg.body[0] == TELEPHONY:
        # A new owner (WirePlumber restarted) starts with no objects of the
        # old one, so both cases drop them all first.
        devices = LINKS.gateways_gone()
        if msg.body[2]:
            task = asyncio.ensure_future(load_gateways(bus))
            TASKS.add(task)
            task.add_done_callback(TASKS.discard)
    elif not msg.path or not msg.path.startswith(TELEPHONY_PATH):
        return
    elif msg.member == "InterfacesAdded":
        devices = [LINKS.gateway_added(msg.body[0], msg.body[1])]
    elif msg.member == "InterfacesRemoved":
        devices = [LINKS.gateway_removed(msg.body[0])]
    elif msg.member == "PropertiesChanged" and msg.body[0] == Links.GATEWAY_TRANSPORT:
        devices = [LINKS.gateway_changed(msg.path, msg.body[1])]
    for device in devices:
        if device is not None:
            LINKS.emit(device)


async def follow_telephony(bus):
    """Follows PipeWire's hands-free links on the session bus `bus` into LINKS."""
    bus.add_message_handler(lambda msg: on_session_signal(bus, msg))
    await add_matches(bus, [
        "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',"
        f"member='NameOwnerChanged',arg0='{TELEPHONY}'",
        f"type='signal',sender='{TELEPHONY}',interface='org.freedesktop.DBus.ObjectManager'",
        f"type='signal',sender='{TELEPHONY}',interface='org.freedesktop.DBus.Properties',"
        f"member='PropertiesChanged',arg0='{Links.GATEWAY_TRANSPORT}'",
    ])
    # After the match rules, so a change between the two is not lost.
    await load_gateways(bus)


async def main():
    session = await MessageBus(bus_type=BusType.SESSION).connect()
    await follow_telephony(session)

    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    agent = Agent()
    bus.export(PATH, agent)
    introspection = await bus.introspect("org.bluez", "/org/bluez")
    manager = bus.get_proxy_object("org.bluez", "/org/bluez", introspection).get_interface(
        "org.bluez.AgentManager1")
    await manager.call_register_agent(PATH, CAPABILITY)
    await manager.call_request_default_agent(PATH)

    bus.add_message_handler(on_signal)
    rules = ["type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager'"]
    for interface in (Links.DEVICE, Links.TRANSPORT, Links.CONTROL, Links.NETWORK):
        rules.append("type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',"
                     f"member='PropertiesChanged',arg0='{interface}'")
    await add_matches(bus, rules)
    # After the match rules, so a change between the two is not lost.
    reply = await bus.call(Message(destination="org.bluez", path="/",
                                   interface="org.freedesktop.DBus.ObjectManager",
                                   member="GetManagedObjects"))
    devices = []
    for path, interfaces in reply.body[0].items():
        if Links.DEVICE in interfaces:
            devices.append(path)
        LINKS.added(path, interfaces)
    for device in devices:
        LINKS.emit(device)
    emit(event="ready", capability=CAPABILITY)

    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    while line := await reader.readline():
        try:
            agent.answer(json.loads(line))
        except (ValueError, AttributeError):
            emit(event="bad-input", line=line.decode(errors="replace").strip())
    try:
        await manager.call_unregister_agent(PATH)
    except DBusError:
        pass
    emit(event="exit")


if __name__ == "__main__":
    asyncio.run(main())
