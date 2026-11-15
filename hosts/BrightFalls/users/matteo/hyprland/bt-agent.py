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


def on_signal(msg):
    if msg.message_type != MessageType.SIGNAL:
        return
    if msg.member == "PropertiesChanged" and msg.body[0] == "org.bluez.Device1":
        rssi = rssi_of(msg.body[1])
        if rssi is not None:
            emit(event="rssi", device=msg.path, rssi=rssi)
    elif msg.member == "InterfacesAdded":
        rssi = rssi_of(msg.body[1].get("org.bluez.Device1", {}))
        if rssi is not None:
            emit(event="rssi", device=msg.body[0], rssi=rssi)


async def main():
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    agent = Agent()
    bus.export(PATH, agent)
    introspection = await bus.introspect("org.bluez", "/org/bluez")
    manager = bus.get_proxy_object("org.bluez", "/org/bluez", introspection).get_interface(
        "org.bluez.AgentManager1")
    await manager.call_register_agent(PATH, CAPABILITY)
    await manager.call_request_default_agent(PATH)

    bus.add_message_handler(on_signal)
    for rule in ("type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',"
                 "member='PropertiesChanged',arg0='org.bluez.Device1'",
                 "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager',"
                 "member='InterfacesAdded'"):
        await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                               interface="org.freedesktop.DBus", member="AddMatch",
                               signature="s", body=[rule]))
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


asyncio.run(main())
