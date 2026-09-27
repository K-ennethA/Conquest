// Screen-space weather layer drawn over the 3D board, under the HUD (WeatherFX).
// canvas_item only -> identical in Compatibility (OpenGL 3) and Forward+.
// Each weather contributes by its cross-fade weight (0..1).
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float sun_amt = 0.0;
uniform float rain_amt = 0.0;
uniform float sand_amt = 0.0;
uniform float bloom_amt = 0.0;
uniform vec2 sun_pos = vec2(0.30, -0.12);
uniform float aspect = 1.7778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec3 add_rgb = vec3(0.0);
	vec4 mix_col = vec4(0.0);

	// --- Bright sun: warm glare in the corner + slow god rays fanning out.
	if (sun_amt > 0.001) {
		vec2 d = uv - sun_pos;
		d.x *= aspect;
		float r = length(d);
		float ang = atan(d.y, d.x);
		float rays = 0.5 + 0.5 * sin(ang * 23.0 + sin(ang * 5.0 + TIME * 0.25) * 2.2 + TIME * 0.08);
		rays *= 0.5 + 0.5 * sin(ang * 9.0 - TIME * 0.11);
		rays = pow(rays, 2.5);
		float fall = exp(-r * 0.75);
		vec3 warm = vec3(1.0, 0.82, 0.52);
		add_rgb += warm * rays * fall * 0.24 * sun_amt;
		add_rgb += warm * exp(-r * 5.0) * 0.55 * sun_amt;
		add_rgb += vec3(1.0, 0.9, 0.7) * 0.035 * sun_amt;
	}

	// --- Rain: cool dim vignette + faint sheets of rain moving across the screen.
	if (rain_amt > 0.001) {
		vec2 c = uv - 0.5;
		c.x *= aspect;
		float vig = smoothstep(0.45, 1.25, length(c));
		vec2 sp = vec2(uv.x * 38.0 + uv.y * 7.0, uv.y * 2.2 - TIME * 3.4);
		float sheet = smoothstep(0.62, 0.95, noise(sp)) * 0.10;
		float gust = fbm(vec2(uv.x * 2.0 - TIME * 0.35, uv.y * 1.5)) ;
		mix_col = vec4(0.16, 0.2, 0.28, (vig * 0.38 + 0.05 + gust * 0.06) * rain_amt);
		add_rgb += vec3(0.7, 0.8, 1.0) * sheet * rain_amt;
	}

	// --- Desert storm: orange haze of billowing sand, thicker at the top (sky).
	if (sand_amt > 0.001) {
		vec2 p = vec2(uv.x * 3.0 * aspect - TIME * 0.55, uv.y * 3.0 + TIME * 0.05);
		float n = fbm(p);
		float n2 = fbm(p * 2.3 + vec2(-TIME * 0.9, 0.0));
		float band = mix(1.0, 0.55, uv.y);
		float a = (0.18 + 0.30 * n * band + 0.12 * n2) * sand_amt;
		vec3 sand = mix(vec3(0.72, 0.48, 0.26), vec3(0.95, 0.75, 0.48), n2);
		mix_col = vec4(mix(mix_col.rgb, sand, a / max(a + mix_col.a, 0.001)), clamp(mix_col.a + a, 0.0, 0.75));
	}

	// --- Overbloom: soft pastel glow creeping in from the edges.
	if (bloom_amt > 0.001) {
		vec2 c = uv - 0.5;
		c.x *= aspect;
		float edge = smoothstep(0.35, 1.2, length(c));
		float shimmer = 0.5 + 0.5 * sin(TIME * 0.6 + uv.x * 3.0 + uv.y * 2.0);
		vec3 pastel = mix(vec3(1.0, 0.62, 0.85), vec3(1.0, 0.9, 0.55), uv.y + 0.2 * shimmer);
		add_rgb += pastel * edge * 0.22 * bloom_amt;
		add_rgb += vec3(1.0, 0.85, 0.95) * 0.03 * bloom_amt;
	}

	// Composite (premultiplied): out = rgb + dst * (1 - a). The haze/tint part is a
	// normal "over" blend; the light part is purely additive (it adds no alpha).
	COLOR = vec4(mix_col.rgb * mix_col.a + add_rgb, mix_col.a);
}
