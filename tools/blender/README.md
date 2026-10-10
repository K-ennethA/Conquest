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
| `--target-height` | The unit's TRUE design height in metres (default `1.8`) — see scale below |
| `--max-footprint` | Optional width/depth clamp in world units (default `0` = off) — see scale below |
| `--target-faces` | Decimation budget. Note the result is in TRIANGLES, so a quad-based sculpt lands near 2x this |
| `--thorns` | Scatter N procedural spikes over the surface. Default `0` (off) |

## What it does

1. Joins all meshes into one object.
2. **Optional** — scatters `--thorns N` spikes (see below). Off by default.
3. Decimates to the budget (a sculpt is hundreds of thousands of polys).
4. Shades smooth, then Smart-UV-unwraps — **after** decimating, since decimation
   destroys any earlier UV layout.
5. Adds a simple Principled material when the sculpt has none.
6. Scales to the true design height (a wide model overhangs its cell).
7. Moves the origin to the **feet**, centred in X/Y.
8. Applies transforms and exports `.glb` with +Y up.

It prints a report and notes when the model overhangs a single cell.

## Scale — true size, one tile

Units are shown at their **true design height** (CONQUEST.md "Size"): 1 world unit =
1 m and cells are **2.0**, so pass the owner's size straight in — a 2 ft Blightcap is
`--target-height 0.61`, an 8 ft Barkling `2.44`. Only height binds:

```
scale = target_height / height
```

A model wider than its cell — Barkling's arms, Petalfang's vines — **overhangs its
neighbours and stays one tile**. That is intended, not a bug: the game draws a
team-coloured tile plate under every unit so the tile it owns is always clear, and
puts the health bar on the measured model top. The run notes the overhang:

```
true size: height 5.181 -> 1.219 (no footprint clamp)
NOTE 2.91 x 2.07 overhangs one 2.0 cell -- fine for a one-tile unit; the tile plate shows which tile it owns
```

Over **two cells** either way it says so: either a stray object is dragging the
bounds out, or this is a giant that should get a multi-cell `footprint` (a design
call — Eldroot is the 2×2 one). Never shrink a unit to make it fit.

`--max-footprint N` (> 0) re-enables the old fit-in-a-cell clamp,
`min(target_height / height, N / max(width, depth))`, reporting which bound. The
assets built before the true-size rule pin it in `assets.conf` so a rebuild never
changes them, and the 2×2 Eldroot uses `--max-footprint 3.8`. Their in-game size is
set by the roster `model_scale` instead.

Forge-delivered `*_forge.glb` models skip this script; their size is likewise
`model_scale` = design height / imported height.

## Thorns (`--thorns N`)

An opt-in extra pass for spiky creatures — it is off by default, so nothing else in
the registry is affected. It scatters `N` small cones over the surface and joins
them in **before** decimation and unwrapping, so the spikes are budgeted and UV'd
along with the body rather than bolted on afterwards.

Placement is biased toward the **thin, protruding** parts — on a vine creature the
thorns belong on the tendrils, not the bulky central body. Two cheap heuristics are
blended, since either alone misplaces them: distance from the mesh's centre of mass,
and radial distance from the vertical body axis. The inner half of the range is
dropped outright, and a minimum-separation pass stops thorns clumping wherever the
sculpt happens to be most densely tessellated.

Each thorn points along its face **normal**, with randomised length, base radius,
roll and a slight tilt so they don't look stamped. Size is ~3.8% of the model's
largest dimension (pre-rescale).

Tune `N` by eye and re-render. `petalfang` uses `--thorns 40`.

## The conventions that matter

- **Scale** — board cells are **2.0 world units**. A regular humanoid is ~1.8.
  You don't need to sculpt at that size; the pipeline rescales to `--target-height`.
- **Origin at the feet** — units sit at `y = 0` on a cell centre. Handled for you.
- **Facing** — face **−Y in Blender**. The +Y-up export turns that into Godot's
  **+Z** (toward the battle camera), which is the game's model-forward convention:
  leave `model_yaw_deg` at 0. A sculpt that ends up facing away needs
  `model_yaw_deg = 180`. Check with `dev_scripts/render_unit_facing.gd` (CONQUEST.md
  "Unit facing"). This is the one thing worth getting right while sculpting.
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

Set `footprint` only for a giant (a design call — see "Scale" above); a model
that merely overhangs its cell stays one tile. See `game/characters/CharacterResource.gd`.

## Worked example — `tree_grunt`

> Both worked examples predate the true-size rule: they were built with the old
> fit-in-a-cell clamp (`--max-footprint 1.9`, now pinned in `assets.conf`). Their
> output still reads this way; a new unit's run reports `true size:` instead.

```
source faces=240562
decimated 240562 -> 9889 faces (ratio 0.0208)
smart UV unwrap done
added default material 'tree_grunt_mat'
scale candidates: height 0.09728 (18.503 -> 1.800), footprint 0.07529 (25.235 -> 1.900)
BOUND BY FOOTPRINT -- scaled by 0.07529
final size w=1.900 d=0.857 h=1.393
final origin_at_feet_z=0.0000 centred_x=0.0000 centred_y=0.0000
```

Its arms span wide, so the footprint binds and it lands 1.393 tall rather than 1.8.
Under the old height-only scaling it came out **2.455 wide** and tripped the
"exceeds one cell" NOTE; now it fits, and the NOTE is gone.

## Worked example — `petalfang` (with thorns)

```
source faces=68368
thorns: 40 spikes, len~0.470 (3.8% of maxdim 12.36), joined -> 68648 faces
decimated 68648 -> 9408 faces (ratio 0.0728)
smart UV unwrap done
added default material 'petalfang_mat'
scale candidates: height 0.34739 (5.181 -> 1.800), footprint 0.15352 (12.376 -> 1.900)
BOUND BY FOOTPRINT -- scaled by 0.15352
final size w=1.900 d=1.386 h=0.795
final origin_at_feet_z=0.0000 centred_x=0.0000 centred_y=0.0000
```

A sprawling vine-serpent: wide and low, so it fills the cell at 1.900 × 1.386 and
is only 0.795 tall. That is the footprint constraint working as intended.

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

## Iterating on a sculpt

A `.glb` is a **derived artifact** — editing your `.blend` changes nothing in game
until it is re-exported. Nothing watches the source file.

Re-export is one command:

```bash
tools/blender/reingest.sh              # rebuild anything whose .blend is newer
tools/blender/reingest.sh --all        # rebuild everything
tools/blender/reingest.sh tree_grunt   # rebuild one asset
```

Add a line to `tools/blender/assets.conf` per unit and the script handles the
rest. The no-argument form compares timestamps, so it is cheap to run habitually.

> **Caveat — `petalfang` and `--thorns`.** `assets.conf` has five columns
> (`name|source|output|height|faces`) with nowhere to put extra flags, so
> `reingest.sh` cannot pass `--thorns 40` and will rebuild petalfang **smooth**,
> silently dropping every spike. Re-export it with the full command in the comment
> at the bottom of `assets.conf` until the registry grows an options column.

**Nothing downstream breaks on re-export.** The `CharacterResource` references the
`.glb` by path and Godot's `.import` settings file persists, so stats, id,
footprint and import settings all survive — Godot just re-imports the new mesh.
Verified: after a rebuild the character still reports its stats and the model is
still 1.8 tall with its origin at the feet.

This also means re-rigging or adding animations later needs no code or resource
changes: re-run, and the new clips are picked up by the animation bridge.
