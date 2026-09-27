extends PanelContainer
class_name WeatherChip

## HUD chip under the objective chip: the battle weather's icon + name and, when
## it is scheduled / dynamic / summoned, "changes in N" (or "N rounds left"). The
## tooltip carries the weather's rules text. Announces every weather change on the
## [ActionAnnouncer] banner. Hidden on a permanently Clear battle.
##
## Reads [Weather] / [signal CombatServices.weather_changed]; refreshes on turn
## starts for the countdown. Styling via the shared [ConquestTheme] chip helpers.

var _icon: WeatherIcon
var _name: Label
var _sub: Label


func _ready() -> void:
	name = "WeatherChip"
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ConquestTheme.keep_style(self)
	var sb := ConquestTheme.chip_box(ConquestTheme.BORDER_SOFT, 0.9)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = WeatherIcon.new(&"clear", ConquestTheme.CREAM, 20.0)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_name)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
	_sub.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_sub)

	var services := get_node_or_null("/root/CombatServices")
	if services != null and services.has_signal("weather_changed"):
		services.weather_changed.connect(_on_weather_changed)
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
	refresh()


func _on_turn_started(_p) -> void:
	refresh()


func _on_weather_changed(now, previous) -> void:
	refresh()
	if now == null or previous == null or not is_inside_tree():
		return
	var ann := get_tree().get_first_node_in_group("action_announcer")
	if ann != null and ann.has_method("announce"):
		ann.announce(change_text(now), now.description, now.color)


## Banner line for a change to [param w] ("Rain begins to fall!").
static func change_text(w) -> String:
	match StringName(w.id):
		&"clear":
			return "The skies clear."
		&"rain":
			return "Rain begins to fall!"
		&"bright_sun":
			return "The sun blazes down!"
		&"desert_storm":
			return "A desert storm rolls in!"
		&"overbloom":
			return "The wilds burst into Overbloom!"
	return "The weather turns: %s!" % w.display_name


## Countdown text for the chip ("" when the weather is permanent).
static func countdown_text(state) -> String:
	if state == null:
		return ""
	var left: int = state.override_rounds_left()
	if left > 0:
		return "%d round%s left" % [left, "" if left == 1 else "s"]
	var n: int = state.rounds_until_change()
	if n <= 0:
		return ""
	return "changes next round" if n == 1 else "changes in %d rounds" % n


func refresh() -> void:
	var state := Weather.state()
	var w := Weather.current()
	var countdown := countdown_text(state)
	visible = not (w.id == Weather.CLEAR and countdown == "")
	_icon.kind = w.fx_kind
	_icon.color = w.color
	_name.text = w.display_name
	_name.add_theme_color_override("font_color", w.color.lightened(0.35))
	_sub.text = countdown
	_sub.visible = countdown != ""
	# The Compendium's wording: description + every rule derived from the data.
	tooltip_text = CompendiumData.weather_tooltip(w)
