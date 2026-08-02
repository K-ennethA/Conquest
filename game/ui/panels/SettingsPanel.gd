extends Control

class_name SettingsPanel

# Fire-Emblem / Pokemon-style OPTIONS overlay. THE one settings surface: the
# battle HUD mounts it behind its top-right gear (see
# game/ui/layout/UILayoutManager.gd), and MainMenu mounts the same class behind
# its own gear so the menu and the battle expose an identical panel rather than
# two drifting copies.
#
# Pure front-end for the presentation settings that already live in the
# `GameSettings` autoload: it reads current values when opened, writes through
# the `set_*` helpers on change, and re-syncs when `settings_changed` fires from
# anywhere else. All GameSettings access is guarded so the panel is safe in a
# headless / minimal scene where the autoload might be absent or default.
#
# Audio is the same deal one layer on: the three sliders write
# GameSettings.master/music/ui_volume (LINEAR 0..1), GameSettings persists them
# and emits, and AudioManager re-levels itself off that signal -- this panel never
# touches AudioManager or an audio bus directly.
#
# Built entirely in code (no .tscn) so it can be instantiated and mounted by the
# HUD without fragile node paths, and so the whole layout lives in one place.

# --- Speed presets shown in the slider label / snapping ---------------------
const _SPEED_STEP := 0.25

# Volume sliders run 0..1 (the unit GameSettings stores) in 5% detents and are
# shown as a percentage.
const _VOLUME_STEP := 0.05

# Vertical rhythm. The card carries four sections now, so the gap is tight
# enough that the whole thing still fits a 720-tall viewport without scrolling
# (~600px tall at these numbers -- raising it costs ~19px per point).
const _ROW_SEPARATION := 10

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
var _master_slider: HSlider = null
var _master_value_label: Label = null
var _music_slider: HSlider = null
var _music_value_label: Label = null
var _ui_slider: HSlider = null
var _ui_value_label: Label = null

# True while we are pushing GameSettings values INTO the controls, so the
# controls' change signals don't bounce back out into the setters (feedback loop).
var _syncing: bool = false


func _ready() -> void:
	# Cover the whole screen and swallow input so board clicks don't fall through
	# while the panel is open.
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	_build_ui()

	# Match the amber HUD look (self-themes; also inherits the parent theme).
	ConquestTheme.apply_to(self)

	# Stay in sync with external changes (other systems / a second panel).
	if _has_settings() and not GameSettings.settings_changed.is_connected(_on_settings_changed):
		GameSettings.settings_changed.connect(_on_settings_changed)

	_refresh_from_settings()


func _exit_tree() -> void:
	if _has_settings() and GameSettings.settings_changed.is_connected(_on_settings_changed):
		GameSettings.settings_changed.disconnect(_on_settings_changed)


func _has_settings() -> bool:
	return typeof(GameSettings) == TYPE_OBJECT


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	# Dim backdrop behind the card; absorbs clicks (and closes on click-away).
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.55)
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
	_frame.custom_minimum_size = Vector2(380, 0)
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_frame.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _ROW_SEPARATION)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	vbox.add_child(_make_separator())

	# --- Animations toggle ---
	var anim_row := _make_row("Animations")
	_anim_check = CheckButton.new()
	_anim_check.mouse_filter = Control.MOUSE_FILTER_STOP
	_anim_check.toggled.connect(_on_anim_toggled)
	anim_row.add_child(_anim_check)
	vbox.add_child(anim_row)

	# --- Battle speed slider (0.5x - 3.0x, step 0.25) ---
	var speed_header := _make_row("Battle Speed")
	_speed_value_label = Label.new()
	_speed_value_label.text = "1.0x"
	_speed_value_label.custom_minimum_size = Vector2(52, 0)
	_speed_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_value_label.add_theme_font_size_override("font_size", 16)
	speed_header.add_child(_speed_value_label)
	vbox.add_child(speed_header)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = _settings_speed_min()
	_speed_slider.max_value = _settings_speed_max()
	_speed_slider.step = _SPEED_STEP
	_speed_slider.value = 1.0
	_speed_slider.custom_minimum_size = Vector2(0, 24)
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_speed_slider.value_changed.connect(_on_speed_changed)
	vbox.add_child(_speed_slider)

	vbox.add_child(_make_separator())

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
	vbox.add_child(focus_row)

	# --- Speed First move clock ---
	# A stepper, not a slider: the allowed values are a fixed short list
	# (GameSettings.SPEED_TIMER_ALLOWED = Off/15/20/30), so stepping through them
	# by index cannot land on an unrepresentable value the way dragging would.
	vbox.add_child(_build_timer_row())

	vbox.add_child(_make_separator())

	# --- Audio ---
	vbox.add_child(_make_section_label("AUDIO"))
	_master_value_label = Label.new()
	_master_slider = _build_volume_control(vbox, "Master", _master_value_label, _on_master_volume_changed)
	_music_value_label = Label.new()
	_music_slider = _build_volume_control(vbox, "Music", _music_value_label, _on_music_volume_changed)
	_ui_value_label = Label.new()
	_ui_slider = _build_volume_control(vbox, "Interface", _ui_value_label, _on_ui_volume_changed)

	vbox.add_child(_make_separator())

	# --- Close ---
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 34)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


## The Speed-First move-clock stepper: `< value >` over the fixed allowed list.
## Both arrows are >= 40px wide so the control stays touch-usable on a phone.
func _build_timer_row() -> HBoxContainer:
	var row := _make_row("Speed Timer")

	_timer_prev_button = Button.new()
	_timer_prev_button.name = "TimerPrev"
	_timer_prev_button.text = "<"
	_timer_prev_button.custom_minimum_size = Vector2(40, 32)
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
	_timer_value_label.add_theme_font_size_override("font_size", 16)
	row.add_child(_timer_value_label)

	_timer_next_button = Button.new()
	_timer_next_button.name = "TimerNext"
	_timer_next_button.text = ">"
	_timer_next_button.custom_minimum_size = Vector2(40, 32)
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
	value_label.add_theme_font_size_override("font_size", 16)
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


## A small caption that opens a group of related rows ("AUDIO").
func _make_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 16)
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

	_update_timer_label(int(GameSettings.speed_turn_timer_seconds))

	if _master_slider:
		_master_slider.value = float(GameSettings.master_volume)
		_update_volume_label(_master_value_label, _master_slider.value)
	if _music_slider:
		_music_slider.value = float(GameSettings.music_volume)
		_update_volume_label(_music_value_label, _music_slider.value)
	if _ui_slider:
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
	var current: int = int(GameSettings.speed_turn_timer_seconds) if _has_settings() else allowed[0]
	var idx := allowed.find(current)
	if idx < 0:
		idx = 0
	var next_idx: int = clampi(idx + direction, 0, allowed.size() - 1)
	var seconds: int = allowed[next_idx]
	_update_timer_label(seconds)
	if _has_settings():
		GameSettings.set_speed_turn_timer_seconds(seconds)


func _on_master_volume_changed(value: float) -> void:
	_update_volume_label(_master_value_label, value)
	if _syncing:
		return
	if _has_settings():
		GameSettings.set_master_volume(value)


func _on_music_volume_changed(value: float) -> void:
	_update_volume_label(_music_value_label, value)
	if _syncing:
		return
	if _has_settings():
		GameSettings.set_music_volume(value)


func _on_ui_volume_changed(value: float) -> void:
	_update_volume_label(_ui_value_label, value)
	if _syncing:
		return
	if _has_settings():
		GameSettings.set_ui_volume(value)
