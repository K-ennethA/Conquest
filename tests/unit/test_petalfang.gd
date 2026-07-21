extends GutTest

# Tests for Petalfang -- the vine-serpent controller -- and the four engine
# capabilities its kit needed:
#   1. status rule_flags + movement honouring "immobilized"
#   2. a per-unit "range_bonus" stat added to EVERY move's reach at targeting time
#   3. bonus damage vs movement-restricted enemies, via the existing PASSIVE
#      rule_modifiers mechanism
#   4. a trap placed at range (ApplyTileEffect -> ON_ENTER TileEffectResource)
#
# Mock style mirrors test_tree_grunt.gd / test_status_condition.gd; the tests that
# need real stat bookkeeping (modifier durations) build an actual Unit, as
# test_move_gating.gd does.

# --- Mocks -----------------------------------------------------------------

## A duck-typed unit. `restricted` drives the "immobilized" rule flag directly so
## a test can pin the damage bonus without standing up a StatusController.
class MockUnit:
	var team: int
	var stats: Dictionary
	var base_stats: Dictionary
	var max_health: int
	var hp: int
	var restricted: bool = false
	var ability_system = null
	var statuses: Array = []
	var modifiers: Array = []
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		base_stats = p_stats.duplicate()
		max_health = stats.get("health", 100)
		hp = max_health
	func get_stat(n: String) -> int:
		return stats.get(n, 0)
	func get_base_stat(n: String) -> int:
		return base_stats.get(n, 0)
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
	func add_stat_modifier(stat: String, amount: int, duration: int) -> int:
		modifiers.append({ "stat": stat, "amount": amount, "duration": duration })
		stats[stat] = int(stats.get(stat, 0)) + amount
		return modifiers.size()
	func add_status(condition) -> void:
		statuses.append(condition)
	func is_immobilized() -> bool:
		return restricted
	func get_ability_system():
		return ability_system
	# Stand-in owner: the team int doubles as the "player" for owner-aware trap factions.
	func get_owner_player() -> int:
		return team

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
	func set_tile(_cell: Vector2i, _tile_id) -> void:
		pass
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell

# --- Helpers ---------------------------------------------------------------

func _petalfang() -> CharacterResource:
	return load("res://game/characters/roster/petalfang.tres") as CharacterResource

func _thorn_spit() -> MoveResource:
	return load("res://game/combat/moves/thorn_spit.tres") as MoveResource

func _ensnared() -> StatusCondition:
	return load("res://game/combat/status/ensnared.tres") as StatusCondition

func _entangled() -> StatusCondition:
	return load("res://game/combat/status/entangled.tres") as StatusCondition

func _thornlust() -> AbilityResource:
	return load("res://game/abilities/thornlust.tres") as AbilityResource

## A bare Unit with real stats bookkeeping plus a StatusController, so status
## rule flags and stat-modifier durations both resolve for real.
func _unit_with_status_controller(display_name: String, movement: int = 4) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = display_name
	res.unit_type = "warrior"
	res.max_health = 100
	res.base_speed = 8
	res.movement_range = movement
	u.stats_resource = res
	add_child_autofree(u)
	var controller := StatusController.new()
	controller.name = "StatusController"
	controller.owner_unit = u
	u.add_child(controller)
	return u

## An AbilitySystem holding [param ability], owned by [param unit].
func _ability_system_with(unit, ability: AbilityResource) -> AbilitySystem:
	var sys: AbilitySystem = autofree(AbilitySystem.new())
	sys.owner_unit = unit
	if ability != null:
		sys.add_ability(ability)
	return sys

## Resolve a single DamageEffect from [param caster] onto [param target].
func _hit(effect: DamageEffect, board, caster, target) -> int:
	var cell: Vector2i = board.cell_of(target)
	var move := MoveResource.new()
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 0
	pattern.max_range = 5
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.move_id = &"test_hit"
	move.targeting = pattern
	var before: int = target.hp
	var ctx := MoveContext.new(caster, board, move, cell, [cell] as Array[Vector2i])
	effect.apply(ctx)
	return before - target.hp

func _damage_effect(power: int, category: CombatTypes.DamageCategory) -> DamageEffect:
	var e := DamageEffect.new()
	e.power = power
	e.scaling_stat = ""
	e.category = category
	return e

# --- GAP 1: status rule flags gate movement ---------------------------------

func test_immobilized_status_blocks_movement_then_releases_on_expiry():
	var u := _unit_with_status_controller("Quarry")
	var board := MockBoard.new()
	board.place(u, Vector2i(0, 0))
	assert_true(u.can_move(), "a free unit can move")

	var controller := u.get_status_controller() as StatusController
	controller.add_status(_ensnared())
	assert_true(controller.has_rule_flag(&"immobilized"),
		"ensnared sets the immobilized rule flag")
	assert_true(u.is_immobilized(), "the unit reports itself immobilized")
	assert_false(u.can_move(), "an immobilized unit cannot move")

	# One tick expires the 1-turn hold.
	controller.tick_all(board)
	assert_false(controller.has_status(&"ensnared"), "ensnared expires after one turn")
	assert_false(controller.has_rule_flag(&"immobilized"), "the rule flag lapses with it")
	assert_true(u.can_move(), "movement is restored once the hold expires")

func test_status_without_rule_flags_does_not_immobilize():
	var u := _unit_with_status_controller("Quarry")
	var plain := StatusCondition.new()
	plain.id = &"plain"
	plain.duration_turns = 3
	u.get_status_controller().add_status(plain)
	assert_false(u.is_immobilized(),
		"a condition authored before rule_flags existed never immobilizes")
	assert_true(u.can_move(), "and movement is untouched")

func test_unit_without_status_controller_is_never_immobilized():
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.max_health = 100
	u.stats_resource = res
	add_child_autofree(u)
	assert_false(u.is_immobilized(), "a legacy unit with no StatusController is free")
	assert_true(u.can_move(), "and can_move() behaves exactly as before")

# --- GAP 2: per-unit range bonus --------------------------------------------

func test_range_bonus_extends_effective_range():
	var move := _thorn_spit()
	var archer := MockUnit.new(0, { "range_bonus": 2 })
	assert_eq(move.targeting.max_range, 3, "thorn_spit is authored at range 3")
	assert_eq(move.effective_max_range(archer), 5, "a +2 bonus reaches 5")
	assert_true(move.can_aim_at(Vector2i(0, 0), Vector2i(5, 0), archer),
		"a cell 5 away is legal with the bonus")

func test_zero_bonus_resolves_exactly_as_before():
	var move := _thorn_spit()
	var plain := MockUnit.new(0, {})
	assert_eq(move.effective_max_range(plain), 3, "no bonus leaves the authored reach")
	assert_eq(move.effective_max_range(null), 3, "a null caster resolves the same")
	assert_true(move.can_aim_at(Vector2i(0, 0), Vector2i(3, 0), plain), "3 away is in range")
	assert_false(move.can_aim_at(Vector2i(0, 0), Vector2i(4, 0), plain), "4 away is not")
	# The no-caster overload is what every pre-existing call site used.
	assert_true(move.can_aim_at(Vector2i(0, 0), Vector2i(3, 0)), "legacy call is unchanged")
	assert_false(move.can_aim_at(Vector2i(0, 0), Vector2i(4, 0)), "legacy call still rejects 4")

func test_range_bonus_does_not_open_the_min_range_dead_zone():
	var pattern := TargetingPattern.new()
	pattern.min_range = 2
	pattern.max_range = 3
	assert_false(pattern.in_range(Vector2i(0, 0), Vector2i(1, 0), 2),
		"a bonus extends the far edge, never the near one")
	assert_true(pattern.in_range(Vector2i(0, 0), Vector2i(5, 0), 2), "the far edge does extend")

func test_negative_range_bonus_cannot_shrink_a_move():
	var move := _thorn_spit()
	var cursed := MockUnit.new(0, { "range_bonus": -5 })
	assert_eq(move.effective_max_range(cursed), 3,
		"a negative bonus is clamped away rather than shortening the move")

func test_shared_move_resource_does_not_leak_range_bonus_between_units():
	# The trap this design exists to avoid: one authored .tres, two casters.
	var move := _thorn_spit()
	var rooted := MockUnit.new(0, { "range_bonus": 2 })
	var normal := MockUnit.new(0, { "range_bonus": 0 })

	assert_eq(move.effective_max_range(rooted), 5, "the buffed unit reaches 5")
	assert_eq(move.effective_max_range(normal), 3, "its squadmate still reaches 3")
	# Resolving for the buffed unit first must not contaminate the second read.
	assert_eq(move.effective_max_range(normal), 3, "and stays 3 on a repeat read")
	assert_eq(move.targeting.max_range, 3, "the shared TargetingPattern is never mutated")

	assert_true(move.can_aim_at(Vector2i(0, 0), Vector2i(5, 0), rooted),
		"the buffed unit may aim 5 cells out")
	assert_false(move.can_aim_at(Vector2i(0, 0), Vector2i(5, 0), normal),
		"its squadmate may not")

func test_range_bonus_is_a_real_stat_on_a_live_unit():
	var u := _unit_with_status_controller("Petal")
	assert_eq(u.get_stat("range_bonus"), 0, "range_bonus starts at 0")
	u.add_stat_modifier("range_bonus", 2, 5)
	assert_eq(u.get_stat("range_bonus"), 2, "a StatModifierEffect can grant it")
	assert_eq(_thorn_spit().effective_max_range(u), 5, "and every move reaches further")

func test_move_executor_honours_the_range_bonus():
	var caster := MockUnit.new(0, { "attack": 10, "range_bonus": 2 })
	var victim := MockUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(victim, Vector2i(5, 0))  # 5 away: out of thorn_spit's authored 3
	var result: Dictionary = MoveExecutor.execute(_thorn_spit(), caster, board, Vector2i(5, 0))
	assert_true(bool(result.get("success", false)),
		"the executor accepts an aim the caster's bonus brings into reach")

func test_move_executor_still_rejects_out_of_range_without_a_bonus():
	var caster := MockUnit.new(0, { "attack": 10 })
	var victim := MockUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(victim, Vector2i(5, 0))
	var result: Dictionary = MoveExecutor.execute(_thorn_spit(), caster, board, Vector2i(5, 0))
	assert_false(bool(result.get("success", true)), "an unbuffed caster is still out of range")
	assert_eq(result.get("reason", ""), "out_of_range", "and fails for the documented reason")

# --- GAP 3: bonus damage vs movement-restricted enemies ----------------------

func test_bonus_damage_applies_to_an_immobilized_target():
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "health": 100, "defense": 0 })
	target.restricted = true
	caster.ability_system = _ability_system_with(caster, _thornlust())
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))
	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, caster, target)
	assert_eq(dealt, 30, "thornlust's +50% turns 20 into 30 against a held target")

func test_forecast_shows_the_bonus_and_matches_what_is_dealt():
	# The predation bonus is DETERMINISTIC, so the forecast must include it -- a
	# forecast that under-reports damage against a held target teaches the player
	# the wrong thing. The property that matters is that preview and resolution
	# AGREE; they now share one helper precisely so they cannot drift.
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "health": 100, "defense": 0 })
	target.restricted = true
	caster.ability_system = _ability_system_with(caster, _thornlust())
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	var effect := _damage_effect(20, CombatTypes.DamageCategory.PHYSICAL)
	var move := MoveResource.new()
	move.effects = [effect] as Array[MoveEffect]

	var forecast: Dictionary = MoveExecutor.preview_vs(move, caster, target)
	assert_eq(int(forecast["damage"]), 30, "forecast includes thornlust's +50%")

	var dealt := _hit(effect, board, caster, target)
	assert_eq(int(forecast["damage"]), dealt, "forecast and resolution must agree")


func test_forecast_omits_the_bonus_for_an_unrestricted_target():
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "health": 100, "defense": 0 })
	target.restricted = false
	caster.ability_system = _ability_system_with(caster, _thornlust())
	var move := MoveResource.new()
	move.effects = [_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL)] as Array[MoveEffect]
	var forecast: Dictionary = MoveExecutor.preview_vs(move, caster, target)
	assert_eq(int(forecast["damage"]), 20, "no bonus shown when the target is free to move")


func test_forecast_never_rolls_crit():
	# Crit stays a PROBABILITY in the forecast. If it were resolved here, a player
	# could cancel and re-aim to fish for a favourable roll -- so preview reports
	# crit_pct and a hypothetical crit_damage, and rolls nothing.
	var caster := MockUnit.new(0, { "crit": 50 })
	var target := MockUnit.new(1, { "health": 100, "defense": 0 })
	var move := MoveResource.new()
	move.crit_chance = 0.25
	move.effects = [_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL)] as Array[MoveEffect]

	var first: Dictionary = MoveExecutor.preview_vs(move, caster, target)
	for i in range(8):
		var again: Dictionary = MoveExecutor.preview_vs(move, caster, target)
		assert_eq(int(again["damage"]), int(first["damage"]), "repeat previews are identical")
		assert_eq(float(again["crit_pct"]), float(first["crit_pct"]), "crit stays a percentage")
	assert_gt(float(first["crit_pct"]), 0.0, "crit chance is reported, not resolved")


func test_no_bonus_damage_against_an_unrestricted_target():
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "health": 100, "defense": 0 })
	target.restricted = false
	caster.ability_system = _ability_system_with(caster, _thornlust())
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))
	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, caster, target)
	assert_eq(dealt, 20, "a mobile target takes the plain 20")

func test_no_bonus_damage_when_the_caster_lacks_the_modifier():
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "health": 100, "defense": 0 })
	target.restricted = true
	caster.ability_system = _ability_system_with(caster, null)  # no passives at all
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))
	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, caster, target)
	assert_eq(dealt, 20, "a held target is only worth more to a caster that hunts them")

func test_damage_is_unchanged_with_no_ability_system_at_all():
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "health": 100, "defense": 0 })
	target.restricted = true
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))
	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, caster, target)
	assert_eq(dealt, 20, "no ability system -> plain damage, no errors")

func test_a_slowed_target_counts_as_movement_restricted():
	# The second half of the definition: current movement below base.
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "health": 100, "defense": 0, "movement": 4 })
	caster.ability_system = _ability_system_with(caster, _thornlust())
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))

	var full := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, caster, target)
	assert_eq(full, 20, "at full movement the target is not restricted")

	target.stats["movement"] = 2  # base stays 4 -> actively slowed
	var slowed := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, caster, target)
	assert_eq(slowed, 30, "a slowed target takes the predation bonus")

func test_low_base_movement_alone_is_not_restricted():
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "health": 100, "defense": 0, "movement": 1 })
	caster.ability_system = _ability_system_with(caster, _thornlust())
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))
	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, caster, target)
	assert_eq(dealt, 20, "a naturally slow unit is not a restricted one")

# --- GAP 4: the vine trap ----------------------------------------------------

func test_stepping_onto_a_trapped_cell_damages_and_holds():
	# The trap is owner-aware now: it springs on the PLACER's enemies, not allies.
	# Duplicate so we don't mutate the shared cached resource; stamp owner = player 0
	# (Petalfang's side), then walk an ENEMY (player 1) onto it.
	var trap := (load("res://game/tiles/effects/resources/vine_trap.tres") as TileEffectResource).duplicate()
	assert_not_null(trap, "vine_trap.tres loads")
	assert_eq(trap.trigger, TileEffectResource.Trigger.ON_ENTER, "the trap fires on entry")
	trap.owner_player = 0  # placed by player 0's side

	var victim := MockUnit.new(1, { "health": 100, "magic_defense": 0, "defense": 0 })
	var board := MockBoard.new()
	board.place(victim, Vector2i(4, 4))

	var system: TileEffectSystem = autofree(TileEffectSystem.new())
	system.tile_effects[Vector2i(4, 4)] = [trap]
	var events: Array = system.on_enter(victim, Vector2i(4, 4), board)

	assert_lt(victim.hp, 100, "entering the trapped cell deals damage to an enemy")
	assert_eq(victim.statuses.size(), 1, "and applies exactly one status")
	assert_eq(victim.statuses[0].id, &"ensnared", "that status is ensnared")
	assert_true(victim.statuses[0].rule_flags.get("immobilized", false),
		"which immobilizes the victim")
	assert_gt(events.size(), 0, "the entry is logged")


func test_a_trap_spares_the_placers_own_ally():
	# An ally of the placer (same owner) walks over the trap and takes NOTHING.
	var trap := (load("res://game/tiles/effects/resources/vine_trap.tres") as TileEffectResource).duplicate()
	trap.owner_player = 0
	var ally := MockUnit.new(0, { "health": 100, "magic_defense": 0, "defense": 0 })
	var board := MockBoard.new()
	board.place(ally, Vector2i(4, 4))

	var system: TileEffectSystem = autofree(TileEffectSystem.new())
	system.tile_effects[Vector2i(4, 4)] = [trap]
	system.on_enter(ally, Vector2i(4, 4), board)

	assert_eq(ally.hp, 100, "a friendly unit does not trigger its own side's trap")
	assert_eq(ally.statuses.size(), 0, "and is not ensnared")

func test_trap_damage_is_flat_so_the_victim_does_not_scale_it():
	# TileEffectResource.run() makes the OCCUPANT the MoveContext caster, so a
	# scaling_stat here would scale the trap by its own victim's magic. Pinned.
	var trap := load("res://game/tiles/effects/resources/vine_trap.tres") as TileEffectResource
	var damage: DamageEffect = null
	for e in trap.effects:
		if e is DamageEffect:
			damage = e as DamageEffect
	assert_not_null(damage, "the trap deals damage")
	assert_eq(damage.scaling_stat, "", "the trap's damage is flat, not victim-scaled")
	assert_eq(damage.category, CombatTypes.DamageCategory.MAGICAL, "and is magical")

func test_vine_trap_move_targets_an_empty_tile_at_range():
	var move := load("res://game/combat/moves/vine_trap.tres") as MoveResource
	assert_not_null(move, "vine_trap.tres (the move) loads")
	assert_eq(move.targeting.target_kind, CombatTypes.TargetKind.EMPTY_TILE,
		"the move is aimed at unoccupied ground")
	assert_gt(move.targeting.max_range, 0, "it places the trap at a distance")
	assert_gt(move.cooldown, 0, "and is gated by a cooldown")
	assert_eq(move.effects.size(), 1, "it carries exactly one effect")
	assert_true(move.effects[0] is ApplyTileEffect, "which layers a tile effect onto the cell")
	assert_eq(move.effects[0].effect.id, &"vine_trap", "namely the vine trap")

# --- Authored statuses -------------------------------------------------------

func test_ensnared_holds_for_exactly_one_turn():
	var ensnared := _ensnared()
	assert_not_null(ensnared, "ensnared.tres loads")
	assert_eq(ensnared.id, &"ensnared", "id is ensnared")
	assert_eq(ensnared.duration_turns, 1, "the hold lasts one turn")
	assert_true(ensnared.rule_flags.get("immobilized", false), "it sets the immobilized flag")
	assert_eq(ensnared.tick_effects.size(), 0, "it applies nothing -- it is a pure rule")

func test_entangled_slows_the_next_turn_then_wears_off():
	# The debuff must cover exactly the target's NEXT turn and then lapse. A slow
	# that silently never expires is the failure mode this test exists to catch.
	var u := _unit_with_status_controller("Quarry", 4)
	var board := MockBoard.new()
	board.place(u, Vector2i(0, 0))
	var controller := u.get_status_controller() as StatusController

	controller.add_status(_entangled())
	assert_eq(u.get_stat("movement"), 4, "movement is untouched on the turn it lands")

	# The target's next turn: the status ticks once, applying the slow.
	controller.tick_all(board)
	assert_eq(u.get_stat("movement"), 2, "movement is reduced for that next turn")
	assert_false(controller.has_status(&"entangled"),
		"and the status itself is spent -- it cannot tick a second time")

	# The turn after: the modifier's own duration lapses and movement returns.
	u.process_turn_start()
	assert_eq(u.get_stat("movement"), 4, "movement is back to base -- the slow wore off")

	# And it stays off.
	u.process_turn_start()
	assert_eq(u.get_stat("movement"), 4, "no residual reduction lingers")

func test_entangled_cannot_stack_into_a_permanent_slow():
	var u := _unit_with_status_controller("Quarry", 4)
	var board := MockBoard.new()
	board.place(u, Vector2i(0, 0))
	var controller := u.get_status_controller() as StatusController

	# Hit twice before it ever ticks: REFRESH means one instance, not two.
	controller.add_status(_entangled())
	controller.add_status(_entangled())
	assert_eq(controller.get_active().size(), 1, "a second casting refreshes rather than stacks")
	controller.tick_all(board)
	assert_eq(u.get_stat("movement"), 2, "the slow is applied once, not twice")

func test_entangled_carries_the_movement_reduction():
	var entangled := _entangled()
	assert_not_null(entangled, "entangled.tres loads")
	assert_eq(entangled.duration_turns, 1, "it is scoped to a single turn")
	assert_eq(entangled.tick_effects.size(), 1, "it carries one effect")
	assert_true(entangled.tick_effects[0] is StatModifierEffect, "which is a stat modifier")
	assert_eq(entangled.tick_effects[0].stat_name, "movement", "on movement")
	assert_lt(entangled.tick_effects[0].amount, 0, "and it is a reduction")
	assert_eq(entangled.tick_effects[0].duration, 1,
		"lasting exactly one turn, so it can never compound")

func test_ingrained_status_roots_for_five_turns():
	var ingrained := load("res://game/combat/status/ingrained.tres") as StatusCondition
	assert_not_null(ingrained, "ingrained.tres (the status) loads")
	assert_eq(ingrained.duration_turns, 5, "the root lasts 5 turns")
	assert_true(ingrained.rule_flags.get("immobilized", false), "and immobilizes the caster")

# --- Authored moves ----------------------------------------------------------

func test_thorn_spit_is_a_ranged_physical_hit_that_can_crit():
	var move := _thorn_spit()
	assert_not_null(move, "thorn_spit.tres loads")
	assert_eq(move.move_id, &"thorn_spit", "move_id is thorn_spit")
	assert_eq(move.category, CombatTypes.DamageCategory.PHYSICAL, "it is physical")
	assert_gt(move.targeting.max_range, 1, "and genuinely ranged")
	assert_gt(move.crit_chance, 0.0, "with a meaningful crit chance")
	assert_eq(move.cooldown, 0, "it is the at-will attack, so no cooldown")
	assert_true(move.is_valid(), "it has targeting and at least one effect")

func test_gathering_vines_applies_entangled():
	var move := load("res://game/combat/moves/gathering_vines.tres") as MoveResource
	assert_not_null(move, "gathering_vines.tres loads")
	assert_eq(move.targeting.target_kind, CombatTypes.TargetKind.ENEMY, "it targets an enemy")
	assert_gt(move.targeting.max_range, 1, "at range")
	var applied: ApplyStatusEffect = null
	for e in move.effects:
		if e is ApplyStatusEffect:
			applied = e as ApplyStatusEffect
	assert_not_null(applied, "it applies a status")
	assert_eq(applied.condition.id, &"entangled", "namely entangled")

func test_gathering_vines_entangles_a_real_target_through_the_executor():
	var caster := MockUnit.new(0, { "magic": 10 })
	var victim := MockUnit.new(1, { "health": 100, "magic_defense": 0, "defense": 0 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(victim, Vector2i(2, 0))
	# Deterministic without touching the shared authored resource: ApplyStatusEffect
	# does not gate on the hit roll, so the status lands regardless of accuracy.
	var move := load("res://game/combat/moves/gathering_vines.tres") as MoveResource
	var result: Dictionary = MoveExecutor.execute(move, caster, board, Vector2i(2, 0))
	assert_true(bool(result.get("success", false)), "the move resolves")
	assert_eq(victim.statuses.size(), 1, "the target is left with one status")
	assert_eq(victim.statuses[0].id, &"entangled", "which is entangled")

func test_ingrained_roots_the_caster_and_extends_every_move():
	var move := load("res://game/combat/moves/ingrained.tres") as MoveResource
	assert_not_null(move, "ingrained.tres (the move) loads")
	assert_eq(move.targeting.target_kind, CombatTypes.TargetKind.SELF, "it targets the caster")
	assert_gt(move.cooldown, 0, "and is gated by a cooldown")

	var root: ApplyStatusEffect = null
	var reach: StatModifierEffect = null
	for e in move.effects:
		if e is ApplyStatusEffect:
			root = e as ApplyStatusEffect
		elif e is StatModifierEffect:
			reach = e as StatModifierEffect
	assert_not_null(root, "it applies a status")
	assert_eq(root.condition.id, &"ingrained", "which roots the caster")
	assert_true(root.condition.rule_flags.get("immobilized", false), "via the immobilized flag")
	assert_not_null(reach, "and grants a stat modifier")
	assert_eq(reach.stat_name, "range_bonus", "on range_bonus")
	assert_gt(reach.amount, 0, "which is positive")
	assert_eq(reach.duration, 5, "for 5 turns, matching the root")
	assert_eq(root.condition.duration_turns, reach.duration,
		"the root and the reach expire together")

func test_ingrained_cast_on_a_live_unit_roots_it_and_lengthens_thorn_spit():
	var u := _unit_with_status_controller("Petalfang", 3)
	var board := MockBoard.new()
	board.place(u, Vector2i(2, 2))
	assert_true(u.can_move(), "free before the cast")
	assert_eq(_thorn_spit().effective_max_range(u), 3, "and at its authored reach")

	var move := load("res://game/combat/moves/ingrained.tres") as MoveResource
	var result: Dictionary = MoveExecutor.execute(move, u, board, Vector2i(2, 2))
	assert_true(bool(result.get("success", false)), "ingrained resolves on the caster's own cell")

	assert_true(u.is_immobilized(), "the caster is rooted")
	assert_false(u.can_move(), "and cannot move")
	assert_eq(u.get_stat("range_bonus"), 2, "while gaining reach")
	assert_eq(_thorn_spit().effective_max_range(u), 5, "so thorn_spit now reaches 5")

# --- Authored ability --------------------------------------------------------

func test_thornlust_is_a_passive_carrying_the_damage_modifier():
	var ability := _thornlust()
	assert_not_null(ability, "thornlust.tres loads")
	assert_eq(ability.id, &"thornlust", "ability id is thornlust")
	assert_eq(ability.trigger, AbilityTrigger.Trigger.PASSIVE, "it is a passive")
	assert_true(ability.rule_modifiers.has("damage_vs_restricted"),
		"it contributes the damage_vs_restricted rule modifier")
	assert_gt(float(ability.rule_modifiers["damage_vs_restricted"]), 0.0,
		"and the modifier is a positive bonus")
	assert_eq(ability.effects.size(), 0,
		"it has no pipeline effects -- it is purely a standing rule")

func test_thornlust_surfaces_through_passive_modifiers():
	var unit := MockUnit.new(0, {})
	var sys := _ability_system_with(unit, _thornlust())
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var mods: Dictionary = sys.passive_modifiers(unit, board)
	assert_almost_eq(float(mods.get("damage_vs_restricted", 0.0)), 0.5, 0.001,
		"the merged passives expose the +50% bonus")

# --- The character -----------------------------------------------------------

func test_petalfang_loads_with_four_moves_and_one_ability():
	var petal := _petalfang()
	assert_not_null(petal, "petalfang.tres loads")
	assert_eq(petal.character_id, &"petalfang", "character_id is petalfang")
	assert_eq(petal.display_name, "Petalfang", "display name is Petalfang")
	assert_eq(petal.move_count(), 4, "Petalfang carries exactly 4 moves")
	assert_eq(petal.ability_count(), 1, "and exactly 1 ability")
	assert_eq(petal.get_move(0).move_id, &"thorn_spit", "slot 0 is thorn_spit")
	assert_eq(petal.get_move(1).move_id, &"vine_trap", "slot 1 is vine_trap")
	assert_eq(petal.get_move(2).move_id, &"gathering_vines", "slot 2 is gathering_vines")
	assert_eq(petal.get_move(3).move_id, &"ingrained", "slot 3 is ingrained")
	assert_eq(petal.abilities[0].id, &"thornlust", "its ability is thornlust")
	var v: Dictionary = petal.validate()
	assert_true(bool(v.get("valid", false)),
		"petalfang passes CharacterResource.validate(): %s" % [str(v.get("issues", []))])

func test_petalfang_is_a_ranged_grunt_not_a_bruiser():
	var petal := _petalfang()
	var grunt := load("res://game/characters/roster/tree_grunt.tres") as CharacterResource
	assert_false(petal.is_boss, "Petalfang is a grunt, not a boss")
	assert_eq(petal.get_footprint(), Vector2i(1, 1), "it occupies a single cell")
	assert_eq(petal.attack_range, _thorn_spit().targeting.max_range,
		"its attack_range matches thorn_spit's reach")
	assert_gt(petal.attack_range, 1, "it fights at range")
	assert_lt(petal.base_health, grunt.base_health, "squishier than the melee grunt")
	assert_lt(petal.base_defense, grunt.base_defense, "and thinner-skinned")
	assert_gt(petal.base_magic, grunt.base_magic, "but a far better caster")
