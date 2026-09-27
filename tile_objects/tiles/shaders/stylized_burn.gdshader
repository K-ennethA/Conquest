shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// =============================================================
//  Stylized Painterly Lava / Burning ground
//  - Cooled basalt CRUST plates (cellular) drifting slowly on a molten
//    river; glowing seams between plates pulse and flow.
//  - Crust thickens toward land (global terrain mask, lava channel) so a
//    lava pool cools at its banks and never shows a square tile edge.
//  - World-space: neighbouring lava tiles form one seamless flow.
//  - Emissive, posterized palette (hot yellow -> orange -> ember red).
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"

group_uniforms Palette;
uniform vec3 char_dark  : source_color = vec3(0.10, 0.07, 0.07);
uniform vec3 crust      : source_color = vec3(0.22, 0.14, 0.12);
uniform vec3 ember      : source_color = vec3(0.62, 0.14, 0.04);
uniform vec3 flame_mid  : source_color = vec3(0.98, 0.42, 0.07);
uniform vec3 flame_hot  : source_color = vec3(1.0, 0.84, 0.36);
group_uniforms;

group_uniforms Fire;
uniform float flame_scale : hint_range(0.2, 6.0) = 1.3;
uniform float flame_speed : hint_range(0.0, 4.0) = 0.35;
uniform float emission_strength : hint_range(0.0, 8.0) = 2.4;
uniform float crust_amount : hint_range(0.0, 1.0) = 0.55;
uniform vec2 flow_dir = vec2(0.6, 1.0);
group_uniforms;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Cellular edge distance (F2 - F1): 0 on the seams between plates.
float plate_edge(vec2 p) {
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
	float t = TIME * flame_speed;
	vec2 fdir = normalize(flow_dir);
	vec2 warp = vec2(fbm(wp * 0.5 + fdir * t * 0.3), fbm(wp * 0.5 + 3.3 - fdir * t * 0.2)) * 1.3;

	// Molten heat field: slow flowing fbm, brighter in the channel centre.
	float heat = fbm(wp * flame_scale * 0.8 + warp - fdir * t);
	float pulse = sin(TIME * 1.7 + heat * 9.0) * 0.5 + 0.5;

	// Crust plates, thicker near the banks.
	float bank = 0.0;
	float rock_rim = 0.0;
	if (terrain_mask_on > 0.5) {
		float lb = terrain_at_warped(wp, 1.1).b;
		bank = 1.0 - smoothstep(0.45, 0.9, lb);
		rock_rim = 1.0 - smoothstep(0.54, 0.62, lb);
	}
	float e = plate_edge(wp * flame_scale + warp * 0.6 - fdir * t * 0.25);
	float cover = crust_amount + bank * 0.45 - heat * 0.35;
	float plate = smoothstep(0.06, 0.16 + (1.0 - cover) * 0.25, e) * step(0.2, cover + 0.15);

	float h = clamp(heat * 1.3 - 0.15 + pulse * 0.15, 0.0, 1.0);
	h = floor(h * 4.0 + 0.5) / 4.0 * 0.6 + h * 0.4;
	vec3 molten = mix(ember, flame_mid, smoothstep(0.1, 0.6, h));
	molten = mix(molten, flame_hot, smoothstep(0.62, 1.0, h));

	float crust_shade = fbm(wp * 3.0 + 5.0);
	vec3 crust_col = mix(char_dark, crust, crust_shade);
	plate = max(plate, rock_rim);
	vec3 col = mix(molten, crust_col, plate);
	// Glowing rim of each plate.
	float rim = (1.0 - smoothstep(0.0, 0.1, e)) * (1.0 - plate);
	vec3 glow = molten * (1.0 - plate) + flame_hot * rim * 0.4;

	float wny = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float side = smoothstep(0.2, 0.8, wny);
	col = mix(crust_col * 0.8, col, side);
	glow *= side;

	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	col = apply_grid(col, world_pos, cam_dist);
	col = apply_outside(col, wp);
	ALBEDO = col;
	EMISSION = glow * emission_strength * (1.0 - smoothstep(10.0, 60.0, outside_board(wp)));
	ROUGHNESS = 1.0;
}
