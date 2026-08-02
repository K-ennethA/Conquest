# Conquest

A 3D Fire Emblem–style tactical turn-based strategy game built in **Godot 4.6** (GDScript).

Grid movement, unit stats & combat, pluggable turn systems, and online multiplayer.

---

## Running the game

1. Install **Godot 4.6** (Forward+ renderer).
2. Open `project.godot` in the Godot editor.
3. Press **F5** (or Play) — the main scene is `menus/MainMenu.tscn`.

There is no external build step; GDScript is interpreted by the engine.

## Running the tests

Tests use [GUT](https://github.com/bitwes/Gut) (bundled in `addons/gut`).

- In-editor: open the **GUT** bottom panel and run.
- Headless / CI:
  ```
  godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
  ```

## Project layout

| Path | Purpose |
|------|---------|
| `systems/` | Autoload singletons & core subsystems (events, players, turns, networking) |
| `systems/net/` | **New** consolidated server-authoritative multiplayer core (`NetSession`) |
| `game/` | Gameplay content: units, maps, tiles, UI, visuals, world |
| `tile_objects/` | Unit / board / tile scene implementations (`class_name Unit`, etc.) |
| `board/`, `turns/` | Grid, cursor, and early turn/priority prototypes |
| `menus/` | Menus, lobby, galleries, multiplayer setup |
| `addons/` | GUT + custom editor tools (map / tile / unit creators) |
| `tests/` | GUT test suite (`unit/`, `integration/`, `performance/`, `mocks/`) |
| `dev_scripts/` | Ad-hoc developer/debug scripts, not part of the build |
| `docs/archive/` | Historical development notes & fix summaries |

## Autoloads

Defined in `project.godot` under `[autoload]`. Core singletons: `GameEvents` (event bus),
`PlayerManager`, `TurnSystemManager`, `GameSettings`, `ResourceManager`, `GameModeManager`.

## Multiplayer

See [`systems/net/README.md`](systems/net/README.md) for the current (consolidated) networking
architecture and how to host/join. `systems/net/` is the only networking stack: the older
`systems/networking/` and `systems/multiplayer/` layers (and their Dictionary-based state
simulator) have been deleted.
