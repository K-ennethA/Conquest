extends GutTest

## WHERE THE HERO (AND EVERYONE ELSE) APPEARS, for every shipped area under each stage of the
## story: entry points (new journey, warp arrival, whiteout respawn) stand on cells the hero can
## really walk -- terrain AND entity blockers -- never on an exit, and lead out into the area;
## every open warp's arrival (row / column preserved) lands somewhere walkable; scripted moves
## end on open ground; a save made before an area was rebuilt is settled onto reachable ground on
## load; the grass tables resolve and the towns roll nothing.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")


func _areas() -> Array[OverworldAreaResource]:
	var out: Array[OverworldAreaResource] = []
	for id in StoryController.all_area_ids():
		var a := load(StoryController.area_path(id)) as OverworldAreaResource
		if a != null:
			out.append(a)
	return out


func _area(id: String) -> OverworldAreaResource:
	return load(StoryController.area_path(id)) as OverworldAreaResource


## The story stages a spawn has to hold up under (entity presence follows the flags).
func _stages() -> Dictionary:
	var raided := StoryFixture.sent_off(StoryState.new())
	raided.set_flag("opening.attack", 1)
	return {
		"new": StoryState.new(),
		"sent_off": StoryFixture.sent_off(StoryState.new()),
		"raided": raided,
		"past_opening": StoryFixture.past_opening(StoryState.new()),
	}


func _warp_at(a: OverworldAreaResource, s: StoryState, c: Vector3i) -> WarpEntity:
	for e in a.present_entities(s):
		if e is WarpEntity and e.occupies(c):
			return e
	return null


func _interactable_at(a: OverworldAreaResource, s: StoryState, c: Vector3i) -> bool:
	for e in a.present_entities(s):
		if e.is_interactable() and e.occupies(c):
			return true
	return false


func _flatten(commands: Array) -> Array:
	var out: Array = []
	var stack: Array = commands.duplicate()
	while not stack.is_empty():
		var c = stack.pop_front()
		if not (c is StoryCommand):
			continue
		out.append(c)
		for l in (c as StoryCommand).child_lists():
			stack.append_array(l)
	return out


func test_every_entry_is_a_real_place_to_stand() -> void:
	var stages := _stages()
	for a in _areas():
		for stage in stages:
			var s: StoryState = stages[stage]
			var g := OverworldGrid.build(a, s)
			for eid in a.entry_ids():
				var e: Dictionary = a.entry(eid)
				var c: Vector3i = e["cell"]
				var tag: String = "%s/%s (%s)" % [a.area_id, eid, stage]
				assert_true(g.is_walkable(c), "%s: walkable, no prop or NPC on it (%s)" % [tag, g.blocker_at(c)])
				assert_null(_warp_at(a, s, c), "%s: not on an exit (no bounce-back)" % tag)
				assert_false(g.walkable_neighbours(c).is_empty(), "%s: not boxed in" % tag)
				# Facing: open ground, or whoever you are meant to wake up looking at (the Wayshrine,
				# your mother) -- never a wall, and never straight back into the exit.
				var f: Vector2i = OverworldEntity.facing_vector(String(e["facing"]))
				var fc := Vector3i(c.x + f.x, c.y + f.y, 0)
				assert_true(g.is_walkable(fc) or _interactable_at(a, s, fc),
					"%s: faces %s onto open ground or someone to talk to" % [tag, e["facing"]])
				assert_null(_warp_at(a, s, fc), "%s: does not face straight back into an exit" % tag)


func test_every_open_warp_lands_on_walkable_ground() -> void:
	var stages := _stages()
	for a in _areas():
		for stage in stages:
			var s: StoryState = stages[stage]
			for e in a.present_entities(s):
				if not (e is WarpEntity) or not (e as WarpEntity).is_open(s):
					continue
				var w := e as WarpEntity
				var t := _area(String(w.target_area))
				assert_not_null(t, "%s/%s targets a real area" % [a.area_id, w.id])
				if t == null:
					continue
				var te: Dictionary = t.entry(String(w.target_entry))
				assert_false(te.is_empty(), "%s/%s targets a real entry" % [a.area_id, w.id])
				if te.is_empty():
					continue
				var tg := OverworldGrid.build(t, s)
				for wc in w.cells():
					# Exactly StoryController.warp_to's choice.
					var arrive: Vector3i = te["cell"]
					var kept: Vector3i = w.arrival_cell(wc, arrive)
					if t.in_bounds(kept) and tg.is_walkable(kept):
						arrive = kept
					var tag: String = "%s/%s from %s -> %s %s (%s)" % [a.area_id, w.id, wc, t.area_id, arrive, stage]
					assert_true(tg.is_walkable(arrive), "%s: lands walkable" % tag)
					assert_null(_warp_at(t, s, arrive), "%s: not on the way-back exit" % tag)


func test_wayshrines_and_scripts_respawn_and_warp_to_real_entries() -> void:
	for a in _areas():
		var cmds: Array = _flatten(a.on_enter)
		for e in a.entity_list():
			cmds.append_array(_flatten(e.interact_script(String(a.area_id), StoryState.new())))
			cmds.append_array(_flatten(e.on_step))
			if e is WayshrineEntity:
				var r: Dictionary = a.entry(String((e as WayshrineEntity).respawn_entry))
				assert_false(r.is_empty(), "%s/%s: its respawn entry exists" % [a.area_id, e.id])
		for c in cmds:
			if c is SetRespawnCommand or c is WarpCommand:
				var t := _area(String(c.area_id))
				assert_not_null(t, "%s: %s targets a real area" % [a.area_id, c.describe()])
				if t != null:
					assert_false(t.entry(String(c.entry)).is_empty(), "%s: %s targets a real entry" % [a.area_id, c.describe()])


func test_scripted_moves_end_on_open_ground() -> void:
	# A move to an impassable cell falls back to a straight line THROUGH walls (cutscene staging):
	# Rowan once ran into the Chapel of the Starfall during the raid.
	for a in _areas():
		var g := OverworldGrid.from_map(a.terrain)
		var cmds: Array = _flatten(a.on_enter)
		for e in a.entity_list():
			cmds.append_array(_flatten(e.on_interact))
			cmds.append_array(_flatten(e.on_step))
		for c in cmds:
			if c is MoveActorCommand:
				assert_true(g.is_terrain_passable((c as MoveActorCommand).to),
					"%s: %s ends on passable terrain (%s)" % [a.area_id, c.describe(), g.tile_id_at((c as MoveActorCommand).to)])


func test_a_save_inside_a_rebuilt_wall_is_settled_onto_reachable_ground() -> void:
	var ch := _area("crownhaven")
	var s := StoryFixture.past_opening(StoryState.new())
	var g := OverworldGrid.build(ch, s)
	# Inside the chapel's wall (stone_wall), where open ground stood before Crownhaven was rebuilt.
	var wall := Vector3i(25, 10, 0)
	assert_false(g.is_walkable(wall), "the fixture cell is a wall")
	s.set_location("crownhaven", wall, "east")
	assert_true(StoryController.settle_location(s, ch), "the hero is moved")
	var c: Vector3i = s.location_cell()
	assert_true(g.is_walkable(c), "onto walkable ground (%s)" % c)
	assert_lte(absi(c.x - wall.x) + absi(c.y - wall.y), 1, "right beside where he was")
	assert_eq(s.location_facing(), "east", "facing kept")
	assert_false(TapPathfinder.find_path(g, c, ch.entry("west_gate")["cell"]).is_empty(), "and can walk out")
	# Standing on an NPC is moved too; a good spot is left alone.
	s.set_location("crownhaven", ch.entity("tam").cell, "south")
	assert_true(StoryController.settle_location(s, ch), "off an NPC")
	s.set_location("crownhaven", ch.entry("wayshrine")["cell"], "north")
	assert_false(StoryController.settle_location(s, ch), "a walkable, reachable cell is kept")
	assert_eq(s.location_cell(), ch.entry("wayshrine")["cell"], "unchanged")


func test_continue_journey_settles_the_loaded_location() -> void:
	var dir := "user://test_overworld_spawns/"
	StorySaveManager.set_save_dir(dir)
	StoryController.end_session()
	var s := StoryFixture.past_opening(StoryState.new())
	s.rng_seed = 7
	s.set_location("crownhaven", Vector3i(25, 10, 0), "south")
	assert_true(bool(StorySaveManager.save(1, s).get("success", false)), "saved")
	var r: Dictionary = StoryController.continue_journey(1)
	assert_true(bool(r.get("success", false)), "loads")
	var loaded: StoryState = StoryController.state()
	var g := OverworldGrid.build(_area("crownhaven"), loaded)
	assert_true(g.is_walkable(loaded.location_cell()), "the hero stands on open ground (%s)" % loaded.location_cell())
	StoryController.end_session()
	StorySaveManager.delete(1)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)


func test_grass_tables_resolve_and_towns_roll_nothing() -> void:
	var s := StoryFixture.past_opening(StoryState.new())
	for a in _areas():
		var g := OverworldGrid.from_map(a.terrain)
		for z in a.zones():
			var cells: int = 0
			for y in range(a.height()):
				for x in range(a.width()):
					var c := Vector3i(x, y, 0)
					if g.is_terrain_passable(c) and z.contains(c, g.tile_id_at(c)):
						cells += 1
			assert_gt(cells, 0, "%s: an encounter zone covers walkable grass" % a.area_id)
			var hits: int = 0
			for step in range(500):
				var r: Dictionary = EncounterRoller.roll(99, String(a.area_id), step, z, s)
				if bool(r["hit"]):
					hits += 1
					var entry: EncounterEntry = r["entry"]
					assert_not_null(CharacterLibrary.get_character(entry.character_id),
						"%s: wild %s is a real character" % [a.area_id, entry.character_id])
			assert_gt(hits, 0, "%s: the grass does ambush you" % a.area_id)
		if a.kind == OverworldAreaResource.Kind.TOWN:
			assert_eq(a.zones().size(), 0, "%s: a town has no wild encounters" % a.area_id)
	assert_gt(_area("mossway").zones().size(), 0, "the Mossway's grass is wild")
