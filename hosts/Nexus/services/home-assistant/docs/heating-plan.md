# Heating plan

How the radiator valves are driven day to day: one timeline for the time of day, a handful of temperature levels, and who is home. Built 2026-11-14, all in HA, replacing the scene-per-time-of-day schedules. The boiler, valves and sync blueprint underneath are in [heating.md](heating.md).

Times of day, setpoints, room names and people are house data. They live in HA and are not written here; this file describes the mechanism and the reasons for it.

## Current state

| Piece | What it is |
|-------|------------|
| `input_select.heating_period` | The period of the day: Night, Breakfast, Work, Lunch, Dinner, Bedtime. |
| `switch.schedule_heating_plan` | One Scheduler timeline, every day, whose blocks set the period. Change the morning with the breakfast helpers below; change the other blocks in the Scheduler card's editor, by dragging block edges or typing start and end times. A Breakfast edge dragged by hand is overwritten the next time a breakfast helper changes. |
| `input_number.heating_level_*` | Five temperature levels: `floor`, `base`, `comfy`, `office`, `bedtime`. |
| `input_boolean.heating_plan` | On: the plan drives the valves. Off: every valve is switched off. This is the summer and long-trip switch. |
| `input_number.heating_breakfast_time`, `input_number.heating_breakfast_warm_up` | Breakfast time (a slider in hours, 03:00–09:00 in 15-minute steps) and the warm-up before it (0.5–4 h). They move the morning of the timeline; see below. |
| `automation.heating_plan_breakfast` | 10 s after either breakfast helper changes, it rewrites the timeline up to the first Work block with `scheduler.edit`. Breakfast runs from breakfast minus warm-up for one hour; any gap until 08:00 is Night; every block from Work on is kept as set in the timeline. |
| `input_boolean.heating_tv_watching` | The TV modifier's flag. `automation.heating_plan` sets it once the TV and the Shield have both been on for 2 min, and clears it once either has been off for 10 min. |
| `automation.heating_plan` | Maps period, levels, presence and the TV flag to one setpoint per valve. |
| Dashboard | The Climate dashboard's "Heat & air" section, in this order: the on/off toggle, the timeline bar, the breakfast slider and warm-up buttons, the level buttons, and a markdown table of which room gets which level. |

**The timeline bar is a `button-card`, not the Scheduler card.** On a dashboard, the Scheduler card only draws a list row; its timeline exists only inside its editor. The bar reads `timeslots` and `actions` from `switch.schedule_heating_plan`, so it always draws the real schedule. It shows:
- a now marker;
- the current period and when it ends;
- each room's live setpoint;
- who is home, and whether the second person's modifier is active;
- the TV modifier: a pink strip under 20:00–00:00, solid while it is active, and a line saying whether it is on, ready or waiting for 20:00;
- the breakfast time, the warm-up, and when heating starts.

The bar uses `triggers_update: all`, because button-card has no timer; that is what moves the now marker. Tapping it opens a Bubble Card pop-up (`#heating-plan-times`) that holds the Scheduler card, whose editor is where times change.

**Rooms in three groups.**
- A work room that follows the `office` level during Work and Lunch, and only while the person it belongs to is home.
- A living area of two rooms (where meals are eaten and cooked) that follows `base`, `comfy` or `floor` through the day.
- The main bedroom follows `floor`, except in the Bedtime period, when it gets the `bedtime` level.
- The damp-prone bedroom and the WC are fixed at their mould minimums in the automation, whatever the period.

**Modifiers on top of the timeline.**
- **Presence.** One person is the base plan. The other person being home raises the living area from `base` to `comfy` during Work. Both away means `floor` everywhere, apart from the fixed mould minimums. A person counts as away only after 20 min, because a phone's GPS reports away for a minute at a time.
- **TV.** From 20:00 to midnight, with someone home, while the TV and the Shield are both on, the living room is held at `comfy` or above, whatever the period. Only the living room changes. The modifier ends 10 min after either device goes off, or at midnight. A period change while it is active keeps it, because the plan recomputes with the modifier included.

**The room-to-level table lives in two places:** the automation's `targets` variable and the dashboard's markdown card. Change both together.

## Why it is built this way

- **One timeline, not one schedule per scene.** The Scheduler card (4.0.19) shows a schedule whose blocks each set an `input_select` option as a single draggable timeline. This was spiked on 2026-11-14 with a throwaway helper before the build. Blocks under about 2 h show an icon instead of their name at desktop width.
- **Levels instead of scenes.** A card cannot read the setpoints a scene would apply; a scene's state exposes only its entity list. So a table built from scenes would have been hand-typed and would go stale. Levels are helpers, so the dashboard table and the automation read the same numbers.
- **No setpoint above what a room reaches.** A valve that never reaches its setpoint keeps the boiler running for hours. The living area tops out around 18 °C at the usual flow temperature. A setpoint of 19 there kept the boiler on all afternoon on 2026-11-14.
- **The living area holds `base` between meals instead of dropping to `floor`.** It warms at 0.2–0.4 °C/h, so it cannot get back from the floor in time for a meal. The kitchen warms at about 0.5 °C/h, and the work room and bedrooms at about 1 °C/h.
- **Nights go to the floor.** On a night near 0 °C outside, the radiators at a 60 °C flow could not hold even 17 °C in the living area. The boiler ran non-stop from 01:00 to 10:00 on 2026-11-14 without getting there. The owners chose the floor plus a morning warm-up over raising the flow temperature, because the radiators are the limit. On cold mornings the living area therefore reaches about 17 °C by breakfast, not 18.
- **Breakfast starts about 2 h early, and its start changes with the household's mornings,** sometimes as early as 05:00 or a night trip. Hence a breakfast slider and a warm-up setting, rather than dragging a timeline edge on a phone. After breakfast the morning goes back to Night until 08:00, so an early breakfast does not keep the living area warm until Work.
- **The bedtime warm-up is one hour.** It lifts the bedroom about 1 °C, not to the full `bedtime` level.
- **The TV modifier holds the living room rather than warming it.** In the three weeks to 14 Nov, evening viewing ran 23–114 min and always ended between 21:11 and 22:09. The Bedtime period dropped the living room in the middle of that. Holding the room at `comfy` from Dinner costs far less than warming it again at 0.2–0.4 °C/h.
- **TV detection uses media players, not plug power.** The LG TV's media player (`on`, else `unavailable`) and the Shield's two media players match the evenings to the minute. The Shield's plug power drops to 0 mid-show. The TV alone does not count, because the household only watches through the Shield.

## Behaviour to know

- **Writes.** The automation writes a valve only when its mode or setpoint differs, so battery TRVs are not woken for nothing. After each write it waits up to 30 s for the valve to report the new value. Runs are queued, and without that wait a second run read the old setpoint, skipped its write, and left the valve on the first run's value (seen 2026-11-14: living room left at Bedtime's level in Dinner).
- **Manual changes.** A valve changed by hand holds until the next period, presence, level or TV change, or the 20:00 and midnight checks.
- **Restart.** The automation re-applies on HA start. The `input_select` restores its state, so the nightly 03:00 restart keeps the current period.
- **Plan off.** Setting the period while the plan switch is off switches the valves off, because that is what "off" means. Turn the plan on first. On the first run, the period was set before the switch was turned on, so every valve went off for a second and then on again.
- **Self-test.** The plan fires whatever the self-test is doing, as the old schedules did.

## Rollback

A full local HA backup, "Before heating plan 2026-11-14", was taken before the build. It is encrypted with the automatic-backup key. The recorder is Postgres, so the backup holds config, not history.

To go back without restoring it:
1. Turn the plan switch off, or disable `automation.heating_plan`.
2. The old Morning and Night schedules were deleted on 2026-11-14 (as was the first-floor dehumidifier schedule), so re-create a scene schedule in the Scheduler card, or restore the backup. The scenes still exist.
3. Restore the scene tiles in "Heat & air" from a backup dashboard.

## Pending

- Delete the scenes, and the backup dashboards `backup-20261114-climate`, `-2` and `-3`, after a few days of the plan running cleanly.
- The TV modifier was tested on 2026-11-14 with the evening window moved to the current hour: 2 min after the TV and Shield came on, the living room went from the floor to comfy in the Bedtime period. It has not yet run on a real evening.

## Changelog

| Date | Change |
|------|--------|
| 2026-11-14 | Built: period helper, Scheduler timeline, five levels, plan switch, automation, dashboard card. Old Morning and Night schedules disabled; scene tiles removed from the dashboard. First applied in the Dinner period and checked against every valve. |
| 2026-11-14 | Floor level 16 → 16.5, and `temperature_accuracy` −1 → −0.6 on every valve. With −1 a valve only opened 1 °C below setpoint, so a 16 floor let rooms drift to 15. Now a floor room holds about 15.9–16.5. A 17 floor was rejected: on near-0 °C nights the living area cannot hold 17, which keeps the boiler running all night. |
| 2026-11-14 | Added the breakfast time slider and warm-up buttons, and `automation.heating_plan_breakfast`, which moves the morning of the timeline to match. The old Morning, Night and first-floor dehumidifier schedules were deleted by hand. |
| 2026-11-14 | Added the TV modifier: `input_boolean.heating_tv_watching`, plus triggers in `automation.heating_plan` for watching starting and stopping, 20:00 and midnight. While it is active the living room is held at comfy or above. The timeline bar and the table card describe it. |
| 2026-11-14 | Tested the TV modifier. The test exposed a race between queued runs: fixed by waiting for each valve to confirm its write. The timeline bar shows the TV window and state. The separate Schedules section was removed from the dashboard; the Scheduler card lives only in the timeline's pop-up. |
