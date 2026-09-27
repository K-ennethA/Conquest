shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// =============================================================
//  Stylized FLAME tongues (burning tiles). A static mesh of small quads
//  (UV = corner, COLOR.a = per-flame phase, COLOR.r = size) billboarded to
//  the camera around the Y axis in the vertex stage; the fragment draws a
//  teardrop flame shape eaten by rising noise, posterized into 3 hot bands
//  (the painterly/cel read, no textures, no particles).
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"

uniform vec3 col_outer : source_color = vec3(0.95, 0.28, 0.05);
uniform vec3 col_mid : source_color = vec3(1.0, 0.62, 0.12);
uniform vec3 col_core : source_color = vec3(1.0, 0.93, 0.6);
uniform float intensity = 1.6;

varying vec2 q;
varying float phase;

void vertex() {
	phase = COLOR.a * 6.2831;
	float size = mix(0.28, 0.55, COLOR.r);
	q = UV;
	vec2 c = UV * 2.0 - 1.0;
	vec3 cam_right = normalize((INV_VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz * vec3(1.0, 0.0, 1.0));
	float flick = 1.0 + 0.12 * sin(TIME * 9.0 + phase * 3.0);
	vec3 wc = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wp = wc + cam_right * c.x * size * 0.45 + vec3(0.0, 1.0, 0.0) * (UV.y) * size * 1.35 * flick;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(q.x * 2.0 - 1.0, q.y);   // x -1..1, y 0 (base) .. 1 (tip)
	float t = TIME * 2.2 + phase;
	float n = fbm(vec2(p.x * 2.0 + phase, p.y * 2.5 - t));
	// Teardrop: wide at the base, pinched at the tip, wobbling sideways.
	float wob = sin(p.y * 5.0 - t * 1.3) * 0.12 * p.y;
	float w = mix(0.95, 0.05, pow(p.y, 0.8));
	float d = abs(p.x + wob) / max(w, 0.001);
	float shape = 1.0 - smoothstep(0.55, 1.0, d + (n - 0.5) * 0.9 + p.y * 0.25);
	shape *= smoothstep(0.0, 0.08, p.y);
	float heat = shape * (1.0 - p.y * 0.7) + (n - 0.5) * 0.3;
	vec3 col = col_outer;
	col = mix(col, col_mid, step(0.45, heat));
	col = mix(col, col_core, step(0.72, heat));
	ALBEDO = col * shape * intensity;
}
