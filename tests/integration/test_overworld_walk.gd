extends GutTest

## THE WALKABLE SCENE, booted for real (OverworldScene.tscn as the current scene, the shipped
## Oakvale / Mossway content), driven through its public host API rather than synthesised keys:
## walking + collision, the sign, the chest (and that it stays open across a reload), the Elder's
## choice opening the east gate (the guard walks aside), the Wayshrine (heal + respawn + save),
## the edge warp, a trainer spotting you, and the grass hook through the debug duel stub with a
## befriend offer accepted into the party. Animations off: every step / bubble is instant.
##
## Scene changes are switched OFF on StoryController, so a warp / battle hand-off records its
## target and the suite re-boots the scene itself.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_overworld_walk/"

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
	# This suite drives the DEBUG stub (the real duel is covered by test_story_duel_wiring):
	# swap the shipped real launcher out for the stub fallback.
	DuelLauncher.reset()
	StoryController.register_debug_duel_stub()


func after_each() -> void:
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	# Restore the shipped seam: the real duel, with the stub only as the fallback.
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


func _boot(area: String = "", cell: Vector3i = Cells.INVALID, facing: String = "south") -> OverworldController:
	if not StoryController.has_session():
		StoryController.new_journey(1)
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


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Step and wait for the arrival handler (animations off -> the walk ends next frame).
func _step(ow: OverworldController, dir: Vector2i) -> bool:
	var ok: bool = ow.try_step(dir)
	await _frames(3)
	return ok


## Read every dialogue through; answer choices with [param pick]. Bounded in frames.
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


func test_boots_on_the_tile_board_with_hero_and_actors() -> void:
	var ow := await _boot()
	assert_not_null(ow.grid, "the grid is built")
	assert_eq(ow.area.area_id, &"oakvale", "a new journey starts in Oakvale")
	assert_eq(ow.player.cell, Vector3i(10, 11, 0), "at the start entry")
	assert_not_null(ow.get_node_or_null("Map/Tiles"), "MapLoader built the terrain as a battle board")
	assert_not_null(ow.actor("elder"), "NPC actors exist")
	assert_not_null(ow.player.model(), "the hero has a model (the HeroResource placeholder)")
	assert_eq(ow.hud.area_ribbon().get_node("Text").text, "OAKVALE", "the area ribbon names the town")


func test_walk_turn_and_collide() -> void:
	var ow := await _boot("oakvale", Vector3i(10, 11, 0), "north")
	assert_true(await _step(ow, Vector2i(0, -1)), "a step onto flagstones")
	assert_eq(ow.player.cell, Vector3i(10, 10, 0), "one cell north")
	assert_false(await _step(ow, Vector2i(0, -1)), "the Wayshrine blocks")
	assert_eq(ow.player.cell, Vector3i(10, 10, 0), "the bump does not move the hero")
	assert_eq(ow.player.facing, Vector2i(0, -1), "facing the shrine")
	assert_eq(StoryController.state().location_cell(), Vector3i(10, 10, 0), "every step updates the save location")
	assert_eq(ow.hud.prompt_text().contains("Touch"), true, "the prompt offers to touch the shrine")


func test_sign_reads_in_the_text_box() -> void:
	var ow := await _boot("oakvale", Vector3i(16, 8, 0), "east")
	assert_true(ow.interact(), "Confirm on the town sign runs its script")
	await _frames(2)
	var d := ow.dialogue()
	assert_true(d.root_control().visible, "the grove text box is up")
	assert_true(d.sequencer().current_beat().text.begins_with("OAKVALE"), "with the sign's text")
	assert_true(ow.is_input_blocked(), "walking is locked while a script runs")
	await _drain(ow)
	assert_false(ow.is_input_blocked(), "and released after")


func test_chest_gives_once_and_stays_open_across_a_reload() -> void:
	var ow := await _boot("oakvale", Vector3i(5, 13, 0), "south")
	var gold_before: int = StoryController.state().gold
	assert_true(ow.interact(), "open the mill chest")
	await _drain(ow)
	var s: StoryState = StoryController.state()
	assert_eq(s.item_count("sagebloom_poultice"), 1, "the poultice is in the story bag")
	assert_eq(s.gold, gold_before + 30, "and the gold")
	assert_true(s.has_flag("oakvale.mill_chest.opened"), "the opened flag is set")
	StoryController.save_game()
	StoryController.end_session()
	StoryController.continue_journey(1)
	var ow2 := await _boot("oakvale", Vector3i(5, 13, 0), "south")
	var lid := ow2.actor("mill_chest").model().get_node("Lid") as Node3D
	assert_lt(lid.rotation_degrees.x, -45.0, "after a reload the lid is still open")
	ow2.interact()
	await _drain(ow2)
	assert_eq(StoryController.state().item_count("sagebloom_poultice"), 1, "and it gives nothing twice")


func test_guard_blocks_until_the_elders_quest_then_walks_aside() -> void:
	var ow := await _boot("oakvale", Vector3i(18, 9, 0), "east")
	assert_false(ow.grid.is_walkable(Vector3i(19, 9, 0)), "the guard stands in the east gate")
	# Talk to the Elder and say NO first: nothing opens.
	var ow2 := await _boot("oakvale", Vector3i(10, 6, 0), "north")
	ow2.interact()
	await _drain(ow2, 1)
	assert_false(StoryController.state().has_flag("quest.blight_road"), "'Not yet' sets nothing")
	ow2.interact()
	await _drain(ow2, 0)
	var s: StoryState = StoryController.state()
	assert_eq(s.get_flag_int("quest.blight_road"), 1, "'I will walk it' starts the quest")
	assert_eq(s.item_count("heartwood_charm"), 1, "the Elder's gift")
	assert_eq(ow2.actor("guard").cell, Vector3i(18, 10, 0), "the guard walked aside")
	assert_true(ow2.grid.is_walkable(Vector3i(19, 9, 0)), "the gate is open")
	var ow3 := await _boot("oakvale", Vector3i(18, 9, 0), "east")
	assert_true(ow3.grid.is_walkable(Vector3i(19, 9, 0)), "and it stays open on the next load (persisted move)")
	assert_eq(ow3.actor("guard").cell, Vector3i(18, 10, 0), "the guard stands aside")


func test_wayshrine_heals_sets_respawn_and_saves() -> void:
	var ow := await _boot("oakvale", Vector3i(10, 10, 0), "north")
	var s: StoryState = StoryController.state()
	s.party[0].current_hp = 5
	s.party[1].wounded = true
	s.respawn = {}
	assert_true(ow.interact(), "touch the Wayshrine")
	await _drain(ow)
	assert_eq(s.party[0].current_hp, StoryPartyMember.HP_FULL, "healed")
	assert_false(s.party[1].wounded, "wounds cleared")
	assert_eq(s.respawn, {"area_id": "oakvale", "entry": "wayshrine"}, "respawn set")
	assert_true(s.has_flag("wayshrine.oakvale.wayshrine.lit"), "lit")
	assert_eq(int(StorySaveManager.peek(1)["party"][0]["current_hp"]), -1, "and the journey was saved")


func test_edge_warp_to_the_mossway() -> void:
	StoryController.new_journey(1)
	StoryController.state().set_flag("quest.blight_road", 1)
	StoryController.state().set_actor_position("oakvale", "guard", Vector3i(18, 10, 0), "west", true)
	var ow := await _boot("oakvale", Vector3i(20, 9, 0), "east")
	await _step(ow, Vector2i(1, 0))
	var s: StoryState = StoryController.state()
	assert_eq(s.location_area(), "mossway", "stepping onto the edge warps to Route 1")
	assert_eq(s.location_cell(), Vector3i(1, 6, 0), "at its west entry")
	assert_true(s.visited_areas.has("mossway"), "visited")
	assert_eq(String(StorySaveManager.peek(1)["location"]["area_id"]), "mossway", "the warp autosaved")
	var ow2 := await _boot()
	assert_eq(ow2.area.area_id, &"mossway", "and the next boot is the route")
	assert_eq(ow2.player.cell, Vector3i(1, 6, 0), "where the warp put us")


func test_trainer_spots_you_and_the_battle_is_staged() -> void:
	var ow := await _boot("mossway", Vector3i(18, 6, 0), "east")
	assert_false(StoryController.is_script_running(), "not in his sight yet")
	await _step(ow, Vector2i(1, 0))
	assert_true(StoryController.is_script_running(), "stepping into Bram's line starts his script")
	await _drain(ow, 0, 60)
	assert_eq(ow.actor("bram").cell, Vector3i(19, 5, 0), "he walked up next to the hero")
	var req: BattleRequest = StoryController.active_request()
	assert_not_null(req, "his tactical battle is armed")
	assert_eq(req.encounter_id, "trainer.mossway.bram", "his encounter id")
	assert_eq(req.map_path, "res://game/overworld/content/battles/ow_mossway_clearing.tres", "on his board")
	assert_eq(req.return_to["cell"], [19, 6, 0], "the return point is where the hero stood")
	assert_eq(GameSettings.selected_map_path, req.map_path, "GameSettings is staged like a campaign chapter")
	assert_eq(GameSettings.selected_squad, ["vineweave", "blightcap"], "with the fielded party")
	assert_true(StoryController.is_battle_active(), "a story battle is active")
	# The round trip without GameWorld (the tactical integration suite boots the real board):
	var win := BattleResult.make("", BattleResult.OUTCOME_VICTORY)
	win.party_after = [{"member_id": "vineweave", "current_hp": 30, "wounded": false},
		{"member_id": "blightcap", "current_hp": 0, "wounded": true}]
	assert_true(bool(StoryController.report_battle_result(win)["success"]), "the result is reported")
	assert_false(bool(StoryController.report_battle_result(win)["success"]), "EXACTLY ONCE: a second report is refused")
	assert_eq(StoryController.end_actions("victory")[0]["id"], "continue", "the end screen offers Continue Journey")
	StoryController.on_end_action("continue")
	var s: StoryState = StoryController.state()
	assert_true(s.has_flag("trainer.mossway.bram.defeated"), "Bram's defeated flag")
	assert_eq(s.gold, 100 + 120, "his purse")
	assert_true(s.member("blightcap").wounded, "a KO'd member is wounded until a Wayshrine")
	assert_eq(s.location_cell(), Vector3i(19, 6, 0), "back where we stood")
	var ow2 := await _boot()
	assert_eq(ow2.actor("bram").cell, Vector3i(19, 5, 0), "Bram is still where he walked up to")
	await _drain(ow2, 0, 120)
	assert_false(StoryController.is_script_running(), "the paused script resumed and finished (his defeated line)")
	await _step(ow2, Vector2i(1, 0))
	assert_false(StoryController.is_script_running(), "he never challenges again")


func test_whiteout_returns_to_the_wayshrine_healed() -> void:
	var ow := await _boot("mossway", Vector3i(18, 6, 0), "east")
	await _step(ow, Vector2i(1, 0))
	await _drain(ow, 0, 60)
	var loss := BattleResult.make("", BattleResult.OUTCOME_DEFEAT)
	loss.party_after = [{"member_id": "vineweave", "current_hp": 0, "wounded": true}]
	StoryController.report_battle_result(loss)
	assert_eq(StoryController.end_actions("defeat")[0]["id"], "wayshrine", "the end screen offers the Wayshrine")
	StoryController.on_end_action("wayshrine")
	var s: StoryState = StoryController.state()
	assert_eq(s.location_area(), "oakvale", "whited out to Oakvale")
	assert_eq(s.location_cell(), Vector3i(10, 10, 0), "at the Wayshrine")
	assert_false(s.member("vineweave").wounded, "healed")
	assert_false(s.has_flag("trainer.mossway.bram.defeated"), "Bram is still undefeated")
	var ow2 := await _boot()
	await _frames(2)
	assert_true(ow2.dialogue().root_control().visible, "the retreat line is shown on arrival")
	await _drain(ow2)
	assert_false(StoryController.is_script_running(), "the whited-out script was stopped, not resumed")


func test_grass_encounter_through_the_duel_stub_and_befriend() -> void:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	s.grace_steps = 0
	# Walk the Mossway's first grass patch until the deterministic roller fires (bounded).
	var ow := await _boot("mossway", Vector3i(4, 2, 0), "east")
	var fired := false
	for i in range(80):
		var dir := Vector2i(1, 0) if (i / 4) % 2 == 0 else Vector2i(-1, 0)
		await _step(ow, dir)
		if StoryController.is_script_running():
			fired = true
			break
	assert_true(fired, "walking the tall grass rolls a wild encounter")
	await _frames(3)
	var stub: DuelStub = get_tree().root.get_node_or_null(DuelStub.NODE_NAME) as DuelStub
	assert_not_null(stub, "the debug duel stub is up (DuelLauncher -> DuelStub)")
	var req: BattleRequest = StoryController.active_request()
	assert_eq(req.kind, "duel", "a wild encounter is a duel")
	assert_eq(req.source, "wild", "sourced wild")
	var foe: String = req.lead_foe_id()
	stub.resolve(BattleResult.OUTCOME_VICTORY, true)
	await _frames(3)
	# StoryController concluded (deferred) and would change scene: reboot the overworld.
	var ow2 := await _boot()
	await _frames(3)
	var d := ow2.dialogue()
	assert_true(d.is_choosing(), "the befriend prompt asks")
	d.advance_clock(100.0)
	assert_true(d.choices_visible(), "with Yes / No")
	var party_before: int = s.party.size()
	d.choose(0)
	await _drain(ow2)
	assert_eq(StoryController.state().party.size(), party_before + 1, "the wild unit joined")
	assert_eq(StoryController.state().party[party_before].character_id, foe, "the unit that was fought")


func test_story_recruit_is_non_missable() -> void:
	var ow := await _boot("mossway", Vector3i(30, 4, 0), "north")
	assert_true(ow.interact(), "challenge the lone Petalfang")
	await _drain(ow, 0, 30)
	var stub: DuelStub = get_tree().root.get_node_or_null(DuelStub.NODE_NAME) as DuelStub
	assert_not_null(stub, "its duel opens")
	assert_true(StoryController.active_request().is_story_critical(), "a story-critical recruit")
	stub.resolve(BattleResult.OUTCOME_FLED)
	await _frames(3)
	var ow2 := await _boot()
	await _drain(ow2)
	assert_not_null(ow2.entity_at(Vector3i(30, 3, 0)), "after a flee the recruit is still there")
	ow2.interact()
	await _drain(ow2, 0, 30)
	(get_tree().root.get_node(DuelStub.NODE_NAME) as DuelStub).resolve(BattleResult.OUTCOME_VICTORY)
	await _frames(3)
	var ow3 := await _boot()
	await _drain(ow3, 1)
	assert_false(StoryController.state().party_has("petalfang"), "'Not now' declines")
	assert_not_null(ow3.entity_at(Vector3i(30, 3, 0)), "and the recruit stays (non-missable)")
	ow3.interact()
	await _drain(ow3, 0, 30)
	(get_tree().root.get_node(DuelStub.NODE_NAME) as DuelStub).resolve(BattleResult.OUTCOME_VICTORY)
	await _frames(3)
	var ow4 := await _boot()
	await _drain(ow4, 0)
	assert_true(StoryController.state().party_has("petalfang"), "a story-critical win always offers; accepting joins")
	assert_true(StoryController.state().has_flag("mossway.petalfang.recruited"), "recruited flag")
	ow4.refresh_world()
	assert_null(ow4.entity_at(Vector3i(30, 3, 0)), "and the recruit leaves the meadow")


func test_tap_walks_a_path() -> void:
	var ow := await _boot("oakvale", Vector3i(10, 11, 0), "north")
	ow.tap_cell(Vector3i(12, 11, 0))
	for i in range(30):
		await get_tree().process_frame
	assert_eq(ow.player.cell, Vector3i(12, 11, 0), "a tap walks there over the grid")
	ow.tap_cell(Vector3i(14, 11, 0))
	for i in range(40):
		await get_tree().process_frame
		if StoryController.is_script_running():
			break
	assert_true(StoryController.is_script_running(), "a tap on an NPC walks next to him and talks")
	await _drain(ow)


func test_journey_menu_saves() -> void:
	var ow := await _boot("oakvale", Vector3i(10, 11, 0), "north")
	ow.open_journey_menu()
	assert_true(ow.journey.is_open(), "the Journey menu opens")
	assert_true(ow.is_input_blocked(), "and blocks walking")
	StoryController.state().gold = 4242
	ow.journey.save_requested.emit()
	assert_eq(int(StorySaveManager.peek(1)["gold"]), 4242, "Save writes the slot")
	ow.journey.close()
	assert_false(ow.is_input_blocked(), "closing it releases input")
