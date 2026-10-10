---
name: blender-unit-import
description: Import a Blender-sculpted character/creature into Conquest as a playable/enemy unit — run the tools/blender/prepare_unit.py pipeline to turn a .blend into a true-size .glb, then wire it into a CharacterResource .tres. Use whenever the user says they have a new model/character/unit in Blender to add, references a .blend file, or asks to import/replace a unit's model.
---

# Blender → Conquest unit import

The authoritative reference is `tools/blender/README.md` — read it for the scale math,
thorns heuristic, and facing details. This skill is the fast path.

## 1. Export the .blend → .glb (the pipeline does all the fixup)

Blender 5.0 is at `C:/Program Files/Blender Foundation/Blender 5.0/blender.exe`.
The user's sculpts live in their Blender folder (e.g. `C:/Users/kenne/OneDrive/Documents/*.blend`).
Ask for the exact `.blend` path if unknown; do NOT guess a name.

Run (from the project root; the .blend is opened read-only, never saved over):

```bash
"C:/Program Files/Blender Foundation/Blender 5.0/blender.exe" --background \
  "<ABS_PATH_TO>.blend" --factory-startup \
  --python tools/blender/prepare_unit.py -- \
  --output "game/characters/models/<biome>/<name>.glb" \
  --name <name> --target-height <design height, metres> --target-faces 5000
```

- `<biome>` = a folder under `game/characters/models/` (e.g. `forest`).
- `<name>` = the unit id (lowercase, matches the .tres filename).
- Add `--thorns N` ONLY for spiky creatures (petalfang uses 40); off by default — a
  clean hero sculpt needs none.
- `--target-height` is the unit's TRUE design height in metres (1 unit = 1 m; ask
  the owner if unknown — e.g. 8 ft = 2.44). Units are shown at true size and a
  wide one overhangs its 2.0 cell and stays ONE tile (CONQUEST.md "Size"); never
  shrink to fit. Only a giant gets a multi-cell `footprint`, and that is the
  owner's call.
- The pipeline joins meshes, decimates, smart-UVs, scales to that height, moves
  the origin to the feet, and exports +Y up. It prints a report; a "NOTE ...
  overhangs" line is expected for wide units — only "over 2 cells" needs a look.

Conventions baked into the sculpt (the pipeline can't fix these): face **−Y in
Blender** (→ Godot −Z forward); name animation clips `idle`/`walk`/`attack`/`hit`/`death`.

## 2. Import the new .glb into Godot

```bash
"<godot exe>" --headless --path . --import
```
(Godot exe: `C:/Users/kenne/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe`)

## 3. Wire it into a CharacterResource

Create/edit `game/characters/roster/<name>.tres` (a `CharacterResource`). Point its
model field at the new `.glb` (check an existing roster .tres for the exact field name
— e.g. the model_scene/model path + `model_yaw_deg` used by `petalfang.tres`). Also set
`character_id` (= filename), `display_name`, `element` (for type matchups), base stats,
and `moveset` (Array of MoveResource). `CharacterLibrary` auto-scans the roster dir, so
no registration is needed — the id is the filename.

To make it appear immediately: add the id to `ArenaController.DEFAULT_SQUAD` (or an
enemy pool / a map spawn) so it spawns in a test round.

## 4. Gate + commit

Central gate as always: `--import`, GUT suite, boot (see the minimize-godot-launches
memory — batch into one run). Then commit the `.glb`, the roster `.tres`, and any move
`.tres`.

## Gotchas
- A model built with `--max-footprint` (legacy `assets.conf` rows, Eldroot) is
  clamped to its cell; set its true size with the roster `model_scale` (design
  height / imported height) instead of re-exporting.
- A forge-delivered `*_forge.glb` is sized the same way: `model_scale` = design
  height / imported height. Check with `dev_scripts/true_size_shots.tscn`.
- `.blend1` backups next to the `.blend` are Blender autosaves — ignore them.
