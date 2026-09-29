# World art: painterly, seamless, one landscape

The battle map reads as ONE continuous painted landscape, not a grid of boxes.
Cells are communicated by the cursor / range overlays (and an optional subtle
grid), never by seams in the ground. Reference look: the grass tile
(`tile_objects/tiles/shaders/stylized_grass.gdshader`).

## Building blocks

| Piece | Where |
|---|---|
| Noise helpers | `tile_objects/tiles/shaders/noise_lib.gdshaderinc` |
| World globals + helpers (terrain mask, grid, weather, out-of-board haze) | `tile_objects/tiles/shaders/world_lib.gdshaderinc` |
| Shared grass / dirt paint (board grass, dirt paths, world skirt) | `tile_objects/tiles/shaders/ground_lib.gdshaderinc` |
| Ground materials (one shared material per terrain kind) | `tile_objects/tiles/materials/stylized_*_material.tres`, chosen by `TileResource.material_style` |
| Water / lava | `stylized_water.gdshader`, `stylized_burn.gdshader` |
| Generic ground (snow, ice, tundra, ash, obsidian, sacred stone) | `stylized_ground.gdshader` |
| Props (castle masonry, stairs, bridges, paving, rocks) | `stylized_props.gdshader` via `ProcMesh.material()` |
| Tile decor (soil sides, tufts, flowers) / tall grass / motes | `stylized_decor`, `stylized_tall_grass`, `stylized_motes` |
| Trees | `tile_objects/tiles/lowpoly/TreeBuilder.gd` + `stylized_foliage.gdshader` |
| Tile-effect ground FX (fire, poison, ice, heal, water, fortify, telegraph) | `game/visuals/world/EffectFX.gd`, `stylized_effect_decal`, `stylized_flame` |
| Terrain class mask (per-cell texture read by the shaders) | `game/visuals/world/TerrainMask.gd` |
| Landscape around the board (non-interactive) | `game/visuals/world/WorldSkirt.gd` + `world_skirt.gdshader` |
| Lighting / sky / fog / grade / contact shadows | `game/visuals/world/WorldLook.gd` |

Rules of thumb: pattern in WORLD space (seamless across tiles), share one
material per kind (never per tile), posterize a little (cel read), fade fine
detail with camera distance, deterministic variation (hash the world position,
never `randf()`).

## Global shader uniforms (`project.godot` `[shader_globals]`)

Set them with `RenderingServer.global_shader_parameter_set(name, value)`.

### Weather hooks (for the weather system)

| Uniform | Range / default | Effect |
|---|---|---|
| `weather_wetness` | 0..1, 0 | darker, more saturated ground, glossier (lower roughness), stronger water ripples |
| `weather_dust` | 0..1, 0 | tan wash / haze over ground, props and foliage |
| `weather_bloom` | 0..1, 0 | more wildflowers, richer saturation, bigger / brighter light motes |
| `weather_sun` | 0..1, 0 | warmer, brighter surfaces |
| `wind_strength_global` | >= 0, 1 | multiplies all sway: grass strokes, tufts, tall grass, canopies |

`WorldLook.set_weather(wetness, dust, bloom, sun, wind)` writes all five at
once. Lighting-level weather (sun colour / energy, ambient, fog, glow, grade)
goes through the `WorldLook` node's properties, which all apply on set and
can be tweened:

```gdscript
var look := WorldLook.find(get_tree())
var tw := look.create_tween().set_parallel()
tw.tween_property(look, "sun_energy", 0.7, 2.0)
tw.tween_property(look, "fog_density", 0.8, 2.0)
tw.tween_property(look, "haze_color", Color(0.55, 0.6, 0.66), 2.0)
```

Properties: `sun_color`, `sun_energy`, `sun_rotation_degrees`,
`shadow_softness`, `ambient_energy`, `sky_top_color`, `sky_horizon_color`,
`haze_color`, `fog_density`, `exposure`, `glow_intensity`, `glow_bloom`,
`saturation`, `contrast`, `contact_shadows`.

### Board / world (driven by the game)

| Uniform | Set by | Meaning |
|---|---|---|
| `terrain_mask`, `terrain_mask_rect`, `terrain_mask_on` | `TerrainMask.publish` (map load) | per-cell classes: R water, G dirt/path, B lava, A grass |
| `board_rect` | `TerrainMask.publish` | playable XZ rect; outside it surfaces dim then fade into `haze_color` |
| `haze_color` | `WorldLook` | distant landscape / sky blend colour |
| `grid_lines` | `GameSettings.set_grid_lines` | 0 off, 1 subtle cell grid (Settings > Grid Lines) |
| `focus_world` | `WorldLook` (cursor) | canopies between camera and cursor dither away so units stay visible |

## World skirt

`MapLoader` builds `Tiles/WorldSkirt` after the tiles: a heightfield landscape
extending 110 units past every edge (slightly below the board so the playable
area reads as a gentle plateau), continuing edge biomes (rivers / moats / lava
straight out, roads a few cells, grass elsewhere), with MultiMesh trees, bushes
and rocks. It has no collision, is never registered with CombatServices, and is
skipped on the headless renderer.

Computing it is ~350 ms of GDScript, so it is split into `WorldSkirt.compute`
(pure data: surface arrays + MultiMesh transform buffers, thread-safe) and a cheap
node mount. The data (and the meshes made from it) is cached per
`TerrainMask.content_key` (board size + tile layout), and `WorldSkirt.prewarm`
computes a neighbouring story area's skirt on the WorkerThreadPool. The terrain
mask is cached the same way (`TerrainMask.mask_for`). Tile geometry from
`LowPolyTileBuilder` / `PavedTileBuilder` is likewise built once per (style, cell)
and shared (`TileMeshCache`) -- so a tile builder must stay a pure function of
its style and cell.
