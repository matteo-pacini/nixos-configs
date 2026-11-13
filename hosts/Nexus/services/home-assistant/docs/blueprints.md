# Blueprints

The automation blueprints this HA uses, the automations built from them, and the device behaviour they rely on. The blueprints are in git; the automations built from them are only in HA. Keep this file current: see "State docs" in [../AGENTS.md](../AGENTS.md).

## How they reach HA

- Blueprint files live in `../blueprints/automation/` and are listed under `blueprints.automation` in `../default.nix`. The module symlinks each one into `/var/lib/hass/blueprints/automation/`, flat, so the path an automation stores is just the file name.
- A blueprint only supplies the template. Each automation built from one is created in the UI and stored in `automations.yaml` with a `use_blueprint` block: the path and that instance's inputs.
- A blueprint change needs a commit and a deploy. The deploy restarts HA, which reloads every automation built from it. Changing an instance's inputs is a live edit and needs neither.
- A new blueprint file must be added to `blueprints.automation`, and `git add`ed before a build.

## Current state

As of 2026-11-13. Every custom blueprint HA lists comes from this repo. None has a `source_url`, and no automation points at a blueprint that is missing.

| Blueprint | Automations | Purpose |
|-----------|-------------|---------|
| `sonoff_trvzb_external_temp_sync.yaml` | 6, one per radiator valve | Feeds a room temperature sensor's value to a Sonoff TRVZB. |
| `socket-auto-recover.yaml` | 2 | Turns a smart socket back on when it switches itself off unattended. |
| `door_warning_blueprint.yaml` | 2 | Repeats a phone notification while a door stays open. |

HA also lists four blueprints of its own under `homeassistant/` (`motion_light`, `notify_leaving_zone`, `confirmable_notification`, `inverted_binary_sensor`). They ship with HA, nothing uses them, and HA recreates them, so they stay out of this repo.

### `sonoff_trvzb_external_temp_sync.yaml`

Six automations, one per radiator valve, named `automation.sonoff_trvzb_external_temperature_sensor_sync_<room>`. Each takes that room's temperature sensor and its radiator valve device, and leaves the other inputs at their defaults (`retain` off).

What it does:

- Triggers on a change of the room sensor's value, and every 30 minutes.
- Publishes `{"external_temperature_input": <value>}` to `zigbee2mqtt/<TRV friendly name>/set`.
- Skips the publish when the room sensor has not reported for 2 hours (`last_reported`).
- Publishes `{"temperature_sensor_select": "remote_temperature"}` first, but only when the TRV's select entity is on neither `remote_temperature` nor `remote_source_offline`.

Device behaviour it relies on (TRVZB firmware 1.4.4, Zigbee2MQTT 2.14.3):

- `temperature_sensor_select` takes `local_temperature`, `remote_temperature` or `remote_source_offline`. Zigbee2MQTT rejects any other value, such as the older `external`, before it reaches the radio.
- The TRV switches itself to `remote_source_offline` exactly 120 minutes after the last external value and regulates on its own sensor, which sits next to the radiator and reads high. Measured from 14 days of history on 2026-11-13.
- It returns to `remote_temperature` by itself on the next external value. No select write is needed.
- The room sensors report at least every 55 minutes, changed or not (4 days of journal, 2026-11-13). That is what makes the 2 hour `last_reported` limit safe.

Why each part is there:

- **30 minute resend.** A steady room produces no sensor change, so the TRV would fall back after 2 hours. The nightly 03:00 restart of Zigbee2MQTT and HA (`hosts/Nexus/services/backup.nix`) has the same effect: the sensor returns from `unavailable`, which the state trigger ignores.
- **2 hour `last_reported` limit.** Without it, a dead room sensor's last value would be resent until HA marks the sensor unavailable, which takes 25 hours for a battery device. With it, the resend stops after 2 hours and the TRV falls back 2 hours later.
- **Conditional select write.** Each write wakes a battery device. Sending it on every run would double the traffic for nothing.

Things to know when debugging:

- A TRV whose `current_temperature` differs from its room sensor is on its own sensor, whatever its select entity says. After a mesh outage the fallback report can be lost and the select stays stale at `remote_temperature`.
- Publishing the room value to the TRV's `/set` topic by hand brings it back within seconds.
- Keep `retain` off. A retained `/set` message is replayed to the TRV at every Zigbee2MQTT start.

Not verified (2026-11-13):

- That `last_reported` advances when the sensor reports an unchanged value. This is documented HA behaviour, not observed here.
- The dead-sensor path as a whole.
- Five fallbacks in the 14 day history came sooner than 2 hours after the last sensor change: 1, 12, 40, 46 and 75 minutes, on two of the valves. Cause unknown.

### `socket-auto-recover.yaml`

Turns a socket back on when it switches off with no user and no automation behind it. Written for the Tuya TS011F plugs, which sometimes drop their relay on their own. The blueprint's own description holds the rule that matters: do not add a socket that something else legitimately switches, such as the two driven by `generic_hygrostat`.

Two sockets are beyond its reach:

- The socket that powers Nexus, because HA runs on Nexus.
- The socket that powers the network rack. That rack holds the switch whose PoE port feeds the Zigbee coordinator, so with it off there is no Zigbee network to send the "on" over.

Related, and only in HA: the Tuya plugs come back off after a power cut unless their `power_outage_memory` setting is on, and the setting does not always survive the cut. A UI automation re-arms it. Devices that use `power_on_behavior` instead are not covered by that automation. (Not checked live, 2026-11-13.)

### `door_warning_blueprint.yaml`

Sends a repeating notification to both phones while the chosen door sensor stays open. Inputs: the door sensor, how long it must be open first, and the time between repeats.

## How to inspect an instance

From the HA site in the browser (see "Gotchas" in [../AGENTS.md](../AGENTS.md)):

```js
const hass = document.querySelector("home-assistant").hass;
// every blueprint HA knows, with its source
await hass.connection.sendMessagePromise({ type: "blueprint/list", domain: "automation" });
// one instance as stored: use_blueprint.path and use_blueprint.input
const reg = await hass.connection.sendMessagePromise({ type: "config/entity_registry/get", entity_id: "automation.<name>" });
await hass.callApi("GET", "config/automation/config/" + reg.unique_id);
```

The `automation/config` websocket call returns the blueprint already expanded, without `use_blueprint`. Use the REST call above to see the inputs.

## Changelog

| Date | Change |
|------|--------|
| 2026-11-13 | `sonoff_trvzb_external_temp_sync.yaml`: select value `external` replaced by `remote_temperature` and sent only when needed; 30 minute resend added; 2 hour `last_reported` limit added (`6223094`). Before this, Zigbee2MQTT logged about 230 rejected select writes a day and the six TRVs fell back to their own sensor 42 or more times in 14 days. Verified after deploy: all six resent at 16:30 UTC with no Zigbee2MQTT errors. |
| 2026-11-13 | One instance: `retain: true` removed from its inputs and the retained `/set` message cleared from the broker. Live edit. |
| 2026-11-13 | Confirmed that all three custom blueprints are served from this repo and removed the note in `default.nix` about older copies under `matteo-pacini/` (`16babf3`). |
