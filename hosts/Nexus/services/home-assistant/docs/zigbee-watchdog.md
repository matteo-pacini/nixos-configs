# Zigbee Coordinator Watchdog

A UI automation that notices when the Zigbee coordinator's radio stops and brings it back. It lives only in HA (`automations.yaml`), so this file is its record in git. Keep it current: see "State docs" in [../AGENTS.md](../AGENTS.md).

## The failure it handles

The coordinator is an SLZB-06 (CC2652P, Z-Stack) reached over TCP at `zigbee-coordinator.iot.internal:6638`. Its firmware can stop passing Zigbee traffic while everything around it still looks healthy:

- the TCP connection stays established and the coordinator answers ping;
- the `zigbee2mqtt` process keeps running and stays connected to MQTT;
- `binary_sensor.zigbee2mqtt_bridge_connection_state` and `binary_sensor.zigbee2mqtt_running` stay `on`.

What does change:

- no device message arrives on `zigbee2mqtt/<device>`;
- every send fails in the Zigbee2MQTT journal with `failed with status '(0x11: BUFFER_FULL)'`;
- mains devices go `unavailable` after the 10 minute availability timeout. Battery devices keep looking fine for up to 25 hours.

The freeze can happen at Zigbee2MQTT start (seen after the nightly 03:00 backup restart) or in the middle of a run.

## Current state

As of 2026-11-13.

| | |
|---|---|
| Entity | `automation.zigbee_coordinator_watchdog_2` |
| Automation id | `zigbee_coordinator_watchdog` |
| Enabled | yes, all actions enabled |
| Mode | `single`, `max_exceeded: silent` |
| Trigger | time pattern, every 5 minutes |

**Guards** (all must pass before a run starts):

1. HA has been up for 5 minutes (`sensor.uptime`).
2. `binary_sensor.zigbee2mqtt_bridge_connection_state` has been `on` for 5 minutes. A Zigbee2MQTT restart is not radio silence.
3. `button.switch_port_1_power_cycle` was last pressed more than 1 hour ago. This limits recovery to one attempt per hour. An `unknown` button state passes.

**Steps:**

1. Wait up to 3 minutes for any message on `zigbee2mqtt/+`. A message ends the run: the radio is alive.
2. On silence: create the persistent notification `zigbee_radio_watchdog`, notify both phones, press `button.switch_port_1_power_cycle` (PoE power cycle of the coordinator's switch port).
3. Wait 30 seconds, then up to 3 minutes for `binary_sensor.zigbee_coordinator_iot_internal` (ping) to be `on`. On timeout: notify "manual intervention needed" and stop.
4. Notify "coordinator is back", then call `shell_command.restart_zigbee2mqtt`.
5. Wait 2 minutes, then up to 3 minutes for a message on `zigbee2mqtt/+`.
6. On a message: notify success and dismiss the persistent notification. On silence: notify "manual intervention needed".

A freeze is detected 3 to 8 minutes after it starts. A full recovery takes about 5.5 minutes from there.

**Why it is built this way:**

- `zigbee2mqtt/+` is a single-level wildcard, so it matches device state topics only. `bridge/...` and `<device>/availability` are two levels deep and do not count as traffic.
- Mains plugs with power monitoring publish about once per second across the mesh, so 3 minutes of silence is not normal operation.
- The 2 minute wait in step 5 is there because Zigbee2MQTT republishes cached device states while it starts. Those are not radio traffic and would report a false success. (Cached republish is from memory, not verified, 2026-11-13; the wait is safe either way.)
- The 30 second wait in step 3 is there because the ping sensor can poll slower than the outage lasts, so `on` straight after the press proves nothing.
- The automation polls instead of restarting on every message. A `mode: restart` automation triggered by each message would update `last_triggered` about once per second, and it could not arm itself while the radio is already silent.

**What the repo provides for it** (in `../default.nix`): `shell_command.restart_zigbee2mqtt`, and the polkit rule that lets the `hass` user restart `zigbee2mqtt.service`. Zigbee2MQTT itself is `hosts/Nexus/services/zigbee2mqtt.nix`.

## Known gaps

- **Blind during the cooldown.** Guard 3 blocks the whole run, detection included. A second freeze within an hour of a recovery gives no notification.
- **Failure branches are untested.** Only the success path has run live. The two "manual intervention" notifications have never fired.
- **Which step fixes it is unknown.** The PoE power cycle and the service restart both ran in the one live recovery, so whether either is enough alone is not known.
- **The ping check proves little.** In the live run it passed at the first look and may never have seen the coordinator go down. Harmless: `zigbee2mqtt` retries its start every 60 seconds until the coordinator answers.
- **Root cause of `BUFFER_FULL` is not found.** The watchdog treats the symptom.
- **It cannot fix a coordinator that has no power.** The coordinator is fed by a PoE port on a switch in the network rack, and the rack's own supply runs through a Zigbee smart socket. If that socket is off, the coordinator is off, and nothing can switch the socket back on over Zigbee. The PoE power cycle does not help either.

## The network around it

- **The Zigbee channel is runtime state.** The network runs on channel 25. That is stored in Zigbee2MQTT's data directory and reported in `bridge/info`; `zigbee2mqtt.nix` sets no channel. The 2.4 GHz Wi-Fi plan leaves out the Wi-Fi channel that overlaps it, so do not re-enable that channel or accept an automatic channel plan that does. (The Wi-Fi side lives in the network controller, last seen 2026-10-27.)
- **Everything restarts at 03:00.** The nightly backup (`hosts/Nexus/services/backup.nix`) stops Zigbee2MQTT, Mosquitto and HA, then starts them again. The coordinator has frozen at that start before. Guard 2 keeps the watchdog quiet while the bridge comes back.
- **Zigbee2MQTT retries its start forever**, every 60 seconds (`zigbee2mqtt.nix`), because the coordinator can take minutes to answer after an unclean reboot.
- **The broker has two listeners** (`mosquitto.nix`): localhost with full access and no password, and a LAN one limited to a single topic tree for another host.

## How to inspect it

From the HA site in the browser (see "Gotchas" in [../AGENTS.md](../AGENTS.md)):

```js
const hass = document.querySelector("home-assistant").hass;
// live config
await hass.connection.sendMessagePromise({ type: "automation/config", entity_id: "automation.zigbee_coordinator_watchdog_2" });
// recent runs: script_execution is "finished", "failed_conditions" (a guard) or "failed_single" (already running)
await hass.connection.sendMessagePromise({ type: "trace/list", domain: "automation", item_id: "zigbee_coordinator_watchdog" });
```

`automation.trigger` does not return until the run ends, which can take 9 minutes. Do not await it.

Zigbee2MQTT's own view, from its frontend on Nexus port 8099 (websocket at `/api`): `bridge/info` for the coordinator and channel, `bridge/devices` for the device list, and `<device>/availability` for who is online.

Or over MQTT on Nexus, with no sudo:

```bash
"$(nix build --no-link --print-out-paths nixpkgs#mosquitto)/bin/mosquitto_sub" -h 127.0.0.1 -t 'zigbee2mqtt/#' -v
```

Retained `availability` topics outlive a device rename, so an old name can show `offline` forever. Compare against `bridge/devices` before calling a device offline.

On Nexus, the radio's side of the story:

```bash
journalctl -u zigbee2mqtt --since "-1h" | grep -E "BUFFER_FULL|Failed to ping"
```

## Changelog

| Date | Change |
|------|--------|
| 2026-11-13 | Coordinator froze at 13:47 UTC in the middle of a run and the watchdog did not fire. It triggered on `zigbee2mqtt/bridge/health` and tested for an empty `devices` map, but that map holds counters since Zigbee2MQTT start and never empties after a mid-run freeze. |
| 2026-11-13 | Rewritten to detect radio silence on `zigbee2mqtt/+`, polled every 5 minutes. Added the bridge-online guard. Recovery actions disabled for the first test; detection confirmed against the frozen coordinator. |
| 2026-11-13 | Recovery completed: PoE power cycle, wait for ping, Zigbee2MQTT restart, traffic check, phone notifications at each step, one attempt per hour. First live run recovered the mesh (15:47 to 15:52 UTC, 56 of 56 devices back). |
