extends Control

class_name SoloModeSelect

## Solo mode picker, reached from MainMenu's "Solo" button. Offers the single-player
## registers as large mode cards -- Campaign (story battles, not yet built), Skirmish
## (pick a map, fight the AI) and Arena Run (draft augments across a gauntlet) -- then
## hands off to the unified [b]MatchSetup[/b] screen in the matching variant. Dark
## "Legends" menu look via [MenuTheme].
##
## Campaign has no content yet, so it renders as a styled COMING-SOON card: same size
## and shape as the live cards but dimmed, disabled (no click / press affordance) and
## tooltipped "In development". Choosing it by keyboard flashes a brief caption instead
## of navigating.
##
## Keyboard: 1 = Campaign (coming-soon flash), 2 = Skirmish, 3 = Arena Run, ESC = back.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"
const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"

## Message flashed when the not-yet-built Campaign card is chosen.
const COMING_SOON_TEXT := "Campaign is still in development -- coming soon."

var _status_label: Label = null


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_build_ui()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(1180.0, 0.0)
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

	cards.add_child(_make_coming_soon_card(
		"1.  Campaign",
		"Story battles across the\nForgotten Forest -- coming soon."))
	cards.add_child(_make_mode_card(
		"2.  Skirmish",
		"Pick a map, choose your squad,\ndefeat the AI.",
		MatchConfigPanel.MODE_SKIRMISH))
	cards.add_child(_make_mode_card(
		"3.  Arena Run",
		"Draft augments between rounds.\nSurvive the gauntlet.",
		MatchConfigPanel.MODE_ARENA))
	cards.add_child(_make_action_card(
		"4.  Challenges",
		"Beat maps other players built --\nor share your own gauntlet.",
		_on_challenges_chosen))

	# Flashes the coming-soon caption; empty and reserved (fixed height) so the layout
	# never jumps when the message appears.
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.custom_minimum_size = Vector2(0.0, 22.0)
	page.add_child(_status_label)
	MenuTheme.style_caption(_status_label)
	_status_label.add_theme_color_override("font_color", MenuTheme.GOLD)
	_status_label.modulate = Color(1, 1, 1, 0)

	var footspace := Control.new()
	footspace.custom_minimum_size = Vector2(0.0, 10.0)
	page.add_child(footspace)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 44.0)
	back.pressed.connect(_on_back_pressed)
	page.add_child(back)

	var hint := Label.new()
	hint.text = "1 Campaign  •  2 Skirmish  •  3 Arena Run  •  4 Challenges  •  ESC back"
	page.add_child(hint)
	MenuTheme.style_caption(hint)


## A tall, clickable mode card: a big gold heading over a dim description line.
func _make_mode_card(heading: String, blurb: String, mode: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(268.0, 180.0)
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


## A clickable card that runs an arbitrary [param callback] instead of staging a
## MatchSetup mode (used by Challenges, which navigates to its own browse screen).
func _make_action_card(heading: String, blurb: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(268.0, 180.0)
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


## A same-shape card for a mode that is not built yet: disabled (the theme's dimmed
## "disabled" stylebox), non-interactive, muted heading, and a subtle "In development"
## tooltip. Choosing it by keyboard flashes [member _status_label] instead.
func _make_coming_soon_card(heading: String, blurb: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(268.0, 180.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "In development"
	btn.modulate = Color(1, 1, 1, 0.75)

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
	head.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(head)

	var desc := Label.new()
	desc.text = blurb
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(desc)

	# A small gold "COMING SOON" tag so the card reads as intentional, not broken.
	var tag := Label.new()
	tag.text = "COMING SOON"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", MenuTheme.GOLD_DK)
	col.add_child(tag)

	btn.add_child(col)
	return btn


func _on_mode_chosen(mode: String) -> void:
	MatchSetup.requested_mode = mode
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


func _on_challenges_chosen() -> void:
	get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)


func _flash_coming_soon() -> void:
	if _status_label == null:
		return
	_status_label.text = COMING_SOON_TEXT
	_status_label.modulate = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(_status_label, "modulate:a", 0.0, 0.8)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				_flash_coming_soon()
			KEY_2:
				_on_mode_chosen(MatchConfigPanel.MODE_SKIRMISH)
			KEY_3:
				_on_mode_chosen(MatchConfigPanel.MODE_ARENA)
			KEY_4:
				_on_challenges_chosen()
			KEY_ESCAPE:
				_on_back_pressed()
