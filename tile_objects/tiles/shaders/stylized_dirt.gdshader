shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

// =============================================================
//  Stylized Painterly Dirt / Path
//  Same paint box as the grass (ground_lib), world-space so a path is one
//  continuous strip. Edges touching grass cells grow a noisy, painted grass
//  fringe (read from the global terrain mask) instead of a hard box edge, so
//  paths blend into the meadow.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/ground_lib.gdshaderinc"

uniform float fringe_amount : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near_amt = ground_near(cam_dist);
	vec2 wp = world_pos.xz;
	vec3 col = dirt_color(wp, near_amt);
	float wny = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	if (wny > 0.5) {
		// The terrain mask describes floor 0 only: no turf fringe on decks / walls.
		float f = world_pos.y < 0.8 ? grass_fringe(wp) * fringe_amount : 0.0;
		// A thin dark soil line where turf meets path sells the edge.
		float lip = smoothstep(0.05, 0.35, f) * (1.0 - smoothstep(0.35, 0.7, f));
		col = mix(col, dirt_dark * 0.8, lip * 0.35);
		col = mix(col, grass_color(wp, near_amt, TIME), f);
	} else {
		col *= 0.72;
	}
	col = apply_grid(col, world_pos, cam_dist);
	col = apply_weather(col, 1.0);
	col = apply_outside(col, wp);
	ALBEDO = col;
	ROUGHNESS = weather_roughness(1.0);
	SPECULAR = weather_wetness * 0.6;
}
