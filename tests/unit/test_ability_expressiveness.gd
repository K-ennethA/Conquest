extends GutTest

# Tests for the expressiveness abilities gained on top of the original
# trigger + condition + self-targeted-effects model: real targeting patterns,
# reaching the unit that caused the trigger, per-unit cooldown / limited uses,
# composed conditions, and the damage_dealt announcement that finally makes the
# combat triggers fireable. Mock style mirrors test_abilities.gd -- no scene tree.

# --- Mocks -----------------------------------------------------------------

class MockUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var max_health: int          # read by HealEffect's percent-of-max term
	var modifiers: Array = []
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = stats.get("health", 100)
		max_health = hp
	func get_stat(name: String) -> int:
		return stats.get(name, 0)
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp += n
	func add_stat_modifier(stat: String, amount: int, duration: int) -> int:
		modifiers.append({ "stat": stat, "amount": amount, "duration": duration })
		return modifiers.size()

class MockBoard:
	var placements: Array = []       # { unit, cell }
	var tags: Dictionary = {}        # cell -> terrain tag (StringName)
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
	func set_tile(cell: Vector2i, _tile_id) -> void:
		pass
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	func tag_tile(cell: Vector2i, tag: StringName) -> void:
		tags[cell] = tag
	func tile_tag_at(cell: Vector2i) -> StringName:
		return tags.get(cell, &"")

# Stand-in for the GameEvents autoload, injected via MoveContext.event_bus. The
# real signal is typed (Unit, Unit, int) and would reject mocks, so effects that
# announce themselves route through this in tests.
class MockEventBus:
	extends Node
	signal damage_dealt(attacker, defender, damage)
	var calls: Array = []
	func _init() -> void:
		damage_dealt.connect(_record)
	func _record(attacker, defender, damage) -> void:
		calls.append({ "attacker": attacker, "defender": defender, "damage": damage })

# A condition that simply reports whatever it was constructed with, so the
# composites can be tested without dragging in board/health state.
class FixedCondition:
	extends AbilityCondition
	var value: bool = true
	func _init(p_value: bool) -> void:
		value = p_value
	func is_met(_unit, _board) -> bool:
		return value
	func describe() -> String:
		return "fixed(%s)" % value

# --- Helpers ---------------------------------------------------------------

func _system_for(unit) -> AbilitySystem:
	var sys := AbilitySystem.new()
	sys.owner_unit = unit
	return autofree(sys)

# A 100%-accurate, never-critting damage effect, so damage totals are exact.
func _ability_with_damage(power: int) -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"test_damage"
	var dmg := DamageEffect.new()
	dmg.power = power
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	a.effects = [dmg]
	return a

func _ability_with_heal(amount: int) -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"test_heal"
	var heal := HealEffect.new()
	heal.amount = amount
	heal.scaling_stat = ""
	a.effects = [heal]
	return a

func _pattern(kind: CombatTypes.TargetKind, shape: CombatTypes.AreaShape, size: int) -> TargetingPattern:
	var p := TargetingPattern.new()
	p.target_kind = kind
	p.min_range = 0
	p.max_range = 0
	p.area_shape = shape
	p.area_size = size
	return p

# --- Targeting: back-compat ------------------------------------------------

func test_no_targeting_still_affects_only_its_own_unit():
	# The guarantee every already-authored ability (natures_blessing, the
	# AbilityLibrary samples) depends on: a null targeting pattern is unchanged
	# self-targeting, even with allies and enemies standing right next to it.
	var holder := MockUnit.new(0, { "health": 100 })
	holder.hp = 50
	var ally := MockUnit.new(0, { "health": 100 })
	ally.hp = 50
	var foe := MockUnit.new(1, { "health": 100 })
	foe.hp = 50
	var board := MockBoard.new()
	board.place(holder, Vector2i(2, 2))
	board.place(ally, Vector2i(2, 3))
	board.place(foe, Vector2i(3, 2))
	var ability := _ability_with_heal(10)
	assert_null(ability.targeting, "targeting defaults to null")
	ability.run_effects(holder, board)
	assert_eq(holder.hp, 60, "the ability's own unit is healed")
	assert_eq(ally.hp, 50, "an adjacent ally is untouched without a targeting pattern")
	assert_eq(foe.hp, 50, "an adjacent enemy is untouched without a targeting pattern")

func test_natures_blessing_resource_still_self_heals():
	# The shipped .tres, exercised end to end, to prove the authored content did
	# not change behaviour.
	var path := "res://game/abilities/natures_blessing.tres"
	if not ResourceLoader.exists(path):
		pass_test("natures_blessing.tres not present in this checkout")
		return
	var ability: AbilityResource = load(path)
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 50
	var neighbour := MockUnit.new(0, { "health": 100 })
	neighbour.hp = 50
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	board.place(neighbour, Vector2i(0, 1))
	var events := ability.run_effects(unit, board)
	assert_eq(events.size(), 1, "exactly one target: the unit itself")
	assert_eq(events[0].get("target"), unit, "the heal landed on its own unit")
	assert_eq(unit.hp, 60, "it still restores 10% of max health to itself")
	assert_eq(neighbour.hp, 50, "the neighbour is unaffected")

# --- Targeting: patterns ---------------------------------------------------

func test_ally_radius_pattern_affects_the_units_the_pattern_selects():
	# An aura: heal every ally within a Manhattan radius of 1, but not the caster
	# (affects_caster_tile stays false) and not enemies.
	var holder := MockUnit.new(0, { "health": 100 })
	holder.hp = 50
	var near_ally := MockUnit.new(0, { "health": 100 })
	near_ally.hp = 50
	var far_ally := MockUnit.new(0, { "health": 100 })
	far_ally.hp = 50
	var foe := MockUnit.new(1, { "health": 100 })
	foe.hp = 50
	var board := MockBoard.new()
	board.place(holder, Vector2i(4, 4))
	board.place(near_ally, Vector2i(4, 5))    # distance 1
	board.place(far_ally, Vector2i(4, 7))     # distance 3 -- outside
	board.place(foe, Vector2i(3, 4))          # distance 1 but hostile
	var ability := _ability_with_heal(10)
	ability.targeting = _pattern(CombatTypes.TargetKind.ALLY, CombatTypes.AreaShape.DIAMOND, 1)
	ability.run_effects(holder, board)
	assert_eq(near_ally.hp, 60, "the adjacent ally is healed by the aura")
	assert_eq(far_ally.hp, 50, "an ally outside the radius is not")
	assert_eq(foe.hp, 50, "an adjacent enemy is not an ALLY target")
	assert_eq(holder.hp, 50, "the caster's own tile is excluded unless affects_caster_tile")

func test_enemy_radius_pattern_hits_every_adjacent_foe():
	var holder := MockUnit.new(0, { "health": 100 })
	var foe_a := MockUnit.new(1, { "health": 100 })
	var foe_b := MockUnit.new(1, { "health": 100 })
	var ally := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(holder, Vector2i(0, 0))
	board.place(foe_a, Vector2i(1, 0))
	board.place(foe_b, Vector2i(0, 1))
	board.place(ally, Vector2i(0, -1))
	var ability := _ability_with_damage(7)
	ability.targeting = _pattern(CombatTypes.TargetKind.ENEMY, CombatTypes.AreaShape.DIAMOND, 1)
	ability.run_effects(holder, board)
	assert_eq(foe_a.hp, 93, "first adjacent enemy takes the retaliation damage")
	assert_eq(foe_b.hp, 93, "second adjacent enemy too")
	assert_eq(ally.hp, 100, "the adjacent ally is not an ENEMY target")
	assert_eq(holder.hp, 100, "the caster never damages itself")

# --- Targeting: the triggering unit ----------------------------------------

func test_targets_triggering_unit_applies_effects_to_other():
	# Thornskin in miniature: ON_DAMAGED, striking back at the attacker, which is
	# nowhere near the defender's own targeting reach.
	var defender := MockUnit.new(0, { "health": 100 })
	var attacker := MockUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(defender, Vector2i(0, 0))
	board.place(attacker, Vector2i(6, 6))
	var ability := _ability_with_damage(5)
	ability.targets_triggering_unit = true
	ability.run_effects(defender, board, attacker)
	assert_eq(attacker.hp, 95, "the triggering unit takes the effect")
	assert_eq(defender.hp, 100, "the ability's own unit is untouched")

func test_targets_triggering_unit_no_ops_without_one():
	var defender := MockUnit.new(0, { "health": 100 })
	var bystander := MockUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(defender, Vector2i(0, 0))
	board.place(bystander, Vector2i(0, 1))
	var ability := _ability_with_damage(5)
	ability.targets_triggering_unit = true
	var events := ability.run_effects(defender, board)   # no triggering unit
	assert_eq(events.size(), 0, "nothing resolves when no unit caused the trigger")
	assert_eq(defender.hp, 100, "the ability's own unit is not hit as a fallback")
	assert_eq(bystander.hp, 100, "and neither is anybody else")

func test_trigger_threads_other_through_to_the_ability():
	# The AbilitySystem end of the same path: trigger(..., other) reaches effects.
	var defender := MockUnit.new(0, { "health": 100 })
	var attacker := MockUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(defender, Vector2i(0, 0))
	board.place(attacker, Vector2i(1, 0))
	var ability := _ability_with_damage(5)
	ability.trigger = AbilityTrigger.Trigger.ON_DAMAGED
	ability.targets_triggering_unit = true
	var sys := _system_for(defender)
	sys.add_ability(ability)
	sys.trigger(AbilityTrigger.Trigger.ON_DAMAGED, defender, board, attacker)
	assert_eq(attacker.hp, 95, "the attacker took the retaliation")

func test_thornskin_resource_retaliates():
	var path := "res://game/abilities/thornskin.tres"
	if not ResourceLoader.exists(path):
		pass_test("thornskin.tres not present in this checkout")
		return
	var ability: AbilityResource = load(path)
	assert_eq(ability.trigger, AbilityTrigger.Trigger.ON_DAMAGED, "thornskin fires when damaged")
	assert_true(ability.targets_triggering_unit, "thornskin reaches the attacker")
	var defender := MockUnit.new(0, { "health": 100 })
	var attacker := MockUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(defender, Vector2i(0, 0))
	board.place(attacker, Vector2i(1, 0))
	ability.run_effects(defender, board, attacker)
	assert_lt(attacker.hp, 100, "the attacker is hurt in return")
	assert_eq(defender.hp, 100, "the defender takes no extra damage from its own ability")

# --- Cooldown and limited uses ---------------------------------------------

func test_cooldown_skips_until_ticked():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 10
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var ability := _ability_with_heal(5)
	ability.trigger = AbilityTrigger.Trigger.ON_TURN_START
	ability.cooldown = 1
	var sys := _system_for(unit)
	sys.add_ability(ability)

	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.hp, 15, "first trigger activates")
	assert_eq(sys.cooldown_remaining(ability), 1, "and starts the cooldown")

	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.hp, 15, "a second trigger is skipped while cooling down")

	sys.tick_cooldowns()
	assert_eq(sys.cooldown_remaining(ability), 0, "the cooldown ticked down to ready")
	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.hp, 20, "it activates again once the cooldown has elapsed")

func test_max_activations_one_fires_exactly_once():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 10
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var ability := _ability_with_heal(5)
	ability.trigger = AbilityTrigger.Trigger.ON_TURN_START
	ability.max_activations = 1
	var sys := _system_for(unit)
	sys.add_ability(ability)

	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.hp, 15, "the once-per-battle ability fires")
	assert_eq(sys.activations_left(ability), 0, "and is spent")
	for _i in range(5):
		sys.tick_cooldowns()
		sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.hp, 15, "it never fires again, however many turns pass")

func test_unlimited_by_default():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 0
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var ability := _ability_with_heal(5)
	ability.trigger = AbilityTrigger.Trigger.ON_TURN_START
	var sys := _system_for(unit)
	sys.add_ability(ability)
	for _i in range(4):
		sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.hp, 20, "cooldown 0 / max_activations -1 fires on every trigger")
	assert_eq(sys.activations_left(ability), -1, "unlimited abilities report -1 left")

func test_two_units_sharing_one_resource_track_independently():
	# The subtle one. A .tres is loaded ONCE and handed to every unit that has the
	# ability, so activation state must live on the per-unit component. If it ever
	# migrates onto the resource, one unit spending its single activation would
	# silently disarm the other -- invisible in normal play, fatal in a squad.
	var unit_a := MockUnit.new(0, { "health": 100 })
	unit_a.hp = 10
	var unit_b := MockUnit.new(0, { "health": 100 })
	unit_b.hp = 10
	var board := MockBoard.new()
	board.place(unit_a, Vector2i(0, 0))
	board.place(unit_b, Vector2i(5, 5))

	var shared := _ability_with_heal(5)          # ONE instance, both units
	shared.trigger = AbilityTrigger.Trigger.ON_TURN_START
	shared.cooldown = 1
	shared.max_activations = 1

	var sys_a := _system_for(unit_a)
	sys_a.add_ability(shared)
	var sys_b := _system_for(unit_b)
	sys_b.add_ability(shared)

	# A spends its single activation; B must be untouched by that.
	sys_a.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit_a, board)
	assert_eq(unit_a.hp, 15, "unit A activated")
	assert_eq(unit_b.hp, 10, "unit B did not activate off A's trigger")
	assert_eq(sys_a.cooldown_remaining(shared), 1, "A's cooldown started")
	assert_eq(sys_b.cooldown_remaining(shared), 0, "B's cooldown is untouched")
	assert_eq(sys_a.activations_left(shared), 0, "A is spent")
	assert_eq(sys_b.activations_left(shared), 1, "B still has its activation")

	# B now uses its own.
	sys_b.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit_b, board)
	assert_eq(unit_b.hp, 15, "unit B activates on its own schedule")

	# And A stays spent even after ticking, because uses are per unit too.
	sys_a.tick_cooldowns()
	sys_a.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit_a, board)
	assert_eq(unit_a.hp, 15, "A's single activation is still spent after its cooldown")

func test_reset_activations_clears_per_unit_state():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 10
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var ability := _ability_with_heal(5)
	ability.trigger = AbilityTrigger.Trigger.ON_TURN_START
	ability.max_activations = 1
	var sys := _system_for(unit)
	sys.add_ability(ability)
	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	sys.reset_activations()
	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.hp, 20, "a fresh battle re-arms the ability")

# --- Condition composition -------------------------------------------------

func test_all_condition_requires_every_child():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var both := AllCondition.new()
	both.conditions = [FixedCondition.new(true), FixedCondition.new(true)]
	assert_true(both.is_met(unit, board), "all children met -> met")
	var one_fails := AllCondition.new()
	one_fails.conditions = [FixedCondition.new(true), FixedCondition.new(false)]
	assert_false(one_fails.is_met(unit, board), "a single failing child fails the whole AND")
	var empty := AllCondition.new()
	assert_true(empty.is_met(unit, board), "an empty AND is vacuously met")

func test_any_condition_needs_one_child():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var one_passes := AnyCondition.new()
	one_passes.conditions = [FixedCondition.new(false), FixedCondition.new(true)]
	assert_true(one_passes.is_met(unit, board), "one met child is enough for OR")
	var none_pass := AnyCondition.new()
	none_pass.conditions = [FixedCondition.new(false), FixedCondition.new(false)]
	assert_false(none_pass.is_met(unit, board), "no met child -> not met")
	var empty := AnyCondition.new()
	assert_true(empty.is_met(unit, board), "an empty OR stays permissive, like the base class")

func test_not_condition_inverts():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var inverted := NotCondition.new()
	inverted.condition = FixedCondition.new(false)
	assert_true(inverted.is_met(unit, board), "NOT of an unmet condition is met")
	inverted.condition = FixedCondition.new(true)
	assert_false(inverted.is_met(unit, board), "NOT of a met condition is unmet")
	var bare := NotCondition.new()
	assert_false(bare.is_met(unit, board), "NOT of nothing is never met")

func test_composites_nest_with_real_conditions():
	# The motivating case: "below 30% health AND standing on sacred ground",
	# authorable without a single new condition class.
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(1, 1))
	var wounded := HealthBelowCondition.new()
	wounded.threshold = 0.3
	var sacred := OnTerrainCondition.new()
	sacred.terrain_id = &"sacred_ground"
	var combo := AllCondition.new()
	combo.conditions = [wounded, sacred]

	unit.hp = 20                                     # wounded, wrong tile
	assert_false(combo.is_met(unit, board), "wounded alone is not enough")
	board.tag_tile(Vector2i(1, 1), &"sacred_ground") # wounded AND on sacred ground
	assert_true(combo.is_met(unit, board), "both halves hold")
	unit.hp = 90                                     # healthy, right tile
	assert_false(combo.is_met(unit, board), "the terrain alone is not enough")

	# And the same pair under OR: either half is sufficient.
	var either := AnyCondition.new()
	either.conditions = [wounded, sacred]
	assert_true(either.is_met(unit, board), "healthy but on sacred ground satisfies OR")

func test_composed_condition_gates_a_real_ability():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var ability := _ability_with_heal(5)
	ability.trigger = AbilityTrigger.Trigger.ON_TURN_START
	ability.max_activations = 1
	var never := AllCondition.new()
	never.conditions = [FixedCondition.new(true), FixedCondition.new(false)]
	ability.condition = never
	var sys := _system_for(unit)
	sys.add_ability(ability)
	unit.hp = 50
	sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.hp, 50, "an unmet composite condition blocks the ability")
	assert_eq(sys.activations_left(ability), 1, "and a blocked ability spends no activation")

# --- damage_dealt announcement ---------------------------------------------

func test_damage_effect_announces_damage_dealt():
	var attacker := MockUnit.new(0, { "health": 100, "attack": 0 })
	var defender := MockUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(defender, Vector2i(1, 0))
	var bus := MockEventBus.new()
	autofree(bus)

	var dmg := DamageEffect.new()
	dmg.power = 12
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	var move := MoveResource.new()
	move.move_id = &"test_strike"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	move.targeting = pattern
	var cells: Array[Vector2i] = [Vector2i(1, 0)] as Array[Vector2i]
	var ctx := MoveContext.new(attacker, board, move, Vector2i(1, 0), cells)
	ctx.event_bus = bus
	dmg.apply(ctx)

	assert_eq(bus.calls.size(), 1, "one damage_dealt announcement per landed hit")
	assert_eq(bus.calls[0]["attacker"], attacker, "the caster is reported as the attacker")
	assert_eq(bus.calls[0]["defender"], defender, "the target is reported as the defender")
	assert_eq(bus.calls[0]["damage"], 12, "the DEALT amount is reported")
	assert_eq(defender.hp, 88, "and the damage actually landed")

func test_damage_effect_without_a_bus_still_resolves():
	# The headless / no-autoload path: the emit is guarded, so damage still lands.
	var attacker := MockUnit.new(0, { "health": 100 })
	var defender := MockUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(defender, Vector2i(1, 0))
	var dmg := DamageEffect.new()
	dmg.power = 9
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	var move := MoveResource.new()
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	move.targeting = pattern
	var cells: Array[Vector2i] = [Vector2i(1, 0)] as Array[Vector2i]
	var ctx := MoveContext.new(attacker, board, move, Vector2i(1, 0), cells)
	dmg.apply(ctx)
	assert_eq(defender.hp, 91, "mock units never reach the typed autoload signal, and damage resolves")
