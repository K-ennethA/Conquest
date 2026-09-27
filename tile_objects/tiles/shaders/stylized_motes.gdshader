shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// =============================================================
//  Soft floating light MOTES (sacred meadow / shrine / healing glow).
//  Each mote is a tiny quad; UV.x/UV.y give the quad corner and COLOR.a a
//  per-mote phase. The quad is billboarded to the camera in the vertex stage
//  and bobs / drifts / twinkles, so a whole tile's motes are ONE static mesh
//  (no particles, no per-frame CPU).
// =============================================================

#include "res://tile_objects/tiles/shaders/noise_lib.gdshaderinc"
#include "res://tile_objects/tiles/shaders/world_lib.gdshaderinc"

uniform vec3 mote_color : source_color = vec3(1.0, 0.86, 0.45);
uniform float mote_size = 0.07;
uniform float rise = 0.35;
uniform float energy = 1.4;

varying float twinkle;
varying vec2 corner;

void vertex() {
	float ph = COLOR.a * 6.2831;
	float t = TIME * 0.35 + ph;
	vec3 centre = VERTEX;
	centre.y += fract(t * 0.25 + COLOR.a) * rise + sin(t * 1.7) * 0.05;
	centre.x += sin(t * 1.3 + ph) * 0.08;
	centre.z += cos(t * 1.1 + ph * 1.3) * 0.08;
	corner = UV * 2.0 - 1.0;
	vec3 cam_right = (INV_VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	vec3 cam_up = (INV_VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	// Model -> world is a pure translation for tiles; billboard in world space.
	vec3 wcentre = (MODEL_MATRIX * vec4(centre, 1.0)).xyz;
	float s = mote_size * (1.0 + weather_bloom);
	vec3 wp = wcentre + (cam_right * corner.x + cam_up * corner.y) * s;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	float life = fract(t * 0.25 + COLOR.a);
	twinkle = (0.55 + 0.45 * sin(TIME * 4.0 + ph * 3.0)) * smoothstep(0.0, 0.2, life) * (1.0 - smoothstep(0.7, 1.0, life));
}

void fragment() {
	float d = length(corner);
	float a = (1.0 - smoothstep(0.1, 1.0, d));
	a *= a;
	ALBEDO = mote_color * a * twinkle * energy * (1.0 + weather_bloom);
}
