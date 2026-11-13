# Working on the live half

How to read and change the part of Home Assistant that is not in git: dashboards, UI automations, scenes, helpers, config entries. Read "Repo or HA" in [../AGENTS.md](../AGENTS.md) first.

Everything here goes through the user's browser, with Claude in Chrome on the HA site. The API calls below are HA internals and can change with an HA release, so each group carries the date it was last used.

## Getting a handle

```js
const hass = document.querySelector("home-assistant").hass;
```

`hass` is a snapshot. After any `await`, read it again before trusting a state.

- Websocket: `hass.connection.sendMessagePromise({ type: "...", ... })`
- REST: `hass.callApi("GET" | "POST" | "DELETE", "<path without /api/>", body)`
- Services: `hass.callService(domain, service, data)`

## Which call does what

Used on 2026-11-13:

| Task | Call |
|------|------|
| Automation config, with any blueprint expanded | websocket `automation/config` with `entity_id` |
| Automation as stored, with `use_blueprint` | REST `GET config/automation/config/<unique_id>` |
| Save an automation | REST `POST config/automation/config/<unique_id>` with the whole config |
| An entity's `unique_id` | websocket `config/entity_registry/get` |
| Automation runs | websocket `trace/list`, then `trace/get` with `run_id` |
| Entity history | websocket `history/history_during_period` |
| Evaluate a template, with its errors | websocket subscription `render_template` with `report_errors: true` |
| Blueprints HA knows | websocket `blueprint/list` with `domain` |
| Watch MQTT topics, retained messages included | websocket subscription `mqtt/subscribe` |
| Publish to MQTT | service `mqtt.publish` |

Used between 2026-11-08 and 2026-11-10, taken from session notes and not re-tested since:

| Task | Call |
|------|------|
| Dashboard config | websocket `lovelace/config` and `lovelace/config/save` |
| Create or change a dashboard | websocket `lovelace/dashboards/create`, `lovelace/dashboards/update` |
| Scene | REST `config/scene/config/<id>`, GET then POST |
| Delete a config entry | REST `DELETE config/config_entries/entry/<id>`. The websocket `config_entries/delete` does not exist. |
| Create a UI helper through its flow | REST `config/config_entries/flow` |
| `input_number` and similar helpers | websocket `input_number/create`, `input_number/delete` |
| Add a schedule | service `scheduler.add`. There is no `scheduler/add` websocket command. |
| What uses an entity | websocket `search/related` |
| Energy dashboard preferences | websocket `energy/get_prefs`, `energy/save_prefs` |
| Back-fill long-term statistics | websocket `recorder/import_statistics` |
| Default theme | service `frontend.set_theme` |

Zigbee2MQTT has its own frontend on Nexus port 8099. Its websocket at `/api` sends `bridge/info`, `bridge/devices` (with each device's exposed properties and their allowed values) and every device's state. That is the quickest way to see what a Zigbee device really accepts.

## Finding what uses an entity

Searching automation configs for an `entity_id` misses automations built from device triggers or device actions. Those store the entity registry id and a `device_id`, not the entity id. Use `search/related`, or resolve the registry id and search for both. A `generic_hygrostat` helper switches its socket with no automation at all.

## Browser tool limits

- **Output that looks like a cookie or a query string is blocked** (`[BLOCKED: Cookie/query string data]`). A result with many `key=value; key=value` pairs trips it. Return JSON, and strip URLs.
- **Output is cut at about 1000 characters.** Store the full result on `window` and read it in slices, or return only a summary.
- **A single call times out after 45 seconds.** Split a long wait into several calls.
- **`automation.trigger` does not return until the run ends.** Do not await it for an automation that waits or delays.
- **Anything on `window` is lost on navigation.**
- **A background tab throttles animations**, so a measurement taken mid-transition can read 0. Check with a screenshot.
- Start the browser before the first tool call, or the extension is not reachable.

## Changing things safely

- **Back up a dashboard before a bulk edit.** The shell cannot read `.storage`, so copy the dashboard into a hidden, admin-only dashboard named `backup-<yyyymmdd>-<name>`, compare the copy with the original, and delete it once the user has signed the change off.
- **Editing a `.storage` file by hand needs HA stopped.** HA rewrites those files from memory, so an edit made while it runs is lost. The order is: stop HA, copy the file, edit, start HA. It needs sudo, so the user runs it. This is the way to repair a config entry without deleting it, which keeps its entities and areas.
- **A helper starts at its minimum.** A new `input_number` holds its minimum value until set. Set it before building a template sensor or a utility meter on top of it, or that first value lands in the statistics.
- **An entity id can come back with `_2`.** When a deleted entity's long-term statistics still own the clean id, the replacement takes a suffix. Delete the old entity and its config entry before adding the new one.
- **A new `command_line` sensor reads `unknown` until its next scan.** Some scan every 10 minutes. Call `homeassistant.update_entity` on it.
- **Stop after one or two failed logins.** Nexus runs fail2ban on the reverse proxy's log, so a script retrying a bad token can get the machine banned from every Nexus site. (That HA's 401 responses count towards the ban is not verified, 2026-11-13.)

## Tests that pass for the wrong reason

Two bugs reached the live site because a test run in the page differed from the real page:

- Patching `connectedCallback` on a custom element that is already defined does nothing, because the registry copied the callbacks when the element was defined. The test only styled elements that already existed.
- A custom card's host element is `display: inline` unless it says otherwise, and a ResizeObserver reports it as 0 wide. The test element was block-level.

Test on a freshly loaded view and on the real card, not only on an element made by hand.
