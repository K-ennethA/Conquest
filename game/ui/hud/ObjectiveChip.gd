extends PanelContainer
class_name ObjectiveChip

## Small persistent HUD chip: the map's objective in a few words ("Rout the enemy",
## "Survive 3/8 turns", "Seize the throne", see [ObjectiveText]) plus a "Danger zone"
## tag while that overlay is on.
##
## Two presentations (see [method set_inline]): INLINE -- frameless, riding in the
## phase banner's info row (the traditional-turn HUD, so the top HUD stays one strip)
## -- or STANDALONE -- its own small notched plate under the Speed-First turn queue.
##
## Reads the compiled rules from the GameWorldManager (group "game_world_manager").
## Refreshed on turn starts / board rebuilds / danger-zone toggles, with a slow poll
## as a safety net (the rules appear only once the map finishes loading).

var _label: Label
var _danger: Label
var _danger_chip: Control
var _poll: Timer
var _danger_on: bool = false
var _tag: Label
var _inline: bool = false


func _ready() -> void:
	name = "ObjectiveChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Matches the phase chip above it: a slim navy strip with a gold diamond, cream
	# objective text, and a violet "Danger zone" tag while that overlay is on.
	ConquestTheme.keep_style(self)
	_apply_frame()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var icon := Label.new()
	icon.text = "◆"
	icon.add_theme_color_override("font_color", ConquestTheme.GOLD)
	icon.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var tag := Label.new()
	tag.text = "OBJECTIVE"
	tag.theme_type_variation = &"SectionLabel"
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.visible = not _inline
	row.add_child(tag)
	_tag = tag

	_label = Label.new()
	_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)

	var danger_col := Color(0.72, 0.5, 1.0)
	var danger_chip := ConquestTheme.chip("Danger zone", danger_col, ConquestTheme.FS_CAPTION)
	danger_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	danger_chip.visible = false
	row.add_child(danger_chip)
	_danger = danger_chip.get_node("Text") as Label
	_danger_chip = danger_chip

	if GameEvents:
		GameEvents.danger_zone_changed.connect(_on_danger_zone_changed)
		GameEvents.unit_moved.connect(func(_u, _a, _b): refresh())
	var services := get_node_or_null("/root/CombatServices")
	if services != null and services.has_signal("board_ready"):
		services.board_ready.connect(refresh)
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(func(ts):
			if ts != null and not ts.turn_started.is_connected(_on_turn_started):
				ts.turn_started.connect(_on_turn_started)
			refresh())
		if TurnSystemManager.has_active_turn_system():
			var ts = TurnSystemManager.get_active_turn_system()
			if not ts.turn_started.is_connected(_on_turn_started):
				ts.turn_started.connect(_on_turn_started)

	_poll = Timer.new()
	_poll.wait_time = 1.0
	_poll.autostart = true
	_poll.timeout.connect(refresh)
	add_child(_poll)
	refresh()


## INLINE (true): frameless, for the phase banner's info row -- the "OBJECTIVE" tag
## is dropped (the gold diamond marks it). STANDALONE (false): its own notched plate.
func set_inline(on: bool) -> void:
	_inline = on
	if _tag != null:
		_tag.visible = not on
	_apply_frame()


func is_inline() -> bool:
	return _inline


func _apply_frame() -> void:
	if _inline:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 2
		add_theme_stylebox_override("panel", e)
	else:
		var sb := ConquestTheme.chip_box(ConquestTheme.BORDER_SOFT, 0.9)
		sb.content_margin_top = 3
		sb.content_margin_bottom = 4
		add_theme_stylebox_override("panel", sb)


func _on_turn_started(_p) -> void:
	refresh()


func _on_danger_zone_changed(active: bool, _count: int) -> void:
	_danger_on = active
	refresh()


func refresh() -> void:
	var gwm := get_tree().get_first_node_in_group("game_world_manager") if is_inside_tree() else null
	var text := ""
	if gwm != null and gwm.has_method("get_game_mode_rules"):
		text = ObjectiveText.chip_text(gwm.get_game_mode_rules(), gwm.get_objective_rounds_done())
	_label.text = text
	_danger_chip.visible = _danger_on
	visible = text != "" or _danger_on
