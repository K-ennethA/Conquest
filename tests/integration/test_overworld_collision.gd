extends GutTest

## COLLISION AUDIT of every shipped overworld area (docs/STORY_MODE.md "Collision").
##
## The cart bug: PropEntity used to default `blocking` to false from _init(), while the exported
## default is true -- so ResourceSaver left a builder's `blocking = true` out of area.tres and the
## reload came back walk-through. Solidity is now per KIND ([constant PropEntity.SOLID_KINDS]) and
## is asserted here against the SHIPPED, re-loaded resources:
##   * every solid prop's cells are unwalkable on the real [OverworldGrid];
##   * walk-over decor (crops) stays walkable;
##   * making props solid never cuts anything off: from every entry point every warp, NPC (a
##     neighbouring cell), chest, sign, shrine, trigger and scripted-move target is still reachable
##     under each story stage -- and no solid prop sits on an entry, an exit, an actor or a
##     cutscene destination;
##   * a prop's model stays within (a little more than) its footprint.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")

## How far (metres) a prop's model may poke past its footprint rect. A cell is 2 m; hand-cart
## shafts, wheels and eaves overhang a little.
const MESH_OVERHANG := 0.8

var _areas_cache: Array[OverworldAreaResource] = []


func _areas() -> Array[OverworldAreaResource]:
	if _areas_cache.is_empty():
		for id in StoryController.all_area_ids():
			var a := load(StoryController.area_path(id)) as OverworldAreaResource
			if a != null:
				_areas_cache.append(a)
	return _areas_cache


func _area(id: String) -> OverworldAreaResource:
	for a in _areas():
		if String(a.area_id) == id:
			return a
	return null


## Story stages entity presence depends on: nothing done, then every opening flag cumulatively,
## then past the opening plus each other flag a condition mentions, one at a time.
func _stages() -> Array[StoryState]:
	var out: Array[StoryState] = [StoryState.new()]
	var s := StoryState.new()
	for f in StoryFixture.OPENING_FLAGS:
		s = StoryState.new()
		for g in StoryFixture.OPENING_FLAGS.slice(0, StoryFixture.OPENING_FLAGS.find(f) + 1):
			s.set_flag(g, 1)
		out.append(s)
	var done := StoryFixture.past_opening(StoryState.new())
	out.append(done)
	var extra: Dictionary = {}
	for a in _areas():
		for e in a.entity_list():
			_collect_flags(e.visible_if, extra)
			if e is WarpEntity:
				_collect_flags((e as WarpEntity).requires, extra)
	for f in extra:
		if StoryFixture.OPENING_FLAGS.has(f):
			continue
		var t := StoryFixture.past_opening(StoryState.new())
		t.set_flag(f, 1)
		out.append(t)
	return out


func _collect_flags(condition: String, into: Dictionary) -> void:
	var re := RegEx.new()
	re.compile("\"([a-z0-9_.]+)\"")
	for m in re.search_all(condition):
		into[m.get_string(1)] = true


# --- the shape of a prop ----------------------------------------------------------------------

func test_every_prop_kind_has_a_collision_rule() -> void:
	for k in PropEntity.KINDS:
		var p := PropEntity.new()
		p.prop = k
		var solid: bool = PropEntity.SOLID_KINDS.has(k)
		assert_eq(p.is_blocking(), solid, "%s: is_blocking follows SOLID_KINDS" % k)
	for k in PropEntity.SOLID_KINDS:
		assert_true(PropEntity.KINDS.has(k), "SOLID_KINDS names a real kind (%s)" % k)
	for k in ["cart", "barrels", "well", "stall", "haystack", "logs", "fence", "dummy", "crystal",
			"banner", "lamp", "scarecrow", "rubble", "statue", "house", "cabin", "chapel", "smithy",
			"keep", "tower", "windmill", "arena", "ruin"]:
		if PropEntity.KINDS.has(k):
			assert_true(PropEntity.SOLID_KINDS.has(k), "%s is solid" % k)
	assert_false(PropEntity.SOLID_KINDS.has("crops"), "crops are walk-over")
	assert_false(PropEntity.SOLID_KINDS.has("gate"), "a gatehouse's arch is walked UNDER (terrain decides)")


func test_the_explicit_collision_field_overrides_the_kind_default() -> void:
	var cart := PropEntity.new()
	cart.prop = "cart"
	assert_true(cart.is_blocking(), "a cart is solid by default")
	cart.collision = "walkable"
	assert_false(cart.is_blocking(), "...unless authored walkable")
	var crops := PropEntity.new()
	crops.prop = "crops"
	assert_false(crops.is_blocking(), "crops are walk-over by default")
	crops.collision = "solid"
	assert_true(crops.is_blocking(), "...unless authored solid")


func test_collision_survives_a_save_and_reload() -> void:
	# The original bug: a value equal to the exported default was dropped on save, and _init()
	# put a different one back on load.
	var tmp := "user://test_prop_collision.tres"
	for k in PropEntity.KINDS:
		for mode in ["auto", "solid", "walkable"]:
			var p := PropEntity.new()
			p.id = &"x"
			p.prop = k
			p.collision = mode
			var want: bool = p.is_blocking()
			assert_eq(ResourceSaver.save(p, tmp), OK, "saved")
			var back := ResourceLoader.load(tmp, "", ResourceLoader.CACHE_MODE_IGNORE) as PropEntity
			assert_not_null(back, "reloaded")
			if back != null:
				assert_eq(back.is_blocking(), want, "%s/%s: the same solidity after a round trip" % [k, mode])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


func test_shipped_solid_props_block_every_cell_of_their_footprint() -> void:
	var checked: int = 0
	var stages: Array[StoryState] = _stages()
	for a in _areas():
		var g := OverworldGrid.build(a, stages[0])
		for s in stages:
			g.rebuild_blockers(a, s)
			for e in a.present_entities(s):
				if not (e is PropEntity):
					continue
				var p := e as PropEntity
				if not p.is_blocking():
					continue
				for c in p.cells():
					checked += 1
					assert_false(g.is_walkable(c), "%s/%s (%s): cell %s is not walkable" % [a.area_id, p.id, p.prop, c])
	assert_gt(checked, 200, "the audit saw the shipped props")


func test_shipped_carts_are_solid() -> void:
	# The owner's report: Crownhaven's market cart.
	var ch := _area("crownhaven")
	var cart := ch.entity("market_cart") as PropEntity
	assert_not_null(cart, "Crownhaven has its market cart")
	var g := OverworldGrid.build(ch, StoryFixture.past_opening(StoryState.new()))
	for c in cart.cells():
		assert_true(g.is_terrain_passable(c), "the cart stands on open street")
		assert_false(g.is_walkable(c), "the player cannot walk through the cart at %s" % c)
		assert_eq(g.blocker_at(c), "market_cart", "the cart is the blocker")
	var cart_count: int = 0
	for a in _areas():
		for e in a.entity_list():
			if e is PropEntity and (e as PropEntity).prop == "cart":
				cart_count += 1
				assert_true((e as PropEntity).is_blocking(), "%s/%s is solid" % [a.area_id, e.id])
	assert_gt(cart_count, 3, "several carts ship")


func test_walk_over_decor_stays_walkable() -> void:
	var oak := _area("oakvale")
	var g := OverworldGrid.build(oak, StoryFixture.sent_off(StoryState.new()))
	var field := oak.entity("field") as PropEntity
	assert_not_null(field, "the crop field exists")
	var walkable: int = 0
	for c in field.cells():
		# (the scarecrow stands IN the field: only the cells no solid prop shares)
		if g.is_terrain_passable(c) and g.blocker_at(c).is_empty():
			assert_true(g.is_walkable(c), "crops can be walked over (%s)" % c)
			walkable += 1
	assert_gt(walkable, 5, "most of the field is open to walk over")


func test_a_two_cell_prop_blocks_both_cells() -> void:
	var a := OverworldAreaResource.new()
	a.area_id = &"collision_probe"
	var m := MapResource.new()
	m.width = 6
	m.height = 3
	for y in range(3):
		for x in range(6):
			m.set_tile_at_position(Vector2i(x, y), "NORMAL", "", "grass_plains")
	a.terrain = m
	var stall := PropEntity.new()
	stall.id = &"stall"
	stall.prop = "stall"
	stall.cell = Vector3i(2, 1, 0)
	stall.footprint = Vector2i(2, 1)
	var typed: Array[Resource] = [stall]
	a.entities = typed
	var g := OverworldGrid.build(a, StoryState.new())
	assert_false(g.is_walkable(Vector3i(2, 1, 0)), "the first cell")
	assert_false(g.is_walkable(Vector3i(3, 1, 0)), "the second cell")
	assert_true(g.is_walkable(Vector3i(4, 1, 0)), "and no further")
	assert_true(g.is_walkable(Vector3i(2, 0, 0)), "nor beside it")


# --- the models stay inside their footprints --------------------------------------------------

func test_prop_models_stay_within_their_footprints() -> void:
	var seen: int = 0
	var problems: Dictionary = {}
	for a in _areas():
		for e in a.entity_list():
			if not (e is PropEntity):
				continue
			var p := e as PropEntity
			var node: Node3D = OverworldProps.prop(p.prop, p.footprint, p.tint, 0)
			var box: AABB = _aabb(node)
			node.free()
			if box.size == Vector3.ZERO:
				continue
			seen += 1
			var cs: float = Cells.CELL_SIZE
			var x0: float = -cs * 0.5 - MESH_OVERHANG
			var z0: float = -cs * 0.5 - MESH_OVERHANG
			var x1: float = p.footprint.x * cs - cs * 0.5 + MESH_OVERHANG
			var z1: float = p.footprint.y * cs - cs * 0.5 + MESH_OVERHANG
			if box.position.x < x0 or box.position.z < z0 or box.end.x > x1 or box.end.z > z1:
				problems["%s/%s (%s %s): model spans x %.2f..%.2f z %.2f..%.2f m, footprint allows x %.2f..%.2f z %.2f..%.2f" % [
					a.area_id, p.id, p.prop, p.footprint, box.position.x, box.end.x, box.position.z, box.end.z, x0, x1, z0, z1]] = true
	assert_gt(seen, 100, "the audit measured the shipped props")
	var keys: Array = problems.keys()
	keys.sort()
	assert_eq(keys.size(), 0, "models poke out of their footprints:\n  " + "\n  ".join(PackedStringArray(keys)))


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first: bool = true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var mi := cur as MeshInstance3D
			var box: AABB = mi.mesh.get_aabb()
			var t: Transform3D = Transform3D.IDENTITY
			var walk: Node = mi
			while walk != null and walk != n:
				if walk is Node3D:
					t = (walk as Node3D).transform * t
				walk = walk.get_parent()
			box = t * box
			out = box if first else out.merge(box)
			first = false
		stack.append_array(cur.get_children())
	return out


# --- nothing becomes unreachable --------------------------------------------------------------

## The cells every present SOLID prop occupies (key Vector3i -> prop id).
func _solid_cells(a: OverworldAreaResource, s: StoryState) -> Dictionary:
	var out: Dictionary = {}
	for e in a.present_entities(s):
		if e is PropEntity and (e as PropEntity).is_blocking():
			for c in e.cells():
				out[c] = String(e.id)
	return out


## BFS over terrain minus [param solid] from [param seed]; the set of reachable cells.
func _flood(g: OverworldGrid, solid: Dictionary, seed_cell: Vector3i) -> Dictionary:
	return _flood_with(func(c: Vector3i) -> bool: return g.is_terrain_passable(c) and not solid.has(c), seed_cell)


## BFS over the cells [param walkable] accepts from [param seed_cell].
func _flood_with(walkable: Callable, seed_cell: Vector3i) -> Dictionary:
	var seen: Dictionary = {}
	if not walkable.call(seed_cell):
		return seen
	seen[seed_cell] = true
	var queue: Array[Vector3i] = [seed_cell]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_front()
		for d in OverworldGrid.DIRS:
			var n := Vector3i(c.x + d.x, c.y + d.y, c.z)
			if seen.has(n) or not walkable.call(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


func _any_reachable(reach: Dictionary, cells: Array) -> bool:
	for c in cells:
		if reach.has(c):
			return true
	return false


func _neighbours(c: Vector3i) -> Array:
	var out: Array = []
	for d in OverworldGrid.DIRS:
		out.append(Vector3i(c.x + d.x, c.y + d.y, c.z))
	return out


## The cells an entity can be used FROM: its own cells for walk-on things (warps, triggers), the
## neighbours of its cells for things you face (NPC, chest, sign, shrine, trainer).
func _use_cells(e: OverworldEntity) -> Array:
	if e is WarpEntity or e is TriggerZone:
		return e.cells()
	var out: Array = []
	for c in e.cells():
		out.append_array(_neighbours(c))
	return out


func test_every_destination_is_reachable_from_every_entry() -> void:
	var stages: Array[StoryState] = _stages()
	var targets: int = 0
	var cut_by_props: Dictionary = {}
	var cut_by_terrain: Dictionary = {}
	for a in _areas():
		var g := OverworldGrid.build(a, stages[0])
		var entries: Dictionary = {}
		for eid in a.entry_ids():
			entries[eid] = a.entry(eid)["cell"]
		for s in stages:
			g.rebuild_blockers(a, s)
			var solid: Dictionary = _solid_cells(a, s)
			var bare: Dictionary = {}
			# The walker's real rules (terrain + every present blocker: NPCs, signs, chests, the
			# shrine, props) against the same with the props taken away.
			var real := func(c: Vector3i) -> bool: return g.is_walkable(c)
			var no_props := func(c: Vector3i) -> bool:
				return g.is_terrain_passable(c) and (g.blocker_at(c).is_empty() or solid.has(c))
			for eid in entries:
				var reach: Dictionary = _flood(g, solid, entries[eid])
				var terrain_reach: Dictionary = _flood(g, bare, entries[eid])
				var real_reach: Dictionary = _flood_with(real, entries[eid])
				var npc_reach: Dictionary = _flood_with(no_props, entries[eid])
				assert_gt(reach.size(), 20, "%s/%s: the entry opens onto a real stretch of ground" % [a.area_id, eid])
				for e in a.present_entities(s):
					if e is PropEntity or not (e.has_actor() or e is WarpEntity or e is TriggerZone):
						continue
					var cells: Array = _use_cells(e)
					var key: String = "%s: %s '%s' %s from entry '%s'" % [a.area_id, e.kind(), e.id, str(e.cells()[0]), eid]
					targets += 1
					if not _any_reachable(terrain_reach, cells):
						cut_by_terrain[key] = true
					elif not _any_reachable(reach, cells):
						cut_by_props[key] = true
					elif _any_reachable(npc_reach, cells) and not _any_reachable(real_reach, cells):
						cut_by_props[key + " (with the NPCs in place)"] = true
	assert_gt(targets, 300, "the audit checked the shipped destinations")
	var keys: Array = cut_by_props.keys()
	keys.sort()
	assert_eq(keys.size(), 0, "a solid prop cuts these off:\n  " + "\n  ".join(PackedStringArray(keys)))
	keys = cut_by_terrain.keys()
	keys.sort()
	assert_eq(keys.size(), 0, "the terrain alone leaves these unreachable:\n  " + "\n  ".join(PackedStringArray(keys)))



func test_no_solid_prop_sits_on_an_entry_an_exit_or_an_actor() -> void:
	var stages: Array[StoryState] = _stages()
	var problems: Dictionary = {}
	for a in _areas():
		var g := OverworldGrid.from_map(a.terrain)
		for s in stages:
			var solid: Dictionary = _solid_cells(a, s)
			for eid in a.entry_ids():
				var c: Vector3i = a.entry(eid)["cell"]
				if solid.has(c):
					problems["%s: entry '%s' %s is under prop %s" % [a.area_id, eid, c, solid[c]]] = true
			for e in a.present_entities(s):
				if e is PropEntity:
					continue
				var walked: bool = e is WarpEntity or e is TriggerZone
				if not walked and not e.has_actor():
					continue
				for c in e.cells():
					# A warp over a wall (a map-edge cell) is never walked; only walkable cells count.
					if solid.has(c) and (not walked or g.is_terrain_passable(c)):
						problems["%s: %s '%s' %s is under prop %s" % [a.area_id, e.kind(), e.id, c, solid[c]]] = true
	var keys: Array = problems.keys()
	keys.sort()
	assert_eq(keys.size(), 0, "solid props sit on:\n  " + "\n  ".join(PackedStringArray(keys)))


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


## Every MoveActorCommand a script of [param a] can run: [{cmd, owner (entity or null)}].
func _moves(a: OverworldAreaResource, s: StoryState) -> Array:
	var out: Array = []
	for c in _flatten(a.on_enter):
		if c is MoveActorCommand:
			out.append({"cmd": c, "owner": null})
	for e in a.entity_list():
		var cmds: Array = _flatten(e.interact_script(String(a.area_id), s))
		cmds.append_array(_flatten(e.on_interact))
		cmds.append_array(_flatten(e.on_step))
		if e is TriggerZone:
			cmds.append_array(_flatten((e as TriggerZone).step_script(String(a.area_id))))
		if e is TrainerEntity:
			cmds.append_array(_flatten((e as TrainerEntity).encounter_script(String(a.area_id), e.cell, true)))
		for c in cmds:
			if c is MoveActorCommand:
				out.append({"cmd": c, "owner": e})
	return out


func test_scripted_walks_clear_the_props() -> void:
	# A cutscene walker routes over the grid and, failing a route, cuts straight through whatever
	# is in the way (OverworldController._path_for). So every scripted walk needs a REAL route
	# around the solid props from where the actor stands to where it is sent.
	var s := StoryFixture.past_opening(StoryState.new())
	var checked: int = 0
	for a in _areas():
		var g := OverworldGrid.from_map(a.terrain)
		var solid: Dictionary = _solid_cells(a, s)
		var bare: Dictionary = {}
		for m in _moves(a, s):
			var cmd: MoveActorCommand = m["cmd"]
			var owner: OverworldEntity = m["owner"]
			var who: String = cmd.actor
			if who == "self" or who.is_empty():
				who = String(owner.id) if owner != null else ""
			var starts: Array = []
			if who == "player" or who.is_empty():
				if owner != null:
					starts = [owner.cell]
					starts.append_array(_neighbours(owner.cell))
			else:
				var actor := a.entity(who)
				if actor == null:
					continue
				starts = [actor.cell]
			assert_false(solid.has(cmd.to), "%s: %s does not end inside prop %s" % [a.area_id, cmd.describe(), solid.get(cmd.to, "")])
			var any_start: bool = false
			for st in starts:
				if g.is_terrain_passable(st) and not solid.has(st):
					any_start = true
					# Reachable with props iff reachable without (terrain connectivity unchanged).
					var with_props: Dictionary = _flood(g, solid, st)
					var without: Dictionary = _flood(g, bare, st)
					if without.has(cmd.to):
						checked += 1
						assert_true(with_props.has(cmd.to),
							"%s: %s (from %s) still has a route around the props" % [a.area_id, cmd.describe(), st])
						break
			if not starts.is_empty() and not any_start:
				pending("%s: %s has no walkable start" % [a.area_id, cmd.describe()])
	assert_gt(checked, 10, "the audit followed the shipped cutscene walks")


# --- buildings, walls and arches --------------------------------------------------------------

const BUILDING_KINDS: Array[String] = ["house", "ruin", "keep", "cabin", "chapel", "smithy", "windmill", "arena"]


func test_building_models_sit_on_wall_terrain_and_every_wall_has_a_building() -> void:
	# A house is a model over a block of stone_wall terrain: no walking through a corner (the
	# whole footprint is solid) and no invisible wall (every wall cell outside Crownhaven's rampart
	# is under a building).
	var problems: Dictionary = {}
	for a in _areas():
		var g := OverworldGrid.from_map(a.terrain)
		var covered: Dictionary = {}
		for e in a.entity_list():
			if not (e is PropEntity):
				continue
			var p := e as PropEntity
			if p.prop == "tower" or p.prop == "gate" or BUILDING_KINDS.has(p.prop):
				for c in p.cells():
					covered[c] = true
			if BUILDING_KINDS.has(p.prop):
				for c in p.cells():
					if g.is_terrain_passable(c):
						problems["%s/%s: building cell %s stands on walkable terrain (%s)" % [a.area_id, p.id, c, g.tile_id_at(c)]] = true
		var rampart := Rect2i(3, 3, 25, 21)
		for y in range(g.height):
			for x in range(g.width):
				var c := Vector3i(x, y, 0)
				if g.tile_id_at(c) != &"stone_wall" or covered.has(c):
					continue
				var on_rampart: bool = String(a.area_id) == "crownhaven" and rampart.has_point(Vector2i(x, y)) \
					and not rampart.grow(-1).has_point(Vector2i(x, y))
				if not on_rampart:
					problems["%s: an unexplained wall at %s (no building over it)" % [a.area_id, c]] = true
	var keys: Array = problems.keys()
	keys.sort()
	assert_eq(keys.size(), 0, "walls and buildings disagree:\n  " + "\n  ".join(PackedStringArray(keys)))


func test_gatehouse_arches_are_walkable_and_their_towers_are_not() -> void:
	var seen: int = 0
	for a in _areas():
		var g := OverworldGrid.from_map(a.terrain)
		for e in a.entity_list():
			if not (e is PropEntity) or (e as PropEntity).prop != "gate":
				continue
			var cells: Array[Vector3i] = e.cells()
			seen += 1
			assert_false(g.is_terrain_passable(cells[0]), "%s/%s: its first tower is solid" % [a.area_id, e.id])
			assert_false(g.is_terrain_passable(cells[cells.size() - 1]), "%s/%s: its last tower is solid" % [a.area_id, e.id])
			for i in range(1, cells.size() - 1):
				assert_true(g.is_terrain_passable(cells[i]), "%s/%s: the arch is walked through" % [a.area_id, e.id])
	assert_gt(seen, 3, "Crownhaven's gatehouses were checked")


func test_the_overworld_is_a_single_floor() -> void:
	# OverworldGrid walks floor 0 only (M1); a tile on another floor would be an unreachable or
	# invisible-wall surprise. Stairs / bridges that need floors arrive with M2.
	for a in _areas():
		for entry in a.terrain.tile_layout:
			assert_eq(MapResource.entry_floor(entry), 0, "%s: every tile is on the ground floor" % a.area_id)


func test_props_never_wall_off_open_ground() -> void:
	# Every open cell the entries could reach on bare terrain is still reachable with the props
	# (and NPCs / signs) standing: no pocket of ground is sealed away behind scenery.
	var stages: Array[StoryState] = _stages()
	var problems: Dictionary = {}
	for a in _areas():
		var g := OverworldGrid.build(a, stages[0])
		var seeds: Array = []
		for eid in a.entry_ids():
			seeds.append(a.entry(eid)["cell"])
		for s in stages:
			g.rebuild_blockers(a, s)
			var solid: Dictionary = _solid_cells(a, s)
			var real := func(c: Vector3i) -> bool: return g.is_walkable(c)
			var no_props := func(c: Vector3i) -> bool:
				return g.is_terrain_passable(c) and (g.blocker_at(c).is_empty() or solid.has(c))
			var reach: Dictionary = {}
			var before: Dictionary = {}
			for sd in seeds:
				reach.merge(_flood_with(real, sd))
				before.merge(_flood_with(no_props, sd))
			for c in before:
				if not reach.has(c) and not solid.has(c) and g.blocker_at(c).is_empty():
					problems["%s: open ground at %s is walled off" % [a.area_id, c]] = true
	var keys: Array = problems.keys()
	keys.sort()
	assert_eq(keys.size(), 0, "props wall off open ground:\n  " + "\n  ".join(PackedStringArray(keys)))
