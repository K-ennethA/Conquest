extends Control

class_name SoloModeSelect

## Solo mode picker, reached from MainMenu's "Solo" button. Offers the single-player
## registers as large mode cards -- Campaign (the story battles ending at the Eldroot
## boss, via [CampaignScreen]), Skirmish (pick a map, fight the AI), Arena Run (draft augments across a gauntlet), Challenges and Duel
## (a 1v1 turn battle, via [DuelSetup]) -- then hands off to the matching screen. This is
## also the Arena entry point (Arena is no longer a title-screen command): Arena Run opens
## [MatchSetup] in its arena variant.
##
## Look: the shared illuminated-grove page ([MenuKit.build_page]: breadcrumb, Cinzel title,
## key hints, Back in the footer); each mode is an [method MenuKit.option_card] with an
## accent edge, a Cinzel heading, a tagline and its number key.
##
## Siege (MatchConfigPanel.MODE_SIEGE) is no longer offered here; its runtime stays in
## game/modes for a possible return.
##
## Keyboard: 1 = Campaign, 2 = Skirmish, 3 = Arena Run, 4 = Challenges, 5 = Duel,
## 6 = Story, Esc / pad B = back. Mouse hover and keyboard / pad focus are one
## highlight (MenuNav).

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"
const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const CAMPAIGN_SCREEN_SCENE := "res://menus/CampaignScreen.tscn"
const DUEL_SETUP_SCENE := "res://menus/DuelSetup.tscn"
const STORY_START_SCENE := "res://game/overworld/ui/StoryStartScreen.tscn"

# --- Card row geometry (1280x720) --------------------------------------------
#
# The cards are EXPAND_FILL inside one HBox, so the row's MINIMUM width is what has to fit
# -- a card narrower than its custom_minimum is not something a container will give you.
#
#   6 cards x CARD_WIDTH + 5 x CARD_SEPARATION  =  6 x 185 + 5 x 14  =  1180
#
# ...which is exactly the page width, inside the 1280 viewport. CARD_HEIGHT is the row's
# height floor; the card content (rule, heading, tagline, wrapped blurb) fits inside it,
# so the row never grows taller.
const CARD_WIDTH: float = 185.0
## 200 (was 180 with five cards): six narrower cards wrap the longer taglines, so the row
## trades a little height for the sixth card's width.
const CARD_HEIGHT: float = 200.0
const CARD_SEPARATION: int = 14
const PAGE_WIDTH: float = 1180.0

var _cards: Array[Button] = []
var _back_button: Button = null


func _ready() -> void:
	var page := MenuKit.build_page(self, [], "Solo", "Choose how you want to play.")
	_build_ui(page)
	if not _cards.is_empty():
		MenuNav.focus_deferred(_cards[0])


func _build_ui(page: Dictionary) -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(PAGE_WIDTH, 0.0)
	column.add_theme_constant_override("separation", MenuTheme.SP_L)
	center.add_child(column)

	var cards := HBoxContainer.new()
	cards.name = "ModeCards"
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", CARD_SEPARATION)
	column.add_child(cards)

	_add_card(cards, _make_action_card(1, "Campaign", "Story",
		"Story battles across the Forgotten Forest.", MenuTheme.EL_NATURE, _on_campaign_chosen))
	_add_card(cards, _make_mode_card(2, "Skirmish", "You vs the AI",
		"Pick a map, choose your squad, defeat the AI.", MenuTheme.GOLD,
		MatchConfigPanel.MODE_SKIRMISH))
	_add_card(cards, _make_mode_card(3, "Arena Run", "Roguelite",
		"Draft augments between rounds. Survive the gauntlet.", MenuTheme.EL_FIRE,
		MatchConfigPanel.MODE_ARENA))
	_add_card(cards, _make_action_card(4, "Challenges", "Community",
		"Beat maps other players built -- or share your own gauntlet.", MenuTheme.ACCENT,
		_on_challenges_chosen))
	_add_card(cards, _make_action_card(5, "Duel", "One on one",
		"Two units, no movement -- just the moves.", MenuTheme.EL_EARTH, _on_duel_chosen))
	_add_card(cards, _make_action_card(6, "Story", "Journey",
		"Walk the forest, meet its people, fight what bars the road.", MenuTheme.EL_HOLY,
		_on_story_chosen))
	# Wrap horizontal focus across the row.
	_cards[0].focus_neighbor_left = _cards[0].get_path_to(_cards[-1])
	_cards[-1].focus_neighbor_right = _cards[-1].get_path_to(_cards[0])

	_back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	_back_button.name = "BackButton"
	_back_button.pressed.connect(_on_back_pressed)
	page.actions.add_child(_back_button)

	MenuKit.add_standard_hints(page.hints, "Select")
	var hint := MenuKit.label(
		"1 Campaign  •  2 Skirmish  •  3 Arena Run  •  4 Challenges  •  5 Duel  •  6 Story", &"MutedLabel")
	hint.name = "KeyHint"
	hint.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.hints.add_child(hint)


func _add_card(row: HBoxContainer, card: Button) -> void:
	row.add_child(card)
	_cards.append(card)


## A mode card that stages a [MatchSetup] variant: pressing it calls
## [method _on_mode_chosen] bound to [param mode].
func _make_mode_card(number: int, heading: String, tagline: String, blurb: String,
		accent: Color, mode: String) -> Button:
	var btn := _make_card(number, heading, tagline, blurb, accent)
	btn.pressed.connect(_on_mode_chosen.bind(mode))
	return btn


## A card that runs an arbitrary [param callback] instead of staging a MatchSetup mode
## (Campaign and Challenges navigate to their own screens).
func _make_action_card(number: int, heading: String, tagline: String, blurb: String,
		accent: Color, callback: Callable) -> Button:
	var btn := _make_card(number, heading, tagline, blurb, accent)
	btn.pressed.connect(callback)
	return btn


## The shared card body: accent edge, number-key numeral, Cinzel heading, tagline, blurb.
## The content sits in option_card's full-rect margin (a Button is not a Container), so
## it never widens the card past CARD_WIDTH; the blurb wraps inside it.
func _make_card(number: int, heading: String, tagline: String, blurb: String,
		accent: Color) -> Button:
	var parts := MenuKit.option_card(Vector2(CARD_WIDTH, CARD_HEIGHT))
	var btn: Button = parts["button"]
	btn.name = heading.replace(" ", "") + "Card"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.tooltip_text = "%s  (%d)" % [heading, number]
	MenuKit.accent_card(btn, accent)
	var m: MarginContainer = parts["margin"]
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 12)
	var v: VBoxContainer = parts["content"]
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	# 4, not 6: with the Cinzel heading the longest blurb (Siege) otherwise grows the
	# card past CARD_HEIGHT, and the row must stay exactly CARD_HEIGHT tall.
	v.add_theme_constant_override("separation", 4)

	var rule := GroveRule.new()
	rule.color = accent
	rule.custom_minimum_size = Vector2(72, 10)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(rule)
	var head := MenuKit.label(heading, &"SubheadingLabel")
	head.add_theme_font_size_override("font_size", 20)
	v.add_child(head)
	# Wraps: six cards leave ~150px of text width, and "LANES AND BASES" is wider than that.
	var tl := MenuKit.label(tagline.to_upper(), &"SectionLabel", true)
	tl.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	tl.add_theme_color_override("font_color", accent.lightened(0.2))
	# Six cards share the row: a long tagline wraps rather than spilling past the frame.
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tl)
	var desc := MenuKit.label(blurb, &"DimLabel", true)
	desc.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	v.add_child(desc)

	# Quiet number-key numeral in the top-right corner.
	var num := MenuKit.label(str(number), &"MutedLabel")
	num.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	num.offset_left = -30
	num.offset_right = -12
	num.offset_top = 8
	num.offset_bottom = 30
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	btn.add_child(num)

	MenuKit.ignore_mouse(btn)
	MenuNav.hover_focus(btn)
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
	MenuNav.change_scene(self, MATCH_SETUP_SCENE)


func _on_challenges_chosen() -> void:
	MenuNav.change_scene(self, CHALLENGE_BROWSE_SCENE)


func _on_duel_chosen() -> void:
	MenuNav.change_scene(self, DUEL_SETUP_SCENE)


func _on_campaign_chosen() -> void:
	MenuNav.change_scene(self, CAMPAIGN_SCREEN_SCENE)


func _on_story_chosen() -> void:
	MenuNav.change_scene(self, STORY_START_SCENE)


func _on_back_pressed() -> void:
	MenuNav.change_scene(self, MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var idx: int = (event as InputEventKey).keycode - KEY_1
	if idx >= 0 and idx < _cards.size():
		get_viewport().set_input_as_handled()
		_cards[idx].grab_focus()
		_cards[idx].pressed.emit()
