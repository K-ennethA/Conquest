extends Node3D

## Standalone showcase for the stylized animated tile set.
## Open dev_scripts/grass_preview.tscn and press F6 (Run Current Scene).
## Lays out four patches side by side -- Grass, Water, Burn, and Tree tiles --
## so you can see every stylized material animating at once, the way they look
## on the board.

const CELL := 2.0            # matches Grid.cell_size (Vector3(2,0,2))
const TILE_HEIGHT := 0.3
const PATCH := 3             # PATCH x PATCH tiles per material
const PATCH_STRIDE := 8.0    # world X distance between patch origins
const TREE_TILE := "res://tile_objects/tiles/scenes/forest/tree_tile.tscn"

func _ready() -> void:
	# Flat material patches (Grass / Water / Burn) built via TileResource so the
	# preview matches runtime exactly.
	var styles := [
		{"name": "GRASS", "style": TileResource.MaterialStyle.GRASS},
		{"name": "WATER", "style": TileResource.MaterialStyle.WATER},
		{"name": "BURN",  "style": TileResource.MaterialStyle.BURN},
	]

	var patch_index := 0
	for entry in styles:
		_build_material_patch(entry["style"], patch_index, entry["name"])
		patch_index += 1

	# Tree patch: full tile scenes (grass base + tree on top).
	_build_tree_patch(patch_index)
	_add_label("TREE", patch_index)

	_setup_camera_and_light(patch_index)

func _build_material_patch(style: int, patch_index: int, label: String) -> void:
	var res := TileResource.new()
	res.material_style = style
	var mat := res.create_material()

	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL, TILE_HEIGHT, CELL)
	mesh.material = mat  # shared -> seamless field + batching

	for x in PATCH:
		for z in PATCH:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(patch_index * PATCH_STRIDE + x * CELL, 0.0, z * CELL)
			add_child(mi)

	_add_label(label, patch_index)

func _build_tree_patch(patch_index: int) -> void:
	var tree_scene: PackedScene = load(TREE_TILE)
	if tree_scene == null:
		push_warning("Showcase: could not load " + TREE_TILE)
		return
	for x in PATCH:
		for z in PATCH:
			var tile := tree_scene.instantiate()
			tile.position = Vector3(patch_index * PATCH_STRIDE + x * CELL, 0.0, z * CELL)
			add_child(tile)

func _add_label(text: String, patch_index: int) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(patch_index * PATCH_STRIDE + (PATCH - 1) * CELL * 0.5, 2.2, -2.0)
	add_child(lbl)

func _setup_camera_and_light(patch_count: int) -> void:
	var span_x := (patch_count) * PATCH_STRIDE
	var center := Vector3(span_x * 0.5 - PATCH_STRIDE * 0.5, 0.0, (PATCH - 1) * CELL * 0.5)

	var cam := Camera3D.new()
	cam.position = center + Vector3(0.0, 14.0, 16.0)
	cam.look_at(center, Vector3.UP)
	cam.current = true
	add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.72, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
