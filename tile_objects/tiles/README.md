# Tile visuals — reusable stylized tile system

Procedural, animated, **art-free** tile visuals for the tactics board. Nothing here
needs an external mesh or texture; everything is driven by shaders + primitive meshes.

## Folder layout

```
tile_objects/tiles/
├── tile.gd / tile.tscn      Base tile (BoxMesh + collision). All tiles build on this.
├── shaders/                 Shader SOURCE (.gdshader) + noise_lib.gdshaderinc (shared helpers)
├── materials/               Reusable ShaderMaterial PRESETS (.tres) — the "brushes"
├── scenes/<biome>/          Tile scenes with extra geometry, grouped by biome
└── assets/                  Misc tile data (tile_map.tres)
```

Related data lives with the rest of the game (kept where the Tile Creator plugin writes):

```
game/tiles/resources/<biome>/   TileResource data (.tres)   ← plugin output dir
game/tiles/effects/resources/   TileEffectResource data (.tres)
```

## Biome folders

Tiles are grouped by biome, and a biome is **two mirrored folders** — nothing else:

```
game/tiles/resources/<biome>/       the TileResource .tres  (gameplay + look)
tile_objects/tiles/scenes/<biome>/  the .tscn geometry it points at
```

Current biomes: `common/`, `forest/`, `volcano/`, `ice/`.

**Adding a biome needs no code change.** `TileCatalog` (`game/tiles/TileCatalog.gd`)
walks `game/tiles/resources/` *recursively* and indexes every `.tres` that loads as a
`TileResource`, so a brand-new folder shows up in the Map Creator palette and the Map
Gallery on the next scan (call `TileCatalog.rescan()` after writing tiles at runtime).
`TileCatalog.find()` also falls back to matching a tile's **file name** anywhere in the
tree, so moving an asset between biome folders won't break maps that saved the old path.

A tile renders through its **`model_path`** — the `TileResource` field that names the
scene MapLoader instantiates for that cell (see *Getting it onto the board* below).
A tile with an empty `model_path` falls back to the plain `tile.tscn` slab.

Per-tile behaviour is authored the same way: effects live in
`game/tiles/effects/resources/` and are attached by setting `has_default_effects = true`
and listing them in `default_effects`. Effects are resolved **per tile**, not per tile
type — e.g. `volcano/magma_vent.tres` → `scorching_vent.tres` (damage on turn start),
`ice/ice_sheet.tres` → `slippery_ice.tres` (passive evasion penalty).

## The material-style system

`TileResource` has a `material_style` enum (`FLAT`, `GRASS`, `WATER`, `BURN`). `FLAT`
builds the classic per-tile `StandardMaterial3D`; any other style returns the **shared**
`ShaderMaterial` mapped in `TileResource.MATERIAL_STYLE_SHADERS`. Sharing one material
per style means adjacent tiles form one seamless, batched field.

### Three ways to reuse a stylized tile
1. **Tile Creator dock** → *Material Style* dropdown → Grass / Water / Burn. Fastest.
2. **Assign a preset directly**: drop a `materials/*.tres` onto a MeshInstance3D's
   `material_override` (e.g. for a one-off decorative mesh).
3. **Instance a scene**: `scenes/forest/tree_tile.tscn` for tiles that need geometry.

## Add a NEW flat material style (e.g. "SAND")
1. `shaders/stylized_sand.gdshader` — `#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"`.
2. `materials/stylized_sand_material.tres` — a ShaderMaterial pointing at that shader.
3. `TileResource.gd`: add `SAND` to `enum MaterialStyle` and a `MaterialStyle.SAND: "res://.../materials/stylized_sand_material.tres"` entry in `MATERIAL_STYLE_SHADERS`.
4. `addons/tile_creator/tile_creator_dock.gd`: append `"Sand (Animated)"` to `material_styles`
   (order MUST match the enum).

That's it — dock preview, save, and in-game all work automatically.

## Add a NEW geometry tile (like the tree)
Copy `scenes/forest/tree_tile.tscn` into your biome's `scenes/<biome>/` folder. Its base
`MeshInstance3D` gets a `materials/*` preset (or a small inline `StandardMaterial3D` for a
FLAT tile); add child meshes for the geometry (use `materials/stylized_foliage_material.tres`
for wind-swayed canopy). Give it a `TileResource` in `game/tiles/resources/<biome>/` for
gameplay (movement/cover/LOS), and point that resource's `model_path` back at the scene.

### Getting it onto the board — `TileResource.model_path`

`TileResource.model_path` is the hook: point it at the geometry scene and `MapLoader`
instantiates that scene for every cell using this terrain.

```
# game/tiles/resources/forest/tall_grass.tres
model_path = "res://tile_objects/tiles/scenes/forest/tall_grass_tile.tscn"
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
