// =============================================================
//  Painterly GROUND colour functions shared by the grass tile, the dirt /
//  path tile and the world skirt, so all three are literally the same paint.
//  #include after noise_lib + world_lib. Declares its own palette uniforms.
// =============================================================

group_uniforms Palette;
uniform vec3 grass_dark   : source_color = vec3(0.11, 0.26, 0.15);
uniform vec3 grass_mid    : source_color = vec3(0.21, 0.41, 0.20);
uniform vec3 grass_bright : source_color = vec3(0.41, 0.58, 0.27);
// Sun-dried patches blended in by the field tint (warmer, yellower).
uniform vec3 grass_dry    : source_color = vec3(0.50, 0.54, 0.28);
// Cool shadowed clover.
uniform vec3 clover_color : source_color = vec3(0.12, 0.33, 0.24);
// Bare earth / trodden path.
uniform vec3 dirt_dark    : source_color = vec3(0.30, 0.21, 0.14);
uniform vec3 dirt_mid     : source_color = vec3(0.49, 0.36, 0.23);
uniform vec3 dirt_light   : source_color = vec3(0.66, 0.53, 0.36);
group_uniforms;

group_uniforms Pattern;
// Higher = finer/denser brush strokes.
uniform float blade_scale : hint_range(1.0, 30.0) = 5.0;
// Size of the lighter/darker grass clumps (tufts).
uniform float tuft_scale : hint_range(0.25, 8.0) = 1.1;
// Push the two-tone contrast up or down.
uniform float pattern_contrast : hint_range(0.2, 3.0) = 1.0;
// World-space size of the lush <-> dry field drift (smaller = broader patches).
uniform float field_scale : hint_range(0.01, 1.0) = 0.07;
uniform float dry_amount : hint_range(0.0, 1.0) = 0.35;
uniform float clover_amount : hint_range(0.0, 1.0) = 0.55;
uniform float flower_density : hint_range(0.0, 0.2) = 0.012;
group_uniforms;

group_uniforms Wind;
uniform float wind_speed : hint_range(0.0, 3.0) = 0.4;
uniform float wind_strength : hint_range(0.0, 0.6) = 0.12;
uniform vec2 wind_dir = vec2(1.0, 0.35);
group_uniforms;

// Cellular (Worley) distance to the nearest jittered point: soft round blobs.
float cell_dist(vec2 p, out vec2 cell_id) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	cell_id = i;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash21(i + g), hash21(i + g + 17.31));
			float d = length(g + o - f);
			if (d < best) {
				best = d;
				cell_id = i + g;
			}
		}
	}
	return best;
}

// Near-detail factor: procedural detail has no mipmaps, so fade fine detail
// with distance to keep far ground from shimmering into muddy noise.
float ground_near(float cam_dist) {
	return 1.0 - smoothstep(12.0, 46.0, cam_dist);
}

// The painterly grass field (world-space => seamless across tiles).
vec3 grass_color(vec2 base_wp, float near_amt, float time) {
	vec2 wp = base_wp;
	vec2 wdir = normalize(wind_dir);
	float gust = sin(time * wind_speed + wp.x * 0.6 + wp.y * 0.4) * 0.5 + 0.5;
	vec2 wind = wdir * gust * wind_strength * wind_mul();
	wp += wind;

	// 1. Field tint (lush <-> dry), static (no wind) so patches don't swim.
	float field = fbm(base_wp * field_scale + vec2(3.7, 1.3));
	float dry = smoothstep(0.48, 0.72, field) * dry_amount * (1.0 - weather_bloom * 0.6);

	// 2. Painterly strokes: domain-warped fbm, stretched along the wind axis.
	float tuft = fbm(wp * tuft_scale + wind * 2.0);
	float strokes = tuft;
	if (near_amt > 0.0) {
		// (Skipped in the distance, where near_amt fades them out anyway.)
		vec2 side = vec2(-wdir.y, wdir.x);
		vec2 sp = vec2(dot(wp, wdir) * 0.35, dot(wp, side)) * blade_scale;
		vec2 warp = vec2(fbm(wp * 0.9), fbm(wp * 0.9 + 5.2)) * 1.6;
		strokes = fbm(sp + warp);
	}
	float t = mix(tuft, mix(strokes, tuft, 0.35), near_amt);
	t = clamp((t - 0.5) * pattern_contrast * 1.6 + 0.5, 0.0, 1.0);
	// Posterize a little for the hand-painted, cel-shaded read.
	t = floor(t * 5.0 + 0.5) / 5.0 * 0.6 + t * 0.4;

	vec3 col = mix(grass_dark, grass_mid, smoothstep(0.0, 0.55, t));
	col = mix(col, grass_bright, smoothstep(0.5, 1.0, t));
	col = mix(col, mix(col, grass_dry, 0.75), dry);

	// 3. Clover clumps: soft cellular blobs, cooler and a touch darker.
	vec2 cid;
	float cd = cell_dist(base_wp * 1.35, cid);
	float clump_on = step(0.45, hash21(cid + 3.1));
	float clover = (1.0 - smoothstep(0.18, 0.46, cd)) * clump_on * clover_amount * (0.4 + 0.6 * near_amt);
	col = mix(col, clover_color, clover * 0.7);

	// 4. Wildflower specks (near only, rare, colour-varied; more in bloom).
	float fdens = flower_density * (1.0 + weather_bloom * 4.0);
	vec2 fid;
	float fd = cell_dist(base_wp * 5.5, fid);
	float fh = hash21(fid + 9.7);
	if (fh < fdens && near_amt > 0.05) {
		float petal = 1.0 - smoothstep(0.10, 0.16, fd);
		float pick = hash21(fid + 1.9);
		vec3 fcol = pick < 0.4 ? vec3(0.96, 0.95, 0.86)
			: (pick < 0.75 ? vec3(0.98, 0.84, 0.32) : vec3(0.78, 0.66, 0.95));
		float centre = 1.0 - smoothstep(0.0, 0.045, fd);
		fcol = mix(fcol, vec3(0.95, 0.70, 0.20), centre * 0.8);
		col = mix(col, fcol, petal * near_amt * near_amt);
	}
	return col;
}

// Painterly bare earth: broad warm/cool drift, dabbed strokes, darker ruts
// and pale pebble specks. World-space => seamless.
vec3 dirt_color(vec2 wp, float near_amt) {
	float field = fbm(wp * 0.11 + vec2(7.1, 2.3));
	vec2 warp = vec2(fbm(wp * 0.7 + 1.3), fbm(wp * 0.7 + 9.1)) * 1.4;
	float dabs = fbm(wp * 2.2 + warp);
	float t = clamp((dabs - 0.5) * 1.7 + 0.5, 0.0, 1.0);
	t = floor(t * 4.0 + 0.5) / 4.0 * 0.55 + t * 0.45;
	vec3 col = mix(dirt_dark, dirt_mid, smoothstep(0.0, 0.5, t));
	col = mix(col, dirt_light, smoothstep(0.55, 1.0, t) * 0.8);
	col *= mix(0.92, 1.06, field);
	// Worn ruts: long soft darker streaks.
	float rut = fbm(vec2(wp.x * 0.35, wp.y * 2.6) + warp * 0.3);
	col = mix(col, dirt_dark, smoothstep(0.62, 0.8, rut) * 0.35);
	// Pebble specks (near only).
	vec2 pid;
	float pd = cell_dist(wp * 4.0, pid);
	if (hash21(pid + 4.4) < 0.18 && near_amt > 0.05) {
		float peb = 1.0 - smoothstep(0.07, 0.13, pd);
		vec3 pc = mix(vec3(0.62, 0.58, 0.52), vec3(0.78, 0.74, 0.66), hash21(pid + 2.0));
		col = mix(col, pc, peb * near_amt);
	}
	return col;
}

// Soft sparse grass fringe amount on bare dirt next to grass: the mask's grass
// channel, warped by noise and broken into strokes, so edges read hand-painted.
float grass_fringe(vec2 wp) {
	vec4 m = terrain_at_warped(wp, 0.9);
	float g = m.a;
	float n = fbm(wp * 3.1 + 2.0);
	return smoothstep(0.30, 0.62, g + (n - 0.5) * 0.55);
}
