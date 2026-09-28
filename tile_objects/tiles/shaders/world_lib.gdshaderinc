// =============================================================
//  Shared WORLD helpers for every stylized world shader (ground, water,
//  lava, foliage, props, world skirt). #include AFTER noise_lib.
//
//  Reads project-wide GLOBAL shader uniforms (declared in project.godot
//  [shader_globals]; see docs/WORLD_ART.md):
//
//   Board / terrain (driven by game/visuals/world/TerrainMask.gd on map load)
//     terrain_mask       RGBA per-cell classes of floor 0 (+ a margin ring
//                        that continues the edge biome into the world skirt):
//                        R = water, G = dirt/path, B = lava, A = grass-ish.
//                        Linear-filtered: blends 50/50 exactly on cell borders.
//     terrain_mask_rect  xy = world XZ of the texture's (0,0) corner,
//                        zw = world XZ size covered by the texture.
//     terrain_mask_on    1 once a map has written the mask (0 = ignore it).
//     board_rect         playable area in world XZ: (min_x, min_z, max_x, max_z).
//     grid_lines         0 = off, 1 = subtle cell grid (Settings: Grid lines).
//     haze_color         colour the far landscape fades into (sky / backdrop).
//
//   Weather hooks (driven by the weather system; defaults = normal look)
//     weather_wetness  0..1 darker, glossier ground, stronger water ripples
//     weather_dust     0..1 tan tint / haze on ground & foliage
//     weather_bloom    0..1 extra flowers / saturation, glowing specks
//     weather_sun      0..1 warmer, brighter highlights
//     wind_strength_global  multiplier for all sway (1 = authored)
// =============================================================

global uniform sampler2D terrain_mask : filter_linear, repeat_disable;
global uniform vec4 terrain_mask_rect;
global uniform float terrain_mask_on;
global uniform vec4 board_rect;
global uniform float grid_lines;
global uniform vec3 haze_color;
global uniform float weather_wetness;
global uniform float weather_dust;
global uniform float weather_bloom;
global uniform float weather_sun;
global uniform float wind_strength_global;

const float CELL_SIZE = 2.0;

// Terrain classes around a world XZ point (smoothly blended across cells).
// Returns vec4(0) when no map has published a mask.
vec4 terrain_at(vec2 wxz) {
	if (terrain_mask_on < 0.5 || terrain_mask_rect.z <= 0.0) {
		return vec4(0.0);
	}
	vec2 uv = (wxz - terrain_mask_rect.xy) / terrain_mask_rect.zw;
	return textureLod(terrain_mask, uv, 0.0);
}

// Same, but with a noisy domain warp so class borders read as organic,
// painted edges instead of straight cell lines.
vec4 terrain_at_warped(vec2 wxz, float amount) {
	vec2 w = vec2(fbm(wxz * 0.9 + 3.1), fbm(wxz * 0.9 + 8.7)) - 0.5;
	return terrain_at(wxz + w * amount);
}

// Distance (world units) outside the playable board; 0 inside.
float outside_board(vec2 wxz) {
	if (board_rect.z <= board_rect.x) {
		return 0.0;
	}
	vec2 d = max(board_rect.xy - wxz, wxz - board_rect.zw);
	return length(max(d, vec2(0.0)));
}

// Subtle cell grid (only where grid_lines is on and inside the board).
float grid_line_mask(vec3 wp, float cam_dist) {
	if (grid_lines < 0.01 || outside_board(wp.xz) > 0.0) {
		return 0.0;
	}
	vec2 g = abs(fract(wp.xz / CELL_SIZE + 0.5) - 0.5) * CELL_SIZE; // dist to line
	float w = 0.025 + cam_dist * 0.0012;
	float l = 1.0 - smoothstep(w, w * 2.2, min(g.x, g.y));
	return l * grid_lines;
}

vec3 apply_grid(vec3 col, vec3 wp, float cam_dist) {
	float g = grid_line_mask(wp, cam_dist);
	return mix(col, col * 0.62 + vec3(0.02, 0.03, 0.02), g * 0.75);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Weather tinting for any lit world surface. `ground` = 1 for ground, 0 for
// foliage / props (wetness darkens ground more).
vec3 apply_weather(vec3 col, float ground) {
	float l = luma(col);
	// Bloom: richer saturation.
	col = mix(vec3(l), col, 1.0 + weather_bloom * 0.35);
	// Sun: warmer, slightly brighter.
	col *= mix(vec3(1.0), vec3(1.12, 1.05, 0.9), weather_sun);
	// Dust: tan wash.
	col = mix(col, vec3(0.72, 0.6, 0.42) * (0.55 + l), weather_dust * 0.45);
	// Wetness: darker, more saturated ground.
	col *= 1.0 - weather_wetness * mix(0.18, 0.35, ground);
	return col;
}

// Roughness under weather (wet = glossy).
float weather_roughness(float r) {
	return mix(r, r * 0.35, weather_wetness);
}

// Out-of-bounds treatment for the world skirt: a touch darker / desaturated
// just outside the board, fading into the haze colour far away.
vec3 apply_outside(vec3 col, vec2 wxz) {
	float o = outside_board(wxz);
	if (o <= 0.0) {
		return col;
	}
	float near_dim = smoothstep(0.0, 1.2, o);
	float l = luma(col);
	col = mix(col, vec3(l) * vec3(0.96, 1.0, 1.03), near_dim * 0.38);
	col *= 1.0 - near_dim * 0.2;
	// Soft occlusion line hugging the board's edge (the foot of its rim).
	col *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.7, o));
	float haze = smoothstep(4.0, 70.0, o);
	haze = sqrt(haze);
	return mix(col, haze_color, haze * 0.9);
}

float wind_mul() {
	return max(wind_strength_global, 0.0);
}
