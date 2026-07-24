extends Control

class_name UnitGallery

# Unit Gallery - a Pokedex-style browser over the character roster.
#
# The gallery is driven DIRECTLY by CharacterResource (game/characters/roster/*.tres,
# via CharacterLibrary). It used to derive a UnitStatsResource per character and show
# that instead, but UnitStatsResource carries no moveset and no abilities, so the moves
# panel could only ever show hardcoded placeholders keyed off a legacy class string.
# Reading the CharacterResource means the REAL authored content - a move's targeting,
# accuracy, crit and effect list, an ability's trigger and effects - is what is shown.
#
# There is exactly ONE piece of "which unit is on screen" state: _current_index, an
# index into filtered_characters. The ItemList, the Prev/Next pager and the Left/Right
# arrow keys all route through _select_index(), so the list and the detail pane can
# never disagree.

# --- Card accents -----------------------------------------------------------
# Move cards are colour-coded by damage category so a moveset is scannable at a
# glance; the element (when authored) is named in the small type tag on the card.
const CAT_PHYSICAL := Color("c9cbd6")   # steel grey
const CAT_MAGICAL := Color("a860e0")    # arcane violet
const CAT_TRUE := Color("f0913c")       # piercing orange
const ABILITY_ACCENT := Color("5fb84e") # passives read as "nature" green

const MUTED := Color(0.72, 0.70, 0.78)

# Turntable speed for the model preview (radians / second) - slow, like the old tween.
const MODEL_SPIN_SPEED := 0.45

# UI Elements
@onready var back_button: Button
@onready var unit_list: ItemList
@onready var unit_display_container: VBoxContainer
@onready var unit_name_label: Label
@onready var unit_type_label: Label
@onready var unit_description: RichTextLabel
@onready var unit_portrait: TextureRect
@onready var portrait_placeholder: Label
@onready var unit_model_viewport: SubViewport
@onready var model_viewport_container: SubViewportContainer
@onready var model_placeholder: Label
@onready var stats_container: VBoxContainer
@onready var moves_container: VBoxContainer
@onready var abilities_container: VBoxContainer
@onready var search_input: LineEdit
@onready var filter_option: OptionButton
@onready var sort_option: OptionButton
@onready var prev_button: Button
@onready var next_button: Button
@onready var index_label: Label

# Data
var all_characters: Array[CharacterResource] = []
var filtered_characters: Array[CharacterResource] = []
var current_character: CharacterResource
var current_model_instance: Node3D

# THE source of truth for what is displayed: an index into filtered_characters.
# -1 means "nothing shown" (empty filter result).
var _current_index: int = -1

# Filter and sort options. The old fixed-class list ("Warrior"/"Archer"/...) is gone
# along with the classes themselves - these filter on properties characters actually
# have today.
var filter_modes: Array[String] = ["All", "Bosses", "Standard", "Has Abilities", "Has Moves"]
var sort_options: Array[String] = ["Name", "Health", "Attack", "Defense", "Speed", "Moves", "Total Stats"]


func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look
	_create_ui()
	_load_all_characters()
	_setup_connections()
	_apply_filters()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _create_ui() -> void:
	"""Create the complete UI for the unit gallery"""
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var main_container := HBoxContainer.new()
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_container)

	# --- Left panel: list + controls ---
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)
	main_container.add_child(left_panel)

	var header_container := HBoxContainer.new()
	left_panel.add_child(header_container)

	var title := Label.new()
	title.text = "UNIT GALLERY"
	title.add_theme_font_size_override("font_size", 24)
	title.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(title)

	back_button = Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(80, 40)
	header_container.add_child(back_button)

	var search_label := Label.new()
	search_label.text = "Search:"
	left_panel.add_child(search_label)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Search units..."
	left_panel.add_child(search_input)

	var filter_label := Label.new()
	filter_label.text = "Filter:"
	left_panel.add_child(filter_label)

	filter_option = OptionButton.new()
	for mode in filter_modes:
		filter_option.add_item(mode)
	left_panel.add_child(filter_option)

	var sort_label := Label.new()
	sort_label.text = "Sort by:"
	left_panel.add_child(sort_label)

	sort_option = OptionButton.new()
	for sort_type in sort_options:
		sort_option.add_item(sort_type)
	left_panel.add_child(sort_option)

	var list_label := Label.new()
	list_label.text = "Units:"
	left_panel.add_child(list_label)

	unit_list = ItemList.new()
	unit_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	unit_list.custom_minimum_size = Vector2(280, 320)
	left_panel.add_child(unit_list)

	# --- Right panel: pager + scrolling detail ---
	var right_panel := VBoxContainer.new()
	right_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_panel.custom_minimum_size = Vector2(500, 0)
	main_container.add_child(right_panel)

	_create_pager(right_panel)

	# The detail pane is tall (stats + every move + every ability), so it scrolls.
	var scroll := ScrollContainer.new()
	scroll.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(scroll)

	var scroll_body := VBoxContainer.new()
	scroll_body.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.add_child(scroll_body)

	_create_unit_display(scroll_body)


func _create_pager(parent: VBoxContainer) -> void:
	"""Pokedex-style Prev / index / Next row. Mirrored on the Left/Right arrow keys."""
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(pager)

	prev_button = Button.new()
	prev_button.text = "< PREV"
	prev_button.custom_minimum_size = Vector2(110, 36)
	pager.add_child(prev_button)

	index_label = Label.new()
	index_label.text = "0 / 0"
	index_label.custom_minimum_size = Vector2(110, 0)
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	index_label.add_theme_font_size_override("font_size", 16)
	pager.add_child(index_label)

	next_button = Button.new()
	next_button.text = "NEXT >"
	next_button.custom_minimum_size = Vector2(110, 36)
	pager.add_child(next_button)


func _create_unit_display(parent: VBoxContainer) -> void:
	"""Create the unit detail area"""
	unit_display_container = VBoxContainer.new()
	unit_display_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	parent.add_child(unit_display_container)

	# --- Header: portrait + name/identity ---
	var header_container := HBoxContainer.new()
	unit_display_container.add_child(header_container)

	var portrait_slot := PanelContainer.new()
	portrait_slot.custom_minimum_size = Vector2(120, 120)
	header_container.add_child(portrait_slot)

	unit_portrait = TextureRect.new()
	unit_portrait.custom_minimum_size = Vector2(104, 104)
	unit_portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	unit_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_slot.add_child(unit_portrait)

	# Shown instead of the TextureRect when a character has no portrait authored.
	portrait_placeholder = Label.new()
	portrait_placeholder.text = "No\nportrait"
	portrait_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_placeholder.modulate = MUTED
	portrait_slot.add_child(portrait_placeholder)

	var info_container := VBoxContainer.new()
	info_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(info_container)

	unit_name_label = Label.new()
	unit_name_label.add_theme_font_size_override("font_size", 22)
	info_container.add_child(unit_name_label)

	unit_type_label = Label.new()
	unit_type_label.add_theme_font_size_override("font_size", 14)
	unit_type_label.modulate = MUTED
	unit_type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_container.add_child(unit_type_label)

	# --- Description ---
	unit_display_container.add_child(_section_header("Description"))

	unit_description = RichTextLabel.new()
	unit_description.custom_minimum_size = Vector2(0, 60)
	unit_description.fit_content = true
	unit_display_container.add_child(unit_description)

	# --- 3D model ---
	unit_display_container.add_child(_section_header("Model"))

	model_viewport_container = SubViewportContainer.new()
	model_viewport_container.custom_minimum_size = Vector2(300, 200)
	model_viewport_container.stretch = true
	unit_display_container.add_child(model_viewport_container)

	unit_model_viewport = SubViewport.new()
	unit_model_viewport.size = Vector2i(300, 200)
	unit_model_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	model_viewport_container.add_child(unit_model_viewport)

	_setup_model_viewport()

	# Most roster characters have no model_scene yet; they get this instead of an
	# empty black viewport.
	model_placeholder = Label.new()
	model_placeholder.text = "No 3D model authored for this character."
	model_placeholder.modulate = MUTED
	model_placeholder.visible = false
	unit_display_container.add_child(model_placeholder)

	# --- Stats ---
	unit_display_container.add_child(_section_header("Statistics"))

	stats_container = VBoxContainer.new()
	unit_display_container.add_child(stats_container)

	# --- Moves ---
	unit_display_container.add_child(_section_header("Moves"))

	moves_container = VBoxContainer.new()
	moves_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	moves_container.add_theme_constant_override("separation", 8)
	unit_display_container.add_child(moves_container)

	# --- Abilities ---
	unit_display_container.add_child(_section_header("Abilities"))

	abilities_container = VBoxContainer.new()
	abilities_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	abilities_container.add_theme_constant_override("separation", 8)
	unit_display_container.add_child(abilities_container)

	# Hidden until a character is selected (an empty filter keeps it hidden).
	unit_display_container.visible = false


func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = MenuTheme.GOLD
	return label


func _setup_model_viewport() -> void:
	"""Set up the 3D model viewport with camera and lighting"""
	if not unit_model_viewport:
		return

	var camera := Camera3D.new()
	# look_at_from_position orients without requiring the node be in the tree yet
	# (plain look_at() errors here because it is called before add_child()).
	camera.look_at_from_position(Vector3(0, 1.5, 3), Vector3(0, 1, 0), Vector3.UP)
	unit_model_viewport.add_child(camera)

	var light := DirectionalLight3D.new()
	light.look_at_from_position(Vector3(2, 3, 2), Vector3(0, 0, 0), Vector3.UP)
	light.light_energy = 1.1
	unit_model_viewport.add_child(light)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.09, 0.13, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.42, 0.52, 1.0)
	env.ambient_light_energy = 0.4
	camera.environment = env


func _setup_connections() -> void:
	"""Set up signal connections"""
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	if unit_list:
		unit_list.item_selected.connect(_on_unit_selected)

	if search_input:
		search_input.text_changed.connect(_on_search_changed)

	if filter_option:
		filter_option.item_selected.connect(_on_filter_changed)

	if sort_option:
		sort_option.item_selected.connect(_on_sort_changed)

	if prev_button:
		prev_button.pressed.connect(_on_prev_pressed)

	if next_button:
		next_button.pressed.connect(_on_next_pressed)


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

func _load_all_characters() -> void:
	"""Load every roster CharacterResource (game/characters/roster/*.tres).

	These ARE the units - the fixed-class UnitStatsResource directory was retired,
	and a CharacterResource is the canonical stat block a live Unit reads from. It
	is also the only place the moveset and abilities exist, which is why the gallery
	keeps the resource itself rather than deriving a stripped-down copy."""
	all_characters.clear()

	for character_id in CharacterLibrary.all_ids():
		var character: CharacterResource = CharacterLibrary.get_character(character_id)
		if character != null:
			all_characters.append(character)


# ---------------------------------------------------------------------------
# Filtering / sorting / list
# ---------------------------------------------------------------------------

func _apply_filters() -> void:
	"""Rebuild filtered_characters from the search/filter/sort controls, refresh the
	ItemList, and re-point _current_index (keeping the same character on screen when
	it survived the filter)."""
	var previous: CharacterResource = current_character

	filtered_characters = all_characters.duplicate()

	# Search: name, id, description, move names and ability names all match.
	var search_text: String = ""
	if search_input:
		search_text = search_input.text.strip_edges().to_lower()
	if not search_text.is_empty():
		var matched: Array[CharacterResource] = []
		for character in filtered_characters:
			if _character_matches(character, search_text):
				matched.append(character)
		filtered_characters = matched

	# Filter mode.
	var mode: String = "All"
	if filter_option and filter_option.selected >= 0 and filter_option.selected < filter_modes.size():
		mode = filter_modes[filter_option.selected]
	if mode != "All":
		var kept: Array[CharacterResource] = []
		for character in filtered_characters:
			if _character_passes_mode(character, mode):
				kept.append(character)
		filtered_characters = kept

	# Sort.
	var sort_type: String = "Name"
	if sort_option and sort_option.selected >= 0 and sort_option.selected < sort_options.size():
		sort_type = sort_options[sort_option.selected]
	match sort_type:
		"Name":
			filtered_characters.sort_custom(
				func(a: CharacterResource, b: CharacterResource) -> bool:
					return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
		"Health":
			filtered_characters.sort_custom(
				func(a: CharacterResource, b: CharacterResource) -> bool:
					return a.base_health > b.base_health)
		"Attack":
			filtered_characters.sort_custom(
				func(a: CharacterResource, b: CharacterResource) -> bool:
					return a.base_attack > b.base_attack)
		"Defense":
			filtered_characters.sort_custom(
				func(a: CharacterResource, b: CharacterResource) -> bool:
					return a.base_defense > b.base_defense)
		"Speed":
			filtered_characters.sort_custom(
				func(a: CharacterResource, b: CharacterResource) -> bool:
					return a.base_speed > b.base_speed)
		"Moves":
			filtered_characters.sort_custom(
				func(a: CharacterResource, b: CharacterResource) -> bool:
					return a.move_count() > b.move_count())
		"Total Stats":
			filtered_characters.sort_custom(
				func(a: CharacterResource, b: CharacterResource) -> bool:
					return a.power_budget() > b.power_budget())

	_update_unit_list()

	# Keep showing the same character when it is still in the list; otherwise fall
	# back to the first entry (or nothing at all when the filter is empty).
	var target: int = 0
	if previous != null:
		var found: int = filtered_characters.find(previous)
		if found >= 0:
			target = found
	if filtered_characters.is_empty():
		target = -1
	_select_index(target)


func _character_matches(character: CharacterResource, search_text: String) -> bool:
	"""True when the character's identity, description, or any move/ability name
	contains the search text."""
	if character == null:
		return false
	if character.display_name.to_lower().contains(search_text):
		return true
	if String(character.character_id).to_lower().contains(search_text):
		return true
	if character.description.to_lower().contains(search_text):
		return true
	for move in character.moveset:
		if move != null and move.display_name.to_lower().contains(search_text):
			return true
	for ability in character.abilities:
		if ability != null and ability.display_name.to_lower().contains(search_text):
			return true
	return false


func _character_passes_mode(character: CharacterResource, mode: String) -> bool:
	if character == null:
		return false
	match mode:
		"Bosses":
			return character.is_boss
		"Standard":
			return not character.is_boss
		"Has Abilities":
			return character.ability_count() > 0
		"Has Moves":
			return character.move_count() > 0
	return true


func _update_unit_list() -> void:
	"""Repopulate the ItemList from filtered_characters."""
	if not unit_list:
		return

	unit_list.clear()

	for character in filtered_characters:
		var entry_name: String = character.display_name
		if entry_name.is_empty():
			entry_name = String(character.character_id)
		if entry_name.is_empty():
			entry_name = "(Unnamed)"
		var suffix: String = "%d moves" % character.move_count()
		if character.is_boss:
			suffix = "Boss - " + suffix
		unit_list.add_item("%s  (%s)" % [entry_name, suffix])

	if unit_list.get_item_count() == 0:
		unit_list.add_item("No units found")
		unit_list.set_item_disabled(0, true)


# ---------------------------------------------------------------------------
# Current-index state (single source of truth)
# ---------------------------------------------------------------------------

func _select_index(index: int) -> void:
	"""Point the gallery at filtered_characters[index]. Everything that changes the
	displayed unit - the ItemList, the pager, the arrow keys, re-filtering - goes
	through here, so the list selection and the detail pane can never disagree.
	With an empty list this shows nothing and blanks the pager."""
	if filtered_characters.is_empty():
		_current_index = -1
		current_character = null
		if unit_list:
			unit_list.deselect_all()
		if unit_display_container:
			unit_display_container.visible = false
		_clear_model()
		_update_pager()
		return

	_current_index = clampi(index, 0, filtered_characters.size() - 1)

	if unit_list and _current_index < unit_list.get_item_count():
		unit_list.select(_current_index)
		unit_list.ensure_current_is_visible()

	_update_pager()
	_display_character(filtered_characters[_current_index])


func _page(step: int) -> void:
	"""Step the current index by [param step], wrapping at both ends."""
	var count: int = filtered_characters.size()
	if count <= 0:
		return
	var next_index: int = posmod(_current_index + step, count)
	_select_index(next_index)


func _update_pager() -> void:
	if index_label:
		if filtered_characters.is_empty():
			index_label.text = "0 / 0"
		else:
			index_label.text = "%d / %d" % [_current_index + 1, filtered_characters.size()]

	var enabled: bool = filtered_characters.size() > 1
	if prev_button:
		prev_button.disabled = not enabled
	if next_button:
		next_button.disabled = not enabled


# ---------------------------------------------------------------------------
# Detail pane
# ---------------------------------------------------------------------------

func _display_character(character: CharacterResource) -> void:
	"""Display everything known about [param character]."""
	current_character = character

	if not unit_display_container:
		return

	if character == null:
		unit_display_container.visible = false
		return

	unit_display_container.visible = true

	if unit_name_label:
		var shown_name: String = character.display_name
		if shown_name.is_empty():
			shown_name = String(character.character_id)
		unit_name_label.text = shown_name

	if unit_type_label:
		var tags: Array[String] = []
		var id_text: String = String(character.character_id)
		if not id_text.is_empty():
			tags.append(id_text)
		tags.append("Boss" if character.is_boss else "Standard")
		var footprint: Vector2i = character.get_footprint()
		if footprint != Vector2i.ONE:
			tags.append("%dx%d" % [footprint.x, footprint.y])
		tags.append("%d moves" % character.move_count())
		tags.append("%d abilities" % character.ability_count())
		unit_type_label.text = "  -  ".join(tags)

	if unit_description:
		var desc: String = character.description.strip_edges()
		if desc.is_empty():
			desc = "No description available."
		unit_description.text = desc

	_update_portrait(character)
	_update_model(character)
	_update_stats(character)
	_update_moves(character)
	_update_abilities(character)


func _update_portrait(character: CharacterResource) -> void:
	"""Show the authored portrait, or a muted placeholder when there is none."""
	if not unit_portrait:
		return

	var texture: Texture2D = character.portrait
	unit_portrait.texture = texture
	unit_portrait.visible = texture != null
	if portrait_placeholder:
		portrait_placeholder.visible = texture == null


func _clear_model() -> void:
	if current_model_instance != null:
		if is_instance_valid(current_model_instance):
			var parent: Node = current_model_instance.get_parent()
			if parent != null:
				parent.remove_child(current_model_instance)
			current_model_instance.queue_free()
		current_model_instance = null


func _update_model(character: CharacterResource) -> void:
	"""Instance the character's REAL model_scene into the preview viewport.

	Most roster entries have no model yet (only tree_grunt does today), so the
	viewport is hidden and a muted note takes its place rather than showing an
	empty black rectangle."""
	_clear_model()

	if not unit_model_viewport:
		return

	var packed: PackedScene = character.model_scene
	if packed == null:
		_show_model_placeholder()
		return

	var instance: Node = packed.instantiate()
	if instance is Node3D:
		current_model_instance = instance as Node3D
		unit_model_viewport.add_child(current_model_instance)
		current_model_instance.position = Vector3.ZERO
		current_model_instance.rotation = Vector3.ZERO
		if model_viewport_container:
			model_viewport_container.visible = true
		if model_placeholder:
			model_placeholder.visible = false
		return

	# Something non-spatial was authored there - drop it and show the placeholder.
	if instance != null:
		instance.free()
	_show_model_placeholder()


func _show_model_placeholder() -> void:
	if model_viewport_container:
		model_viewport_container.visible = false
	if model_placeholder:
		model_placeholder.visible = true


func _process(delta: float) -> void:
	# Slow turntable on the model preview (replaces the old per-selection tween,
	# which stacked a new looping tween every time a unit was picked).
	if current_model_instance != null and is_instance_valid(current_model_instance):
		current_model_instance.rotate_y(MODEL_SPIN_SPEED * delta)


func _update_stats(character: CharacterResource) -> void:
	"""Rebuild the stats grid from the character's base stats."""
	if not stats_container:
		return

	_clear_container(stats_container)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 4
	stats_container.add_child(stats_grid)

	var rows: Array = [
		["Health", character.base_health],
		["Attack", character.base_attack],
		["Defense", character.base_defense],
		["Magic", character.base_magic],
		["Magic Def", character.base_magic_defense],
		["Speed", character.base_speed],
		["Movement", character.base_movement],
		["Range", character.attack_range],
		["Power", character.power_budget()],
	]

	for row in rows:
		var label := Label.new()
		label.text = str(row[0]) + ":"
		label.modulate = MUTED
		stats_grid.add_child(label)

		var value := Label.new()
		value.text = str(row[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(60, 0)
		stats_grid.add_child(value)

	var profile: MovementProfile = character.get_movement_profile()
	if profile != null:
		var movement_row := Label.new()
		movement_row.text = "Movement profile: %s" % profile.display_name
		movement_row.modulate = MUTED
		movement_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats_container.add_child(movement_row)


# ---------------------------------------------------------------------------
# Moves
# ---------------------------------------------------------------------------

func _update_moves(character: CharacterResource) -> void:
	"""One card per authored move, built from the real MoveResource."""
	if not moves_container:
		return

	_clear_container(moves_container)

	var shown: int = 0
	for i in range(character.move_count()):
		var move: MoveResource = character.get_move(i)
		if move == null:
			continue
		moves_container.add_child(_build_move_card(move))
		shown += 1

	if shown == 0:
		moves_container.add_child(_muted_label("No moves"))


func _build_move_card(move: MoveResource) -> PanelContainer:
	var accent: Color = _category_color(move.category)

	var card := PanelContainer.new()
	card.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	card.add_theme_stylebox_override("panel", _card_box(accent))

	var body := VBoxContainer.new()
	body.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	card.add_child(body)

	# Header: name + element/category tag.
	var header := HBoxContainer.new()
	header.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	body.add_child(header)

	var move_name: String = move.display_name
	if move_name.is_empty():
		move_name = String(move.move_id)
	if move_name.is_empty():
		move_name = "(Unnamed move)"

	var name_label := Label.new()
	name_label.text = move_name
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header.add_child(name_label)

	var tag := Label.new()
	tag.text = _move_tag_text(move)
	tag.add_theme_font_size_override("font_size", 12)
	tag.modulate = accent
	header.add_child(tag)

	# Description.
	var desc_text: String = move.description.strip_edges()
	if desc_text.is_empty():
		desc_text = "No description."
	body.add_child(_wrapped_label(desc_text))

	# Key stats.
	var stats := Label.new()
	stats.text = _move_stats_text(move)
	stats.add_theme_font_size_override("font_size", 12)
	stats.modulate = MUTED
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	body.add_child(stats)

	# What it actually does, straight from the effect list.
	var effect_text: String = _join_effects(move.effects)
	if not effect_text.is_empty():
		var effects_label := _wrapped_label("Effect: " + effect_text)
		effects_label.add_theme_font_size_override("font_size", 13)
		body.add_child(effects_label)

	return card


func _move_tag_text(move: MoveResource) -> String:
	"""e.g. "Nature / Physical", or just "Physical" when no element is authored."""
	var category_name: String = _category_name(move.category)
	var element_text: String = String(move.element).strip_edges()
	if element_text.is_empty():
		return category_name
	return "%s / %s" % [element_text.capitalize(), category_name]


func _move_stats_text(move: MoveResource) -> String:
	"""Cooldown, uses, cost, accuracy, crit and range as one scannable line."""
	var parts: Array[String] = []

	if move.cooldown > 0:
		parts.append("Cooldown %d turn%s" % [move.cooldown, "" if move.cooldown == 1 else "s"])
	else:
		parts.append("No cooldown")

	if move.max_uses == 1:
		parts.append("Once per battle")
	elif move.max_uses > 1:
		parts.append("%d uses per battle" % move.max_uses)

	if move.energy_cost > 0:
		parts.append("Cost %d" % move.energy_cost)

	parts.append("Accuracy %d%%" % _as_percent(move.accuracy))
	parts.append("Crit %d%%" % _as_percent(move.crit_chance))

	var targeting: TargetingPattern = move.targeting
	if targeting != null:
		if targeting.min_range == targeting.max_range:
			parts.append("Range %d" % targeting.max_range)
		else:
			parts.append("Range %d-%d" % [targeting.min_range, targeting.max_range])
		parts.append("Targets %s" % _target_kind_name(targeting.target_kind))
		if targeting.area_shape != CombatTypes.AreaShape.SINGLE:
			parts.append("Area %s %d" % [_area_shape_name(targeting.area_shape), targeting.area_size])
	else:
		parts.append("No targeting pattern")

	return "   -   ".join(parts)


# ---------------------------------------------------------------------------
# Abilities
# ---------------------------------------------------------------------------

func _update_abilities(character: CharacterResource) -> void:
	"""One card per authored ability, built from the real AbilityResource."""
	if not abilities_container:
		return

	_clear_container(abilities_container)

	var shown: int = 0
	for ability in character.abilities:
		if ability == null:
			continue
		abilities_container.add_child(_build_ability_card(ability))
		shown += 1

	if shown == 0:
		abilities_container.add_child(_muted_label("No abilities"))


func _build_ability_card(ability: AbilityResource) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	card.add_theme_stylebox_override("panel", _card_box(ABILITY_ACCENT))

	var body := VBoxContainer.new()
	body.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	card.add_child(body)

	var header := HBoxContainer.new()
	header.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	body.add_child(header)

	var ability_name: String = ability.display_name
	if ability_name.is_empty():
		ability_name = String(ability.id)
	if ability_name.is_empty():
		ability_name = "(Unnamed ability)"

	var name_label := Label.new()
	name_label.text = ability_name
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header.add_child(name_label)

	var tag := Label.new()
	tag.text = _trigger_label(ability.trigger)
	tag.add_theme_font_size_override("font_size", 12)
	tag.modulate = ABILITY_ACCENT
	header.add_child(tag)

	var desc_text: String = ability.description.strip_edges()
	if desc_text.is_empty():
		desc_text = "No description."
	body.add_child(_wrapped_label(desc_text))

	var stats := Label.new()
	stats.text = _ability_stats_text(ability)
	stats.add_theme_font_size_override("font_size", 12)
	stats.modulate = MUTED
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	body.add_child(stats)

	var effect_text: String = _join_effects(ability.effects)
	if not effect_text.is_empty():
		var effects_label := _wrapped_label("Effect: " + effect_text)
		effects_label.add_theme_font_size_override("font_size", 13)
		body.add_child(effects_label)

	var rules_text: String = _rule_modifiers_text(ability)
	if not rules_text.is_empty():
		var rules_label := _wrapped_label("Rules: " + rules_text)
		rules_label.add_theme_font_size_override("font_size", 13)
		body.add_child(rules_label)

	return card


func _ability_stats_text(ability: AbilityResource) -> String:
	var parts: Array[String] = []

	parts.append("Trigger: %s" % _trigger_label(ability.trigger))

	if ability.cooldown > 0:
		parts.append("Cooldown %d turn%s" % [ability.cooldown, "" if ability.cooldown == 1 else "s"])
	else:
		parts.append("No cooldown")

	if ability.max_activations == 1:
		parts.append("Once per battle")
	elif ability.max_activations > 1:
		parts.append("%d activations per battle" % ability.max_activations)
	else:
		parts.append("Unlimited activations")

	var condition: AbilityCondition = ability.condition
	if condition != null:
		parts.append("Condition: %s" % condition.describe())

	if ability.targets_triggering_unit:
		parts.append("Applies to the triggering unit")

	var targeting: TargetingPattern = ability.targeting
	if targeting != null:
		parts.append("Area %s (%s)" % [_area_shape_name(targeting.area_shape), targeting.describe_range()])

	return "   -   ".join(parts)


func _rule_modifiers_text(ability: AbilityResource) -> String:
	"""Action-economy tweaks ("extra_actions": 1 -> "Extra actions: 1")."""
	var modifiers: Dictionary = ability.rule_modifiers
	if modifiers.is_empty():
		return ""
	var parts: Array[String] = []
	for key in modifiers.keys():
		var value_text: String = str(modifiers[key])
		parts.append("%s: %s" % [str(key).capitalize(), value_text])
	return ", ".join(parts)


# ---------------------------------------------------------------------------
# Small shared helpers
# ---------------------------------------------------------------------------

func _join_effects(effects: Array) -> String:
	"""Summarise a move/ability by joining every effect's own describe()."""
	var parts: Array[String] = []
	for effect in effects:
		if effect == null:
			continue
		var described: String = str(effect.describe()).strip_edges()
		if not described.is_empty():
			parts.append(described)
	return "; ".join(parts)


func _clear_container(container: Node) -> void:
	"""Detach and free every child. Detaching first matters because queue_free() is
	deferred - without it, paging would briefly stack the outgoing unit's cards
	underneath the incoming one's."""
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _card_box(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(MenuTheme.PANEL_HI.r, MenuTheme.PANEL_HI.g, MenuTheme.PANEL_HI.b, 0.85)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_width_left = 5
	sb.border_color = accent
	sb.set_content_margin_all(10)
	return sb


func _wrapped_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	return label


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = MUTED
	return label


func _as_percent(value: float) -> int:
	"""0..1 -> 0..100, clamped so an odd authored value can't print nonsense."""
	return roundi(clampf(value, 0.0, 1.0) * 100.0)


func _category_name(category: int) -> String:
	match category:
		CombatTypes.DamageCategory.PHYSICAL:
			return "Physical"
		CombatTypes.DamageCategory.MAGICAL:
			return "Magical"
		CombatTypes.DamageCategory.TRUE:
			return "True"
	return "Unknown"


func _category_color(category: int) -> Color:
	match category:
		CombatTypes.DamageCategory.MAGICAL:
			return CAT_MAGICAL
		CombatTypes.DamageCategory.TRUE:
			return CAT_TRUE
	return CAT_PHYSICAL


func _target_kind_name(kind: int) -> String:
	match kind:
		CombatTypes.TargetKind.SELF:
			return "self"
		CombatTypes.TargetKind.ALLY:
			return "allies"
		CombatTypes.TargetKind.ENEMY:
			return "enemies"
		CombatTypes.TargetKind.ANY_UNIT:
			return "any unit"
		CombatTypes.TargetKind.TILE:
			return "tiles"
		CombatTypes.TargetKind.EMPTY_TILE:
			return "empty tiles"
	return "unknown"


func _area_shape_name(shape: int) -> String:
	match shape:
		CombatTypes.AreaShape.SINGLE:
			return "single"
		CombatTypes.AreaShape.CROSS:
			return "cross"
		CombatTypes.AreaShape.SQUARE:
			return "square"
		CombatTypes.AreaShape.DIAMOND:
			return "diamond"
		CombatTypes.AreaShape.LINE:
			return "line"
		CombatTypes.AreaShape.ARC:
			return "arc"
	return "unknown"


func _trigger_label(trigger: int) -> String:
	"""Readable label for an AbilityTrigger.Trigger value (ON_TURN_START ->
	"On turn start")."""
	match trigger:
		AbilityTrigger.Trigger.PASSIVE:
			return "Passive"
		AbilityTrigger.Trigger.ON_TURN_START:
			return "On turn start"
		AbilityTrigger.Trigger.ON_TURN_END:
			return "On turn end"
		AbilityTrigger.Trigger.ON_MOVE:
			return "On move"
		AbilityTrigger.Trigger.ON_TILE_ENTER:
			return "On tile enter"
		AbilityTrigger.Trigger.ON_ATTACK:
			return "On attack"
		AbilityTrigger.Trigger.ON_DAMAGED:
			return "On damaged"
		AbilityTrigger.Trigger.ON_KILL:
			return "On kill"
		AbilityTrigger.Trigger.ON_DEATH:
			return "On death"
	return "Unknown trigger"


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


func _on_unit_selected(index: int) -> void:
	"""ItemList click - routed through the same _select_index as the pager."""
	_select_index(index)


func _on_search_changed(_new_text: String) -> void:
	_apply_filters()


func _on_filter_changed(_index: int) -> void:
	_apply_filters()


func _on_sort_changed(_index: int) -> void:
	_apply_filters()


func _on_prev_pressed() -> void:
	_page(-1)


func _on_next_pressed() -> void:
	_page(1)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return

	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if key_event.echo:
		return

	# Left/Right page the dex - but never while the user is typing in the search
	# box, where the arrows must keep moving the text caret. _input() runs before
	# GUI input, so this focus check is what keeps the LineEdit usable.
	if key_event.keycode == KEY_LEFT or key_event.keycode == KEY_RIGHT:
		if search_input != null and search_input.has_focus():
			return
		_page(-1 if key_event.keycode == KEY_LEFT else 1)
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return

	match key_event.keycode:
		KEY_ESCAPE:
			_on_back_pressed()
		KEY_F5:
			_load_all_characters()
			_apply_filters()


func _exit_tree() -> void:
	_clear_model()
