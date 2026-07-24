extends Control

class_name SettingsPanel

# Fire-Emblem / Pokemon-style in-game OPTIONS overlay.
#
# Pure front-end for the presentation settings that already live in the
# `GameSettings` autoload: it reads current values when opened, writes through
# the `set_*` helpers on change, and re-syncs when `settings_changed` fires from
# anywhere else. All GameSettings access is guarded so the panel is safe in a
# headless / minimal scene where the autoload might be absent or default.
#
# Built entirely in code (no .tscn) so it can be instantiated and mounted by the
# HUD without fragile node paths, and so the whole layout lives in one place.

# --- Speed presets shown in the slider label / snapping ---------------------
const _SPEED_STEP := 0.25

# Controls (created in _build_ui)
var _backdrop: ColorRect = null
var _frame: PanelContainer = null
var _anim_check: CheckButton = null
var _speed_slider: HSlider = null
var _speed_value_label: Label = null
var _focus_option: OptionButton = null

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
	vbox.add_theme_constant_override("separation", 14)
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

	vbox.add_child(_make_separator())

	# --- Close ---
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 34)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


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
