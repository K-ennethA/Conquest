extends GutTest

# Unit tests for the Unit class (current, component-based API).
#
# The previous suite used `Unit.new("name", speed, movement)` plus `unit_name` /
# `speed` / `max_movement` properties -- none of which exist anymore. Unit is now
# a TileObject whose stats come from a UnitStats component (UnitStatsResource),
# and it can optionally hold a CharacterResource to perform data-authored moves.
# These tests exercise that current surface, including the new character/move API.

var unit: Unit


func after_each():
	if unit and is_instance_valid(unit):
		unit.free()
		unit = null


func _make_stats() -> UnitStatsResource:
	var res := UnitStatsResource.new()
	res.unit_name = "Rook"
	res.unit_type = "warrior"
	res.max_health = 120
	res.base_attack = 25
	res.base_defense = 15
	res.base_speed = 8
	res.movement_range = 4
	res.attack_range = 1
	return res


# --- Construction / defaults (no scene setup required) ---------------------

func test_default_construction():
	unit = Unit.new()
	assert_not_null(unit, "Unit.new() should create a unit")
	assert_false(unit.has_turn, "Unit should not have a turn initially")
	assert_null(unit.owner_player, "Unit should have no owner initially")

func test_display_name_without_stats():
	unit = Unit.new()
	assert_eq(unit.get_display_name(), "Unknown Unit", "Unit without stats reports a placeholder name")

func test_can_move_to_base_always_true():
	unit = Unit.new()
	assert_true(unit.can_move_to(Vector3(0, 0, 0)), "Base unit allows movement to any position")
	assert_true(unit.can_move_to(Vector3(10, 5, -3)), "Base unit allows movement to any position")

func test_owner_player_assignment():
	unit = Unit.new()
	var player := Player.new(0, "P1")
	unit.set_owner_player(player)
	assert_eq(unit.get_owner_player(), player, "Owner player should be settable and retrievable")


# --- Character / move API (no scene setup required) ------------------------

func test_no_character_means_empty_moveset():
	unit = Unit.new()
	assert_false(unit.has_character(), "A bare unit has no character")
	assert_eq(unit.get_moveset().size(), 0, "Moveset should be empty without a character")
	assert_null(unit.get_move(0), "get_move should return null without a character")

func test_character_moveset_exposed():
	unit = Unit.new()
	var move := MoveResource.new()
	move.move_id = &"jab"
	var character := CharacterResource.new()
	character.character_id = &"hero"
	character.display_name = "Hero"
	var moveset: Array[MoveResource] = [move]
	character.moveset = moveset
	unit.character_resource = character

	assert_true(unit.has_character(), "Unit with a CharacterResource reports has_character")
	assert_eq(unit.get_moveset().size(), 1, "Moveset should come from the character")
	assert_eq(unit.get_move(0), move, "get_move(0) should return the assigned move")
	assert_null(unit.get_move(5), "Out-of-range slot should return null")

func test_perform_move_empty_slot_fails_cleanly():
	unit = Unit.new()
	var result := unit.perform_move(0, Vector2i.ZERO, null)
	assert_false(result.success, "Performing a move with no character should fail")
	assert_eq(result.reason, "no_move_in_slot", "Failure reason should be no_move_in_slot")


# --- Stats via the component (requires the unit in the scene tree) ----------

func test_stats_and_movement_through_component():
	unit = Unit.new()
	unit.stats_resource = _make_stats()
	add_child(unit)  # triggers _ready() so the UnitStats component initializes

	assert_eq(unit.get_stat("health"), 120, "Health should read through the stats component")
	assert_eq(unit.get_stat("attack"), 25, "Attack should read through the stats component")
	assert_eq(unit.get_display_name(), "Rook", "Display name should come from the stats resource")
	assert_eq(unit.get_movement_range(), 4, "Movement range should match movement_range stat")
	assert_true(unit.is_alive(), "A freshly created unit should be alive")
