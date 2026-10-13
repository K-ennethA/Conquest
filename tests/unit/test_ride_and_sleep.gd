extends GutTest

## The pure rules under the new regions' mechanics: a TRAVEL field move's tiles are passable only
## while RIDING (OverworldGrid.riding_tiles); a usable prop; a sleeper's LYING pose (head north,
## face up, whatever the model's yaw correction).


func _map() -> MapResource:
	var m := MapResource.new()
	m.width = 3
	m.height = 1
	m.set_tile_at_position(Vector2i(0, 0), "NORMAL", "", "grass_plains")
	m.set_tile_at_position(Vector2i(1, 0), "WATER", "", "deep_water")
	m.set_tile_at_position(Vector2i(2, 0), "NORMAL", "", "grass_plains")
	return m


func test_water_is_passable_only_while_riding() -> void:
	var g := OverworldGrid.from_map(_map())
	var water := Vector3i(1, 0, 0)
	assert_false(g.is_terrain_passable(water), "on foot the water blocks")
	var tiles: Array[StringName] = [&"deep_water"]
	assert_true(g.is_tile_in(water, tiles), "it is a ridden tile")
	assert_false(g.is_tile_in(Vector3i(0, 0, 0), tiles), "the grass is not")
	g.riding_tiles = tiles
	assert_true(g.is_terrain_passable(water), "riding, it carries you")
	assert_true(g.is_terrain_passable(Vector3i(2, 0, 0)), "and the land stays walkable (you step ashore)")
	assert_false(g.is_terrain_passable(Vector3i(3, 0, 0)), "never off the map")
	g.riding_tiles = [] as Array[StringName]
	assert_false(g.is_terrain_passable(water), "off the mount, blocked again")


func test_a_prop_is_usable_only_with_a_script() -> void:
	var p := PropEntity.new()
	p.prop = "bed"
	p.footprint = Vector2i(1, 2)
	assert_false(p.is_interactable(), "scenery by default")
	assert_true(p.is_blocking(), "a bed is solid")
	p.on_interact = StoryCommand.list([SetFlagCommand.make("rested")])
	p.verb = "Rest"
	assert_true(p.is_interactable(), "with a script it is usable")
	assert_eq(p.prompt_verb(), "Rest", "under its own verb")
	assert_eq(p.cells().size(), 2, "on both of its cells")


func test_a_lying_sleeper_has_head_north_and_face_up() -> void:
	for yaw in [0.0, 90.0, 180.0, -90.0]:
		var b := OverworldActor.lying_basis(yaw)
		# The model's native forward is what its yaw correction turns to +Z (south).
		var fwd: Vector3 = Basis(Vector3.UP, -deg_to_rad(yaw)) * Vector3(0, 0, 1)
		assert_true((b * Vector3.UP).is_equal_approx(Vector3(0, 0, -1)), "yaw %s: head to the north" % yaw)
		assert_true((b * fwd).is_equal_approx(Vector3.UP), "yaw %s: face to the sky" % yaw)


func test_npc_sleep_follows_its_condition() -> void:
	var n := NpcEntity.new()
	var s := StoryState.new()
	assert_false(n.is_asleep(s), "awake by default")
	n.asleep_if = "not has(\"town.awake\")"
	assert_true(n.is_asleep(s), "asleep while the condition holds")
	s.set_flag("town.awake", 1)
	assert_false(n.is_asleep(s), "awake once it does not")
