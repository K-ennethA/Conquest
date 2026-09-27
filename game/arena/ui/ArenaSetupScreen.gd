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
##
## Presentation uses the shared out-of-battle kit (MenuTheme / MenuKit): breadcrumb
## page, run-length preset cards, segmented turn-system toggle, consistent Back.

const BASE_RULESET_PATH := "res://game/arena/rulesets/arena_solo.tres"
const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

# Run-length presets (label -> rounds). Standard is the default.
const PRESET_SHORT := 4
const PRESET_STANDARD := 6
const PRESET_LONG := 8

# Rounds-override spinbox bounds.
const CUSTOM_MIN := 3
const CUSTOM_MAX := 12

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
	var page := MenuKit.build_page(self, ["Arena"], "Arena Run",
		"Battle through escalating waves of AI enemies. Between rounds you draft upgrades for your squad.")

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)
	center.add_child(_build_card())

	# --- Action buttons + live summary of what will actually launch -----------
	_summary_label = MenuKit.label("", &"DimLabel")
	_summary_label.name = "Summary"
	_summary_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.actions.add_child(_summary_label)
	var back_btn := MenuKit.button("Back", MenuKit.GHOST, 140)
	back_btn.name = "BackButton"
	back_btn.pressed.connect(_on_back_pressed)
	page.actions.add_child(back_btn)
	var start_btn := MenuKit.button("Choose Squad  >", MenuKit.PRIMARY, 240, 54)
	start_btn.name = "StartButton"
	start_btn.pressed.connect(_on_start_pressed)
	page.actions.add_child(start_btn)

	# --- Inline message (errors / guards) ------------------------------------
	MenuKit.add_standard_hints(page.hints)
	_message_label = MenuKit.label("", &"")
	_message_label.name = "Message"
	_message_label.visible = false
	page.hints.add_child(_message_label)

	_update_summary()
	for b in _preset_group.get_buttons():
		if (b as BaseButton).button_pressed:
			MenuNav.focus_deferred(b as Control)


# --- Card ------------------------------------------------------------------

func _build_card() -> Control:
	var panel := MenuKit.card()
	panel.name = "SetupCard"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.custom_minimum_size = Vector2(760, 0)
	panel.add_child(col)

	# RUN LENGTH (primary path) ----------------------------------------------
	col.add_child(MenuKit.section("Run length"))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", MenuTheme.SP_M)
	_preset_group = ButtonGroup.new()
	presets.add_child(_make_preset_button("Short", PRESET_SHORT, "A quick run"))
	presets.add_child(_make_preset_button("Standard", PRESET_STANDARD, "The intended length"))
	presets.add_child(_make_preset_button("Long", PRESET_LONG, "An endurance test"))
	col.add_child(presets)

	col.add_child(HSeparator.new())

	# Turn system row.
	var turn_row := HBoxContainer.new()
	turn_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	turn_row.add_child(_row_label("Turn system"))
	_turn_group = ButtonGroup.new()
	turn_row.add_child(_make_turn_button("Traditional", TurnSystemBase.TurnSystemType.TRADITIONAL))
	turn_row.add_child(_make_turn_button("Speed First", TurnSystemBase.TurnSystemType.INITIATIVE))
	col.add_child(turn_row)

	# Rounds override row.
	var rounds_row := HBoxContainer.new()
	rounds_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	rounds_row.add_child(_row_label("Custom rounds"))
	_rounds_spin = SpinBox.new()
	_rounds_spin.name = "RoundsSpin"
	_rounds_spin.min_value = float(CUSTOM_MIN)
	_rounds_spin.max_value = float(CUSTOM_MAX)
	_rounds_spin.step = 1.0
	_rounds_spin.value = float(_preset_rounds)
	_rounds_spin.custom_minimum_size = Vector2(130.0, 46.0)
	_rounds_spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rounds_spin.tooltip_text = "Overrides the preset once changed (3-12)."
	rounds_row.add_child(_rounds_spin)
	var note := MenuKit.label("Overrides the preset once changed (%d-%d)." % [CUSTOM_MIN, CUSTOM_MAX], &"MutedLabel")
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rounds_row.add_child(note)
	col.add_child(rounds_row)
	# Connect AFTER setting the initial value so the sync above does not count as a touch.
	_rounds_spin.value_changed.connect(_on_rounds_override_changed)

	# Mode row (Solo now; Versus is a disabled "coming soon" affordance). ------
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	mode_row.add_child(_row_label("Mode"))
	var solo := MenuKit.badge("Solo", MenuTheme.GOLD, true)
	solo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_row.add_child(solo)
	var versus := MenuKit.badge("Versus -- coming soon", MenuTheme.TEXT_MUTED)
	versus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_row.add_child(versus)
	col.add_child(mode_row)
	return panel


# --- Widget factories -------------------------------------------------------

func _make_preset_button(label: String, rounds: int, blurb: String) -> Button:
	var parts := MenuKit.option_card(Vector2(236, 108), true)
	var btn: Button = parts["button"]
	btn.name = "Preset" + label
	btn.button_group = _preset_group
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = parts["content"]
	v.add_theme_constant_override("separation", 2)
	v.add_child(MenuKit.label(label, &"SubheadingLabel"))
	var r := MenuKit.label("%d rounds" % rounds, &"")
	r.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	v.add_child(r)
	var d := MenuKit.label(blurb, &"MutedLabel")
	v.add_child(d)
	MenuKit.ignore_mouse(btn)
	MenuNav.hover_focus(btn)
	if rounds == _preset_rounds:
		btn.button_pressed = true
	btn.pressed.connect(_on_preset_pressed.bind(rounds))
	return btn


func _make_turn_button(label: String, turn_type: int) -> Button:
	var btn := MenuKit.button(label, &"", 170, 46)
	btn.toggle_mode = true
	btn.button_group = _turn_group
	if turn_type == _turn_system:
		btn.button_pressed = true
	btn.pressed.connect(_on_turn_system_pressed.bind(turn_type))
	return btn


func _row_label(text: String) -> Label:
	var lbl := MenuKit.label(text, &"")
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lbl


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
		return "Speed First"
	return "Traditional"


func _update_summary() -> void:
	if _summary_label == null:
		return
	var source: String = "custom" if _custom_rounds_active else "preset"
	_summary_label.text = "%d rounds (%s)  ·  %s turns" % [
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

	# Stage the ruleset and go pick a squad; Character Select calls begin_pending_run(),
	# which starts the run (and changes to the GameWorld scene) with the chosen units.
	arena.prepare_run(rs)
	MenuNav.change_scene(self, "res://menus/CharacterSelect.tscn")


func _on_back_pressed() -> void:
	# Discard any staged ruleset so it can't leak into a later map launch.
	var arena: Node = get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("abort_run"):
		arena.abort_run()
	MenuNav.change_scene(self, MAIN_MENU_SCENE)


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	MenuKit.set_status(_message_label, text, "error")
	_message_label.visible = true


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
