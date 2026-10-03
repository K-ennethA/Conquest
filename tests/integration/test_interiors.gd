extends GutTest

## ENTERABLE BUILDINGS (docs/STORY_MODE.md "Interiors"): opt-in doors on building facades, one
## interior template, the exit mat back to the door's front cell (facing away), the shipped list
## of enterable buildings (and that a plain house has no door), interior rooms that are reachable
## and encounter-free, a save made inside reloading inside, the world map's "You are here" and the
## quest tracker inside an interior, and the Royal Workshop's ceremony leading into the raid.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_interiors/"

## THE enterable buildings (town -> building prop ids). Everything else stays a plain block.
const ENTERABLE := {
	"oakvale": ["house_home", "house_inn", "house_hall", "house_bakery"],
	"river_crossing": ["toll_house"],
	"crownhaven": ["workshop", "barracks", "gilded_stag", "guildhall", "chapel", "forge"],
	"woodland_town": ["wardens_lodge", "stumped_hart", "trading_post", "forge", "herb_hut"],
}
const BUILDING_KINDS: Array[String] = ["house", "ruin", "keep", "cabin", "chapel", "smithy", "windmill", "arena"]

var _guard
var _scene: Node = null
var _prev_scene: Node = null


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false


func after_each() -> void:
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


# --- helpers -----------------------------------------------------------------------------------

func _area(id: String) -> OverworldAreaResource:
	return OverworldAreaResource.load_by_id(id)


func _doors(a: OverworldAreaResource) -> Array[DoorEntity]:
	var out: Array[DoorEntity] = []
	for e in a.entity_list():
		if e is DoorEntity:
			out.append(e as DoorEntity)
	return out


func _door_of(a: OverworldAreaResource, building: String) -> DoorEntity:
	for d in _doors(a):
		if String(d.building) == building:
			return d
	return null


func _teardown() -> void:
	if _scene != null and is_instance_valid(_scene):
		get_tree().current_scene = _prev_scene
		if _scene.get_parent() != null:
			_scene.get_parent().remove_child(_scene)
		_scene.free()
	_scene = null


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Boot the overworld where the journey stands (or at [param cell] of [param area]).
func _boot(area: String = "", cell: Vector3i = Cells.INVALID, facing: String = "south") -> OverworldController:
	var s: StoryState = StoryController.state()
	if area != "":
		if area != s.location_area():
			s.on_area_changed()
		s.set_location(area, cell, facing)
	_teardown()
	var n: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(n)
	get_tree().current_scene = n
	_scene = n
	await _frames(3)
	return n as OverworldController


## Read every line / answer every choice with the first option until the script ends or warps away.
func _drain(ow: OverworldController, max_frames: int = 1200) -> void:
	var start_area: String = StoryController.state().location_area()
	for i in range(max_frames):
		await get_tree().process_frame
		var d: StoryDialogue = ow.dialogue() if is_instance_valid(ow) else null
		if d != null and d.root_control().visible:
			if d.is_choosing():
				d.advance_clock(100.0)
				if d.choices_visible():
					d.choose(0)
			else:
				d.skip()
			continue
		if not StoryController.is_script_running():
			return
		if StoryController.state().location_area() != start_area:
			return


func _journey_past_opening() -> StoryState:
	StoryController.new_journey(0)
	var s: StoryState = StoryController.state()
	StoryFixture.past_opening(s)
	return s


# --- opt-in: which buildings have doors ---------------------------------------------------------

func test_a_default_building_has_no_door() -> void:
	var p := PropEntity.new()
	p.prop = "house"
	p.footprint = Vector2i(3, 2)
	assert_false(p.enterable, "a building is NOT enterable by default")
	assert_eq(p.door_cell(), Cells.INVALID, "and has no door cell")
	assert_true(p.is_blocking(), "it is a plain solid block")
	# The shipped towns: only the listed buildings have a door; every other building is a plain block.
	var plain: int = 0
	for id in StoryController.all_area_ids():
		var a := _area(id)
		var want: Array = ENTERABLE.get(id, [])
		for e in a.entity_list():
			if not (e is PropEntity) or not BUILDING_KINDS.has((e as PropEntity).prop):
				continue
			var b := e as PropEntity
			var door := _door_of(a, String(b.id))
			if want.has(String(b.id)):
				assert_true(b.enterable, "%s/%s is enterable" % [id, b.id])
				assert_not_null(door, "%s/%s has a door" % [id, b.id])
			else:
				plain += 1
				assert_false(b.enterable, "%s/%s is not enterable" % [id, b.id])
				assert_null(door, "%s/%s has no door (and no door marker)" % [id, b.id])
		assert_eq(_doors(a).size(), want.size(), "%s: exactly the opted-in doors" % id)
	assert_gt(plain, 10, "most buildings stay plain blocks (houses, the keep, the barn, ...)")
	for spec in [["crownhaven", "house_0"], ["oakvale", "house_farm"], ["woodland_town", "cabin_0"], ["crownhaven", "keep"]]:
		var b := _area(spec[0]).entity(spec[1]) as PropEntity
		assert_not_null(b, "%s/%s exists" % spec)
		if b != null:
			assert_false(b.enterable, "%s/%s: a default house has no door" % spec)


func test_every_door_leads_to_its_interior_and_back_out_front() -> void:
	var seen: int = 0
	for town in ENTERABLE:
		var a := _area(town)
		for d in _doors(a):
			seen += 1
			var b := a.entity(String(d.building)) as PropEntity
			assert_eq(d.cell, b.door_cell(), "%s/%s: the door is on the facade cell" % [town, d.id])
			assert_true(b.cells().has(d.cell), "inside the building's footprint")
			assert_eq(d.enter_dir, "north", "walked into from the south (the camera side)")
			var room := _area(String(d.target_area))
			assert_not_null(room, "%s/%s leads to %s" % [town, d.id, d.target_area])
			if room == null:
				continue
			assert_true(room.is_interior(), "%s is an INTERIOR" % room.area_id)
			assert_eq(String(room.parent_area), town, "%s belongs to %s" % [room.area_id, town])
			assert_false(room.entry(String(d.target_entry)).is_empty(), "the door arrives at a real entry")
			# The exit mat: back to the door's front cell, facing away from the building.
			var exits: Array = []
			for e in room.entity_list():
				if e is WarpEntity:
					exits.append(e)
			assert_eq(exits.size(), 1, "%s has one way out" % room.area_id)
			var exit := exits[0] as WarpEntity
			assert_eq(String(exit.target_area), town, "the exit leads back to %s" % town)
			var back: Dictionary = a.entry(String(exit.target_entry))
			assert_eq(back.get("cell"), d.front_cell(), "%s: out onto the door's front cell" % room.area_id)
			assert_eq(back.get("facing"), "south", "%s: facing away from the building" % room.area_id)
			var mat := room.entity("exit_mat") as PropEntity
			assert_not_null(mat, "%s has an exit mat" % room.area_id)
			if mat != null:
				assert_true(exit.occupies(mat.cell), "the exit is ON the mat")
				assert_false(mat.is_blocking(), "the mat is walked onto")
	assert_eq(seen, 16, "every opted-in building has its door")


func test_interiors_are_small_reachable_rooms_with_no_wild_creatures() -> void:
	var rooms: int = 0
	for id in StoryController.all_area_ids():
		var a := _area(id)
		if not a.is_interior():
			continue
		rooms += 1
		assert_eq(a.kind, OverworldAreaResource.Kind.INTERIOR, "%s is an interior" % id)
		assert_eq(a.zones().size(), 0, "%s: no wild encounters inside" % id)
		var fw: int = a.width() - 2
		var fh: int = a.height() - 1
		assert_true(fw >= 8 and fw <= 12 and fh >= 6 and fh <= 8, "%s: an 8x6 .. 12x8 floor (%dx%d)" % [id, fw, fh])
		for s in [StoryState.new(), StoryFixture.past_opening(StoryState.new())]:
			var g := OverworldGrid.build(a, s)
			var start: Vector3i = a.entry("door")["cell"]
			assert_true(g.is_walkable(start), "%s: you arrive on open floor" % id)
			var reach: Dictionary = {start: true}
			var queue: Array[Vector3i] = [start]
			while not queue.is_empty():
				var c: Vector3i = queue.pop_front()
				for n in g.walkable_neighbours(c):
					if not reach.has(n):
						reach[n] = true
						queue.append(n)
			var mat: Vector3i = (a.entity("exit_mat") as PropEntity).cell
			assert_true(reach.has(mat), "%s: the exit mat can be reached" % id)
			var open_floor: int = 0
			for y in range(1, a.height()):
				for x in range(1, a.width() - 1):
					var c := Vector3i(x, y, 0)
					if g.is_walkable(c):
						open_floor += 1
						assert_true(reach.has(c), "%s: floor cell %s is reachable" % [id, c])
			assert_gt(open_floor, 30, "%s: a room to walk round" % id)
	assert_eq(rooms, 16, "the shipped interiors")


# --- walking through doors ---------------------------------------------------------------------

func test_stepping_into_a_door_enters_its_interior_and_the_mat_returns_you_outside() -> void:
	var s := _journey_past_opening()
	var ch := _area("crownhaven")
	var door := _door_of(ch, "forge")
	var front: Vector3i = door.front_cell()
	# From the side (not facing the building), nothing happens.
	var ow := await _boot("crownhaven", Vector3i(front.x - 1, front.y, 0), "east")
	ow.try_step(Vector2i(1, 0))
	await _frames(3)
	assert_eq(s.location_area(), "crownhaven", "walking past a door does not enter it")
	assert_eq(ow.player.cell, front, "you just stand in front of it")
	# Facing the building: in.
	assert_eq(ow.entity_at(door.cell), door, "the door can be faced")
	assert_false(ow.try_step(Vector2i(0, -1)), "the door is not a cell to stand on")
	await _frames(3)
	assert_eq(s.location_area(), "crownhaven_forge", "stepping into the forge's door goes inside the forge")
	var room := _area("crownhaven_forge")
	assert_eq(s.location_cell(), room.entry("door")["cell"], "onto the cell above the exit mat")
	assert_eq(s.location_facing(), "north", "facing into the room")
	# Inside: step onto the mat.
	ow = await _boot()
	assert_eq(ow.area.area_id, &"crownhaven_forge", "the interior boots")
	assert_eq(ow.camera.bounds, OverworldController.camera_bounds_for(room), "the camera frames the room")
	assert_eq(ow.camera.distance, OverworldCamera.INTERIOR_DISTANCE, "a little closer than outdoors")
	assert_true(ow.try_step(Vector2i(0, 1)), "step onto the exit mat")
	await _frames(6)
	assert_eq(s.location_area(), "crownhaven", "the mat leads back out")
	assert_eq(s.location_cell(), front, "to the cell in front of the door")
	assert_eq(s.location_facing(), "south", "facing away from the building")


func test_confirm_on_a_door_enters_too_and_plain_houses_do_not_open() -> void:
	var s := _journey_past_opening()
	var oak := _area("oakvale")
	var door := _door_of(oak, "house_home")
	var ow := await _boot("oakvale", door.front_cell(), "north")
	assert_true(ow.hud.prompt_text().contains("Enter"), "the prompt says Enter (%s)" % ow.hud.prompt_text())
	assert_true(ow.interact(), "Confirm on the hero's front door")
	await _frames(3)
	assert_eq(s.location_area(), "oakvale_home", "goes into the hero's home")
	# A plain house: walking into it is just a bump.
	var farm := oak.entity("house_farm") as PropEntity
	var below := Vector3i(farm.cell.x + 1, farm.cell.y + farm.footprint.y, 0)
	ow = await _boot("oakvale", below, "north")
	assert_false(ow.try_step(Vector2i(0, -1)), "a bump")
	await _frames(3)
	assert_eq(s.location_area(), "oakvale", "the farmhouse is not enterable")


# --- saves, the map, the tracker -----------------------------------------------------------------

func test_a_save_inside_an_interior_loads_back_inside() -> void:
	assert_true(bool(StoryController.new_journey(1)["success"]), "a journey in slot 1")
	var s: StoryState = StoryController.state()
	StoryFixture.past_opening(s)
	var resp: Dictionary = s.respawn.duplicate()
	s.on_area_changed()
	s.set_location("woodland_inn", Vector3i(4, 3, 0), "west")
	assert_true(bool(StoryController.save_game()["success"]), "saved inside the Stumped Hart")
	StoryController.end_session()
	assert_true(bool(StoryController.continue_journey(1)["success"]), "loaded")
	var t: StoryState = StoryController.state()
	assert_eq(t.location_area(), "woodland_inn", "back inside the inn")
	assert_eq(t.location_cell(), Vector3i(4, 3, 0), "where you stood")
	assert_eq(t.location_facing(), "west", "facing the same way")
	assert_eq(t.respawn, resp, "the respawn point is unchanged (interiors are not Wayshrines)")
	var ow := await _boot()
	assert_eq(ow.area.area_id, &"woodland_inn", "the interior boots from the save")
	assert_eq(ow.player.cell, Vector3i(4, 3, 0), "with the hero where they stood")


func test_the_world_map_says_you_are_in_the_town_inside_an_interior() -> void:
	var atlas := WorldAtlas.load_default()
	for town in ENTERABLE:
		var place: WorldLocation = atlas.location_for_area(town)
		for d in _doors(_area(town)):
			var l: WorldLocation = atlas.location_for_area(String(d.target_area))
			assert_not_null(l, "%s is on the map" % d.target_area)
			if l != null:
				assert_eq(l.id, place.id, "%s is part of %s" % [d.target_area, place.id])
	var ids: Array[String] = atlas.location_ids()
	for id in ["crownhaven_workshop", "oakvale_home"]:
		assert_false(ids.has(id), "%s is not a place of its own" % id)
	var s := StoryState.new()
	s.set_location("crownhaven_workshop", Vector3i(6, 6, 0), "north")
	var view := WorldMapView.new()
	add_child_autofree(view)
	view.setup(atlas, s)
	assert_eq(view.here_id(), "crownhaven", "You are here: Crownhaven")


func test_the_quest_tracker_counts_an_interior_as_its_town() -> void:
	StoryController.new_journey(0)
	var s: StoryState = StoryController.state()
	StoryFixture.sent_off(s)
	s.set_flag("opening.arrived_crownhaven", 1)
	var e: Dictionary = QuestLog.tracked_entry(s)
	assert_eq(String(e.get("area", "")), "crownhaven_workshop", "the objective: Professor Elias, inside the workshop")
	var ow := await _boot("crownhaven_workshop", Vector3i(6, 6, 0), "north")
	assert_eq(ow.hud.tracker_place(), "Here", "inside the workshop: Here")
	assert_eq(ow.objective_marker_actor(), "elias", "with Elias marked")
	ow = await _boot("crownhaven", Vector3i(24, 7, 0), "north")
	assert_eq(ow.hud.tracker_place(), "Here", "in Crownhaven, the workshop is here too")
	ow = await _boot("river_crossing", Vector3i(11, 2, 0), "north")
	assert_eq(ow.hud.tracker_place(), "→ Crownhaven", "elsewhere it points the way")


# --- the Royal Workshop: the ceremony inside, the raid outside ------------------------------------

func test_the_workshop_ceremony_gives_the_starter_and_the_shard_then_the_raid_in_the_yard() -> void:
	assert_true(bool(StoryController.new_journey(1)["success"]), "a journey")
	var s: StoryState = StoryController.state()
	StoryFixture.sent_off(s)
	s.set_flag("opening.arrived_crownhaven", 1)
	var ow := await _boot("crownhaven_workshop", Vector3i(6, 3, 0), "north")
	assert_eq(ow.entity_at(Vector3i(6, 2, 0)).id, &"elias", "Professor Elias waits inside")
	assert_true(ow.interact(), "talk to him")
	await _drain(ow)
	assert_true(s.has_flag("opening.starter_received"), "the starter is received")
	assert_true(s.has_flag("key.bonding_shard"), "and the bonding shard")
	assert_eq(s.get_flag_int("opening.starter_pick"), 1, "the first option was picked")
	assert_eq(s.party.size(), 1, "one creature")
	assert_false(s.has_flag("opening.attack"), "the raid does not happen indoors")
	assert_eq(s.location_area(), "crownhaven", "the alarm: out into the yard")
	assert_eq(s.location_cell(), _door_of(_area("crownhaven"), "workshop").front_cell(), "in front of the workshop door")
	# A journey stopped right here (saved in the workshop) is sent back out to the raid.
	var inside := await _boot("crownhaven_workshop", Vector3i(6, 6, 0), "north")
	await _frames(3)
	assert_eq(s.location_area(), "crownhaven", "re-entering mid-opening puts you back in the yard")
	assert_not_null(inside, "booted")
	ow = await _boot()
	assert_true(StoryController.is_script_running(), "the raid plays in the yard")
	await _drain(ow)
	for f in ["opening.attack", "opening.researcher_taken", "opening.raiders_fled", "opening.chase"]:
		assert_true(s.has_flag(f), "the raid sets %s" % f)
	assert_eq(s.location_area(), "oakvale_ruins", "and the chase leads home")
