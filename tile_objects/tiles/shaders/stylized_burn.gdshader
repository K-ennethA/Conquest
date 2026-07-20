shader_type spatial;
render_mode cull_back, diffuse_toon;

// =============================================================
//  Stylized Animated Burn / Scorched tile
//  - Charred dark ground with glowing embers and animated,
//    upward-licking flames (emissive, so it glows in the dark
//    and casts light with SDFGI/GI or a light on the tile).
//  - Fully procedural, world-position driven (seamless field).
// =============================================================

group_uniforms Palette;
uniform vec3 char_dark  : source_color = vec3(0.06, 0.05, 0.05);
uniform vec3 ember      : source_color = vec3(0.55, 0.14, 0.03);
uniform vec3 flame_mid  : source_color = vec3(0.95, 0.35, 0.05);
uniform vec3 flame_hot  : source_color = vec3(1.0, 0.78, 0.20);
group_uniforms;

group_uniforms Fire;
uniform float flame_scale : hint_range(1.0, 12.0) = 5.0;
uniform float flame_speed : hint_range(0.0, 4.0) = 1.6;
uniform float emission_strength : hint_range(0.0, 8.0) = 3.0;
group_uniforms;

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = world_pos.xz;

	// Flames scroll "upward" (−z) and flicker with a second faster field.
	float rise = fbm(vec2(wp.x * flame_scale, wp.y * flame_scale - TIME * flame_speed));
	float flick = fbm(wp * flame_scale * 2.1 + TIME * flame_speed * 1.4);
	float fire = clamp(rise * flick * 2.2, 0.0, 1.0);

	// Embers glowing in the cracks of the charred ground.
	float emb = smoothstep(0.42, 0.72, rise);

	vec3 col = mix(char_dark, ember, emb);
	col = mix(col, flame_mid, smoothstep(0.55, 0.85, fire));
	col = mix(col, flame_hot, smoothstep(0.80, 1.0, fire));

	// Emission: embers glow faintly, flames glow hot.
	vec3 glow = mix(ember * 0.5, mix(flame_mid, flame_hot, fire), fire);
	float glow_mask = max(emb * 0.35, smoothstep(0.45, 1.0, fire));

	ALBEDO = col;
	EMISSION = glow * glow_mask * emission_strength;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
