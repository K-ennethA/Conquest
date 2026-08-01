extends Control

class_name MultiplayerModeSelection

## Multiplayer mode picker, reached from MainMenu's "Versus" button. Offers Local
## (hot-seat) and Network (online) as large mode cards -- the same card pattern as
## [SoloModeSelect] -- then hands off to the matching setup screen. Dark "Legends"
## menu look via [MenuTheme].
##
## Keyboard: 1 = Local, 2 = Network, ESC = back.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"
const NETWORK_SETUP_SCENE := "res://menus/NetworkMultiplayerSetup.tscn"


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_build_ui()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(700.0, 0.0)
	page.add_theme_constant_override("separation", 16)
	center.add_child(page)

	var title := Label.new()
	title.text = "VERSUS"
	page.add_child(title)
	MenuTheme.style_title(title, 40)

	var subtitle := Label.new()
	subtitle.text = "Choose how you want to face an opponent"
	page.add_child(subtitle)
	MenuTheme.style_subtitle(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 20.0)
	page.add_child(spacer)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 20)
	page.add_child(cards)

	cards.add_child(_make_mode_card(
		"1.  Local",
		"Hot-seat on the same device --\nplayers take turns sharing a screen.",
		_on_local_multiplayer_pressed))
	cards.add_child(_make_mode_card(
		"2.  Network",
		"Play online over the internet\nor a local network.",
		_on_network_multiplayer_pressed))

	var footspace := Control.new()
	footspace.custom_minimum_size = Vector2(0.0, 10.0)
	page.add_child(footspace)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 48.0)
	back.pressed.connect(_on_back_pressed)
	page.add_child(back)

	var hint := Label.new()
	hint.text = "1 Local  •  2 Network  •  ESC back"
	page.add_child(hint)
	MenuTheme.style_caption(hint)


## A tall, clickable mode card: a big gold heading over a dim description line
## (same shape as [method SoloModeSelect._make_mode_card]).
func _make_mode_card(heading: String, blurb: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(300.0, 200.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)

	var head := Label.new()
	head.text = heading
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", MenuTheme.GOLD)
	col.add_child(head)

	var desc := Label.new()
	desc.text = blurb
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(desc)

	btn.add_child(col)
	return btn


func _on_local_multiplayer_pressed() -> void:
	"""Handle Local Multiplayer card press."""
	GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	GameSettings.set_player_count(2)  # Default to 2 players for local

	# Go to the unified Match Setup (local hot-seat variant: map + turn system).
	MatchSetup.requested_mode = MatchConfigPanel.MODE_LOCAL
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


func _on_network_multiplayer_pressed() -> void:
	"""Handle Network Multiplayer card press."""
	get_tree().change_scene_to_file(NETWORK_SETUP_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				_on_local_multiplayer_pressed()
			KEY_2:
				_on_network_multiplayer_pressed()
			KEY_ESCAPE:
				_on_back_pressed()
