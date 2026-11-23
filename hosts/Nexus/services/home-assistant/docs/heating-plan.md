# Heating plan

How the radiator valves are driven day to day: one timeline for the time of day, a handful of temperature levels, and who is home. It lives entirely in HA. The boiler, valves and sync blueprint underneath are in [heating.md](heating.md).

Times of day, setpoints, room names and people are house data. They live in HA and are not written here; this file describes the mechanism and the reasons for it.

## Current state

| Piece | What it is |
|-------|------------|
| `input_select.heating_period` | The period of the day: Night, Breakfast, Work, Lunch, Dinner, Bedtime. |
| `switch.schedule_heating_plan` | One Scheduler timeline, every day, whose blocks set the period. Change the morning with the breakfast helpers below; change the other blocks in the Scheduler card's editor, by dragging block edges or typing start and end times. A Breakfast edge dragged by hand is overwritten the next time a breakfast helper changes. |
| `input_number.heating_level_*` | Five temperature levels: `floor`, `base`, `comfy`, `office`, `bedtime`. |
| `input_number.heating_min_bedroom_2`, `input_number.heating_min_wc` | The mould minimums of the two rooms the plan does not vary, held all day, home or away. Shown on the dashboard as "B2 min" and "WC min". |
| `input_boolean.heating_plan` | On: the plan drives the valves. Off: the plan leaves the valves alone, so they keep whatever they were last set to, by the plan or by hand. This is the summer, long-trip and manual-control switch. |
| `script.heating_plan_off_all` | Turns the plan off, then switches every valve off. |
| `input_number.heating_breakfast_time`, `input_number.heating_breakfast_warm_up` | Breakfast time (a slider in hours, 03:00–09:00 in 15-minute steps) and the warm-up before it (0.5–4 h). They move the morning of the timeline; see below. |
| `automation.heating_plan_breakfast` | 10 s after either breakfast helper changes, it rewrites the timeline up to the first Work block with `scheduler.edit`. Breakfast runs from breakfast time minus warm-up until an hour after breakfast time, or until 08:00 if that is later, and never past 10:00. Work starts where Breakfast ends, so no Night block falls between them. Every block from Work on is kept as set in the timeline. |
| `input_boolean.heating_tv_watching` | The TV modifier's flag. `automation.heating_plan` sets it once the TV and the Shield have both been on for 2 min, and clears it once either has been off for 10 min. It also clears a stale flag on HA start and at midnight. |
| `automation.heating_plan` | Maps period, levels, presence and the TV flag to one setpoint per valve. |
| Dashboard | The Climate dashboard's "Heat & air" section, in this order: the on/off toggle (two cards, one shown per state of the switch), the plan card, the breakfast slider and warm-up buttons, the five level buttons, and the two mould minimum buttons. |

**The plan card is a `button-card`, not the Scheduler card.** On a dashboard, the Scheduler card only draws a list row; its timeline exists only inside its editor. The plan card is one JavaScript template, the `bar` custom field. It has two parts:
- **A grid of timeline blocks by rooms.** There is one row per block of the Scheduler timeline, in the order of the day, so a period that occurs twice (Work, before and after Lunch) has two rows. Each row shows its time slot under the period name, read from the timeline. When the day starts and ends in Night, the early block is folded into the last row, which then reads as running past midnight to the first block of the morning. Columns are the four planned rooms and the two mould minimum rooms; the two bedrooms are headed B1 (main) and B2. Each cell shows the temperature the plan gives that room in that period under the current presence and TV state, and the level it comes from, or "min" for a mould minimum. Warmer cells are tinted stronger. The row of the block running now is selected. An arrow marks a cell a modifier raised, in that modifier's colour.
- **One pill per modifier under the grid**, one per line: the first person (the work room only follows its level while they are home), the second person, and the TV.

A pill has three states:

| State | Looks like | Means |
|-------|------------|-------|
| On | Filled | The modifier is changing a setpoint now. |
| Armed | Outlined | It can apply later today. The pill says what it waits for. |
| Off | Dim | It cannot apply as things stand: the person is away, nobody is home, or the plan is off. |

Things to know about the card:
- **The grid shows what the plan computes, not what the valves report.** A valve changed by hand does not show here; the Radiators list beside it does.
- **It repeats the automation's rules.** The template's `resolve` function is a copy of the automation's `targets` logic. It does not apply the automation's 5 min away delay, so for 5 min after someone leaves the card can show a modifier as off while the valves still have it.
- **Times are shown on the card but changed elsewhere.** Tapping the card opens a Bubble Card pop-up (`#heating-plan-times`) that holds the Scheduler card, whose editor is where block times change. The morning is set by the breakfast helpers.
- It reads `timeslots` and `actions` from `switch.schedule_heating_plan` for the rows, and uses `triggers_update: all`, because button-card has no timer.
- The pattern is in the Nocturne design system as the PlanMatrix component.

**Rooms in three groups.**
- A work room that follows the `office` level during Work and Lunch, and only while the person it belongs to is home.
- A living area of two rooms (where meals are eaten and cooked) that follows `base`, `comfy` or `floor` through the day.
- The main bedroom follows `floor`, except in the Bedtime period, when it gets the `bedtime` level.
- The damp-prone bedroom and the WC are held at their mould minimums, whatever the period and whoever is home. Each minimum is a helper.

**Modifiers on top of the timeline.**
- **Presence.** One person is the base plan. The other person being home raises the living area from `base` to `comfy` during Work. Both away means `floor` everywhere, apart from the fixed mould minimums. A person counts as away only 5 min after the person entity leaves `home`. The UniFi integration already waits 300 s after it last saw the phone, so the valves follow about 13 min after someone walks out. The 5 min cover short spells in which the tracker is unavailable. The delay is in two places in `automation.heating_plan`, the `for` of the leaving trigger and the grace period in the two presence variables: change both together.
  - **Presence comes from Wi-Fi, not GPS.** Each person entity has one tracker, the UniFi client tracker for that person's phone. HA is reachable from the LAN and the tailnet only, so a phone that leaves without Tailscale on cannot report its location, and a GPS tracker can stay `home` long after the person has gone. The app's GPS tracker is not set on the person even as a second tracker, because a person with both uses the GPS state whenever the Wi-Fi tracker is not `home`, and a stale GPS `home` would win. A UniFi tracker follows one MAC address, the phone's private address for the home network. If a phone ever gets a new private address, its person stays away until the tracker for the new address is enabled and set on the person.
  - **A UniFi outage reads as everyone away.** When the UniFi integration is down, both trackers go `unavailable` and both people `unknown`, which the plan counts as away: every room drops to `floor` or its mould minimum. If every room is at the floor while people are home, check the UniFi config entry first. The gateway's certificate is self-signed, so the entry must have "Verify SSL certificate" off.
- **TV.** From 20:00 to midnight, with someone home, while the TV and the Shield are both on, the living room is held at `comfy` or above, whatever the period. Only the living room changes. The modifier ends 10 min after either device goes off, or at midnight. A period change while it is active keeps it, because the plan recomputes with the modifier included.

**The room-to-level table lives in two places:** the automation's `targets` variable and the plan card's `resolve` function. Change both together.

## Why it is built this way

- **One timeline, not one schedule per scene.** The Scheduler card shows a schedule whose blocks each set an `input_select` option as a single draggable timeline. Blocks under about 2 h show an icon instead of their name at desktop width.
- **Levels instead of scenes.** A card cannot read the setpoints a scene would apply; a scene's state exposes only its entity list. So a table built from scenes would have to be hand-typed and would go stale. Levels are helpers, so the dashboard table and the automation read the same numbers.
- **`comfy` is above what the living area reaches, on purpose.** A valve that never reaches its setpoint keeps the boiler running for hours, and the living area tops out around 18 °C at the usual flow temperature. `comfy` is set at 19 all the same, because 18 is too low for comfort; the longer boiler run is accepted. Do not lower it to save boiler time.
- **The living area holds `base` between meals instead of dropping to `floor`.** It warms at 0.2–0.4 °C/h, so it cannot get back from the floor in time for a meal. The kitchen warms at about 0.5 °C/h, and the work room and bedrooms at about 1 °C/h.
- **Nights go to the floor.** On a night near 0 °C outside, the radiators at a 60 °C flow cannot hold even 17 °C in the living area, and the boiler runs all night without getting there. The floor plus a morning warm-up is preferred over raising the flow temperature, because the radiators are the limit. On cold mornings the living area therefore reaches about 17 °C by breakfast, not 18.
- **The floor is 16.5, with `temperature_accuracy` −0.6 on every valve.** With −1 a valve only opens 1 °C below setpoint, so rooms drift a degree under the floor. A 17 floor would keep the boiler running all night on cold nights, as above.
- **Breakfast starts about 2 h early, and its start changes with the household's mornings,** sometimes as early as 05:00 or a night trip. Hence a breakfast slider and a warm-up setting, rather than dragging a timeline edge on a phone. An early Breakfast runs on until Work at 08:00, with no Night block between them.
- **The bedtime warm-up is one hour.** It lifts the bedroom about 1 °C, not to the full `bedtime` level.
- **The TV modifier holds the living room rather than warming it.** Evening viewing usually ends between about 21:00 and 22:15, and the Bedtime period would drop the living room in the middle of it. Holding the room at `comfy` from Dinner costs far less than warming it again at 0.2–0.4 °C/h.
- **TV detection uses media players, not plug power.** The LG TV's media player (`on`, else `unavailable`) and the Shield's two media players track viewing to the minute. The Shield's plug power drops to 0 mid-show. The TV alone does not count, because the household only watches through the Shield.

## Behaviour to know

- **Writes.** The automation writes a valve only when its mode or setpoint differs, so battery TRVs are not woken for nothing. After each write it waits up to 30 s for the valve to report the new value. Runs are queued, and without that wait a second run would read the old setpoint, skip its write, and leave the valve on the first run's value.
- **Manual changes.** A valve changed by hand holds until the next period, presence, level or TV change, or the 20:00 and midnight checks.
- **Restart.** The automation re-applies on HA start. The `input_select` restores its state, so the nightly 03:00 restart keeps the current period.
- **The TV flag is reconciled on HA start and at midnight.** If the flag is on while the TV and the Shield are not both on, the automation clears it. The stop trigger alone is not enough: it is a template trigger with a 10 min `for`, so a restart inside those 10 min loses the timer, and after the restart the template is already true and never fires. Midnight only ends the modifier through the hour check, so a stuck flag would switch the modifier on again at 20:00 every evening. A restart while the household is watching clears the flag too, when the media players have not reported yet; the watching trigger sets it again 2 min later.
- **Plan off.** Tapping the toggle while the plan is on opens a Bubble Card pop-up (`#heating-plan-off`) with two choices: leave the radiators as they are (turns the switch off) or turn them all off (`script.heating_plan_off_all`). Turning the switch off anywhere else, such as the entity's own toggle, leaves the valves as they are. While the plan is off, `automation.heating_plan` still keeps the TV flag current but stops before writing any valve, whatever triggered it. Turning the plan on applies the plan at once.
- **Saving `automation.heating_plan` drops a pending away trigger.** If someone is inside the 5 min away delay when the automation is saved, re-run it by hand.
- **Self-test.** The plan fires whatever the self-test is doing.
