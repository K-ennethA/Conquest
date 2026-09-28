extends Control

class_name MapGallery

# Map Gallery - Browse each battle map as a live 3D render of its real tile scenes,
# plus its description, metadata (weather, fog, floors), and a tile-effect legend.
# Mirrors the structure of UnitGallery / TileGallery: a left list, a right detail
# pane, and a Back-to-menu button, all built in code in _ready().
#
# THE RENDER is the shared [MapPreview3D] component (the map picker and the main-menu
# diorama use the same one): authored tile scenes (or a coloured box for a tile with no
# model), team-coloured spawn markers, floor-aware -- upper-floor tiles and spawns of
# multi-floor maps sit at their floor height. A map with nothing to render gets a
# name-monogram placeholder instead of an empty dark frame.
#
# LOOK. Hosted in a Compendium tab, so it wears the illuminated-grove kit
# (docs/UI_STYLE.md): theme label variations, FS_* sizes, a sunken well around the
# render and tag badges for the legend.

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

const MUTED := MenuTheme.TEXT_MUTED

## Breathing room inside the host (the Compendium's tab panel already pads the page).
const PAGE_MARGIN: int = MenuTheme.SP_S

# UI Elements
@onready var back_button: Button
@onready var map_list: ItemList
@onready var map_name_label: Label
@onready var map_description: RichTextLabel
@onready var metadata_container: VBoxContainer
@onready var legend_container: HFlowContainer

## Live 3D render of the selected map (shared component, floor-aware).
var map_preview: MapPreview3D

# Neutral placeholder shown over the 3D frame when a map has no tiles to render.
var map_preview_placeholder: PanelContainer
var map_preview_monogram: Label

# Data
var all_maps: Array[MapResource] = []
var current_map: MapResource


func _ready() -> void:
	theme = MenuTheme.build()  # the illuminated-grove menu theme
	_create_ui()
	_load_all_maps()
	_setup_connections()
	_populate_map_list()

	# Select the first map on open so the picture/detail are never blank.
	if not all_maps.is_empty():
		map_list.select(0)
		_display_map(all_maps[0])


func _create_ui() -> void:
	"""Create the complete UI for the map gallery"""
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", PAGE_MARGIN)
	outer.add_theme_constant_override("margin_right", PAGE_MARGIN)
	outer.add_theme_constant_override("margin_top", PAGE_MARGIN)
	outer.add_theme_constant_override("margin_bottom", PAGE_MARGIN)
	add_child(outer)

	# Main container: a fixed-width list column, the detail pane takes the rest.
	var main_container := HBoxContainer.new()
	main_container.add_theme_constant_override("separation", MenuTheme.SP_XL)
	outer.add_child(main_container)

	# Left panel - Map list
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(320, 0)
	left_panel.add_theme_constant_override("separation", MenuTheme.SP_XS)
	main_container.add_child(left_panel)

	# Title and back button (the Compendium hides this whole row when hosting).
	var header_container := HBoxContainer.new()
	# A real gap between the title and Back (the default ~4px let a long title touch it).
	header_container.add_theme_constant_override("separation", MenuTheme.SP_M)
	left_panel.add_child(header_container)

	var title := Label.new()
	title.text = "Map Gallery"
	title.theme_type_variation = &"HeadingLabel"
	title.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(title)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 120, 44)
	header_container.add_child(back_button)

	# Map list
	left_panel.add_child(_form_label("Maps"))

	map_list = ItemList.new()
	map_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	map_list.custom_minimum_size = Vector2(280, 120)
	left_panel.add_child(map_list)

	# Right panel - Map picture and details
	# (scrolls, so the details below the preview stay reachable on short windows)
	var right_scroll := ScrollContainer.new()
	right_scroll.name = "DetailScroll"
	right_scroll.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.custom_minimum_size = Vector2(500, 0)
	main_container.add_child(right_scroll)

	var right_panel := VBoxContainer.new()
	right_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_panel.add_theme_constant_override("separation", MenuTheme.SP_S)
	right_scroll.add_child(right_panel)

	_create_map_display(right_panel)


func _create_map_display(parent: VBoxContainer) -> void:
	"""Create the map picture + detail area"""
	# Map name (title)
	map_name_label = Label.new()
	map_name_label.add_theme_font_override("font", MenuTheme.display_font(2))
	map_name_label.add_theme_font_size_override("font_size", MenuTheme.FS_HEADING + 4)
	map_name_label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	parent.add_child(map_name_label)

	# Real 3D render of the map on a slow turntable (MapPreview3D, shared with the map
	# picker and the main menu diorama), in a sunken well. A neutral monogram
	# placeholder sits on top, shown only when a map has no tiles to render.
	var well := PanelContainer.new()
	well.name = "MapPreviewWell"
	well.add_theme_stylebox_override("panel", MenuTheme.inset_box())
	parent.add_child(well)

	var preview_frame := Control.new()
	preview_frame.custom_minimum_size = Vector2(360, 300)
	well.add_child(preview_frame)

	map_preview = MapPreview3D.new()
	map_preview.name = "MapPreview"
	map_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_preview.background_color = MenuTheme.PANEL_SUNK
	preview_frame.add_child(map_preview)

	map_preview_placeholder = PanelContainer.new()
	map_preview_placeholder.name = "MapPreviewPlaceholder"
	map_preview_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_preview_placeholder.add_theme_stylebox_override("panel", MenuTheme.inset_box())
	map_preview_placeholder.visible = false
	preview_frame.add_child(map_preview_placeholder)

	var placeholder_center := CenterContainer.new()
	map_preview_placeholder.add_child(placeholder_center)

	map_preview_monogram = Label.new()
	map_preview_monogram.add_theme_font_override("font", MenuTheme.display_font(2))
	map_preview_monogram.add_theme_font_size_override("font_size", 64)
	map_preview_monogram.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	placeholder_center.add_child(map_preview_monogram)

	# Description (wrapped)
	parent.add_child(_section_header("Description"))

	map_description = RichTextLabel.new()
	map_description.custom_minimum_size = Vector2(0, 40)
	map_description.fit_content = true
	parent.add_child(map_description)

	# Metadata
	parent.add_child(_section_header("Details"))

	metadata_container = VBoxContainer.new()
	metadata_container.add_theme_constant_override("separation", MenuTheme.SP_XS)
	parent.add_child(metadata_container)

	# Tile-effect legend (a flow row: wraps instead of widening the pane)
	parent.add_child(_section_header("Tile Effects"))

	legend_container = HFlowContainer.new()
	legend_container.add_theme_constant_override("h_separation", MenuTheme.SP_S)
	legend_container.add_theme_constant_override("v_separation", MenuTheme.SP_XS)
	parent.add_child(legend_container)


func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"SectionLabel"
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	return label


## Small muted caption above a form control.
func _form_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	return label


## Up-to-two-letter monogram for a map with no renderable tiles (initials of the
## first two words, else the first two characters). Never empty.
func _map_monogram(map_name: String) -> String:
	var trimmed := map_name.strip_edges()
	if trimmed.is_empty():
		return "?"
	var words := trimmed.split(" ", false)
	if words.size() >= 2:
		return (String(words[0]).substr(0, 1) + String(words[1]).substr(0, 1)).to_upper()
	return trimmed.substr(0, 2).to_upper()


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
		push_warning("MapGallery: No map resources directory found")
		return

	var dir := DirAccess.open(MAPS_DIR)
	if not dir:
		push_error("MapGallery: Failed to open map resources directory")
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# Exported builds list remapped resources as "<name>.tres.remap".
		var res_name := file_name.trim_suffix(".remap")
		if res_name.ends_with(".tres"):
			var resource_path := MAPS_DIR + res_name
			if ResourceLoader.exists(resource_path):
				var resource = load(resource_path)
				if resource is MapResource:
					all_maps.append(resource)
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
		# flagged, since the in-game selection screens treat them differently.
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

	# Rebuild the 3D render for this map (or the monogram when there is nothing to draw).
	var has_tiles: bool = not map_res.tile_layout.is_empty()
	if map_preview:
		map_preview.show_map(map_res)
	if map_preview_placeholder != null:
		map_preview_placeholder.visible = not has_tiles
		if not has_tiles and map_preview_monogram != null:
			map_preview_monogram.text = _map_monogram(map_res.map_name)

	_update_metadata(map_res)
	_update_legend(map_res)


func _update_metadata(map_res: MapResource) -> void:
	"""Rebuild the metadata rows for the selected map"""
	if not metadata_container:
		return

	for child in metadata_container.get_children():
		metadata_container.remove_child(child)
		child.queue_free()

	var victory := ", ".join(map_res.victory_conditions) if not map_res.victory_conditions.is_empty() else "None"
	var size_text := str(map_res.width) + "x" + str(map_res.height)
	var floors: int = map_res.get_floor_count()
	if floors > 1:
		size_text += "  (%d floors)" % floors
	var weather_text := map_res.weather_summary()
	if weather_text == "":
		weather_text = "Clear"
	var rows := [
		["Status", map_res.status if map_res.is_active() else map_res.status + " (draft: not offered in normal map selection)"],
		["Size", size_text],
		["Difficulty", map_res.difficulty],
		["Players", str(map_res.recommended_players) + " recommended, " + str(map_res.max_players) + " max"],
		["Type", map_res.map_type],
		["Victory", victory],
		["Weather", weather_text],
	]
	if map_res.fog_of_war:
		rows.append(["Fog of war", "On -- each side sees only what its units can see"])

	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", MenuTheme.SP_S)
		metadata_container.add_child(line)

		var key_label := Label.new()
		key_label.text = str(row[0])
		key_label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		key_label.add_theme_color_override("font_color", MUTED)
		key_label.custom_minimum_size = Vector2(110, 0)
		line.add_child(key_label)

		var value_label := Label.new()
		value_label.text = str(row[1])
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		line.add_child(value_label)


func _update_legend(map_res: MapResource) -> void:
	"""Show a chip for each effect-bearing tile type actually present on the map"""
	if not legend_container:
		return

	for child in legend_container.get_children():
		legend_container.remove_child(child)
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
		var chip_color: Color = TILE_COLORS.get(tile_type, TILE_FALLBACK)
		legend_container.add_child(MenuKit.badge(str(info.get("name", "Effect")), chip_color))


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
				# Hosted in the Compendium the shell owns Back (it hid our button).
				if back_button != null and back_button.visible:
					_on_back_pressed()
			KEY_F5:
				_load_all_maps()
				_populate_map_list()


# Positions are normally Vector2i; handle a Dictionary {x, y} defensively too.
func _read_pos(value) -> Vector2i:
	return MapPreview3D.read_pos(value)
