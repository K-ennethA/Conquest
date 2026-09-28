extends Control

class_name SettingsPanel

# Fire-Emblem / Pokemon-style OPTIONS overlay. THE one settings surface: the
# battle HUD mounts it behind its top-right gear (see
# game/ui/layout/UILayoutManager.gd), and MainMenu / PauseMenu mount the same
# class behind their own gear so the menu and the battle expose an identical
# panel rather than two drifting copies.
#
# Pure front-end for the presentation settings that already live in the
# `GameSettings` autoload: it reads current values when opened, writes through
# the `set_*` helpers on change, and re-syncs when `settings_changed` fires from
# anywhere else. All GameSettings access is guarded so the panel is safe in a
# headless / minimal scene where the autoload might be absent or default.
#
# Three tabs:
#   General  -- animations, battle speed, camera focus, the Speed-First move
#               clock, weather effects (visual only) and the board grid overlay.
#   Audio    -- the three volume sliders. They write GameSettings.master/music/
#               ui_volume (LINEAR 0..1), GameSettings persists them and emits, and
#               AudioManager re-levels itself off that signal -- this panel never
#               touches AudioManager or an audio bus directly.
#   Controls -- keyboard rebinding for every InputActions.REBINDABLE action
#               (gamepad bindings are fixed and listed for reference).
#
# Built entirely in code (no .tscn) so it can be instantiated and mounted by the
# HUD without fragile node paths, and so the whole layout lives in one place.

# --- Speed presets shown in the slider label / snapping ---------------------
const _SPEED_STEP := 0.25

# Volume sliders run 0..1 (the unit GameSettings stores) in 5% detents and are
# shown as a percentage.
const _VOLUME_STEP := 0.05

# Vertical rhythm inside a tab. The General tab is the tallest content tab; at
# this gap the whole card (title + tabs + Close) still fits a 720-tall viewport
# without scrolling (the Controls tab scrolls its own list).
const _ROW_SEPARATION := 12

# Fallback list used when GameSettings is absent; mirrors
# GameSettings.SPEED_TIMER_ALLOWED.
const _TIMER_FALLBACK: Array[int] = [0, 15, 20, 30]

# Controls (created in _build_ui)
var _backdrop: ColorRect = null
var _frame: PanelContainer = null
var _anim_check: CheckButton = null
var _speed_slider: HSlider = null
var _speed_value_label: Label = null
var _focus_option: OptionButton = null
var _timer_value_label: Label = null
var _timer_prev_button: Button = null
var _timer_next_button: Button = null
var _weather_option: OptionButton = null
var _grid_option: OptionButton = null
var _master_slider: HSlider = null
var _master_value_label: Label = null
var _music_slider: HSlider = null
var _music_value_label: Label = null
var _ui_slider: HSlider = null
var _ui_value_label: Label = null

# Controls tab: action -> the Button showing (and capturing) its keyboard binding.
var _bind_buttons: Dictionary = {}
# Action currently waiting for a key press ("" when not capturing).
var _capturing_action: StringName = &""
var _controls_status: Label = null

# True while we are pushing GameSettings values INTO the controls, so the
# controls' change signals don't bounce back out into the setters (feedback loop).
var _syncing: bool = false


func _ready() -> void:
	# Cover the whole screen and swallow input so board clicks don't fall through
	# while the panel is open.
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	# While open, board/HUD gameplay handlers ignore input (InputActions.gameplay_input_blocked).
	add_to_group(InputActions.OVERLAY_GROUP)

	_build_ui()

	# The shared navy + gold look (same tokens in battle and in the main menu).
	ConquestTheme.apply_to(self)
	var frame_sb := ConquestTheme.panel_box(0.98)
	frame_sb.border_color = MenuTheme.GOLD_DK
	frame_sb.crest = true
	_frame.add_theme_stylebox_override("panel", frame_sb)
	# Our subtree is already themed: keep a later HUD-wide sweep off the frame.
	ConquestTheme.keep_style(_frame)
	_apply_local_colours()

	# Stay in sync with external changes (other systems / a second panel).
	if _has_settings() and not GameSettings.settings_changed.is_connected(_on_settings_changed):
		GameSettings.settings_changed.connect(_on_settings_changed)
	if _has_settings() and GameSettings.has_signal("controls_changed") \
			and not GameSettings.controls_changed.is_connected(_refresh_bindings):
		GameSettings.controls_changed.connect(_refresh_bindings)

	_refresh_from_settings()


func _exit_tree() -> void:
	if _has_settings() and GameSettings.settings_changed.is_connected(_on_settings_changed):
		GameSettings.settings_changed.disconnect(_on_settings_changed)
	if _has_settings() and GameSettings.has_signal("controls_changed") \
			and GameSettings.controls_changed.is_connected(_refresh_bindings):
		GameSettings.controls_changed.disconnect(_refresh_bindings)


func _has_settings() -> bool:
	return typeof(GameSettings) == TYPE_OBJECT


## Re-apply the deliberate text colours after ConquestTheme.apply_to() (which strips
## every baked label colour back to the theme default).
func _apply_local_colours() -> void:
	var title_node := _frame.find_child("Title", true, false) as Label
	if title_node != null:
		title_node.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	var hint := _frame.find_child("ControlsHint", true, false) as Label
	if hint != null:
		hint.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	for lbl in _frame.find_children("PadBinding*", "Label", true, false):
		(lbl as Label).add_theme_color_override("font_color", MenuTheme.TEXT_MUTED)


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	# Dim backdrop behind the card; absorbs clicks (and closes on click-away).
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.03, 0.08, 0.6)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	# Center the card.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_frame = PanelContainer.new()
	_frame.custom_minimum_size = Vector2(560, 0)
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_frame.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "Settings"
	title.add_theme_font_override("font", MenuTheme.display_font(2))
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)
	var rule := GroveRule.new()
	rule.color = MenuTheme.GOLD
	rule.custom_minimum_size = Vector2(160, 10)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(rule)

	# Tabs: General (presentation), Audio (volumes), Controls (keyboard rebinding).
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)

	tabs.add_child(_build_general_tab())
	tabs.add_child(_build_audio_tab())
	tabs.add_child(_build_controls_tab())

	vbox.add_child(_make_separator())

	# --- Close ---
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.theme_type_variation = &"PrimaryButton"
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


func _build_general_tab() -> Control:
	var general := VBoxContainer.new()
	general.name = "General"
	general.add_theme_constant_override("separation", _ROW_SEPARATION)

	# --- Animations toggle ---
	var anim_row := _make_row("Animations")
	_anim_check = CheckButton.new()
	_anim_check.mouse_filter = Control.MOUSE_FILTER_STOP
	_anim_check.toggled.connect(_on_anim_toggled)
	anim_row.add_child(_anim_check)
	general.add_child(anim_row)

	# --- Battle speed slider (0.5x - 3.0x, step 0.25) ---
	var speed_header := _make_row("Battle Speed")
	_speed_value_label = Label.new()
	_speed_value_label.text = "1.0x"
	_speed_value_label.custom_minimum_size = Vector2(52, 0)
	_speed_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_value_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	speed_header.add_child(_speed_value_label)
	general.add_child(speed_header)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = _settings_speed_min()
	_speed_slider.max_value = _settings_speed_max()
	_speed_slider.step = _SPEED_STEP
	_speed_slider.value = 1.0
	_speed_slider.custom_minimum_size = Vector2(0, 24)
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_speed_slider.value_changed.connect(_on_speed_changed)
	general.add_child(_speed_slider)

	general.add_child(_make_separator())

	# --- Camera auto-focus ---
	var focus_row := _make_row("Camera Focus")
	_focus_option = OptionButton.new()
	_focus_option.mouse_filter = Control.MOUSE_FILTER_STOP
	# Indices map directly onto GameSettings.AutoFocus (OFF=0, QUICK=1, CINEMATIC=2).
	_focus_option.add_item("Off", 0)
	_focus_option.add_item("Quick", 1)
	_focus_option.add_item("Cinematic", 2)
	_focus_option.item_selected.connect(_on_focus_selected)
	focus_row.add_child(_focus_option)
	general.add_child(focus_row)

	# --- Speed First move clock ---
	# A stepper, not a slider: the allowed values are a fixed short list
	# (GameSettings.SPEED_TIMER_ALLOWED = Off/15/20/30), so stepping through them
	# by index cannot land on an unrepresentable value the way dragging would.
	general.add_child(_build_timer_row())

	general.add_child(_make_separator())

	# --- Weather effects (visual only; gameplay unaffected) ---
	var weather_row := _make_row("Weather Effects")
	_weather_option = OptionButton.new()
	_weather_option.mouse_filter = Control.MOUSE_FILTER_STOP
	# Indices map onto GameSettings.WeatherEffects (FULL=0, REDUCED=1, OFF=2).
	_weather_option.add_item("Full", 0)
	_weather_option.add_item("Reduced", 1)
	_weather_option.add_item("Off (visual only)", 2)
	_weather_option.item_selected.connect(_on_weather_selected)
	weather_row.add_child(_weather_option)
	general.add_child(weather_row)

	# --- Optional board grid overlay (GameSettings.GridLines: OFF=0, SUBTLE=1) ---
	var grid_row := _make_row("Grid Lines")
	_grid_option = OptionButton.new()
	_grid_option.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_option.add_item("Off", 0)
	_grid_option.add_item("Subtle", 1)
	_grid_option.item_selected.connect(_on_grid_selected)
	grid_row.add_child(_grid_option)
	general.add_child(grid_row)

	return general


func _build_audio_tab() -> Control:
	var audio := VBoxContainer.new()
	audio.name = "Audio"
	audio.add_theme_constant_override("separation", _ROW_SEPARATION)

	_master_value_label = Label.new()
	_master_slider = _build_volume_control(audio, "Master", _master_value_label, _on_master_volume_changed)
	_music_value_label = Label.new()
	_music_slider = _build_volume_control(audio, "Music", _music_value_label, _on_music_volume_changed)
	_ui_value_label = Label.new()
	_ui_slider = _build_volume_control(audio, "Interface", _ui_value_label, _on_ui_volume_changed)

	return audio


## The Speed-First move-clock stepper: `< value >` over the fixed allowed list.
## Both arrows are >= 40px wide so the control stays touch-usable on a phone.
func _build_timer_row() -> HBoxContainer:
	var row := _make_row("Speed Timer")

	_timer_prev_button = Button.new()
	_timer_prev_button.name = "TimerPrev"
	_timer_prev_button.text = "<"
	_timer_prev_button.custom_minimum_size = Vector2(44, 36)
	_timer_prev_button.tooltip_text = "Shorter move clock"
	_timer_prev_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_timer_prev_button.pressed.connect(_on_timer_step.bind(-1))
	row.add_child(_timer_prev_button)

	_timer_value_label = Label.new()
	_timer_value_label.name = "TimerValue"
	_timer_value_label.text = "Off"
	_timer_value_label.custom_minimum_size = Vector2(56, 0)
	_timer_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_value_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	row.add_child(_timer_value_label)

	_timer_next_button = Button.new()
	_timer_next_button.name = "TimerNext"
	_timer_next_button.text = ">"
	_timer_next_button.custom_minimum_size = Vector2(44, 36)
	_timer_next_button.tooltip_text = "Longer move clock"
	_timer_next_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_timer_next_button.pressed.connect(_on_timer_step.bind(1))
	row.add_child(_timer_next_button)

	return row


## One volume control: a `Label ..... 60%` header row plus the slider under it.
## Appends both to [param parent] and returns the slider; [param value_label] is
## the caller's label so it can be kept for later refreshes.
func _build_volume_control(parent: VBoxContainer, label_text: String, value_label: Label,
		on_changed: Callable) -> HSlider:
	var header := _make_row(label_text)
	value_label.text = "100%"
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	header.add_child(value_label)
	parent.add_child(header)

	var slider := HSlider.new()
	slider.name = label_text + "Volume"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = _VOLUME_STEP
	slider.value = 1.0
	slider.custom_minimum_size = Vector2(0, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.value_changed.connect(on_changed)
	parent.add_child(slider)
	return slider


func _build_controls_tab() -> Control:
	"""Controls tab: one row per rebindable action (InputActions.REBINDABLE) with a
	button showing its current keyboard key(s). Click a button, then press the new
	key (Esc cancels). Gamepad bindings are fixed and listed for reference."""
	var root := VBoxContainer.new()
	root.name = "Controls"
	root.add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.name = "ControlsHint"
	hint.text = "Click an action, then press a key. Esc cancels."
	hint.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	for entry in InputActions.REBINDABLE:
		var action: StringName = entry["action"]
		var lbl := Label.new()
		lbl.text = entry["label"]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		grid.add_child(lbl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 34)
		btn.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_begin_capture.bind(action))
		grid.add_child(btn)
		_bind_buttons[action] = btn

		var pad := Label.new()
		pad.name = "PadBinding_%s" % String(action)
		pad.text = InputActions.describe(action, true)
		pad.custom_minimum_size = Vector2(70, 0)
		pad.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		grid.add_child(pad)

	_controls_status = Label.new()
	_controls_status.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	_controls_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_controls_status)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.custom_minimum_size = Vector2(0, 38)
	reset_btn.theme_type_variation = &"GhostButton"
	reset_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	reset_btn.pressed.connect(_on_reset_bindings)
	root.add_child(reset_btn)

	_refresh_bindings()
	return root


func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	return row


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


# --- Settings bounds (null-safe) --------------------------------------------

func _settings_speed_min() -> float:
	if _has_settings():
		return float(GameSettings.BATTLE_SPEED_MIN)
	return 0.5


func _settings_speed_max() -> float:
	if _has_settings():
		return float(GameSettings.BATTLE_SPEED_MAX)
	return 3.0


# --- Open / close -----------------------------------------------------------

func open() -> void:
	_refresh_from_settings()
	visible = true
	move_to_front()


func close() -> void:
	_cancel_capture()
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func _on_backdrop_input(event: InputEvent) -> void:
	# Click anywhere on the dim area (outside the card) closes the panel.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


# --- Sync: GameSettings -> controls -----------------------------------------

func _refresh_from_settings() -> void:
	if not _has_settings():
		return
	_syncing = true

	if _anim_check:
		_anim_check.button_pressed = bool(GameSettings.animations_enabled)

	if _speed_slider:
		var speed := float(GameSettings.battle_speed)
		_speed_slider.min_value = _settings_speed_min()
		_speed_slider.max_value = _settings_speed_max()
		_speed_slider.value = speed
		_update_speed_label(speed)

	if _focus_option:
		var mode := int(GameSettings.camera_auto_focus)
		var idx := _focus_option.get_item_index(mode)
		if idx >= 0:
			_focus_option.select(idx)

	if "speed_turn_timer_seconds" in GameSettings:
		_update_timer_label(int(GameSettings.speed_turn_timer_seconds))

	if _weather_option and "weather_effects" in GameSettings:
		var widx := _weather_option.get_item_index(int(GameSettings.weather_effects))
		if widx >= 0:
			_weather_option.select(widx)
	if _grid_option and "grid_lines" in GameSettings:
		var gidx := _grid_option.get_item_index(int(GameSettings.grid_lines))
		if gidx >= 0:
			_grid_option.select(gidx)

	if _master_slider and "master_volume" in GameSettings:
		_master_slider.value = float(GameSettings.master_volume)
		_update_volume_label(_master_value_label, _master_slider.value)
	if _music_slider and "music_volume" in GameSettings:
		_music_slider.value = float(GameSettings.music_volume)
		_update_volume_label(_music_value_label, _music_slider.value)
	if _ui_slider and "ui_volume" in GameSettings:
		_ui_slider.value = float(GameSettings.ui_volume)
		_update_volume_label(_ui_value_label, _ui_slider.value)

	_syncing = false


func _on_settings_changed() -> void:
	_refresh_from_settings()


func _update_speed_label(speed: float) -> void:
	if not _speed_value_label:
		return
	var txt: String
	if is_equal_approx(speed * 2.0, roundf(speed * 2.0)):
		# Whole or half steps (0.5, 1.0, 1.5, ...) read best with one decimal.
		txt = "%.1f" % speed
	else:
		# Quarter steps (0.75, 1.25, ...).
		txt = "%.2f" % speed
	_speed_value_label.text = txt + "x"


## Repaint the stepper: the value readout plus the two arrows' disabled state
## (the list does not wrap, so the ends are dead ends and must look it).
func _update_timer_label(seconds: int) -> void:
	if _timer_value_label:
		_timer_value_label.text = "Off" if seconds <= 0 else "%ds" % seconds
	var allowed := _timer_values()
	var idx := allowed.find(seconds)
	if _timer_prev_button:
		_timer_prev_button.disabled = idx <= 0
	if _timer_next_button:
		_timer_next_button.disabled = idx < 0 or idx >= allowed.size() - 1


## The allowed move-clock values, from GameSettings when it is present.
func _timer_values() -> Array[int]:
	if _has_settings():
		var from_settings: Array[int] = GameSettings.SPEED_TIMER_ALLOWED
		if not from_settings.is_empty():
			return from_settings
	return _TIMER_FALLBACK


func _update_volume_label(label: Label, linear: float) -> void:
	if label == null:
		return
	label.text = "%d%%" % int(round(clampf(linear, 0.0, 1.0) * 100.0))


# --- Sync: controls -> GameSettings -----------------------------------------

func _on_anim_toggled(pressed: bool) -> void:
	if _syncing:
		return
	if _has_settings():
		GameSettings.set_animations_enabled(pressed)


func _on_speed_changed(value: float) -> void:
	# Always keep the readout live, even while syncing.
	_update_speed_label(value)
	if _syncing:
		return
	if _has_settings():
		GameSettings.set_battle_speed(value)


func _on_focus_selected(index: int) -> void:
	if _syncing:
		return
	if not _focus_option:
		return
	var mode := _focus_option.get_item_id(index)
	if _has_settings():
		GameSettings.set_camera_auto_focus(mode)


## Step the move clock by [param direction] positions through the allowed list.
## Clamped, never wrapped -- pressing `>` at 30s should do nothing, not silently
## jump the player back to Off.
func _on_timer_step(direction: int) -> void:
	if _syncing:
		return
	var allowed := _timer_values()
	var current: int = allowed[0]
	if _has_settings() and "speed_turn_timer_seconds" in GameSettings:
		current = int(GameSettings.speed_turn_timer_seconds)
	var idx := allowed.find(current)
	if idx < 0:
		idx = 0
	var next_idx: int = clampi(idx + direction, 0, allowed.size() - 1)
	var seconds: int = allowed[next_idx]
	_update_timer_label(seconds)
	if _has_settings() and GameSettings.has_method("set_speed_turn_timer_seconds"):
		GameSettings.set_speed_turn_timer_seconds(seconds)


func _on_weather_selected(index: int) -> void:
	if _syncing or not _weather_option:
		return
	if _has_settings() and GameSettings.has_method("set_weather_effects"):
		GameSettings.set_weather_effects(_weather_option.get_item_id(index))


func _on_grid_selected(index: int) -> void:
	if _syncing or not _grid_option:
		return
	if _has_settings() and GameSettings.has_method("set_grid_lines"):
		GameSettings.set_grid_lines(_grid_option.get_item_id(index))


func _on_master_volume_changed(value: float) -> void:
	_update_volume_label(_master_value_label, value)
	if _syncing:
		return
	if _has_settings() and GameSettings.has_method("set_master_volume"):
		GameSettings.set_master_volume(value)


func _on_music_volume_changed(value: float) -> void:
	_update_volume_label(_music_value_label, value)
	if _syncing:
		return
	if _has_settings() and GameSettings.has_method("set_music_volume"):
		GameSettings.set_music_volume(value)


func _on_ui_volume_changed(value: float) -> void:
	_update_volume_label(_ui_value_label, value)
	if _syncing:
		return
	if _has_settings() and GameSettings.has_method("set_ui_volume"):
		GameSettings.set_ui_volume(value)


# --- Controls: rebinding ------------------------------------------------------

func _refresh_bindings() -> void:
	for action in _bind_buttons.keys():
		var btn: Button = _bind_buttons[action]
		if action == _capturing_action:
			btn.text = "Press a key..."
			continue
		var keys := InputActions.describe_keys(action)
		btn.text = keys if not keys.is_empty() else "(unbound)"


func _begin_capture(action: StringName) -> void:
	_capturing_action = action
	if _controls_status:
		_controls_status.text = "Press a key for %s (Esc to cancel)." % InputActions.label_for(action)
	_refresh_bindings()


func _cancel_capture() -> void:
	if _capturing_action == &"":
		return
	_capturing_action = &""
	if _controls_status:
		_controls_status.text = ""
	_refresh_bindings()


## Capture the next key press for the action being rebound. Runs in _input so the
## key never reaches gameplay handlers (the panel is also an input-blocking overlay).
func _input(event: InputEvent) -> void:
	if _capturing_action == &"" or not visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	get_viewport().set_input_as_handled()
	if k.keycode == KEY_ESCAPE:
		_cancel_capture()
		return
	# A lone modifier is not a binding; wait for the real key (Shift+Tab etc.).
	if k.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return
	var action := _capturing_action
	var code: int = k.get_keycode_with_modifiers()
	var conflict := InputActions.find_conflict(code, action)
	_capturing_action = &""
	if _has_settings() and GameSettings.has_method("set_key_binding"):
		GameSettings.set_key_binding(action, code)
	else:
		InputActions.set_keyboard_bindings(action, [code])
	if _controls_status:
		_controls_status.text = "%s bound to %s." % [InputActions.label_for(action), OS.get_keycode_string(code)]
		if conflict != &"":
			_controls_status.text += " Swapped with %s." % InputActions.label_for(conflict)
	_refresh_bindings()


func _on_reset_bindings() -> void:
	_capturing_action = &""
	if _has_settings() and GameSettings.has_method("reset_key_bindings"):
		GameSettings.reset_key_bindings()
	else:
		InputActions.restore_all_defaults()
	if _controls_status:
		_controls_status.text = "Controls reset to defaults."
	_refresh_bindings()
