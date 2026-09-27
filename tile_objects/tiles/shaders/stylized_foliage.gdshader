shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// =============================================================
//  Stylized painterly FOLIAGE (tree canopies, pine tiers, bushes).
//  - Shaded by the WORLD normal into a painted ramp: sunlit top, mid
//    leaf body, cool blue-green shadowed underside, warm rim on the
//    silhouette -- on top of the (toon) scene lighting.
//  - Leaf-cluster breakup: cellular dabs in object space, posterized, so
//    each blob reads as clumps of leaves, not a smooth ball.
//  - Per-TREE variation without per-tree materials: the node origin
//    (MODEL_MATRIX[3]) is hashed into a lush / olive / autumn hue shift.
//    COLOR.r (vertex) picks the palette: 0 = broadleaf, 1 = conifer.
//  - Gentle canopy sway (height-weighted, world-phased) x wind_strength_global.
//  - Cursor see-through: canopy fragments between the camera and the
//    cursor focus point dither away (focus_world global), so units behind
//    trees stay visible and selectable.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"

global uniform vec4 focus_world;

group_uniforms Palette;
uniform vec3 leaf_shadow : source_color = vec3(0.07, 0.20, 0.19);
uniform vec3 leaf_dark   : source_color = vec3(0.11, 0.30, 0.13);
uniform vec3 leaf_mid    : source_color = vec3(0.22, 0.43, 0.17);
uniform vec3 leaf_bright : source_color = vec3(0.50, 0.64, 0.27);
uniform vec3 pine_dark   : source_color = vec3(0.05, 0.19, 0.15);
uniform vec3 pine_mid    : source_color = vec3(0.12, 0.33, 0.22);
uniform vec3 pine_bright : source_color = vec3(0.30, 0.52, 0.30);
uniform vec3 autumn_mid  : source_color = vec3(0.78, 0.42, 0.12);
uniform vec3 autumn_bright : source_color = vec3(0.98, 0.72, 0.26);
uniform vec3 rim_color   : source_color = vec3(0.95, 0.92, 0.6);
uniform vec3 snow_color  : source_color = vec3(0.92, 0.95, 1.0);
group_uniforms;

group_uniforms Variation;
uniform float autumn_chance : hint_range(0.0, 1.0) = 0.18;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

group_uniforms Wind;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.1;
uniform float wind_strength : hint_range(0.0, 0.4) = 0.045;
uniform vec2 wind_dir = vec2(1.0, 0.4);
group_uniforms;

group_uniforms Pattern;
uniform float clump_scale : hint_range(1.0, 16.0) = 4.2;
group_uniforms;

varying vec3 world_pos;
varying vec3 obj_pos;
varying vec3 world_nrm;
varying float tree_hash;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	tree_hash = hash21(origin.xz * 0.37 + 1.3);
	vec2 wd = normalize(wind_dir);
	float phase = TIME * wind_speed + origin.x * 0.35 + origin.z * 0.27;
	float reach = max(VERTEX.y - 0.4, 0.0);
	float sway = sin(phase) + 0.3 * sin(phase * 2.3 + VERTEX.x * 3.0);
	vec2 d = wd * sway * wind_strength * reach * wind_mul();
	VERTEX.x += d.x;
	VERTEX.z += d.y;
	obj_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Leaf-cluster cells (2D Worley over a slanted object-space projection: 9 taps,
// cheap enough for a whole forest of MultiMesh trees).
float cell_blob(vec3 p) {
	vec2 q = p.xz + vec2(p.y * 0.8, -p.y * 0.6);
	vec2 i = floor(q);
	vec2 f = fract(q);
	float best = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash21(i + g), hash21(i + g + 5.3));
			best = min(best, length(g + o - f));
		}
	}
	return best;
}

void fragment() {
	// --- Cursor see-through (screen-door dither, stays in the opaque pass).
	if (focus_world.w > 0.5) {
		vec3 cam = CAMERA_POSITION_WORLD;
		vec3 target = focus_world.xyz + vec3(0.0, 0.6, 0.0);
		vec3 ray = target - cam;
		float len = length(ray);
		vec3 rd = ray / len;
		float along = dot(world_pos - cam, rd);
		if (along < len - 0.35) {
			float perp = length(world_pos - cam - rd * along);
			float fade = 1.0 - smoothstep(0.55, 1.15, perp);
			// Bayer-ish 4x4 threshold.
			vec2 px = mod(floor(FRAGCOORD.xy), 4.0);
			float thr = (mod(px.x * 2.0 + px.y * 3.0, 4.0) * 4.0 + mod(px.x + px.y * 2.0, 4.0)) / 16.0;
			if (fade * 0.8 > thr + 0.03) {
				discard;
			}
		}
	}

	float conifer = step(0.5, COLOR.r);
	float h = tree_hash;
	// Leaf clusters: posterized cellular dabs in object space.
	float cb = cell_blob(obj_pos * clump_scale + h * 13.0);
	float dab = 1.0 - smoothstep(0.25, 0.75, cb);
	float n = fbm(obj_pos.xz * 3.0 + obj_pos.y * 2.0 + h * 9.0);

	// Painted light ramp from the world normal (top lit, underside cool).
	float up = world_nrm.y * 0.5 + 0.5;
	float ramp = clamp(up * 0.85 + dab * 0.35 + (n - 0.5) * 0.3 - 0.15, 0.0, 1.0);
	ramp = floor(ramp * 4.0 + 0.5) / 4.0 * 0.7 + ramp * 0.3;

	vec3 dark = mix(leaf_dark, pine_dark, conifer);
	vec3 mid = mix(leaf_mid, pine_mid, conifer);
	vec3 bright = mix(leaf_bright, pine_bright, conifer);
	// Per-tree hue: lush <-> olive drift, occasional autumn broadleaf.
	float olive = fract(h * 7.31);
	mid = mix(mid, mid * vec3(1.12, 1.04, 0.8), olive * 0.6);
	bright = mix(bright, bright * vec3(1.1, 1.0, 0.75), olive * 0.5);
	float autumn = step(1.0 - autumn_chance, fract(h * 3.17)) * (1.0 - conifer);
	mid = mix(mid, autumn_mid, autumn * 0.85);
	bright = mix(bright, autumn_bright, autumn * 0.85);

	vec3 col = mix(leaf_shadow, dark, smoothstep(0.0, 0.3, ramp));
	col = mix(col, mid, smoothstep(0.25, 0.6, ramp));
	col = mix(col, bright, smoothstep(0.62, 1.0, ramp));

	// Warm rim on the silhouette.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, rim_color * bright * 1.6, fres * 0.35 * up);

	// Optional snow caps (frozen pines).
	col = mix(col, snow_color, snow_amount * smoothstep(0.72, 0.9, up + (n - 0.5) * 0.3));

	col = apply_weather(col, 0.0);
	col = apply_outside(col, world_pos.xz);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.18, 0.24, 0.08);
}
