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
## Look: the shared illuminated-grove theme (it inherits its host's [MenuTheme]). The turn
## system is picked on two compact toggle cards with a tiny turn-order diagram each (the
## explanation the old stand-alone TurnSystemSelection screen gave, folded in here); every
## other row is a Cinzel caption + a themed control.
##
## Host reads back with [method get_turn_system] / [method get_ai_difficulty] /
## [method get_run_length] / [method get_versus_rounds], and can push the universal picks
## to GameSettings via [method apply_settings] (turn system always; AI difficulty in
## skirmish; versus rounds in versus). Arena run length is NOT written to GameSettings --
## the host stamps it onto the duplicated ruleset instead.

## Emitted whenever the player changes any pick (turn system, difficulty, run length,
## rounds) -- lets the host keep a live "what will launch" summary.
signal changed

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

## Lay the rows out for a NARROW host column: the two turn-system cards stack vertically
## instead of side by side, and each captioned row puts its caption ABOVE its control
## instead of beside it. A host whose column is narrow (MatchSetup's ~320px settings column
## at 1280x720) sets this BEFORE [method configure]: two Cinzel card titles, or a caption
## plus a dropdown, do not fit side by side in that width, and a row that does not fit
## spills past the card edge.
var narrow_layout: bool = false

# --- Live control refs ------------------------------------------------------
## Turn-system toggle cards keyed by TurnSystemBase.TurnSystemType id (one ButtonGroup).
var _turn_cards: Dictionary = {}
var _turn_group: ButtonGroup = null
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
	_turn_cards = {}
	_turn_group = null
	_difficulty_option = null
	_versus_option = null
	_preset_group = null
	_rounds_spin = null
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var col := VBoxContainer.new()
	col.name = "ConfigRows"
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", MenuTheme.SP_S if narrow_layout else MenuTheme.SP_M)
	add_child(col)

	col.add_child(_section_heading("Turn System"))
	col.add_child(_turn_system_row())

	match _mode:
		MODE_SKIRMISH, MODE_SIEGE:
			col.add_child(_difficulty_row())
			var note := MenuKit.label(
				"Harder AI plays sharper -- and some maps field extra enemies on Hard and above.",
				&"MutedLabel", true)
			note.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
			col.add_child(note)
		MODE_ARENA:
			col.add_child(_section_heading("Run Length", true))
			col.add_child(_run_length_row())
			col.add_child(_custom_rounds_row())
		MODE_VERSUS:
			col.add_child(_versus_rounds_row())
		MODE_LOCAL, MODE_SIEGE_LOCAL:
			pass  # Turn System only for local hot-seat.

	# The rows are laid out full-rect inside this plain Control, which does not size to
	# its children: grow the panel's minimum height to fit them (never below the floor
	# the host asked for), so the turn cards can never overlap the rows beneath.
	var floor_h: float = custom_minimum_size.y
	col.minimum_size_changed.connect(func() -> void:
		var need: float = maxf(floor_h, col.get_combined_minimum_size().y)
		if absf(custom_minimum_size.y - need) > 0.5:
			custom_minimum_size.y = need)


# --- Row factories ----------------------------------------------------------

## The turn system as two side-by-side toggle cards, each with a tiny turn-order diagram
## (blue / red pips) -- the look of the old TurnSystemSelection screen, sized for a column.
func _turn_system_row() -> Control:
	var row: BoxContainer = VBoxContainer.new() if narrow_layout else HBoxContainer.new()
	row.name = "TurnSystemCards"
	row.add_theme_constant_override("separation", MenuTheme.SP_M)
	_turn_group = ButtonGroup.new()
	row.add_child(_make_turn_card(TurnSystemBase.TurnSystemType.TRADITIONAL, "Traditional",
		"Armies take turns", "BBB|RRR", MenuTheme.GOLD,
		"You move every one of your units, then your opponent moves all of theirs."))
	row.add_child(_make_turn_card(TurnSystemBase.TurnSystemType.INITIATIVE, "Speed First",
		"Units act by speed", "BRBBRR", MenuTheme.ACCENT,
		"Every unit acts once per round, fastest first -- whichever army it belongs to."))
	var current: int = GameSettings.selected_turn_system if GameSettings != null \
		else TurnSystemBase.TurnSystemType.TRADITIONAL
	var pick: Button = _turn_cards.get(current, _turn_cards.get(TurnSystemBase.TurnSystemType.TRADITIONAL))
	if pick != null:
		pick.button_pressed = true
	return row


func _make_turn_card(id: int, title: String, tagline: String, pips: String, accent: Color,
		tip: String) -> Button:
	# Narrow (stacked) cards drop the fixed 96px floor and size to their three lines.
	var parts := MenuKit.option_card(Vector2(0, 0 if narrow_layout else 96), true)
	var b: Button = parts["button"]
	b.name = title.replace(" ", "") + "Card"
	b.button_group = _turn_group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = tip
	MenuKit.accent_card(b, accent)
	var m: MarginContainer = parts["margin"]
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8 if narrow_layout else 10)
	var v: VBoxContainer = parts["content"]
	v.add_theme_constant_override("separation", 2 if narrow_layout else 4)
	var t := MenuKit.label(title, &"SubheadingLabel")
	v.add_child(t)
	var tl := MenuKit.label(tagline.to_upper(), &"SectionLabel")
	tl.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	tl.add_theme_color_override("font_color", accent.lightened(0.2))
	v.add_child(tl)
	v.add_child(MenuKit.pip_row(pips))
	MenuKit.ignore_mouse(b)
	MenuNav.hover_focus(b)
	b.toggled.connect(func(on: bool) -> void:
		if on:
			changed.emit())
	_turn_cards[id] = b
	return b


func _difficulty_row() -> Control:
	var row := _labelled_row("AI Difficulty")
	_difficulty_option = OptionButton.new()
	_difficulty_option.name = "DifficultyOption"
	for i in range(4):  # BotController.Difficulty: EASY..BRUTAL
		_difficulty_option.add_item(BotController.difficulty_name(i), i)
	_select_option_by_id(_difficulty_option, clampi(GameSettings.ai_difficulty, 0, 3))
	_difficulty_option.custom_minimum_size = Vector2(0.0, 44.0)
	_difficulty_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	MenuNav.hover_focus(_difficulty_option)
	_difficulty_option.item_selected.connect(func(_i: int) -> void: changed.emit())
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
	_versus_option.custom_minimum_size = Vector2(0.0, 44.0)
	_versus_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_versus_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	MenuNav.hover_focus(_versus_option)
	_versus_option.item_selected.connect(func(_i: int) -> void: changed.emit())
	row.add_child(_versus_option)
	return row


func _run_length_row() -> Control:
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 10)
	_preset_group = ButtonGroup.new()
	presets.add_child(_make_preset_button("Short", PRESET_SHORT, "A quick run"))
	presets.add_child(_make_preset_button("Standard", PRESET_STANDARD, "The intended length"))
	presets.add_child(_make_preset_button("Long", PRESET_LONG, "An endurance test"))
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


func _make_preset_button(label: String, rounds: int, blurb: String = "") -> Button:
	# A small toggle option card: preset name over its round count, gold frame when picked.
	var parts := MenuKit.option_card(Vector2(0.0, 60.0), true)
	var btn: Button = parts["button"]
	btn.name = label + "Preset"
	btn.button_group = _preset_group
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.tooltip_text = ("%s run: %d rounds. %s" % [label, rounds, blurb]).strip_edges()
	var m: MarginContainer = parts["margin"]
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 10)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8)
	var v: VBoxContainer = parts["content"]
	v.add_theme_constant_override("separation", 0)
	var t := MenuKit.label(label, &"SubheadingLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var n := MenuKit.label("%d rounds" % rounds, &"")
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	n.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	v.add_child(n)
	if not blurb.is_empty():
		var d := MenuKit.label(blurb, &"MutedLabel")
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		d.clip_text = true
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(d)
	MenuKit.ignore_mouse(btn)
	MenuNav.hover_focus(btn)
	if rounds == _preset_rounds:
		btn.button_pressed = true
	btn.pressed.connect(_on_preset_pressed.bind(rounds))
	return btn


## An HBox with a left-aligned caption and space for a right-aligned control.
## Fixed to a >=44px row height (touch rule) so every config row -- across skirmish,
## arena and versus -- reads at the same scale. In [member narrow_layout] it is a VBox
## instead: caption on top, the control full-width beneath it.
func _labelled_row(text: String) -> BoxContainer:
	var row: BoxContainer = VBoxContainer.new() if narrow_layout else HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 44.0)
	row.add_theme_constant_override("separation", MenuTheme.SP_XS if narrow_layout else MenuTheme.SP_M)
	var lbl := MenuKit.label(text, &"SubheadingLabel")
	if not narrow_layout:
		lbl.custom_minimum_size = Vector2(140.0, 0.0)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	return row


## A Cinzel section caption; [param amber] tints it gold to flag arena-only rows (the
## roguelite register), the theme's section colour otherwise.
func _section_heading(text: String, amber: bool = false) -> Label:
	# SectionLabel (Cinzel caps: its lowercase are small capitals), text kept as written.
	var lbl := MenuKit.label(text, &"SectionLabel")
	if amber:
		lbl.add_theme_color_override("font_color", MenuTheme.GOLD)
	return lbl


# --- Selection handlers -----------------------------------------------------

func _on_preset_pressed(rounds: int) -> void:
	# Picking a preset makes it the active length again and clears any custom override,
	# re-syncing the spinbox to the preset (presets are the primary path).
	_preset_rounds = rounds
	_custom_rounds_active = false
	if _rounds_spin != null:
		_rounds_spin.set_value_no_signal(float(rounds))
	changed.emit()


func _on_rounds_override_changed(value: float) -> void:
	# The moment the player touches the spinbox, the override supersedes the preset.
	_custom_rounds_active = true
	_custom_rounds = clampi(int(round(value)), CUSTOM_MIN, CUSTOM_MAX)
	changed.emit()


## "6 rounds (preset)" / "9 rounds (custom)" -- the arena run length as it will launch.
func run_length_text() -> String:
	return "%d rounds (%s)" % [get_run_length(), "custom" if _custom_rounds_active else "preset"]


## "Traditional" / "Speed First" -- the chosen turn system's display name.
func turn_system_name() -> String:
	if get_turn_system() == TurnSystemBase.TurnSystemType.INITIATIVE:
		return "Speed First"
	return "Traditional"


# --- Read-back API ----------------------------------------------------------

## The chosen turn system (TurnSystemBase.TurnSystemType). Defaults to Traditional.
func get_turn_system() -> int:
	for id in _turn_cards:
		var card: Button = _turn_cards[id]
		if is_instance_valid(card) and card.button_pressed:
			return int(id)
	return TurnSystemBase.TurnSystemType.TRADITIONAL


## Select the turn system card for [param turn_system] (a TurnSystemBase.TurnSystemType).
func set_turn_system(turn_system: int) -> void:
	var card: Button = _turn_cards.get(turn_system, null)
	if card != null:
		card.button_pressed = true


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
