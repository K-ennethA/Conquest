extends Control

class_name MapGallery

# Map Gallery - Browse each battle map with a top-down picture painted from its
# tile data, plus its description, metadata, and a tile-effect legend. Mirrors the
# structure of UnitGallery / TileGallery: a left list, a right detail pane, and a
# Back-to-menu button, all built in code in _ready().

# Palette mapping tile_type -> cell colour, tuned to the warm-amber / natural vibe.
# Kept as a const so the map picture and the legend chips read identically.
const TILE_COLORS := {
	"NORMAL": Color("6f8f4e"),          # grass green
	"PLAINS": Color("6f8f4e"),
	"GRASS": Color("6f8f4e"),
	"DIFFICULT_TERRAIN": Color("3f5e32"),  # dark forest (tall-grass avoid tile)
	"WATER": Color("3b6ea5"),
	"LAVA": Color("c0431f"),
	"WALL": Color("5a5450"),
	"ICE": Color("bcd8e6"),
	"SWAMP": Color("5b5a34"),
	"SACRED_GROUND": Color("c7a63b"),
	"CORRUPTED": Color("6b3f7a"),
}
const TILE_FALLBACK := Color("777777")

# Spawn markers coloured by player_id.
const PLAYER0_COLOR := Color("4a90d9")  # blue
const PLAYER1_COLOR := Color("d94a4a")  # red
const PLAYER_FALLBACK := Color("e6a64b")  # amber

# tile_type -> tile-effect id (from TileEffectVisuals) for the legend.
const EFFECT_FOR_TILE := {
	"LAVA": &"fire",
	"WATER": &"empowering_water",
	"SACRED_GROUND": &"fortify",
	"DIFFICULT_TERRAIN": &"tall_grass",
}

const MAPS_DIR := "res://game/maps/resources/"
const TILES_DIR := "res://game/tiles/resources/"

# --- 3D preview tuning -------------------------------------------------------
# Grid spacing between tile centres (world units). Each tile mesh is a little
# smaller than the step so a thin gap reads as a grid.
const TILE_STEP := 2.0
const TILE_MESH_SIZE := Vector3(1.8, 0.3, 1.8)
const SPAWN_RADIUS := 0.35
const SPAWN_Y := 0.5  # sits on top of the tile surface
# Gentle turntable so the depth/perspective is obvious at a glance.
const TURNTABLE_SPEED := 0.35  # radians / second

# UI Elements
@onready var back_button: Button
@onready var map_list: ItemList
@onready var map_name_label: Label
@onready var map_description: RichTextLabel
@onready var metadata_container: VBoxContainer
@onready var legend_container: HBoxContainer

# 3D preview nodes (built in _create_map_display / _setup_map_viewport).
@onready var map_viewport: SubViewport
@onready var map_root: Node3D
@onready var map_camera: Camera3D
# Cached span of the current map so _process turntable / re-aims stay stable.
var _map_span: float = TILE_STEP

# --- 3D tile geometry caches -------------------------------------------------
# Tiles render as their REAL authored scene (TileResource.model_path) rather than a
# flat coloured box. Everything here is keyed by path and loaded once, so switching
# maps in the list never re-reads a file per cell. A cached null means "already
# tried, unusable" - a broken path falls back to the box and is never retried.
var _tile_resource_cache: Dictionary = {}   # .tres path -> TileResource (or null)
var _tile_model_cache: Dictionary = {}      # .tscn path -> PackedScene (or null)
var _type_model_paths: Dictionary = {}      # type_name -> model scene path
var _type_model_paths_built: bool = false

# Data
var all_maps: Array[MapResource] = []
var current_map: MapResource


func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look
	_create_ui()
	_load_all_maps()
	_setup_connections()
	_populate_map_list()

	# Select the first map on open so the picture/detail are never blank.
	if not all_maps.is_empty():
		map_list.select(0)
		_display_map(all_maps[0])

	print("Map Gallery initialized with " + str(all_maps.size()) + " maps")


func _create_ui() -> void:
	"""Create the complete UI for the map gallery"""
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Main container
	var main_container := HBoxContainer.new()
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_container)

	# Left panel - Map list
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)
	left_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	main_container.add_child(left_panel)

	# Title and back button
	var header_container := HBoxContainer.new()
	left_panel.add_child(header_container)

	var title := Label.new()
	title.text = "MAP GALLERY"
	title.add_theme_font_size_override("font_size", 24)
	title.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(title)

	back_button = Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(80, 40)
	header_container.add_child(back_button)

	# Map list
	var list_label := Label.new()
	list_label.text = "Maps:"
	left_panel.add_child(list_label)

	map_list = ItemList.new()
	map_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	map_list.custom_minimum_size = Vector2(280, 400)
	left_panel.add_child(map_list)

	# Right panel - Map picture and details
	var right_panel := VBoxContainer.new()
	right_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_panel.custom_minimum_size = Vector2(500, 0)
	main_container.add_child(right_panel)

	_create_map_display(right_panel)


func _create_map_display(parent: VBoxContainer) -> void:
	"""Create the map picture + detail area"""
	# Map name (title)
	map_name_label = Label.new()
	map_name_label.add_theme_font_size_override("font_size", 22)
	parent.add_child(map_name_label)

	# Real 3D render of the map, shown through a SubViewport for depth/perspective
	# (mirrors TileGallery's 3D tile preview). The 2D "painted picture" is gone.
	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(420, 420)
	viewport_container.stretch = true
	parent.add_child(viewport_container)

	map_viewport = SubViewport.new()
	map_viewport.size = Vector2i(420, 420)
	map_viewport.transparent_bg = false
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(map_viewport)

	_setup_map_viewport()

	# Description (wrapped)
	var desc_label := Label.new()
	desc_label.text = "Description:"
	desc_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(desc_label)

	map_description = RichTextLabel.new()
	map_description.custom_minimum_size = Vector2(0, 80)
	map_description.fit_content = true
	parent.add_child(map_description)

	# Metadata
	var meta_label := Label.new()
	meta_label.text = "Details:"
	meta_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(meta_label)

	metadata_container = VBoxContainer.new()
	parent.add_child(metadata_container)

	# Tile-effect legend
	var legend_label := Label.new()
	legend_label.text = "Tile Effects:"
	legend_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(legend_label)

	legend_container = HBoxContainer.new()
	parent.add_child(legend_container)


func _setup_connections() -> void:
	"""Set up signal connections"""
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	if map_list:
		map_list.item_selected.connect(_on_map_selected)


func _load_all_maps() -> void:
	"""Load every MapResource under the maps resource directory (so new maps
	appear automatically), guarding against nulls / non-map .tres files."""
	all_maps.clear()

	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		print("No map resources directory found")
		return

	var dir := DirAccess.open(MAPS_DIR)
	if not dir:
		print("Failed to open map resources directory")
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var resource_path := MAPS_DIR + file_name
			if ResourceLoader.exists(resource_path):
				var resource = load(resource_path)
				if resource is MapResource:
					all_maps.append(resource)
					print("Loaded map: " + resource.map_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Stable, readable ordering.
	all_maps.sort_custom(func(a, b): return a.map_name < b.map_name)


func _populate_map_list() -> void:
	"""Update the map list display"""
	if not map_list:
		return

	map_list.clear()

	for map_res in all_maps:
		var display_text := map_res.map_name
		if display_text.is_empty():
			display_text = "(Unnamed Map)"
		# Drafts are shown here (handy for reviewing work in progress in 3D) but
		# flagged, since the in-game selection screens hide them.
		if not map_res.is_active():
			display_text = "[Draft] " + display_text
		map_list.add_item(display_text)

	if map_list.get_item_count() == 0:
		map_list.add_item("No maps found")
		map_list.set_item_disabled(0, true)


func _display_map(map_res: MapResource) -> void:
	"""Display picture + details for the selected map"""
	current_map = map_res
	if not map_res:
		return

	if map_name_label:
		map_name_label.text = map_res.map_name

	if map_description:
		map_description.text = map_res.description

	# Rebuild the 3D render for this map.
	_build_map_3d(map_res)

	_update_metadata(map_res)
	_update_legend(map_res)


func _update_metadata(map_res: MapResource) -> void:
	"""Rebuild the metadata rows for the selected map"""
	if not metadata_container:
		return

	for child in metadata_container.get_children():
		child.queue_free()

	var victory := ", ".join(map_res.victory_conditions) if not map_res.victory_conditions.is_empty() else "None"
	var rows := [
		["Status", map_res.status if map_res.is_active() else map_res.status + " (draft - not in map selection)"],
		["Size", str(map_res.width) + "x" + str(map_res.height)],
		["Difficulty", map_res.difficulty],
		["Players", str(map_res.recommended_players) + " recommended, " + str(map_res.max_players) + " max"],
		["Type", map_res.map_type],
		["Victory", victory],
	]

	for row in rows:
		var label := Label.new()
		label.text = str(row[0]) + ": " + str(row[1])
		metadata_container.add_child(label)


func _update_legend(map_res: MapResource) -> void:
	"""Show a chip for each effect-bearing tile type actually present on the map"""
	if not legend_container:
		return

	for child in legend_container.get_children():
		child.queue_free()

	# Collect the effect-carrying tile types present on this map.
	var present_types := {}
	for entry in map_res.tile_layout:
		var tile_type := _read_tile_type(entry)
		if EFFECT_FOR_TILE.has(tile_type):
			present_types[tile_type] = true

	if present_types.is_empty():
		var none_label := Label.new()
		none_label.text = "No terrain effects on this map"
		none_label.modulate = Color(0.7, 0.7, 0.7)
		legend_container.add_child(none_label)
		return

	for tile_type in present_types.keys():
		var effect_id: StringName = EFFECT_FOR_TILE[tile_type]
		var info := TileEffectVisuals.info_for_id(effect_id)

		var chip := HBoxContainer.new()
		legend_container.add_child(chip)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.color = TILE_COLORS.get(tile_type, TILE_FALLBACK)
		chip.add_child(swatch)

		var name_label := Label.new()
		name_label.text = " " + str(info.get("name", "Effect"))
		chip.add_child(name_label)

		# Small spacer between chips.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(12, 0)
		chip.add_child(spacer)


# Read a tile_type string defensively - values are normally Strings.
func _read_tile_type(entry: Dictionary) -> String:
	return str(entry.get("tile_type", "NORMAL")).to_upper()


# Signal handlers
func _on_back_pressed() -> void:
	"""Handle back button press"""
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


func _on_map_selected(index: int) -> void:
	"""Handle map selection from list"""
	if index >= 0 and index < all_maps.size():
		var selected_map := all_maps[index]
		if selected_map != null:
			_display_map(selected_map)


# Input handling
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return

	if event is InputEventKey:
		match event.keycode:
			KEY_ESCAPE:
				_on_back_pressed()
			KEY_F5:
				_load_all_maps()
				_populate_map_list()
				print("Map list refreshed")


# ---------------------------------------------------------------------------
# 3D map preview
# ---------------------------------------------------------------------------
# Builds a real 3D scene (one box mesh per tile, small spheres for spawns) inside
# a SubViewport with an angled Fire-Emblem-style perspective camera, so the map
# reads with genuine depth instead of a flat painted picture. Rendered from live
# tile data so it is always current (there are no pre-rendered previews on disk).

func _setup_map_viewport() -> void:
	"""Populate the SubViewport with a MapRoot, camera, light and environment."""
	if not map_viewport:
		return

	# MapRoot holds all per-map geometry; rebuilt by _build_map_3d.
	map_root = Node3D.new()
	map_root.name = "MapRoot"
	map_viewport.add_child(map_root)

	# Angled top-down perspective camera (aimed for real once a map loads).
	map_camera = Camera3D.new()
	map_camera.name = "MapCamera"
	# look_at_from_position orients without needing the node in-tree first
	# (plain look_at() errors before add_child()).
	map_camera.look_at_from_position(
		Vector3(0.0, _map_span * 0.9, _map_span * 0.7), Vector3.ZERO, Vector3.UP)
	map_viewport.add_child(map_camera)

	# Warm, slightly dark environment with ambient so nothing renders pure black.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.09, 0.12, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45, 1.0)
	env.ambient_light_energy = 0.45
	map_camera.environment = env

	# Directional key light, angled to match the camera side for readable shading.
	var light := DirectionalLight3D.new()
	light.name = "MapLight"
	light.look_at_from_position(
		Vector3(_map_span * 0.6, _map_span * 1.2, _map_span * 0.4), Vector3.ZERO, Vector3.UP)
	light.light_energy = 1.1
	map_viewport.add_child(light)


func _build_map_3d(map_res: MapResource) -> void:
	"""Rebuild MapRoot's children (tiles + spawn markers) for the given map and
	re-aim the camera to frame it. Guards nulls / empty layouts without crashing."""
	if not map_root:
		return

	# Free previous geometry. Detach first so the outgoing map is never visible for
	# a frame underneath the incoming one (queue_free is deferred).
	for child in map_root.get_children():
		map_root.remove_child(child)
		child.queue_free()

	# Reset turntable so each map starts square-on.
	map_root.rotation = Vector3.ZERO

	if map_res == null:
		return

	var cols: int = map_res.width
	var rows: int = map_res.height
	if cols < 1:
		cols = 1
	if rows < 1:
		rows = 1

	# Update span + re-aim camera for this map's size (stable framing).
	_map_span = maxf(float(cols), float(rows)) * TILE_STEP
	_aim_camera()

	# Centre offsets so the whole grid is centred on the origin.
	var offset_x: float = float(cols - 1) * TILE_STEP * 0.5
	var offset_z: float = float(rows - 1) * TILE_STEP * 0.5

	# Shared meshes (per-instance material overrides colour them). The tile box is only
	# the fallback now - tiles that name a model get their authored scene instead.
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = TILE_MESH_SIZE
	var spawn_mesh := SphereMesh.new()
	spawn_mesh.radius = SPAWN_RADIUS
	spawn_mesh.height = SPAWN_RADIUS * 2.0

	# Tiles.
	for entry in map_res.tile_layout:
		var pos := _read_pos(entry.get("position", Vector2i.ZERO))
		if pos.x < 0 or pos.x >= cols or pos.y < 0 or pos.y >= rows:
			continue
		var tile_type := _read_tile_type(entry)

		# The authored scenes are already a full cell (a 2 x 0.2 x 2 slab matching
		# TILE_STEP), so they go in at IDENTITY scale; TILE_MESH_SIZE is the box's.
		var visual: Node3D = _instantiate_tile_model(entry, tile_type)

		if not visual:
			var color: Color = TILE_COLORS.get(tile_type, TILE_FALLBACK)
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = tile_mesh
			mesh_instance.material_override = _solid_material(color)
			visual = mesh_instance

		map_root.add_child(visual)
		visual.position = Vector3(
			float(pos.x) * TILE_STEP - offset_x,
			0.0,
			float(pos.y) * TILE_STEP - offset_z)

	# Spawn markers, sitting on top of their tile.
	for spawn in map_res.unit_spawns:
		var pos := _read_pos(spawn.get("position", Vector2i.ZERO))
		if pos.x < 0 or pos.x >= cols or pos.y < 0 or pos.y >= rows:
			continue
		var player_id := int(spawn.get("player_id", -1))
		var marker_color := PLAYER_FALLBACK
		if player_id == 0:
			marker_color = PLAYER0_COLOR
		elif player_id == 1:
			marker_color = PLAYER1_COLOR

		var marker := MeshInstance3D.new()
		marker.mesh = spawn_mesh
		marker.material_override = _solid_material(marker_color)
		marker.position = Vector3(
			float(pos.x) * TILE_STEP - offset_x,
			SPAWN_Y,
			float(pos.y) * TILE_STEP - offset_z)
		map_root.add_child(marker)


func _load_tile_resource(resource_path: String) -> TileResource:
	"""Cached TileResource load; null for an empty, missing or wrong-typed path."""
	if resource_path.is_empty():
		return null

	if _tile_resource_cache.has(resource_path):
		return _tile_resource_cache[resource_path] as TileResource

	var tile_resource: TileResource = null
	if ResourceLoader.exists(resource_path):
		var loaded = load(resource_path)
		if loaded is TileResource:
			tile_resource = loaded as TileResource

	_tile_resource_cache[resource_path] = tile_resource
	return tile_resource


func _build_type_model_paths() -> void:
	"""Map each tile TYPE to a tile resource that actually has geometry.

	Only consulted when a layout entry records no tile_resource_path of its own
	(maps authored before that field, and create_default_layout's bare "NORMAL"
	cells). Types with no modelled resource are simply absent, so they keep the box.
	"""
	if _type_model_paths_built:
		return
	_type_model_paths_built = true

	if not DirAccess.dir_exists_absolute(TILES_DIR):
		return

	var dir := DirAccess.open(TILES_DIR)
	if not dir:
		return

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Stable ordering, so which resource claims a shared type never varies by run.
	file_names.sort()

	var type_names: Array = Tile.TileType.keys()
	for entry_name in file_names:
		var tile_resource := _load_tile_resource(TILES_DIR + entry_name)
		if not tile_resource or tile_resource.model_path.is_empty():
			continue
		var type_index: int = int(tile_resource.tile_type)
		if type_index < 0 or type_index >= type_names.size():
			continue
		var type_name: String = str(type_names[type_index])
		if not _type_model_paths.has(type_name):
			_type_model_paths[type_name] = tile_resource.model_path


func _load_tile_model(scene_path: String) -> PackedScene:
	"""Cached PackedScene load for a model_path; null when missing or not a scene."""
	if scene_path.is_empty():
		return null

	if _tile_model_cache.has(scene_path):
		return _tile_model_cache[scene_path] as PackedScene

	var packed: PackedScene = null
	if ResourceLoader.exists(scene_path):
		var loaded = load(scene_path)
		if loaded is PackedScene:
			packed = loaded as PackedScene

	_tile_model_cache[scene_path] = packed
	return packed


func _tile_model_path(entry: Dictionary, tile_type: String) -> String:
	"""Model scene path for a layout entry, or "" when it renders as a coloured box.

	The entry's OWN tile_resource_path wins - it names the exact tile the author
	painted. Only when that is empty (or unloadable) do we fall back to the type.
	"""
	var resource_path := str(entry.get("tile_resource_path", ""))
	if not resource_path.is_empty():
		var tile_resource := _load_tile_resource(resource_path)
		if tile_resource:
			return tile_resource.model_path

	_build_type_model_paths()
	return str(_type_model_paths.get(tile_type, ""))


func _instantiate_tile_model(entry: Dictionary, tile_type: String) -> Node3D:
	"""Instance of a layout entry's authored tile scene, or null when it has none.

	Fully guarded: this is the real game scene (tile.gd DOES run here, exactly as on
	the board), so one bad tile resource must never take the gallery down with it.
	"""
	var packed := _load_tile_model(_tile_model_path(entry, tile_type))
	if not packed:
		return null

	var instance = packed.instantiate()
	if instance is Node3D:
		return instance as Node3D

	# Something non-spatial was authored there - drop it and use the box instead.
	if instance:
		instance.free()
	return null


func _aim_camera() -> void:
	"""Re-position the camera for the current _map_span (angled top-down)."""
	if not map_camera:
		return
	map_camera.look_at_from_position(
		Vector3(0.0, _map_span * 0.9, _map_span * 0.7), Vector3.ZERO, Vector3.UP)


func _solid_material(color: Color) -> StandardMaterial3D:
	"""A simple lit material with the given albedo."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat


# Slow turntable rotation so the perspective/depth is obvious at a glance.
func _process(delta: float) -> void:
	if map_root:
		map_root.rotate_y(TURNTABLE_SPEED * delta)


# Positions are normally Vector2i; handle a Dictionary {x, y} defensively too.
func _read_pos(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO
