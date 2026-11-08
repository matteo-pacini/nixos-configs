# Custom Lovelace cards

Cards written for this Home Assistant. Each one is a single ES module with no
build step and no dependencies. `default.nix` installs it as a
`customLovelaceModules` entry. The module's version is a hash of the file, so
every change gets a new resource URL and browsers stop using a cached copy.

After a deploy, hard-refresh the browser (Ctrl+Shift+R). The service worker
keeps serving the old frontend index until then.

## nocturne-floorplan

This card is the layered house plan on **Home > Home** (dashboard
`dashboard-home`, first view). One card shows one floor at a time and has three
layers:

| Layer  | Draws                                                                                    | From                                         |
|--------|------------------------------------------------------------------------------------------|----------------------------------------------|
| Lights | A bulb per light: tap to toggle, hold for its dialog. Tapping a room switches all of its lights. | `rooms[].lights[].entity` (`light.*` or `switch.*`) |
| Heat   | A "current / target" pill. Current is green when at or above target, red below it. The pill turns orange with a flame while heating. A humidity pill sits under it. | `temperature`, `climate` (target and `hvac_action`), `humidity` |
| Doors  | A bar on the wall: green when closed, red when open.                                      | `floors[].doors[].entity` (`binary_sensor.*`, on = open) |

Visual design and the reasoning behind it: the "Home floor drafts" artifact
(draft A), https://claude.ai/artifact/LFWSboBTmE83nFT9kYynnc. Colours and faces
come from the Nocturne theme variables (`../themes/nocturne.yaml`).

### Where things live

- **The card's code** is `nocturne-floorplan.js`, in this public repository.
  It is generic: it contains no rooms and no entity ids. The schema is
  documented in the comment at the top of the file.
- **The house** is the card's YAML, stored in the Home Assistant dashboard
  config (the dashboard's `lovelace.*` file in `/var/lib/hass/.storage`), not
  in this repo.
  It holds every room shape, position and entity id. Change it in the UI (edit
  the dashboard, then the card's code editor) or over the websocket API (below).
  It needs no deploy.

### Adding a sensor to an existing room

Edit the card YAML only. Find the room under `floors[].rooms[]` and set the key:

- `temperature` / `humidity`: a numeric sensor. The pill appears once the room
  has a `pill` position.
- `climate`: a radiator valve. It adds the target and the heating state to the
  room's temperature pill. If the room has no `temperature`, the pill falls back
  to the valve's `current_temperature`.
- A light: append `{ entity: light.x, at: [x, y] }` to `lights`. Leave out `at`
  to centre it in the room. Several lights in one room each need an `at`.
- A door: append `{ entity: binary_sensor.x, a: [x, y], b: [x, y] }` to that
  floor's `doors`. `a` and `b` are the two ends of the bar, drawn on the wall
  line.

### Adding a room

Add an entry to `floors[].rooms[]`:

- `name`.
- `poly`: the outline in floor percent.
- `label`: the top-left of the name.
- Any sensor keys from the previous section.

Trace the polygon starting with the room's largest rectangle. The default light
position and centre are the bounding box of its first four points, extended
down to the lowest point. A room outside the main outline, like the detached
garage, also needs:

- `shell`: its own dark outline.
- The floor's `x0`, set low enough to include it.

### Coordinates

Every position is `[x, y]` in percent:

- `x` is a percent of the floor's `width`.
- `y` is a percent of 1000 SVG units.

On the current floors:

- **Walls.** Rooms are inset about 1% from each other, and the house outline
  runs from 0 to 100.
- **Pills.** A pill is 56 units tall (5.6% of y). The humidity pill sits 64
  units (6.4%) below the temperature pill unless `humidity_pill` places it.
- **Bulbs.** A bulb has a radius of 58 units. Its brightness text sits 104
  units below its centre.
- **Short rooms.** Leave about 8% of y between a dimmable bulb and the pill
  under it. If the room is too short, put `humidity_pill` beside the
  temperature pill, as the Office does.

To try a layout before saving it, load the module in a browser tab on the HA
frontend and render it with a test config:

```js
const el = document.createElement("nocturne-floorplan");
el.setConfig(config);
el.hass = document.querySelector("home-assistant").hass;
document.querySelector("home-assistant").shadowRoot.append(el);
```

Remove it afterwards. A tab reload also clears it.

### Editing the card YAML from a script

`lovelace/config` reads the dashboard and `lovelace/config/save` writes the
whole thing back:

```js
const hass = document.querySelector("home-assistant").hass;
const cfg = await hass.connection.sendMessagePromise({ type: "lovelace/config", url_path: "dashboard-home" });
const card = cfg.views[0].sections.flatMap((s) => s.cards).find((c) => c.type === "custom:nocturne-floorplan");
// ...change `card`...
await hass.connection.sendMessagePromise({ type: "lovelace/config/save", url_path: "dashboard-home", config: cfg });
```

Find the card by `type`, not by section index; sections get reordered.

### Adding a new kind of sensor

Smoke, windows and motion are examples of a new kind. Each one is a change to
the code, then a deploy. Keep it data-driven like the existing layers:

1. **Config key.** Add a key to the room or floor schema, and document it in
   the header comment of `nocturne-floorplan.js` and in this README.
2. **`_collect()`.** Add its entity ids here. The card only redraws when one of
   the collected entities changes, so a missing id means a stale plan.
3. **`_plan()`.** Draw it, behind an `on("<layer>")` check.
4. **New layer.** If it needs a layer of its own, add an entry to `LAYERS` with
   its id, name, `mdi:` icon and theme colour variable. Then add its count to
   `_counts()`.
5. **Colours.** Use theme variables only (`--green-color`, `--red-color` and
   so on, plus the `--fp-*` aliases in `CSS`), so that Night and Dawn both work.

Then add the sensor to the card YAML in HA as described above.
