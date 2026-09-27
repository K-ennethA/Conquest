shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// =============================================================
//  Painterly ground DECAL for tile effects / hazards: a flat quad laid on a
//  cell (UV 0..1) that paints a soft, noisy, animated patch in the world's
//  brush language instead of a flat tinted square.
//    kind 0  generic   soft tinted glow ring
//    kind 1  fire      charred scorch + glowing ember cracks
//    kind 2  poison    bubbling toxic puddle + drifting mist
//    kind 3  ice       frost bloom with crystalline cracks and sparkle
//    kind 4  heal      warm radiant ring + rune dots (sacred / healing)
//    kind 5  water     rippling puddle
//    kind 6  telegraph pulsing danger ring (hazard sweeps here next)
//    kind 7  fortify   golden rune circle
//  World-space noise => neighbouring cells blend into one patch.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"

uniform int kind = 0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float strength = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float cracks(vec2 p) {
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
	vec2 uv = UV - 0.5;
	vec2 wp = world_pos.xz;
	float r = length(uv) * 2.0;
	float n = fbm(wp * 1.6 + 3.0);
	// Soft organic footprint: a noisy blob rather than a square.
	float blob = 1.0 - smoothstep(0.55, 1.0, r + (n - 0.5) * 0.5);
	vec3 col = tint;
	float a = 0.0;
	vec3 glow = vec3(0.0);
	float t = TIME;

	if (kind == 1) {
		float e = cracks(wp * 2.2 + n);
		float crack = 1.0 - smoothstep(0.02, 0.09, e);
		float flick = 0.6 + 0.4 * sin(t * 5.0 + n * 12.0);
		col = mix(vec3(0.07, 0.05, 0.04), vec3(0.2, 0.1, 0.06), n);
		glow = vec3(1.0, 0.45, 0.08) * crack * flick * 2.5;
		col += glow;
		a = blob * 0.85;
	} else if (kind == 2) {
		float m = fbm(wp * 2.4 + vec2(t * 0.15, -t * 0.1));
		float bub = 0.0;
		vec2 bp = wp * 3.0;
		vec2 bi = floor(bp);
		float life = fract(t * 0.5 + hash21(bi));
		float bd = length(fract(bp) - 0.5 - (vec2(hash21(bi + 1.0), hash21(bi + 2.0)) - 0.5) * 0.5);
		bub = (1.0 - smoothstep(0.05 + life * 0.18, 0.1 + life * 0.18, bd)) * smoothstep(0.03, 0.08 + life * 0.18, bd) * (1.0 - life);
		col = mix(vec3(0.18, 0.32, 0.08), vec3(0.55, 0.85, 0.2), m);
		col = mix(col, vec3(0.8, 1.0, 0.45), bub);
		glow = vec3(0.3, 0.6, 0.1) * (m * 0.4 + bub);
		a = blob * (0.6 + 0.3 * m);
	} else if (kind == 3) {
		float e = cracks(wp * 3.0);
		float crack = 1.0 - smoothstep(0.01, 0.05, e);
		float sparkle = step(0.985, hash21(floor(wp * 18.0) + floor(t * 2.0)));
		col = mix(vec3(0.72, 0.88, 0.96), vec3(0.92, 0.98, 1.0), n);
		col = mix(col, vec3(1.0), crack * 0.8 + sparkle);
		glow = vec3(0.3, 0.55, 0.7) * (crack * 0.3 + sparkle);
		a = blob * 0.78;
	} else if (kind == 4 || kind == 7) {
		float ring = smoothstep(0.62, 0.7, r) * (1.0 - smoothstep(0.74, 0.86, r));
		float ang = atan(uv.y, uv.x);
		float runes = step(0.5, fract(ang * 1.9098 + 0.25)) * smoothstep(0.52, 0.56, r) * (1.0 - smoothstep(0.58, 0.62, r));
		float pulse = 0.7 + 0.3 * sin(t * 2.0);
		float inner = (1.0 - smoothstep(0.0, 0.7, r)) * 0.25;
		col = tint;
		glow = tint * (ring + runes * 0.8 + inner) * pulse * 1.4;
		a = clamp(ring + runes * 0.8 + inner, 0.0, 1.0) * pulse;
	} else if (kind == 5) {
		float rip = sin(r * 18.0 - t * 3.0) * 0.5 + 0.5;
		col = mix(vec3(0.16, 0.42, 0.62), vec3(0.6, 0.85, 0.95), rip * (1.0 - r) + n * 0.2);
		a = blob * 0.6;
	} else if (kind == 6) {
		float pulse = 0.5 + 0.5 * sin(t * 3.0);
		float edge = smoothstep(0.45, 0.72, r) * (1.0 - smoothstep(0.8, 0.97, r + (n - 0.5) * 0.2));
		float stripes = step(0.5, fract((uv.x + uv.y) * 4.0 - t * 0.6));
		col = tint;
		glow = tint * (edge * 1.2 + stripes * 0.15) * (0.6 + 0.4 * pulse);
		a = (edge * 0.85 + stripes * 0.22 * blob) * (0.55 + 0.45 * pulse);
	} else {
		float ring = smoothstep(0.5, 0.8, r) * blob;
		col = tint;
		glow = tint * ring;
		a = ring * 0.7 + blob * 0.15;
	}
	ALBEDO = col + glow * 0.3;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
