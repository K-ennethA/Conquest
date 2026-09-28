shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

// =============================================================
//  Painterly vertex-coloured PROPS: castle masonry, parapets, stairs,
//  bridges, flagstones, planks, rocks (ProcMesh / PavedTileBuilder /
//  FloorDecor / world skirt). The vertex colour is the base paint; this
//  shader adds the same world-space brush-dab language as the ground:
//   * stone: mottled dabs + pale weathering + moss creeping onto upward
//     faces, darker at the foot (fake contact occlusion);
//   * wood (warm hue): long grain streaks along the plank;
//   * weather + outside-board haze + optional grid on walkable tops.
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"

// Vertex colours are used as-is (the project's decor convention), so this
// colour is too (no source_color conversion) to stay in the same space.
uniform vec3 moss_color = vec3(0.42, 0.52, 0.28);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.25;
uniform float dab_strength : hint_range(0.0, 1.0) = 0.5;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 n = abs(world_nrm);
	// Planar projection picked by the dominant normal axis (cheap triplanar).
	vec2 uv = n.y > 0.6 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near_amt = 1.0 - smoothstep(12.0, 50.0, cam_dist);

	float warmth = COLOR.r - COLOR.b;          // wood is clearly warm
	float is_wood = smoothstep(0.12, 0.2, warmth);
	vec2 warp = vec2(fbm(uv * 1.3 + 2.0), fbm(uv * 1.3 + 7.0)) * 0.8;
	float dabs = fbm(uv * 3.2 + warp);
	float stone_mod = mix(0.82, 1.14, floor(dabs * 5.0 + 0.5) / 5.0 * 0.6 + dabs * 0.4);
	// Wood grain: stretched along the longer horizontal axis of the plank.
	vec2 gu = n.y > 0.6 ? world_pos.zx : uv;
	float grain = fbm(vec2(gu.x * 0.8, gu.y * 14.0) + warp);
	float wood_mod = mix(0.84, 1.1, grain);
	vec3 col = base * mix(1.0, mix(stone_mod, wood_mod, is_wood), dab_strength * 2.0 * (0.5 + 0.5 * near_amt));

	// Stone weathering: pale chalky dabs + moss on up faces.
	float up = smoothstep(0.55, 0.95, world_nrm.y);
	float moss_n = fbm(world_pos.xz * 0.9 + world_pos.y * 0.5 + 11.0);
	float moss = smoothstep(0.55, 0.75, moss_n) * moss_amount * (1.0 - is_wood) * (0.25 + 0.75 * up);
	col = mix(col, moss_color * (0.8 + 0.4 * dabs), moss * 0.6);

	// Fake contact occlusion at the foot of each floor (floors are 2.5 apart).
	float yl = mod(world_pos.y + 0.4, 2.5) - 0.4;
	col *= mix(0.72, 1.0, smoothstep(0.05, 0.6, yl) * (1.0 - up * 0.6) + up * 0.6);

	if (world_nrm.y > 0.9) {
		col = apply_grid(col, world_pos, cam_dist);
	}
	col = apply_weather(col, 0.5);
	col = apply_outside(col, world_pos.xz);
	ALBEDO = col;
	ROUGHNESS = weather_roughness(0.95);
	SPECULAR = weather_wetness * 0.5;
}
