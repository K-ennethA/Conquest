extends Control

class_name TileGallery

# Tile Gallery - Browse and view all available tiles and their effects
#
# ELEMENTS. This gallery predates the element work, so a tile's page said nothing about
# the matchup the board actually resolves for it. It does now: an elemented tile carries
# the same ElementVisuals badge a unit or a move does, plus a one-line matchup hint
# derived from the LIVE matrix.
#
# Where the element comes from is `element_chart.tres` and nothing else (CONQUEST.md rule
# 9). Its `tile_elements` map is keyed on BOTH a TileEffectResource.id and, for terrain
# that grows its own effect, the TILE's own id -- which is why deep_water is water with no
# effect resource at all, and molten_lava is fire through a legacy TileEffect that carries
# no id of its own. See `tile_element_of` / `effect_element_of`.
#
# ELEMENTLESS TILES GET NO BADGE. The chart leaves pure-utility terrain (grass, trees,
# obsidian, the `stealth` flag) deliberately neutral because it has nothing to apply, and
# a badge there would promise a matchup the board never resolves. Absence is the authored
# answer -- never invent one.

# UI Elements
@onready var back_button: Button
@onready var tile_list: ItemList
@onready var tile_display_container: VBoxContainer
@onready var tile_name_label: Label
@onready var tile_type_label: Label
@onready var tile_description: RichTextLabel
@onready var tile_preview_viewport: SubViewport
@onready var properties_container: VBoxContainer
@onready var effects_container: VBoxContainer
@onready var search_input: LineEdit
@onready var filter_option: OptionButton
@onready var sort_option: OptionButton

# --- Element readout -----------------------------------------------------------

## The tile-level badge in the detail header. Renamed off [constant
## ElementVisuals.BADGE_NAME] so a test (and a future reader) can tell the ONE tile badge
## from the per-effect badges further down the page.
const TILE_BADGE_NAME := "TileElementBadge"
## The row holding that badge and the matchup hint. Hidden whole for an elementless tile.
const TILE_ELEMENT_ROW_NAME := "TileElementRow"
## The matchup hint label inside that row.
const TILE_MATCHUP_NAME := "TileMatchupHint"
## Per-effect badge, on the card for an individual tile effect.
const EFFECT_BADGE_NAME := "EffectElementBadge"

## Cap for the tile badge. Wider than the shared default because this page has the room
## and an elided element name on the Compendium's own tile page would be absurd.
const BADGE_CAP: float = 96.0

## Element badge + matchup hint for the selected tile, kept as fields so the header row is
## built ONCE and only re-pointed per selection (the ElementVisuals contract).
var tile_element_badge: PanelContainer = null
var tile_element_row: HBoxContainer = null
var tile_matchup_label: Label = null

# Data
var all_tiles: Array[TileResource] = []
var filtered_tiles: Array[TileResource] = []
var current_tile: TileResource
var current_tile_preview: Node3D

# Filter and sort options
var tile_types = ["All", "NORMAL", "DIFFICULT_TERRAIN", "WATER", "WALL", "SPECIAL", "LAVA", "ICE", "SWAMP", "SACRED_GROUND", "CORRUPTED"]
var sort_options = ["Name", "Type", "Movement Cost", "Rarity", "Effect Count"]

# ===========================================================================
# Element derivation (pure statics -- no scene, so the rules are pinnable)
# ===========================================================================

## The element of [param tile], or &"" when nobody has elemented it.
##
## Two authored sources, in this order, both out of `element_chart.tres`:
##   1. the TILE's own id -- how terrain that grows its own effect is elemented
##      (deep_water -> water, molten_lava -> fire), including terrain whose effect is a
##      legacy [TileEffect] carrying no id to key on;
##   2. the first elemented [TileEffectResource] in its default effects -- how authored
##      effect content is elemented (tall_grass -> nature, sacred_meadow -> nature).
##
## Never a field on the tile: the chart is the single authority (CONQUEST.md rule 9), so
## elementing new terrain stays a one-file content edit.
static func tile_element_of(tile) -> StringName:
	if tile == null:
		return &""

	if tile.has_method("get_id"):
		var by_tile_id: StringName = ElementChart.chart().tile_element(tile.get_id())
		if by_tile_id != &"":
			return by_tile_id

	var defaults = tile.get("default_effects")
	if defaults is Array:
		for effect in (defaults as Array):
			var el: StringName = _effect_own_element(effect)
			if el != &"":
				return el
	return &""


## The element of ONE tile effect on [param tile].
##
## A [TileEffectResource] answers for itself (its [method TileEffectResource.element]
## reads the chart by its own id). A legacy [TileEffect] has no id at all, so it inherits
## the TILE's element -- which is exactly how the chart authored it: `molten_lava -> fire`
## is a TILE id entry standing in for the burn that terrain applies.
static func effect_element_of(effect, tile) -> StringName:
	var own: StringName = _effect_own_element(effect)
	if own != &"":
		return own
	return tile_element_of(tile)


static func _effect_own_element(effect) -> StringName:
	if effect == null or typeof(effect) != TYPE_OBJECT:
		return &""
	if effect.has_method("element"):
		return ElementChartResource.key_of(effect.element())
	return &""


## Elements [param element] hits for LESS than neutral -- the RESISTED half of its matrix
## row.
##
## Deliberately a sibling of [method ElementChartGallery.strong_against] rather than
## something inferred from it: the chart authors every direction explicitly and has no
## implied symmetry, so "hits harder" and "hits softer" are two separate reads of the
## same row.
static func resisted_against(element) -> Array[StringName]:
	var key: StringName = ElementChartResource.key_of(element)
	var out: Array[StringName] = []
	if key == &"":
		return out
	for defender in ElementChartGallery.elements():
		if ElementVisuals.label_for_multiplier(ElementChart.multiplier(key, defender)) \
				== ElementVisuals.RESISTED:
			out.append(defender)
	return out


## "Deals more to nature, less to fire" -- the one-line matchup summary for
## [param element]. "" for an elementless subject (nothing to say), and
## [constant ElementChartGallery.NO_MATCHUPS_TEXT] for an element the chart has authored
## no matchup for at all (wind today) -- reported rather than papered over.
##
## Every name here is READ from the live matrix through
## [method ElementChartGallery.strong_against] / [method resisted_against], so retuning
## `element_chart.tres` retunes this line with no code edit.
static func matchup_hint(element) -> String:
	var key: StringName = ElementChartResource.key_of(element)
	if key == &"":
		return ""
	var more: Array[StringName] = ElementChartGallery.strong_against(key)
	var less: Array[StringName] = resisted_against(key)
	if more.is_empty() and less.is_empty():
		return ElementChartGallery.NO_MATCHUPS_TEXT
	var parts: Array[String] = []
	if not more.is_empty():
		parts.append("Deals more to " + _element_name_list(more))
	if not less.is_empty():
		if parts.is_empty():
			parts.append("Deals less to " + _element_name_list(less))
		else:
			parts.append("less to " + _element_name_list(less))
	return ", ".join(parts)


## Element display names, lower-cased so they read as words inside the hint sentence
## rather than as a second row of chips.
static func _element_name_list(elements: Array) -> String:
	var names: Array[String] = []
	for e in elements:
		var n: String = ElementVisuals.label_for(e).to_lower()
		if n != "":
			names.append(n)
	return ", ".join(names)


func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look (matches Unit/Map galleries)
	_create_ui()
	_load_all_tiles()
	_setup_connections()

func _create_ui() -> void:
	"""Create the complete UI for the tile gallery"""
	# Set up main layout
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Outer 24px breathing room; 16px between the list and detail panels.
	var outer = MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 24)
	outer.add_theme_constant_override("margin_right", 24)
	outer.add_theme_constant_override("margin_top", 24)
	outer.add_theme_constant_override("margin_bottom", 24)
	add_child(outer)

	# Main container
	var main_container = HBoxContainer.new()
	main_container.add_theme_constant_override("separation", 16)
	outer.add_child(main_container)

	# Left panel - Tile list and controls
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)
	left_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	left_panel.add_theme_constant_override("separation", 6)
	main_container.add_child(left_panel)

	# Title and back button
	var header_container = HBoxContainer.new()
	left_panel.add_child(header_container)

	var title = Label.new()
	title.text = "TILE GALLERY"
	title.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", MenuTheme.GOLD)
	title.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(title)

	back_button = Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(80, 40)
	header_container.add_child(back_button)

	# Search and filter controls
	var controls_container = VBoxContainer.new()
	controls_container.add_theme_constant_override("separation", 6)
	left_panel.add_child(controls_container)

	# Search
	controls_container.add_child(_form_label("Search"))

	search_input = LineEdit.new()
	search_input.placeholder_text = "Search tiles..."
	controls_container.add_child(search_input)

	# Filter by type
	controls_container.add_child(_form_label("Filter by type"))

	filter_option = OptionButton.new()
	for tile_type in tile_types:
		filter_option.add_item(tile_type)
	controls_container.add_child(filter_option)

	# Sort options
	controls_container.add_child(_form_label("Sort by"))

	sort_option = OptionButton.new()
	for sort_type in sort_options:
		sort_option.add_item(sort_type)
	controls_container.add_child(sort_option)

	# Tile list
	controls_container.add_child(_form_label("Tiles"))

	tile_list = ItemList.new()
	tile_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	tile_list.custom_minimum_size = Vector2(280, 400)
	controls_container.add_child(tile_list)

	# Right panel - Tile details
	var right_panel = VBoxContainer.new()
	right_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_panel.custom_minimum_size = Vector2(500, 0)
	right_panel.add_theme_constant_override("separation", 8)
	main_container.add_child(right_panel)
	
	_create_tile_display(right_panel)

func _create_tile_display(parent: VBoxContainer) -> void:
	"""Create the tile display area"""
	tile_display_container = VBoxContainer.new()
	tile_display_container.add_theme_constant_override("separation", 10)
	parent.add_child(tile_display_container)

	# Tile header
	var header_container = HBoxContainer.new()
	tile_display_container.add_child(header_container)

	# Tile basic info
	var info_container = VBoxContainer.new()
	info_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(info_container)

	tile_name_label = Label.new()
	tile_name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	tile_name_label.add_theme_color_override("font_color", MenuTheme.GOLD)
	info_container.add_child(tile_name_label)

	tile_type_label = Label.new()
	tile_type_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	info_container.add_child(tile_type_label)

	# Element badge + matchup hint. ONE row, built once and re-pointed per selection
	# (ElementVisuals badges are made to be re-pointed, not rebuilt), and hidden whole for
	# an elementless tile so the header costs those tiles nothing.
	tile_element_row = HBoxContainer.new()
	tile_element_row.name = TILE_ELEMENT_ROW_NAME
	tile_element_row.add_theme_constant_override("separation", 8)
	info_container.add_child(tile_element_row)

	tile_element_badge = ElementVisuals.make_badge(&"", MenuTheme.FONT_CAPTION, BADGE_CAP)
	tile_element_badge.name = TILE_BADGE_NAME
	# SHRINK_BEGIN, not the badge default SHRINK_END: this row is left-aligned under the
	# tile's name, so the chip must hug the left edge rather than the far side of the panel.
	tile_element_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tile_element_row.add_child(tile_element_badge)

	tile_matchup_label = Label.new()
	tile_matchup_label.name = TILE_MATCHUP_NAME
	tile_matchup_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	tile_matchup_label.modulate = MenuTheme.CREAM_DIM
	tile_matchup_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	tile_element_row.add_child(tile_matchup_label)

	tile_element_row.visible = false

	# Description
	tile_display_container.add_child(_section_header("Description"))

	tile_description = RichTextLabel.new()
	tile_description.custom_minimum_size = Vector2(0, 80)
	tile_description.fit_content = true
	tile_display_container.add_child(tile_description)

	# 3D Tile preview
	tile_display_container.add_child(_section_header("3D Preview"))

	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(300, 200)
	viewport_container.stretch = true
	tile_display_container.add_child(viewport_container)
	
	tile_preview_viewport = SubViewport.new()
	tile_preview_viewport.size = Vector2(300, 200)
	tile_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(tile_preview_viewport)
	
	# Add camera and lighting to viewport
	_setup_preview_viewport()
	
	# Properties section
	tile_display_container.add_child(_section_header("Properties"))

	properties_container = VBoxContainer.new()
	tile_display_container.add_child(properties_container)

	# Effects section
	tile_display_container.add_child(_section_header("Tile Effects"))

	effects_container = VBoxContainer.new()
	effects_container.add_theme_constant_override("separation", 8)
	tile_display_container.add_child(effects_container)

	# Initially hide tile display
	tile_display_container.visible = false


func _section_header(text: String) -> Label:
	var label = Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	return label


## Small muted caption above a form control (search / filter / sort / list).
func _form_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	label.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	return label

func _setup_preview_viewport() -> void:
	"""Set up the 3D tile preview viewport with camera and lighting"""
	# Add camera
	var camera = Camera3D.new()
	# look_at_from_position orients without requiring the node be in the tree yet
	# (plain look_at() errors here because it is called before add_child()).
	camera.look_at_from_position(Vector3(2, 3, 2), Vector3(0, 0, 0), Vector3.UP)
	tile_preview_viewport.add_child(camera)

	# Add lighting
	var light = DirectionalLight3D.new()
	light.look_at_from_position(Vector3(2, 3, 2), Vector3(0, 0, 0), Vector3.UP)
	light.light_energy = 1.0
	tile_preview_viewport.add_child(light)
	
	# Add environment
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.3, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5, 1.0)
	env.ambient_light_energy = 0.3
	camera.environment = env

func _setup_connections() -> void:
	"""Set up signal connections"""
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	if tile_list:
		tile_list.item_selected.connect(_on_tile_selected)
	
	if search_input:
		search_input.text_changed.connect(_on_search_changed)
	
	if filter_option:
		filter_option.item_selected.connect(_on_filter_changed)
	
	if sort_option:
		sort_option.item_selected.connect(_on_sort_changed)

func _load_all_tiles() -> void:
	"""Load all available tile resources, via TileCatalog.

	This used to scan res://game/tiles/resources/ NON-RECURSIVELY and, finding
	nothing, call _create_default_tiles() to "helpfully" regenerate a starter set.
	Once tiles moved into biome folders (forest/, volcano/, ice/, common/) that
	flat scan matched zero files, so every visit to this gallery wrote four
	STALE-format tiles (no id, no model_path) back into the root -- shadowing the
	real ones and tripping TileCatalog's duplicate-id guard. Hosting the gallery
	inside the Compendium turned that from occasional into routine.

	TileCatalog walks the whole tree and is the same index the map creator, the
	map gallery and MapLoader use, so the gallery now sees exactly what the game
	sees. The regeneration fallback is deliberately gone: 17 tiles ship with the
	project, and recreating obsolete copies can only corrupt the catalog.
	"""
	all_tiles.clear()

	TileCatalog.rescan()
	for resource_path in TileCatalog.all_paths():
		var resource = load(resource_path)
		if resource is TileResource:
			all_tiles.append(resource)

	if all_tiles.is_empty():
		push_warning("[TileGallery] No TileResource found under " + TileCatalog.ROOT)

	# Apply initial filter and sort
	_apply_filters()

func _create_default_tiles() -> void:
	"""Create default tile examples and save them as resources"""

	# Ensure directory exists
	if not DirAccess.dir_exists_absolute("res://game/tiles/resources/"):
		DirAccess.open("res://").make_dir_recursive("game/tiles/resources")
	
	# Grass Plains Tile (No effects)
	var grass_tile = TileResource.new()
	grass_tile.tile_name = "Grass Plains"
	grass_tile.tile_type = Tile.TileType.NORMAL
	grass_tile.description = "Standard grassy terrain that's easy to traverse. No special effects."
	grass_tile.base_movement_cost = 1
	grass_tile.is_passable = true
	grass_tile.blocks_line_of_sight = false
	grass_tile.base_color = Color(0.4, 0.8, 0.3, 1.0)  # Green
	grass_tile.emission_enabled = false
	grass_tile.metallic = 0.0
	grass_tile.roughness = 1.0
	grass_tile.has_default_effects = false
	grass_tile.default_effects = []
	grass_tile.provides_cover = false
	grass_tile.cover_bonus = 0
	grass_tile.elevation = 0
	grass_tile.rarity = "Common"
	grass_tile.generation_weight = 1.0
	all_tiles.append(grass_tile)
	
	# Save grass tile
	ResourceSaver.save(grass_tile, "res://game/tiles/resources/grass_plains.tres")
	
	# Molten Lava Tile (Fire damage)
	var lava_tile = TileResource.new()
	lava_tile.tile_name = "Molten Lava"
	lava_tile.tile_type = Tile.TileType.LAVA
	lava_tile.description = "Dangerous molten rock that burns anything that steps on it. Deals 10 fire damage per turn to units standing on it."
	lava_tile.base_movement_cost = 2
	lava_tile.is_passable = true
	lava_tile.blocks_line_of_sight = false
	lava_tile.base_color = Color(1.0, 0.2, 0.0, 1.0)  # Red
	lava_tile.emission_enabled = true
	lava_tile.emission_color = Color(1.0, 0.3, 0.0)  # Orange glow
	lava_tile.metallic = 0.0
	lava_tile.roughness = 0.8
	lava_tile.has_default_effects = true
	lava_tile.provides_cover = false
	lava_tile.cover_bonus = 0
	lava_tile.elevation = 0
	lava_tile.rarity = "Rare"
	lava_tile.generation_weight = 0.3
	
	# Create fire damage effect
	var fire_effect = TileEffect.new()
	fire_effect.effect_name = "Lava Burn"
	fire_effect.effect_type = TileEffect.EffectType.FIRE_DAMAGE
	fire_effect.strength = 10  # 10 damage per turn (editable)
	fire_effect.duration = -1  # Permanent effect
	fire_effect.triggers_on_enter = true
	fire_effect.triggers_on_turn_start = true
	fire_effect.triggers_on_turn_end = false
	fire_effect.triggers_on_exit = false
	
	lava_tile.default_effects = [fire_effect]
	all_tiles.append(lava_tile)
	
	# Save lava tile
	ResourceSaver.save(lava_tile, "res://game/tiles/resources/molten_lava.tres")
	
	# Deep Water Tile
	var water_tile = TileResource.new()
	water_tile.tile_name = "Deep Water"
	water_tile.tile_type = Tile.TileType.WATER
	water_tile.description = "Deep water that slows movement but can be crossed by most units."
	water_tile.base_movement_cost = 3
	water_tile.is_passable = true
	water_tile.blocks_line_of_sight = false
	water_tile.base_color = Color(0.2, 0.4, 0.8, 1.0)  # Blue
	water_tile.emission_enabled = false
	water_tile.metallic = 0.8
	water_tile.roughness = 0.1
	water_tile.has_default_effects = false
	water_tile.default_effects = []
	water_tile.provides_cover = false
	water_tile.cover_bonus = 0
	water_tile.elevation = -1
	water_tile.rarity = "Common"
	water_tile.generation_weight = 0.8
	all_tiles.append(water_tile)
	
	# Save water tile
	ResourceSaver.save(water_tile, "res://game/tiles/resources/deep_water.tres")
	
	# Stone Wall Tile
	var wall_tile = TileResource.new()
	wall_tile.tile_name = "Stone Wall"
	wall_tile.tile_type = Tile.TileType.WALL
	wall_tile.description = "Solid stone wall that blocks movement and provides cover from attacks."
	wall_tile.base_movement_cost = 999  # Impassable
	wall_tile.is_passable = false
	wall_tile.blocks_line_of_sight = true
	wall_tile.base_color = Color(0.3, 0.3, 0.3, 1.0)  # Gray
	wall_tile.emission_enabled = false
	wall_tile.metallic = 0.2
	wall_tile.roughness = 0.9
	wall_tile.has_default_effects = false
	wall_tile.default_effects = []
	wall_tile.provides_cover = true
	wall_tile.cover_bonus = 3
	wall_tile.elevation = 2
	wall_tile.rarity = "Common"
	wall_tile.generation_weight = 0.5
	all_tiles.append(wall_tile)
	
	# Save wall tile
	ResourceSaver.save(wall_tile, "res://game/tiles/resources/stone_wall.tres")

func _apply_filters() -> void:
	"""Apply current search, filter, and sort settings"""
	# Safely duplicate the array, handling null values
	filtered_tiles.clear()
	for tile in all_tiles:
		if tile != null:
			filtered_tiles.append(tile)
	
	# Apply search filter
	var search_text = search_input.text.to_lower() if search_input else ""
	if not search_text.is_empty():
		filtered_tiles = filtered_tiles.filter(func(tile): 
			return tile.tile_name.to_lower().contains(search_text) or Tile.TileType.keys()[tile.tile_type].to_lower().contains(search_text) or tile.description.to_lower().contains(search_text)
		)
	
	# Apply type filter
	var selected_type = tile_types[filter_option.selected] if filter_option else "All"
	if selected_type != "All":
		filtered_tiles = filtered_tiles.filter(func(tile): 
			return Tile.TileType.keys()[tile.tile_type] == selected_type
		)
	
	# Apply sorting
	var sort_type = sort_options[sort_option.selected] if sort_option else "Name"
	match sort_type:
		"Name":
			filtered_tiles.sort_custom(func(a, b): return a.tile_name < b.tile_name)
		"Type":
			filtered_tiles.sort_custom(func(a, b): 
				return Tile.TileType.keys()[a.tile_type] < Tile.TileType.keys()[b.tile_type]
			)
		"Movement Cost":
			filtered_tiles.sort_custom(func(a, b): return a.get_movement_cost() < b.get_movement_cost())
		"Rarity":
			var rarity_order = {"Common": 0, "Uncommon": 1, "Rare": 2, "Epic": 3, "Legendary": 4}
			filtered_tiles.sort_custom(func(a, b): 
				var a_val = rarity_order.get(a.rarity, 0)
				var b_val = rarity_order.get(b.rarity, 0)
				return a_val < b_val
			)
		"Effect Count":
			filtered_tiles.sort_custom(func(a, b): 
				return a.default_effects.size() > b.default_effects.size()
			)
	
	_update_tile_list()

func _update_tile_list() -> void:
	"""Update the tile list display"""
	if not tile_list:
		return
	
	tile_list.clear()
	
	for tile in filtered_tiles:
		var type_name = Tile.TileType.keys()[tile.tile_type]
		var display_text = tile.tile_name + " (" + type_name + ")"
		tile_list.add_item(display_text)
	
	# Update count display
	if tile_list.get_item_count() == 0:
		tile_list.add_item("No tiles found")
		tile_list.set_item_disabled(0, true)

func _display_tile(tile: TileResource) -> void:
	"""Display detailed information for the selected tile"""
	current_tile = tile
	
	if not tile_display_container:
		return
	
	tile_display_container.visible = true
	
	# Update basic info
	if tile_name_label:
		tile_name_label.text = tile.tile_name
	
	if tile_type_label:
		var type_name = Tile.TileType.keys()[tile.tile_type]
		tile_type_label.text = type_name + "  -  " + tile.rarity

		# Colour code by rarity, in the theme's warmer register rather than raw
		# primaries, so the tag sits with the gold/cream palette instead of fighting it.
		match tile.rarity:
			"Common":
				tile_type_label.modulate = MenuTheme.CREAM_DIM
			"Uncommon":
				tile_type_label.modulate = Color("6fae5a")
			"Rare":
				tile_type_label.modulate = Color("5a9bd6")
			"Epic":
				tile_type_label.modulate = Color("a86fd0")
			"Legendary":
				tile_type_label.modulate = MenuTheme.GOLD
	
	# Element badge + matchup hint (absent entirely for an unelemented tile).
	_update_tile_element(tile)

	if tile_description:
		tile_description.text = tile.description

	# Update 3D preview
	_update_tile_preview(tile)
	
	# Update properties
	_update_tile_properties(tile)
	
	# Update effects
	_update_tile_effects(tile)

func _update_tile_element(tile: TileResource) -> void:
	"""Point the header's element badge + matchup hint at [param tile].

	An elementless tile hides the WHOLE row, badge and hint together -- the chart leaves
	pure-utility terrain neutral on purpose, and a row reading "Neutral / no matchups" on
	most of the catalogue would be furniture rather than information."""
	if tile_element_row == null or not is_instance_valid(tile_element_row):
		return

	var element: StringName = tile_element_of(tile)
	if element == &"":
		tile_element_row.visible = false
		ElementVisuals.update_badge(tile_element_badge, &"", BADGE_CAP)
		if tile_matchup_label != null:
			tile_matchup_label.text = ""
		return

	tile_element_row.visible = true
	ElementVisuals.update_badge(tile_element_badge, element, BADGE_CAP)
	if tile_matchup_label != null:
		tile_matchup_label.text = matchup_hint(element)


func _update_tile_preview(tile: TileResource) -> void:
	"""Update the 3D tile preview"""
	if not tile_preview_viewport:
		return
	
	# Clear existing tile
	if current_tile_preview:
		current_tile_preview.queue_free()
		current_tile_preview = null
	
	# Create simple 3D preview without using the complex Tile class
	current_tile_preview = Node3D.new()
	current_tile_preview.name = "TilePreview"
	
	# Create mesh
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(2, 0.2, 2)
	mesh_instance.mesh = mesh
	current_tile_preview.add_child(mesh_instance)
	
	# Apply material directly from TileResource
	var material = tile.create_material()
	mesh_instance.material_override = material
	
	tile_preview_viewport.add_child(current_tile_preview)
	
	# Position tile at origin
	current_tile_preview.position = Vector3(0, 0, 0)

func _update_tile_properties(tile: TileResource) -> void:
	"""Update the properties display"""
	if not properties_container:
		return
	
	# Clear existing properties
	for child in properties_container.get_children():
		child.queue_free()
	
	# Create properties grid
	var properties_grid = GridContainer.new()
	properties_grid.columns = 2
	properties_grid.add_theme_constant_override("h_separation", 12)
	properties_grid.add_theme_constant_override("v_separation", 6)
	properties_container.add_child(properties_grid)

	# Add properties
	var properties = [
		["Movement Cost", str(tile.get_movement_cost())],
		["Passable", "Yes" if tile.is_tile_passable() else "No"],
		["Blocks Sight", "Yes" if tile.blocks_line_of_sight else "No"],
		["Provides Cover", "Yes" if tile.provides_cover else "No"],
		["Cover Bonus", str(tile.cover_bonus) if tile.provides_cover else "N/A"],
		["Elevation", str(tile.elevation)],
		["Rarity", tile.rarity],
		["Has Effects", "Yes" if tile.has_default_effects else "No"]
	]

	for prop in properties:
		var label = Label.new()
		label.text = prop[0] + ":"
		label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		label.modulate = Color(0.72, 0.70, 0.78)
		properties_grid.add_child(label)

		var value = Label.new()
		value.text = prop[1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		properties_grid.add_child(value)

func _update_tile_effects(tile: TileResource) -> void:
	"""Update the effects display"""
	if not effects_container:
		return
	
	# Clear existing effects
	for child in effects_container.get_children():
		child.queue_free()
	
	if not tile.has_default_effects:
		var no_effects = Label.new()
		no_effects.text = "This tile has no special effects"
		no_effects.modulate = MenuTheme.CREAM_DIM
		effects_container.add_child(no_effects)
		return

	# Two authoring formats live side by side here, and the gallery used to show only the
	# first: create_tile_effects() returns the LEGACY TileEffect list (type-derived, plus
	# any legacy entries in default_effects) and silently drops every authored
	# TileEffectResource -- which is exactly the half that carries an element. Both are
	# listed now, so an elemented tile's page finally has an effect to badge.
	var effects = tile.create_tile_effects()
	var authored: Array = _authored_effect_resources(tile)

	if effects.is_empty() and authored.is_empty():
		var no_effects = Label.new()
		no_effects.text = "No effects configured"
		no_effects.modulate = MenuTheme.CREAM_DIM
		effects_container.add_child(no_effects)
		return

	# Accent tile effects in the piercing-orange used for hazards elsewhere, so
	# each effect reads as a left-accented card matching the unit move cards.
	var accent = Color("f0913c")
	for effect in effects:
		var card = PanelContainer.new()
		card.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		card.add_theme_stylebox_override("panel", MenuTheme.card_box(accent))
		effects_container.add_child(card)

		var effect_container = VBoxContainer.new()
		effect_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		card.add_child(effect_container)

		# Effect name and type chip
		var effect_header = HBoxContainer.new()
		effect_header.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		effect_container.add_child(effect_header)

		var effect_name = Label.new()
		effect_name.text = effect.effect_name
		effect_name.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
		effect_name.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		effect_header.add_child(effect_name)

		_add_effect_element_badge(effect_header, effect, tile)

		effect_header.add_child(MenuTheme.make_chip(
			TileEffect.EffectType.keys()[effect.effect_type], accent))

		# Effect description
		var effect_desc = Label.new()
		effect_desc.text = effect._get_effect_description()
		effect_desc.modulate = MenuTheme.CREAM_DIM
		effect_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_desc.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		effect_container.add_child(effect_desc)

		# Effect properties
		var props_text = "Strength: " + str(effect.strength)
		if effect.duration > 0:
			props_text += "   -   Duration: " + str(effect.duration) + " turns"
		elif effect.duration == -1:
			props_text += "   -   Duration: Permanent"
		else:
			props_text += "   -   Duration: Instant"

		var effect_props = Label.new()
		effect_props.text = props_text
		effect_props.modulate = Color(0.72, 0.70, 0.78)
		effect_props.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		effect_container.add_child(effect_props)

		_add_effect_matchup_hint(effect_container, effect, tile)

	for authored_effect in authored:
		_add_effect_resource_card(authored_effect, tile, accent)


## The authored [TileEffectResource]s on [param tile]. Kept separate from
## [method TileResource.create_tile_effects], which is typed Array[TileEffect] and
## therefore cannot carry them.
func _authored_effect_resources(tile: TileResource) -> Array:
	var out: Array = []
	var defaults = tile.get("default_effects")
	if not (defaults is Array):
		return out
	for effect in (defaults as Array):
		if effect != null and effect is TileEffectResource:
			out.append(effect)
	return out


## One card for an authored [TileEffectResource]: its name, its element badge, the trigger
## it fires on, and -- only when it differs from the header's -- its matchup hint.
##
## Deliberately COMPACT (a header row and at most one caption). The right column's budget
## is already spent on the description, the 3D preview and the eight-row property grid;
## this section gets the slack that is left, so a card here states what the effect IS and
## sends the rest to the effect's own place in the game.
func _add_effect_resource_card(effect: TileEffectResource, tile: TileResource, accent: Color) -> void:
	var card := PanelContainer.new()
	card.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(accent))
	effects_container.add_child(card)

	var body := VBoxContainer.new()
	body.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	card.add_child(body)

	var header := HBoxContainer.new()
	header.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	body.add_child(header)

	var name_label := Label.new()
	var shown: String = effect.display_name.strip_edges()
	if shown == "":
		shown = String(effect.id).capitalize()
	name_label.text = shown
	name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	name_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header.add_child(name_label)

	_add_effect_element_badge(header, effect, tile)

	header.add_child(MenuTheme.make_chip(
			TileEffectResource.Trigger.keys()[effect.trigger], accent))

	_add_effect_matchup_hint(body, effect, tile)

	# A pass-through TRAP says so on its card -- the same authored line the terrain
	# panel shows in battle (TileEffectResource.trap_descriptor, "" for non-traps).
	var trap_line: String = String(effect.trap_descriptor()) if effect.has_method("trap_descriptor") else ""
	if trap_line != "":
		var trap_label := Label.new()
		trap_label.name = "TrapDescriptor"
		trap_label.text = trap_line
		trap_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		trap_label.add_theme_color_override("font_color", MenuTheme.GOLD)
		body.add_child(trap_label)


## Append the element badge for [param effect] to [param row], or nothing at all when the
## effect is elementless. Absence is the authored answer -- see the file header.
func _add_effect_element_badge(row: HBoxContainer, effect, tile: TileResource) -> void:
	var element: StringName = effect_element_of(effect, tile)
	if element == &"":
		return
	var badge := ElementVisuals.make_badge(element, MenuTheme.FONT_CAPTION, BADGE_CAP)
	badge.name = EFFECT_BADGE_NAME
	row.add_child(badge)


## Append the matchup hint for [param effect] to [param body] -- but ONLY when it is not
## already the line the header row is showing for the tile as a whole. Every shipped tile
## takes its effect's element from the tile itself, so in practice this adds no row at all
## and the section keeps its existing budget; a tile whose effect is elemented differently
## from its terrain is the case that needs saying twice.
func _add_effect_matchup_hint(body: VBoxContainer, effect, tile: TileResource) -> void:
	var element: StringName = effect_element_of(effect, tile)
	if element == &"" or element == tile_element_of(tile):
		return
	var hint: String = matchup_hint(element)
	if hint == "":
		return
	var label := Label.new()
	label.text = hint
	label.modulate = MenuTheme.CREAM_DIM
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	body.add_child(label)

# Signal handlers
func _on_back_pressed() -> void:
	"""Handle back button press"""
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _on_tile_selected(index: int) -> void:
	"""Handle tile selection from list"""
	if index >= 0 and index < filtered_tiles.size():
		var selected_tile = filtered_tiles[index]
		if selected_tile != null:
			_display_tile(selected_tile)
		else:
			push_warning("TileGallery: Selected tile is null at index " + str(index))

func _on_search_changed(new_text: String) -> void:
	"""Handle search text change"""
	_apply_filters()

func _on_filter_changed(index: int) -> void:
	"""Handle filter option change"""
	_apply_filters()

func _on_sort_changed(index: int) -> void:
	"""Handle sort option change"""
	_apply_filters()

# Input handling
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_ESCAPE:
				_on_back_pressed()
			KEY_F5:
				# Refresh tile list
				_load_all_tiles()

func _exit_tree() -> void:
	"""Clean up when exiting"""
	if current_tile_preview:
		current_tile_preview.queue_free()
