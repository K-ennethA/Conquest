extends Control

class_name MatchConfigPanel

## Reusable, code-built configuration column shared by every "set up a match" surface:
## the unified [b]MatchSetup[/b] screen (Solo -> Skirmish / Arena Run) and, embedded, the
## Versus lobby's waiting panel. It owns NO navigation -- it only renders the rows a given
## mode needs and reports the chosen values back to its host, which decides what to launch.
##
## Modes (call [method configure] once after adding the panel to the tree):
##   * [constant MODE_SKIRMISH] -- Turn System + AI Difficulty. Solo vs the AI on a map.
##   * [constant MODE_ARENA]    -- Turn System + Run Length (Short 4 / Standard 6 / Long 8 /
##                                 Custom 3-12). The arena-specific rows carry a subtle amber
##                                 accent to signal the roguelite register.
##   * [constant MODE_VERSUS]   -- Turn System + Rounds (Bo1 / Bo3 / Bo5). Host-side lobby.
##   * [constant MODE_LOCAL]    -- Turn System only. Local hot-seat versus on a map.
##   * [constant MODE_SIEGE]       -- Solo Siege vs the AI. Same rows as skirmish (Turn
##       System + AI Difficulty); the mode differs in what the MAP declares, not in what
##       this column has to ask.
##   * [constant MODE_SIEGE_LOCAL] -- Local hot-seat Siege. Turn System only, exactly as
##       MODE_LOCAL. Two strings rather than one flagged mode because that is already how
##       this panel tells "solo vs AI" from "hot-seat" (skirmish vs local), and a single
##       siege string would have to consult GameSettings.game_mode to know which rows to
##       draw -- a dependency this panel deliberately does not have.
##
## Host reads back with [method get_turn_system] / [method get_ai_difficulty] /
## [method get_run_length] / [method get_versus_rounds], and can push the universal picks
## to GameSettings via [method apply_settings] (turn system always; AI difficulty in
## skirmish; versus rounds in versus). Arena run length is NOT written to GameSettings --
## the host stamps it onto the duplicated ruleset instead.

const MODE_SKIRMISH := "skirmish"
const MODE_ARENA := "arena"
const MODE_VERSUS := "versus"
const MODE_LOCAL := "local"
const MODE_SIEGE := "siege"
const MODE_SIEGE_LOCAL := "siege_local"

## Every mode that is a SIEGE match, whichever side of the solo/versus split it came from.
## Consumers ask this instead of comparing against the two strings, so a third siege
## variant is one array entry rather than a scattered `or`.
const SIEGE_MODES: Array[String] = [MODE_SIEGE, MODE_SIEGE_LOCAL]


## True when [param mode] launches a Siege match (solo or hot-seat).
static func is_siege_mode(mode: String) -> bool:
	return SIEGE_MODES.has(mode)

# Run-length presets (rounds). Standard is the default.
const PRESET_SHORT := 4
const PRESET_STANDARD := 6
const PRESET_LONG := 8

# Rounds-override spinbox bounds (arena Custom).
const CUSTOM_MIN := 3
const CUSTOM_MAX := 12

var _mode: String = MODE_SKIRMISH

# --- Live control refs ------------------------------------------------------
var _turn_option: OptionButton = null
var _difficulty_option: OptionButton = null
var _versus_option: OptionButton = null

# Arena run-length state (mirrors ArenaSetupScreen's preset-vs-override resolution).
var _preset_group: ButtonGroup = null
var _rounds_spin: SpinBox = null
var _preset_rounds: int = PRESET_STANDARD
var _custom_rounds_active: bool = false
var _custom_rounds: int = PRESET_STANDARD


## Build the rows for [param mode] and reset selections to sane defaults. Safe to call
## again to rebuild in a different mode. Reads current GameSettings so re-opening the
## panel reflects the last chosen turn system / difficulty.
func configure(mode: String) -> void:
	_mode = mode
	_turn_option = null
	_difficulty_option = null
	_versus_option = null
	_preset_group = null
	_rounds_spin = null
	for child in get_children():
		child.queue_free()

	var col := VBoxContainer.new()
	col.name = "ConfigRows"
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	col.add_child(_turn_system_row())

	match _mode:
		MODE_SKIRMISH, MODE_SIEGE:
			col.add_child(_difficulty_row())
		MODE_ARENA:
			col.add_child(_section_heading("RUN LENGTH", true))
			col.add_child(_run_length_row())
			col.add_child(_custom_rounds_row())
		MODE_VERSUS:
			col.add_child(_versus_rounds_row())
		MODE_LOCAL, MODE_SIEGE_LOCAL:
			pass  # Turn System only for local hot-seat.


# --- Row factories ----------------------------------------------------------

func _turn_system_row() -> Control:
	var row := _labelled_row("Turn System")
	_turn_option = OptionButton.new()
	_turn_option.add_item("Traditional", TurnSystemBase.TurnSystemType.TRADITIONAL)
	_turn_option.add_item("Speed First", TurnSystemBase.TurnSystemType.INITIATIVE)
	_turn_option.tooltip_text = "Traditional: each side acts in full. Speed First: units act in speed order."
	_select_option_by_id(_turn_option, GameSettings.selected_turn_system)
	_turn_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_turn_option)
	return row


func _difficulty_row() -> Control:
	var row := _labelled_row("AI Difficulty")
	_difficulty_option = OptionButton.new()
	for i in range(4):  # BotController.Difficulty: EASY..BRUTAL
		_difficulty_option.add_item(BotController.difficulty_name(i), i)
	_select_option_by_id(_difficulty_option, clampi(GameSettings.ai_difficulty, 0, 3))
	_difficulty_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_difficulty_option)
	return row


func _versus_rounds_row() -> Control:
	var row := _labelled_row("Rounds")
	_versus_option = OptionButton.new()
	_versus_option.add_item("Best of 1", 1)
	_versus_option.add_item("Best of 3", 3)
	_versus_option.add_item("Best of 5", 5)
	_versus_option.tooltip_text = "How many games decide the match (applied locally by the host)."
	_select_option_by_id(_versus_option, clampi(GameSettings.versus_rounds, 1, 5))
	_versus_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_versus_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_versus_option)
	return row


func _run_length_row() -> Control:
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 10)
	_preset_group = ButtonGroup.new()
	presets.add_child(_make_preset_button("Short", PRESET_SHORT))
	presets.add_child(_make_preset_button("Standard", PRESET_STANDARD))
	presets.add_child(_make_preset_button("Long", PRESET_LONG))
	return presets


func _custom_rounds_row() -> Control:
	var row := _labelled_row("Custom")
	_rounds_spin = SpinBox.new()
	_rounds_spin.min_value = float(CUSTOM_MIN)
	_rounds_spin.max_value = float(CUSTOM_MAX)
	_rounds_spin.step = 1.0
	_rounds_spin.value = float(_preset_rounds)
	_rounds_spin.custom_minimum_size = Vector2(120.0, 0.0)
	_rounds_spin.tooltip_text = "Overrides the preset once changed (%d-%d)." % [CUSTOM_MIN, CUSTOM_MAX]
	_rounds_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rounds_spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_rounds_spin)
	# Connect AFTER setting the initial value so the sync above is not counted as a touch.
	_rounds_spin.value_changed.connect(_on_rounds_override_changed)
	return row


func _make_preset_button(label: String, rounds: int) -> Button:
	var btn := Button.new()
	btn.text = "%s\n%d" % [label, rounds]
	btn.toggle_mode = true
	btn.button_group = _preset_group
	btn.custom_minimum_size = Vector2(0.0, 52.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if rounds == _preset_rounds:
		btn.button_pressed = true
	btn.pressed.connect(_on_preset_pressed.bind(rounds))
	return btn


## An HBox with a left-aligned cream label and space for a right-aligned control.
## Fixed to a >=40px row height so every config row -- across skirmish, arena and
## versus -- reads at the same scale.
func _labelled_row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 40.0)
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(140.0, 0.0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	return row


## A section heading; [param amber] tints it gold to flag arena-only rows, dim
## cream otherwise (shared [method MenuTheme.style_section_header] register).
func _section_heading(text: String, amber: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	MenuTheme.style_section_header(lbl, amber)
	return lbl


# --- Selection handlers -----------------------------------------------------

func _on_preset_pressed(rounds: int) -> void:
	# Picking a preset makes it the active length again and clears any custom override,
	# re-syncing the spinbox to the preset (presets are the primary path).
	_preset_rounds = rounds
	_custom_rounds_active = false
	if _rounds_spin != null:
		_rounds_spin.set_value_no_signal(float(rounds))


func _on_rounds_override_changed(value: float) -> void:
	# The moment the player touches the spinbox, the override supersedes the preset.
	_custom_rounds_active = true
	_custom_rounds = clampi(int(round(value)), CUSTOM_MIN, CUSTOM_MAX)


# --- Read-back API ----------------------------------------------------------

## The chosen turn system (TurnSystemBase.TurnSystemType). Defaults to Traditional.
func get_turn_system() -> int:
	if _turn_option == null:
		return TurnSystemBase.TurnSystemType.TRADITIONAL
	return _turn_option.get_selected_id()


## The chosen AI difficulty (0..3). Meaningful only in skirmish; falls back to the
## current GameSettings value otherwise.
func get_ai_difficulty() -> int:
	if _difficulty_option == null:
		return clampi(GameSettings.ai_difficulty, 0, 3)
	return _difficulty_option.get_selected_id()


## Final arena round count: the custom override wins if the player touched the spinbox,
## otherwise the selected preset. Clamped to the valid band.
func get_run_length() -> int:
	var rounds: int = _custom_rounds if _custom_rounds_active else _preset_rounds
	return clampi(rounds, CUSTOM_MIN, CUSTOM_MAX)


## The chosen Versus best-of count (1 / 3 / 5). Falls back to GameSettings otherwise.
func get_versus_rounds() -> int:
	if _versus_option == null:
		return clampi(GameSettings.versus_rounds, 1, 9)
	return _versus_option.get_selected_id()


## Push the universal picks to GameSettings: turn system always; AI difficulty in
## skirmish; versus rounds in versus. Arena run length is written to the ruleset by the
## host, not here.
func apply_settings() -> void:
	if GameSettings == null:
		return
	if GameSettings.has_method("set_turn_system"):
		GameSettings.set_turn_system(get_turn_system())
	if (_mode == MODE_SKIRMISH or _mode == MODE_SIEGE) and GameSettings.has_method("set_ai_difficulty"):
		GameSettings.set_ai_difficulty(get_ai_difficulty())
	if _mode == MODE_VERSUS and GameSettings.has_method("set_versus_rounds"):
		GameSettings.set_versus_rounds(get_versus_rounds())


# --- Helpers ----------------------------------------------------------------

## Select the OptionButton entry whose item id equals [param id]; no-op if absent.
func _select_option_by_id(option: OptionButton, id: int) -> void:
	for i in range(option.item_count):
		if option.get_item_id(i) == id:
			option.select(i)
			return
