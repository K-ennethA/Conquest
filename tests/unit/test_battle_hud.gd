extends GutTest

## Battle HUD presentation: the shared navy + gold tokens, input-driven key hints,
## the FE command list (Move / Skills / Wait / Info / Cancel), phase titles and the
## End Turn shortcut guard. Headless: no GameWorld scene is loaded.

const ACTIONS_PANEL := preload("res://game/ui/panels/UnitActionsPanel.tscn")


func _character_unit() -> Unit:
	var c := CharacterResource.new()
	c.character_id = &"vineweave"
	c.display_name = "Torvald Ironhide the Unbroken"
	var u := Unit.new()
	u.character_resource = c
	add_child_autofree(u)
	return u


# --- Tokens -----------------------------------------------------------------------

func test_battle_theme_shares_the_menu_tokens() -> void:
	assert_eq(ConquestTheme.GOLD, MenuTheme.GOLD, "one accent colour in and out of battle")
	assert_eq(ConquestTheme.PANEL, MenuTheme.PANEL)
	assert_eq(ConquestTheme.CREAM, MenuTheme.CREAM)
	# The legacy amber names now resolve onto the navy tokens.
	assert_eq(ConquestTheme.AMBER, MenuTheme.GOLD)
	var t := ConquestTheme.build()
	assert_true(t.has_stylebox("focus", "HudCommand"), "command-list buttons have a focus state")
	assert_eq(t.get_color("font_focus_color", "HudCommand"), ConquestTheme.GOLD_LITE,
		"focused command text stays gold on navy (never light-on-light)")


func test_hp_colour_tiers_match_the_map_bar() -> void:
	assert_eq(ConquestTheme.hp_color(0.9), ConquestTheme.HP_HIGH)
	assert_eq(ConquestTheme.hp_color(0.4), ConquestTheme.HP_MID)
	assert_eq(ConquestTheme.hp_color(0.1), ConquestTheme.HP_LOW)
	assert_eq(HealthBar.COLOR_HIGH, ConquestTheme.HP_HIGH)


# --- Key hints ----------------------------------------------------------------------

func test_hints_come_from_the_input_map() -> void:
	# No gamepad in the headless run -> keyboard glyphs, straight from InputMap.
	assert_eq(InputActions.hint(InputActions.WAIT), InputActions.describe(InputActions.WAIT))
	assert_eq(ConquestTheme.short_key("Escape"), "Esc")
	assert_eq(ConquestTheme.action_glyph(&""), "")


# --- Command list ---------------------------------------------------------------------

func test_command_list_labels_and_hints() -> void:
	var u := _character_unit()
	var panel = ACTIONS_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame

	panel.selected_unit = u
	panel._update_unit_header()
	panel._update_actions()

	assert_eq(panel.move_button.text, "Move")
	assert_eq(panel.moves_button.text, "Skills")
	assert_eq(panel.end_unit_turn_button.text, "Wait", "the per-unit action is WAIT, not 'End Turn'")
	assert_eq(panel.unit_summary_button.text, "Info")
	assert_eq(panel.cancel_button.text, "Cancel")
	assert_false(panel.end_player_turn_button.visible, "ending the phase lives in the Map Menu")
	# Always-available commands show their bound key.
	assert_eq(panel.command_hint_text(panel.unit_summary_button),
		ConquestTheme.action_glyph(InputActions.UNIT_INFO))
	assert_eq(panel.command_hint_text(panel.cancel_button),
		ConquestTheme.action_glyph(InputActions.CANCEL))
	# The full name is never clipped.
	assert_eq(panel.unit_name_label.text, "Torvald Ironhide the Unbroken")
	assert_false(panel.unit_name_label.clip_text)
	assert_ne(panel.unit_name_label.autowrap_mode, TextServer.AUTOWRAP_OFF)


# --- Phase titles -------------------------------------------------------------------------

func test_phase_titles() -> void:
	var prev: int = GameSettings.game_mode
	GameSettings.game_mode = GameSettings.GameMode.SINGLE_PLAYER
	var human := Player.new(0, "Player 1")
	var ai := Player.new(1, "Enemy")
	ai.is_ai = true
	assert_eq(ConquestTheme.phase_title(human), "PLAYER PHASE")
	assert_eq(ConquestTheme.phase_title(ai), "ENEMY PHASE")
	assert_eq(ConquestTheme.side_label(ai), "Enemy")
	GameSettings.game_mode = GameSettings.GameMode.VERSUS
	assert_eq(ConquestTheme.phase_title(Player.new(1, "P2")), "PLAYER TWO PHASE")
	GameSettings.game_mode = prev
	assert_eq(ConquestTheme.team_color(human), ConquestTheme.TEAM_BLUE)
	assert_eq(ConquestTheme.team_color(ai), ConquestTheme.TEAM_RED)


# --- End Turn shortcut -------------------------------------------------------------------

func test_end_turn_shortcut_is_refused_off_the_local_turn() -> void:
	var menu := MapMenu.new()
	add_child_autofree(menu)
	assert_false(menu.can_open_end_turn(), "nobody is the local human in a bare test tree")
