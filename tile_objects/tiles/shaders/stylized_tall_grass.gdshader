shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled, depth_draw_opaque;

// =============================================================
//  Tall-grass blades (the evasion terrain). Vertex-coloured base -> tip
//  gradient, double-sided, softly translucent so a unit standing in the
//  clump shows THROUGH it, and swaying in a slow wave that rolls across
//  the whole patch (world-space phase). Tips catch a warm rim so the
//  patch reads as distinctly taller/lusher than the lawn around it.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"

uniform float sway_strength = 0.09;
uniform float sway_speed = 1.1;
uniform float ground_y = 0.1;
uniform vec3 tip_glow : source_color = vec3(0.95, 0.9, 0.55);

varying vec3 world_pos;
varying float height01;

void vertex() {
	float above = max(VERTEX.y - ground_y, 0.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Rolling gust: a travelling wave across the field + a little flutter.
	float wave = sin(TIME * sway_speed - wp.x * 0.45 - wp.z * 0.2);
	float flutter = sin(TIME * 3.1 + wp.x * 3.0 + wp.z * 2.3) * 0.25;
	float k = above * above * 2.2 * wind_mul();
	VERTEX.x += (wave + flutter) * sway_strength * k;
	VERTEX.z += (wave * 0.4 - flutter) * sway_strength * 0.5 * k;
	height01 = clamp(above / 1.1, 0.0, 1.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	// Sun-kissed tips.
	col = mix(col, col + tip_glow * 0.18, smoothstep(0.55, 1.0, height01));
	col = apply_weather(col, 0.0);
	col = apply_outside(col, world_pos.xz);
	ALBEDO = col;
	ALPHA = COLOR.a;
	BACKLIGHT = vec3(0.25, 0.35, 0.12) * height01;
	ROUGHNESS = 1.0;
}
