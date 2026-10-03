// Unit glow pass -- the forge palette's per-vertex emission, added over the unit's
// own StandardMaterial3D as its next_pass (attached at import by unit_glow_import.gd).
//
// CUSTOM0 = the forge glow mask: the glb's float _GLOW attribute (HDR, unclamped),
// carried into ARRAY_CUSTOM0 by addons/color1 (stock Godot 4.6 drops it). In the forge
// source the glow colour is already final (palette emission rgb x emission_scale, see
// forge improve/palettes.py) and the Blender material wires it straight into Emission
// Color with the material's Emission Strength -- so emission here is CUSTOM0.rgb x
// glow_energy (= the glb's KHR_materials_emissive_strength), not x albedo.
//
// Additive + unshaded = exactly the emission term a StandardMaterial3D would add, while
// the base material stays a StandardMaterial3D (skin tints, UnitVisualManager overlays
// and the spent-unit transparency fade keep working unchanged). Same vertex stream as
// the base pass, so it depth-matches the opaque surface and only lights what is visible.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float glow_energy = 1.0;

varying vec3 v_glow;

void vertex() {
	v_glow = CUSTOM0.rgb;
}

void fragment() {
	ALBEDO = v_glow * glow_energy;
}
