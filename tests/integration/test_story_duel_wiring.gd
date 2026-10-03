extends GutTest

## STORY -> REAL DUEL wiring (docs/STORY_MODE.md "Wiring"): the shipped DuelLauncher seam holds
## DuelController (the debug DuelStub is only a fallback), so a tall-grass encounter stages a
## real story DuelRequest and runs on the real DuelStage. Covered end to end:
##   * grass -> duel (1 wild foe, the party lead with its CARRIED HP) -> win -> the results
##     card's Continue reports ONCE -> back where the hero stood -> the befriend prompt ->
##     "Welcome it" -> the party grows; the lead that fought earns Growth, the bench does not
##     and keeps its HP;
##   * a lost wild duel whites out to the Wayshrine, healed, with no Growth;
##   * fleeing ends the duel as "fled": HP carried, no Growth, the hero stays put;
##   * the story-critical recruit always offers on a win.
## Scene changes are off on both controllers; the suite mounts the stage and re-boots the
## overworld itself. The befriend / flee odds are pinned on the shared ruleset (restored after):
## the seeded rolls themselves are covered by test_duel_lifecycle.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const STAGE := preload("res://game/duel/DuelStage.tscn")
const TEMP_DIR := "user://test_story_duel_wiring/"
const TEMP_ROSTER := "user://test_story_duel_wiring_roster.json"

var _guard
var _world: Node = null
var _prev_scene: Node = null
var _stage: DuelStage = null
var _rules_backup: Dictionary = {}
## HELD for the whole test: a Resource nobody references drops out of the cache, and the next
## load() would re-read the shipped odds from disk.
var _rules: DuelRuleset = null
## A shared area whose zone modes a test forced (restored in after_each).
var _hidden_area: OverworldAreaResource = null
var _hidden_modes: Array = []


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
	_restore_shipped_launchers()
	RosterLedger.reset()
	_rules = DuelRuleset.load_default()
	_rules_backup = {"befriend_base_chance": _rules.befriend_base_chance, "flee_base": _rules.flee_base}
	CombatServices.clear()


func after_each() -> void:
	_free_stage()
	_teardown()
	StoryFixture.restore_zone_modes(_hidden_area, _hidden_modes)
	_hidden_area = null
	_hidden_modes = []
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	DuelController.reset()
	DuelController.record_profile = true
	DuelController.scene_changes_enabled = true
	_restore_shipped_launchers()
	for k in _rules_backup.keys():
		_rules.set(k, _rules_backup[k])
	_rules = null
	for n in get_tree().root.get_children():
		if n is DuelStub or n is EvolutionScreen:
			n.free()
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	CombatServices.clear()
	CombatServices.match_rng = null
	_guard.restore()
	await get_tree().process_frame


func _restore_shipped_launchers() -> void:
	DuelLauncher.reset()
	DuelController.register_story_launcher()
	StoryController.register_debug_duel_stub()


func _boot(area: String = "", cell: Vector3i = Cells.INVALID, facing: String = "south") -> OverworldController:
	if not StoryController.has_session():
		StoryController.new_journey(1)
		StoryFixture.past_opening(StoryController.state())
	if area != "":
		var s: StoryState = StoryController.state()
		if area != s.location_area():
			s.on_area_changed()
		s.set_location(area, cell, facing)
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


func _drain(ow: OverworldController, pick: int = 0, max_frames: int = 600) -> void:
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


## The staged story duel on the real stage (instant pacing, under the root like a scene).
func _mount_stage() -> DuelStage:
	_stage = STAGE.instantiate()
	_stage.instant = true
	get_tree().root.add_child(_stage)
	await _frames(2)
	return _stage


## A wild Mossway duel staged straight through StoryController (no walk).
func _begin_wild(character_id: StringName) -> DuelRequest:
	var entry := EncounterEntry.new()
	entry.character_id = character_id
	var began: Dictionary = StoryController.begin_battle(entry.to_request("mossway"))
	assert_true(bool(began["success"]), "the wild duel launches (%s)" % String(began.get("reason", "")))
	return DuelController.active_request()


func _press_continue() -> void:
	assert_true(await _until(func() -> bool: return _stage.hud.results_visible()), "the results card is up")
	var cont: Button = _stage.hud.continue_button()
	assert_not_null(cont, "a story duel's card offers Continue Journey")
	if cont != null:
		cont.pressed.emit()
	await _frames(3)


func test_grass_encounter_runs_the_real_duel_and_a_befriend_grows_the_party() -> void:
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())
	var s: StoryState = StoryController.state()
	s.grace_steps = 0
	var lead: StoryPartyMember = s.member("vineweave")
	var half: int = floori(lead.max_hp() * 0.5)
	lead.current_hp = half
	s.member("blightcap").current_hp = 20
	# The per-step roll is the HIDDEN zone mode (visible creatures are the default; their contact
	# battles are test_wild_spawns'): force the Mossway's grass hidden for this test.
	_hidden_area = StoryController.load_area("mossway")
	_hidden_modes = StoryFixture.set_zone_modes(_hidden_area, EncounterZone.Mode.HIDDEN)
	var ow := await _boot("mossway", Vector3i(4, 2, 0), "east")
	var fired := false
	for i in range(80):
		var dir := Vector2i(1, 0) if (i / 4) % 2 == 0 else Vector2i(-1, 0)
		ow.try_step(dir)
		await _frames(3)
		if StoryController.is_script_running():
			fired = true
			break
	assert_true(fired, "walking the tall grass rolls a wild encounter")
	if not fired:
		return
	await _frames(2)
	var stood: Vector3i = s.location_cell()
	assert_null(get_tree().root.get_node_or_null(DuelStub.NODE_NAME), "the debug stub is NOT used")
	var req: DuelRequest = DuelController.active_request()
	assert_not_null(req, "DuelController staged the story duel")
	if req == null:
		return
	assert_true(DuelController.is_story_duel(), "a story-origin duel")
	assert_true(req.is_wild(), "a wild encounter")
	assert_eq(req.foe_party.size(), 1, "wild encounters are one foe")
	assert_true(req.can_befriend(), "the grass table allows befriending")
	assert_eq(req.player_party[0].member_id, "vineweave", "the party lead steps forward")
	assert_eq(req.player_party[0].current_hp, half, "with its carried HP")
	var foe_id: String = String(req.foe_party[0].character_id)
	# Make the win and the offer certain (the seeded roll is pinned by test_duel_lifecycle).
	_rules.befriend_base_chance = 1.0
	req.player_is_ai = true
	req.foe_party[0].strength = 0.1
	# Read the HP in the SAME frame the stage enters the tree: setup (and the carried HP)
	# happens in _ready, the fight only starts deferred. Reading after a few frames raced
	# the AI's first swing on a busy full-suite run.
	_stage = STAGE.instantiate()
	_stage.instant = true
	get_tree().root.add_child(_stage)
	var stage: DuelStage = _stage
	assert_eq(int(stage.battle.unit_of(0).get_hp()), half, "the duel unit starts at the carried HP")
	await _frames(2)
	assert_true(await _until(func() -> bool: return stage.battle.is_over, 900), "the duel ends")
	assert_eq(stage.battle.result.outcome, DuelResult.OUTCOME_VICTORY, "a win")
	assert_null(StoryController.last_result(), "nothing is reported before the card's Continue")
	var final_hp: int = int(stage.battle.result.party_after[0]["current_hp"])
	await _press_continue()
	var br: BattleResult = StoryController.last_result()
	assert_not_null(br, "Continue reported the result to StoryController")
	if br == null:
		return
	assert_eq(br.outcome, BattleResult.OUTCOME_VICTORY, "as a victory")
	assert_true(br.has_open_offer(), "the wild foe offers to join")
	assert_null(StoryController.active_request(), "the battle concluded")
	assert_eq(s.location_cell(), stood, "back exactly where the hero stood")
	assert_eq(lead.current_hp, final_hp, "the lead's duel HP carried back out")
	assert_eq(s.member("blightcap").current_hp, 20, "the bench keeps its HP")
	assert_eq(lead.growth_points(), 1, "the lead fought and survived: +1 Growth")
	assert_eq(s.member("blightcap").growth_points(), 0, "the bench never fought: no Growth")
	var party_before: int = s.party.size()
	var ow2 := await _boot()
	await _frames(3)
	var d := ow2.dialogue()
	assert_true(d.is_choosing(), "the story's befriend prompt asks")
	d.advance_clock(100.0)
	d.choose(0)
	await _drain(ow2)
	assert_eq(s.party.size(), party_before + 1, "accepting adds the unit to the party")
	if s.party.size() > party_before:
		assert_eq(s.party[party_before].character_id, foe_id, "the foe that was fought")
		assert_eq(s.party[party_before].member_id,
			StoryPartyMember.uid_for(StoryPartyMember.line_of(foe_id), ["vineweave", "blightcap"]),
			"keyed by the RosterLedger uid scheme")


func test_a_lost_wild_duel_whites_out_to_the_wayshrine() -> void:
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())
	var s: StoryState = StoryController.state()
	s.set_location("mossway", Vector3i(6, 3, 0), "east")
	var req := _begin_wild(&"petalfang")
	req.player_is_ai = true
	req.player_party[0].strength = 0.1
	req.foe_party[0].strength = 4.0
	var stage := await _mount_stage()
	assert_true(await _until(func() -> bool: return stage.battle.is_over, 900), "the duel ends")
	assert_eq(stage.battle.result.outcome, DuelResult.OUTCOME_DEFEAT, "a loss")
	await _press_continue()
	assert_eq(StoryController.last_result().outcome, BattleResult.OUTCOME_DEFEAT, "reported as a defeat")
	assert_eq(s.location_area(), "oakvale", "whited out to the respawn town")
	assert_eq(s.location_cell(), Vector3i(10, 10, 0), "at its Wayshrine")
	assert_false(s.member("vineweave").wounded, "the party is healed")
	assert_eq(s.member("vineweave").current_hp, StoryPartyMember.HP_FULL, "to full")
	assert_eq(s.member("vineweave").growth_points(), 0, "a loss earns no Growth (growth_on_loss 0)")


func test_fleeing_ends_the_duel_where_you_stood() -> void:
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())
	var s: StoryState = StoryController.state()
	s.set_location("mossway", Vector3i(6, 3, 0), "east")
	s.member("vineweave").current_hp = 60
	_rules.flee_base = 1.0
	var req := _begin_wild(&"blightcap")
	assert_true(req.can_flee(), "a wild duel may be fled")
	var stage := await _mount_stage()
	var mine := func() -> bool:
		return stage.battle.current_actor() == stage.battle.unit_of(0) and stage.hud._accepting
	assert_true(await _until(mine, 600), "the player's turn opens")
	assert_true(stage.battle.can_flee(), "Flee is live")
	stage.hud.choose_flee()
	assert_true(await _until(func() -> bool: return stage.battle.is_over, 120), "the duel ends")
	assert_eq(stage.battle.result.outcome, DuelResult.OUTCOME_FLED, "as fled")
	await _press_continue()
	assert_eq(StoryController.last_result().outcome, BattleResult.OUTCOME_FLED, "reported as fled")
	assert_eq(s.location_area(), "mossway", "no whiteout")
	assert_eq(s.location_cell(), Vector3i(6, 3, 0), "the hero stays put")
	assert_lte(s.member("vineweave").current_hp, 60, "HP carried (never healed by running)")
	assert_eq(s.member("vineweave").growth_points(), 0, "running earns no Growth")


func test_the_story_critical_recruit_always_offers_on_a_win() -> void:
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())
	var moss := StoryController.load_area("mossway")
	var recruit = moss.entity("lone_petalfang")
	var spec: BattleSpec = null
	for c in recruit.on_interact:
		if c is StartDuelCommand:
			spec = (c as StartDuelCommand).spec
	assert_not_null(spec, "the Lone Petalfang's duel spec")
	if spec == null:
		return
	_rules.befriend_base_chance = 0.0
	var br_req: BattleRequest = spec.to_request(BattleRequest.SOURCE_SCRIPT)
	br_req.kind = BattleRequest.KIND_DUEL
	assert_true(bool(StoryController.begin_battle(br_req)["success"]), "the recruit duel launches")
	var req: DuelRequest = DuelController.active_request()
	assert_false(req.is_wild(), "a scripted (non-wild) duel")
	assert_true(req.is_story_critical(), "flagged story-critical")
	req.player_is_ai = true
	req.foe_party[0].strength = 0.1
	var stage := await _mount_stage()
	assert_true(await _until(func() -> bool: return stage.battle.is_over, 900), "the duel ends")
	assert_eq(stage.battle.result.outcome, DuelResult.OUTCOME_VICTORY, "a win")
	await _press_continue()
	assert_true(StoryController.last_result().has_open_offer(),
		"a story-critical recruit offers even at a 0% join chance (never missable)")
