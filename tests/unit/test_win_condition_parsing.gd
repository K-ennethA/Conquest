extends GutTest

# WinConditionLibrary string parsing for Survive / Seize objectives, the turn
# counter fed to SurviveTurns (completed_rounds), and end-to-end rule evaluation
# with a real turn value -- the "can never be won" regression (turn was hardcoded 0).

class MockUnit:
	var team: int
	var hp: int
	func _init(p_team: int, p_hp: int = 100) -> void:
		team = p_team
		hp = p_hp

class MockBoard:
	var placements: Array = []
	func place(unit, cell: Vector3i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func units_at(cell: Vector3i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out

class MockSpeedSystem:
	var round_number: int = 1
	var current_turn: int = 1

class MockTraditionalSystem:
	var current_turn: int = 1
	var registered_players: Array = [1, 2]


# --- Survive ---------------------------------------------------------------------

func test_survive_with_inline_count():
	var c := WinConditionLibrary.build_one("Survive 8 Turns", 0)
	assert_true(c is SurviveTurns, "Survive string -> SurviveTurns")
	assert_eq((c as SurviveTurns).turns, 8)
	assert_eq((c as SurviveTurns).faction, 0)

func test_survive_without_count_uses_turn_limit():
	var c := WinConditionLibrary.build_one("Survive", 0, [], 6)
	assert_true(c is SurviveTurns)
	assert_eq((c as SurviveTurns).turns, 6, "falls back to the map's turn_limit")

func test_survive_without_count_or_limit_uses_default():
	var c := WinConditionLibrary.build_one("survive the onslaught", 0)
	assert_eq((c as SurviveTurns).turns, WinConditionLibrary.DEFAULT_SURVIVE_TURNS)


# --- Seize -----------------------------------------------------------------------

func test_seize_reads_throne_marker_from_special_rules():
	var rules := ["some_other_rule", "objective:THRONE:-1:7:5"]
	var c := WinConditionLibrary.build_one("Seize Throne", 0, rules)
	assert_true(c is CaptureThrone, "Seize -> CaptureThrone")
	assert_eq((c as CaptureThrone).target_cell, Vector3i(7, 5, 0))

func test_seize_inline_cell_wins_over_marker():
	var c := WinConditionLibrary.build_one("Capture (2, 3)", 0, ["objective:THRONE:-1:7:5"])
	assert_eq((c as CaptureThrone).target_cell, Vector3i(2, 3, 0))

func test_seize_without_any_cell_falls_back_to_defeat_all():
	var c := WinConditionLibrary.build_one("Seize Throne", 0, [])
	assert_true(c is DefeatAllEnemies, "no cell anywhere -> safe fallback")

func test_find_objective_cell_ignores_malformed_rules():
	assert_null(WinConditionLibrary.find_objective_cell(["objective:THRONE:x:y"]))
	assert_eq(WinConditionLibrary.find_objective_cell(["objective:throne:0:1:2"]), Vector2i(1, 2))

func test_build_rules_for_map_threads_marker_and_limit():
	var map := MapResource.new()
	map.victory_conditions = ["Seize Throne"]
	map.special_rules = ["objective:THRONE:-1:4:4"]
	var rules := WinConditionLibrary.build_rules_for_map(map)
	assert_eq(rules.win_conditions.size(), 1)
	assert_true(rules.win_conditions[0] is CaptureThrone)
	assert_eq((rules.win_conditions[0] as CaptureThrone).target_cell, Vector3i(4, 4, 0))


# --- Turn counter ----------------------------------------------------------------

func test_completed_rounds_speed_first():
	var ts := MockSpeedSystem.new()
	assert_eq(WinConditionLibrary.completed_rounds(ts), 0, "round 1 in progress -> 0 done")
	ts.round_number = 4
	assert_eq(WinConditionLibrary.completed_rounds(ts), 3)

func test_completed_rounds_traditional_counts_full_rounds():
	var ts := MockTraditionalSystem.new()  # 2 players; current_turn counts player phases
	assert_eq(WinConditionLibrary.completed_rounds(ts), 0)
	ts.current_turn = 2  # P2's first phase
	assert_eq(WinConditionLibrary.completed_rounds(ts), 0)
	ts.current_turn = 3  # P1's second phase: one full round done
	assert_eq(WinConditionLibrary.completed_rounds(ts), 1)
	ts.current_turn = 7
	assert_eq(WinConditionLibrary.completed_rounds(ts), 3)

func test_completed_rounds_null_is_zero():
	assert_eq(WinConditionLibrary.completed_rounds(null), 0)


# --- End to end ------------------------------------------------------------------

func test_survive_rules_resolve_to_victory_once_turns_elapse():
	var rules := WinConditionLibrary.build_rules(["Survive 3 Turns"])
	var ally := MockUnit.new(0)
	var enemy := MockUnit.new(1)
	var state := { "units": [ally, enemy], "turn": 2 }
	assert_eq(rules.evaluate(state), GameModeRules.Outcome.ONGOING)
	state["turn"] = 3
	assert_eq(rules.evaluate(state), GameModeRules.Outcome.VICTORY, "survived 3 full rounds")

func test_seize_rules_resolve_when_ally_stands_on_throne():
	var rules := WinConditionLibrary.build_rules(["Seize Throne"], 0, ["objective:THRONE:-1:5:5"])
	var ally := MockUnit.new(0)
	var enemy := MockUnit.new(1)
	var board := MockBoard.new()
	board.place(ally, Vector3i(1, 1, 0))
	board.place(enemy, Vector3i(9, 9, 0))
	var state := { "units": board.all_units(), "board": board, "turn": 0 }
	assert_eq(rules.evaluate(state), GameModeRules.Outcome.ONGOING)
	board.placements[0].cell = Vector3i(5, 5, 0)
	assert_eq(rules.evaluate(state), GameModeRules.Outcome.VICTORY, "ally on the throne wins")
