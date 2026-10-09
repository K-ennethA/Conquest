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

# --- Where the cards come from ----------------------------------------------
#
# The stat table, the move cards and the ability cards are built by [UnitPageContent],
# which was EXTRACTED from this file when the in-battle DETAILS overlay ([UnitDetailPage])
# needed the same page. The gallery keeps what makes it a gallery -- search, filter, sort,
# the pager and the 3D turntable -- and delegates "what does a move card say" so the two
# surfaces cannot drift. The accents and the small text helpers live there too.
const Content := preload("res://game/ui/screens/UnitPageContent.gd")

# --- Look ---------------------------------------------------------------------
#
# Hosted in a Compendium tab, so it wears the illuminated-grove kit (docs/UI_STYLE.md):
# a heraldic crest (element shield + initial) beside the name, the real portrait (the
# authored one, else a PortraitCache capture of the unit's own 3D model) when there is
# one, and the auto-framed UnitPreview3D turntable for the model.

const MUTED := MenuTheme.TEXT_MUTED

## Breathing room inside the host (the Compendium's tab panel already pads the page).
const PAGE_MARGIN: int = MenuTheme.SP_S

# Turntable speed for the model preview (radians / second) - slow, like the old tween.
const MODEL_SPIN_SPEED := 0.45

# UI Elements
@onready var back_button: Button
@onready var unit_list: ItemList
@onready var unit_display_container: VBoxContainer
@onready var unit_name_label: Label
## Heraldic crest: the unit's element on a shield, its initial in Cinzel.
var _crest: PanelContainer = null
## Frame around the portrait; hidden while there is no portrait to show.
var _portrait_slot: PanelContainer = null
## EVOLUTION: the line strip + "evolves from / into" (CompendiumData.evolution_blocks), shown
## only for a unit in an evolution line; its unit links re-point this gallery.
var _evolution_header: Label = null
var _evolution_text: RichTextLabel = null
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
	theme = MenuTheme.build()  # the illuminated-grove menu theme
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

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", PAGE_MARGIN)
	outer.add_theme_constant_override("margin_right", PAGE_MARGIN)
	outer.add_theme_constant_override("margin_top", PAGE_MARGIN)
	outer.add_theme_constant_override("margin_bottom", PAGE_MARGIN)
	add_child(outer)

	var main_container := HBoxContainer.new()
	main_container.add_theme_constant_override("separation", MenuTheme.SP_XL)
	outer.add_child(main_container)

	# --- Left panel: list + controls ---
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)
	left_panel.add_theme_constant_override("separation", MenuTheme.SP_XS)
	main_container.add_child(left_panel)

	# Title + back (the Compendium hides this whole row when it hosts the gallery).
	var header_container := HBoxContainer.new()
	# A real gap between the title and Back (the default ~4px let a long title touch it).
	header_container.add_theme_constant_override("separation", MenuTheme.SP_M)
	left_panel.add_child(header_container)

	var title := Label.new()
	title.text = "Unit Gallery"
	title.theme_type_variation = &"HeadingLabel"
	title.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(title)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 120, 44)
	header_container.add_child(back_button)

	left_panel.add_child(_form_label("Search"))

	search_input = LineEdit.new()
	search_input.placeholder_text = "Search units..."
	left_panel.add_child(search_input)

	left_panel.add_child(_form_label("Filter"))

	filter_option = OptionButton.new()
	for mode in filter_modes:
		filter_option.add_item(mode)
	left_panel.add_child(filter_option)

	left_panel.add_child(_form_label("Sort by"))

	sort_option = OptionButton.new()
	for sort_type in sort_options:
		sort_option.add_item(sort_type)
	left_panel.add_child(sort_option)

	left_panel.add_child(_form_label("Units"))

	unit_list = ItemList.new()
	unit_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	unit_list.custom_minimum_size = Vector2(280, 120)
	left_panel.add_child(unit_list)

	# --- Right panel: pager + scrolling detail ---
	var right_panel := VBoxContainer.new()
	right_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_panel.custom_minimum_size = Vector2(500, 0)
	right_panel.add_theme_constant_override("separation", MenuTheme.SP_S)
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
	index_label.add_theme_font_override("font", MenuTheme.heading_font())
	index_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	pager.add_child(index_label)

	next_button = Button.new()
	next_button.text = "NEXT >"
	next_button.custom_minimum_size = Vector2(110, 36)
	pager.add_child(next_button)


func _create_unit_display(parent: VBoxContainer) -> void:
	"""Create the unit detail area"""
	unit_display_container = VBoxContainer.new()
	unit_display_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	unit_display_container.add_theme_constant_override("separation", MenuTheme.SP_S)
	parent.add_child(unit_display_container)

	# --- Header: portrait + crest + name/identity ---
	var header_container := HBoxContainer.new()
	header_container.add_theme_constant_override("separation", MenuTheme.SP_L)
	unit_display_container.add_child(header_container)

	_portrait_slot = PanelContainer.new()
	_portrait_slot.name = "PortraitSlot"
	_portrait_slot.add_theme_stylebox_override("panel", MenuTheme.inset_box())
	_portrait_slot.custom_minimum_size = Vector2(120, 120)
	_portrait_slot.visible = false
	header_container.add_child(_portrait_slot)
	var portrait_slot := _portrait_slot

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

	_crest = MenuKit.crest("?", MenuTheme.GOLD, MenuTheme.GOLD_DK, 56.0)
	_crest.name = "UnitCrest"
	_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_container.add_child(_crest)

	var info_container := VBoxContainer.new()
	info_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	info_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_container.add_child(info_container)

	unit_name_label = Label.new()
	unit_name_label.theme_type_variation = &"HeadingLabel"
	info_container.add_child(unit_name_label)

	unit_type_label = Label.new()
	unit_type_label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
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

	# Auto-framed turntable render (shared UnitPreview3D component): any model size
	# fits, the authored yaw / scale are applied, and it spins on its own.
	var preview := UnitPreview3D.new()
	preview.name = "ModelPreview"
	preview.spin_speed = MODEL_SPIN_SPEED
	preview.background_color = Color(0.07, 0.08, 0.15, 1.0)
	preview.custom_minimum_size = Vector2(300, 260)
	model_viewport_container = preview
	unit_display_container.add_child(preview)
	preview._ensure()
	unit_model_viewport = preview.viewport

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

	# --- Evolution (only for units in a line) ---
	_evolution_header = _section_header("Evolution")
	_evolution_header.name = "EvolutionHeader"
	unit_display_container.add_child(_evolution_header)
	_evolution_text = RichTextLabel.new()
	_evolution_text.name = "EvolutionText"
	_evolution_text.bbcode_enabled = true
	_evolution_text.fit_content = true
	_evolution_text.meta_clicked.connect(_on_evolution_link)
	unit_display_container.add_child(_evolution_text)

	# Hidden until a character is selected (an empty filter keeps it hidden).
	unit_display_container.visible = false


func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"SectionLabel"
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	return label


## Small muted caption above a form control (search / filter / sort / list).
func _form_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	return label


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
	for move in character.get_moveset():
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
		if _crest != null:
			MenuKit.set_crest(_crest, shown_name, MenuKit.element_color(String(character.element)))

	if unit_type_label:
		var tags: Array[String] = []
		var id_text: String = String(character.character_id)
		if not id_text.is_empty():
			tags.append(id_text)
		tags.append("Boss" if character.is_boss else "Standard")
		if character.element != &"":
			tags.append(String(character.element).capitalize())
		for t in character.tags:
			tags.append(String(t))
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
	_update_evolution(character)


## The unit's evolution line, from the same blocks the Compendium's search entries carry.
func _update_evolution(character: CharacterResource) -> void:
	if _evolution_text == null:
		return
	var lines: PackedStringArray = []
	for block in CompendiumData.evolution_blocks(character):
		if block.get("type", "") == "text":
			lines.append(String(block["text"]))
		for item in block.get("items", []):
			lines.append("• " + String(item))
	_evolution_text.text = "\n".join(lines)
	_evolution_header.visible = not lines.is_empty()
	_evolution_text.visible = not lines.is_empty()


## "units:<id>" from the evolution strip: show that unit (clearing a filter that hides it).
func _on_evolution_link(meta) -> void:
	var parts := String(meta).split(":", true, 1)
	if parts.size() != 2 or parts[0] != CompendiumData.SECTION_UNITS:
		return
	for pass_index in 2:
		for i in filtered_characters.size():
			if String(filtered_characters[i].character_id) == parts[1]:
				_select_index(i)
				return
		if search_input != null:
			search_input.text = ""
		if filter_option != null:
			filter_option.select(0)
		_apply_filters()


func _update_portrait(character: CharacterResource) -> void:
	"""Show the unit's portrait: the authored one, else a real capture of its 3D model
	(PortraitCache -- resolved asynchronously, never in headless runs). With neither,
	the portrait frame is dropped and the crest beside the name stands in."""
	if not unit_portrait:
		return

	var texture: Texture2D = character.portrait
	if texture == null:
		var id_str: String = String(character.character_id)
		texture = PortraitCache.get_cached(id_str)
		if texture == null and character.model_scene != null:
			PortraitCache.get_portrait(id_str, _on_portrait_resolved.bind(id_str))
	_set_portrait(texture)


func _set_portrait(texture: Texture2D) -> void:
	unit_portrait.texture = texture
	unit_portrait.visible = texture != null
	if portrait_placeholder:
		portrait_placeholder.visible = false
	if _portrait_slot:
		_portrait_slot.visible = texture != null


## PortraitCache callback: applied only if that unit is still the one on screen.
func _on_portrait_resolved(texture: Texture2D, id_str: String) -> void:
	if texture == null or not is_inside_tree() or current_character == null:
		return
	if String(current_character.character_id) != id_str or current_character.portrait != null:
		return
	_set_portrait(texture)


func _clear_model() -> void:
	if model_viewport_container is UnitPreview3D:
		(model_viewport_container as UnitPreview3D).clear()
	if current_model_instance != null:
		if is_instance_valid(current_model_instance):
			var parent: Node = current_model_instance.get_parent()
			if parent != null:
				parent.remove_child(current_model_instance)
			current_model_instance.queue_free()
		current_model_instance = null


func _update_model(character: CharacterResource) -> void:
	"""Show the character's REAL model_scene on the auto-framed turntable
	(UnitPreview3D applies the authored yaw / scale and fits the camera to the mesh).

	A character without a usable model gets a muted note instead of an empty black
	rectangle."""
	_clear_model()

	if not unit_model_viewport:
		return

	var preview := model_viewport_container as UnitPreview3D
	if preview == null or not preview.show_character(character):
		_show_model_placeholder()
		return
	if model_viewport_container:
		model_viewport_container.visible = true
	if model_placeholder:
		model_placeholder.visible = false


func _show_model_placeholder() -> void:
	if model_viewport_container:
		model_viewport_container.visible = false
	if model_placeholder:
		model_placeholder.visible = true


func _update_stats(character: CharacterResource) -> void:
	"""Rebuild the stats table from the character's base stats.

	No live unit is passed: out of battle there is nothing to be buffed BY, so every row
	renders as its authored base. The same builder is what the in-battle detail page calls
	WITH a unit, which is where the `base → effective` arrows come from."""
	if not stats_container:
		return

	Content.clear_container(stats_container)
	stats_container.add_child(Content.build_stat_table(character))


# ---------------------------------------------------------------------------
# Moves
# ---------------------------------------------------------------------------

func _update_moves(character: CharacterResource) -> void:
	"""One card per authored move, built from the real MoveResource."""
	if not moves_container:
		return

	Content.clear_container(moves_container)

	var shown: int = 0
	for i in range(character.move_count()):
		var move: MoveResource = character.get_move(i)
		if move == null:
			continue
		moves_container.add_child(Content.build_move_card(move))
		shown += 1

	if shown == 0:
		moves_container.add_child(Content.muted_label("No moves"))


# ---------------------------------------------------------------------------
# Abilities
# ---------------------------------------------------------------------------

func _update_abilities(character: CharacterResource) -> void:
	"""One card per authored ability, built from the real AbilityResource."""
	if not abilities_container:
		return

	Content.clear_container(abilities_container)

	var shown: int = 0
	for ability in character.abilities:
		if ability == null:
			continue
		abilities_container.add_child(Content.build_ability_card(ability))
		shown += 1

	if shown == 0:
		abilities_container.add_child(Content.muted_label("No abilities"))



# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	MenuNav.change_scene(self, "res://menus/MainMenu.tscn")


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
			# Hosted in the Compendium the shell owns Back (it hid our button).
			if back_button != null and back_button.visible:
				_on_back_pressed()
		KEY_F5:
			_load_all_characters()
			_apply_filters()


func _exit_tree() -> void:
	_clear_model()
