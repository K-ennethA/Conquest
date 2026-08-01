extends GutTest

## Regression for the "enemy re-cast a cooldown move (Strangling Roots) every turn" bug.
##
## The AI's attack ranking (_ranked_attacks / _ranked_attacks_from_cells) never consulted
## the actor's MovesetController, so a DAMAGING move on cooldown stayed the top pick even
## though the AI's cast starts its cooldown (BotTurnDriver calls MovesetController.on_used
## after perform_move, exactly as the human UI does). The planner now skips a damaging move
## while it is on cooldown -- the same can_use gate the support and trap branches already
## used -- so a cooldown move is cast once, then withheld until it recharges.
##
## These tests drive a REAL MovesetController: ready -> the planner attacks; after the cast
## (on_used) the same move is refused and the planner advances/idles instead.

# --- Mocks -----------------------------------------------------------------

class MockUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var mc  # a real MovesetController (or null -> "everything ready")
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))
	func get_stat(name: String) -> int:
		return int(stats.get(name, 0))
	func get_hp() -> int:
		return hp
	func take_damage(n: int) -> void:
		hp -= n
	func get_moveset_controller():
		return mc

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


## A range-1 melee strike with an authored cooldown, built in code (no .tres load).
func _strike(power: int, cd: int) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_strike_cd"
	m.display_name = "Test Strike"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.cooldown = cd
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = power
	d.scaling_stat = ""
	d.scale = 0.0
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


func _adjacent_fight() -> Dictionary:
	var actor := MockUnit.new(0, { "attack": 10 })
	var enemy := MockUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))  # adjacent -> a range-1 strike reaches it
	return { "actor": actor, "enemy": enemy, "board": board }


# --- plan(): movement-aware planner ----------------------------------------

func test_plan_skips_damaging_move_on_cooldown():
	var mc = autofree(MovesetController.new())
	var scene := _adjacent_fight()
	var actor = scene["actor"]
	actor.mc = mc
	var move := _strike(20, 3)
	var bot := BotController.new()

	# Ready -> the planner casts it.
	var d1 := bot.plan(actor, [move], scene["board"], [])
	assert_eq(d1["action"], BotController.ActionType.MOVE, "a ready move is cast")
	assert_eq(d1["move"], move, "and it is the strike")

	# The AI cast starts the cooldown (mirrors BotTurnDriver's on_used after perform_move).
	mc.on_used(move)
	assert_false(mc.can_use(move), "the cast put the move on cooldown")

	# On cooldown -> the planner refuses to re-cast it (no MOVE decision this turn).
	var d2 := bot.plan(actor, [move], scene["board"], [])
	assert_ne(d2["action"], BotController.ActionType.MOVE, "a move on cooldown is not re-cast")


# --- decide(): single-step planner -----------------------------------------

func test_decide_skips_damaging_move_on_cooldown():
	var mc = autofree(MovesetController.new())
	var scene := _adjacent_fight()
	var actor = scene["actor"]
	actor.mc = mc
	var move := _strike(20, 3)
	var bot := BotController.new()

	var d1 := bot.decide(actor, [move], scene["board"])
	assert_eq(d1["action"], BotController.ActionType.MOVE, "a ready move is cast")

	mc.on_used(move)
	var d2 := bot.decide(actor, [move], scene["board"])
	assert_ne(d2["action"], BotController.ActionType.MOVE, "a move on cooldown is not re-cast (it advances instead)")


# --- Recovery: usable again once the cooldown ticks out --------------------

func test_move_usable_again_after_cooldown_expires():
	var mc = autofree(MovesetController.new())
	var scene := _adjacent_fight()
	var actor = scene["actor"]
	actor.mc = mc
	var move := _strike(20, 2)
	var bot := BotController.new()

	mc.on_used(move)  # cooldown 2
	assert_eq(bot.plan(actor, [move], scene["board"], [])["action"], BotController.ActionType.WAIT, "withheld while on cooldown")
	mc.tick_cooldowns()
	mc.tick_cooldowns()
	var d := bot.plan(actor, [move], scene["board"], [])
	assert_eq(d["action"], BotController.ActionType.MOVE, "cast again once the cooldown has ticked out")
	assert_eq(d["move"], move, "the recharged strike is chosen")


# --- Regression: a cooldown-0 move is never withheld -----------------------

func test_zero_cooldown_move_is_always_available():
	var mc = autofree(MovesetController.new())
	var scene := _adjacent_fight()
	var actor = scene["actor"]
	actor.mc = mc
	var move := _strike(20, 0)
	var bot := BotController.new()

	mc.on_used(move)  # no cooldown -> stays ready
	var d := bot.plan(actor, [move], scene["board"], [])
	assert_eq(d["action"], BotController.ActionType.MOVE, "a cooldown-0 move is available every turn")
