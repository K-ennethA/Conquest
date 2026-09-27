extends Control

class_name MainMenu

## Title screen. A slowly turning 3D diorama of one of the game's maps sits behind
## a left-hand command list (Single Player / Versus / Arena / Compendium /
## Settings / Quit); the focused command's one-line description shows under the
## list. Mouse hover and keyboard / gamepad focus are one highlight (MenuNav).
##
## Built in code (the .tscn is only the root). Number keys 1-6 remain as quiet
## shortcuts and are shown as small numerals beside each command. Esc / B moves the
## cursor to Quit rather than quitting outright.

const DIORAMA_MAPS: Array[String] = [
	"res://game/maps/resources/elemental_crossroads.tres",
	"res://game/maps/resources/forgotten_forest.tres",
	"res://game/maps/resources/skirmish_arena.tres",
]

const ENTRIES := [
	{"id": "single", "text": "Single Player",
		"desc": "Lead your squad against the AI. Pick a turn system, a battlefield and your units."},
	{"id": "versus", "text": "Versus",
		"desc": "Two commanders, one battlefield. Play hot-seat on this device, or connect over the network."},
	{"id": "arena", "text": "Arena",
		"desc": "A run of escalating battles against AI waves, drafting upgrades for your squad between rounds."},
	{"id": "compendium", "text": "Compendium",
		"desc": "Browse every unit, tile, map and status effect -- and build your own battlefields in the Map Maker."},
	{"id": "settings", "text": "Settings",
		"desc": "Animations, battle speed, camera focus and keyboard controls."},
	{"id": "quit", "text": "Quit",
		"desc": "Close Conquest and return to the desktop."},
]

var single_player_button: Button
var versus_button: Button
var compendium_button: Button
var arena_button: Button
var settings_button: Button
var quit_button: Button

var _buttons: Array[Button] = []
var _desc_label: Label
var _status_panel: PanelContainer
var _status_label: Label
var _settings_panel: SettingsPanel
var _diorama: MapPreview3D


func _ready() -> void:
	theme = MenuTheme.build()

	# Arriving at the main menu always ends any network match: close the session
	# and restore local play, so single-player / hotseat afterwards starts clean.
	var net_msg: String = ""
	if GameModeManager:
		GameModeManager.end_network_session()
		net_msg = GameModeManager.consume_menu_message()

	_build_ui()
	if net_msg != "":
		_show_status_message(net_msg)
	MenuNav.focus_deferred(single_player_button)


# --- Layout ---------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ground := ColorRect.new()
	ground.name = "Ground"
	ground.color = MenuTheme.BG_DEEP
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	var bd := MenuBackdrop.new()
	bd.name = "Backdrop"
	bd.motes = false
	bd.flourishes = false
	bd.vignette_strength = 0.0
	add_child(bd)

	_build_diorama()

	# Left-to-right scrim so the command list always reads over the diorama.
	var scrim := TextureRect.new()
	scrim.name = "Scrim"
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.38, 0.72, 1.0])
	g.colors = PackedColorArray([
		Color(MenuTheme.BG_DEEP, 0.96), Color(MenuTheme.BG_DEEP, 0.82),
		Color(MenuTheme.BG_DEEP, 0.15), Color(MenuTheme.BG_DEEP, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	scrim.texture = gt
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var atmosphere := MenuBackdrop.new()
	atmosphere.name = "Atmosphere"
	atmosphere.solid = false
	atmosphere.vignette_strength = 0.75
	add_child(atmosphere)

	var margin := MarginContainer.new()
	margin.name = "Page"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", MenuTheme.SP_PAGE)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)

	var title := MenuKit.label("CONQUEST", &"DisplayLabel")
	title.name = "Title"
	col.add_child(title)

	var rule_row := HBoxContainer.new()
	rule_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.add_child(rule_row)
	var rule := GroveRule.new()
	rule.color = MenuTheme.GOLD
	rule.custom_minimum_size = Vector2(96, 12)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule_row.add_child(rule)
	var tagline := MenuKit.label("TURN-BASED GRID TACTICS", &"SectionLabel")
	tagline.name = "Subtitle"
	tagline.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	tagline.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	rule_row.add_child(tagline)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap)

	var list := VBoxContainer.new()
	list.name = "MenuButtons"
	list.custom_minimum_size = Vector2(430, 0)
	list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	list.add_theme_constant_override("separation", 4)
	col.add_child(list)

	for i in ENTRIES.size():
		var entry: Dictionary = ENTRIES[i]
		if entry["id"] == "quit":
			var sep := Control.new()
			sep.custom_minimum_size = Vector2(0, 10)
			list.add_child(sep)
		var b := _make_entry(entry, i + 1)
		list.add_child(b)
		_buttons.append(b)

	single_player_button = _buttons[0]
	versus_button = _buttons[1]
	arena_button = _buttons[2]
	compendium_button = _buttons[3]
	settings_button = _buttons[4]
	quit_button = _buttons[5]
	single_player_button.pressed.connect(_on_single_player_pressed)
	versus_button.pressed.connect(_on_versus_pressed)
	arena_button.pressed.connect(_on_arena_pressed)
	compendium_button.pressed.connect(_on_compendium_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	# Wrap vertical focus so Up on the first entry reaches Quit and back.
	_buttons[0].focus_neighbor_top = _buttons[0].get_path_to(_buttons[-1])
	_buttons[-1].focus_neighbor_bottom = _buttons[-1].get_path_to(_buttons[0])

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap2)

	_desc_label = MenuKit.label("", &"DimLabel", true)
	_desc_label.name = "Description"
	_desc_label.custom_minimum_size = Vector2(430, 56)
	_desc_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_desc_label)

	# Network / session messages (e.g. "The opponent disconnected").
	_status_panel = MenuKit.card()
	_status_panel.name = "StatusPanel"
	_status_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_status_panel.custom_minimum_size = Vector2(430, 0)
	var status_sb := MenuTheme.accented_card(MenuTheme.ACCENT, SIDE_LEFT, MenuTheme.PANEL, 0.94)
	status_sb.content_margin_top = 12
	status_sb.content_margin_bottom = 12
	_status_panel.add_theme_stylebox_override("panel", status_sb)
	_status_panel.visible = false
	col.add_child(_status_panel)
	_status_label = MenuKit.label("", &"", true)
	_status_label.name = "StatusLabel"
	_status_panel.add_child(_status_label)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", MenuTheme.SP_XL)
	col.add_child(footer)
	footer.add_child(MenuKit.key_hint("Up/Down", "D-Pad", "Choose"))
	MenuKit.add_standard_hints(footer, "Select", "Quit")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var ver := String(ProjectSettings.get_setting("application/config/version", ""))
	var version := MenuKit.label(("v" + ver) if ver != "" else "Development build", &"MutedLabel")
	version.name = "Version"
	footer.add_child(version)


func _make_entry(entry: Dictionary, number: int) -> Button:
	var b := Button.new()
	b.name = String(entry["id"]).capitalize().replace(" ", "") + "Button"
	b.text = entry["text"]
	b.theme_type_variation = &"MenuItem"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 50)
	b.focus_mode = Control.FOCUS_ALL
	MenuNav.hover_focus(b)
	b.focus_entered.connect(_on_entry_focused.bind(entry))

	# Quiet number-key shortcut at the right edge.
	var num := MenuKit.label(str(number), &"MutedLabel")
	num.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	num.offset_left = -34
	num.offset_right = -14
	num.offset_top = -12
	num.offset_bottom = 12
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(num)
	return b


func _build_diorama() -> void:
	var path := ""
	for p in DIORAMA_MAPS:
		if ResourceLoader.exists(p):
			path = p
			break
	if path == "":
		return
	var res := load(path) as MapResource
	if res == null:
		return
	_diorama = MapPreview3D.new()
	_diorama.name = "Diorama"
	_diorama.framing = MapPreview3D.Framing.DIORAMA
	_diorama.transparent = true
	_diorama.show_spawns = false
	_diorama.turntable_speed = 0.05
	_diorama.lens_shift = -0.32
	_diorama.zoom_out = 1.15
	_diorama.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_diorama)
	_diorama.show_map(res)
	_diorama.map_root.rotation.y = 0.5


func _on_entry_focused(entry: Dictionary) -> void:
	if _desc_label != null:
		_desc_label.text = entry["desc"]


func _show_status_message(message: String) -> void:
	"""Show a status message (e.g. why a network match ended) under the menu."""
	if _status_label == null:
		return
	_status_label.text = message
	_status_panel.visible = true


# --- Actions ------------------------------------------------------------------------

func _on_single_player_pressed() -> void:
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_player_count(1)  # Single player vs AI
	MenuNav.change_scene(self, "res://menus/TurnSystemSelection.tscn")


func _on_versus_pressed() -> void:
	MenuNav.change_scene(self, "res://menus/MultiplayerModeSelection.tscn")


func _on_compendium_pressed() -> void:
	MenuNav.change_scene(self, "res://menus/Compendium.tscn")


func _on_arena_pressed() -> void:
	# The setup screen picks run length + turn system before ArenaController starts
	# the run (it, not this menu, launches the actual GameWorld round).
	MenuNav.change_scene(self, "res://game/arena/ui/ArenaSetupScreen.tscn")


func _on_settings_pressed() -> void:
	if _settings_panel == null:
		# Hosted on its own CanvasLayer; the panel themes itself with the shared
		# navy + gold tokens, so it looks the same here as in battle.
		var layer := CanvasLayer.new()
		layer.name = "SettingsLayer"
		layer.layer = 10
		add_child(layer)
		_settings_panel = SettingsPanel.new()
		_settings_panel.name = "SettingsPanel"
		layer.add_child(_settings_panel)
		_settings_panel.visibility_changed.connect(_on_settings_visibility_changed)
	_settings_panel.open()


func _on_settings_visibility_changed() -> void:
	var open := _settings_panel != null and _settings_panel.visible
	# Keep keyboard / pad focus inside the panel while it is open.
	for b in _buttons:
		b.focus_mode = Control.FOCUS_NONE if open else Control.FOCUS_ALL
	if open:
		var first := _first_focusable(_settings_panel)
		if first != null:
			first.call_deferred(&"grab_focus")
	else:
		MenuNav.focus_deferred(settings_button)


func _first_focusable(node: Node) -> Control:
	for c in node.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL \
				and (c as Control).is_visible_in_tree() and not (c is TabBar):
			return c
		var deeper := _first_focusable(c)
		if deeper != null:
			return deeper
	return null


func _settings_open() -> bool:
	return _settings_panel != null and _settings_panel.visible


func _on_quit_pressed() -> void:
	get_tree().quit()


# --- Input --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		if _settings_open():
			_settings_panel.close()
		elif quit_button != null and not quit_button.has_focus():
			quit_button.grab_focus()
		return
	if _settings_open() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var idx: int = (event as InputEventKey).keycode - KEY_1
	if idx >= 0 and idx < _buttons.size():
		get_viewport().set_input_as_handled()
		_buttons[idx].grab_focus()
		_buttons[idx].pressed.emit()
