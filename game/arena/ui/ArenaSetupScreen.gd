extends Control

## Pre-run SETUP screen for the Arena mode. MainMenu's "Arena" button now opens THIS
## instead of starting a run directly, so the player picks how long the run is and which
## turn system every round uses before committing.
##
## Design: run-LENGTH PRESETS are the primary path (Short / Standard / Long); a secondary
## "Custom" section offers the turn-system choice and an optional rounds override that
## supersedes the preset the moment the player touches the spinbox. Mode is Solo for now
## (a disabled "Versus -- coming soon" affordance is shown but does nothing).
##
## On Start Run it duplicates the shared arena_solo.tres (never mutating it), writes the
## chosen total_rounds + turn_system, and hands the copy to ArenaController.start_run(),
## which itself changes to the GameWorld scene. Every step is null-guarded: a missing
## autoload or base resource shows an inline message rather than crashing.

const BASE_RULESET_PATH := "res://game/arena/rulesets/arena_solo.tres"
const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

# Run-length presets (label -> rounds). Standard is the default.
const PRESET_SHORT := 4
const PRESET_STANDARD := 6
const PRESET_LONG := 8

# Rounds-override spinbox bounds.
const CUSTOM_MIN := 3
const CUSTOM_MAX := 12

# Warm palette. Pulled from ConquestTheme when present, else tasteful hardcoded fallbacks
# so a missing constant can never crash this screen (mirrors ArenaResultsScreen).
var _bg_top: Color = Color(0.10, 0.075, 0.05, 1.0)
var _bg_bottom: Color = Color(0.05, 0.035, 0.02, 1.0)
var _plate_fill: Color = Color("2c2114")
var _ink: Color = Color("2a1608")
var _cream: Color = Color("fcefd6")
var _cream_dim: Color = Color("e7d3ad")
var _amber: Color = Color("e6a64b")
var _amber_lite: Color = Color("f0c072")
var _amber_dk: Color = Color("c6822f")
var _brown: Color = Color("5a3a1e")
var _brown_dk: Color = Color("37220f")
var _gold: Color = Color("f0c040")

# --- Selection state --------------------------------------------------------
# The preset the player picked (rounds). Standard by default.
var _preset_rounds: int = PRESET_STANDARD
# Custom rounds override: only wins once the player actually touches the spinbox.
var _custom_rounds_active: bool = false
var _custom_rounds: int = PRESET_STANDARD
# Chosen turn system: Traditional by default (see ArenaRuleset notes).
var _turn_system: int = TurnSystemBase.TurnSystemType.TRADITIONAL

# --- Live node refs ---------------------------------------------------------
var _preset_group: ButtonGroup = null
var _turn_group: ButtonGroup = null
var _rounds_spin: SpinBox = null
var _summary_label: Label = null
var _message_label: Label = null


func _ready() -> void:
	_load_palette()
	_build_background()

	var page: VBoxContainer = VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", 18)
	add_child(page)

	# --- Title ---------------------------------------------------------------
	var title: Label = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", _gold)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.text = "ARENA"
	page.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", _cream)
	subtitle.text = "Solo Run Setup"
	page.add_child(subtitle)

	# --- Settings card -------------------------------------------------------
	page.add_child(_build_card())

	# --- Live summary of what will actually launch --------------------------
	_summary_label = Label.new()
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.add_theme_font_size_override("font_size", 17)
	_summary_label.add_theme_color_override("font_color", _cream_dim)
	page.add_child(_summary_label)

	# --- Inline message (errors / guards) ------------------------------------
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.add_theme_color_override("font_color", Color("d87a4a"))
	_message_label.visible = false
	page.add_child(_message_label)

	# --- Action buttons ------------------------------------------------------
	page.add_child(_build_actions())

	_update_summary()


# --- Card ------------------------------------------------------------------

func _build_card() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_box())
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(520.0, 0.0)
	margin.add_child(col)

	# RUN LENGTH (primary path) ----------------------------------------------
	col.add_child(_section_heading("RUN LENGTH"))

	var presets: HBoxContainer = HBoxContainer.new()
	presets.add_theme_constant_override("separation", 10)
	presets.alignment = BoxContainer.ALIGNMENT_CENTER
	_preset_group = ButtonGroup.new()
	presets.add_child(_make_preset_button("Short", PRESET_SHORT))
	presets.add_child(_make_preset_button("Standard", PRESET_STANDARD))
	presets.add_child(_make_preset_button("Long", PRESET_LONG))
	col.add_child(presets)

	col.add_child(_divider())

	# CUSTOM (secondary) ------------------------------------------------------
	col.add_child(_section_heading("CUSTOM"))

	# Turn system row.
	var turn_row: HBoxContainer = HBoxContainer.new()
	turn_row.add_theme_constant_override("separation", 12)
	turn_row.add_child(_row_label("Turn System"))
	var turn_choices: HBoxContainer = HBoxContainer.new()
	turn_choices.add_theme_constant_override("separation", 8)
	turn_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_choices.alignment = BoxContainer.ALIGNMENT_END
	_turn_group = ButtonGroup.new()
	turn_choices.add_child(_make_turn_button("Traditional", TurnSystemBase.TurnSystemType.TRADITIONAL))
	turn_choices.add_child(_make_turn_button("Speed", TurnSystemBase.TurnSystemType.INITIATIVE))
	turn_row.add_child(turn_choices)
	col.add_child(turn_row)

	# Rounds override row.
	var rounds_row: HBoxContainer = HBoxContainer.new()
	rounds_row.add_theme_constant_override("separation", 12)
	rounds_row.add_child(_row_label("Rounds Override"))

	_rounds_spin = SpinBox.new()
	_rounds_spin.min_value = float(CUSTOM_MIN)
	_rounds_spin.max_value = float(CUSTOM_MAX)
	_rounds_spin.step = 1.0
	_rounds_spin.value = float(_preset_rounds)
	_rounds_spin.custom_minimum_size = Vector2(120.0, 0.0)
	_rounds_spin.size_flags_horizontal = Control.SIZE_SHRINK_END
	_rounds_spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rounds_spin.tooltip_text = "Overrides the preset once changed (3-12)."
	var spin_wrap: HBoxContainer = HBoxContainer.new()
	spin_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin_wrap.alignment = BoxContainer.ALIGNMENT_END
	spin_wrap.add_child(_rounds_spin)
	rounds_row.add_child(spin_wrap)
	col.add_child(rounds_row)
	# Connect AFTER setting the initial value so the sync above does not count as a touch.
	_rounds_spin.value_changed.connect(_on_rounds_override_changed)

	# Mode row (Solo now; Versus is a disabled "coming soon" affordance). ------
	var mode_row: HBoxContainer = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	mode_row.add_child(_row_label("Mode"))
	var mode_choices: HBoxContainer = HBoxContainer.new()
	mode_choices.add_theme_constant_override("separation", 8)
	mode_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_choices.alignment = BoxContainer.ALIGNMENT_END

	var solo_tag: Label = Label.new()
	solo_tag.add_theme_font_size_override("font_size", 16)
	solo_tag.add_theme_color_override("font_color", _ink)
	solo_tag.text = "Solo"
	var solo_wrap: PanelContainer = PanelContainer.new()
	solo_wrap.add_theme_stylebox_override("panel", _pill_box(_amber_lite))
	solo_wrap.add_child(solo_tag)
	mode_choices.add_child(solo_wrap)

	var versus_btn: Button = Button.new()
	versus_btn.text = "Versus (soon)"
	versus_btn.disabled = true
	versus_btn.focus_mode = Control.FOCUS_NONE
	versus_btn.add_theme_font_size_override("font_size", 16)
	versus_btn.add_theme_stylebox_override("disabled", _button_box(_brown.lerp(_amber, 0.12)))
	versus_btn.add_theme_color_override("font_disabled_color", _cream_dim)
	mode_choices.add_child(versus_btn)

	mode_row.add_child(mode_choices)
	col.add_child(mode_row)

	return panel


# --- Widget factories -------------------------------------------------------

func _make_preset_button(label: String, rounds: int) -> Button:
	var btn: Button = Button.new()
	btn.text = "%s\n%d rounds" % [label, rounds]
	btn.toggle_mode = true
	btn.button_group = _preset_group
	btn.custom_minimum_size = Vector2(150.0, 56.0)
	btn.add_theme_font_size_override("font_size", 18)
	btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	_style_choice_button(btn)
	if rounds == _preset_rounds:
		btn.button_pressed = true
	btn.pressed.connect(_on_preset_pressed.bind(rounds))
	return btn


func _make_turn_button(label: String, turn_type: int) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.button_group = _turn_group
	btn.custom_minimum_size = Vector2(130.0, 40.0)
	btn.add_theme_font_size_override("font_size", 16)
	_style_choice_button(btn)
	if turn_type == _turn_system:
		btn.button_pressed = true
	btn.pressed.connect(_on_turn_system_pressed.bind(turn_type))
	return btn


func _section_heading(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", _brown_dk)
	lbl.text = text
	return lbl


func _row_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", _ink)
	lbl.text = text
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lbl


func _divider() -> HSeparator:
	var sep: HSeparator = HSeparator.new()
	var sep_box: StyleBoxFlat = StyleBoxFlat.new()
	sep_box.bg_color = _brown.darkened(0.05)
	sep_box.content_margin_top = 1.0
	sep_box.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", sep_box)
	return sep


# --- Action buttons ---------------------------------------------------------

func _build_actions() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)

	var back_btn: Button = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(160.0, 52.0)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.add_theme_stylebox_override("normal", _button_box(_brown.lerp(_amber, 0.10)))
	back_btn.add_theme_stylebox_override("hover", _button_box(_brown.lerp(_amber, 0.22)))
	back_btn.add_theme_stylebox_override("pressed", _button_box(_brown_dk))
	back_btn.add_theme_color_override("font_color", _cream)
	back_btn.add_theme_color_override("font_hover_color", _cream)
	back_btn.pressed.connect(_on_back_pressed)
	row.add_child(back_btn)

	var start_btn: Button = Button.new()
	start_btn.text = "Start Run"
	start_btn.custom_minimum_size = Vector2(240.0, 52.0)
	start_btn.add_theme_font_size_override("font_size", 24)
	start_btn.add_theme_stylebox_override("normal", _button_box(_amber_lite))
	start_btn.add_theme_stylebox_override("hover", _button_box(_amber_lite.lightened(0.10)))
	start_btn.add_theme_stylebox_override("pressed", _button_box(_amber_dk))
	start_btn.add_theme_color_override("font_color", _ink)
	start_btn.add_theme_color_override("font_hover_color", _brown_dk)
	start_btn.pressed.connect(_on_start_pressed)
	row.add_child(start_btn)

	return row


# --- Selection handlers -----------------------------------------------------

func _on_preset_pressed(rounds: int) -> void:
	# Picking a preset makes it the active length again and clears any custom override,
	# re-syncing the spinbox to the preset (presets are the primary path).
	_preset_rounds = rounds
	_custom_rounds_active = false
	if _rounds_spin != null:
		_rounds_spin.set_value_no_signal(float(rounds))
	_update_summary()


func _on_turn_system_pressed(turn_type: int) -> void:
	_turn_system = turn_type
	_update_summary()


func _on_rounds_override_changed(value: float) -> void:
	# The moment the player touches the spinbox, the override supersedes the preset.
	_custom_rounds_active = true
	_custom_rounds = clampi(int(round(value)), CUSTOM_MIN, CUSTOM_MAX)
	_update_summary()


# --- Resolution -------------------------------------------------------------

## Final round count: the custom override wins if the player touched the spinbox,
## otherwise the selected preset.
func _resolved_rounds() -> int:
	var rounds: int = _custom_rounds if _custom_rounds_active else _preset_rounds
	return clampi(rounds, CUSTOM_MIN, CUSTOM_MAX)


func _turn_system_name() -> String:
	if _turn_system == TurnSystemBase.TurnSystemType.INITIATIVE:
		return "Speed"
	return "Traditional"


func _update_summary() -> void:
	if _summary_label == null:
		return
	var source: String = "custom" if _custom_rounds_active else "preset"
	_summary_label.text = "Run: %d rounds (%s)  •  %s turns" % [
		_resolved_rounds(), source, _turn_system_name()
	]


# --- Start / Back -----------------------------------------------------------

func _on_start_pressed() -> void:
	var base: Resource = load(BASE_RULESET_PATH)
	if base == null:
		_show_message("Arena ruleset is missing -- cannot start a run.")
		return

	var arena: Node = get_node_or_null("/root/ArenaController")
	if arena == null or not arena.has_method("start_run"):
		_show_message("Arena mode is not available.")
		return

	# Never mutate the shared .tres -- deep-duplicate, then write the chosen settings.
	var rs: Resource = base.duplicate(true)
	if rs == null:
		_show_message("Could not prepare the run.")
		return
	rs.total_rounds = _resolved_rounds()
	rs.turn_system = _turn_system

	# start_run itself changes to the GameWorld scene -- do NOT change scene here.
	arena.start_run(rs)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true


# --- Background -------------------------------------------------------------

func _build_background() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = _bg_top
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var glow: ColorRect = ColorRect.new()
	glow.color = Color(_amber.r, _amber.g, _amber.b, 0.10)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.anchor_top = 0.45
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var vignette: ColorRect = ColorRect.new()
	vignette.color = Color(_bg_bottom.r, _bg_bottom.g, _bg_bottom.b, 0.55)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	vignette.anchor_top = 0.6
	vignette.offset_top = 0.0
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


# --- Styleboxes -------------------------------------------------------------

func _card_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = _amber
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(3)
	sb.border_color = _brown
	sb.set_content_margin_all(0.0)
	sb.shadow_color = Color(0, 0, 0, 0.42)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	return sb


func _button_box(fill: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(9)
	sb.set_border_width_all(2)
	sb.border_color = _brown_dk
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 8.0
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb


func _pill_box(fill: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = _brown_dk
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 7.0
	return sb


## Segmented-choice button look: unselected reads as a dim inset plate, the selected
## (pressed / toggled-on) state lights up amber so the current pick is obvious.
func _style_choice_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _button_box(_brown.lerp(_amber, 0.14)))
	btn.add_theme_stylebox_override("hover", _button_box(_brown.lerp(_amber, 0.28)))
	btn.add_theme_stylebox_override("pressed", _button_box(_amber_lite))
	btn.add_theme_stylebox_override("focus", _button_box(Color(0, 0, 0, 0)))
	btn.add_theme_color_override("font_color", _cream)
	btn.add_theme_color_override("font_hover_color", _cream)
	btn.add_theme_color_override("font_pressed_color", _ink)


# --- Palette load -----------------------------------------------------------

## Pull the warm colours from ConquestTheme (a verified script class_name; resolves at
## author time). The hardcoded defaults above stand in if the class is ever removed.
func _load_palette() -> void:
	_plate_fill = ConquestTheme.PLATE_BG
	_ink = ConquestTheme.INK
	_cream = ConquestTheme.CREAM
	_cream_dim = ConquestTheme.CREAM_DIM
	_amber = ConquestTheme.AMBER
	_amber_lite = ConquestTheme.AMBER_LITE
	_amber_dk = ConquestTheme.AMBER_DK
	_brown = ConquestTheme.BROWN
	_brown_dk = ConquestTheme.BROWN_DK
	_gold = ConquestTheme.EL_HOLY
	_bg_top = ConquestTheme.INK.lerp(Color.BLACK, 0.15)
	_bg_bottom = ConquestTheme.BROWN_DK.darkened(0.35)
