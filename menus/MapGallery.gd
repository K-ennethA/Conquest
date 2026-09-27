extends Control

class_name MapGallery

# Map Gallery - Browse each battle map with a top-down picture painted from its
# tile data, plus its description, metadata, and a tile-effect legend. Mirrors the
# structure of UnitGallery / TileGallery: a left list, a right detail pane, and a
# Back-to-menu button, all built in code in _ready().

# Palette shared with the 3D preview / map-card thumbnails (MapPreview3D), so the
# legend chips read identically to the rendered cells.
const TILE_COLORS := MapPreview3D.TILE_COLORS
const TILE_FALLBACK := MapPreview3D.TILE_FALLBACK

# tile_type -> tile-effect id (from TileEffectVisuals) for the legend.
const EFFECT_FOR_TILE := {
	"LAVA": &"fire",
	"WATER": &"empowering_water",
	"SACRED_GROUND": &"fortify",
	"DIFFICULT_TERRAIN": &"tall_grass",
}

const MAPS_DIR := "res://game/maps/resources/"
const TILES_DIR := "res://game/tiles/resources/"

# UI Elements
@onready var back_button: Button
@onready var map_list: ItemList
@onready var map_name_label: Label
@onready var map_description: RichTextLabel
@onready var metadata_container: VBoxContainer
@onready var legend_container: HBoxContainer

## Live 3D render of the selected map (shared component, floor-aware).
var map_preview: MapPreview3D

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
	main_container.add_theme_constant_override("separation", 20)
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_container)

	# Left panel - Map list
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(320, 0)
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
	map_list.custom_minimum_size = Vector2(280, 120)
	left_panel.add_child(map_list)

	# Right panel - Map picture and details
	# (scrolls, so the details below the preview stay reachable on short windows)
	var right_scroll := ScrollContainer.new()
	right_scroll.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.custom_minimum_size = Vector2(500, 0)
	main_container.add_child(right_scroll)
	var right_panel := VBoxContainer.new()
	right_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_panel.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_panel)

	_create_map_display(right_panel)


func _create_map_display(parent: VBoxContainer) -> void:
	"""Create the map picture + detail area"""
	# Map name (title)
	map_name_label = Label.new()
	map_name_label.add_theme_font_size_override("font_size", 22)
	parent.add_child(map_name_label)

	# Real 3D render of the map on a slow turntable (MapPreview3D, shared with the
	# map picker and the main menu diorama).
	map_preview = MapPreview3D.new()
	map_preview.name = "MapPreview"
	map_preview.custom_minimum_size = Vector2(360, 300)
	map_preview.background_color = MenuTheme.PANEL_SUNK
	parent.add_child(map_preview)

	# Description (wrapped)
	var desc_label := Label.new()
	desc_label.text = "Description:"
	desc_label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	parent.add_child(desc_label)

	map_description = RichTextLabel.new()
	map_description.custom_minimum_size = Vector2(0, 40)
	map_description.fit_content = true
	parent.add_child(map_description)

	# Metadata
	var meta_label := Label.new()
	meta_label.text = "Details:"
	meta_label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	parent.add_child(meta_label)

	metadata_container = VBoxContainer.new()
	parent.add_child(metadata_container)

	# Tile-effect legend
	var legend_label := Label.new()
	legend_label.text = "Tile Effects:"
	legend_label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
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
	if map_preview:
		map_preview.show_map(map_res)

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
		["Status", map_res.status if map_res.is_active() else map_res.status + " (draft: offered in local play only, hidden from network lobbies)"],
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
		none_label.theme_type_variation = &"MutedLabel"
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
	return MapPreview3D.read_tile_type(entry)


# Signal handlers
func _on_back_pressed() -> void:
	"""Handle back button press"""
	MenuNav.change_scene(self, "res://menus/MainMenu.tscn")


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


# Positions are normally Vector2i; handle a Dictionary {x, y} defensively too.
func _read_pos(value) -> Vector2i:
	return MapPreview3D.read_pos(value)
