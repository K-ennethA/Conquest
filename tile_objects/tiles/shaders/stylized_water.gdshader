shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

// =============================================================
//  Stylized Painterly Water
//  - World-space everywhere, so neighbouring water tiles (and the world
//    skirt's rivers / moats) form ONE seamless body of water.
//  - Depth colour: shallow turquoise near the banks deepening to a cool
//    blue in open water. "Distance to land" comes from the global terrain
//    mask (world_lib), so it needs no depth buffer and works in
//    Compatibility too.
//  - Soft animated shoreline foam hugging land, with a second broken foam
//    line lapping in and out.
//  - Gentle flow: two domain-warped layers drifting along flow_dir, posterized
//    into painterly bands, with cellular glints on the crests.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/ground_lib.gdshaderinc"

group_uniforms Palette;
uniform vec3 water_deep    : source_color = vec3(0.07, 0.25, 0.42);
uniform vec3 water_mid     : source_color = vec3(0.11, 0.37, 0.54);
uniform vec3 water_shallow : source_color = vec3(0.2, 0.52, 0.6);
uniform vec3 foam_color    : source_color = vec3(0.84, 0.94, 0.94);
group_uniforms;

group_uniforms Waves;
uniform float wave_scale : hint_range(0.1, 4.0) = 0.9;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.35;
uniform vec2 flow_dir = vec2(0.25, 1.0);
uniform float glint_amount : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

group_uniforms Shore;
uniform float shore_foam : hint_range(0.0, 1.0) = 0.5;
// Mask level below which a water cell paints its bank (organic shoreline).
uniform float shore_line : hint_range(0.0, 0.8) = 0.58;
uniform vec3 mud_color : source_color = vec3(0.24, 0.2, 0.13);
uniform float depth_reach : hint_range(0.5, 6.0) = 2.6;
group_uniforms;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 0 at the waterline -> 1 in open water (approximate distance to land).
float water_depth(vec2 wp) {
	if (terrain_mask_on < 0.5) {
		return 0.8;
	}
	float d = 0.0;
	float r = depth_reach;
	d += terrain_at(wp).r;
	d += terrain_at(wp + vec2(r, 0.0)).r;
	d += terrain_at(wp - vec2(r, 0.0)).r;
	d += terrain_at(wp + vec2(0.0, r)).r;
	d += terrain_at(wp - vec2(0.0, r)).r;
	d += terrain_at(wp + vec2(r, r) * 0.7).r;
	d += terrain_at(wp - vec2(r, r) * 0.7).r;
	d += terrain_at(wp + vec2(r, -r) * 0.7).r;
	d += terrain_at(wp + vec2(-r, r) * 0.7).r;
	return clamp((d / 9.0 - 0.45) / 0.55, 0.0, 1.0);
}

void fragment() {
	vec2 wp = world_pos.xz;
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near_amt = 1.0 - smoothstep(14.0, 50.0, cam_dist);
	float t = TIME * wave_speed;
	vec2 fdir = normalize(flow_dir);
	float rip = 1.0 + weather_wetness * 0.8;

	// Flowing painterly bands.
	vec2 warp = vec2(fbm(wp * 0.35 + fdir * t * 0.6), fbm(wp * 0.35 + 4.3 - fdir * t * 0.4)) * 1.8;
	float n1 = fbm(wp * wave_scale + warp - fdir * t * 1.4);
	float n2 = fbm(wp * wave_scale * 2.3 - warp * 0.5 - fdir * t * 2.1 + 7.0);
	float waves = mix(n1, n2, 0.4 * rip);
	float band = floor(waves * 5.0) / 5.0;

	// Distance-to-land shading (warped so the depth edge isn't a cell grid).
	vec2 wwp = wp + (vec2(fbm(wp * 0.8 + 1.7), fbm(wp * 0.8 + 6.1)) - 0.5) * 0.9;
	float depth = water_depth(wwp);
	float bank_out = 0.0;
	vec3 col = mix(water_shallow, water_mid, smoothstep(0.0, 0.45, depth));
	col = mix(col, water_deep, smoothstep(0.45, 1.0, depth));
	col *= mix(0.9, 1.1, mix(band, waves, 0.5));

	// Crest glints: small bright cellular dabs riding the flow (near only).
	vec2 gp = wp * 2.2 - fdir * t * 1.2 + warp * 0.3;
	float g = fbm(gp * 1.7);
	float glint = smoothstep(0.66, 0.74, g) * glint_amount * (0.35 + 0.65 * near_amt) * rip;
	col = mix(col, foam_color, glint * 0.55);

	// Shoreline foam: a soft band on the waterline plus a broken lapping line.
	if (terrain_mask_on > 0.5) {
		float wet = terrain_at_warped(wp, 1.1).r;          // 1 water .. 0 land
		float lap = sin(TIME * 1.3 + wet * 14.0 + fbm(wp * 1.5) * 4.0) * 0.5 + 0.5;
		// A band hugging the waterline (wet ~0.5 on the cell border), not a fill:
		// water drawn over a low bank (world skirt) stays water, not solid foam.
		float edge = smoothstep(shore_line - 0.02, shore_line + 0.04, wet) * (1.0 - smoothstep(shore_line + 0.06, shore_line + 0.2, wet));
		float ring = smoothstep(0.62, 0.70, wet) * (1.0 - smoothstep(0.74, 0.82, wet)) * lap;
		float brk = smoothstep(0.35, 0.6, fbm(wp * 3.5 + fdir * t));
		float foam = max(edge, ring * brk * 0.8) * shore_foam;
		col = mix(col, foam_color, clamp(foam, 0.0, 1.0));
		// Bank: where the (warped) mask says land, a water cell paints damp turf
		// and a dark mud lip instead -- the pool's outline becomes organic rather
		// than the cell square. Only on up-facing water that borders land.
		if (wet < shore_line) {
			float near_g = ground_near(cam_dist);
			vec3 turf = grass_color(wp, near_g, TIME) * 0.95;
			float mud = smoothstep(shore_line - 0.12, shore_line, wet);
			col = mix(turf, mud_color, mud * 0.85);
			bank_out = 1.0;
		}
	}

	// Water surfaces facing sideways (board edge) read as dark deep water.
	float wny = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	col = mix(water_deep * 0.7, col, smoothstep(0.2, 0.8, wny));

	col = apply_grid(col, world_pos, cam_dist);
	col = apply_weather(col, 0.0);
	col = apply_outside(col, wp);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.22, 0.1, weather_wetness), 1.0, bank_out);
	SPECULAR = 0.55 * (1.0 - bank_out);
	RIM = 0.15 * (1.0 - bank_out);
	RIM_TINT = 0.6;
}
