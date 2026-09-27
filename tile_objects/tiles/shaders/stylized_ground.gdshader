shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

// =============================================================
//  Generic Stylized Painterly Ground (snow, ice, ash, obsidian, tundra,
//  sacred stone...). One shader, one shared material per terrain kind, so
//  every kind reads with the same painterly language as the grass:
//  world-space (seamless across neighbours), broad colour drift,
//  domain-warped brush dabs posterized into a few tones, optional
//  cellular cracks (ice / obsidian / dry earth), sparse specks
//  (pebbles, glitter), toon lighting. No per-tile edges.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"

group_uniforms Palette;
uniform vec3 col_dark  : source_color = vec3(0.45, 0.45, 0.45);
uniform vec3 col_mid   : source_color = vec3(0.60, 0.60, 0.60);
uniform vec3 col_light : source_color = vec3(0.78, 0.78, 0.78);
uniform vec3 speck_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 crack_color : source_color = vec3(0.2, 0.2, 0.2);
uniform vec3 glow_color : source_color = vec3(0.0, 0.0, 0.0);
group_uniforms;

group_uniforms Pattern;
uniform float dab_scale : hint_range(0.2, 8.0) = 1.8;
uniform float drift_scale : hint_range(0.01, 1.0) = 0.12;
uniform float contrast : hint_range(0.2, 3.0) = 1.4;
uniform float speck_density : hint_range(0.0, 1.0) = 0.12;
uniform float speck_scale : hint_range(1.0, 12.0) = 4.5;
uniform float crack_amount : hint_range(0.0, 1.0) = 0.0;
uniform float crack_scale : hint_range(0.2, 4.0) = 1.2;
uniform float glow_strength : hint_range(0.0, 4.0) = 0.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 1.0;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float edge_dist(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash21(i + g), hash21(i + g + 11.7));
			float d = length(g + o - f);
			if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
		}
	}
	return f2 - f1;
}

void fragment() {
	vec2 wp = world_pos.xz;
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near_amt = 1.0 - smoothstep(12.0, 46.0, cam_dist);

	float drift = fbm(wp * drift_scale + vec2(2.1, 7.7));
	vec2 warp = vec2(fbm(wp * 0.8 + 1.1), fbm(wp * 0.8 + 6.3)) * 1.5;
	float dabs = fbm(wp * dab_scale + warp);
	float t = clamp((mix(dabs, drift, 0.35) - 0.5) * contrast + 0.5, 0.0, 1.0);
	t = floor(t * 5.0 + 0.5) / 5.0 * 0.6 + t * 0.4;
	vec3 col = mix(col_dark, col_mid, smoothstep(0.0, 0.5, t));
	col = mix(col, col_light, smoothstep(0.5, 1.0, t));

	float glow = 0.0;
	if (crack_amount > 0.0) {
		float e = edge_dist(wp * crack_scale + warp * 0.35);
		float crack = 1.0 - smoothstep(0.015, 0.06, e);
		col = mix(col, crack_color, crack * crack_amount * (0.5 + 0.5 * near_amt));
		glow = crack * crack_amount;
	}

	// Specks (pebbles / glitter), near only.
	vec2 sp = wp * speck_scale;
	vec2 si = floor(sp);
	vec2 so = vec2(hash21(si), hash21(si + 5.3));
	float sd = length(fract(sp) - so * 0.8 - 0.1);
	if (hash21(si + 2.7) < speck_density) {
		col = mix(col, speck_color, (1.0 - smoothstep(0.06, 0.12, sd)) * near_amt);
	}

	float wny = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	col *= mix(0.7, 1.0, smoothstep(0.2, 0.8, wny));

	col = apply_grid(col, world_pos, cam_dist);
	col = apply_weather(col, 1.0);
	col = apply_outside(col, wp);
	ALBEDO = col;
	EMISSION = glow_color * glow * glow_strength;
	ROUGHNESS = weather_roughness(roughness_base);
	SPECULAR = max(specular_amount, weather_wetness * 0.5);
}
