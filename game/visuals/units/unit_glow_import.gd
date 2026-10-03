@tool
extends EditorScenePostImport
## Import script for forge unit glbs (set as `import_script/path` in each
## game/characters/models/*/*_forge.glb.import). Editor/import-time only.
##
## Every surface that carries the glow mask in CUSTOM0 (addons/color1) gets the shared
## glow pass as its material's next_pass, and the stock glTF emission is switched off:
## the forge glbs export emissiveFactor (1,1,1) x emissive strength, which a stock
## import turns into a uniformly glowing unit. The glb's emissive strength moves to the
## glow pass as glow_energy. The surface material stays a StandardMaterial3D, so skin
## tints (SkinLibrary.tinted_material duplicates it; next_pass rides along) still apply.

const GLOW_SHADER: Shader = preload("res://game/visuals/units/unit_glow.gdshader")


func _post_import(scene: Node) -> Object:
	_walk(scene)
	return scene


func _walk(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			if mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_CUSTOM0:
				_attach(mesh.surface_get_material(s), "%s surface %d" % [node.name, s])
	elif node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh != null:
		var im: ImporterMesh = (node as ImporterMeshInstance3D).mesh
		for s in im.get_surface_count():
			if im.get_surface_format(s) & Mesh.ARRAY_FORMAT_CUSTOM0:
				_attach(im.get_surface_material(s), "%s surface %d" % [node.name, s])
	for child in node.get_children():
		_walk(child)


func _attach(mat: Material, where: String) -> void:
	if not (mat is BaseMaterial3D):
		push_warning("unit_glow_import: %s has CUSTOM0 but no BaseMaterial3D; glow skipped" % where)
		return
	var base := mat as BaseMaterial3D
	if base.next_pass is ShaderMaterial and (base.next_pass as ShaderMaterial).shader == GLOW_SHADER:
		return  # shared material already handled on another surface
	var energy: float = base.emission_energy_multiplier if base.emission_enabled else 1.0
	base.emission_enabled = false
	var glow := ShaderMaterial.new()
	glow.shader = GLOW_SHADER
	glow.set_shader_parameter("glow_energy", energy)
	base.next_pass = glow
	print("unit_glow_import: glow pass on %s (glow_energy %.3f)" % [where, energy])
