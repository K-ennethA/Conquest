shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// =============================================================
//  Stylized Animated Grass  (top-down tactics tiles)
//  - Fully procedural: needs NO texture assets.
//  - Pattern is driven by WORLD position, so every grass tile
//    sharing this material forms ONE continuous, seamless field.
//  - Gentle wind ripple so the grass reads as "alive".
//  - Toon diffuse for a clean, non-realistic animated look.
//  Reuse: assign this same material to any grass tile.
// =============================================================

group_uniforms Palette;
uniform vec3 grass_dark   : source_color = vec3(0.09, 0.28, 0.12);
uniform vec3 grass_mid    : source_color = vec3(0.22, 0.52, 0.20);
uniform vec3 grass_bright : source_color = vec3(0.50, 0.74, 0.32);
group_uniforms;

group_uniforms Pattern;
// Higher = finer/denser vertical blade streaks.
uniform float blade_scale : hint_range(1.0, 30.0) = 9.0;
// Size of the lighter/darker grass clumps (tufts).
uniform float tuft_scale : hint_range(0.25, 8.0) = 2.0;
// Push the two-tone contrast up or down.
uniform float pattern_contrast : hint_range(0.2, 3.0) = 1.15;
group_uniforms;

group_uniforms Wind;
uniform float wind_speed : hint_range(0.0, 3.0) = 0.4;
uniform float wind_strength : hint_range(0.0, 0.6) = 0.14;
uniform vec2 wind_dir = vec2(1.0, 0.35);
group_uniforms;

group_uniforms Edges;
// Subtle darkening at tile borders keeps the grid readable for units/cursor.
uniform float edge_darken : hint_range(0.0, 0.8) = 0.22;
uniform float edge_softness : hint_range(0.5, 1.0) = 0.78;
group_uniforms;

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = world_pos.xz;

	// Wind: slowly oscillating offset so the whole pattern ripples.
	vec2 wdir = normalize(wind_dir);
	float gust = sin(TIME * wind_speed + wp.x * 0.6 + wp.y * 0.4) * 0.5 + 0.5;
	vec2 wind = wdir * gust * wind_strength;
	wp += wind;

	// Vertical blade streaks (stretched noise) + soft tuft clumps.
	float blades = vnoise(vec2(wp.x * blade_scale, wp.y * blade_scale * 0.22));
	float tuft = fbm(wp * tuft_scale + wind * 2.0);
	float t = mix(blades, tuft, 0.5);
	t = clamp((t - 0.5) * pattern_contrast + 0.5, 0.0, 1.0);

	// Three-tone stylized ramp.
	vec3 col = mix(grass_dark, grass_mid, smoothstep(0.0, 0.6, t));
	col = mix(col, grass_bright, smoothstep(0.55, 1.0, t));

	// Edge darkening (uses per-face UV of the box top).
	vec2 e = abs(UV - 0.5) * 2.0;
	float edge = max(e.x, e.y);
	col *= 1.0 - edge_darken * smoothstep(edge_softness, 1.0, edge);

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
