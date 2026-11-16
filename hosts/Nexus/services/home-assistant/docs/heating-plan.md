# Heating plan

How the radiator valves are driven day to day: one timeline for the time of day, a handful of temperature levels, and who is home. Built 2026-11-14, all in HA, replacing the scene-per-time-of-day schedules. The boiler, valves and sync blueprint underneath are in [heating.md](heating.md).

Times of day, setpoints, room names and people are house data. They live in HA and are not written here; this file describes the mechanism and the reasons for it.

## Current state

| Piece | What it is |
|-------|------------|
| `input_select.heating_period` | The period of the day: Night, Breakfast, Work, Lunch, Dinner, Bedtime. |
| `switch.schedule_heating_plan` | One Scheduler timeline, every day, whose blocks set the period. Change the morning with the breakfast helpers below; change the other blocks in the Scheduler card's editor, by dragging block edges or typing start and end times. A Breakfast edge dragged by hand is overwritten the next time a breakfast helper changes. |
| `input_number.heating_level_*` | Five temperature levels: `floor`, `base`, `comfy`, `office`, `bedtime`. |
| `input_number.heating_min_bedroom_2`, `input_number.heating_min_wc` | The mould minimums of the two rooms the plan does not vary, held all day, home or away. Shown on the dashboard as "B2 min" and "WC min". |
| `input_boolean.heating_plan` | On: the plan drives the valves. Off: every valve is switched off. This is the summer and long-trip switch. |
| `input_number.heating_breakfast_time`, `input_number.heating_breakfast_warm_up` | Breakfast time (a slider in hours, 03:00–09:00 in 15-minute steps) and the warm-up before it (0.5–4 h). They move the morning of the timeline; see below. |
| `automation.heating_plan_breakfast` | 10 s after either breakfast helper changes, it rewrites the timeline up to the first Work block with `scheduler.edit`. Breakfast runs from breakfast minus warm-up for one hour; any gap until 08:00 is Night; every block from Work on is kept as set in the timeline. |
| `input_boolean.heating_tv_watching` | The TV modifier's flag. `automation.heating_plan` sets it once the TV and the Shield have both been on for 2 min, and clears it once either has been off for 10 min. It also clears a stale flag on HA start and at midnight. |
| `automation.heating_plan` | Maps period, levels, presence and the TV flag to one setpoint per valve. |
| Dashboard | The Climate dashboard's "Heat & air" section, in this order: the on/off toggle, the plan card, the breakfast slider and warm-up buttons, the five level buttons, and the two mould minimum buttons. |

**The plan card is a `button-card`, not the Scheduler card.** On a dashboard, the Scheduler card only draws a list row; its timeline exists only inside its editor. The plan card is one JavaScript template, the `bar` custom field (the name is left from the timeline bar it replaced). It has two parts:
- **A grid of periods by rooms.** Rows run in the order of the day, Breakfast first and Night last. Columns are the four planned rooms and the two mould minimum rooms; the two bedrooms are headed B1 (main) and B2. Each cell shows the temperature the plan gives that room in that period under the current presence and TV state, and the level it comes from, or "min" for a mould minimum. Warmer cells are tinted stronger. The current period's row is selected and says when it ends. The Breakfast row says when its block starts, which is what the breakfast helpers set. An arrow marks a cell a modifier raised, in that modifier's colour.
- **One pill per modifier under the grid**, one per line: the first person (the work room only follows its level while they are home), the second person, and the TV.

A pill has three states:

| State | Looks like | Means |
|-------|------------|-------|
| On | Filled | The modifier is changing a setpoint now. |
| Armed | Outlined | It can apply later today. The pill says what it waits for. |
| Off | Dim | It cannot apply as things stand: the person is away, nobody is home, or the plan is off. |

Things to know about the card:
- **The grid shows what the plan computes, not what the valves report.** A valve changed by hand does not show here; the Radiators list beside it does.
- **It repeats the automation's rules.** The template's `resolve` function is a copy of the automation's `targets` logic. It does not apply the automation's 20 min away delay, so for 20 min after someone leaves the card can show a modifier as off while the valves still have it.
- **Block times are not on the dashboard any more**, apart from the Breakfast start and the end of the current period. They are in the Scheduler editor: tapping the card opens a Bubble Card pop-up (`#heating-plan-times`) that holds the Scheduler card.
- It reads `timeslots` and `actions` from `switch.schedule_heating_plan` for those two times, and uses `triggers_update: all`, because button-card has no timer.
- The pattern is in the Nocturne design system as the PlanMatrix component.

**Rooms in three groups.**
- A work room that follows the `office` level during Work and Lunch, and only while the person it belongs to is home.
- A living area of two rooms (where meals are eaten and cooked) that follows `base`, `comfy` or `floor` through the day.
- The main bedroom follows `floor`, except in the Bedtime period, when it gets the `bedtime` level.
- The damp-prone bedroom and the WC are held at their mould minimums, whatever the period and whoever is home. Each minimum is a helper.

**Modifiers on top of the timeline.**
- **Presence.** One person is the base plan. The other person being home raises the living area from `base` to `comfy` during Work. Both away means `floor` everywhere, apart from the fixed mould minimums. A person counts as away only after 20 min, because a phone's GPS reports away for a minute at a time.
  - **Presence comes from Wi-Fi, not GPS.** Since 2026-11-16 each person entity has one tracker, the UniFi client tracker for that person's phone. HA is reachable from the LAN and the tailnet only, so a phone that leaves without Tailscale on cannot report its location: on 2026-11-16 the app's last report was from just inside the home zone, and the person stayed `home` for over an hour. The app's GPS tracker was removed from the person rather than kept beside the Wi-Fi one, because a person with both uses the GPS state whenever the Wi-Fi tracker is not `home`, and a stale GPS `home` would win. A UniFi tracker follows one MAC address, the phone's private address for the home network. If a phone ever gets a new private address, its person stays away until the tracker for the new address is enabled and set on the person.
- **TV.** From 20:00 to midnight, with someone home, while the TV and the Shield are both on, the living room is held at `comfy` or above, whatever the period. Only the living room changes. The modifier ends 10 min after either device goes off, or at midnight. A period change while it is active keeps it, because the plan recomputes with the modifier included.

**The room-to-level table lives in two places:** the automation's `targets` variable and the plan card's `resolve` function. Change both together.

## Why it is built this way

- **One timeline, not one schedule per scene.** The Scheduler card (4.0.19) shows a schedule whose blocks each set an `input_select` option as a single draggable timeline. This was spiked on 2026-11-14 with a throwaway helper before the build. Blocks under about 2 h show an icon instead of their name at desktop width.
- **Levels instead of scenes.** A card cannot read the setpoints a scene would apply; a scene's state exposes only its entity list. So a table built from scenes would have been hand-typed and would go stale. Levels are helpers, so the dashboard table and the automation read the same numbers.
- **No setpoint above what a room reaches.** A valve that never reaches its setpoint keeps the boiler running for hours. The living area tops out around 18 °C at the usual flow temperature. A setpoint of 19 there kept the boiler on all afternoon on 2026-11-14. The owners put `comfy` back to 19 all the same, because 18 was too low for comfort; the longer boiler run is accepted. Do not lower it again to save boiler time.
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
- **The TV flag is reconciled on HA start and at midnight.** If the flag is on while the TV and the Shield are not both on, the automation clears it. The stop trigger alone is not enough: it is a template trigger with a 10 min `for`, so a restart inside those 10 min loses the timer, and after the restart the template is already true and never fires. Midnight only ends the modifier through the hour check, so a stuck flag would switch the modifier on again at 20:00 every evening. A restart while the household is watching clears the flag too, when the media players have not reported yet; the watching trigger sets it again 2 min later.
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
- Delete the backup dashboards `backup-20261116-climate` and `backup-20261116-climate-2`, taken before each of the two redesigns of the plan card on 2026-11-16, once the owner has signed the card off.
- The plan card has only been seen in the dark theme at desktop width, in the Lunch period with one person home (2026-11-16). The light theme, phone width, the TV pill when on and the plan-off state are not verified.
- The stale-flag check on HA start is not verified (2026-11-15). The same branch was tested through a temporary time trigger carrying the midnight id; a restart with the flag on has not been tried.

## Changelog

| Date | Change |
|------|--------|
| 2026-11-14 | Built: period helper, Scheduler timeline, five levels, plan switch, automation, dashboard card. Old Morning and Night schedules disabled; scene tiles removed from the dashboard. First applied in the Dinner period and checked against every valve. |
| 2026-11-14 | Floor level 16 → 16.5, and `temperature_accuracy` −1 → −0.6 on every valve. With −1 a valve only opened 1 °C below setpoint, so a 16 floor let rooms drift to 15. Now a floor room holds about 15.9–16.5. A 17 floor was rejected: on near-0 °C nights the living area cannot hold 17, which keeps the boiler running all night. |
| 2026-11-14 | Added the breakfast time slider and warm-up buttons, and `automation.heating_plan_breakfast`, which moves the morning of the timeline to match. The old Morning, Night and first-floor dehumidifier schedules were deleted by hand. |
| 2026-11-14 | Added the TV modifier: `input_boolean.heating_tv_watching`, plus triggers in `automation.heating_plan` for watching starting and stopping, 20:00 and midnight. While it is active the living room is held at comfy or above. The timeline bar and the table card describe it. |
| 2026-11-14 | Tested the TV modifier. The test exposed a race between queued runs: fixed by waiting for each valve to confirm its write. The timeline bar shows the TV window and state. The separate Schedules section was removed from the dashboard; the Scheduler card lives only in the timeline's pop-up. |
| 2026-11-15 | First real evening of the TV modifier: it switched on at 20:04. The TV went off at 20:54 and HA restarted at 21:02, inside the 10 min stop delay, so the flag stayed on and the living room was held at comfy into the Night period. Added a branch to `automation.heating_plan` that clears a stale flag on HA start and at midnight, with ids on those two triggers. Tested with a temporary time trigger: flag set by hand, cleared when the trigger fired, living room back to the floor. |
| 2026-11-15 | Recorded that the owners set `comfy` back to 19: 18 was too low. Seen live on 2026-11-15, when the TV modifier held the living room at 19. |
| 2026-11-16 | Redrew the timeline bar: modifier chips with three states, a strip per modifier, room tiles with an arrow on raised rooms. The grey status lines and the breakfast line are gone; the breakfast slider and warm-up cards below already show those. The level table is unchanged. |
| 2026-11-16 | Both people's presence now comes from their phone's UniFi client tracker alone; the app's GPS tracker was removed from each person. The second person's UniFi tracker was enabled for this, and was seen to read away while the phone was out. The first person already had a UniFi tracker beside the GPS one. Not verified (2026-11-16): that the second person reads home again when the phone returns. |
| 2026-11-16 | The two mould minimums moved out of the automation into `input_number.heating_min_bedroom_2` and `input_number.heating_min_wc`, with a button each on the dashboard. The automation reads them and re-runs when one changes. Tested by raising one by 0.5 and back: the valve followed both times. |
| 2026-11-16 | Replaced the timeline bar and the markdown level table with one plan card: a grid of periods by rooms with the current row selected, and a pill each for the two people and the TV. The 24 h strip, the room tiles and the table are gone. |
