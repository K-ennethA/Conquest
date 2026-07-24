extends GutTest

# Tests for the first fully-authored unit -- the Tree Grunt -- and the engine
# piece it needed: percent-of-max-health healing. Covers the HealEffect maths,
# the authored .tres content (tree_bash / rooted / natures_blessing), and the
# ability firing through an AbilitySystem on ON_TURN_START. Mock style mirrors
# test_abilities.gd / test_combat_hit_crit.gd -- no scene tree required.

# --- Mocks -----------------------------------------------------------------

class MockUnit:
	var team: int
	var stats: Dictionary
	var max_health: int
	var hp: int
	var modifiers: Array = []
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		max_health = stats.get("health", 100)
		hp = max_health
	func get_stat(n: String) -> int:
		return stats.get(n, 0)
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
	func add_stat_modifier(stat: String, amount: int, duration: int) -> int:
		modifiers.append({ "stat": stat, "amount": amount, "duration": duration })
		return modifiers.size()

# A target exposing neither max_health nor get_base_stat, to prove the percent
# term is skipped rather than erroring.
class _NoMaxUnit:
	var hp: int = 10
	func get_stat(_n: String) -> int:
		return 0
	func heal(n: int) -> void:
		hp += n

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

## An ANY_UNIT single-target move, so gather_targets() returns whoever stands on
## the affected cells regardless of allegiance.
func _any_unit_move() -> MoveResource:
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ANY_UNIT
	pattern.min_range = 0
	pattern.max_range = 4
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	var move := MoveResource.new()
	move.move_id = &"test_heal"
	move.targeting = pattern
	return move

## Apply [param effect] to every unit standing on [param cells].
func _apply_heal(effect: HealEffect, board, caster, cells: Array[Vector2i]) -> Array:
	var ctx := MoveContext.new(caster, board, _any_unit_move(), cells[0], cells)
	effect.apply(ctx)
	return ctx.results

func _heal_effect(flat: int, percent: float) -> HealEffect:
	var e := HealEffect.new()
	e.amount = flat
	e.percent_of_max_health = percent
	return e

func _tree_grunt() -> CharacterResource:
	return load("res://game/characters/roster/tree_grunt.tres") as CharacterResource

# --- HealEffect: percent of max health --------------------------------------

func test_percent_heals_ten_percent_of_target_max_health():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 50
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	_apply_heal(_heal_effect(0, 0.10), board, unit, [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(unit.hp, 60, "10% of a 100 max-health target restores 10")

func test_flat_amount_still_heals_on_its_own():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 50
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	_apply_heal(_heal_effect(24, 0.0), board, unit, [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(unit.hp, 74, "a flat-only heal is unaffected by the new percent term")

func test_flat_and_percent_combine():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 40
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var events := _apply_heal(_heal_effect(5, 0.10), board, unit, [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(unit.hp, 55, "5 flat + 10% of 100 restores 15 in total")
	assert_eq(events[0].get("amount"), 15, "the logged event reports the combined heal")

func test_zero_percent_leaves_existing_behaviour_unchanged():
	var unit := MockUnit.new(0, { "health": 200 })
	unit.hp = 100
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	# Default-constructed HealEffect: percent defaults to 0.0, amount to 20.
	var plain := HealEffect.new()
	_apply_heal(plain, board, unit, [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(unit.hp, 120, "an authored-before-the-change heal restores exactly its flat amount")
	assert_eq(plain.percent_of_max_health, 0.0, "percent_of_max_health defaults to 0.0")

func test_percent_is_resolved_per_target():
	var big := MockUnit.new(0, { "health": 100 })
	var small := MockUnit.new(0, { "health": 60 })
	big.hp = 10
	small.hp = 10
	var board := MockBoard.new()
	board.place(big, Vector2i(0, 0))
	board.place(small, Vector2i(1, 0))
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	_apply_heal(_heal_effect(0, 0.10), board, big, cells)
	assert_eq(big.hp, 20, "the 100 max-health target heals its own 10")
	assert_eq(small.hp, 16, "the 60 max-health target heals its own 6, not the caster's share")

func test_percent_skipped_when_target_exposes_no_max_health():
	var caster := MockUnit.new(0, { "health": 100 })
	var odd := _NoMaxUnit.new()
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(odd, Vector2i(1, 0))
	_apply_heal(_heal_effect(3, 0.10), board, caster, [Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(odd.hp, 13, "unreadable max health drops the percent term, keeping the flat heal")

# --- Authored moves ---------------------------------------------------------

func test_tree_bash_has_no_cooldown_and_is_a_melee_physical_hit():
	var bash := load("res://game/combat/moves/tree_bash.tres") as MoveResource
	assert_not_null(bash, "tree_bash.tres loads")
	assert_eq(bash.move_id, &"tree_bash", "move_id is tree_bash")
	assert_eq(bash.cooldown, 0, "tree_bash has no cooldown")
	assert_true(bash.is_valid(), "tree_bash has targeting and at least one effect")
	assert_eq(bash.category, CombatTypes.DamageCategory.PHYSICAL, "tree_bash is physical")
	assert_eq(bash.targeting.max_range, 1, "tree_bash is melee (range 1)")
	assert_eq(bash.targeting.target_kind, CombatTypes.TargetKind.ENEMY, "tree_bash targets enemies")

func test_rooted_has_cooldown_three_and_self_buff_then_heal():
	var rooted := load("res://game/combat/moves/rooted.tres") as MoveResource
	assert_not_null(rooted, "rooted.tres loads")
	assert_eq(rooted.cooldown, 3, "rooted is gated by a 3-turn cooldown")
	assert_eq(rooted.targeting.target_kind, CombatTypes.TargetKind.SELF, "rooted targets the caster")
	assert_eq(rooted.effects.size(), 3, "rooted carries three effects")
	assert_true(rooted.effects[0] is StatModifierEffect, "first effect buffs a stat")
	assert_eq(rooted.effects[0].stat_name, "defense", "first buff is defense")
	assert_gt(rooted.effects[0].amount, 0, "the defense buff is positive")
	assert_eq(rooted.effects[0].duration, 3, "the defense buff lasts 3 turns")
	assert_true(rooted.effects[1] is StatModifierEffect, "second effect buffs a stat")
	assert_eq(rooted.effects[1].stat_name, "magic_defense", "second buff is magic_defense")
	assert_gt(rooted.effects[1].amount, 0, "the magic_defense buff is positive")
	assert_eq(rooted.effects[1].duration, 3, "the magic_defense buff lasts 3 turns")
	assert_true(rooted.effects[2] is HealEffect, "third effect heals")
	assert_almost_eq(rooted.effects[2].percent_of_max_health, 0.1, 0.001,
		"rooted restores 10% of max health")

func test_rooted_buffs_and_heals_the_caster_once_per_cast():
	var grunt := MockUnit.new(0, { "health": 100 })
	grunt.hp = 50
	var board := MockBoard.new()
	board.place(grunt, Vector2i(2, 2))
	var rooted := load("res://game/combat/moves/rooted.tres") as MoveResource
	var result := MoveExecutor.execute(rooted, grunt, board, Vector2i(2, 2))
	assert_true(result.success, "rooted resolves on the caster's own cell")
	assert_eq(grunt.modifiers.size(), 2, "both defensive buffs are applied")
	assert_eq(grunt.hp, 60, "one cast heals 10% of max health exactly once")

# --- Authored ability -------------------------------------------------------

func test_natures_blessing_triggers_on_turn_start():
	var ability := load("res://game/abilities/natures_blessing.tres") as AbilityResource
	assert_not_null(ability, "natures_blessing.tres loads")
	assert_eq(ability.id, &"natures_blessing", "ability id is natures_blessing")
	assert_eq(ability.trigger, AbilityTrigger.Trigger.ON_TURN_START,
		"nature's blessing fires at the start of the unit's turn")
	assert_eq(ability.effects.size(), 1, "it carries exactly one effect")
	assert_true(ability.effects[0] is HealEffect, "that effect is a heal")
	assert_almost_eq(ability.effects[0].percent_of_max_health, 0.1, 0.001,
		"it restores 10% of max health")

func test_ability_system_heals_its_unit_on_turn_start():
	var grunt := MockUnit.new(0, { "health": 80 })
	grunt.hp = 40
	var board := MockBoard.new()
	board.place(grunt, Vector2i(3, 1))
	var sys: AbilitySystem = autofree(AbilitySystem.new())
	sys.owner_unit = grunt
	sys.add_ability(load("res://game/abilities/natures_blessing.tres") as AbilityResource)

	var events := sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, grunt, board)
	assert_eq(grunt.hp, 48, "the grunt regains 10% of its 80 max health")
	assert_eq(events.size(), 1, "one heal event is logged")
	assert_eq(events[0].get("effect"), "heal", "the logged event is a heal")

	# A different event must leave the grunt alone.
	sys.trigger(AbilityTrigger.Trigger.ON_KILL, grunt, board)
	assert_eq(grunt.hp, 48, "the ability does not fire on an unrelated event")

# --- The character -----------------------------------------------------------

func test_tree_grunt_loads_with_two_moves_and_one_ability():
	var grunt := _tree_grunt()
	assert_not_null(grunt, "tree_grunt.tres loads")
	assert_eq(grunt.character_id, &"tree_grunt", "character_id is preserved")
	assert_eq(grunt.move_count(), 2, "the grunt carries exactly 2 moves")
	assert_eq(grunt.ability_count(), 1, "the grunt carries exactly 1 ability")
	assert_eq(grunt.get_move(0).move_id, &"tree_bash", "slot 0 is tree_bash")
	assert_eq(grunt.get_move(1).move_id, &"rooted", "slot 1 is rooted")
	assert_eq(grunt.abilities[0].id, &"natures_blessing", "its ability is nature's blessing")
	assert_eq(grunt.abilities[0].trigger, AbilityTrigger.Trigger.ON_TURN_START,
		"the grunt's ability fires on turn start")
	var v: Dictionary = grunt.validate()
	# NOTE: wrap the issues array -- "%s" % some_array treats the array as the
	# ARGUMENT LIST, so an empty issues list raises "not enough arguments".
	assert_true(bool(v.get("valid", false)),
		"tree_grunt passes CharacterResource.validate(): %s" % [str(v.get("issues", []))])

func test_tree_grunt_is_a_spawnable_grunt_not_a_boss():
	var grunt := _tree_grunt()
	assert_false(grunt.is_boss, "the grunt is not a boss")
	assert_eq(grunt.get_footprint(), Vector2i(1, 1), "the grunt occupies a single cell")
	assert_eq(grunt.attack_range, 1, "the grunt is a melee unit")
	# Individually weak: comfortably below an authored front-line hero.
	var frontliner := load("res://game/characters/roster/vineweave.tres") as CharacterResource
	assert_lt(grunt.power_budget(), frontliner.power_budget(),
		"a grunt is individually weaker than an authored front-liner")
	assert_lt(grunt.base_speed, frontliner.base_speed, "the grunt is slower")
	assert_lt(grunt.base_movement, frontliner.base_movement, "the grunt has shorter movement")
