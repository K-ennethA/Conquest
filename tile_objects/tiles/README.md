# Tile visuals — reusable stylized tile system

Procedural, animated, **art-free** tile visuals for the tactics board. Nothing here
needs an external mesh or texture; everything is driven by shaders + primitive meshes.

## Folder layout

```
tile_objects/tiles/
├── tile.gd / tile.tscn      Base tile (BoxMesh + collision). All tiles build on this.
├── shaders/                 Shader SOURCE (.gdshader) + noise_lib.gdshaderinc (shared helpers)
├── materials/               Reusable ShaderMaterial PRESETS (.tres) — the "brushes"
├── scenes/                  Tile scenes with extra geometry (e.g. tree_tile.tscn)
└── assets/                  Misc tile data (tile_map.tres)
```

Related data lives with the rest of the game (kept where the Tile Creator plugin writes):

```
game/tiles/resources/        TileResource data (.tres) incl. tree.tres  ← plugin output dir
```

## The material-style system

`TileResource` has a `material_style` enum (`FLAT`, `GRASS`, `WATER`, `BURN`). `FLAT`
builds the classic per-tile `StandardMaterial3D`; any other style returns the **shared**
`ShaderMaterial` mapped in `TileResource.MATERIAL_STYLE_SHADERS`. Sharing one material
per style means adjacent tiles form one seamless, batched field.

### Three ways to reuse a stylized tile
1. **Tile Creator dock** → *Material Style* dropdown → Grass / Water / Burn. Fastest.
2. **Assign a preset directly**: drop a `materials/*.tres` onto a MeshInstance3D's
   `material_override` (e.g. for a one-off decorative mesh).
3. **Instance a scene**: `scenes/tree_tile.tscn` for tiles that need geometry.

## Add a NEW flat material style (e.g. "SAND")
1. `shaders/stylized_sand.gdshader` — `#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"`.
2. `materials/stylized_sand_material.tres` — a ShaderMaterial pointing at that shader.
3. `TileResource.gd`: add `SAND` to `enum MaterialStyle` and a `MaterialStyle.SAND: "res://.../materials/stylized_sand_material.tres"` entry in `MATERIAL_STYLE_SHADERS`.
4. `addons/tile_creator/tile_creator_dock.gd`: append `"Sand (Animated)"` to `material_styles`
   (order MUST match the enum).

That's it — dock preview, save, and in-game all work automatically.

## Add a NEW geometry tile (like the tree)
Copy `scenes/tree_tile.tscn`. Its base `MeshInstance3D` gets a `materials/*` preset; add
child meshes for the geometry (use `materials/stylized_foliage_material.tres` for wind-swayed
canopy). Give it a `TileResource` in `game/tiles/resources/` for gameplay (movement/cover/LOS).

### Getting it onto the board — `TileResource.model_path`

`TileResource.model_path` is the hook: point it at the geometry scene and `MapLoader`
instantiates that scene for every cell using this terrain.

```
# game/tiles/resources/tall_grass.tres
model_path = "res://tile_objects/tiles/scenes/tall_grass_tile.tscn"
```

`MapLoader._create_tile_at_position()` resolves the cell's `TileResource` first, then picks
a scene, most specific first:

1. `resolved.model_path` — loaded when it is non-empty, `ResourceLoader.exists()`, and casts
   to `PackedScene`.
2. the map's `tile_resource_path`, when that field holds a scene rather than a TileResource
   (legacy map data).
3. `default_tile_scene` (`tile.tscn`).

Every step is guarded, so a missing or broken scene silently falls back instead of failing
the map load. So a new geometry tile needs exactly two things: the scene, and that one field.

**Sizing.** Author geometry scenes at FULL cell size — a `2 x 0.2 x 2` `BoxMesh` plus a
matching `BoxShape3D`, exactly like `tree_tile.tscn` (`Grid` cell size is 2). MapLoader
applies its `Basis().scaled(Vector3(2, 1, 2))` fix-up **only** to the unit-box
`default_tile_scene`/legacy path; scenes reached through `model_path` are placed at identity
so they are not doubled to 4x4. Keep decorative geometry above the slab (`y > 0.1`) and
roughly inside the 2x2 footprint so neighbouring tiles don't intersect.

## Preview everything
Run `dev_scripts/grass_preview.tscn` (F6) — shows Grass / Water / Burn / Tree patches
animating side by side.
