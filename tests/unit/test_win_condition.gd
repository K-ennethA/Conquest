extends GutTest

# Tests for the modular win-condition framework and the GameModeRules bundle.
# Uses lightweight mocks (no scene tree / live board), matching the style of
# test_move_system.gd.

# --- Mocks -----------------------------------------------------------------

class MockUnit:
	var team: int
	var hp: int
	var unit_id: StringName
	func _init(p_team: int, p_hp: int = 100, p_id: StringName = &"") -> void:
		team = p_team
		hp = p_hp
		unit_id = p_id

class MockBoard:
	var placements: Array = []  # { unit, cell }
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)
	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out

# --- DefeatAllEnemies ------------------------------------------------------

func test_defeat_all_met_when_no_enemies_remain():
	var cond := DefeatAllEnemies.new()
	cond.faction = 0
	var ally := MockUnit.new(0, 100)
	var enemy := MockUnit.new(1, 0)  # dead
	var state := { "units": [ally, enemy] }
	assert_eq(cond.evaluate(state), WinCondition.Status.MET, "all enemies down -> MET")

func test_defeat_all_ongoing_while_enemy_alive():
	var cond := DefeatAllEnemies.new()
	cond.faction = 0
	var ally := MockUnit.new(0, 100)
	var enemy := MockUnit.new(1, 40)  # alive
	var state := { "units": [ally, enemy] }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "living enemy -> ONGOING")

# --- CaptureThrone ---------------------------------------------------------

func test_capture_throne_met_when_right_faction_on_cell():
	var cond := CaptureThrone.new()
	cond.faction = 0
	cond.target_cell = Vector2i(5, 5)
	var ally := MockUnit.new(0, 100)
	var board := MockBoard.new()
	board.place(ally, Vector2i(5, 5))
	var state := { "board": board, "units": board.all_units() }
	assert_eq(cond.evaluate(state), WinCondition.Status.MET, "ally on throne -> MET")

func test_capture_throne_ongoing_when_enemy_holds_cell():
	var cond := CaptureThrone.new()
	cond.faction = 0
	cond.target_cell = Vector2i(5, 5)
	var enemy := MockUnit.new(1, 100)
	var ally := MockUnit.new(0, 100)
	var board := MockBoard.new()
	board.place(enemy, Vector2i(5, 5))
	board.place(ally, Vector2i(0, 0))
	var state := { "board": board, "units": board.all_units() }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "enemy on throne -> ONGOING")

func test_capture_throne_ignores_dead_holder():
	var cond := CaptureThrone.new()
	cond.faction = 0
	cond.target_cell = Vector2i(2, 2)
	var dead_ally := MockUnit.new(0, 0)
	var board := MockBoard.new()
	board.place(dead_ally, Vector2i(2, 2))
	var state := { "board": board, "units": board.all_units() }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "dead ally does not capture")

# --- SurviveTurns ----------------------------------------------------------

func test_survive_turns_met_at_target_turn():
	var cond := SurviveTurns.new()
	cond.turns = 3
	cond.faction = 0
	var ally := MockUnit.new(0, 100)
	assert_eq(cond.evaluate({ "units": [ally], "turn": 3 }), WinCondition.Status.MET, "reached turn -> MET")
	assert_eq(cond.evaluate({ "units": [ally], "turn": 2 }), WinCondition.Status.ONGOING, "before turn -> ONGOING")

func test_survive_turns_failed_when_faction_wiped():
	var cond := SurviveTurns.new()
	cond.turns = 5
	cond.faction = 0
	cond.require_survivor = true
	var dead := MockUnit.new(0, 0)
	assert_eq(cond.evaluate({ "units": [dead], "turn": 1 }), WinCondition.Status.FAILED, "no survivors -> FAILED")

# --- ProtectUnit -----------------------------------------------------------

func test_protect_unit_ongoing_while_alive_failed_when_dead():
	var cond := ProtectUnit.new()
	cond.protected_id = &"vip"
	var vip_alive := MockUnit.new(0, 100, &"vip")
	assert_eq(cond.evaluate({ "units": [vip_alive] }), WinCondition.Status.ONGOING, "vip alive -> ONGOING")
	var vip_dead := MockUnit.new(0, 0, &"vip")
	assert_eq(cond.evaluate({ "units": [vip_dead] }), WinCondition.Status.FAILED, "vip dead -> FAILED")
	assert_eq(cond.evaluate({ "units": [] }), WinCondition.Status.FAILED, "vip missing -> FAILED")

# --- GameModeRules ---------------------------------------------------------

func test_rules_victory_when_win_condition_met():
	var rules := GameModeRules.new()
	var win := DefeatAllEnemies.new()
	win.faction = 0
	rules.win_conditions = [win]
	var ally := MockUnit.new(0, 100)
	var enemy := MockUnit.new(1, 0)  # dead
	assert_eq(rules.evaluate({ "units": [ally, enemy] }), GameModeRules.Outcome.VICTORY, "enemies gone -> VICTORY")

func test_rules_defeat_when_win_condition_failed():
	var rules := GameModeRules.new()
	var protect := ProtectUnit.new()
	protect.protected_id = &"vip"
	rules.win_conditions = [protect]
	var vip_dead := MockUnit.new(0, 0, &"vip")
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
	var enemy := MockUnit.new(1, 100)
	var board := MockBoard.new()
	board.place(enemy, Vector2i(0, 0))
	var state := { "board": board, "units": board.all_units(), "turn": 1 }
	assert_eq(rules.evaluate(state), GameModeRules.Outcome.DEFEAT, "enemy captured home -> DEFEAT")

func test_rules_ongoing_and_flags_default_off():
	var rules := GameModeRules.new()
	var win := DefeatAllEnemies.new()
	win.faction = 0
	rules.win_conditions = [win]
	var ally := MockUnit.new(0, 100)
	var enemy := MockUnit.new(1, 50)  # alive
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
	var ally := MockUnit.new(0, 100)
	var enemy := MockUnit.new(1, 0)  # dead: defeat_all MET, but not enough turns
	assert_eq(rules.evaluate({ "units": [ally, enemy], "turn": 2 }), GameModeRules.Outcome.ONGOING, "one of two met -> ONGOING")
	assert_eq(rules.evaluate({ "units": [ally, enemy], "turn": 5 }), GameModeRules.Outcome.VICTORY, "both met -> VICTORY")
