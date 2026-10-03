@tool
extends EditorScenePostImport
## Import script for forge unit glbs (set as `import_script/path` in each
## game/characters/models/*/*_forge.glb.import). Editor/import-time only.
##
## 1. ALWAYS switches off the stock glTF emission. Forge glbs export emissiveFactor
##    (1,1,1) x emissive strength (an artifact of the vertex-colour Glow -> Emission link),
##    which a stock import turns into a uniformly WHITE unit. Colour comes from COLOR_0
##    (vertex_color_use_as_albedo, set by the importer) and must never depend on step 2.
## 2. Surfaces that carry the glow mask in CUSTOM0 (addons/color1) get the shared glow
##    pass as their material's next_pass, with the glb's emissive strength as glow_energy.
##    The surface material stays a StandardMaterial3D, so skin tints
##    (SkinLibrary.tinted_material duplicates it; next_pass rides along) still apply.
## 3. Self-heal: if CUSTOM0 is missing, the color1 extension was not registered for this
##    import (e.g. an editor session that was already open when the plugin was enabled --
##    the 2026-10-02 white-unit defect). The script registers the extension itself and,
##    in the editor, schedules one reimport of the file so the glow pass is restored.

const GLOW_SHADER: Shader = preload("res://game/visuals/units/unit_glow.gdshader")
const COLOR1_EXT: Script = preload("res://addons/color1/color1_ext.gd")

static var _fallback_ext: GLTFDocumentExtension = null
static var _healed: Dictionary = {}

var _missing_glow := false


func _post_import(scene: Node) -> Object:
	_missing_glow = false
	_walk(scene)
	if _missing_glow:
		_heal(get_source_file())
	return scene


func _walk(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			_fix(mesh.surface_get_material(s), (mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0,
				"%s surface %d" % [node.name, s])
	elif node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh != null:
		var im: ImporterMesh = (node as ImporterMeshInstance3D).mesh
		for s in im.get_surface_count():
			_fix(im.get_surface_material(s), (im.get_surface_format(s) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0,
				"%s surface %d" % [node.name, s])
	for child in node.get_children():
		_walk(child)


func _fix(mat: Material, has_glow: bool, where: String) -> void:
	if not (mat is BaseMaterial3D):
		push_warning("unit_glow_import: %s has no BaseMaterial3D; left as imported" % where)
		return
	var base := mat as BaseMaterial3D
	if base.next_pass is ShaderMaterial and (base.next_pass as ShaderMaterial).shader == GLOW_SHADER:
		return  # shared material already handled on another surface
	var energy: float = base.emission_energy_multiplier if base.emission_enabled else 1.0
	base.emission_enabled = false
	if not has_glow:
		_missing_glow = true
		push_error("unit_glow_import: %s has no CUSTOM0 glow mask (color1 extension inactive for this import); stock emission removed, glow pass skipped" % where)
		return
	var glow := ShaderMaterial.new()
	glow.shader = GLOW_SHADER
	glow.set_shader_parameter("glow_energy", energy)
	base.next_pass = glow
	print("unit_glow_import: glow pass on %s (glow_energy %.3f)" % [where, energy])


static func _heal(src: String) -> void:
	if src.is_empty() or _healed.has(src):
		return  # at most one heal per file per session (no reimport loop)
	_healed[src] = true
	if _fallback_ext == null:
		_fallback_ext = COLOR1_EXT.new()
		GLTFDocument.register_gltf_document_extension(_fallback_ext, true)
		print("unit_glow_import: registered the color1 glTF extension (plugin was not active)")
	var tree := Engine.get_main_loop() as SceneTree
	if not Engine.is_editor_hint() or tree == null:
		return
	_schedule_reimport(tree, src)


static func _schedule_reimport(tree: SceneTree, src: String) -> void:
	tree.create_timer(1.0).timeout.connect(func() -> void:
		var fs := EditorInterface.get_resource_filesystem()
		if fs == null:
			return
		if fs.is_scanning():
			_schedule_reimport(tree, src)
			return
		print("unit_glow_import: reimporting %s with the glow mask" % src)
		fs.reimport_files(PackedStringArray([src])))
