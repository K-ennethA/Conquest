extends GutTest

# Tests for Mycothrall, the Hollowing -- the parasite that infests, drains, and
# HIJACKS its host -- and the three engine capabilities its kit needed:
#   1. STATUS-SOURCED damage reduction: a StatusCondition can carry a
#      `damage_taken_scale`, aggregated "take the strongest" (min, NOT a product),
#      and combined multiplicatively with the defender's passive scale (Braced).
#   2. LIFESTEAL on DamageEffect: heal the caster a fraction of what it dealt
#      (Siphon Bite); 0.0 is a regression-safe no-op.
#   3. INFECTION -> MIND CONTROL: an Infested stacking counter that promotes to
#      Enthralled (the "controlled" rule flag), the AI allegiance inversion that
#      turns a controlled unit on its own side, and the turn-system latch that makes
#      control last EXACTLY one turn (the anti-lockout, in BOTH turn systems).
#
# Mock style mirrors test_eldroot.gd / test_blightcap.gd. The turn-flow tests build
# real Units, Players and turn systems because that is the machinery under test.

# --- Mocks -----------------------------------------------------------------

## A duck-typed unit with a REAL StatusController, so status rule flags, stacking,
## and the status damage-reduction aggregate all resolve through the production path.
## `controlled_override` stands in for the live control state in the planner test;
## `passive_scale` gives it a defender-side passive reduction for the multiply test.
class Thrall:
	var team: int
	var stats: Dictionary
	var hp: int
	var max_health: int
	var controlled_override: bool = false
	var passive_scale: float = 1.0
	var _sc: StatusController
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		max_health = int(stats.get("health", 100))
		hp = max_health
		_sc = StatusController.new()
		_sc.owner_unit = self
	func get_stat(n: String) -> int:
		return int(stats.get(n, 0))
	func get_base_stat(n: String) -> int:
		return int(stats.get(n, 0))
	func get_hp() -> int:
		return hp
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
	func get_status_controller() -> StatusController:
		return _sc
	func is_controlled() -> bool:
		return controlled_override or _sc.has_rule_flag(&"controlled")
	func status_damage_taken_scale() -> float:
		return _sc.status_damage_taken_scale()
	func passive_modifiers(_u = null, _b = null) -> Dictionary:
		return { "damage_taken_scale": passive_scale } if passive_scale != 1.0 else {}

## A board that answers the placement / allegiance / reachability queries the effects
## and the planner ask.
class MockBoard:
	var placements: Array = []
	var blocked: Array = []
	var bounds: Rect2i = Rect2i(0, 0, 12, 12)
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
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	func in_bounds(cell: Vector2i) -> bool:
		return bounds.has_point(cell)
	func is_blocked(cell: Vector2i) -> bool:
		return cell in blocked
	func can_fit(unit, anchor: Vector2i) -> bool:
		if not in_bounds(anchor) or is_blocked(anchor):
			return false
		for other in units_at(anchor):
			if other != unit:
				return false
		return true

# --- Content loaders -------------------------------------------------------

func _braced() -> StatusCondition:
	return load("res://game/combat/status/braced.tres") as StatusCondition

func _infested() -> StatusCondition:
	return load("res://game/combat/status/infested.tres") as StatusCondition

func _enthralled() -> StatusCondition:
	return load("res://game/combat/status/enthralled.tres") as StatusCondition

func _parasitic_hold() -> AbilityResource:
	return load("res://game/abilities/parasitic_hold.tres") as AbilityResource

func _infesting_lunge() -> MoveResource:
	return load("res://game/combat/moves/infesting_lunge.tres") as MoveResource

func _siphon_bite() -> MoveResource:
	return load("res://game/combat/moves/siphon_bite.tres") as MoveResource

## The roster entry, or null when its .glb has not been imported by the editor yet.
func _mycothrall() -> CharacterResource:
	var path := "res://game/characters/roster/mycothrall.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as CharacterResource

# --- Setup -----------------------------------------------------------------

func before_each() -> void:
	# CombatServices is a global autoload; clear any board leaked from another test so
	# _tick_unit_turn_start's internal status tick is deterministic (the explicit tick
	# in _open_turn_for is the one under test).
	CombatServices.clear()

func after_each() -> void:
	CombatServices.clear()

# --- Helpers ---------------------------------------------------------------

func _controller_for(unit) -> StatusController:
	var sc := StatusController.new()
	sc.owner_unit = unit
	return sc

## Resolve one MoveEffect from [param caster] onto [param target] through the shared
## pipeline (ENEMY-targeted single cell). Returns the ctx for log inspection.
func _resolve(effect: MoveEffect, board, caster, target) -> MoveContext:
	var cell: Vector2i = board.cell_of(target)
	var move := MoveResource.new()
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 0
	pattern.max_range = 6
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.move_id = &"test_resolve"
	move.targeting = pattern
	var ctx := MoveContext.new(caster, board, move, cell, [cell] as Array[Vector2i])
	effect.apply(ctx)
	return ctx

## HP [param target] loses to one [param effect] resolved from [param caster].
func _hit(effect: DamageEffect, board, caster, target) -> int:
	var before: int = target.hp
	_resolve(effect, board, caster, target)
	return before - target.hp

## A flat DamageEffect that ignores defense (TRUE), so reduction math is exact.
func _true_damage(power: int, lifesteal: float = 0.0) -> DamageEffect:
	var d := DamageEffect.new()
	d.power = power
	d.scaling_stat = ""
	d.category = CombatTypes.DamageCategory.TRUE
	d.lifesteal = lifesteal
	return d

## The InfestEffect wired with the authored Infested / Enthralled statuses.
func _infest_effect() -> InfestEffect:
	var e := InfestEffect.new()
	e.infested = _infested()
	e.enthralled = _enthralled()
	e.control_threshold = 2
	return e

## A minimal melee DamageEffect move (SINGLE, range 1) for planner tests.
func _melee_move() -> MoveResource:
	var move := MoveResource.new()
	move.move_id = &"test_melee"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 1
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	move.effects = [_true_damage(10)]
	return move

## A real Unit with real stats bookkeeping plus a StatusController child, so rule
## flags resolve through the production path (mirrors test_eldroot._real_unit).
func _real_unit(display_name: String) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = display_name
	res.unit_type = "warrior"
	res.max_health = 100
	res.base_speed = 8
	res.movement_range = 3
	u.stats_resource = res
	add_child_autofree(u)
	var controller := StatusController.new()
	controller.name = "StatusController"
	controller.owner_unit = u
	u.add_child(controller)
	return u

## A player owning one real Unit, both registered with [param ts].
func _register_one_unit(ts: TurnSystemBase, unit: Unit, ai: bool = false) -> Player:
	var player := Player.new(1, "Test Player")
	player.is_ai = ai
	player.add_unit(unit)
	ts.register_player(player)
	return player

## Drive the turn-start tick the way a live turn system does, then run the status
## tick with an explicit board (there is no live board in a headless test, so
## _tick_unit_turn_start's own status tick is skipped -- see test_eldroot._open_turn_for).
func _open_turn_for(ts: TurnSystemBase, unit: Unit, board) -> void:
	ts._tick_unit_turn_start(unit)
	var controller = unit.get_status_controller()
	if controller != null:
		controller.tick_all(board)

# ===========================================================================
# MECHANIC 1 -- status-sourced damage reduction (Braced)
# ===========================================================================

func test_braced_reduces_incoming_damage():
	var board := MockBoard.new()
	var caster := Thrall.new(0, {})
	var target := Thrall.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	assert_eq(_hit(_true_damage(20), board, caster, target), 20, "baseline: 20 TRUE damage in full")

	target.get_status_controller().add_status(_braced())
	assert_eq(_hit(_true_damage(20), board, caster, target), 12, "Braced (0.6) takes 40% less -- 20 -> 12")

func test_braced_wears_off_after_one_turn():
	var board := MockBoard.new()
	var caster := Thrall.new(0, {})
	var target := Thrall.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	var sc := target.get_status_controller()
	sc.add_status(_braced())
	assert_eq(_hit(_true_damage(20), board, caster, target), 12, "reduced while Braced")

	sc.tick_all(board)  # 1-turn duration -> expires
	assert_false(sc.has_status(&"braced"), "Braced is a 1-turn buff and wore off")
	assert_eq(_hit(_true_damage(20), board, caster, target), 20, "full damage once it lapses")

func test_re_bracing_refreshes_but_never_deepens():
	# The known-issue fix: a damage-reduction status REFRESHES its timer, it never
	# stacks or compounds. Two applications must not reduce further than one.
	var board := MockBoard.new()
	var caster := Thrall.new(0, {})
	var once := Thrall.new(1, { "health": 100 })
	var twice := Thrall.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(once, Vector2i(1, 0))
	board.place(twice, Vector2i(2, 0))

	once.get_status_controller().add_status(_braced())

	twice.get_status_controller().add_status(_braced())
	twice.get_status_controller().add_status(_braced())
	assert_eq(twice.get_status_controller().stack_count(&"braced"), 1,
		"REFRESH keeps a single instance, no second stack")
	assert_almost_eq(twice.get_status_controller().status_damage_taken_scale(), 0.6, 0.001,
		"and the aggregate is the single 0.6, not 0.36")

	assert_eq(_hit(_true_damage(20), board, caster, twice),
		_hit(_true_damage(20), board, caster, once),
		"bracing twice reduces damage no more than bracing once")

func test_status_reduction_multiplies_with_a_passive_reduction_not_sums():
	# One reduction of EACH source combines multiplicatively: passive x status.
	var board := MockBoard.new()
	var caster := Thrall.new(0, {})
	var target := Thrall.new(1, { "health": 100 })
	target.passive_scale = 0.5  # a defender-side passive damage_taken_scale
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))
	target.get_status_controller().add_status(_braced())  # 0.6 status scale

	# 20 * (0.5 * 0.6) = 20 * 0.3 = 6. A SUM (0.5 + 0.6 = 1.1) would AMPLIFY to 22.
	assert_eq(_hit(_true_damage(20), board, caster, target), 6,
		"passive x status = 0.3 -> 6 damage (multiplied, not summed)")

func test_status_scale_aggregate_takes_the_strongest_not_a_product():
	var unit := Thrall.new(0, { "health": 100 })
	var sc := unit.get_status_controller()
	sc.add_status(_braced())              # 0.6
	var extra := StatusCondition.new()    # a second, DIFFERENT reduction (0.5)
	extra.id = &"test_ward"
	extra.duration_turns = 2
	extra.stacking = StatusCondition.Stacking.REFRESH
	extra.damage_taken_scale = 0.5
	sc.add_status(extra)
	assert_almost_eq(sc.status_damage_taken_scale(), 0.5, 0.001,
		"two different reductions take the STRONGEST (min 0.5), never the product 0.30")

# ===========================================================================
# MECHANIC 2 -- lifesteal (Siphon Bite)
# ===========================================================================

func test_lifesteal_heals_the_caster_for_a_fraction_of_damage_dealt():
	var board := MockBoard.new()
	var caster := Thrall.new(0, { "health": 100 })
	caster.hp = 50  # wounded, so the heal is visible and not capped
	var target := Thrall.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	var dealt: int = _hit(_true_damage(20, 0.5), board, caster, target)
	assert_eq(dealt, 20, "the bite deals 20")
	assert_eq(caster.hp, 60, "and drains half of it back -- 50 + round(20*0.5) = 60")

func test_zero_lifesteal_is_a_no_op():
	var board := MockBoard.new()
	var caster := Thrall.new(0, { "health": 100 })
	caster.hp = 50
	var target := Thrall.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	_hit(_true_damage(20, 0.0), board, caster, target)
	assert_eq(caster.hp, 50, "a 0-lifesteal DamageEffect never touches the caster (regression-safe)")

func test_siphon_bite_is_a_melee_drain():
	var move := _siphon_bite()
	assert_not_null(move, "siphon_bite.tres loads")
	assert_eq(move.targeting.max_range, 1, "melee")
	assert_eq(move.targeting.target_kind, CombatTypes.TargetKind.ENEMY, "aimed at an enemy")
	var damage: DamageEffect = null
	for e in move.effects:
		if e is DamageEffect:
			damage = e as DamageEffect
	assert_not_null(damage, "it deals damage")
	assert_almost_eq(damage.lifesteal, 0.5, 0.001, "and drains about half of it")

# ===========================================================================
# MECHANIC 3 -- infection -> control
# ===========================================================================

func test_two_attacks_infest_then_seize_control():
	var board := MockBoard.new()
	var myco := Thrall.new(0, { "attack": 12 })
	var victim := Thrall.new(1, { "health": 100 })
	board.place(myco, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	var sc := victim.get_status_controller()

	var effect := _infest_effect()

	# First attack: one Infested stack, not yet controlled.
	_resolve(effect, board, myco, victim)
	assert_eq(sc.stack_count(&"infested"), 1, "the first hit plants one Infested stack")
	assert_false(sc.has_rule_flag(&"controlled"), "one stack is not control yet")

	# Second attack: the counter is spent and the victim is Enthralled.
	_resolve(effect, board, myco, victim)
	assert_eq(sc.stack_count(&"infested"), 0, "the second hit CLEARS the infestation counter")
	assert_true(sc.has_status(&"enthralled"), "and applies Enthralled")
	assert_true(sc.has_rule_flag(&"controlled"), "so the victim now carries the controlled rule flag")
	assert_true(victim.is_controlled(), "and reports itself controlled")

func test_parasitic_hold_seizes_control_over_two_attacks_end_to_end():
	# The full ON_ATTACK path: the ability fires against the unit the parasite just hit,
	# with no extra plumbing (targets_triggering_unit), and two hits hand it over.
	var board := MockBoard.new()
	var myco := Thrall.new(0, { "attack": 12 })
	var victim := Thrall.new(1, { "health": 100 })
	board.place(myco, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))

	var sys: AbilitySystem = autofree(AbilitySystem.new())
	sys.owner_unit = myco
	sys.add_ability(_parasitic_hold())
	var sc := victim.get_status_controller()

	sys.trigger(AbilityTrigger.Trigger.ON_ATTACK, myco, board, victim)
	assert_eq(sc.stack_count(&"infested"), 1, "first attack infests once")
	assert_false(victim.is_controlled(), "not controlled after one")

	sys.trigger(AbilityTrigger.Trigger.ON_ATTACK, myco, board, victim)
	assert_true(victim.is_controlled(), "the second attack seizes control")
	assert_eq(sc.stack_count(&"infested"), 0, "spending the counter")

func test_seizing_control_announces_the_betrayal():
	var board := MockBoard.new()
	var myco := Thrall.new(0, { "attack": 12 })
	var victim := Thrall.new(1, { "health": 100 })
	board.place(myco, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))

	var seen := { "count": 0, "unit": null, "source": null }
	var on_controlled := func(u, s):
		seen["count"] = int(seen["count"]) + 1
		seen["unit"] = u
		seen["source"] = s
	GameEvents.unit_controlled.connect(on_controlled)

	var effect := _infest_effect()
	_resolve(effect, board, myco, victim)   # no promotion yet
	assert_eq(int(seen["count"]), 0, "no announcement on the first infestation")
	_resolve(effect, board, myco, victim)   # promotion
	assert_eq(int(seen["count"]), 1, "the takeover fires unit_controlled exactly once")
	assert_eq(seen["unit"], victim, "naming the hijacked unit")
	assert_eq(seen["source"], myco, "and the parasite that did it")

	GameEvents.unit_controlled.disconnect(on_controlled)

func test_a_controlled_unit_attacks_an_ally_not_an_enemy():
	var board := MockBoard.new()
	var actor := Thrall.new(0, { "attack": 12, "health": 100 })
	var ally := Thrall.new(0, { "health": 100 })
	var enemy := Thrall.new(1, { "health": 100 })
	board.place(actor, Vector2i(5, 5))
	board.place(ally, Vector2i(6, 5))    # adjacent friend
	board.place(enemy, Vector2i(4, 5))   # adjacent foe

	var bot := BotController.new()

	# BASELINE: a normal actor targets the enemy.
	var normal: Dictionary = bot.decide(actor, [_melee_move()], board)
	assert_eq(normal.get("target"), enemy, "uncontrolled, it strikes the enemy")

	# CONTROLLED: allegiance inverts -- it turns on its own ally.
	actor.controlled_override = true
	var hijacked: Dictionary = bot.decide(actor, [_melee_move()], board)
	assert_eq(hijacked.get("target"), ally, "controlled, it strikes its ALLY instead")
	assert_true(board.are_allies(actor, hijacked.get("target")), "the victim really is on its own side")

func test_a_controlled_casters_enemy_move_actually_lands_on_the_ally():
	# The execution half of the inversion: gather_targets flips ENEMY<->ALLY for a
	# controlled caster, so the forced attack deals real damage to the ally.
	var board := MockBoard.new()
	var actor := Thrall.new(0, { "attack": 12 })
	actor.controlled_override = true
	var ally := Thrall.new(0, { "health": 100 })
	var enemy := Thrall.new(1, { "health": 100 })
	board.place(actor, Vector2i(0, 0))
	board.place(ally, Vector2i(1, 0))
	board.place(enemy, Vector2i(0, 1))

	# Resolve an ENEMY-targeted damage effect aimed at the ally's cell.
	var move := MoveResource.new()
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 0
	pattern.max_range = 3
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.move_id = &"test_enemy_move"
	move.targeting = pattern
	var acell: Vector2i = board.cell_of(ally)
	var ctx := MoveContext.new(actor, board, move, acell, [acell] as Array[Vector2i])
	_true_damage(15).apply(ctx)

	assert_eq(ally.hp, 85, "the controlled unit's ENEMY move struck its ally for 15")
	assert_eq(enemy.hp, 100, "and its real enemy was spared")

# --- The anti-lockout: control lasts EXACTLY one turn, in BOTH turn systems --

func test_control_is_forced_then_expires_traditional():
	# THE LOCKOUT BUG, PINNED (mirror of the stun expiry test). A control that
	# prevented its own expiry would puppet the unit forever.
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Hollowed One")
	var player := _register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))

	ts.is_active = true
	ts.current_player = player
	ts.is_turn_in_progress = true

	unit.get_status_controller().add_status(_enthralled())
	assert_true(unit.is_controlled(), "the hijack is on")

	# Turn N: barred from the player (force-driven instead), Enthralled ticks away.
	_open_turn_for(ts, unit, board)
	assert_true(ts.is_turn_forced_control(unit), "turn N: latched as controlled this turn")
	assert_false(ts.can_unit_act(unit), "turn N: the player cannot command it")
	assert_false(unit.is_controlled(), "and the control expired during the turn it cost")

	# Turn N+1: nothing to latch, so the unit is its own again.
	ts.current_turn += 1
	unit.reset_turn_actions()
	_open_turn_for(ts, unit, board)
	assert_false(ts.is_turn_forced_control(unit), "turn N+1: no longer controlled")
	assert_true(ts.can_unit_act(unit), "turn N+1: actable again -- no permanent puppet")

func test_control_is_forced_then_expires_speed_first():
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	var unit := _real_unit("Hollowed One")
	_register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))

	ts.is_active = true
	ts.is_turn_in_progress = true
	ts.current_acting_unit = unit

	unit.get_status_controller().add_status(_enthralled())
	_open_turn_for(ts, unit, board)
	assert_true(ts.is_turn_forced_control(unit), "round N: latched as controlled")
	assert_false(ts.can_unit_act(unit), "round N: the player cannot command it")
	assert_false(unit.is_controlled(), "and control ran out during it")

	ts.current_turn += 1
	unit.reset_turn_actions()
	ts.current_acting_unit = unit
	_open_turn_for(ts, unit, board)
	assert_false(ts.is_turn_forced_control(unit), "round N+1: free")
	assert_true(ts.can_unit_act(unit), "round N+1: actable again")

func test_a_controlled_unit_stays_registered_so_its_status_can_tick():
	# The mechanism behind the no-lockout guarantee, exactly as for stun: gate it OUT
	# of acting, never drop it from the turn system (dropping it would freeze the tick
	# that expires the control).
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Hollowed One")
	var player := _register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	ts.is_active = true
	ts.current_player = player
	ts.is_turn_in_progress = true

	unit.get_status_controller().add_status(_enthralled())
	_open_turn_for(ts, unit, board)

	assert_true(unit in ts.registered_units, "still registered with the turn system")
	assert_true(unit in ts.get_units_for_player(player), "still one of the player's units")

func test_control_latch_is_cleared_on_reset():
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Hollowed One")
	var player := _register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	ts.is_active = true
	ts.current_player = player
	ts.is_turn_in_progress = true

	unit.get_status_controller().add_status(_enthralled())
	_open_turn_for(ts, unit, board)
	assert_true(ts.is_turn_forced_control(unit), "control is latched")

	ts.clear_turn_tick_state()
	assert_false(ts.is_turn_forced_control(unit), "reset clears the control latch")

# ===========================================================================
# CONTENT -- the authored statuses, ability, moves and character
# ===========================================================================

func test_braced_status_values():
	var braced := _braced()
	assert_eq(braced.id, &"braced")
	assert_eq(braced.duration_turns, 1, "a one-turn defensive buff")
	assert_eq(braced.stacking, StatusCondition.Stacking.REFRESH,
		"REFRESH so re-applying only refreshes the timer -- never deepens the reduction")
	assert_almost_eq(braced.damage_taken_scale, 0.6, 0.001, "takes 40% less")
	assert_false(bool(braced.rule_flags.get("controlled", false)), "it is not a control status")

func test_infested_is_an_inert_two_stack_counter():
	var infested := _infested()
	assert_eq(infested.id, &"infested")
	assert_eq(infested.stacking, StatusCondition.Stacking.STACK, "it stacks")
	assert_eq(infested.max_stacks, 2, "toward control at two stacks")
	assert_eq(infested.tick_effects.size(), 0, "and does no damage on its own -- a pure counter")
	assert_almost_eq(infested.damage_taken_scale, 1.0, 0.001, "and no reduction")

func test_enthralled_is_a_one_turn_control_status():
	var enthralled := _enthralled()
	assert_eq(enthralled.id, &"enthralled")
	assert_eq(enthralled.duration_turns, 1, "exactly one hijacked turn")
	assert_true(bool(enthralled.rule_flags.get("controlled", false)),
		"it declares the controlled rule flag")

func test_parasitic_hold_infests_on_every_attack():
	var ability := _parasitic_hold()
	assert_not_null(ability, "parasitic_hold.tres loads")
	assert_eq(ability.id, &"parasitic_hold")
	assert_eq(ability.trigger, AbilityTrigger.Trigger.ON_ATTACK, "it fires when the parasite attacks")
	assert_true(ability.targets_triggering_unit, "and reaches the unit it just hit")
	assert_eq(ability.cooldown, 0, "on every attack, no cooldown")
	var infest: InfestEffect = null
	for e in ability.effects:
		if e is InfestEffect:
			infest = e as InfestEffect
	assert_not_null(infest, "it carries the InfestEffect")
	assert_eq(infest.infested.id, &"infested", "wired to the Infested counter")
	assert_eq(infest.enthralled.id, &"enthralled", "and the Enthralled control status")
	assert_eq(infest.control_threshold, 2, "two stacks seize control")

func test_infesting_lunge_leaps_strikes_and_self_braces():
	var move := _infesting_lunge()
	assert_not_null(move, "infesting_lunge.tres loads")
	assert_eq(move.cooldown, 2, "on a cooldown")
	assert_gt(move.targeting.max_range, 1, "and reaches further than melee")
	assert_true(move.targeting.requires_empty_cell, "it lands on a free cell")
	assert_true(move.targeting.requires_adjacent_enemy, "beside its prey (the Spore Leap targeting)")
	assert_true(move.effects[0] is LeapEffect, "the leap resolves FIRST")

	var has_damage := false
	var self_brace: ApplyStatusEffect = null
	for e in move.effects:
		if e is DamageEffect:
			has_damage = true
		if e is ApplyStatusEffect and (e as ApplyStatusEffect).condition != null \
			and (e as ApplyStatusEffect).condition.id == &"braced":
			self_brace = e as ApplyStatusEffect
	assert_true(has_damage, "it strikes on arrival")
	assert_not_null(self_brace, "and grants Braced")
	assert_true(self_brace.to_caster, "to the CASTER (a self-buff on an enemy-targeted move)")

func test_infesting_lunge_actually_braces_the_caster():
	# End to end: the self-application really lands Braced on the caster.
	var board := MockBoard.new()
	var caster := Thrall.new(0, { "health": 100 })
	board.place(caster, Vector2i(0, 0))

	var move := _infesting_lunge()
	var brace: ApplyStatusEffect = null
	for e in move.effects:
		if e is ApplyStatusEffect:
			brace = e as ApplyStatusEffect
	assert_not_null(brace, "the move has the brace effect")

	var ctx := MoveContext.new(caster, board, move, Vector2i(0, 0), [Vector2i(0, 0)] as Array[Vector2i])
	brace.apply(ctx)
	assert_true(caster.get_status_controller().has_status(&"braced"),
		"the caster braced itself")

func test_mycothrall_character_sheet():
	var myco := _mycothrall()
	if myco == null:
		pending("mycothrall.tres not loadable yet (its .glb needs an editor import); skipping.")
		return

	assert_eq(myco.character_id, &"mycothrall", "stable id")
	assert_eq(myco.display_name, "Mycothrall, the Hollowing", "display name")
	assert_ne(myco.description, "", "it has flavour")
	assert_eq(myco.footprint, Vector2i(1, 1), "a one-cell skirmisher")
	assert_false(myco.is_boss, "not a boss")
	assert_eq(myco.attack_range, 1, "melee")
	assert_eq(myco.min_difficulty, 2, "authored Hard+")
	assert_eq(myco.get_min_difficulty(), 2, "and reports it")

	var move_ids: Array[StringName] = []
	for m in myco.moveset:
		move_ids.append(m.move_id)
	assert_eq(myco.moveset.size(), 2, "two moves")
	assert_true(&"infesting_lunge" in move_ids, "it knows Infesting Lunge")
	assert_true(&"siphon_bite" in move_ids, "and Siphon Bite")

	assert_eq(myco.abilities.size(), 1, "one ability")
	assert_eq(myco.abilities[0].id, &"parasitic_hold", "Parasitic Hold")

	# A fast, fragile skirmisher relative to the tanky Blightcap.
	var blightcap := load("res://game/characters/roster/blightcap.tres") as CharacterResource
	if blightcap != null:
		assert_lt(myco.base_health, blightcap.base_health, "more fragile than Blightcap")
		assert_gt(myco.base_speed, blightcap.base_speed, "and much faster")

func test_mycothrall_is_gated_below_hard():
	var myco := _mycothrall()
	if myco == null:
		pending("mycothrall.tres not loadable yet; the boot test covers the live gate.")
		return
	var loader = autofree(MapLoader.new())
	var diff: int = loader._current_ai_difficulty()
	var allowed: bool = loader._difficulty_allows(myco)
	assert_eq(allowed, diff >= 2, "a min_difficulty-2 character is allowed iff the game is Hard+")
	if diff < 2:
		assert_false(allowed, "so it is gated out below Hard")

func test_authored_statuses_are_discoverable_by_the_catalog():
	StatusCatalog.rescan()
	assert_not_null(StatusCatalog.find_by_id(&"braced"), "Braced resolves by id")
	assert_not_null(StatusCatalog.find_by_id(&"infested"), "Infested resolves by id")
	assert_not_null(StatusCatalog.find_by_id(&"enthralled"), "Enthralled resolves by id")
