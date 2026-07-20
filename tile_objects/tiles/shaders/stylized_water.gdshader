shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

// =============================================================
//  Stylized Animated Water  (top-down tactics tiles)
//  - Fully procedural, no textures.
//  - World-position driven, so adjacent water tiles form one
//    continuous, seamless body of water.
//  - Two layers of scrolling noise = drifting ripples; bright
//    crests read as toon foam.
// =============================================================

group_uniforms Palette;
uniform vec3 water_deep    : source_color = vec3(0.04, 0.20, 0.45);
uniform vec3 water_shallow : source_color = vec3(0.13, 0.46, 0.72);
uniform vec3 foam_color    : source_color = vec3(0.82, 0.95, 1.0);
group_uniforms;

group_uniforms Waves;
uniform float wave_scale : hint_range(0.5, 10.0) = 2.6;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.5;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.55;
group_uniforms;

group_uniforms Edges;
uniform float edge_foam : hint_range(0.0, 1.0) = 0.45;
uniform float edge_softness : hint_range(0.5, 1.0) = 0.72;
group_uniforms;

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = world_pos.xz;
	float t = TIME * wave_speed;

	// Two layers drifting in different directions -> lively ripples.
	float n1 = fbm(wp * wave_scale + vec2(t, t * 0.5));
	float n2 = fbm(wp * wave_scale * 1.7 - vec2(t * 0.7, t * 0.35));
	float waves = (n1 + n2) * 0.5;

	vec3 col = mix(water_deep, water_shallow, smoothstep(0.30, 0.72, waves));

	// Foam on the brightest crests.
	float foam = smoothstep(1.0 - foam_amount * 0.6, 1.0, waves + n1 * 0.2);
	col = mix(col, foam_color, foam);

	// Foam ring at tile edges (shoreline feel, and keeps grid readable).
	vec2 e = abs(UV - 0.5) * 2.0;
	float edge = max(e.x, e.y);
	col = mix(col, foam_color, edge_foam * smoothstep(edge_softness, 1.0, edge));

	ALBEDO = col;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	RIM = 0.2;
}
