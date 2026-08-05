extends Control

class_name SoloModeSelect

## Solo mode picker, reached from MainMenu's "Solo" button. Offers the single-player
## registers as large mode cards -- Campaign (the story battles ending at the Eldroot
## boss, via [CampaignScreen]), Skirmish (pick a map, fight the AI), Siege (push the lanes
## and take their base), Arena Run (draft augments across a gauntlet) and Challenges --
## then hands off to the matching screen. Dark "Legends" menu look via [MenuTheme].
##
## Keyboard: 1 = Campaign, 2 = Skirmish, 3 = Siege, 4 = Arena Run, 5 = Challenges,
## ESC = back.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"
const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const CAMPAIGN_SCREEN_SCENE := "res://menus/CampaignScreen.tscn"

# --- Card row geometry (1280x720) --------------------------------------------
#
# The page is a 1180-wide column inside a CenterContainer, and the cards are EXPAND_FILL
# inside one HBox, so the row's MINIMUM width is what has to fit -- a card narrower than
# its custom_minimum is not something a container will give you.
#
#   5 cards x CARD_WIDTH + 4 x CARD_SEPARATION  =  5 x 220 + 4 x 20  =  1180
#
# ...which is exactly the page width, and 100px inside the 1280 viewport. Adding Siege as
# a fifth card therefore cost width, not height: CARD_HEIGHT is unchanged, so the page's
# vertical stack (title 40 + subtitle + 20 spacer + 180 cards + 10 + 44 back + caption) is
# the same it was. The old per-card 268 is where the 1420 that would NOT have fitted came
# from, so the number is declared here rather than repeated at each call site.
const CARD_WIDTH: float = 220.0
const CARD_HEIGHT: float = 180.0
const CARD_SEPARATION: int = 20
const PAGE_WIDTH: float = 1180.0


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_build_ui()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(PAGE_WIDTH, 0.0)
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
	cards.name = "ModeCards"
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", CARD_SEPARATION)
	page.add_child(cards)

	cards.add_child(_make_action_card(
		"1.  Campaign",
		"Story battles across the\nForgotten Forest.",
		_on_campaign_chosen))
	cards.add_child(_make_mode_card(
		"2.  Skirmish",
		"Pick a map, choose your squad,\ndefeat the AI.",
		MatchConfigPanel.MODE_SKIRMISH))
	# Siege sits beside Skirmish, not off in its own register: both are "pick a map, take a
	# squad, fight the AI", and what makes Siege different is the MAP's own objective.
	cards.add_child(_make_mode_card(
		"3.  Siege",
		"Push the lanes, hold your base,\ntake theirs.",
		MatchConfigPanel.MODE_SIEGE))
	cards.add_child(_make_mode_card(
		"4.  Arena Run",
		"Draft augments between rounds.\nSurvive the gauntlet.",
		MatchConfigPanel.MODE_ARENA))
	cards.add_child(_make_action_card(
		"5.  Challenges",
		"Beat maps other players built --\nor share your own gauntlet.",
		_on_challenges_chosen))

	var footspace := Control.new()
	footspace.custom_minimum_size = Vector2(0.0, 10.0)
	page.add_child(footspace)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 44.0)
	back.pressed.connect(_on_back_pressed)
	page.add_child(back)

	var hint := Label.new()
	hint.name = "KeyHint"
	hint.text = "1 Campaign  •  2 Skirmish  •  3 Siege  •  4 Arena Run  •  5 Challenges  •  ESC back"
	page.add_child(hint)
	MenuTheme.style_caption(hint)


## A tall, clickable mode card: a big gold heading over a dim description line.
func _make_mode_card(heading: String, blurb: String, mode: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
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
	btn.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
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


func _on_mode_chosen(mode: String) -> void:
	# Declare the register, exactly as MultiplayerModeSelection declares VERSUS on its way
	# out. GameSettings.game_mode DEFAULTS to VERSUS, and GameWorldManager only scores a
	# map's own compiled win conditions in SINGLE_PLAYER (_evaluate_game_end) -- so without
	# this a Siege launched from here would fall through to the neutral "last side standing"
	# path and a base capture would decide nothing. Arena already sets the same flag from
	# ArenaController; this is the missing half of that pair for the map-launched modes.
	if GameSettings != null and GameSettings.has_method("set_game_mode"):
		GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	MatchSetup.requested_mode = mode
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


func _on_challenges_chosen() -> void:
	get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)


func _on_campaign_chosen() -> void:
	get_tree().change_scene_to_file(CAMPAIGN_SCREEN_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				_on_campaign_chosen()
			KEY_2:
				_on_mode_chosen(MatchConfigPanel.MODE_SKIRMISH)
			KEY_3:
				_on_mode_chosen(MatchConfigPanel.MODE_SIEGE)
			KEY_4:
				_on_mode_chosen(MatchConfigPanel.MODE_ARENA)
			KEY_5:
				_on_challenges_chosen()
			KEY_ESCAPE:
				_on_back_pressed()
