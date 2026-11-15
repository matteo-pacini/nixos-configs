"""desk-bt-agent against private D-Bus daemons, with this script playing BlueZ
on the "system" bus and PipeWire's telephony service on the "session" bus.

Usage: test-bt-agent.py <desk-bt-agent> <dbus-daemon> <work dir>

Every device here is invented. BlueZ calls the agent's methods as it would
while pairing; the test answers on the agent's stdin as the panel does, and
checks each JSON line the agent prints and each reply BlueZ gets.
"""

import asyncio
import json
import os
import shutil
import subprocess
import sys
import tempfile

from dbus_fast import Message, MessageType, Variant
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, dbus_method

AGENT, DBUS_DAEMON, WORK = sys.argv[1:4]
# A socket path has a 108-byte limit, which a work directory can pass.
SOCKETS = tempfile.mkdtemp(prefix="bt-")

DEV_A = "/org/bluez/hci0/dev_00_00_5E_00_53_0A"
DEV_B = "/org/bluez/hci0/dev_00_00_5E_00_53_0B"
DEV_C = "/org/bluez/hci0/dev_00_00_5E_00_53_0C"
FD_A = DEV_A + "/fd0"
A2DP_SINK = "0000110b-0000-1000-8000-00805f9b34fb"
TEL = "org.pipewire.Telephony"
TEL_PATH = "/org/pipewire/Telephony"
GATEWAY = "org.pipewire.Telephony.AudioGateway1"
GATEWAY_TRANSPORT = "org.pipewire.Telephony.AudioGatewayTransport1"

failed = False
count = 0


def check(name, expected, actual):
    global failed, count
    count += 1
    if expected == actual:
        print(f"ok   {name}")
    else:
        failed = True
        print(f"FAIL {name}\n     expected {expected!r}\n     actual   {actual!r}")


def start_bus(name):
    conf = os.path.join(WORK, f"{name}.conf")
    with open(conf, "w") as f:
        f.write(f"""<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path={SOCKETS}/{name}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
""")
    proc = subprocess.Popen([DBUS_DAEMON, "--config-file", conf, "--nofork", "--print-address"],
                            stdout=subprocess.PIPE, text=True)
    address = proc.stdout.readline().strip()
    if not address:
        raise SystemExit(f"dbus-daemon for the {name} bus did not start")
    return proc, address


class AgentManager(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.AgentManager1")
        self.calls = []
        self.agent = None

    @dbus_method()
    def RegisterAgent(self, agent: "o", capability: "s"):
        self.calls.append(("RegisterAgent", agent, capability))

    @dbus_method()
    def RequestDefaultAgent(self, agent: "o"):
        self.calls.append(("RequestDefaultAgent", agent))

    @dbus_method()
    def UnregisterAgent(self, agent: "o"):
        self.calls.append(("UnregisterAgent", agent))


class Objects:
    """An ObjectManager at `root` answering from `objects` (path -> interface
    -> property -> Variant), with its signals sent as BlueZ and PipeWire send
    them, from the manager's path."""

    def __init__(self, bus, root, objects):
        self.bus, self.root, self.objects = bus, root, objects
        bus.add_message_handler(self.handle)

    def handle(self, msg):
        if (msg.message_type == MessageType.METHOD_CALL and msg.path == self.root
                and msg.member == "GetManagedObjects"):
            return Message.new_method_return(msg, "a{oa{sa{sv}}}", [self.objects])
        return None

    async def signal(self, path, interface, member, signature, body):
        await self.bus.send(Message.new_signal(path, interface, member, signature, body))

    async def add(self, path, interfaces):
        self.objects.setdefault(path, {}).update(interfaces)
        await self.signal(self.root, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded",
                          "oa{sa{sv}}", [path, interfaces])

    async def remove(self, path, names):
        for name in names:
            self.objects.get(path, {}).pop(name, None)
        await self.signal(self.root, "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved",
                          "oas", [path, names])

    async def change(self, path, interface, props):
        await self.signal(path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                          "sa{sv}as", [interface, props, []])


def device(address, **more):
    props = {"Address": Variant("s", address), "Name": Variant("s", "Test device")}
    props.update(more)
    return {"org.bluez.Device1": props}


def gateway(address, state):
    return {GATEWAY: {"Address": Variant("s", address)},
            GATEWAY_TRANSPORT: {"State": Variant("s", state)}}


async def start_telephony(address, objects):
    bus = await MessageBus(bus_address=address).connect()
    tel = Objects(bus, TEL_PATH, objects)
    await bus.request_name(TEL)
    return bus, tel


class Agent:
    def __init__(self, proc):
        self.proc = proc

    async def event(self):
        line = await asyncio.wait_for(self.proc.stdout.readline(), 10)
        return json.loads(line) if line else None

    def send(self, obj):
        self.proc.stdin.write((obj if isinstance(obj, str) else json.dumps(obj)).encode() + b"\n")


async def main():
    system, system_address = start_bus("system")
    session, session_address = start_bus("session")
    try:
        await run(system_address, session_address)
    finally:
        system.terminate()
        session.terminate()
        shutil.rmtree(SOCKETS, ignore_errors=True)


async def run(system_address, session_address):
    bluez_bus = await MessageBus(bus_address=system_address).connect()
    manager = AgentManager()
    bluez_bus.export("/org/bluez", manager)
    # Lower case on purpose: the agent compares addresses in upper case.
    bluez = Objects(bluez_bus, "/", {
        "/org/bluez": {},
        "/org/bluez/hci0": {"org.bluez.Adapter1": {"Address": Variant("s", "00:00:5E:00:53:00")}},
        DEV_A: {**device("00:00:5e:00:53:0a"),
                "org.bluez.MediaControl1": {"Connected": Variant("b", True)}},
        DEV_B: device("00:00:5E:00:53:0B"),
        FD_A: {"org.bluez.MediaTransport1": {"Device": Variant("o", DEV_A),
                                             "UUID": Variant("s", A2DP_SINK),
                                             "State": Variant("s", "idle")}},
    })
    await bluez_bus.request_name("org.bluez")
    tel_bus, tel = await start_telephony(session_address, {
        TEL_PATH + "/ag0": gateway("00:00:5E:00:53:0A", "idle")})

    env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=system_address,
               DBUS_SESSION_BUS_ADDRESS=session_address)
    proc = await asyncio.create_subprocess_exec(AGENT, stdin=subprocess.PIPE,
                                                stdout=subprocess.PIPE, env=env)
    agent = Agent(proc)

    def links(dev, transports=(), control=False, network=False, calls="none"):
        return {"event": "links", "device": dev, "transports": list(transports),
                "control": control, "network": network, "calls": calls}

    # ---- start ----
    check("start: links of every device, the hands-free link included",
          [links(DEV_A, [{"uuid": A2DP_SINK, "state": "idle"}], control=True, calls="connected"),
           links(DEV_B)],
          sorted([await agent.event(), await agent.event()], key=lambda e: e["device"]))
    check("start: ready", {"event": "ready", "capability": "KeyboardDisplay"}, await agent.event())
    path = manager.calls[0][1] if manager.calls else None
    check("start: registered as the default KeyboardDisplay agent",
          [("RegisterAgent", path, "KeyboardDisplay"), ("RequestDefaultAgent", path)], manager.calls)
    owner = None

    async def call(member, signature, body):
        """BlueZ calling the agent: returns (reply type, body or error name)."""
        reply = await asyncio.wait_for(bluez_bus.call(Message(
            destination=owner, path=path, interface="org.bluez.Agent1", member=member,
            signature=signature, body=body)), 10)
        if reply.message_type == MessageType.ERROR:
            return ("error", reply.error_name)
        return ("return", reply.body)

    # The agent's unique name: the sender of RegisterAgent is the only other
    # connection on the bus that is not ours.
    reply = await bluez_bus.call(Message(destination="org.freedesktop.DBus",
                                         path="/org/freedesktop/DBus",
                                         interface="org.freedesktop.DBus", member="ListNames"))
    others = [n for n in reply.body[0] if n.startswith(":") and n != bluez_bus.unique_name]
    owner = others[0]

    async def ask(member, signature, body, answer):
        task = asyncio.ensure_future(call(member, signature, body))
        request = await agent.event()
        if answer is not None:
            agent.send({"id": request["id"], **answer})
        return request, task

    # ---- pairing ----
    request, task = await ask("RequestConfirmation", "ou", [DEV_B, 1234], {"accept": True})
    check("confirmation: the passkey as six digits",
          {"event": "request", "id": 1, "method": "RequestConfirmation", "device": DEV_B,
           "passkey": "001234"}, request)
    check("confirmation accepted: BlueZ gets a plain return", ("return", []), await task)

    request, task = await ask("RequestConfirmation", "ou", [DEV_B, 999999], {"accept": False})
    check("confirmation refused: Rejected", ("error", "org.bluez.Error.Rejected"), await task)

    request, task = await ask("RequestPasskey", "o", [DEV_B], {"accept": True, "passkey": 987654})
    check("passkey asked", {"event": "request", "id": 3, "method": "RequestPasskey", "device": DEV_B},
          request)
    check("passkey given: returned as a number", ("return", [987654]), await task)

    request, task = await ask("RequestPinCode", "o", [DEV_B], {"accept": True, "pin": "0000"})
    check("PIN given: returned as a string", ("return", ["0000"]), await task)

    request, task = await ask("AuthorizeService", "os", [DEV_B, A2DP_SINK], {"accept": True})
    check("service question carries the UUID",
          {"event": "request", "id": 5, "method": "AuthorizeService", "device": DEV_B,
           "uuid": A2DP_SINK}, request)
    check("service allowed", ("return", []), await task)

    task = asyncio.ensure_future(call("DisplayPasskey", "ouq", [DEV_B, 42, 3]))
    check("passkey to type on the device: no id, padded, keys entered",
          {"event": "request", "id": None, "method": "DisplayPasskey", "device": DEV_B,
           "passkey": "000042", "entered": 3}, await agent.event())
    check("passkey to type: returns at once", ("return", []), await task)

    task = asyncio.ensure_future(call("DisplayPinCode", "os", [DEV_B, "123456"]))
    check("PIN to type on the device",
          {"event": "request", "id": None, "method": "DisplayPinCode", "device": DEV_B,
           "pincode": "123456"}, await agent.event())
    await task

    # BlueZ withdraws an open request: the panel is told, the call refused.
    request, task = await ask("RequestAuthorization", "o", [DEV_B], None)
    check("authorization asked", 6, request["id"])
    check("cancel: the open request withdrawn", ("return", []), await call("Cancel", "", []))
    check("cancel: the panel told which", {"event": "cancel", "ids": [6]}, await agent.event())
    check("cancel: the open call refused", ("error", "org.bluez.Error.Rejected"), await task)

    agent.send({"id": 6, "accept": True})
    check("an answer after the cancel is stale", {"event": "stale-answer", "id": 6}, await agent.event())
    agent.send({"id": 99, "accept": True})
    check("an answer to nothing is stale", {"event": "stale-answer", "id": 99}, await agent.event())
    agent.send("not json")
    check("a line that is not JSON", {"event": "bad-input", "line": "not json"}, await agent.event())
    agent.send("[1, 2]")
    check("JSON that is not an object", {"event": "bad-input", "line": "[1, 2]"}, await agent.event())

    # ---- links and signal strength ----
    await bluez.change(FD_A, "org.bluez.MediaTransport1", {"State": Variant("s", "active")})
    check("transport active",
          links(DEV_A, [{"uuid": A2DP_SINK, "state": "active"}], control=True, calls="connected"),
          await agent.event())
    await bluez.change(DEV_B, "org.bluez.Device1", {"Connected": Variant("b", True)})
    await bluez.change(DEV_B, "org.bluez.Device1", {"RSSI": Variant("n", -42)})
    check("RSSI change (other Device1 changes say nothing)",
          {"event": "rssi", "device": DEV_B, "rssi": -42}, await agent.event())
    await bluez.add(DEV_C, device("00:00:5E:00:53:0C", RSSI=Variant("n", -70)))
    check("a device found while scanning: its RSSI",
          {"event": "rssi", "device": DEV_C, "rssi": -70}, await agent.event())
    await bluez.change(DEV_B, "org.bluez.Network1", {"Connected": Variant("b", True)})
    check("network (PAN) up", links(DEV_B, network=True), await agent.event())
    await bluez.remove(FD_A, ["org.bluez.MediaTransport1"])
    check("transport gone", links(DEV_A, control=True, calls="connected"), await agent.event())
    await bluez.add(DEV_A, {"org.bluez.MediaControl1": {"Connected": Variant("b", False)}})
    check("media control down", links(DEV_A, calls="connected"), await agent.event())

    # ---- calls ----
    await tel.change(TEL_PATH + "/ag0", GATEWAY_TRANSPORT, {"State": Variant("s", "active")})
    check("call audio through this computer", links(DEV_A, calls="active"), await agent.event())
    await tel.add(TEL_PATH + "/ag1", gateway("00:00:5E:00:53:0B", "idle"))
    check("a second hands-free link", links(DEV_B, network=True, calls="connected"),
          await agent.event())
    await tel.remove(TEL_PATH + "/ag1", [GATEWAY, GATEWAY_TRANSPORT])
    check("hands-free link gone", links(DEV_B, network=True), await agent.event())
    # An unrelated object under another path of the telephony service.
    await tel.signal("/org/pipewire/Other", "org.freedesktop.DBus.ObjectManager",
                     "InterfacesAdded", "oa{sa{sv}}",
                     ["/org/pipewire/Other/x", gateway("00:00:5E:00:53:0B", "active")])
    # WirePlumber stops: every call link is gone.
    tel_bus.disconnect()
    await tel_bus.wait_for_disconnect()
    check("telephony service gone: no calls", links(DEV_A, calls="none"), await agent.event())
    # It comes back with the link idle: read again.
    tel_bus, tel = await start_telephony(session_address, {
        TEL_PATH + "/ag5": gateway("00:00:5E:00:53:0A", "idle")})
    check("telephony service back: read again", links(DEV_A, calls="connected"), await agent.event())

    # ---- release and exit ----
    check("release", ("return", []), await call("Release", "", []))
    check("release told", {"event": "released"}, await agent.event())
    proc.stdin.close()
    check("stdin closed: exit", {"event": "exit"}, await agent.event())
    check("stdin closed: process ends with 0", 0, await asyncio.wait_for(proc.wait(), 10))
    check("stdin closed: unregistered", ("UnregisterAgent", path), manager.calls[-1])
    check("nothing else printed", None, await agent.event())


asyncio.run(main())
print(f"{'FAILED' if failed else 'ok'}: {count} checks")
sys.exit(1 if failed else 0)
