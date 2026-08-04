extends CanvasLayer

class_name ReplayHUD

## The REPLAY TRANSPORT BAR: the only piece of UI a replay adds to the battle screen.
##
## A single amber strip along the bottom -- play/pause, speed, step, "Turn 4/12", exit -- and
## a status line above it for the two things playback has to be able to say: "this replay
## diverged" and "here is how the recorded battle ended". Everything else on screen is the
## ordinary battle HUD, because a replay IS the ordinary battle, watched.
##
## INVISIBLE OUTSIDE PLAYBACK. [UILayoutManager] mounts this in every battle, exactly as it
## mounts [NetToast], and it self-hides unless [method ReplayPlayback.is_playing] -- so a
## normal battle pays one hidden CanvasLayer and nothing else. Styling is [ConquestTheme]
## (warm amber plate, cream text) like the toast, so it reads as part of the same HUD.
##
## IT OWNS NO PLAYBACK STATE. Every button forwards to the [ReplayDriver] and every label is
## redrawn from the driver's own read-outs on [signal ReplayDriver.state_changed]. The two
## nodes find each other from either direction (the HUD is built with the battle UI, the
## driver is mounted later by the boot), so whichever lands second completes the binding.

## Group the driver finds this node by.
const GROUP := &"replay_hud"

## Above the network toast (122), below the ultimate cut-in (124) and the turn wipe (128):
## those two are cinematic and are meant to own the screen while they play.
const OVERLAY_LAYER: int = 123

const BAR_HEIGHT: float = 52.0
const BOTTOM_MARGIN: float = 18.0
## The project's touch-target floor.
const BUTTON_SIZE: Vector2 = Vector2(52, 44)

# Godot's default font has no media-control or Geometric Shapes glyphs (probe table
# in tests/unit/test_status_feedback.gd, 2026-08-03) -- ▶ ⏸ ⏭ are all tofu. ASCII
# stand-ins match the pause button's "||" in UILayoutManager; ">" plays, ">|" steps.
const LABEL_PLAY := ">"
const LABEL_PAUSE := "||"
const LABEL_STEP := ">|"
const LABEL_EXIT := "EXIT"

## Slightly translucent plate, like [NetToast]: the bar floats over the board.
const PLATE_BG: Color = Color(0.173, 0.129, 0.078, 0.94)

var _root: Control = null
var _bar: PanelContainer = null
var _status_plate: PanelContainer = null
var _status_label: Label = null
var _play_button: Button = null
var _speed_button: Button = null
var _step_button: Button = null
var _turn_label: Label = null
var _exit_button: Button = null

## The two banner looks, built once. _refresh runs on EVERY applied command, so it must not
## allocate a StyleBox per redraw.
var _box_normal: StyleBoxFlat = null
var _box_alert: StyleBoxFlat = null

var _driver: ReplayDriver = null


func _ready() -> void:
	layer = OVERLAY_LAYER
	add_to_group(GROUP)
	_build_ui()
	# Hidden in every ordinary battle. Read once here AND kept in step by _refresh, so a HUD
	# mounted before the boot has staged playback still lights up when the driver binds.
	_apply_visibility()
	_find_driver()
	_refresh()


# --- Binding ------------------------------------------------------------------

## Take [param driver] as the transport this bar drives. Called by the driver when it mounts
## (and by [method _find_driver] when the driver got there first).
func bind_driver(driver: ReplayDriver) -> void:
	if driver == _driver:
		return
	_unbind_driver()
	_driver = driver
	if _driver == null:
		return
	if not _driver.state_changed.is_connected(_refresh):
		_driver.state_changed.connect(_refresh)
	_apply_visibility()
	_refresh()


func _unbind_driver() -> void:
	if _driver == null or not is_instance_valid(_driver):
		_driver = null
		return
	if _driver.state_changed.is_connected(_refresh):
		_driver.state_changed.disconnect(_refresh)
	_driver = null


func _exit_tree() -> void:
	_unbind_driver()


func _find_driver() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var node: Node = tree.get_first_node_in_group(ReplayDriver.GROUP)
	if node is ReplayDriver:
		bind_driver(node as ReplayDriver)


## True when this bar should be on screen at all.
func is_showing() -> bool:
	return _root != null and _root.visible


func _apply_visibility() -> void:
	if _root != null:
		_root.visible = ReplayPlayback.is_playing()


# --- UI -----------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ReplayRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The bar's own buttons take clicks; everywhere else the board and the camera keep theirs.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var column := VBoxContainer.new()
	column.name = "ReplayColumn"
	column.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	column.offset_bottom = -BOTTOM_MARGIN
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	_box_normal = _plate_box(ConquestTheme.AMBER)
	_box_alert = _plate_box(ConquestTheme.AMBER_DK)

	# Status line (divergence banner / recorded outcome). Hidden while there is nothing to say.
	_status_plate = PanelContainer.new()
	_status_plate.name = "ReplayStatus"
	_status_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status_plate.add_theme_stylebox_override("panel", _box_normal)
	column.add_child(_status_plate)

	_status_label = Label.new()
	_status_label.name = "ReplayStatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_status_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_plate.add_child(_status_label)
	_status_plate.visible = false

	_bar = PanelContainer.new()
	_bar.name = "ReplayBar"
	_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.add_theme_stylebox_override("panel", _box_normal)
	column.add_child(_bar)

	var row := HBoxContainer.new()
	row.name = "ReplayControls"
	row.add_theme_constant_override("separation", 10)
	_bar.add_child(row)

	_play_button = _make_button(LABEL_PAUSE, "Play / pause", _on_play_pressed)
	row.add_child(_play_button)

	_step_button = _make_button(LABEL_STEP, "Step one command (while paused)", _on_step_pressed)
	row.add_child(_step_button)

	_speed_button = _make_button("x1", "Playback speed", _on_speed_pressed)
	row.add_child(_speed_button)

	_turn_label = Label.new()
	_turn_label.name = "ReplayTurnLabel"
	_turn_label.text = "Turn 0/0"
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_label.custom_minimum_size = Vector2(112, 0)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", 18)
	_turn_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_turn_label)

	_exit_button = _make_button(LABEL_EXIT, "Leave the replay", _on_exit_pressed)
	_exit_button.custom_minimum_size = Vector2(80, BUTTON_SIZE.y)
	row.add_child(_exit_button)


func _make_button(text: String, tooltip: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = BUTTON_SIZE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", ConquestTheme.CREAM)
	button.add_theme_color_override("font_hover_color", ConquestTheme.AMBER_LITE)
	button.pressed.connect(handler)
	return button


func _plate_box(border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PLATE_BG
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.border_color = border
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	box.shadow_size = 6
	return box


# --- Handlers -----------------------------------------------------------------

func _on_play_pressed() -> void:
	if _driver != null and is_instance_valid(_driver):
		_driver.toggle_play()


func _on_step_pressed() -> void:
	if _driver != null and is_instance_valid(_driver):
		_driver.step()


func _on_speed_pressed() -> void:
	if _driver != null and is_instance_valid(_driver):
		_driver.cycle_speed()


## Leaving is a plain exit to the main menu (see [method ReplayPlayback.quit_to_menu]); the
## driver's teardown is what disarms spectator mode and switches recording back on.
func _on_exit_pressed() -> void:
	ReplayPlayback.quit_to_menu()


# --- Redraw -------------------------------------------------------------------

func _refresh() -> void:
	_apply_visibility()
	if _driver == null or not is_instance_valid(_driver):
		return
	if _play_button != null:
		_play_button.text = LABEL_PAUSE if _driver.state == ReplayDriver.State.PLAYING else LABEL_PLAY
		# A stopped replay (diverged / finished) has nothing left to play or step.
		var running: bool = _driver.state == ReplayDriver.State.PLAYING \
			or _driver.state == ReplayDriver.State.PAUSED
		_play_button.disabled = not running
	if _step_button != null:
		_step_button.disabled = _driver.state != ReplayDriver.State.PAUSED
	if _speed_button != null:
		_speed_button.text = "x%d" % int(_driver.speed())
	if _turn_label != null:
		_turn_label.text = _driver.turn_label()
	_refresh_status()


func _refresh_status() -> void:
	if _status_plate == null or _status_label == null:
		return
	var text: String = _driver.status_text() if _driver != null and is_instance_valid(_driver) else ""
	# "Paused" is transport chrome, not news -- the play button already says it. The banner is
	# reserved for the two things the player MUST see.
	var newsworthy: bool = _driver != null and is_instance_valid(_driver) \
		and (_driver.is_diverged() or _driver.is_finished())
	_status_plate.visible = newsworthy and not text.is_empty()
	_status_label.text = text
	var alert: bool = _driver != null and is_instance_valid(_driver) and _driver.is_diverged()
	_status_plate.add_theme_stylebox_override("panel", _box_alert if alert else _box_normal)
	_status_label.add_theme_color_override("font_color",
		ConquestTheme.AMBER_LITE if alert else ConquestTheme.CREAM)


## The line currently on the banner ("" when it is hidden) -- the readable state, for tests.
func status_text() -> String:
	if _status_plate == null or not _status_plate.visible or _status_label == null:
		return ""
	return _status_label.text


## The turn counter's text, for tests.
func turn_text() -> String:
	return _turn_label.text if _turn_label != null else ""
