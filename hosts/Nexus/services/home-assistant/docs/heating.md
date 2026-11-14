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
| Heating plan | UI helpers, a Scheduler timeline and a UI automation | Sets every valve from the time of day and who is home. See [heating-plan.md](heating-plan.md). |
| Scenes | UI | Named sets of room setpoints. Superseded by the heating plan on 2026-11-14, kept until it has run for a few days; their dashboard tiles are gone. |
| Schedules | UI, Scheduler integration | They appear as `switch.schedule_*`. Only the heating plan timeline is left; the old scene schedules were deleted on 2026-11-14. |
| Self-test | UI scripts and helpers | A test run of the valves, on its own dashboard tab. |

## What to know before changing anything

- **HA cannot read or set the boiler's flow temperature.** `input_number.boiler_flow_temperature` records the physical dial and nothing else. Changing the helper changes no heat, so never propose it as a fix. A UI automation tells the phones when the dial should be turned for the weather, and its "done" action updates the helper.
- **Why `boiler_calling_for_heat` exists.** The relay goes `unavailable` for about 40 seconds on every HA restart, which would split one boiler run into two on a timeline. A trigger-based sensor only moves on a real on or off and restores its state across restarts.
- **Editing a scene does not move the valves.** A saved scene applies the next time it runs. To change what the house is doing now, set the valves as well.
- **Some rooms have a minimum setpoint for damp reasons.** Ask before lowering any room's floor in the heating plan.
- **A schedule fires whatever the self-test is doing.** The self-test's lock only greys out dashboard buttons. The heating plan behaves the same way.
- **The plan wins at the next change.** A valve set by hand holds until the next period, presence change or level change.

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
3. Check the heating plan: the current period, who counts as home, and whether a manual change was overwritten at the last period change. See [heating-plan.md](heating-plan.md).

## Venting advice

Built 2026-11-14, all in HA. The Venting section on the climate dashboard tells you when opening windows lowers humidity enough to be worth the heat it costs.

| Piece | Where | What it is |
|-------|-------|------------|
| `sensor.venting_ground_floor`, `_first_floor`, `_bathroom`, `_garage` | UI template helpers | All the logic. The state is `key|card primary|card secondary`. |
| Venting cards | Climate dashboard, first tab, "Heat & air" section under the radiator scenes | Mushroom template cards that split the sensor state. They hold no logic. |
| `input_number.venting_min_temp_ground_floor`, `_first_floor` | UI helpers, default 16 °C, on the Dehumidifier settings tab | The coldest the floor's coldest room may settle at after a purge. |
| `automation.venting_advice_notification` | UI automation | Notifies both phones to open, then to close once that zone's advice leaves its open state, with a 60 min backstop. Covers the ground floor, first floor and bathroom; the garage is display only. |

**The model.** A purge replaces a fraction `f` of the air, at most 0.8. About an hour later:

- the room has cooled by `k·f·(T − T_out)`, with `k` 0.10 when the valves are off and 0.03 when a valve is set to heat;
- the room has lost `b·f` of the vapour difference to outside, with `b` 0.4 because furnishings release some water back.

`f` is capped so the coldest room settles no lower than the floor's minimum temperature. The advice gives no duration. It stays "open" while the sensors still show a gain, and drops out when the gain goes or the coldest room reaches its limit. Room air cools faster than the settled estimate during a purge, so that limit trips early. A floor is told to vent when the settled RH is at least 2 points lower and at least 0.4 g of water leaves per Wh of heat lost (1.5 and 0.35 to stay in that state). There is no mould or wall-condensation check: no surface temperature is measured, and an estimated wall RH was dropped on 2026-11-14. Floor advice names no single room until every room has a sensor; only the bathroom gives room-level advice (window and door), because its steam reaches the first-floor landing. Outside air less than 0.5 hPa drier says "keep closed". Windows are never advised open outside 07:00–19:00, the house rule. In those hours the floors say "vent in the morning", the bathroom says "door shut" after a shower, and the garage never says open. A purge still running at 19:00 gets a close notification, and advice still pending at 07:00 notifies then.

**Bathroom.** A shower shows as bathroom vapour 3 hPa or more above the first-floor mean (1.5 to clear). The advice is window open, door shut, so the steam leaves outside instead of across the landing. The notification for closing the window comes when that clears.

**Garage.** Opening the door is only advised when outside air is at least 0.8 hPa drier, RH is above the dehumidifier target, and the garage would stay at 8 °C or above. Otherwise the card points at the dehumidifier.

**Not verified (2026-11-14).** `k` and `b` are estimates, not measurements. To calibrate them, run one 15-minute purge with the valves off and read the temperature and vapour at +1 h and +3 h: `k = (T0 − T60)/(T0 − T_out)`, `b = (v0 − v60)/(v0 − v_out)`. The notification automation had not fired yet when this was written: its template triggers fire on a change into an open state, and two zones were already open when it was created.
