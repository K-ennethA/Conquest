extends Control

class_name OnlineHub

## The ONLINE screen (docs/design/DECISIONS.md #30-32), reached from MainMenu's "Online" row:
## everything you play against other people.
##
##   Versus      -- [MultiplayerModeSelection]: pick the MODE (Conquest map battle or Duel) and
##                  WHERE the opponent is (Network, or Same device hot-seat).
##   Challenges  -- [ChallengeBrowse] (moved here from Solo): other players' maps and gauntlets.
##   Arena       -- multiplayer arena: COMING SOON. Shown so the shape of Online is visible,
##                  disabled and skipped by keyboard / pad focus; nothing behind it yet.
##
## Grove look (MenuKit.build_page + choice cards, docs/UI_STYLE.md); built in code, the .tscn
## is only the root. Keys: 1 Versus, 2 Challenges, Esc / pad B back to the title screen.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const VERSUS_SCENE := "res://menus/MultiplayerModeSelection.tscn"
const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"

## 720p: three cards + two SP_L gaps = 3 x 360 + 2 x 24 = 1128, inside the 1180 page.
const CARD_SIZE := Vector2(360, 300)
const COMING_SOON := "COMING SOON"

var versus_button: Button
var challenges_button: Button
var arena_button: Button
var back_button: Button


func _ready() -> void:
	var page := MenuKit.build_page(self, [], "Online", "Play against other people.")
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)
	var row := HBoxContainer.new()
	row.name = "OnlineCards"
	row.add_theme_constant_override("separation", MenuTheme.SP_L)
	center.add_child(row)

	versus_button = MenuKit.choice_card("Versus", "Conquest or Duel",
		"Face another player in a Conquest map battle or a one-on-one Duel -- over the network, or taking turns on this device.",
		["Network: host, join or a dedicated server", "Same device: hot-seat"],
		MenuTheme.GOLD, null, CARD_SIZE)
	versus_button.name = "VersusCard"
	versus_button.tooltip_text = "Versus  (1)"
	versus_button.pressed.connect(_on_versus_pressed)
	row.add_child(versus_button)

	challenges_button = MenuKit.choice_card("Challenges", "Community",
		"Beat maps and gauntlets other players built -- or share your own.",
		["Browse, download and rank", "Your bases and replays"],
		MenuTheme.ACCENT, null, CARD_SIZE)
	challenges_button.name = "ChallengesCard"
	challenges_button.tooltip_text = "Challenges  (2)"
	challenges_button.pressed.connect(_on_challenges_pressed)
	row.add_child(challenges_button)

	arena_button = MenuKit.choice_card("Arena", "Multiplayer",
		"A shared arena against other players. Not open yet.",
		[], MenuTheme.EL_FIRE, null, CARD_SIZE)
	arena_button.name = "ArenaCard"
	arena_button.disabled = true
	arena_button.focus_mode = Control.FOCUS_NONE
	arena_button.tooltip_text = "Arena -- coming soon"
	arena_button.modulate = Color(1, 1, 1, 0.72)
	var soon := MenuKit.badge(COMING_SOON, MenuTheme.WARNING)
	soon.name = "ComingSoon"
	soon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	soon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content := _card_content(arena_button)
	if content != null:
		content.add_child(soon)
		content.move_child(soon, mini(1, content.get_child_count() - 1))
	MenuKit.ignore_mouse(arena_button)
	row.add_child(arena_button)

	# Wrap horizontal focus across the two live cards (Arena is skipped).
	versus_button.focus_neighbor_left = versus_button.get_path_to(challenges_button)
	challenges_button.focus_neighbor_right = challenges_button.get_path_to(versus_button)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	back_button.name = "BackButton"
	back_button.pressed.connect(_on_back_pressed)
	page.actions.add_child(back_button)

	MenuKit.add_standard_hints(page.hints, "Select")
	var hint := MenuKit.label("1 Versus  •  2 Challenges  •  Arena coming soon", &"MutedLabel")
	hint.name = "KeyHint"
	hint.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.hints.add_child(hint)

	MenuNav.focus_deferred(versus_button)


## The VBox a MenuKit option / choice card holds its content in.
static func _card_content(card: Button) -> VBoxContainer:
	for m in card.get_children():
		if m is MarginContainer:
			for v in m.get_children():
				if v is VBoxContainer:
					return v
	return null


func _on_versus_pressed() -> void:
	MenuNav.change_scene(self, VERSUS_SCENE)


func _on_challenges_pressed() -> void:
	MenuNav.change_scene(self, CHALLENGE_BROWSE_SCENE)


func _on_back_pressed() -> void:
	MenuNav.change_scene(self, MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			get_viewport().set_input_as_handled()
			_on_versus_pressed()
		KEY_2:
			get_viewport().set_input_as_handled()
			_on_challenges_pressed()
