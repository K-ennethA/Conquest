extends GutTest

## OverworldGrid: walkability from tiles + blocking entities + visible_if; TrainerSight; the tap
## pathfinder. Built from an in-memory MapResource (no disk writes).


## 8x6: grass everywhere, a stone wall at (3, 0..3), deep water at (6, 2), a tree at (5, 5).
func _map() -> MapResource:
	var m := MapResource.new()
	m.width = 8
	m.height = 6
	for y in range(6):
		for x in range(8):
			var id := "grass_plains"
			if x == 3 and y <= 3:
				id = "stone_wall"
			elif Vector2i(x, y) == Vector2i(6, 2):
				id = "deep_water"
			elif Vector2i(x, y) == Vector2i(5, 5):
				id = "tree"
			elif Vector2i(x, y) == Vector2i(1, 5):
				id = "tall_grass"
			m.set_tile_at_position(Vector2i(x, y), "NORMAL", "", id)
	return m


func _area(entities: Array = []) -> OverworldAreaResource:
	var a := OverworldAreaResource.new()
	a.area_id = &"grid_test"
	a.terrain = _map()
	var typed: Array[Resource] = []
	for e in entities:
		typed.append(e)
	a.entities = typed
	return a


func test_terrain_walkability() -> void:
	var g := OverworldGrid.build(_area(), StoryState.new())
	assert_true(g.is_walkable(Vector3i(0, 0, 0)), "grass is walkable")
	assert_false(g.is_walkable(Vector3i(3, 1, 0)), "a stone wall is not")
	assert_false(g.is_walkable(Vector3i(6, 2, 0)), "deep water is not walkable on a stroll")
	assert_false(g.is_walkable(Vector3i(5, 5, 0)), "a tree is not")
	assert_false(g.is_walkable(Vector3i(-1, 0, 0)), "off the map is not")
	assert_false(g.is_walkable(Vector3i(0, 0, 1)), "no upper floors in M1")
	assert_eq(g.tile_id_at(Vector3i(1, 5, 0)), &"tall_grass", "tile ids are exposed (encounter zones)")


func test_blocking_entities_and_visible_if() -> void:
	var npc := NpcEntity.new()
	npc.id = &"villager"
	npc.cell = Vector3i(1, 1, 0)
	var gone := NpcEntity.new()
	gone.id = &"recruit"
	gone.cell = Vector3i(2, 2, 0)
	gone.visible_if = "not has(\"recruited\")"
	var warp := WarpEntity.new()
	warp.id = &"exit"
	warp.area_rect = Rect2i(0, 0, 1, 1)
	var s := StoryState.new()
	var a := _area([npc, gone, warp])
	var g := OverworldGrid.build(a, s)
	assert_false(g.is_walkable(Vector3i(1, 1, 0)), "an NPC blocks its cell")
	assert_true(g.is_walkable(Vector3i(1, 1, 0), "villager"), "except for itself")
	assert_false(g.is_walkable(Vector3i(2, 2, 0)), "a present recruit blocks")
	assert_true(g.is_walkable(Vector3i(0, 0, 0)), "a warp never blocks")
	s.set_flag("recruited", 1)
	g.rebuild_blockers(a, s)
	assert_true(g.is_walkable(Vector3i(2, 2, 0)), "once hidden by visible_if it no longer blocks")


func test_props_block_their_whole_footprint_only_when_blocking() -> void:
	var stall := PropEntity.new()
	stall.id = &"stall"
	stall.prop = "stall"
	stall.cell = Vector3i(0, 3, 0)
	stall.footprint = Vector2i(2, 1)
	stall.blocking = true
	var roof := PropEntity.new()
	roof.id = &"roof"
	roof.prop = "house"
	roof.cell = Vector3i(4, 3, 0)
	roof.footprint = Vector2i(2, 2)
	assert_false(roof.blocking, "scenery is not blocking by default")
	assert_eq(stall.cells().size(), 2, "a prop occupies its footprint")
	var a := _area([stall, roof])
	var g := OverworldGrid.build(a, StoryState.new())
	assert_false(g.is_walkable(Vector3i(0, 3, 0)), "a blocking stall blocks its first cell")
	assert_false(g.is_walkable(Vector3i(1, 3, 0)), "and every other cell of its footprint")
	assert_true(g.is_walkable(Vector3i(5, 4, 0)), "a roof over open ground does not block")
	assert_eq(a.validate().filter(func(i: String) -> bool: return i.contains("stall") or i.contains("roof")),
		[], "known prop kinds validate")
	var bad := PropEntity.new()
	bad.id = &"bad"
	bad.prop = "castle_in_the_sky"
	var issues: Array[String] = []
	bad.validate(a, issues)
	assert_eq(issues.size(), 1, "an unknown prop kind is a content error")


func test_moved_actors_block_where_they_stand() -> void:
	var guard := NpcEntity.new()
	guard.id = &"guard"
	guard.cell = Vector3i(4, 1, 0)
	var s := StoryState.new()
	s.set_actor_position("grid_test", "guard", Vector3i(4, 2, 0), "south", true)
	var g := OverworldGrid.build(_area([guard]), s)
	assert_true(g.is_walkable(Vector3i(4, 1, 0)), "the gate is open once the guard stepped aside")
	assert_false(g.is_walkable(Vector3i(4, 2, 0)), "he blocks where he now stands")


func test_trainer_sight_range_facing_and_blockers() -> void:
	var g := OverworldGrid.build(_area(), StoryState.new())
	# Trainer at (4, 4) looking west along row 4: (3,4) (2,4) (1,4) (0,4).
	assert_true(TrainerSight.spots(g, Vector3i(4, 4, 0), Vector2i(-1, 0), 4, Vector3i(1, 4, 0)), "in range, in line")
	assert_false(TrainerSight.spots(g, Vector3i(4, 4, 0), Vector2i(-1, 0), 2, Vector3i(1, 4, 0)), "out of range")
	assert_false(TrainerSight.spots(g, Vector3i(4, 4, 0), Vector2i(1, 0), 4, Vector3i(1, 4, 0)), "behind him")
	assert_false(TrainerSight.spots(g, Vector3i(4, 4, 0), Vector2i(-1, 0), 4, Vector3i(1, 3, 0)), "off his line")
	# Looking west along row 2 from (5,2): the wall at (3,2) blocks (2,2).
	assert_false(TrainerSight.spots(g, Vector3i(5, 2, 0), Vector2i(-1, 0), 5, Vector3i(2, 2, 0)), "a wall blocks sight")
	var npc := NpcEntity.new()
	npc.id = &"crowd"
	npc.cell = Vector3i(2, 4, 0)
	var g2 := OverworldGrid.build(_area([npc]), StoryState.new())
	assert_false(TrainerSight.spots(g2, Vector3i(4, 4, 0), Vector2i(-1, 0), 4, Vector3i(1, 4, 0)), "a blocking NPC blocks sight")
	assert_eq(TrainerSight.approach_cell(Vector3i(4, 4, 0), Vector2i(-1, 0), Vector3i(1, 4, 0)), Vector3i(2, 4, 0),
		"he walks up to the cell next to you")
	assert_eq(TrainerSight.approach_cell(Vector3i(2, 4, 0), Vector2i(-1, 0), Vector3i(1, 4, 0)), Vector3i(2, 4, 0),
		"already adjacent -> he stays put")


func test_tap_pathfinder() -> void:
	var g := OverworldGrid.build(_area(), StoryState.new())
	var p: Array[Vector3i] = TapPathfinder.find_path(g, Vector3i(1, 1, 0), Vector3i(5, 1, 0))
	assert_false(p.is_empty(), "a path exists around the wall")
	assert_eq(p[p.size() - 1], Vector3i(5, 1, 0), "it ends on the target")
	for i in range(p.size()):
		var prev: Vector3i = Vector3i(1, 1, 0) if i == 0 else p[i - 1]
		assert_eq(Cells.manhattan_2d(prev, p[i]), 1, "4-way single steps only")
		assert_true(g.is_walkable(p[i]), "every step is walkable")
	assert_true(TapPathfinder.find_path(g, Vector3i(1, 1, 0), Vector3i(3, 1, 0)).is_empty(), "no path into a wall")
	var plan: Dictionary = TapPathfinder.path_to_adjacent(g, Vector3i(0, 0, 0), Vector3i(5, 5, 0))
	assert_false(plan.is_empty(), "a tap on a tree plans a walk to a neighbouring cell")
	assert_eq(Cells.manhattan_2d(plan["stand"], Vector3i(5, 5, 0)), 1, "standing next to it")
