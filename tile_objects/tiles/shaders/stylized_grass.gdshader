shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

// =============================================================
//  Stylized Painterly Grass  (top-down tactics tiles)
//  - Fully procedural: needs NO texture assets.
//  - Pattern is driven by WORLD position, so every grass tile
//    sharing this material forms ONE continuous, seamless field.
//  - Layers (bottom -> top), see ground_lib.gdshaderinc grass_color():
//      1. Field tint: very low-frequency drift between a lush and a
//         sun-dried palette, so a big map isn't one flat green.
//      2. Painterly strokes: domain-warped fbm stretched along the wind,
//         reading like brushed grass rather than noise.
//      3. Clover clumps: soft cellular blobs, slightly darker/cooler.
//      4. Wildflower specks: rare, tiny, colour-varied dots (near only).
//  - Seamless: no per-tile edges -- the board reads as one continuous
//    field; cells are shown by the cursor / range overlays, not the ground
//    (an OPTIONAL subtle grid comes from the `grid_lines` global).
//  - Reads the weather globals (world_lib.gdshaderinc).
//  Reuse: assign this same material to any grass tile.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/ground_lib.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near_amt = ground_near(cam_dist);
	vec3 col = grass_color(world_pos.xz, near_amt, TIME);
	// Grassy cap skirts (the little bank above water / at the board edge) read
	// as darker turf rather than a flat green wall.
	float wny = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	col *= mix(0.62, 1.0, smoothstep(0.2, 0.8, wny));
	col = apply_grid(col, world_pos, cam_dist);
	col = apply_weather(col, 1.0);
	col = apply_outside(col, world_pos.xz);
	ALBEDO = col;
	ROUGHNESS = weather_roughness(1.0);
	SPECULAR = weather_wetness * 0.5;
}
