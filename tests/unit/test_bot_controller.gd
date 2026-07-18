extends GutTest

# Tests for the bot / boss AI planners. Uses the same MockUnit / MockBoard duck
# typing as test_move_system.gd, extended with the board-query helpers the bot
# expects (all_units) and a unit `is_boss` flag.

# --- Mocks -----------------------------------------------------------------

class MockUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var is_boss: bool = false
	func _init(p_team: int, p_stats: Dictionary, p_boss: bool = false) -> void:
		team = p_team
		stats = p_stats
		hp = stats.get("health", 100)
		is_boss = p_boss
	func get_stat(name: String) -> int:
		return stats.get(name, 0)
	func take_damage(n: int) -> void:
		hp -= n

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

# --- Bot: target selection -------------------------------------------------

func test_bot_picks_higher_damage_target():
	# Two enemies in reach. enemy_soft has no defense, enemy_tank mitigates most
	# of the hit. The bot should aim at the target it can hurt the most.
	var actor := MockUnit.new(0, { "attack": 10 })
	var enemy_soft := MockUnit.new(1, { "health": 100, "defense": 0 })
	var enemy_tank := MockUnit.new(1, { "health": 100, "defense": 20 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy_soft, Vector2i(1, 0))   # range 1
	board.place(enemy_tank, Vector2i(0, 1))   # range 1
	var bot := BotController.new()
	var decision := bot.decide(actor, [MoveLibrary.basic_strike()], board)
	assert_eq(decision["action"], BotController.ActionType.MOVE, "chooses to attack")
	assert_eq(decision["target"], enemy_soft, "targets the softer enemy")
	# power 24 + attack 10 = 34, unmitigated
	assert_eq(decision["estimated_damage"], 34, "estimates full damage on soft target")

func test_bot_steps_toward_nearest_enemy_when_out_of_range():
	var actor := MockUnit.new(0, { "attack": 10 })
	var enemy := MockUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(5, 0))  # range 5, strike only reaches 1
	var bot := BotController.new()
	var decision := bot.decide(actor, [MoveLibrary.basic_strike()], board)
	assert_eq(decision["action"], BotController.ActionType.STEP, "advances when nothing in range")
	assert_eq(decision["step_to"], Vector2i(1, 0), "steps one cell toward the enemy")

func test_bot_waits_when_no_hostiles():
	var actor := MockUnit.new(0, { "attack": 10 })
	var ally := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(ally, Vector2i(1, 0))
	var bot := BotController.new()
	var decision := bot.decide(actor, [MoveLibrary.basic_strike()], board)
	assert_eq(decision["action"], BotController.ActionType.WAIT, "no enemies -> wait")

# --- Boss: faction-agnostic hostility --------------------------------------

func test_boss_treats_both_factions_as_targets():
	# Boss is team 0. One target shares its team (an ally to a normal bot), the
	# other is team 1. A boss must be willing to attack BOTH.
	var boss := MockUnit.new(0, { "attack": 10, "health": 200 }, true)
	var same_team := MockUnit.new(0, { "health": 100, "defense": 0 })   # soft
	var other_team := MockUnit.new(1, { "health": 100, "defense": 30 }) # tanky
	var board := MockBoard.new()
	board.place(boss, Vector2i(0, 0))
	board.place(same_team, Vector2i(1, 0))
	board.place(other_team, Vector2i(0, 1))

	var boss_ai := BossController.new()
	assert_eq(boss_ai._list_hostiles(boss, board).size(), 2, "boss sees both factions as hostile")
	var decision := boss_ai.decide(boss, [MoveLibrary.basic_strike()], board)
	assert_eq(decision["action"], BotController.ActionType.MOVE, "boss attacks")
	assert_eq(decision["target"], same_team, "boss attacks its own faction when that deals more damage")

	# A plain bot only recognizes the opposing faction.
	var bot := BotController.new()
	assert_eq(bot._list_hostiles(boss, board).size(), 1, "plain bot only sees the enemy faction")

# --- Boss: phases ----------------------------------------------------------

func test_boss_phase_advances_with_lost_hp_and_is_monotonic():
	var boss_ai := BossController.new()
	boss_ai.phase_thresholds = [0.66, 0.33]
	var boss := MockUnit.new(0, { "health": 100 }, true)

	boss.hp = 80  # 80% -> phase 0
	boss_ai._advance_phase(boss)
	assert_eq(boss_ai.current_phase, 0, "above first threshold stays phase 0")

	boss.hp = 50  # 50% -> phase 1
	boss_ai._advance_phase(boss)
	assert_eq(boss_ai.current_phase, 1, "crossing 66% -> phase 1")

	boss.hp = 20  # 20% -> phase 2
	boss_ai._advance_phase(boss)
	assert_eq(boss_ai.current_phase, 2, "crossing 33% -> phase 2")

	boss.hp = 100  # healed back up
	boss_ai._advance_phase(boss)
	assert_eq(boss_ai.current_phase, 2, "phase never regresses when healed")

func test_boss_unlocks_special_move_in_later_phase():
	# Phase 1 unlocks a heavy long-range move that out-damages the basic strike
	# and can reach a target the strike cannot.
	var heavy := MoveLibrary.flame_burst()  # range up to 3, magical
	var boss_ai := BossController.new()
	boss_ai.phase_thresholds = [0.5]
	boss_ai.phase_special_moves = [[], [heavy]]  # phase 0: none, phase 1: heavy

	var boss := MockUnit.new(0, { "attack": 10, "magic": 10, "health": 100 }, true)
	boss.hp = 40  # 40% -> phase 1
	var enemy := MockUnit.new(1, { "health": 100, "defense": 0 }, false)
	var board := MockBoard.new()
	board.place(boss, Vector2i(0, 0))
	board.place(enemy, Vector2i(3, 0))  # out of strike range (1), in flame range (3)

	var decision := boss_ai.decide(boss, [MoveLibrary.basic_strike()], board)
	assert_eq(boss_ai.current_phase, 1, "boss entered phase 1")
	assert_eq(decision["action"], BotController.ActionType.MOVE, "special move lets the boss attack")
	assert_eq(decision["move"].move_id, &"flame_burst", "boss uses the unlocked special move")
