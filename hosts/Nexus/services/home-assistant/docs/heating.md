# Heating

Which piece of the heating control lives where, and what each entity really means. Setpoints and room names are house data and stay in HA; this file describes the mechanism only.

Written 2026-11-13. The live pieces were last seen between 2026-11-08 and 2026-11-13.

## The pieces

| Piece | Where | What it is |
|-------|-------|------------|
| Radiator valves | Zigbee, Sonoff TRVZB | One per heated room. Each regulates on a room sensor's reading, fed by the sync blueprint in [blueprints.md](blueprints.md). |
| `switch.boiler_switch` | Zigbee relay | The call for heat to the boiler. It is not "burner firing". |
| `binary_sensor.boiler_calling_for_heat` | `../default.nix` | A trigger-based template sensor that follows the relay. |
| `input_number.boiler_flow_temperature` | UI helper | A note of where the boiler's dial is set. |
| Scenes | UI | Named sets of room setpoints. |
| Schedules | UI, Scheduler integration | Run a scene at a time of day. They appear as `switch.schedule_*`. |
| Self-test | UI scripts and helpers | A test run of the valves, on its own dashboard tab. |

## What to know before changing anything

- **HA cannot read or set the boiler's flow temperature.** `input_number.boiler_flow_temperature` records the physical dial and nothing else. Changing the helper changes no heat, so never propose it as a fix. A UI automation tells the phones when the dial should be turned for the weather, and its "done" action updates the helper.
- **Why `boiler_calling_for_heat` exists.** The relay goes `unavailable` for about 40 seconds on every HA restart, which would split one boiler run into two on a timeline. A trigger-based sensor only moves on a real on or off and restores its state across restarts.
- **Editing a scene does not move the valves.** A saved scene applies the next time it runs. To change what the house is doing now, set the valves as well.
- **Scene tiles carry hand-typed copies of the setpoints.** Each scene tile on the climate dashboard has a typed subtitle, and an "active scene" highlight that compares the valves with hardcoded setpoints. After editing a scene, update that tile's subtitle and its highlight values.
- **Some rooms have a minimum setpoint for damp reasons.** Ask before lowering any room's setpoint in a night or away scene.
- **A schedule fires whatever the self-test is doing.** The self-test's lock only greys out dashboard buttons.
- **The schedule wins the next morning.** A scene pressed by hand lasts until the next scheduled scene.

## TRVZB behaviour

Firmware 1.4.4 through Zigbee2MQTT 2.14.3. The external temperature source and its 2 hour fallback are in [blueprints.md](blueprints.md).

- `temperature_accuracy` is the valve's hysteresis: it opens once the room is that far below the setpoint. Valid values run from -1 to -0.2 in steps of 0.2. HA accepts a value in between without an error, but the valve does not.
- `hvac_action` follows a setpoint change within seconds.
- A TRV that is switched off reports the frost setpoint while keeping its real one.
- `hvac_action` is deliberately kept in the metrics export; the comment on `ignore_attributes` in `../default.nix` says why.
- Each write to a TRV wakes a battery device. Do not poll or rewrite settings on a timer without a reason.

## When a room is not heating as expected

1. Compare the TRV's `current_temperature` with the room sensor. If they differ, the TRV is on its own sensor; see "Things to know when debugging" in [blueprints.md](blueprints.md).
2. Check whether the Zigbee mesh is alive; see [zigbee-watchdog.md](zigbee-watchdog.md). The boiler relay is a Zigbee device, so a dead mesh means no call for heat can change.
3. Check which scene last ran and whether a schedule has overridden it.
