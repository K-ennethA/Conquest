@tool
extends Control

# Augment Creator Dock - Visual authoring tool for Arena augment power-ups.
# Mirrors the structure/style of addons/unit_creator/unit_creator_dock.gd: the whole UI
# is built in code, and a finished Augment resource is written to disk with
# ResourceSaver.save(). Because ArenaRoundBuilder's draft pool auto-scans the augments
# directory, a saved augment is immediately draftable.

const AUGMENTS_DIR: String = "res://game/arena/augments/"

# The augment subtypes an author can attach, in the order shown in the "Add Effect" picker.
const EFFECT_TYPES: Array[String] = [
	"StatEffect",
	"MoveModEffect",
	"GrantAbilityEffect",
	"ExtraActionEffect",
	"RunEffect",
]

# MoveModEffect.Which enum order (ALL=0, FIRST_DAMAGING=1, BY_SLOT=2, BY_ELEMENT=3).
const MOVE_WHICH_LABELS: Array[String] = ["ALL", "FIRST_DAMAGING", "BY_SLOT", "BY_ELEMENT"]

# UI Elements
var scroll_container: ScrollContainer
var main_container: VBoxContainer

# Metadata Section
var id_input: LineEdit
var display_name_input: LineEdit
var description_input: TextEdit
var rarity_option: OptionButton
var target_option: OptionButton

# Effects Section
var effect_type_option: OptionButton
var effects_list_container: VBoxContainer

# Preview + Save
var preview_label: RichTextLabel
var save_button: Button
var clear_button: Button
var status_label: Label

# State: one entry per attached effect row.
# Each entry is a Dictionary: { "type": String, "root": Control, "controls": Dictionary }.
var _effect_rows: Array = []


func _init():
	name = "AugmentCreator"
	set_custom_minimum_size(Vector2(300, 600))
	_create_ui()
	_update_preview()


func _create_ui():
	# Main scroll container
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll_container)

	main_container = VBoxContainer.new()
	main_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll_container.add_child(main_container)

	# Title
	var title := Label.new()
	title.text = "AUGMENT CREATOR"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)

	_add_separator()
	_create_metadata_section()
	_add_separator()
	_create_effects_section()
	_add_separator()
	_create_preview_section()
	_add_separator()
	_create_action_buttons()


func _add_separator():
	var separator := HSeparator.new()
	main_container.add_child(separator)


func _create_metadata_section():
	var section_label := Label.new()
	section_label.text = "METADATA"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)

	# Internal id
	main_container.add_child(_create_label("Augment ID (filename, internal):"))
	id_input = LineEdit.new()
	id_input.placeholder_text = "e.g., double_strike"
	id_input.text_changed.connect(_on_id_changed)
	main_container.add_child(id_input)

	# Display name
	main_container.add_child(_create_label("Display Name:"))
	display_name_input = LineEdit.new()
	display_name_input.placeholder_text = "e.g., Double Strike"
	main_container.add_child(display_name_input)

	# Description
	main_container.add_child(_create_label("Description:"))
	description_input = TextEdit.new()
	description_input.placeholder_text = "Player-facing description..."
	description_input.custom_minimum_size = Vector2(0, 70)
	main_container.add_child(description_input)

	# Rarity + Target grid
	var grid := GridContainer.new()
	grid.columns = 2
	main_container.add_child(grid)

	grid.add_child(_create_label("Rarity:"))
	rarity_option = OptionButton.new()
	rarity_option.add_item("COMMON")
	rarity_option.add_item("RARE")
	rarity_option.add_item("EPIC")
	rarity_option.add_item("LEGENDARY")
	rarity_option.selected = 0
	grid.add_child(rarity_option)

	grid.add_child(_create_label("Target:"))
	target_option = OptionButton.new()
	target_option.add_item("SQUAD")
	target_option.add_item("SINGLE_UNIT")
	target_option.add_item("RUN")
	target_option.selected = 0
	grid.add_child(target_option)


func _create_effects_section():
	var section_label := Label.new()
	section_label.text = "EFFECTS"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)

	# Add-effect row: pick a subtype + Add button.
	var add_row := HBoxContainer.new()
	main_container.add_child(add_row)

	effect_type_option = OptionButton.new()
	for effect_type in EFFECT_TYPES:
		effect_type_option.add_item(effect_type)
	effect_type_option.selected = 0
	effect_type_option.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	add_row.add_child(effect_type_option)

	var add_button := Button.new()
	add_button.text = "Add Effect"
	add_button.pressed.connect(_on_add_effect_pressed)
	add_row.add_child(add_button)

	# Container that holds one panel per attached effect.
	effects_list_container = VBoxContainer.new()
	effects_list_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	main_container.add_child(effects_list_container)


func _create_preview_section():
	var section_label := Label.new()
	section_label.text = "DESCRIPTION PREVIEW"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)

	preview_label = RichTextLabel.new()
	preview_label.fit_content = true
	preview_label.bbcode_enabled = false
	preview_label.custom_minimum_size = Vector2(0, 90)
	preview_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	main_container.add_child(preview_label)


func _create_action_buttons():
	var button_container := HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_child(button_container)

	save_button = Button.new()
	save_button.text = "SAVE AUGMENT"
	save_button.custom_minimum_size = Vector2(120, 40)
	save_button.pressed.connect(_on_save_augment)
	button_container.add_child(save_button)

	clear_button = Button.new()
	clear_button.text = "CLEAR"
	clear_button.custom_minimum_size = Vector2(80, 40)
	clear_button.pressed.connect(_on_clear_form)
	button_container.add_child(clear_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(status_label)


# --- Small UI helpers -------------------------------------------------------

func _create_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_spin(min_v: int, max_v: int, default_v: int) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = 1
	sb.value = default_v
	sb.value_changed.connect(func(_v: float): _update_preview())
	return sb


func _make_line_edit(placeholder: String, default_text: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.text = default_text
	le.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	le.text_changed.connect(func(_t: String): _update_preview())
	return le


func _make_option(labels: Array[String]) -> OptionButton:
	var ob := OptionButton.new()
	for label in labels:
		ob.add_item(label)
	ob.selected = 0
	ob.item_selected.connect(func(_i: int): _update_preview())
	return ob


# --- Effect rows ------------------------------------------------------------

func _on_add_effect_pressed():
	var type_name: String = EFFECT_TYPES[effect_type_option.selected]
	_add_effect_row(type_name)


func _add_effect_row(type_name: String):
	var controls := {}

	var panel := PanelContainer.new()
	var body := VBoxContainer.new()
	panel.add_child(body)

	# Header: subtype title + remove button.
	var header := HBoxContainer.new()
	body.add_child(header)

	var type_label := Label.new()
	type_label.text = type_name
	type_label.add_theme_font_size_override("font_size", 13)
	type_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header.add_child(type_label)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	header.add_child(remove_button)

	# Field grid, populated per subtype.
	var grid := GridContainer.new()
	grid.columns = 2
	body.add_child(grid)

	match type_name:
		"StatEffect":
			grid.add_child(_create_label("Stat:"))
			var stat_le: LineEdit = _make_line_edit("attack / defense / max_health ...", "attack")
			controls["stat"] = stat_le
			grid.add_child(stat_le)

			grid.add_child(_create_label("Amount:"))
			var amount_sb: SpinBox = _make_spin(-999, 999, 1)
			controls["amount"] = amount_sb
			grid.add_child(amount_sb)

		"MoveModEffect":
			grid.add_child(_create_label("Which:"))
			var which_ob: OptionButton = _make_option(MOVE_WHICH_LABELS)
			which_ob.selected = 1  # FIRST_DAMAGING (matches the resource default)
			controls["which"] = which_ob
			grid.add_child(which_ob)

			grid.add_child(_create_label("Slot (BY_SLOT):"))
			var slot_sb: SpinBox = _make_spin(0, 3, 0)
			controls["slot"] = slot_sb
			grid.add_child(slot_sb)

			grid.add_child(_create_label("Element (BY_ELEMENT):"))
			var element_le: LineEdit = _make_line_edit("e.g. ember / frost", "")
			controls["element"] = element_le
			grid.add_child(element_le)

			grid.add_child(_create_label("Extra Hits:"))
			var extra_hits_sb: SpinBox = _make_spin(0, 20, 0)
			controls["extra_hits"] = extra_hits_sb
			grid.add_child(extra_hits_sb)

			grid.add_child(_create_label("Bonus Range:"))
			var bonus_range_sb: SpinBox = _make_spin(-20, 20, 0)
			controls["bonus_range"] = bonus_range_sb
			grid.add_child(bonus_range_sb)

			grid.add_child(_create_label("AoE Expand:"))
			var aoe_sb: SpinBox = _make_spin(0, 20, 0)
			controls["aoe_expand"] = aoe_sb
			grid.add_child(aoe_sb)

			grid.add_child(_create_label("Cooldown Delta:"))
			var cooldown_sb: SpinBox = _make_spin(-20, 20, 0)
			controls["cooldown_delta"] = cooldown_sb
			grid.add_child(cooldown_sb)

			grid.add_child(_create_label("Max Uses Delta:"))
			var max_uses_sb: SpinBox = _make_spin(-20, 20, 0)
			controls["max_uses_delta"] = max_uses_sb
			grid.add_child(max_uses_sb)

		"GrantAbilityEffect":
			grid.add_child(_create_label("Ability Path (.tres):"))
			var ability_le: LineEdit = _make_line_edit("res://game/arena/abilities/...", "")
			controls["ability_path"] = ability_le
			grid.add_child(ability_le)

			grid.add_child(_create_label("Ability ID (fallback):"))
			var ability_id_le: LineEdit = _make_line_edit("vampiric / blitz / amphibious / last_stand", "")
			controls["ability_id"] = ability_id_le
			grid.add_child(ability_id_le)

		"ExtraActionEffect":
			grid.add_child(_create_label("Extra Actions:"))
			var extra_actions_sb: SpinBox = _make_spin(0, 10, 1)
			controls["extra_actions"] = extra_actions_sb
			grid.add_child(extra_actions_sb)

		"RunEffect":
			grid.add_child(_create_label("Extra Squad Slots:"))
			var slots_sb: SpinBox = _make_spin(0, 10, 0)
			controls["extra_squad_slots"] = slots_sb
			grid.add_child(slots_sb)

			grid.add_child(_create_label("Bonus Currency:"))
			var currency_sb: SpinBox = _make_spin(0, 9999, 0)
			controls["bonus_currency"] = currency_sb
			grid.add_child(currency_sb)

			grid.add_child(_create_label("Bonus Draft Options:"))
			var draft_sb: SpinBox = _make_spin(0, 10, 0)
			controls["bonus_draft_options"] = draft_sb
			grid.add_child(draft_sb)

	var row := {}
	row["type"] = type_name
	row["root"] = panel
	row["controls"] = controls
	_effect_rows.append(row)

	remove_button.pressed.connect(func(): _remove_effect_row(row))

	effects_list_container.add_child(panel)
	_update_preview()


func _remove_effect_row(row: Dictionary):
	_effect_rows.erase(row)
	var root = row.get("root")
	if root != null and is_instance_valid(root):
		root.queue_free()
	_update_preview()


# --- Build effects + preview ------------------------------------------------

# Construct the concrete AugmentEffect instances from the current effect rows.
func _build_effects() -> Array[AugmentEffect]:
	var effects: Array[AugmentEffect] = []
	for row in _effect_rows:
		var type_name: String = row["type"]
		var controls: Dictionary = row["controls"]
		var effect: AugmentEffect = _build_effect(type_name, controls)
		if effect != null:
			effects.append(effect)
	return effects


func _build_effect(type_name: String, controls: Dictionary) -> AugmentEffect:
	match type_name:
		"StatEffect":
			var stat_effect := StatEffect.new()
			var stat_le: LineEdit = controls["stat"]
			var amount_sb: SpinBox = controls["amount"]
			stat_effect.stat = stat_le.text.strip_edges()
			stat_effect.amount = int(amount_sb.value)
			return stat_effect

		"MoveModEffect":
			var move_effect := MoveModEffect.new()
			var which_ob: OptionButton = controls["which"]
			var slot_sb: SpinBox = controls["slot"]
			var element_le: LineEdit = controls["element"]
			var extra_hits_sb: SpinBox = controls["extra_hits"]
			var bonus_range_sb: SpinBox = controls["bonus_range"]
			var aoe_sb: SpinBox = controls["aoe_expand"]
			var cooldown_sb: SpinBox = controls["cooldown_delta"]
			var max_uses_sb: SpinBox = controls["max_uses_delta"]
			move_effect.which = which_ob.selected
			move_effect.slot = int(slot_sb.value)
			move_effect.element = StringName(element_le.text.strip_edges())
			move_effect.extra_hits = int(extra_hits_sb.value)
			move_effect.bonus_range = int(bonus_range_sb.value)
			move_effect.aoe_expand = int(aoe_sb.value)
			move_effect.cooldown_delta = int(cooldown_sb.value)
			move_effect.max_uses_delta = int(max_uses_sb.value)
			return move_effect

		"GrantAbilityEffect":
			var grant_effect := GrantAbilityEffect.new()
			var ability_le: LineEdit = controls["ability_path"]
			var ability_id_le: LineEdit = controls["ability_id"]
			var path: String = ability_le.text.strip_edges()
			if path != "" and ResourceLoader.exists(path):
				var loaded = load(path)
				if loaded is AbilityResource:
					grant_effect.ability = loaded
			grant_effect.ability_id = StringName(ability_id_le.text.strip_edges())
			return grant_effect

		"ExtraActionEffect":
			var action_effect := ExtraActionEffect.new()
			var extra_actions_sb: SpinBox = controls["extra_actions"]
			action_effect.extra_actions = int(extra_actions_sb.value)
			return action_effect

		"RunEffect":
			var run_effect := RunEffect.new()
			var slots_sb: SpinBox = controls["extra_squad_slots"]
			var currency_sb: SpinBox = controls["bonus_currency"]
			var draft_sb: SpinBox = controls["bonus_draft_options"]
			run_effect.extra_squad_slots = int(slots_sb.value)
			run_effect.bonus_currency = int(currency_sb.value)
			run_effect.bonus_draft_options = int(draft_sb.value)
			return run_effect

	return null


func _update_preview():
	if preview_label == null:
		return
	var effects: Array[AugmentEffect] = _build_effects()
	if effects.is_empty():
		preview_label.text = "(no effects yet)"
		return
	var lines: Array[String] = []
	for effect in effects:
		var line: String = effect.describe()
		if line.strip_edges() == "":
			line = "(empty)"
		lines.append("- " + line)
	preview_label.text = "\n".join(lines)


# --- Save + form actions ----------------------------------------------------

func _on_id_changed(new_text: String):
	# Auto-fill display name from id, matching unit_creator's convenience behavior.
	if display_name_input and display_name_input.text.is_empty():
		display_name_input.text = new_text.replace("_", " ").capitalize()


func _on_save_augment():
	var augment_id: String = id_input.text.strip_edges()
	if augment_id == "":
		_set_status("Error: Augment ID is required.", true)
		return

	# Ensure the target directory exists (mirrors unit_creator's guard).
	if not DirAccess.dir_exists_absolute(AUGMENTS_DIR):
		DirAccess.open("res://").make_dir_recursive("game/arena/augments")

	var augment := Augment.new()
	augment.id = augment_id
	augment.display_name = display_name_input.text.strip_edges()
	if augment.display_name == "":
		augment.display_name = augment_id
	augment.description = description_input.text
	augment.rarity = rarity_option.selected
	augment.target = target_option.selected
	augment.stat_bonuses = {}
	augment.effects = _build_effects()

	var resource_path: String = AUGMENTS_DIR + augment_id + ".tres"
	var result: int = ResourceSaver.save(augment, resource_path)
	if result == OK:
		_set_status("Saved: " + resource_path, false)
		print("Augment saved: " + resource_path)
	else:
		_set_status("Failed to save (error %d)." % result, true)
		print("Failed to save augment: " + str(result))


func _on_clear_form():
	id_input.text = ""
	display_name_input.text = ""
	description_input.text = ""
	rarity_option.selected = 0
	target_option.selected = 0

	for row in _effect_rows:
		var root = row.get("root")
		if root != null and is_instance_valid(root):
			root.queue_free()
	_effect_rows.clear()

	_set_status("", false)
	_update_preview()


func _set_status(text: String, is_error: bool):
	if status_label == null:
		return
	status_label.text = text
	if is_error:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	else:
		status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
