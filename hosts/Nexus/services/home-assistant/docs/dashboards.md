# Dashboards, cards and charts

Conventions the owner has asked for, and frontend behaviour that cost time to find. The dashboards themselves are only in HA; see [live-config.md](live-config.md) for how to read and change them. The floorplan card has its own notes in [../cards/README.md](../cards/README.md).

Most of this was learned between 2026-10-14 and 2026-11-10 and was not re-tested when this file was written on 2026-11-13. Card behaviour depends on the card's version, so treat a quirk as a lead, not a fact.

## Conventions

These are the owner's stated preferences.

- **Mobile first.** Controls a person acts on go at the top; explanatory text and guides go at the bottom. On a phone, sections render in config order, so ordering the list does most of the work.
- **Short card text.** On a mushroom card: one line for the state, one or two for the subtitle.
- **Propose a redesign before building it.** Show the layout options as an artifact with previews and wait for a choice before touching the live dashboard.
- **Room views use one card order:** temperature, power, batteries, door, lights, then the remaining controls.
- **Automations appear as cards.** Each dashboard shows the automations that belong to it under an "Automations" sub-heading on its first tab, not on a settings tab. The card is a mushroom template card with a robot icon, green when the automation is on and grey when off. Tap toggles it; hold opens its details.
- **Colour carries state the same way everywhere:** green for fine, orange for a warning, red for action needed, cyan for water or cold, yellow for a light that is on.
- **A dashboard tab prefers an icon to a name** where a fitting icon exists.
- **Notifying automations** go to both phones, stay silent from 22:00 to 07:00 with a catch-up check at 07:00, and clear their notification when the condition ends. The owner prefers them as UI automations, made through the browser, over YAML in this repo.

## Layout

- **Sections grid.** `grid_options.columns` is counted against 12 times the section's `column_span`, not against 12. In a section two columns wide, `columns: 12` is half width. The viewport can cap the span below the configured value, so measure the real grid (`gridTemplateColumns`) when a card lands at the wrong width. Use `columns: "full"` for a full-width card.
- **URLs.** A dashboard's title can change while its `url_path` stays. Giving a view a `path`, or renaming one, changes that view's URL, and links to the old one stop working.
- **Hidden panels still work.** A panel hidden from the sidebar is still reachable at its URL.

## Cards

- **Mushroom template card colour.** It reads `icon_color`. A `color:` key is ignored without an error.
- **A blank mushroom template card has a Jinja error.** It shows a grey default icon and logs nothing in the console. Subscribe to `render_template` with `report_errors: true` to see the message.
- **Building a template in JavaScript.** Pass a function to `.replace()`. A replacement string containing `$'` is expanded by JavaScript and corrupts the template.
- **Check that an icon exists** in `/static/mdi/iconList.json` before using an `mdi:` name.
- **Card visibility by template.** A card with a `condition: template` visibility rule was hidden unconditionally. Use `state` or `numeric_state` conditions, or a template binary sensor with a state condition. Seen on HA 2026.8.3; not re-tested on later versions.
- **Scheduler card.** It needs the Scheduler integration's config entry, which is added in the UI; without it the card reports that it cannot reach the component. It only lists schedules for the entity domains its config includes, so a schedule for a new kind of entity is invisible until that domain is added. Its "on workdays" option needs a workday sensor, which this HA does not have, so tick the days.
- **Camera cards.** Where a camera's live stream fails in HA but its snapshots load, show a refreshing snapshot. The cause was not investigated.

## Charts

**Which card can read what:**

| Card | Reads |
|------|-------|
| `mini-graph-card` | Recent raw history only. It cannot show long-term or imported statistics. |
| Built-in statistics graph | Long-term statistics. It cannot draw a shaded band. |
| `apexcharts-card` | Raw history, long-term statistics (`statistics:` on a series), or anything a `data_generator` returns. |

Raw history covers 30 days (see [metrics.md](metrics.md)). To chart data that is not in HA's history, such as a VictoriaMetrics query or a computed series, have a job write it into a sensor's attributes and read those with `data_generator`. The fuel-price sensors in `../default.nix` do this.

**`apexcharts-card` quirks:**

- A `data_generator` already receives `entity`, `start`, `end`, `hass` and `moment`. Declaring a variable named `start` or `end` inside it is a syntax error and the card stays on "Loading".
- The x axis is time only. Bars for named categories were done by giving each category its own one-hour slot and formatting the label.
- `group_by` put monthly bars in the wrong months and repeated the last value. Aggregate in `data_generator`.
- A denser series on the same chart shrinks the bars to a pixel. Bring every series to the same interval.
- A shaded band is `apex_config.annotations.yaxis` with `y`, `y2`, `fillColor` and `opacity`. An area series tints the band, so use `type: line`. `color_threshold` had no effect.
- A second series with `show: { in_chart: false, in_header: true }` gives a live value in the header when the statistics are empty.

**Statistics:**

- Back-fill history with the websocket command `recorder/import_statistics`. Write one row per day and carry the last value forward, or the chart shows isolated dots. The frontend needs a reload before the import shows.
- For a sensor that is 0 or 1 "today" and resets at midnight, use the daily mean, not the daily maximum. Yesterday's 1 still counts in the first hour of the next day, so a maximum marks the following day as well.

## Theme and UIX

- `ha-switch` reads the `ha-switch-*` theme variables. The older `switch-checked-*` ones are ignored.
- Before blaming the theme after a deploy, check that `customElements.get('uix-node')` is defined, and hard refresh.
- `uix-fonts` works without `uix-theme`, which can hide a missing `uix-theme`.

## Remotes

- The media box has two integrations on purpose: `androidtv` (ADB) and `androidtv_remote`. Launching an app by package name through `androidtv_remote` (`remote.turn_on` with `activity`) does nothing and logs no error. Call `media_player.select_source` on the ADB entity with the package name as the source. List installed packages with `androidtv.adb_command` and `pm list packages -3`.
- The TV's media player entity is `unavailable` whenever the TV is off. That is its normal off state, not a network fault.
- Wake-on-LAN does not reach the TV. To turn it on, wake the media box and let HDMI-CEC switch the TV on, which takes about 25 seconds.
