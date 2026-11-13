# History, metrics and energy

Where Home Assistant's data goes, how long each store keeps it, and what the energy and cost entities really measure. Written 2026-11-13; live-only facts carry the date they were last seen.

## Three stores

| Store | Holds | Keeps |
|-------|-------|-------|
| Recorder (Postgres, database `hass`) | Raw state history | 30 days (`purge_keep_days` in `../default.nix`) |
| Long-term statistics (same database) | Hourly aggregates, only for entities with a `state_class` | Not purged |
| VictoriaMetrics | Every exported state change | The long-term archive |

A dashboard card that reads HA history cannot show more than 30 days of raw data. Older raw data has to come from VictoriaMetrics.

The recorder database has one operational trap, covered in `docs/nexus/postgres-collation-handbook.md`.

## The export to VictoriaMetrics

HA's `influxdb` integration writes to VictoriaMetrics on the same host (the `influxdb` block in `../default.nix`).

- **Metric names.** `measurement_attr` is `entity_id`, so a sensor's state becomes the metric `<entity_id>_value`.
- **It writes on a state change only.** Series are sparse. A Grafana panel that shows a current value or a state timeline must wrap its selector in `last_over_time(...)`, with a window to suit the entity: about a day for a continuous measurement, longer for one that changes rarely.
- **An entity that has not changed since the export started has no series at all** until its next change or an HA restart. Do not paper over that by setting a panel's "no value" text to a plausible state.
- **List-valued attributes must be ignored.** A sensor that carries chart data in its attributes needs those attribute names added to `ignore_attributes`. They are lists, not samples.
- **Filters mirror the recorder's.** An entity excluded from the recorder is excluded from the export too.

## Querying VictoriaMetrics

- Other hosts reach it through a read-only reverse proxy that allows only the query, series and label endpoints (`caddy.nix`). `/api/v1/export` returns 403 there. Use a range selector on `/api/v1/query`, such as `metric[150d]`.
- On Nexus itself, `/api/v1/export` with `match[]` works against the local port.
- An entity only has data from the day it was created. `binary_sensor.boiler_calling_for_heat` starts on 2026-11-08; for earlier boiler run time use the relay, `switch.boiler_switch`.

## Getting outside data into HA

The pattern in use is a file bridge. A systemd job running as `hass` writes JSON to a state directory, and a `command_line` sensor in `../default.nix` reads the file, exposing the series as attributes. `hosts/Nexus/services/fuel-price/` is the worked example. Values that are specific to the house, such as which stations to track, live in an agenix secret, not in Nix.

These sensors scan every 10 minutes. After a deploy they read `unknown` until the first scan; call `homeassistant.update_entity` to skip the wait.

## Energy and cost

Seen 2026-11-10; these are UI helpers and live preferences, not checked since.

- **The Energy dashboard's "Now" view** draws a device, or the grid, only when its entry in the energy preferences has `stat_rate` pointing at a live power sensor. The UI never sets that field. Set it with `energy/get_prefs` and `energy/save_prefs`, and check it again after adding a device in the UI.
- **The per-device cost helpers are running totals.** Each is the socket's lifetime energy multiplied by the current rate. It is never "today" or "this month", and it resets with the plug. For spend over a period, use long-term statistics: a `statistic` card with `stat_type: change`, or the Energy dashboard.
- **Point new templates at the rate alias.** A helper gives the current electricity rate a stable entity id. The supplier integration's own entity ids contain meter identifiers, which change with the meter and do not belong in this repo.
- **Supplier meter statistics arrive a day or two late.** For a monthly figure, average over the days that have a reading, not over calendar days.
- **The supplier integration can only re-import data for the meters it has now.** History from before a meter was replaced cannot be refreshed, because those entities no longer exist.
- **The whole-house clamp sensor has bad data before 2026-09-28.** Do not use it for earlier periods.
- **The live gas counter resets at midnight and lags by about two hours.** Take hourly differences over a window wide enough to cover the lag.

## UPS

HA reads the UPSes through apcupsd on Nexus (`hosts/Nexus/services/ups.nix`), one `apcupsd` config entry per apcupsd instance, added in the UI. There is no NUT. The inventory is in `docs/nexus/ups-inventory.md`.
