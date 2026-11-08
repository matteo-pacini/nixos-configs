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
| Lights | A bulb per light: tap to toggle, hold for its dialog. Tapping a room switches all of its lights. A dimmable light is tinted from amber at low brightness to yellow at full. | `rooms[].lights[].entity` (`light.*` or `switch.*`) |
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
- `label`: the left end of the name's baseline. It can sit outside the room
  when the room is too small for its name. The Garage and the Stairs have
  their names above their north walls. A label above the house needs the
  floor's `y0` (negative, in y percent) to make room for it.
- `label_arrow`: optional, `[[x, y], [x, y]]`, an arrow from the first point
  to the second. Use it to point an outside name at its room, as the Stairs
  name does.
- Any sensor keys from the previous section.

`label`, `label_arrow` and `y0` apply only to the wide layout. On phones, room
names sit inside their rooms.

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
- **Zoom.** Pills, bulbs and room names are drawn at a scale `k`, so that
  text stays readable when a wide floor shrinks to fit the card. On a wide
  card, `k` is the plan's width in SVG units divided by 1550 (`ZOOM_UNITS`),
  and at least 1. That makes text the same size on every floor: about 1.43
  on the Ground floor, with the garage, and about 1.05 on the First floor.
  On a phone, `k` is 1.15 (`ZOOM_NARROW`). The sizes below are at `k` = 1.
- **Pills.** A pill is 56 units tall (5.6% of y). The humidity pill sits 64
  units (6.4%) below the temperature pill unless `humidity_pill` places it.
  A temperature pill such as "20.5° / 20°" is about 255 units wide.
- **Bulbs.** A bulb has a radius of 58 units. Its brightness text sits 104
  units below its centre.
- **Short rooms.** Leave about 8% of y between a dimmable bulb and the pill
  under it. If the room is too short, put `humidity_pill` beside the
  temperature pill, as the Office does.

### Phones (narrow cards)

When the card is under 500 px wide (`NARROW` in the code), it turns the plan a
quarter anticlockwise, so a wide floor fills a portrait screen:

- Whatever was on the left of the plan ends up at the bottom, which is why the
  garage sits under the house.
- Text stays upright.
- Room names move to each room's top-left corner, and `label` is ignored.
- Pills keep their usual place, unless the room sets `narrow_pill`.
- The humidity pill goes under the temperature pill, unless the room sets
  `narrow_humidity_pill`.
- A light keeps its `at`, unless it sets `narrow_at`.
- These narrow keys use the same unturned coordinates as everything else.
- Turned, moving down the screen means *lower* x on the plan, and moving right
  means higher y.

On phones, the Kitchen stacks its pills under the upper bulb, level with the
lower one. The Living Room puts its two pills side by side under the bulb. The
Office moves its bulb up (`narrow_at`) to stack its pills underneath.

Check a layout change at phone width as well as desktop width. A Pixel
9 Pro Fold is about 412 px wide folded (the card is then about 380 px) and
about 790 px unfolded. Chrome's window can't be made that narrow, so set the
test element's width to 380px instead.

### Testing a layout

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
