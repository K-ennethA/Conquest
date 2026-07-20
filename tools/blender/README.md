# Blender → Godot unit pipeline

Sculpt freely in Blender. Don't think about poly budget, UVs, scale, origin or
axes — the pipeline handles all of it. Your `.blend` is opened **read-only** and
never saved over.

## Run it

```bash
"C:/Program Files/Blender Foundation/Blender 5.0/blender.exe" \
  --background "path/to/your_sculpt.blend" --factory-startup \
  --python tools/blender/prepare_unit.py -- \
  --output "game/characters/models/<biome>/<name>.glb" \
  --name <name> --target-height 1.8 --target-faces 5000
```

| Flag | Meaning |
|---|---|
| `--output` | Where the `.glb` lands (inside the project) |
| `--name` | Object/mesh name in the export |
| `--target-height` | Final height in world units (see scale below) |
| `--target-faces` | Decimation budget. Note the result is in TRIANGLES, so a quad-based sculpt lands near 2x this |

## What it does

1. Joins all meshes into one object.
2. Decimates to the budget (a sculpt is hundreds of thousands of polys).
3. Shades smooth, then Smart-UV-unwraps — **after** decimating, since decimation
   destroys any earlier UV layout.
4. Adds a simple Principled material when the sculpt has none.
5. Scales so the model is `--target-height` tall.
6. Moves the origin to the **feet**, centred in X/Y.
7. Applies transforms and exports `.glb` with +Y up.

It prints a report and warns when the model overhangs a single cell.

## The conventions that matter

- **Scale** — board cells are **2.0 world units**. A regular humanoid is ~1.8.
  You don't need to sculpt at that size; the pipeline rescales by height.
- **Origin at the feet** — units sit at `y = 0` on a cell centre. Handled for you.
- **Facing** — face **−Y in Blender**. The +Y-up export turns that into Godot's
  −Z forward. This is the one thing worth getting right while sculpting.
- **Up axis** — Blender Z-up becomes Godot Y-up automatically.
- **Animations** — name clips `idle`, `walk`, `attack`, `hit`, `death` so the game
  can find them without per-unit configuration.

## Getting it into the game

1. Export to `game/characters/models/<biome>/<name>.glb`.
2. Create a `CharacterResource` in `game/characters/roster/<name>.tres` with
   `character_id`, stats, and `model_scene` pointing at the `.glb`.
3. That's it — `Unit._setup_character_model()` instantiates `model_scene` at the
   unit's origin and hides the placeholder capsule. Because the export is already
   origin-at-feet and correctly scaled, no runtime correction is needed.

Set `footprint` on the character when the model is wider than one cell (the
pipeline tells you when it is) — see `game/characters/CharacterResource.gd`.

## Worked example — `tree_grunt`

```
source faces=240562
decimated 240562 -> 9889 faces (ratio 0.0208)
smart UV unwrap done
added default material 'tree_grunt_mat'
scaled by 0.09728 (height 18.503 -> 1.800)
final size w=2.455 d=1.107 h=1.800
final origin_at_feet_z=0.0000 centred_x=0.0000 centred_y=0.0000
NOTE footprint 2.45 x 1.11 exceeds one 2.0 cell -- consider a multi-cell footprint
```

## Animations

Rig and animate in Blender, then name your actions so the game can find them:

| Clip | Plays when |
|---|---|
| `idle` | At rest; also queued automatically after any one-shot clip |
| `walk` | The unit moves to a new tile |
| `attack` | This unit deals damage |
| `hit` | This unit takes damage |
| `death` | This unit is eliminated |

Naming is forgiving: `idle`, `Idle` and glTF's `Armature|Idle` all resolve, and
matching is case-insensitive. Only the clip's own name matters, not the action's
position in the file.

Anything missing simply falls back to the built-in procedural animation, so a
model with only `idle` and `death` still works — the rest keeps using tweens. Set
`use_authored_clips = false` on the UnitAnimator autoload to force the procedural
path everywhere and compare feel.

Two behaviours worth knowing:
- A `walk` clip animates the legs; the engine still glides the model across the
  tile, so the two layer rather than fight.
- A `death` clip REPLACES the shrink tween (shrinking a model mid-death-animation
  just erases the animation). A `hit` clip suppresses the squash-punch but keeps
  the red damage flash, which stays readable either way.
