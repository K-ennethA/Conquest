extends Control

class_name TurnSystemSelection

## Turn-system picker (Single Player, and Local Versus after the mode screen). Two
## side-by-side cards explain each mode in plain language with a tiny turn-order
## diagram; picking one stores it in GameSettings and moves on to the map picker.
## Built in code; the .tscn is only the root.

const MAP_SELECTION_SCENE := "res://menus/MapSelection.tscn"

var traditional_button: Button
var initiative_button: Button
var back_button: Button

var selected_turn_system: TurnSystemBase.TurnSystemType = TurnSystemBase.TurnSystemType.TRADITIONAL


func _ready() -> void:
	var versus := GameSettings.game_mode == GameSettings.GameMode.VERSUS
	var page := MenuKit.build_page(self, ["Local Versus" if versus else "Single Player"],
		"How Should Turns Work?",
		"Choose how the two armies take turns. You can pick a different system for every battle.")

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	center.add_child(row)

	traditional_button = MenuKit.choice_card("Traditional", "Armies take turns",
		"You move every one of your units, then your opponent moves all of theirs. Classic, calm and easy to plan around.",
		["Set up combined attacks and formations", "Best for your first battles"],
		MenuTheme.GOLD, MenuKit.pip_row("BBBB|RRRR"), Vector2(440, 340))
	traditional_button.name = "TraditionalButton"
	traditional_button.pressed.connect(_on_traditional_pressed)
	row.add_child(traditional_button)

	initiative_button = MenuKit.choice_card("Speed First", "Units act by speed",
		"Every unit acts once per round, one at a time, fastest first -- whichever army it belongs to. Speed boosts can change the order mid-round.",
		["Fast units strike before slow ones", "Tense, back-and-forth battles"],
		MenuTheme.ACCENT, MenuKit.pip_row("BRBBRR"), Vector2(440, 340))
	initiative_button.name = "InitiativeButton"
	initiative_button.pressed.connect(_on_initiative_pressed)
	row.add_child(initiative_button)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	back_button.name = "BackButton"
	back_button.pressed.connect(_on_back_pressed)
	page.actions.add_child(back_button)
	MenuKit.add_standard_hints(page.hints, "Choose")

	# Resume on whatever was picked last time.
	if GameSettings.selected_turn_system == TurnSystemBase.TurnSystemType.INITIATIVE:
		MenuNav.focus_deferred(initiative_button)
	else:
		MenuNav.focus_deferred(traditional_button)


func _on_traditional_pressed() -> void:
	selected_turn_system = TurnSystemBase.TurnSystemType.TRADITIONAL
	_start_game_with_turn_system()


func _on_initiative_pressed() -> void:
	selected_turn_system = TurnSystemBase.TurnSystemType.INITIATIVE
	_start_game_with_turn_system()


func _on_back_pressed() -> void:
	# Local versus came here from the mode picker; single player from the title.
	if GameSettings.game_mode == GameSettings.GameMode.VERSUS:
		MenuNav.change_scene(self, "res://menus/MultiplayerModeSelection.tscn")
	else:
		MenuNav.change_scene(self, "res://menus/MainMenu.tscn")


func _start_game_with_turn_system() -> void:
	# Store the choice for the game to use. The game mode was already set by the
	# previous screen (Single Player on the title menu, Versus on the mode picker)
	# and is left as-is so local hot-seat stays a two-human match.
	GameSettings.selected_turn_system = selected_turn_system
	MenuNav.change_scene(self, MAP_SELECTION_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_on_traditional_pressed()
			KEY_2:
				_on_initiative_pressed()
