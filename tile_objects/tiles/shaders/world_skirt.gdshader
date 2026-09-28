shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

// =============================================================
//  WORLD SKIRT ground: the non-playable landscape around the board.
//  Literally the same paint as the board's grass / dirt (ground_lib), so the
//  field flows seamlessly off the board; the terrain mask continues roads
//  (dirt) outward; slopes and hill tops get a drier, lighter tint; and
//  apply_outside() dims it a touch right past the border (boundary read)
//  and fades it into haze_color far away (no visible world edge).
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/ground_lib.gdshaderinc"

uniform vec3 slope_color : source_color = vec3(0.42, 0.40, 0.25);
uniform vec3 bank_color : source_color = vec3(0.33, 0.27, 0.18);

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 wp = world_pos.xz;
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near_amt = ground_near(cam_dist);
	vec3 col = grass_color(wp, near_amt, TIME);
	vec4 m = terrain_at_warped(wp, 0.9);
	// Continued roads.
	float road = smoothstep(0.35, 0.65, m.g + (fbm(wp * 2.3) - 0.5) * 0.4);
	col = mix(col, dirt_color(wp, near_amt), road);
	// River / lake banks: damp earth just above the waterline.
	float bank = smoothstep(0.02, 0.3, m.r + m.b) * (1.0 - smoothstep(0.1, 0.3, world_pos.y));
	col = mix(col, bank_color, bank * 0.8);
	// Hills: drier / sunlit tops, steeper faces a touch earthier.
	float slope = 1.0 - clamp(world_nrm.y, 0.0, 1.0);
	col = mix(col, slope_color, smoothstep(0.15, 0.6, slope) * 0.35);
	col *= mix(1.0, 1.08, smoothstep(1.0, 8.0, world_pos.y));
	col = apply_weather(col, 1.0);
	col = apply_outside(col, wp);
	ALBEDO = col;
	ROUGHNESS = weather_roughness(1.0);
	SPECULAR = weather_wetness * 0.5;
}
