# Agent instructions: Home Assistant (Nexus)

Read this before touching Home Assistant (https://home.matteopacini.me, `services.home-assistant` on Nexus). Half of it lives in this repo; the other half lives only in HA's state directory. Work out which half a change belongs to before you start. Repo-wide rules are in the root `AGENTS.md`.

## Repo or HA

**In this repo, in this directory.** These need a commit and a deploy:
- `default.nix`:
  - Integrations: `extraComponents`, and `customComponents` for anything packaged here.
  - Frontend modules: `customLovelaceModules`.
  - YAML config under `config`: command_line sensors, template helpers, YAML automations, and the YAML-mode Overview dashboard.
  - Blueprints, and the `www` symlinks.
- `themes/`: the Nocturne theme (`nocturne.yaml`) and its motion script. The header links the design system artifact.
- `cards/`: custom cards written for this HA, including the house floorplan on Home > Home. See `cards/README.md` for where the floorplan's layout lives and how to add sensors to it.
- `blueprints/automation/`: see [docs/blueprints.md](docs/blueprints.md).
- `patches/`: patches to custom components. Each is tagged `WAIT-FOR` where `default.nix` applies it. Recheck them on every version bump of the component.

**In this repo, elsewhere:**
- `hosts/Nexus/services/zigbee2mqtt.nix`, `mosquitto.nix`: Zigbee2MQTT and the broker.
- `hosts/Nexus/services/backup.nix`: the nightly job that stops and restarts HA (see Gotchas).
- `hosts/Nexus/services/fuel-price/`: jobs that write JSON files which `command_line` sensors in `default.nix` read. The pattern for getting computed or external data into HA.
- `hosts/Nexus/services/ups.nix`: apcupsd, which HA's `apcupsd` integration reads.

**In another repo.** The ZPCards card bundle (`zp-cards` in `default.nix`) is pinned by `version` and `hash`. A new or changed card there needs a release in that repo, a bump of both values here, a deploy and a hard refresh. Reusable cards belong there and must work under any theme; only cards specific to this HA go in `cards/`.

**Only in HA (`/var/lib/hass/.storage` and `/var/lib/hass/*.yaml`).** These are edited live in the UI or over the websocket API. They are not in git and need no deploy:
- Every UI dashboard and its cards, including the floorplan card's YAML and the data a card shows (for example the budget figures).
- UI automations (`automations.yaml`), plus scenes, scripts, schedules and UI helpers.
- Integration config entries, and the Assist pipelines.
- The HTTP proxy settings (`trusted_proxies` and the like), since HA moved them out of YAML.
- The default theme, and the sidebar order. The sidebar is stored per HA user: a system default only applies to users who never changed their own, and one user's sidebar cannot be set from another login.

## State docs

These describe parts of the system whose live half is not in git.

| Doc | Covers |
|-----|--------|
| [docs/zigbee-watchdog.md](docs/zigbee-watchdog.md) | The Zigbee network and the Zigbee Coordinator Watchdog automation (only in HA): what it detects, how it recovers, its guards, and what is still untested. |
| [docs/blueprints.md](docs/blueprints.md) | The blueprints in `blueprints/automation/`, the UI automations built from them, and the device behaviour they rely on. |
| [docs/heating.md](docs/heating.md) | Boiler, radiator valves, scenes and schedules: which piece lives where and what each entity really means. Also the venting advice sensors and their notifications. |
| [docs/heating-plan.md](docs/heating-plan.md) | The heating plan (only in HA) that drives the valves: period timeline, temperature levels, presence, why it is built that way, and how to roll it back. |
| [docs/dashboards.md](docs/dashboards.md) | Dashboard conventions, and card, chart and theme behaviour that cost time to find. |
| [docs/metrics.md](docs/metrics.md) | How HA history reaches VictoriaMetrics, what the recorder keeps, and energy and cost data. |
| [docs/live-config.md](docs/live-config.md) | Reading and changing the live half: which API does what, browser tool limits, and how to do it safely. |

**Keep them current.** They are the only record of the live half, so a stale one is worse than none.
- Read the doc before you change what it covers.
- When you change something a doc describes, update the doc in the same piece of work. Where the doc has a "Current state" section and a Changelog, update the first and append a dated row to the second. This applies to live edits in HA too, which leave no commit of their own.
- When the live system disagrees with a doc, the live system is right. Fix the doc and say so.
- Date every Changelog row and every "not verified" note. Remove a "not verified" note once it has been checked.
- When you learn something about this HA that cost time to find, add it to the doc it belongs in.

## Gotchas

- **Public repo.** Keep house-specific data in HA, not here. This covers the floorplan layout, room names and setpoints, budget figures, health and medication data, meter identifiers, people's names and addresses of any kind. It applies to commit messages and PR descriptions as much as to files. When a service in this repo needs such a value, put it in an agenix secret.
- **Frontend changes and the cache.** After a deploy, a change to a theme, card or module only shows after a hard refresh (Ctrl+Shift+R). The service worker serves the old index until then. The modules built from this directory are versioned by content hash, so their URLs change with each edit; packaged ones use their release version.
- **Card styling uses UIX.** card-mod is gone from nixpkgs. Theme styling only applies while UIX has a config entry (added in the UI) and the theme sets `uix-theme`.
- **The heating plan owns the radiator valves.** `automation.heating_plan` rewrites every valve on each period, presence or level change, so a setpoint written directly to a valve only lasts until then. To change a temperature, change an `input_number.heating_level_*` helper; to change a time, edit the Heating plan timeline in the Scheduler card. Read [docs/heating-plan.md](docs/heating-plan.md) first.
- **Live config goes through the user's browser.** Read or change it with Claude in Chrome on the HA site. Start with [docs/live-config.md](docs/live-config.md).
  - `document.querySelector("home-assistant").hass`
  - `hass.connection.sendMessagePromise({ type: "lovelace/config", ... })`
  - That `hass` object is a snapshot, so read it again after every await.
  - The HA MCP server only sees entities exposed to Assist, which is not all of them.
- **Shell access on Nexus is limited.** `ssh nexus` works without a password; `sudo` does not. `/var/lib/hass` and `/var/lib/zigbee2mqtt` are unreadable, so `.storage` cannot be read or backed up from the shell. `journalctl` works. Tools such as `jq` are not installed; get one with `nix build --no-link --print-out-paths nixpkgs#jq.bin`.
- **HA restarts every night at 03:00.** `backup.nix` stops Zigbee2MQTT, Mosquitto and HA, copies their state, and starts them again. Expect a few minutes of downtime, every integration set up again, and Zigbee entities passing through `unavailable`. Anything that must survive a restart has to be designed for this one.
- **HA is reachable from the LAN and the tailnet only.** The reverse proxy (`caddy.nix`, `privateOnly`) refuses every other source, so a cloud service cannot call a webhook here.
- **Deploys are the user's.** Commit and push when asked, then wait for them to say it is deployed before checking it live.
