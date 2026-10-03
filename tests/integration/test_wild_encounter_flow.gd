extends GutTest

## WILD ENCOUNTER -> BATTLE START, end to end (docs/STORY_MODE.md "Visible wild creatures" and
## "Collision"). The overworld's grass rolls and visible creatures are covered where they were
## built (test_wild_spawns, test_story_duel_wiring); this suite pins the bugs found auditing the
## whole flow:
##   * a step that LANDS while a menu is open (the journey menu was openable mid-step) never fires
##     an encounter / warp behind the menu -- the arrival waits for it to close;
##   * a seeded grass roll starts a duel with exactly the foe EncounterRoller predicts, on the
##     step it predicts;
##   * a visible creature's contact, fought on the REAL duel stage, returns the party to the same
##     cell with the HP the duel left, and the creature is gone;
##   * a TACTICAL encounter row is not silently downgraded to a duel;
##   * every shipped encounter table is non-empty, names real characters, and builds a valid duel
##     request; no shipped roster ever spawns a creature on a blocked cell (a solid prop, a wall).
## Battles go through the debug DuelStub unless a test says otherwise; scene changes are off.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const Fix := preload("res://tests/helpers/wild_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const STAGE := preload("res://game/duel/DuelStage.tscn")
const TEMP_DIR := "user://test_wild_encounter_flow/"
const TEMP_ROSTER := "user://test_wild_encounter_flow_roster.json"

var _guard
var _world: Node = null
var _prev_scene: Node = null
var _stage: DuelStage = null


func before_all() -> void:
	RosterLedger.set_save_path(TEMP_ROSTER)


func after_all() -> void:
	if FileAccess.file_exists(TEMP_ROSTER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_ROSTER))
	RosterLedger.set_save_path(RosterLedger.DEFAULT_SAVE_PATH)


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	for k in ["selected_map_path", "selected_squad", "game_mode", "ai_difficulty", "player_count",
			"player_names"]:
		_guard.watch_setting(k)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false
	DuelController.reset()
	DuelController.record_profile = false
	DuelController.scene_changes_enabled = false
	RosterLedger.reset()
	CombatServices.clear()
	_stub_launcher()


func after_each() -> void:
	_free_stage()
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	StoryController._area_cache.erase(Fix.AREA_ID)
	DuelController.reset()
	DuelController.record_profile = true
	DuelController.scene_changes_enabled = true
	DuelLauncher.reset()
	DuelController.register_story_launcher()
	StoryController.register_debug_duel_stub()
	for n in get_tree().root.get_children():
		if n is DuelStub:
			n.free()
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	CombatServices.clear()
	CombatServices.match_rng = null
	_guard.restore()
	await get_tree().process_frame


func _stub_launcher() -> void:
	DuelLauncher.reset()
	StoryController.register_debug_duel_stub()


func _real_launcher() -> void:
	DuelLauncher.reset()
	DuelController.register_story_launcher()


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


func _free_stage() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.get_parent().remove_child(_stage)
		_stage.free()
	_stage = null


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _until(pred: Callable, max_frames: int = 600) -> bool:
	for i in range(max_frames):
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return bool(pred.call())


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


func _stub() -> DuelStub:
	return get_tree().root.get_node_or_null(DuelStub.NODE_NAME) as DuelStub


## A HIDDEN grass zone on the fixture meadow.
func _hidden(entries: Array, rate: float) -> OverworldAreaResource:
	var z = Fix.zone(entries, 1)
	z.mode = EncounterZone.Mode.HIDDEN
	z.rate = rate
	z.grace_steps = 0
	return Fix.area([z])


func test_a_step_that_lands_behind_an_open_menu_waits_for_it() -> void:
	_journey(_hidden([Fix.entry("petalfang")], 1.0), Vector3i(2, 4, 0), "east")
	var ow := await _boot()
	assert_true(ow.try_step(Vector2i(1, 0)), "the hero starts the step into the grass")
	ow.open_journey_menu()
	assert_true(ow.journey.is_open(), "the Esc key opens the menu mid-step")
	await _frames(8)
	assert_false(StoryController.is_script_running(), "no encounter fires behind the open menu")
	assert_null(StoryController.active_request(), "nor is a battle armed")
	assert_true(ow.is_moving(), "the arrival is still pending")
	ow.journey.close()
	await _frames(6)
	assert_false(ow.is_moving(), "closing the menu lets the step land")
	assert_true(StoryController.is_script_running() or StoryController.active_request() != null,
		"and the grass rolls (rate 1) once it has")


func test_a_seeded_grass_roll_starts_a_duel_with_the_predicted_foe() -> void:
	var table := [Fix.entry("petalfang", EncounterEntry.Behaviour.WANDER, 1.0),
		Fix.entry("blightcap", EncounterEntry.Behaviour.WANDER, 1.0)]
	var area := _hidden(table, 0.5)
	var s := _journey(area, Vector3i(2, 4, 0), "east")
	s.rng_seed = 424242
	var zone: EncounterZone = area.zones()[0]
	# The step the seeded roll first hits on (steps count up from the hero's current counter).
	var first: int = -1
	var expect: EncounterEntry = null
	for st in range(s.steps + 1, s.steps + 60):
		var r: Dictionary = EncounterRoller.roll(s.rng_seed, Fix.AREA_ID, st, zone, s)
		if bool(r["hit"]):
			first = st
			expect = r["entry"]
			break
	assert_gt(first, 0, "the seeded roll hits within 60 steps")
	var ow := await _boot()
	var fired: bool = false
	# Walk back and forth inside the grass (x 3..10): every step lands on a grass cell after the first.
	var dirs := [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(-1, 0), Vector2i(-1, 0)]
	for i in range(60):
		ow.try_step(dirs[i % dirs.size()])
		await _frames(3)
		if StoryController.is_script_running():
			fired = true
			break
	assert_true(fired, "the seeded grass fires an encounter")
	if not fired:
		return
	await _frames(3)
	assert_eq(s.steps, first, "on exactly the step the roll predicted")
	var req: BattleRequest = StoryController.active_request()
	assert_not_null(req, "a duel is armed")
	if req == null:
		return
	assert_eq(req.kind, BattleRequest.KIND_DUEL, "a duel")
	assert_eq(req.source, BattleRequest.SOURCE_WILD, "a wild encounter")
	assert_eq(String(req.opponent["team"][0]["character_id"]), String(expect.character_id), "against the predicted foe")
	assert_eq(req.encounter_id, "%s.grass.%s" % [Fix.AREA_ID, expect.character_id], "named for the grass roll")
	assert_eq(req.return_to["area_id"], Fix.AREA_ID, "returning to this area")
	_stub().resolve(BattleResult.OUTCOME_FLED)
	await _frames(3)


func test_contact_on_the_real_stage_returns_to_the_same_cell_with_the_duels_hp() -> void:
	_real_launcher()
	var e = Fix.entry("blightcap", EncounterEntry.Behaviour.WANDER)
	e.move_chance = 0.0
	var s := _journey(Fix.area([Fix.zone([e], 1)]), Vector3i(4, 4, 0), "east")
	var lead: StoryPartyMember = s.member("vineweave")
	var half: int = floori(lead.max_hp() * 0.5)
	lead.current_hp = half
	var ow := await _boot()
	var c = ow.wild.creatures[0]
	# Put it in front of the hero, facing him: a neutral, fair contact.
	if ow.grid.blocker_at(c.cell) == WildSpawner.blocker_id(c.key):
		ow.grid.clear_blocker(c.cell)
	c.cell = Vector3i(5, 4, 0)
	c.facing = Vector2i(-1, 0)
	ow.grid.set_blocker(c.cell, WildSpawner.blocker_id(c.key))
	ow.wild_actor(c.key).place(c.cell)
	ow.wild._persist_all()
	assert_false(ow.try_step(Vector2i(1, 0)), "walking into it is contact, not a step")
	await _frames(3)
	var req: DuelRequest = DuelController.active_request()
	assert_not_null(req, "the real duel is staged (no stub)")
	if req == null:
		return
	assert_null(_stub(), "the debug stub is not used")
	assert_eq(req.player_party[0].current_hp, half, "the lead enters with its carried HP")
	req.player_is_ai = true
	req.foe_party[0].strength = 0.1
	_stage = STAGE.instantiate()
	_stage.instant = true
	get_tree().root.add_child(_stage)
	var stage: DuelStage = _stage
	await _frames(2)
	assert_true(await _until(func() -> bool: return stage.battle.is_over, 900), "the duel ends")
	assert_eq(stage.battle.result.outcome, DuelResult.OUTCOME_VICTORY, "a win")
	var final_hp: int = int(stage.battle.result.party_after[0]["current_hp"])
	assert_true(await _until(func() -> bool: return stage.hud.results_visible()), "the results card is up")
	stage.hud.continue_button().pressed.emit()
	await _frames(3)
	assert_eq(s.location_area(), Fix.AREA_ID, "still in the meadow")
	assert_eq(s.location_cell(), Vector3i(4, 4, 0), "back on exactly the cell the hero stood on")
	assert_eq(lead.current_hp, final_hp, "with the HP the duel left him")
	# The overworld re-boots (the real game changes scene): the creature is gone, input is back.
	_free_stage()
	var ow2 := await _boot()
	await _drain(ow2)
	assert_eq(ow2.wild.creatures.size(), 0, "the beaten creature left the map")
	assert_eq(ow2.player.cell, Vector3i(4, 4, 0), "the hero stands where he fought")
	assert_false(ow2.is_input_blocked(), "and input is his again")
	assert_true(ow2.try_step(Vector2i(1, 0)), "he can walk on")


func test_a_tactical_encounter_row_is_not_downgraded_to_a_duel() -> void:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.map_path = "res://game/overworld/content/battles/ow_mossway_clearing.tres"
	spec.opponent_name = "Wild pack"
	var team: Array[Dictionary] = [{"character_id": "petalfang", "strength": 1.0}]
	spec.opponent_team = team
	var row := EncounterEntry.new()
	row.character_id = &"petalfang"
	row.kind = EncounterEntry.Kind.TACTICAL
	row.battle = spec
	var cmd := StartDuelCommand.new()
	cmd.entry = row
	cmd.area_id = "mossway"
	var req: BattleRequest = cmd.build_request(null)
	assert_not_null(req, "a request is built")
	assert_eq(req.kind, BattleRequest.KIND_TACTICAL, "a tactical row stays tactical")
	assert_eq(req.map_path, spec.map_path, "on its authored board")
	# And a plain row is still a duel.
	var plain := StartDuelCommand.new()
	plain.entry = Fix.entry("petalfang")
	plain.area_id = "mossway"
	assert_eq(plain.build_request(null).kind, BattleRequest.KIND_DUEL, "a duel row is a duel")


# --- the shipped tables ------------------------------------------------------------------------

func _areas() -> Array[OverworldAreaResource]:
	var out: Array[OverworldAreaResource] = []
	for id in StoryController.all_area_ids():
		var a := load(StoryController.area_path(id)) as OverworldAreaResource
		if a != null:
			out.append(a)
	return out


func test_every_shipped_encounter_table_is_playable() -> void:
	var zones: int = 0
	for a in _areas():
		for z in a.zones():
			zones += 1
			var where := "%s/%s" % [a.area_id, z.key(0)]
			assert_gt(z.entries().size(), 0, "%s: the table is not empty" % where)
			assert_gt(z.rate, 0.0, "%s: a hidden zone could roll" % where)
			assert_lte(z.rate, 1.0, "%s: the rate is a probability" % where)
			assert_gte(z.grace_steps, 0, "%s: grace steps" % where)
			assert_gt(z.max_active, 0, "%s: creatures stand in it" % where)
			var issues: Array[String] = []
			z.validate(issues, where)
			assert_eq(issues, [] as Array[String], "%s: the zone validates" % where)
			var weight: float = 0.0
			for e in z.entries():
				weight += e.weight
				assert_gt(e.strength, 0.0, "%s/%s: a foe with strength" % [where, e.character_id])
				var c: CharacterResource = CharacterLibrary.get_character(e.character_id)
				assert_not_null(c, "%s: %s is a real character" % [where, e.character_id])
				for opening in ["", BattleRequest.OPENING_AMBUSH, BattleRequest.OPENING_AMBUSHED, BattleRequest.OPENING_NEUTRAL]:
					for kind in ["grass", "wild"]:
						var req: BattleRequest = e.to_request(String(a.area_id), kind, opening)
						req.party = StoryBattleBridge.party_snapshot(StoryFixture.past_opening(StoryState.new()).healthy_members())
						assert_true(req.is_duel(), "%s/%s: a duel request" % [where, e.character_id])
						var built: Dictionary = DuelRequest.from_battle_request(req.to_dict())
						assert_true(bool(built.get("success", false)),
							"%s/%s: the duel request builds (%s)" % [where, e.character_id, str(built.get("reason", ""))])
				# A character with no model still gets a body (the overworld's placeholder figure).
				var actor := OverworldActor.new()
				if not actor.set_character_model(c):
					actor.set_model(OverworldProps.figure(Color(0.45, 0.36, 0.26), "villager"))
				assert_not_null(actor.model(), "%s/%s: the creature has a body on the map" % [where, e.character_id])
				actor.free()
			assert_gt(weight, 0.0, "%s: some row can be picked" % where)
	assert_gt(zones, 1, "the Mossway and the Sparse Forest ship wild zones")


func test_no_shipped_roster_spawns_on_a_blocked_cell() -> void:
	# A creature on a solid prop / wall would be an invisible wall (or unreachable for the hero).
	var s := StoryFixture.past_opening(StoryState.new())
	var spawned: int = 0
	for a in _areas():
		if a.zones().is_empty():
			continue
		var g := OverworldGrid.build(a, s)
		var props: Dictionary = {}
		for e in a.entity_list():
			for c in e.cells():
				props[c] = String(e.id)
		var arrive: Vector3i = a.entry(a.entry_ids()[0])["cell"]
		for seed_value in range(40):
			var st := StoryFixture.past_opening(StoryState.new())
			st.rng_seed = seed_value
			var w := WildSpawner.create(a, g, st)
			w.sync(arrive)
			for c in w.creatures:
				spawned += 1
				var own: String = WildSpawner.blocker_id(c.key)
				assert_true(g.is_terrain_passable(c.cell), "%s seed %d: %s is on open ground" % [a.area_id, seed_value, c.key])
				assert_false(props.has(c.cell), "%s seed %d: %s is not under %s" % [a.area_id, seed_value, c.key, props.get(c.cell, "")])
				assert_eq(g.blocker_at(c.cell), own, "%s seed %d: %s holds only its own cell" % [a.area_id, seed_value, c.key])
			# Let them wander: a step never takes a creature through a solid prop or onto a blocker.
			for step in range(25):
				st.steps += 1
				w.tick(arrive, false)
				for c in w.creatures:
					assert_true(g.is_terrain_passable(c.cell), "%s seed %d step %d: %s stays on open ground" % [a.area_id, seed_value, step, c.key])
					assert_false(props.has(c.cell), "%s seed %d step %d: %s does not wander into a prop" % [a.area_id, seed_value, step, c.key])
	assert_gt(spawned, 50, "the shipped zones spawned creatures to audit")


func test_a_save_standing_inside_a_now_solid_prop_is_settled_off_it() -> void:
	# Saves from before props were solid may stand in a cart's cell: loading puts the hero on open ground.
	var ch := load(StoryController.area_path("crownhaven")) as OverworldAreaResource
	var cart: OverworldEntity = ch.entity("market_cart")
	var s := StoryFixture.past_opening(StoryState.new())
	s.set_location("crownhaven", cart.cell, "east")
	var g := OverworldGrid.build(ch, s)
	assert_false(g.is_walkable(cart.cell), "the cart's cell is solid now")
	assert_true(StoryController.settle_location(s, ch), "the hero is moved")
	assert_true(g.is_walkable(s.location_cell()), "onto walkable ground")
	assert_lte(absi(s.location_cell().x - cart.cell.x) + absi(s.location_cell().y - cart.cell.y), 1, "right beside the cart")
