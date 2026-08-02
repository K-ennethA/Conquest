extends GutTest

# Tests for the modular win-condition framework and the GameModeRules bundle.
# Uses the shared doubles (no scene tree / live board), matching the style of
# test_move_system.gd.

# --- Mocks -----------------------------------------------------------------
# ObjectiveUnit is identity + liveness (no stats); RosterBoard adds all_units, the
# hook win conditions enumerate through. See tests/helpers/test_doubles.gd.
const Doubles := preload("res://tests/helpers/test_doubles.gd")

# --- DefeatAllEnemies ------------------------------------------------------

func test_defeat_all_met_when_no_enemies_remain():
	var cond := DefeatAllEnemies.new()
	cond.faction = 0
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var enemy := Doubles.ObjectiveUnit.new(1, 0)  # dead
	var state := { "units": [ally, enemy] }
	assert_eq(cond.evaluate(state), WinCondition.Status.MET, "all enemies down -> MET")

func test_defeat_all_ongoing_while_enemy_alive():
	var cond := DefeatAllEnemies.new()
	cond.faction = 0
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var enemy := Doubles.ObjectiveUnit.new(1, 40)  # alive
	var state := { "units": [ally, enemy] }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "living enemy -> ONGOING")

# --- CaptureThrone ---------------------------------------------------------

func test_capture_throne_met_when_right_faction_on_cell():
	var cond := CaptureThrone.new()
	cond.faction = 0
	cond.target_cell = Vector2i(5, 5)
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var board := Doubles.RosterBoard.new()
	board.place(ally, Vector2i(5, 5))
	var state := { "board": board, "units": board.all_units() }
	assert_eq(cond.evaluate(state), WinCondition.Status.MET, "ally on throne -> MET")

func test_capture_throne_ongoing_when_enemy_holds_cell():
	var cond := CaptureThrone.new()
	cond.faction = 0
	cond.target_cell = Vector2i(5, 5)
	var enemy := Doubles.ObjectiveUnit.new(1, 100)
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var board := Doubles.RosterBoard.new()
	board.place(enemy, Vector2i(5, 5))
	board.place(ally, Vector2i(0, 0))
	var state := { "board": board, "units": board.all_units() }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "enemy on throne -> ONGOING")

func test_capture_throne_ignores_dead_holder():
	var cond := CaptureThrone.new()
	cond.faction = 0
	cond.target_cell = Vector2i(2, 2)
	var dead_ally := Doubles.ObjectiveUnit.new(0, 0)
	var board := Doubles.RosterBoard.new()
	board.place(dead_ally, Vector2i(2, 2))
	var state := { "board": board, "units": board.all_units() }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "dead ally does not capture")

# --- SurviveTurns ----------------------------------------------------------

func test_survive_turns_met_at_target_turn():
	var cond := SurviveTurns.new()
	cond.turns = 3
	cond.faction = 0
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	assert_eq(cond.evaluate({ "units": [ally], "turn": 3 }), WinCondition.Status.MET, "reached turn -> MET")
	assert_eq(cond.evaluate({ "units": [ally], "turn": 2 }), WinCondition.Status.ONGOING, "before turn -> ONGOING")

func test_survive_turns_failed_when_faction_wiped():
	var cond := SurviveTurns.new()
	cond.turns = 5
	cond.faction = 0
	cond.require_survivor = true
	var dead := Doubles.ObjectiveUnit.new(0, 0)
	assert_eq(cond.evaluate({ "units": [dead], "turn": 1 }), WinCondition.Status.FAILED, "no survivors -> FAILED")

# --- ProtectUnit -----------------------------------------------------------

func test_protect_unit_ongoing_while_alive_failed_when_dead():
	var cond := ProtectUnit.new()
	cond.protected_id = &"vip"
	var vip_alive := Doubles.ObjectiveUnit.new(0, 100, &"vip")
	assert_eq(cond.evaluate({ "units": [vip_alive] }), WinCondition.Status.ONGOING, "vip alive -> ONGOING")
	var vip_dead := Doubles.ObjectiveUnit.new(0, 0, &"vip")
	assert_eq(cond.evaluate({ "units": [vip_dead] }), WinCondition.Status.FAILED, "vip dead -> FAILED")
	assert_eq(cond.evaluate({ "units": [] }), WinCondition.Status.FAILED, "vip missing -> FAILED")

# --- GameModeRules ---------------------------------------------------------

func test_rules_victory_when_win_condition_met():
	var rules := GameModeRules.new()
	var win := DefeatAllEnemies.new()
	win.faction = 0
	rules.win_conditions = [win]
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var enemy := Doubles.ObjectiveUnit.new(1, 0)  # dead
	assert_eq(rules.evaluate({ "units": [ally, enemy] }), GameModeRules.Outcome.VICTORY, "enemies gone -> VICTORY")

func test_rules_defeat_when_win_condition_failed():
	var rules := GameModeRules.new()
	var protect := ProtectUnit.new()
	protect.protected_id = &"vip"
	rules.win_conditions = [protect]
	var vip_dead := Doubles.ObjectiveUnit.new(0, 0, &"vip")
	assert_eq(rules.evaluate({ "units": [vip_dead] }), GameModeRules.Outcome.DEFEAT, "vip lost -> DEFEAT")

func test_rules_defeat_when_lose_condition_met():
	var rules := GameModeRules.new()
	var win := SurviveTurns.new()
	win.turns = 10
	win.require_survivor = false
	rules.win_conditions = [win]
	# Enemy seizing our home cell is a losing condition.
	var lose := CaptureThrone.new()
	lose.faction = 1
	lose.target_cell = Vector2i(0, 0)
	rules.lose_conditions = [lose]
	var enemy := Doubles.ObjectiveUnit.new(1, 100)
	var board := Doubles.RosterBoard.new()
	board.place(enemy, Vector2i(0, 0))
	var state := { "board": board, "units": board.all_units(), "turn": 1 }
	assert_eq(rules.evaluate(state), GameModeRules.Outcome.DEFEAT, "enemy captured home -> DEFEAT")

func test_rules_ongoing_and_flags_default_off():
	var rules := GameModeRules.new()
	var win := DefeatAllEnemies.new()
	win.faction = 0
	rules.win_conditions = [win]
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var enemy := Doubles.ObjectiveUnit.new(1, 50)  # alive
	assert_eq(rules.evaluate({ "units": [ally, enemy] }), GameModeRules.Outcome.ONGOING, "battle continues")
	assert_false(rules.allow_bots, "allow_bots defaults off")
	assert_false(rules.boss_enabled, "boss_enabled defaults off")

func test_rules_require_all_win_needs_every_condition():
	var rules := GameModeRules.new()
	rules.require_all_win = true
	var defeat_all := DefeatAllEnemies.new()
	defeat_all.faction = 0
	var survive := SurviveTurns.new()
	survive.turns = 5
	survive.faction = 0
	rules.win_conditions = [defeat_all, survive]
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var enemy := Doubles.ObjectiveUnit.new(1, 0)  # dead: defeat_all MET, but not enough turns
	assert_eq(rules.evaluate({ "units": [ally, enemy], "turn": 2 }), GameModeRules.Outcome.ONGOING, "one of two met -> ONGOING")
	assert_eq(rules.evaluate({ "units": [ally, enemy], "turn": 5 }), GameModeRules.Outcome.VICTORY, "both met -> VICTORY")

# --- DefeatBoss ------------------------------------------------------------

func test_defeat_boss_ongoing_while_enemy_boss_alive():
	var cond := DefeatBoss.new()
	cond.faction = 0
	var boss := Doubles.ObjectiveUnit.new(1, 200, &"boss", true)
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	assert_eq(cond.evaluate({ "units": [ally, boss] }), WinCondition.Status.ONGOING, "living enemy boss -> ONGOING")

func test_defeat_boss_met_when_boss_dead_even_with_grunts_alive():
	# The whole point of "kill the commander": the boss's death wins the map even
	# while ordinary enemies are still standing.
	var cond := DefeatBoss.new()
	cond.faction = 0
	var dead_boss := Doubles.ObjectiveUnit.new(1, 0, &"boss", true)
	var live_grunt := Doubles.ObjectiveUnit.new(1, 50)
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	assert_eq(cond.evaluate({ "units": [ally, live_grunt, dead_boss] }), WinCondition.Status.MET, "boss dead -> MET despite grunts")

func test_defeat_boss_ongoing_when_no_boss_present():
	# A map with no boss must never be won by default -- there is nothing to kill.
	var cond := DefeatBoss.new()
	cond.faction = 0
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var grunt := Doubles.ObjectiveUnit.new(1, 50)
	assert_eq(cond.evaluate({ "units": [ally, grunt] }), WinCondition.Status.ONGOING, "no boss -> never an instant win")

# --- WinConditionLibrary (string -> condition factory) ---------------------

func test_library_maps_strings_to_condition_types():
	assert_true(WinConditionLibrary.build_one("Defeat Boss", 0) is DefeatBoss, "'Defeat Boss' -> DefeatBoss")
	assert_true(WinConditionLibrary.build_one("Eliminate All Enemies", 0) is DefeatAllEnemies, "'Eliminate All Enemies' -> DefeatAllEnemies")
	assert_true(WinConditionLibrary.build_one("Some Nonsense", 0) is DefeatAllEnemies, "unknown -> DefeatAllEnemies fallback")

func test_library_rules_win_on_boss_death():
	var rules := WinConditionLibrary.build_rules(["Defeat Boss"], 0)
	var ally := Doubles.ObjectiveUnit.new(0, 100)
	var dead_boss := Doubles.ObjectiveUnit.new(1, 0, &"boss", true)
	assert_eq(rules.evaluate({ "units": [ally, dead_boss] }), GameModeRules.Outcome.VICTORY, "boss dead -> VICTORY")
	var live_boss := Doubles.ObjectiveUnit.new(1, 200, &"boss", true)
	assert_eq(rules.evaluate({ "units": [ally, live_boss] }), GameModeRules.Outcome.ONGOING, "boss alive -> ONGOING")

func test_library_rules_lose_when_player_side_wiped():
	# Derived lose condition: even with the boss alive (win unmet), losing your whole
	# side is a Defeat.
	var rules := WinConditionLibrary.build_rules(["Defeat Boss"], 0)
	var live_boss := Doubles.ObjectiveUnit.new(1, 200, &"boss", true)
	var dead_ally := Doubles.ObjectiveUnit.new(0, 0)
	assert_eq(rules.evaluate({ "units": [dead_ally, live_boss] }), GameModeRules.Outcome.DEFEAT, "player wiped -> DEFEAT")
