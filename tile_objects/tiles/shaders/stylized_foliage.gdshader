shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// =============================================================
//  Stylized Tree Foliage  (canopy blobs on the tree tile)
//  - Toon three-tone leaves, clumpy procedural shading.
//  - Wind sway in the vertex stage: displacement grows with
//    object-space height, so the top of the canopy sways while
//    it stays anchored to the trunk.
// =============================================================

group_uniforms Palette;
uniform vec3 leaf_dark   : source_color = vec3(0.07, 0.26, 0.10);
uniform vec3 leaf_mid    : source_color = vec3(0.16, 0.45, 0.17);
uniform vec3 leaf_bright : source_color = vec3(0.42, 0.68, 0.28);
group_uniforms;

group_uniforms Wind;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.3;
uniform float wind_strength : hint_range(0.0, 0.4) = 0.09;
uniform vec2 wind_dir = vec2(1.0, 0.4);
group_uniforms;

group_uniforms Pattern;
uniform float clump_scale : hint_range(1.0, 16.0) = 6.0;
uniform float pattern_contrast : hint_range(0.2, 3.0) = 1.1;
group_uniforms;

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	// Sway more the higher/farther the vertex is from the canopy base.
	vec2 wd = normalize(wind_dir);
	float phase = TIME * wind_speed + VERTEX.x * 1.4 + VERTEX.z * 1.4;
	float sway = sin(phase);
	float reach = max(VERTEX.y, 0.0) + 0.35;
	VERTEX.x += wd.x * sway * wind_strength * reach;
	VERTEX.z += wd.y * sway * wind_strength * reach;

	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fbm(world_pos.xz * clump_scale + world_pos.y * 2.0);
	n = clamp((n - 0.5) * pattern_contrast + 0.5, 0.0, 1.0);

	vec3 col = mix(leaf_dark, leaf_mid, smoothstep(0.2, 0.6, n));
	col = mix(col, leaf_bright, smoothstep(0.6, 1.0, n));

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
