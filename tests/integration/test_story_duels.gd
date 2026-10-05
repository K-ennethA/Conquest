extends GutTest

## DUELS IN STORY MODE end to end (docs/design/DECISIONS.md #31 / #33; docs/STORY_MODE.md "Duels in
## story"), against the real overworld, StoryController, DuelController and DuelStage:
##   * content: the duel trainer, the rival, the sparring roster, the ambush, the Crown Arena and its
##     champion ship, validate and appear when their flags say so;
##   * a DUEL TRAINER (Tester Fenna) spots you -> a real duel (not a tactical board) -> her defeated
##     flag and purse;
##   * the RIVAL's first duel after the opening -> rival.met / stage / wins / duel1; the rematch waits
##     for a rest and comes back STRONGER (the rival.stage scaling);
##   * a SPARRING PARTNER in a Classic journey: a lost spar never marks anyone fallen, and the partner
##     is tired until you rest;
##   * the AMBUSH: a trigger on the Mossway bridge -> two self-defence duels (real battles) -> the
##     purse and the draught; in Classic a partner knocked out there falls;
##   * the CROWN CUP: fee paid -> four bouts through the ladder panel -> prize, title, the champion;
##     and a save / reload mid-ladder resumes at the same round without a second fee.
## Scene changes are off on both controllers; the suite mounts the duel stage and re-boots the
## overworld itself. Outcomes are forced with the stage's AI-vs-AI switch and strength knobs.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const STAGE := preload("res://game/duel/DuelStage.tscn")
const TEMP_DIR := "user://test_story_duels/"
const TEMP_ROSTER := "user://test_story_duels_roster.json"

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
	_restore_shipped_launchers()
	RosterLedger.reset()
	CombatServices.clear()


func after_each() -> void:
	_free_stage()
	_teardown()
	get_tree().paused = false
	for n in get_tree().root.get_children():
		if n is DuelStub or n is EvolutionScreen or n is StoryGameOverScreen:
			n.get_parent().remove_child(n)
			n.free()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	DuelController.reset()
	DuelController.record_profile = true
	DuelController.scene_changes_enabled = true
	_restore_shipped_launchers()
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	CombatServices.clear()
	CombatServices.match_rng = null
	_guard.restore()
	await get_tree().process_frame
	await get_tree().process_frame


func _restore_shipped_launchers() -> void:
	DuelLauncher.reset()
	DuelController.register_story_launcher()
	StoryController.register_debug_duel_stub()


# =====================================================================================
#  Helpers
# =====================================================================================

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _until(pred: Callable, max_frames: int = 900) -> bool:
	for i in range(max_frames):
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return bool(pred.call())


## A journey past the opening (the M1 two-member party: Vineweave leads) in slot 1.
func _journey(tier: String = StoryState.TIER_CASUAL) -> StoryState:
	StoryController.new_journey(1, tier)
	return StoryFixture.past_opening(StoryController.state())


func _boot(area: String = "", cell: Vector3i = Cells.INVALID, facing: String = "south") -> OverworldController:
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
	await _frames(2)
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		if _world.get_parent() != null:
			_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func _free_stage() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.get_parent().remove_child(_stage)
		_stage.free()
	_stage = null


func _step(ow: OverworldController, dir: Vector2i) -> void:
	ow.try_step(dir)
	await _frames(3)


## Run the story forward: read dialogue through (choices answered with [param pick]), answer the
## tournament ladder with [param ladder_picks] (then "leave"). Returns "duel" as soon as a duel is
## staged, "done" when the script ended, "timeout" otherwise.
func _drive(ow: OverworldController, pick: int = 0, ladder_picks: Array = [], max_frames: int = 900) -> String:
	for i in range(max_frames):
		await get_tree().process_frame
		if DuelController.is_active():
			return "duel"
		if not is_instance_valid(ow):
			return "timeout"
		if ow.ladder_panel != null and ow.ladder_panel.is_open():
			var a: String = String(ladder_picks.pop_front()) if not ladder_picks.is_empty() else "leave"
			ow.ladder_panel.choose(a)
			continue
		var d: StoryDialogue = ow.dialogue()
		if d != null and d.root_control().visible:
			if d.is_choosing():
				d.advance_clock(100.0)
				if d.choices_visible():
					d.choose(pick)
			else:
				d.skip()
			continue
		if not StoryController.is_script_running():
			return "done"
	return "timeout"


## Fight the staged duel on the real stage, forcing a win (or a loss), and press Continue Journey.
func _fight(win: bool = true) -> DuelResult:
	var req: DuelRequest = DuelController.active_request()
	req.player_is_ai = true
	# Party duels: every member of the losing side is weakened (its whole team must faint).
	if win:
		for c in req.foe_party:
			c.strength = 0.1
	else:
		for c in req.player_party:
			c.strength = 0.1
		for c in req.foe_party:
			c.strength = 4.0
	_free_stage()
	_stage = STAGE.instantiate()
	_stage.instant = true
	get_tree().root.add_child(_stage)
	var stage := _stage
	assert_true(await _until(func() -> bool: return stage.battle.is_over), "the duel ends")
	assert_true(await _until(func() -> bool: return stage.hud.results_visible()), "the results card")
	var result: DuelResult = stage.battle.result
	stage.hud.continue_button().pressed.emit()
	await _frames(3)
	_free_stage()
	return result


# =====================================================================================
#  Content
# =====================================================================================

func test_the_duel_content_ships_and_appears_on_its_flags() -> void:
	var moss := StoryController.load_area("mossway")
	var ch := StoryController.load_area("crownhaven")
	assert_eq(moss.validate(), [] as Array[String], "the Mossway validates (duel opponents duel-eligible)")
	assert_eq(ch.validate(), [] as Array[String], "Crownhaven validates")
	var fenna := moss.entity("fenna") as TrainerEntity
	assert_not_null(fenna, "a duel trainer on the Mossway")
	assert_eq(fenna.battle.kind, BattleSpec.Kind.DUEL, "whose battle is a DUEL")
	assert_false(fenna.battle.spar, "a real battle")
	assert_true(moss.entity("bandit_ambush") is TriggerZone, "the ambush trigger")
	for id in ["lyra", "lyra_arena", "wynn", "aldous", "general", "arena_master", "isolde", "arena"]:
		assert_not_null(ch.entity(id), "Crownhaven has %s" % id)
	assert_eq((ch.entity("arena") as PropEntity).prop, "arena", "the arena building")
	var runs: Array = []
	for c in (ch.entity("arena_master") as NpcEntity).on_interact:
		_collect(c, runs)
	assert_eq(runs.size(), 1, "the arena master runs the tournament")
	if runs.size() == 1:
		assert_eq(String((runs[0] as RunTournamentCommand).tournament.id), "crown_cup", "the Crown Cup")

	var fresh := StoryState.new()
	var past := StoryFixture.past_opening(StoryState.new())
	assert_false(fenna.is_present(fresh), "Fenna waits until the opening is over")
	assert_true(fenna.is_present(past), "then takes the road")
	assert_true(ch.entity("lyra").is_present(past), "the rival waits inside the gate after the opening")
	assert_null(ch.entity("rival_meet"), "and does not ambush you: no trigger zone")
	assert_false(ch.entity("lyra_arena").is_present(past), "and moves to the arena only after the first duel")
	assert_true(ch.entity("wynn").is_present(past), "the sparring roster is in the yard")
	assert_false(moss.entity("bandit_ambush").is_present(past), "the ambush waits for the Act 1 hook")
	past.set_flag("act1.met_rowan", 1)
	assert_true(moss.entity("bandit_ambush").is_present(past), "then springs")
	assert_false(ch.entity("isolde").is_present(past), "the champion appears only once her title is taken")


func _collect(c, out: Array) -> void:
	if c is RunTournamentCommand:
		out.append(c)
	if c is StoryCommand:
		for l in (c as StoryCommand).child_lists():
			for sub in l:
				_collect(sub, out)


# =====================================================================================
#  A duel trainer
# =====================================================================================

func test_a_duel_trainer_spots_you_and_fights_a_real_duel() -> void:
	var s := _journey(StoryState.TIER_CLASSIC)
	var gold: int = s.gold
	var ow := await _boot("mossway", Vector3i(12, 5, 0), "west")
	assert_false(StoryController.is_script_running(), "not in her sight yet")
	await _step(ow, Vector2i(-1, 0))
	assert_true(StoryController.is_script_running(), "stepping into Fenna's line starts her challenge")
	assert_eq(await _drive(ow), "duel", "a duel is staged")
	var br: BattleRequest = StoryController.active_request()
	assert_true(br.is_duel(), "a DUEL, not a tactical board")
	assert_false(StoryController.is_battle_active(), "no tactical story battle is live")
	assert_eq(br.source, BattleRequest.SOURCE_TRAINER, "from a trainer")
	assert_eq(br.encounter_id, "trainer.mossway.fenna", "her encounter id")
	assert_false(br.is_spar(), "a real battle")
	var dr: DuelRequest = DuelController.active_request()
	assert_eq(dr.kind, DuelRequest.KIND_TRAINER, "the duel knows it is a trainer's")
	assert_false(dr.can_flee(), "no running from a trainer")
	assert_eq(String(dr.foe_party[0].character_id), "petalfang", "her Petalfang")
	assert_eq(dr.player_party[0].member_id, "vineweave", "your lead steps up")
	var result := await _fight(true)
	assert_eq(result.outcome, DuelResult.OUTCOME_VICTORY, "won")
	assert_true(s.has_flag("trainer.mossway.fenna.defeated"), "her defeated flag")
	assert_eq(s.gold, gold + 90, "her purse")
	var ow2 := await _boot()
	assert_eq(await _drive(ow2), "done", "her defeated line, then the script ends")
	await _step(ow2, Vector2i(1, 0))
	await _step(ow2, Vector2i(-1, 0))
	assert_false(StoryController.is_script_running(), "she never challenges again")


# =====================================================================================
#  The rival
# =====================================================================================

func test_the_rival_duel_after_the_opening_sets_rival_flags_and_rematches_scale() -> void:
	var s := _journey()
	var gold: int = s.gold
	var ow := await _boot("crownhaven", Vector3i(15, 22, 0), "north")
	await _step(ow, Vector2i(0, -1))
	assert_false(StoryController.is_script_running(), "walking in through the gate is never stopped")
	ow = await _boot("crownhaven", Vector3i(18, 21, 0), "west")
	assert_true(ow.interact(), "talk to Lyra, who waits inside the gate")
	assert_eq(await _drive(ow), "duel", "and challenges you to a duel")
	var br: BattleRequest = StoryController.active_request()
	assert_eq(br.encounter_id, "crownhaven.rival.lark", "the rival's encounter")
	assert_true(br.is_spar(), "a rival FRIENDLY (never permadeath)")
	assert_true(s.has_flag("rival.met"), "rival.met")
	var dr: DuelRequest = DuelController.active_request()
	assert_almost_eq(dr.foe_party[0].strength, 0.9, 0.001, "stage 0: her Blightcap at 0.9")
	await _fight(true)
	var ow2 := await _boot()
	assert_eq(await _drive(ow2), "done", "Lyra's parting words")
	assert_eq(s.get_flag_int("rival.stage"), 1, "one rival duel fought")
	assert_eq(s.get_flag_int("rival.wins"), 1, "and won")
	assert_true(s.has_flag("rival.duel1"), "the first rival duel is behind you")
	assert_eq(s.gold, gold + 60, "her purse")
	await _step(ow2, Vector2i(0, 1))
	await _step(ow2, Vector2i(0, -1))
	assert_false(StoryController.is_script_running(), "the gate trigger is gone")

	# The rematch by the arena: tired until a rest, then stronger.
	var ow3 := await _boot("crownhaven", Vector3i(22, 18, 0), "east")
	assert_true(ow3.actor("lyra_arena").visible, "Lyra waits by the arena")
	assert_true(ow3.interact(), "talk to her")
	assert_eq(await _drive(ow3), "done", "no rematch before a rest")
	s.heal_party()
	assert_true(ow3.interact(), "talk again after a rest")
	assert_eq(await _drive(ow3, 0), "duel", "Rematch!")
	assert_almost_eq(DuelController.active_request().foe_party[0].strength, 0.9 * 1.08, 0.001,
		"stage 1: 8% stronger")
	await _fight(false)
	var ow4 := await _boot()
	await _drive(ow4)
	assert_eq(s.get_flag_int("rival.stage"), 2, "two rival duels fought")
	assert_eq(s.get_flag_int("rival.wins"), 1, "one won")
	assert_eq(s.fallen.size(), 0, "a rival friendly never costs a life")


# =====================================================================================
#  A sparring partner
# =====================================================================================

func test_a_spar_partner_never_marks_fallen_in_classic_and_respects_the_cooldown() -> void:
	var s := _journey(StoryState.TIER_CLASSIC)
	var ow := await _boot("crownhaven", Vector3i(5, 10, 0), "west")
	assert_true(ow.interact(), "talk to Corporal Wynn")
	assert_eq(await _drive(ow, 0), "duel", "Let's spar.")
	var br: BattleRequest = StoryController.active_request()
	assert_eq(br.encounter_id, "crownhaven.spar.wynn", "Wynn's spar")
	assert_true(br.is_spar(), "a friendly")
	var result := await _fight(false)
	assert_eq(result.outcome, DuelResult.OUTCOME_DEFEAT, "the partner is knocked out")
	assert_eq(s.fallen.size(), 0, "nobody falls -- even in Classic")
	assert_not_null(s.member("vineweave"), "Vineweave is still in the party")
	assert_eq(s.member("vineweave").current_hp, 1, "back up at 1 HP")
	assert_eq(s.location_area(), "crownhaven", "no whiteout from a friendly")
	var ow2 := await _boot()
	assert_eq(await _drive(ow2), "done", "Wynn's consolation")
	assert_false(StorySparring.is_ready(s, "crownhaven.spar.wynn"), "Wynn is tired now")
	assert_true(ow2.interact(), "ask again")
	assert_eq(await _drive(ow2, 0), "done", "no bout before a rest")
	assert_false(DuelController.is_active(), "nothing was staged")
	assert_true(StorySparring.is_ready(s, "crownhaven.spar.aldous"), "the other partners are fresh")
	s.heal_party()
	assert_true(ow2.interact(), "after a rest")
	assert_eq(await _drive(ow2, 0), "duel", "Wynn spars again")
	await _fight(true)


# =====================================================================================
#  The ambush
# =====================================================================================

func test_the_ambush_trigger_two_duels_and_the_reward() -> void:
	var s := _journey(StoryState.TIER_CLASSIC)
	s.set_flag("act1.met_rowan", 1)
	var gold: int = s.gold
	var ow := await _boot("mossway", Vector3i(22, 6, 0), "west")
	await _step(ow, Vector2i(-1, 0))
	assert_true(StoryController.is_script_running(), "the bridge trigger springs the ambush")
	assert_eq(await _drive(ow), "duel", "the first bandit attacks")
	assert_true(s.has_flag("mossway.ambush.sprung"), "sprung")
	var br: BattleRequest = StoryController.active_request()
	assert_eq(br.encounter_id, "mossway.ambush.footpad", "the footpad first")
	assert_false(br.is_spar(), "self-defence is a REAL battle")
	assert_eq(br.defeat_policy(), BattleRequest.DEFEAT_WHITEOUT, "a loss whites out")
	await _fight(true)
	assert_true(s.has_flag("mossway.ambush.footpad_beaten"), "the footpad is beaten")
	var ow2 := await _boot()
	assert_eq(await _drive(ow2), "duel", "then Cutpurse Nell herself")
	assert_eq(StoryController.active_request().encounter_id, "mossway.ambush.nell", "the boss")
	await _fight(true)
	var ow3 := await _boot()
	assert_eq(await _drive(ow3), "done", "the bandits scatter")
	assert_true(s.has_flag("mossway.ambush.cleared"), "the road is safe")
	assert_eq(s.gold, gold + 40 + 180, "the footpad's and the stolen purse")
	assert_eq(s.item_count("dawnpetal_draught"), 1, "and the stolen draught")
	ow3.refresh_world()
	assert_false(ow3.actor("nell").visible, "the bandits are gone")
	await _step(ow3, Vector2i(1, 0))
	await _step(ow3, Vector2i(-1, 0))
	assert_false(StoryController.is_script_running(), "the ambush never springs again")


func test_losing_the_ambush_in_classic_costs_the_partner() -> void:
	var s := _journey(StoryState.TIER_CLASSIC)
	# A party of four: the story format fields three (lead + 2 bench), so a lost duel costs those
	# three and the fourth carries on (no wipe, a whiteout).
	s.add_member("petalfang")
	s.add_member("oakheart")
	s.set_flag("act1.met_rowan", 1)
	var ow := await _boot("mossway", Vector3i(22, 6, 0), "west")
	await _step(ow, Vector2i(-1, 0))
	assert_eq(await _drive(ow), "duel", "ambushed")
	await _fight(false)
	assert_not_null(s.fallen_member("vineweave"), "Vineweave fell for good (Classic, a real battle)")
	assert_not_null(s.fallen_member("blightcap"), "so did the bench member switched in after it")
	assert_not_null(s.fallen_member("petalfang"), "and the third team member")
	assert_null(s.fallen_member("oakheart"), "the member past the team size never fought")
	assert_false(s.has_flag("mossway.ambush.footpad_beaten"), "the footpad is not beaten")
	assert_ne(s.location_area(), "mossway", "whited out to the Wayshrine")
	assert_true(StoryController.load_area("mossway").entity("bandit_ambush").is_present(s),
		"the bandits wait on the bridge for another try")


# =====================================================================================
#  The Crown Cup
# =====================================================================================

func test_a_tournament_run_fee_ladder_prize_and_title() -> void:
	var s := _journey()
	s.gold = 500
	var ow := await _boot("crownhaven", Vector3i(21, 22, 0), "east")
	assert_true(ow.interact(), "talk to the arena master")
	assert_eq(await _drive(ow, 0, ["enter"]), "duel", "enter: round 1 starts")
	assert_eq(s.gold, 400, "the 100 gold entry fee")
	for n in range(1, 5):
		var br: BattleRequest = StoryController.active_request()
		assert_eq(br.encounter_id, "arena.crown_cup.round%d" % n, "round %d" % n)
		assert_true(br.is_spar(), "a friendly bout")
		var result := await _fight(true)
		assert_eq(result.outcome, DuelResult.OUTCOME_VICTORY, "round %d won" % n)
		var owr := await _boot()
		if n == 1:
			# The ladder between bouts shows the progress.
			var ok: bool = await _until(func() -> bool:
				var d: StoryDialogue = owr.dialogue()
				if d != null and d.root_control().visible:
					d.skip()
				return owr.ladder_panel != null and owr.ladder_panel.is_open(), 600)
			assert_true(ok, "the ladder re-opens after the bout")
			if ok:
				var panel: TournamentLadderPanel = owr.ladder_panel
				assert_not_null(panel.button("fight"), "Fight Round 2 is offered")
				assert_eq(panel.button("fight").text, "Fight Round 2", "labelled with the round")
				assert_null(panel.button("enter"), "no second entry while running")
				assert_not_null(panel.round_row(1).find_child("Status", true, false), "round 1 marked")
		var picks: Array = ["fight"] if n < 4 else ["leave"]
		var got: String = await _drive(owr, 0, picks)
		assert_eq(got, "duel" if n < 4 else "done", "on to the next bout" if n < 4 else "the cup is over")
	assert_true(s.has_flag("arena.crown_cup.champion"), "the title: Crown Cup Champion")
	assert_eq(s.get_flag_int("arena.crown_cup.wins"), 1, "one cup won")
	assert_eq(s.gold, 400 + 400, "the prize gold")
	assert_eq(s.item_count("sunleaf_totem"), 1, "the prize item")
	assert_false(s.has_flag("arena.crown_cup.run"), "the run is closed")
	assert_eq(s.fallen.size(), 0, "friendly bouts")
	var ow2 := await _boot()
	ow2.refresh_world()
	assert_true(ow2.actor("isolde").visible, "the old champion now waits for a rematch")


func test_save_and_reload_mid_ladder_resumes_the_run() -> void:
	var s := _journey()
	s.gold = 500
	var ow := await _boot("crownhaven", Vector3i(21, 22, 0), "east")
	ow.interact()
	assert_eq(await _drive(ow, 0, ["enter"]), "duel", "round 1")
	await _fight(true)
	var ow2 := await _boot()
	assert_eq(await _drive(ow2, 0, ["leave"]), "done", "leave between bouts")
	var saved: Dictionary = StorySaveManager.peek(1)
	assert_eq(int(saved["flags"].get("arena.crown_cup.run", 0)), 1, "the open run is saved")
	assert_eq(int(saved["flags"].get("arena.crown_cup.round", 0)), 1, "at round 2")
	# Come back, start round 2 -- and quit in the middle of it (the pre-battle autosave stands).
	ow2.interact()
	assert_eq(await _drive(ow2, 0, ["fight"]), "duel", "round 2 starts")
	assert_eq(StoryController.active_request().encounter_id, "arena.crown_cup.round2", "round 2")
	_teardown()
	DuelController.reset()
	StoryController.end_session()
	assert_true(bool(StoryController.continue_journey(1)["success"]), "reload the journey")
	var t: StoryState = StoryController.state()
	assert_eq(t.gold, 400, "no second fee was taken")
	assert_true(t.has_flag("arena.crown_cup.run"), "the run is still open")
	assert_eq(t.get_flag_int("arena.crown_cup.round"), 1, "still at round 2")
	var ow3 := await _boot()
	ow3.interact()
	var ok: bool = await _until(func() -> bool:
		var d: StoryDialogue = ow3.dialogue()
		if d != null and d.root_control().visible:
			d.skip()
		return ow3.ladder_panel != null and ow3.ladder_panel.is_open(), 600)
	assert_true(ok, "the ladder opens")
	if not ok:
		return
	assert_null(ow3.ladder_panel.button("enter"), "no entry fee again")
	assert_eq(ow3.ladder_panel.button("fight").text, "Fight Round 2", "round 2 is waiting")
	assert_eq(await _drive(ow3, 0, ["fight"]), "duel", "fight it")
	assert_eq(StoryController.active_request().encounter_id, "arena.crown_cup.round2", "round 2 again")
	assert_eq(t.gold, 400, "still no second fee")
	await _fight(true)
	var ow4 := await _boot()
	assert_eq(await _drive(ow4, 0, ["leave"]), "done", "leave after round 2")
	assert_eq(t.get_flag_int("arena.crown_cup.round"), 2, "the reloaded run advanced to round 3")
	assert_true(t.has_flag("arena.crown_cup.run"), "and is still open")
