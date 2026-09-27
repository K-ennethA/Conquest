extends GutTest

## Regression: a unit killed while still WAITING in the Speed First turn queue
## stayed queued as a freed reference, and the next queue read (the Turn Queue
## HUD's preview via get_current_round_progress) segfaulted the engine. Found by
## the two-process network smoke test, but it hit hotseat equally.

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const CHAR_ID: StringName = &"test_sf_death_unit"


func before_each() -> void:
	CombatServices.clear()
	var c := CharacterResource.new()
	c.character_id = CHAR_ID
	c.display_name = "Queued"
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 50
	c.base_speed = 10
	c.base_movement = 3
	CharacterLibrary._cache[CHAR_ID] = c


func after_each() -> void:
	CombatServices.clear()
	CharacterLibrary.clear_cache()


func _spawn(map: Node3D, cell: Vector2i, owner: Player) -> Unit:
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = CharacterLibrary.get_character(CHAR_ID)
	unit.position = BoardAdapter.new(GRID, []).cell_to_world(cell)
	map.add_child(unit)
	owner.add_unit(unit)
	return unit


func test_dead_queued_unit_leaves_the_queue() -> void:
	var map := Node3D.new()
	add_child_autofree(map)
	var p0 := Player.new(0, "A")
	var p1 := Player.new(1, "B")
	_spawn(map, Vector2i(0, 0), p0)
	_spawn(map, Vector2i(1, 0), p0)
	var victim := _spawn(map, Vector2i(4, 4), p1)
	var ts := SpeedFirstTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(p0)
	ts.register_player(p1)
	ts.start_turn_system()
	assert_true(victim in ts.turn_queue, "victim is queued")
	assert_ne(ts.current_acting_unit, victim, "victim is not the acting unit")

	var vid := victim.get_instance_id()
	victim.take_damage(9999)
	await get_tree().process_frame
	await get_tree().process_frame

	for u in ts.turn_queue:
		assert_true(is_instance_valid(u), "no freed reference left in the queue")
		if is_instance_valid(u):
			assert_ne(u.get_instance_id(), vid, "dead unit removed from the queue")
	var progress: Dictionary = ts.get_current_round_progress()
	for entry in progress["turn_queue_preview"]:
		assert_ne(entry["name"], "", "preview only lists live units")
	# Advancing past everyone must not touch the freed unit either.
	ts.end_turn_manually()
	ts.end_turn_manually()
	assert_true(ts.is_active, "turn system still running")
