# Office view

The Agents sidebar's **Visualise** button opens this: every agent as a
pixel-art worker in an office.

- A machine is a building.
- A repo is a floor of it. Agents outside any repo go to its Lobby.
- A git worktree is a room on that floor.
- Each agent sits at its own cubicle.

Working and idle agents face their PC. A blocked or done agent turns round
and raises a hand or cheers. When a hidden sub-agent is blocked, its parent
raises a hand on its behalf.

## Modules

Each module's header says what it does; exported functions document their
contract. Rendering flows top-down:

| Module | Concern |
|---|---|
| `index.js` | The dialog: header (counts, ✋ chip, close), scene, docked card. The entry point `main.js` calls into. |
| `worktrees.js` | The floor plan: asks git where each pane's folder belongs, cached per machine and folder, and groups agents into buildings, floors and rooms. |
| `viewport.js` | Drag and wheel panning of the scene. |
| `building.js` | Buildings, floors and rooms. |
| `cubicle.js` | One agent's cubicle: art layers, pose, badge, name tag, bubble, context meter. |
| `cache.js` | Claude's prompt cache: time left, and the wall clock that shows it. |
| `card.js` | The clicked agent's card: location, model, context and cache, what it asks, and the Go to pane and Peek buttons. |
| `art.js` | Art paths and the rects on the cubicle canvas. |

`main.js` lends `index.js` a few helpers through its `h` argument (names,
durations, context colour bands, cache-expiring rule, blocked sub-agents), so
the sidebar and the office agree on them.

## Art

`art/` holds the art:

- **Cubicle layers.** One 144×176 canvas, stacked at the same spot:
  `cubicle`, then a `screen-*` state, then `chair-behind`, the sprite and
  `chair-front`.
- **`art/clock/`.** The clock frame and its tintable 6×9 digits.

The sprites are not in git. At build time `../sprites/render.mjs` turns the
pixel maps in `../sprites/poses.json` and the app colours in
`../sprites/palettes.json` into `art/sprites/<pose>-<app>.svg`. herdr.nix
copies the result into the deployed mod.

GPUI draws images as they are. It can't recolour them or apply filters, so
every app gets its own sprite file. Only `svg()` icons, like the clock
digits, can be tinted.
