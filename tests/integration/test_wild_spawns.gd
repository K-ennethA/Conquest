extends GutTest

## VISIBLE WILD CREATURES in the real OverworldScene, on the test-only fixture area
## (tests/helpers/wild_fixture.gd, handed to StoryController's area cache -- no shipped content):
## the roster is mounted as actors + grid blockers; walking into a creature's back is an AMBUSH
## (the duel request's rules["opening"]); a creature walking into you is AMBUSHED; grace steps
## and a traveller with no partner are left alone; a win despawns it (and it stays gone across a
## round trip and a save + reload), a flee leaves it standing; a HIDDEN zone still rolls.
## Battles go through the debug DuelStub; scene changes are off (the suite re-boots the scene).

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const Fix := preload("res://tests/helpers/wild_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_wild_spawns/"

var _guard
var _world: Node = null
var _prev_scene: Node = null


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	_guard.watch_setting("selected_map_path")
	_guard.watch_setting("selected_squad")
	_guard.watch_setting("game_mode")
	_guard.watch_setting("ai_difficulty")
	_guard.watch_setting("player_count")
	_guard.watch_setting("player_names")
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false
	DuelLauncher.reset()
	StoryController.register_debug_duel_stub()


func after_each() -> void:
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	StoryController._area_cache.erase(Fix.AREA_ID)
	DuelLauncher.reset()
	DuelController.register_story_launcher()
	StoryController.register_debug_duel_stub()
	for n in get_tree().root.get_children():
		if n is DuelStub:
			n.free()
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


## A journey past the opening standing on the fixture area at [param cell].
func _journey(a: OverworldAreaResource, cell: Vector3i = Fix.ENTRY, facing: String = "east") -> StoryState:
	StoryController._area_cache[Fix.AREA_ID] = a
	StoryController.new_journey(1)
	var s: StoryState = StoryFixture.past_opening(StoryController.state())
	s.on_area_changed()
	s.set_location(Fix.AREA_ID, cell, facing)
	s.grace_steps = 0
	return s


func _boot() -> OverworldController:
	_teardown()
	var w: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	await get_tree().process_frame
	await get_tree().process_frame
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _step(ow: OverworldController, dir: Vector2i) -> bool:
	var ok: bool = ow.try_step(dir)
	await _frames(3)
	return ok


func _drain(ow: OverworldController, pick: int = 1, max_frames: int = 600) -> void:
	for i in range(max_frames):
		await get_tree().process_frame
		var d: StoryDialogue = ow.dialogue() if is_instance_valid(ow) else null
		if d != null and d.root_control().visible:
			if d.is_choosing():
				d.advance_clock(100.0)
				if d.choices_visible():
					d.choose(pick)
			else:
				d.skip()
			continue
		if not StoryController.is_script_running():
			return


## Move live creature [param c] (and its actor) to [param cell], facing [param facing].
func _put(ow: OverworldController, c, cell: Vector3i, facing: Vector2i) -> void:
	if ow.grid.blocker_at(c.cell) == WildSpawner.blocker_id(c.key):
		ow.grid.clear_blocker(c.cell)
	c.cell = cell
	c.facing = facing
	ow.grid.set_blocker(cell, WildSpawner.blocker_id(c.key))
	var a: OverworldActor = ow.wild_actor(c.key)
	a.place(cell)
	a.set_facing(facing)
	ow.wild._persist_all()
	ow._update_prompt()


func _stub() -> DuelStub:
	return get_tree().root.get_node_or_null(DuelStub.NODE_NAME) as DuelStub


func _solo(behaviour: int = EncounterEntry.Behaviour.WANDER) -> OverworldAreaResource:
	var e = Fix.entry("petalfang", behaviour)
	e.sense_range = 4
	e.move_chance = 0.0
	return Fix.area([Fix.zone([e], 1)])


func test_the_roster_is_mounted_as_actors_and_blockers() -> void:
	_journey(Fix.area())
	var ow := await _boot()
	assert_not_null(ow.wild, "the spawner is up")
	assert_eq(ow.wild.creatures.size(), 4, "four creatures stand in the grass")
	assert_eq(ow.get_node("Wild").get_child_count(), 4, "each with an actor")
	for c in ow.wild.creatures:
		var a: OverworldActor = ow.wild_actor(c.key)
		assert_not_null(a, "%s has an actor" % c.key)
		assert_eq(a.cell, c.cell, "standing on its cell")
		assert_not_null(a.model(), "with its roster model as the placeholder body")
		assert_false(ow.grid.is_walkable(c.cell), "and blocking its cell")
		assert_eq(ow.actor(WildSpawner.blocker_id(c.key)), a, "actor() finds it by blocker id")
	var cells: Array = []
	for c in ow.wild.creatures:
		cells.append(c.cell)
	# Same visit: a re-boot (a battle round trip) finds everyone where they stood.
	var ow2 := await _boot()
	var cells2: Array = []
	for c in ow2.wild.creatures:
		cells2.append(c.cell)
	assert_eq(cells2, cells, "a re-boot within the visit keeps every creature in place")


func test_walking_into_its_back_is_an_ambush_and_a_win_despawns_it() -> void:
	var s := _journey(_solo(), Vector3i(4, 4, 0), "east")
	var ow := await _boot()
	var c = ow.wild.creatures[0]
	_put(ow, c, Vector3i(5, 4, 0), Vector2i(1, 0))
	assert_eq(ow.hud.prompt_text().contains("Battle"), true, "facing a creature offers a battle")
	assert_false(await _step(ow, Vector2i(1, 0)), "contact is not a step")
	assert_eq(ow.player.cell, Vector3i(4, 4, 0), "the hero stays put")
	assert_true(StoryController.is_script_running(), "the wild battle starts")
	await _frames(3)
	var req: BattleRequest = StoryController.active_request()
	assert_not_null(req, "a duel is armed")
	assert_eq(req.kind, BattleRequest.KIND_DUEL, "a duel")
	assert_eq(req.encounter_id, "wild_test.wild.petalfang", "a visible creature's encounter id")
	assert_eq(req.opening(), BattleRequest.OPENING_AMBUSH, "from behind: an ambush")
	assert_not_null(_stub(), "through the duel stub")
	_stub().resolve(BattleResult.OUTCOME_VICTORY)
	await _frames(3)
	var ow2 := await _boot()
	await _drain(ow2)
	assert_eq(ow2.wild.creatures.size(), 0, "beaten: it left the map")
	assert_null(ow2.wild_actor(c.key), "and its actor")
	assert_true(ow2.grid.is_walkable(Vector3i(5, 4, 0)), "its cell is free")
	assert_eq((s.wild["wild_test|z0"]["slots"] as Dictionary).size(), 0, "the save record forgot it")
	StoryController.save_game()
	StoryController.end_session()
	StoryController._area_cache[Fix.AREA_ID] = ow2.area
	StoryController.continue_journey(1)
	var ow3 := await _boot()
	assert_eq(ow3.wild.creatures.size(), 0, "after a reload it is still gone (ON_REENTER: until you come back)")
	StoryController.state().on_area_changed()
	var ow4 := await _boot()
	assert_eq(ow4.wild.creatures.size(), 1, "re-entering the area brings the zone back")


func test_face_to_face_is_neutral_and_a_flee_leaves_it_standing() -> void:
	_journey(_solo(), Vector3i(4, 4, 0), "east")
	var ow := await _boot()
	var c = ow.wild.creatures[0]
	_put(ow, c, Vector3i(5, 4, 0), Vector2i(-1, 0))
	assert_true(ow.interact(), "Confirm on a creature is contact too")
	await _frames(3)
	assert_eq(StoryController.active_request().opening(), BattleRequest.OPENING_NEUTRAL, "face to face: neutral")
	_stub().resolve(BattleResult.OUTCOME_FLED)
	await _frames(3)
	var ow2 := await _boot()
	await _drain(ow2)
	assert_eq(ow2.wild.creatures.size(), 1, "fled: it is still there")
	assert_eq(ow2.wild.creatures[0].cell, Vector3i(5, 4, 0), "exactly where it stood")


func test_a_creature_walking_into_you_ambushes_you() -> void:
	_journey(_solo(EncounterEntry.Behaviour.AGGRESSIVE), Vector3i(5, 5, 0), "north")
	var ow := await _boot()
	var c = ow.wild.creatures[0]
	_put(ow, c, Vector3i(6, 4, 0), Vector2i(-1, 0))
	assert_true(await _step(ow, Vector2i(0, -1)), "the hero steps into its line of sight")
	assert_true(StoryController.is_script_running(), "it charges: a battle")
	await _frames(3)
	assert_eq(StoryController.active_request().opening(), BattleRequest.OPENING_AMBUSHED,
		"walked into: the foe moves first")
	_stub().resolve(BattleResult.OUTCOME_FLED)
	await _frames(3)


func test_grace_steps_and_no_partner_are_left_alone() -> void:
	var s := _journey(_solo(EncounterEntry.Behaviour.AGGRESSIVE), Vector3i(5, 5, 0), "north")
	s.grace_steps = 2
	var ow := await _boot()
	var c = ow.wild.creatures[0]
	_put(ow, c, Vector3i(6, 4, 0), Vector2i(-1, 0))
	await _step(ow, Vector2i(0, -1))
	assert_false(StoryController.is_script_running(), "during grace it does not walk into you")
	assert_eq(c.cell, Vector3i(6, 4, 0), "it glares from next door")
	assert_eq(s.grace_steps, 1, "a grace step was spent")
	# No partner (the opening): even walking into it starts nothing.
	s.party.clear()
	ow.player.turn_to(Vector2i(1, 0))
	assert_false(await _step(ow, Vector2i(1, 0)), "a bump")
	assert_false(StoryController.is_script_running(), "no battle without a creature to fight with")
	await _step(ow, Vector2i(0, 1))
	await _step(ow, Vector2i(0, -1))
	assert_false(StoryController.is_script_running(), "and it never charges a traveller with no partner")


func test_hidden_zone_still_rolls_in_the_grass() -> void:
	var z = Fix.zone([Fix.entry("petalfang")], 1)
	z.mode = EncounterZone.Mode.HIDDEN
	z.rate = 1.0
	_journey(Fix.area([z]), Vector3i(2, 4, 0), "east")
	var ow := await _boot()
	assert_eq(ow.wild.creatures.size(), 0, "a hidden zone shows nobody")
	await _step(ow, Vector2i(1, 0))
	assert_true(StoryController.is_script_running(), "stepping into the grass rolls (rate 1)")
	await _frames(3)
	var req: BattleRequest = StoryController.active_request()
	assert_eq(req.encounter_id, "wild_test.grass.petalfang", "a grass encounter")
	assert_false(req.rules.has(BattleRequest.RULE_OPENING), "with no contact opening")
	_stub().resolve(BattleResult.OUTCOME_FLED)
	await _frames(3)
