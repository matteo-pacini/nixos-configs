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

As of 2026-11-15.

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

1. Wait up to 3 minutes for a fresh message on `zigbee2mqtt/+` (see "Retained messages" below). A message ends the run: the radio is alive.
2. On silence: create the persistent notification `zigbee_radio_watchdog`, notify both phones, press `button.switch_port_1_power_cycle` (PoE power cycle of the coordinator's switch port).
3. Wait 30 seconds, then up to 3 minutes for `binary_sensor.zigbee_coordinator_iot_internal` (ping) to be `on`. On timeout: notify "manual intervention needed" and stop.
4. Notify "coordinator is back", then call `shell_command.restart_zigbee2mqtt`.
5. Wait 2 minutes, then up to 3 minutes for a fresh message on `zigbee2mqtt/+`.
6. On a message: notify success and dismiss the persistent notification. On silence: notify "manual intervention needed".

A freeze is detected 3 to 8 minutes after it starts. A full recovery takes about 5.5 minutes from there.

**Why it is built this way:**

- `zigbee2mqtt/+` is a single-level wildcard, so it matches device state topics only. `bridge/...` and `<device>/availability` are two levels deep and do not count as traffic.
- Mains plugs with power monitoring publish about once per second across the mesh, so 3 minutes of silence is not normal operation.
- The 2 minute wait in step 5 is there because Zigbee2MQTT republishes cached device states while it starts. Those are not radio traffic and would report a false success. (Cached republish is from memory, not verified, 2026-11-13; the wait is safe either way.)
- The 30 second wait in step 3 is there because the ping sensor can poll slower than the outage lasts, so `on` straight after the press proves nothing.
- The automation polls instead of restarting on every message. A `mode: restart` automation triggered by each message would update `last_triggered` about once per second, and it could not arm itself while the radio is already silent.

**Retained messages.** `zigbee2mqtt.nix` sets `device_options.retain = true` and `advanced.last_seen = "ISO_8601"`. Each `wait_for_trigger` is a new subscription, HA's MQTT client replays retained messages to every new subscription, and the MQTT trigger neither filters them nor exposes the retain flag. Unfiltered, both waits would end at once and a frozen radio would never be detected. So both MQTT triggers carry `payload: live` and this `value_template`, which judges freshness from the `last_seen` in the payload:

```jinja
{% set ls = value_json.get('last_seen') if value_json is defined and value_json is mapping else none %}{% set t = as_timestamp(ls, none) if ls is not none else none %}{{ 'live' if t is none or now().timestamp() - t < 60 else 'stale' }}
```

- A `last_seen` older than 60 seconds is `stale` and ignored. Anything else counts as traffic: a fresh `last_seen`, a payload without one, a payload that is not JSON or not an object, and a `last_seen` that is null or does not parse.
- It must not raise. A template error drops that message, which counts as silence, and enough silence power-cycles the coordinator. The simpler `(now() - as_datetime(value_json.last_seen)).total_seconds() < 60` raises on a non-JSON payload (`value_json` is undefined) and on `last_seen: null`.
- It renders `live`/`stale` rather than a boolean so the `payload` match does not depend on how a boolean renders.
- A replayed state whose `last_seen` is under 60 seconds old is accepted. It proves the radio was alive a minute ago, but it means a run that starts within 60 seconds of a freeze can still pass, and detection then comes one run (5 minutes) later.
- In step 5, the 2 minute wait puts every state replayed from before the freeze past the 60 second limit.

**What the repo provides for it** (in `../default.nix`): `shell_command.restart_zigbee2mqtt`, and the polkit rule that lets the `hass` user restart `zigbee2mqtt.service`. Zigbee2MQTT itself is `hosts/Nexus/services/zigbee2mqtt.nix`.

## Known gaps

- **The retained-replay filter is not tested against a frozen radio.** See "Retained messages" above. What was tested on 2026-11-15: the template, through the websocket `render_template` (what Developer tools > Template uses), against sample payloads (fresh, old and missing `last_seen`, null `last_seen`, non-JSON, non-object JSON); live runs before and after the retain deploy, all ending at the silence check with no recovery step; and the live template against the states the broker replays to a new subscription after the deploy (56 replayed, 37 older than 60 seconds rendered `stale`, 19 fresh rendered `live`, no errors). A trace records only the message that ended the wait, so it cannot show the rejected ones.
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
| 2026-11-15 | Zigbee2MQTT set to retain device states and add `last_seen` (repo change). This breaks the silence check until the automation filters on `last_seen`; see Known gaps. |
| 2026-11-15 | Both waits now accept only fresh messages (`last_seen` under 60 seconds old, or no `last_seen`), applied live before the retain change was deployed. Nothing else in the automation changed. Checked after the deploy: the 21:25 UTC run ended on a message 7 seconds old, and replayed states older than 60 seconds render `stale`. |
