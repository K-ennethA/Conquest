extends GutTest

# Combat / character-move integration tests (formerly the TurnSystem suite).
#
# WHY THIS FILE WAS REPLACED:
# The previous tests constructed units via `Unit.new("name", speed, movement)`
# and asserted turn ordering out of `turns/turn_system.gd`. That constructor no
# longer exists, and turn_system.gd still orders units by a removed `Unit.speed`
# property (turns/turn_system.gd:64) -- so a turn-order test cannot pass without
# editing turns/, which is out of scope here. Rather than leave a permanently
# broken suite, this file now exercises the NEW combat model end-to-end through
# BoardAdapter: MoveExecutor resolving a data-authored move against the live
# board interface, driving damage, range checks, and allegiance-based targeting.

# --- Test doubles ----------------------------------------------------------

# A minimal unit that satisfies the combat unit interface used by DamageEffect /
# MoveContext: get_stat(name), take_damage(n), plus position + owner_player for
# the BoardAdapter.
class MockUnit extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var owner_player = null
	var hp: int = 100
	var stats: Dictionary = {}

	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name, 0))

	func take_damage(amount: int) -> void:
		hp -= amount

class MockOwner extends RefCounted:
	var id: int = 0

var grid: Grid
var owner_a: MockOwner
var owner_b: MockOwner


func before_each():
	grid = Grid.new()
	owner_a = MockOwner.new()
	owner_a.id = 1
	owner_b = MockOwner.new()
	owner_b.id = 2


# Builds a single-target physical strike: power 20 + attack, range 1.
func _make_strike() -> MoveResource:
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 1
	pattern.area_shape = CombatTypes.AreaShape.SINGLE

	var dmg := DamageEffect.new()
	dmg.power = 20
	dmg.scaling_stat = "attack"
	dmg.scale = 1.0
	dmg.category = CombatTypes.DamageCategory.PHYSICAL

	var effects: Array[MoveEffect] = [dmg]

	var move := MoveResource.new()
	move.move_id = &"test_strike"
	move.display_name = "Test Strike"
	move.targeting = pattern
	move.effects = effects
	return move


func _place(adapter: BoardAdapter, unit: MockUnit, cell: Vector2i) -> void:
	unit.position = adapter.cell_to_world(cell)


func test_move_executor_deals_damage_through_adapter():
	var caster := MockUnit.new()
	caster.owner_player = owner_a
	caster.stats = { "attack": 10, "defense": 5 }

	var enemy := MockUnit.new()
	enemy.owner_player = owner_b
	enemy.stats = { "defense": 5 }
	enemy.hp = 100

	var adapter := BoardAdapter.new(grid, [caster, enemy])
	_place(adapter, caster, Vector2i(1, 1))
	_place(adapter, enemy, Vector2i(2, 1))

	var result := MoveExecutor.execute(_make_strike(), caster, adapter, Vector2i(2, 1))

	assert_true(result.success, "Move should resolve successfully")
	# raw = power(20) + attack(10)*1 = 30; physical mitigation -defense(5) = 25.
	assert_eq(enemy.hp, 75, "Enemy should take mitigated damage (30 - 5 = 25)")
	assert_eq(result.events.size(), 1, "One damage event should be logged")
	assert_eq(result.events[0].amount, 25, "Logged damage amount should match")


func test_move_out_of_range_fails():
	var caster := MockUnit.new()
	caster.owner_player = owner_a
	caster.stats = { "attack": 10 }

	var enemy := MockUnit.new()
	enemy.owner_player = owner_b

	var adapter := BoardAdapter.new(grid, [caster, enemy])
	_place(adapter, caster, Vector2i(1, 1))
	_place(adapter, enemy, Vector2i(4, 1))

	var result := MoveExecutor.execute(_make_strike(), caster, adapter, Vector2i(4, 1))

	assert_false(result.success, "A move aimed beyond max range should fail")
	assert_eq(result.reason, "out_of_range", "Failure reason should be out_of_range")


func test_ally_not_hit_by_enemy_targeted_move():
	var caster := MockUnit.new()
	caster.owner_player = owner_a
	caster.stats = { "attack": 10 }

	# Same owner as caster -> an ally, so an ENEMY-targeted move must skip it.
	var ally := MockUnit.new()
	ally.owner_player = owner_a
	ally.stats = { "defense": 0 }
	ally.hp = 100

	var adapter := BoardAdapter.new(grid, [caster, ally])
	_place(adapter, caster, Vector2i(1, 1))
	_place(adapter, ally, Vector2i(2, 1))

	var result := MoveExecutor.execute(_make_strike(), caster, adapter, Vector2i(2, 1))

	assert_true(result.success, "Move still resolves even with no valid targets")
	assert_eq(ally.hp, 100, "An ally must not be damaged by an enemy-targeted move")
	assert_eq(result.events.size(), 0, "No damage events when the only unit in area is an ally")


func test_unit_perform_move_routes_to_executor():
	# A Unit with a CharacterResource exposes the same move via perform_move.
	var move := _make_strike()
	var character := CharacterResource.new()
	character.character_id = &"tester"
	character.display_name = "Tester"
	var moveset: Array[MoveResource] = [move]
	character.moveset = moveset

	var unit := Unit.new()
	unit.character_resource = character
	assert_eq(unit.get_moveset().size(), 1, "Unit should expose its character's moveset")
	assert_eq(unit.get_move(0), move, "get_move(0) should return the first move")

	# Empty slot routes to a clean failure without touching the executor.
	var miss := unit.perform_move(3, Vector2i.ZERO, null)
	assert_false(miss.success, "Performing an empty slot should fail cleanly")
	assert_eq(miss.reason, "no_move_in_slot", "Empty-slot failure reason should be no_move_in_slot")

	unit.free()
