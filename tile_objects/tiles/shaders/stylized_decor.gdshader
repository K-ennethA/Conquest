shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// =============================================================
//  Vertex-coloured tile DECOR (soil sides, rocks, tufts, flowers, tree
//  trunks, pebbles). Anything above the grass surface (ground_y) sways
//  gently in the wind, more at the tips; the soil block below never moves.
//  World-space phase so neighbouring tiles ripple together like one field.
//  Shared by every LowPolyTileBuilder / TreeBuilder tile (one material).
//  COLOR.a < 1 marks "stiff" geometry (trunks): sway scaled by alpha.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"

uniform float sway_strength = 0.035;
uniform float sway_speed = 1.3;
uniform float ground_y = 0.1;

varying vec3 world_pos;

void vertex() {
	float above = max(VERTEX.y - ground_y, 0.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = TIME * sway_speed + wp.x * 0.7 + wp.z * 0.45;
	float k = above * above * 6.0 * COLOR.a * wind_mul();
	VERTEX.x += sin(ph) * sway_strength * k;
	VERTEX.z += cos(ph * 0.8) * sway_strength * 0.6 * k;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	col = apply_weather(col, 0.3);
	col = apply_outside(col, world_pos.xz);
	ALBEDO = col;
	ROUGHNESS = weather_roughness(1.0);
}
