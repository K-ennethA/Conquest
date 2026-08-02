extends GutTest

# Tests for Blightcap -- the poisonous mushroom grunt -- and the three engine
# capabilities its kit needed:
#   1. an ON_DEATH ability trigger, raised while the DYING unit is still on its
#      cell (a death burst needs an origin to explode from)
#   2. LeapEffect, the first effect that relocates the CASTER, plus the targeting
#      constraints that let the EXISTING aim UI choose which side it lands on
#   3. bounded status stacking (StatusCondition.max_stacks) and a data-driven
#      chance on ApplyStatusEffect
#
# Mock style mirrors test_petalfang.gd / test_status_condition.gd. The ON_DEATH
# tests deliberately use a LIVE board (real Unit, real CombatServices/BoardAdapter,
# as tests/integration/test_ai_live_board.gd does) because the whole claim under
# test is about where in Unit._on_unit_died the trigger fires -- a mock could not
# tell a safe firing point from an unsafe one.

const GRID: Grid = preload("res://board/Grid.tres")

# --- Mocks -----------------------------------------------------------------

## A duck-typed unit, as small as each test needs.
class MockUnit:
	var team: int
	var stats: Dictionary
	var max_health: int
	var hp: int
	var statuses: Array = []
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		max_health = int(stats.get("health", 100))
		hp = max_health
	func get_stat(n: String) -> int:
		return stats.get(n, 0)
	func get_base_stat(n: String) -> int:
		return stats.get(n, 0)
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
	func add_status(condition) -> void:
		statuses.append(condition)

## A board that can answer the placement questions LeapEffect and the leap's
## targeting constraints ask: bounds, blocking terrain, occupancy, footprint fit.
class MockBoard:
	var placements: Array = []      # { unit, cell }
	var blocked: Array = []         # Array[Vector2i] of impassable cells
	var bounds: Rect2i = Rect2i(0, 0, 10, 10)
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
	func set_tile(_cell: Vector2i, _tile_id) -> void:
		pass
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	func in_bounds(cell: Vector2i) -> bool:
		return bounds.has_point(cell)
	func is_blocked(cell: Vector2i) -> bool:
		return cell in blocked
	func is_occupied(cell: Vector2i) -> bool:
		return not units_at(cell).is_empty()
	func can_fit(unit, anchor: Vector2i) -> bool:
		if not in_bounds(anchor) or is_blocked(anchor):
			return false
		for other in units_at(anchor):
			if other != unit:
				return false
		return true

## An AbilitySystem that records what the world looked like the instant ON_DEATH
## resolved. This is the assertion that matters: a burst fired one step too late
## would see an invalid unit, an untracked cell, or no board entry at all.
class DeathWatcher extends AbilitySystem:
	var death_calls: int = 0
	var kill_calls: int = 0
	var saw_valid: bool = false
	var saw_in_tree: bool = false
	var saw_cell: Vector2i = Vector2i(-999, -999)
	var saw_on_board: bool = false

	func trigger(event: AbilityTrigger.Trigger, unit = null, board = null, other = null) -> Array:
		if event == AbilityTrigger.Trigger.ON_DEATH:
			var acting = unit if unit != null else owner_unit
			death_calls += 1
			saw_valid = acting != null and is_instance_valid(acting)
			saw_in_tree = acting is Node and (acting as Node).is_inside_tree()
			if board != null and board.has_method("cell_of"):
				saw_cell = board.cell_of(acting)
				if board.has_method("units_at"):
					saw_on_board = acting in board.units_at(saw_cell)
		elif event == AbilityTrigger.Trigger.ON_KILL:
			kill_calls += 1
		return super.trigger(event, unit, board, other)

# --- Content fixtures ------------------------------------------------------

func _poisoned() -> StatusCondition:
	return load("res://game/combat/status/poisoned.tres") as StatusCondition

func _sporeleap() -> MoveResource:
	return load("res://game/combat/moves/sporeleap.tres") as MoveResource

func _blight_burst() -> MoveResource:
	return load("res://game/combat/moves/blight_burst.tres") as MoveResource

func _deathbloom() -> AbilityResource:
	return load("res://game/abilities/deathbloom.tres") as AbilityResource

## The Blightcap roster entry, or null when it cannot load (its .glb model has to
## be imported by the editor first). Callers mark themselves pending rather than
## failing the suite on a missing import.
func _blightcap() -> CharacterResource:
	var path := "res://game/characters/roster/blightcap.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as CharacterResource

# --- Helpers ---------------------------------------------------------------

func _controller_for(unit) -> StatusController:
	# autofree: StatusController is a Node -- an untracked one is a GUT orphan.
	var sc: StatusController = autofree(StatusController.new())
	sc.owner_unit = unit
	return sc

## A seeded RNG, so every probability assertion in this file is reproducible.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

## Resolve [param effect] alone against [param target], through the shared
## pipeline, with an optional injected RNG.
func _resolve(effect: MoveEffect, board, caster, target, rng: RandomNumberGenerator = null) -> MoveContext:
	var cell: Vector2i = board.cell_of(target)
	var move := MoveResource.new()
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 0
	pattern.max_range = 5
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.move_id = &"test_resolve"
	move.targeting = pattern
	var ctx := MoveContext.new(caster, board, move, cell, [cell] as Array[Vector2i])
	ctx.rng = rng
	effect.apply(ctx)
	return ctx

## A minimal move that leaps to its aim cell, with no other effects.
func _leap_move(max_range: int = 4) -> MoveResource:
	var move := MoveResource.new()
	move.move_id = &"test_leap"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = max_range
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	move.effects = [LeapEffect.new()]
	return move

## Run a leap move from [param caster] at [param aim] and report where it ended up.
func _leap_to(board, caster, aim: Vector2i) -> Vector2i:
	var move := _leap_move()
	var ctx := MoveContext.new(caster, board, move, aim, [aim] as Array[Vector2i])
	(move.effects[0] as LeapEffect).apply(ctx)
	return board.cell_of(caster)

# --- Live-board helpers (ON_DEATH) -----------------------------------------

var _map_root: Node3D = null

func before_each() -> void:
	# CombatServices is a global autoload; a stale board from another test must
	# never leak in (mirrors tests/integration/test_ai_live_board.gd).
	CombatServices.clear()
	_map_root = null

func after_each() -> void:
	CombatServices.clear()
	_map_root = null

## Cell -> world, via the same GRID CombatServices.rebuild() uses.
func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(GRID, []).cell_to_world(cell)

## A bare live [Unit] at [param cell] with real stat bookkeeping and a
## [DeathWatcher] standing in for its AbilitySystem.
func _spawn_unit(unit_name: String, cell: Vector2i, owner: Player, ability: AbilityResource) -> Unit:
	var unit := Unit.new()
	unit.name = unit_name
	var res := UnitStatsResource.new()
	res.unit_name = unit_name
	res.unit_type = "warrior"
	res.max_health = 60
	res.base_defense = 0     # flat mitigation, so burst damage is exact
	res.base_speed = 8
	res.movement_range = 3
	unit.stats_resource = res
	unit.position = _cell_to_world(cell)
	unit.owner_player = owner
	_map_root.add_child(unit)  # _map_root is in the tree -> _ready() runs now

	var watcher := DeathWatcher.new()
	watcher.name = "AbilitySystem"
	watcher.owner_unit = unit
	if ability != null:
		watcher.add_ability(ability)
	unit.add_child(watcher)
	return unit

## The DeathWatcher attached to [param unit].
func _watcher_of(unit: Unit) -> DeathWatcher:
	return unit.get_node("AbilitySystem") as DeathWatcher

func _begin_live_board() -> void:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

## Install the live BoardAdapter over everything spawned so far.
func _finish_live_board() -> void:
	CombatServices.rebuild(_map_root)

# --- GAP 1: the ON_DEATH trigger -------------------------------------------

func test_on_death_fires_exactly_once_while_the_dying_unit_is_still_placed():
	_begin_live_board()
	var victim := _spawn_unit("Victim", Vector2i(3, 3), Player.new(0, "A"), null)
	_finish_live_board()

	var watcher := _watcher_of(victim)
	victim.take_damage(999)
	# Second lethal hit: _on_unit_died is idempotent via _is_dead, and ON_DEATH
	# must inherit that -- a burst that fired twice would double-kill the board.
	victim.take_damage(999)

	assert_eq(watcher.death_calls, 1, "ON_DEATH fires exactly once, however many times HP hits 0")
	assert_true(watcher.saw_valid, "the dying unit is still a valid instance when ON_DEATH resolves")
	assert_true(watcher.saw_in_tree, "and is still inside the scene tree")
	assert_eq(watcher.saw_cell, Vector2i(3, 3), "and still reports its own cell -- an origin to explode from")
	assert_true(watcher.saw_on_board, "and the board still finds it standing there")

func test_on_death_does_not_fire_for_the_killer():
	_begin_live_board()
	var victim := _spawn_unit("Victim", Vector2i(2, 2), Player.new(0, "A"), null)
	var killer := _spawn_unit("Killer", Vector2i(2, 3), Player.new(1, "B"), null)
	_finish_live_board()

	# Captured before the kill: the victim's node is freed on the way out.
	var victim_watcher := _watcher_of(victim)
	var killer_watcher := _watcher_of(killer)

	victim.take_damage(999)

	assert_eq(victim_watcher.death_calls, 1, "the victim's own ON_DEATH fires")
	assert_eq(killer_watcher.death_calls, 0, "ON_DEATH is the VICTIM's trigger, never the killer's")

func test_on_kill_still_routes_to_the_killer():
	var board := MockBoard.new()
	var killer := MockUnit.new(0, { "health": 100, "attack": 10 })
	var victim := MockUnit.new(1, { "health": 1 })
	board.place(killer, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))

	var sys: AbilitySystem = autofree(AbilitySystem.new())
	sys.owner_unit = killer
	sys.add_ability(AbilityLibrary.vampiric())   # ON_KILL

	killer.hp = 50
	var kill_events: Array = sys.trigger(AbilityTrigger.Trigger.ON_KILL, killer, board, victim)
	assert_gt(kill_events.size(), 0, "an ON_KILL ability still fires on ON_KILL")

	var death_events: Array = sys.trigger(AbilityTrigger.Trigger.ON_DEATH, killer, board, victim)
	assert_eq(death_events.size(), 0, "and does NOT also fire on the new ON_DEATH")

func test_deathbloom_bursts_over_adjacent_enemies_when_it_dies():
	var ability := _deathbloom()
	assert_not_null(ability, "deathbloom.tres loads")
	assert_eq(ability.trigger, AbilityTrigger.Trigger.ON_DEATH, "deathbloom fires on death")
	assert_not_null(ability.targeting, "its radius comes from an authored targeting pattern")

	_begin_live_board()
	var bomb := _spawn_unit("Blightcap", Vector2i(2, 2), Player.new(0, "A"), ability)
	var adjacent := _spawn_unit("Adjacent", Vector2i(2, 3), Player.new(1, "B"), null)
	var distant := _spawn_unit("Distant", Vector2i(0, 0), Player.new(1, "B"), null)
	_finish_live_board()

	var adjacent_before: int = adjacent.current_health
	var distant_before: int = distant.current_health

	bomb.take_damage(999)

	assert_lt(adjacent.current_health, adjacent_before,
		"the burst damages an enemy standing next to the corpse")
	assert_eq(distant.current_health, distant_before,
		"and reaches only as far as its authored radius")

func test_deathbloom_spares_the_dying_units_own_side():
	_begin_live_board()
	var side := Player.new(0, "A")
	var bomb := _spawn_unit("Blightcap", Vector2i(2, 2), side, _deathbloom())
	var ally := _spawn_unit("Ally", Vector2i(2, 3), side, null)
	_finish_live_board()

	var ally_before: int = ally.current_health
	bomb.take_damage(999)
	assert_eq(ally.current_health, ally_before, "the burst targets ENEMY, so allies are untouched")

# --- GAP 2: LeapEffect (relocating the CASTER) -----------------------------

func test_leap_relocates_the_caster_to_a_valid_cell():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	board.place(caster, Vector2i(1, 1))

	assert_eq(_leap_to(board, caster, Vector2i(4, 1)), Vector2i(4, 1), "the caster lands on the aim cell")

func test_leap_logs_the_relocation():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	board.place(caster, Vector2i(1, 1))

	var move := _leap_move()
	var aim := Vector2i(3, 1)
	var ctx := MoveContext.new(caster, board, move, aim, [aim] as Array[Vector2i])
	(move.effects[0] as LeapEffect).apply(ctx)

	assert_eq(ctx.results.size(), 1, "the leap logs exactly one event")
	var event: Dictionary = ctx.results[0]
	assert_eq(event.get("effect", ""), "leap", "tagged as a leap")
	assert_eq(event.get("from", Vector2i.ZERO), Vector2i(1, 1), "records where it left")
	assert_eq(event.get("to", Vector2i.ZERO), aim, "records where it landed")
	assert_true(bool(event.get("moved", false)), "and that it actually moved")

func test_leap_refuses_an_occupied_cell():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	var squatter := MockUnit.new(1, { "health": 100 })
	board.place(caster, Vector2i(1, 1))
	board.place(squatter, Vector2i(3, 1))

	assert_eq(_leap_to(board, caster, Vector2i(3, 1)), Vector2i(1, 1),
		"an occupied destination leaves the caster where it was")

func test_leap_refuses_a_blocked_cell():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	board.place(caster, Vector2i(1, 1))
	board.blocked.append(Vector2i(3, 1))

	assert_eq(_leap_to(board, caster, Vector2i(3, 1)), Vector2i(1, 1),
		"impassable terrain leaves the caster where it was")

func test_leap_refuses_an_out_of_bounds_cell():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	board.place(caster, Vector2i(1, 1))

	assert_eq(_leap_to(board, caster, Vector2i(-4, 1)), Vector2i(1, 1),
		"a cell off the board leaves the caster where it was")

func test_leap_records_a_refusal_rather_than_erroring():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	board.place(caster, Vector2i(1, 1))
	board.blocked.append(Vector2i(2, 1))

	var move := _leap_move()
	var aim := Vector2i(2, 1)
	var ctx := MoveContext.new(caster, board, move, aim, [aim] as Array[Vector2i])
	(move.effects[0] as LeapEffect).apply(ctx)

	assert_eq(ctx.results.size(), 1, "an invalid leap is a logged no-op, not an error")
	var event: Dictionary = ctx.results[0]
	assert_false(bool(event.get("moved", true)), "the log says it did not move")

# --- GAP 2: the landing-cell targeting constraint --------------------------

func test_leap_targeting_only_accepts_cells_beside_an_enemy():
	var move := _sporeleap()
	assert_not_null(move, "sporeleap.tres loads")
	assert_true(move.targeting.requires_empty_cell, "it is aimed at a free cell")
	assert_true(move.targeting.requires_adjacent_enemy, "that must be beside an enemy")

	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100, "attack": 10 })
	var enemy := MockUnit.new(1, { "health": 100 })
	board.place(caster, Vector2i(1, 5))
	board.place(enemy, Vector2i(4, 5))
	var origin := Vector2i(1, 5)

	assert_true(move.can_target(origin, Vector2i(3, 5), caster, board),
		"the free cell west of the enemy is a legal landing")
	assert_true(move.can_target(origin, Vector2i(4, 4), caster, board),
		"so is the free cell north of it -- THAT choice is the choice of side")
	assert_false(move.can_target(origin, Vector2i(2, 5), caster, board),
		"a free cell that touches nothing hostile is not")
	assert_false(move.can_target(origin, Vector2i(4, 5), caster, board),
		"and the enemy's own cell is not free to land on")

func test_leap_targeting_yields_nothing_when_the_enemy_is_boxed_in():
	var move := _sporeleap()
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100, "attack": 10 })
	var enemy := MockUnit.new(1, { "health": 100 })
	board.place(caster, Vector2i(1, 5))
	board.place(enemy, Vector2i(5, 5))
	# Wall the target in on all four sides: the "move cannot be used" case falls
	# out of the targeting itself -- there is nothing left to aim at.
	for step in TargetingPattern.ORTHOGONAL_STEPS:
		board.blocked.append(Vector2i(5, 5) + step)

	var legal: Array[Vector2i] = []
	var origin := Vector2i(1, 5)
	var reach: int = move.effective_max_range(caster)
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var aim := origin + Vector2i(dx, dy)
			if move.can_target(origin, aim, caster, board):
				legal.append(aim)

	assert_eq(legal.size(), 0, "a fully boxed-in target offers no landing cell at all")

func test_constraints_default_off_so_existing_patterns_are_unchanged():
	var pattern := TargetingPattern.new()
	pattern.min_range = 1
	pattern.max_range = 3
	assert_false(pattern.requires_empty_cell, "empty-cell is opt-in")
	assert_false(pattern.requires_adjacent_enemy, "adjacency is opt-in")

	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	var occupant := MockUnit.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(occupant, Vector2i(2, 0))

	assert_true(pattern.is_aim_allowed(Vector2i(0, 0), Vector2i(2, 0), caster, board),
		"with neither constraint set, the board never narrows an in-range aim")
	assert_false(pattern.is_aim_allowed(Vector2i(0, 0), Vector2i(9, 0), caster, board),
		"range still decides")

func test_executor_rejects_an_illegal_landing_and_resolves_a_legal_one():
	var move := _sporeleap()
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100, "attack": 12 })
	var enemy := MockUnit.new(1, { "health": 100, "defense": 2 })
	board.place(caster, Vector2i(1, 5))
	board.place(enemy, Vector2i(4, 5))

	var rejected: Dictionary = MoveExecutor.execute(move, caster, board, Vector2i(2, 5), _rng(1))
	assert_false(bool(rejected.get("success", true)), "a cell not beside an enemy is refused")
	assert_eq(rejected.get("reason", ""), "invalid_target_cell", "and refused for that reason, not range")
	assert_eq(board.cell_of(caster), Vector2i(1, 5), "the caster did not budge")

	var hp_before: int = enemy.hp
	var accepted: Dictionary = MoveExecutor.execute(move, caster, board, Vector2i(3, 5), _rng(1))
	assert_true(bool(accepted.get("success", false)), "the free cell beside the enemy is accepted")
	assert_eq(board.cell_of(caster), Vector2i(3, 5), "the caster leapt to its chosen side")
	assert_lt(enemy.hp, hp_before, "and the strike then resolved from there")

# --- GAP 3: bounded stacking -----------------------------------------------

func _stacking_burn(cap: int) -> StatusCondition:
	var c := StatusCondition.new()
	c.id = &"test_burn"
	c.display_name = "Test Burn"
	c.duration_turns = 3
	c.stacking = StatusCondition.Stacking.STACK
	c.max_stacks = cap
	var dmg := DamageEffect.new()
	dmg.power = 10
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	c.tick_effects = [dmg]
	return c

func test_max_stacks_defaults_to_unbounded():
	assert_eq(StatusCondition.new().max_stacks, -1,
		"the default is unbounded, i.e. exactly how STACK behaved before the cap existed")

	var unit := MockUnit.new(0, { "health": 100 })
	var sc := _controller_for(unit)
	for _i in range(5):
		sc.add_status(_stacking_burn(-1))
	assert_eq(sc.get_active().size(), 5, "an uncapped STACK condition still stacks without limit")

func test_stacking_stops_at_the_cap():
	var unit := MockUnit.new(0, { "health": 100 })
	var sc := _controller_for(unit)
	for _i in range(6):
		sc.add_status(_stacking_burn(3))
	assert_eq(sc.stack_count(&"test_burn"), 3, "stacking stops dead at max_stacks")

func test_reapplying_at_the_cap_refreshes_instead_of_deepening():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sc := _controller_for(unit)
	sc.add_status(_stacking_burn(2))
	sc.add_status(_stacking_burn(2))

	sc.tick_all(board)   # both instances drop to 2 turns left
	assert_eq(sc.get_active()[0].turns_left, 2, "the oldest instance has ticked down")

	sc.add_status(_stacking_burn(2))
	assert_eq(sc.stack_count(&"test_burn"), 2, "no third instance is added")
	assert_eq(sc.get_active()[0].turns_left, 3, "the OLDEST instance is refreshed to full instead")

func test_tick_damage_scales_with_stack_count():
	var board := MockBoard.new()

	var one := MockUnit.new(0, { "health": 100 })
	board.place(one, Vector2i(0, 0))
	var sc_one := _controller_for(one)
	sc_one.add_status(_stacking_burn(3))
	sc_one.tick_all(board)
	assert_eq(one.hp, 90, "one stack ticks for 10")

	var three := MockUnit.new(0, { "health": 100 })
	board.place(three, Vector2i(1, 0))
	var sc_three := _controller_for(three)
	for _i in range(3):
		sc_three.add_status(_stacking_burn(3))
	sc_three.tick_all(board)
	assert_eq(three.hp, 70, "three stacks tick for 30 -- severity IS the stack count")

func test_cap_is_inert_for_refresh_and_ignore():
	var unit := MockUnit.new(0, { "health": 100 })

	var refreshing := _controller_for(unit)
	var r := _stacking_burn(3)
	r.stacking = StatusCondition.Stacking.REFRESH
	refreshing.add_status(r)
	refreshing.add_status(r)
	assert_eq(refreshing.stack_count(&"test_burn"), 1,
		"REFRESH never reaches a cap -- it never adds a second instance")

	var ignoring := _controller_for(unit)
	var g := _stacking_burn(3)
	g.stacking = StatusCondition.Stacking.IGNORE
	ignoring.add_status(g)
	ignoring.add_status(g)
	assert_eq(ignoring.stack_count(&"test_burn"), 1, "nor does IGNORE")

func test_stack_count_is_queryable_for_the_ui():
	var unit := MockUnit.new(0, { "health": 100 })
	var sc := _controller_for(unit)
	assert_eq(sc.stack_count(&"test_burn"), 0, "absent conditions report 0")
	sc.add_status(_stacking_burn(3))
	sc.add_status(_stacking_burn(3))
	assert_eq(sc.stack_count(&"test_burn"), 2, "severity is reportable without counting get_active()")
	var counts: Dictionary = sc.stacks_by_id()
	assert_eq(int(counts.get(&"test_burn", 0)), 2, "and the whole-unit view agrees")

# --- GAP 3: the poison chance mechanism ------------------------------------

func _apply_status(condition: StatusCondition, chance: float) -> ApplyStatusEffect:
	var e := ApplyStatusEffect.new()
	e.condition = condition
	e.chance = chance
	return e

func test_status_chance_defaults_to_certain():
	assert_eq(ApplyStatusEffect.new().chance, 1.0,
		"the default is 1.0, so every move authored before this field is unchanged")

func test_status_chance_of_one_always_applies():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	var target := MockUnit.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	var effect := _apply_status(_poisoned(), 1.0)
	for i in range(20):
		_resolve(effect, board, caster, target, _rng(i))
	assert_eq(target.statuses.size(), 20, "a certainty lands every single time")

func test_status_chance_of_zero_never_applies():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	var target := MockUnit.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	var effect := _apply_status(_poisoned(), 0.0)
	for i in range(20):
		_resolve(effect, board, caster, target, _rng(i))
	assert_eq(target.statuses.size(), 0, "an impossibility never lands")

func test_status_chance_rolls_through_the_injected_rng():
	var board := MockBoard.new()
	var caster := MockUnit.new(0, { "health": 100 })
	var target := MockUnit.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	# The same seed must produce the same outcome twice -- that is what makes a
	# chance-to-poison safe for replays and networked peers.
	var effect := _apply_status(_poisoned(), 0.5)
	var first: Dictionary = _resolve(effect, board, caster, target, _rng(12345)).results[0]
	var second: Dictionary = _resolve(effect, board, caster, target, _rng(12345)).results[0]
	assert_eq(first.get("applied", null), second.get("applied", null),
		"one seed, one outcome")

	# Over many seeds a 0.5 chance must be neither always nor never. Each roll gets
	# a FRESH board so the previous target is not still standing on the aimed cell.
	var landed: int = 0
	for i in range(40):
		var scratch := MockBoard.new()
		var fresh := MockUnit.new(1, { "health": 100 })
		scratch.place(caster, Vector2i(0, 0))
		scratch.place(fresh, Vector2i(2, 0))
		_resolve(effect, scratch, caster, fresh, _rng(i))
		landed += fresh.statuses.size()
	assert_gt(landed, 0, "a 50% chance sometimes lands")
	assert_lt(landed, 40, "and sometimes does not")

func test_a_certain_application_consumes_no_roll():
	# A 1.0 chance must not perturb the RNG stream, or adding the field would have
	# silently reshuffled every hit/crit resolved after it in existing moves.
	var shared := _rng(999)
	var expected: float = _rng(999).randf()
	var ctx := MoveContext.new(null, MockBoard.new(), MoveResource.new(), Vector2i.ZERO, [] as Array[Vector2i])
	ctx.rng = shared
	assert_true(ctx.roll(1.0), "a certainty passes")
	assert_false(ctx.roll(0.0), "an impossibility fails")
	assert_eq(shared.randf(), expected, "and neither touched the generator")

# --- Content: the authored kit ---------------------------------------------

func test_poisoned_status_values():
	var poison := _poisoned()
	assert_not_null(poison, "poisoned.tres loads")
	assert_eq(poison.id, &"poisoned", "stable id")
	assert_eq(poison.duration_turns, 3, "lasts 3 turns")
	assert_eq(poison.stacking, StatusCondition.Stacking.STACK, "it stacks")
	assert_eq(poison.max_stacks, 3, "with a severity ceiling of 3")
	assert_gt(poison.tick_effects.size(), 0, "and does something each turn")

func test_poisoned_stacks_are_capped_end_to_end():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sc := _controller_for(unit)
	for _i in range(6):
		sc.add_status(_poisoned())
	assert_eq(sc.stack_count(&"poisoned"), 3, "the authored poison caps at 3 stacks")

	var before: int = unit.hp
	sc.tick_all(board)
	var per_tick: int = before - unit.hp
	assert_gt(per_tick, 0, "a maxed poison hurts every turn")

	var lighter := MockUnit.new(0, { "health": 100 })
	board.place(lighter, Vector2i(1, 0))
	var sc_light := _controller_for(lighter)
	sc_light.add_status(_poisoned())
	var light_before: int = lighter.hp
	sc_light.tick_all(board)
	assert_eq(per_tick, (light_before - lighter.hp) * 3,
		"three stacks tick for exactly three times one stack")

func test_blight_burst_is_melee_with_a_chance_to_poison():
	var move := _blight_burst()
	assert_not_null(move, "blight_burst.tres loads")
	assert_eq(move.targeting.max_range, 1, "it is melee")
	assert_eq(move.targeting.target_kind, CombatTypes.TargetKind.ENEMY, "aimed at an enemy")
	assert_eq(move.category, CombatTypes.DamageCategory.PHYSICAL, "physical damage")

	var poison_effect: ApplyStatusEffect = null
	var damage_effect: DamageEffect = null
	for e in move.effects:
		if e is ApplyStatusEffect:
			poison_effect = e as ApplyStatusEffect
		elif e is DamageEffect:
			damage_effect = e as DamageEffect
	assert_not_null(damage_effect, "it deals damage")
	assert_not_null(poison_effect, "and can poison")
	assert_eq(poison_effect.condition.id, &"poisoned", "with the authored poison")
	assert_lt(poison_effect.chance, 1.0, "as a CHANCE, not a certainty")
	assert_gt(poison_effect.chance, 0.0, "that can actually happen")

func test_sporeleap_leaps_before_it_strikes():
	var move := _sporeleap()
	assert_gt(move.cooldown, 0, "the leap has a cooldown")
	assert_gt(move.targeting.max_range, 1, "and reaches further than melee")
	assert_true(move.effects[0] is LeapEffect,
		"the leap resolves FIRST, so the strike lands from the new cell")
	var has_damage: bool = false
	for e in move.effects:
		if e is DamageEffect:
			has_damage = true
	assert_true(has_damage, "and it hits on arrival")

func test_blightcap_character_sheet():
	var blightcap := _blightcap()
	if blightcap == null:
		pending("blightcap.tres not loadable yet (its .glb needs an editor import); skipping.")
		return

	assert_eq(blightcap.character_id, &"blightcap", "stable id")
	assert_eq(blightcap.display_name, "Blightcap", "display name")
	assert_ne(blightcap.description, "", "it has flavour")
	assert_eq(blightcap.footprint, Vector2i(1, 1), "a normal one-cell grunt")
	assert_false(blightcap.is_boss, "and not a boss")
	assert_eq(blightcap.attack_range, 1, "melee by default")

	var petalfang := load("res://game/characters/roster/petalfang.tres") as CharacterResource
	if petalfang != null:
		assert_gt(blightcap.base_health, petalfang.base_health, "tougher than Petalfang")
		assert_lt(blightcap.base_speed, petalfang.base_speed, "and slower")
		assert_gt(blightcap.base_movement, petalfang.base_movement, "a fast runner -- more foot reach than the slow Petalfang")

	var move_ids: Array[StringName] = []
	for m in blightcap.moveset:
		move_ids.append(m.move_id)
	assert_true(&"blight_burst" in move_ids, "it knows Blight Burst")
	assert_true(&"sporeleap" in move_ids, "and Spore Leap -- its only reach")

	assert_eq(blightcap.abilities.size(), 1, "one ability")
	assert_eq(blightcap.abilities[0].id, &"deathbloom", "the death burst")

func test_poisoned_is_discoverable_by_the_catalog():
	StatusCatalog.rescan()
	var found := StatusCatalog.find_by_id(&"poisoned")
	assert_not_null(found, "the poison resolves by id, so any move/tile/ability can name it")
