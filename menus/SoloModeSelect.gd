extends Control

class_name SoloModeSelect

## Solo mode picker, reached from MainMenu's "Solo" button. Offers the two single-player
## registers as large mode cards -- Skirmish (pick a map, fight the AI) and Arena Run
## (draft augments across a gauntlet) -- then hands off to the unified [b]MatchSetup[/b]
## screen in the matching variant. Dark "Legends" menu look via [MenuTheme].
##
## Keyboard: 1 = Skirmish, 2 = Arena Run, ESC = back to the main menu.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_build_ui()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(720.0, 0.0)
	page.add_theme_constant_override("separation", 16)
	center.add_child(page)

	var title := Label.new()
	title.text = "SOLO"
	page.add_child(title)
	MenuTheme.style_title(title, 40)

	var subtitle := Label.new()
	subtitle.text = "Choose how you want to play"
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
		"1.  Skirmish",
		"Pick a map, choose your squad,\ndefeat the AI.",
		MatchConfigPanel.MODE_SKIRMISH))
	cards.add_child(_make_mode_card(
		"2.  Arena Run",
		"Draft augments between rounds.\nSurvive the gauntlet.",
		MatchConfigPanel.MODE_ARENA))

	var footspace := Control.new()
	footspace.custom_minimum_size = Vector2(0.0, 20.0)
	page.add_child(footspace)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 44.0)
	back.pressed.connect(_on_back_pressed)
	page.add_child(back)

	var hint := Label.new()
	hint.text = "1 Skirmish  •  2 Arena Run  •  ESC back"
	page.add_child(hint)
	MenuTheme.style_caption(hint)


## A tall, clickable mode card: a big gold heading over a dim description line.
func _make_mode_card(heading: String, blurb: String, mode: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(320.0, 180.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_mode_chosen.bind(mode))

	# Stacked labels laid over the button; mouse_filter IGNORE so clicks reach the button.
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


func _on_mode_chosen(mode: String) -> void:
	MatchSetup.requested_mode = mode
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				_on_mode_chosen(MatchConfigPanel.MODE_SKIRMISH)
			KEY_2:
				_on_mode_chosen(MatchConfigPanel.MODE_ARENA)
			KEY_ESCAPE:
				_on_back_pressed()
