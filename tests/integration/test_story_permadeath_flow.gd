extends GutTest

## THE DIFFICULTY TIERS end to end (docs/design/DECISIONS.md #29 + "Permadeath refinements"),
## against the real GameWorld / DuelStage / overworld / menus:
##   * CLASSIC tactical: a member killed on the board FALLS -- Journey -> Party lists it under
##     Fallen (where / when), its item is back in the bag, and the next battle leaves it out;
##   * CASUAL: a Wayshrine rests the living and revives the knocked-out for gold (or not);
##   * a friendly SPAR (the shipped Sergeant Rowan bout, a duel) never marks anyone fallen, and a
##     tactical spar shows "Friendly spar" on the objective banner;
##   * PROTECT: a story battle naming a guest ally to protect -- it falls -> defeat -> GAME OVER on
##     the end screen -> Load Last Save rewinds to the pre-battle autosave;
##   * the HERO rule with a stub hero party member: tactical (end screen) and duel (the grove
##     StoryGameOverScreen -> Return to Title keeps the last save);
##   * the New Journey tier picker and lowering the tier from Journey -> Difficulty.
## Scene changes are off on both controllers; the suite mounts the scenes itself.

const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const STAGE := preload("res://game/duel/DuelStage.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const TEMP_DIR := "user://test_story_permadeath/"
const TEMP_BATTLE_SAVE := "user://test_story_permadeath_battle.json"
const TEMP_ROSTER := "user://test_story_permadeath_roster.json"
const DESIGN := Vector2i(1280, 720)

var _guard
var _world: Node = null
var _prev_scene: Node = null
var _stage: DuelStage = null
var _resolved: Array = []
var _prev_recording: bool = true
var _prev_size: Vector2i


func before_all() -> void:
	BattleSaveManager.set_save_path(TEMP_BATTLE_SAVE)
	RosterLedger.set_save_path(TEMP_ROSTER)
	_prev_size = get_tree().root.size
	get_tree().root.size = DESIGN


func after_all() -> void:
	BattleSaveManager.delete_save()
	BattleSaveManager.set_save_path(BattleSaveManager.DEFAULT_SAVE_PATH)
	if FileAccess.file_exists(TEMP_ROSTER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_ROSTER))
	RosterLedger.set_save_path(RosterLedger.DEFAULT_SAVE_PATH)
	get_tree().root.size = _prev_size


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	for k in ["selected_map_path", "selected_squad", "game_mode", "ai_difficulty", "player_count",
			"player_names", "selected_turn_system"]:
		_guard.watch_setting(k)
	_prev_recording = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = false
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false
	DuelController.reset()
	DuelController.record_profile = false
	DuelController.scene_changes_enabled = false
	_restore_shipped_launchers()
	RosterLedger.reset()
	_resolved = []
	GameEvents.battle_resolved.connect(_on_resolved)
	_clear_globals()


func after_each() -> void:
	if GameEvents.battle_resolved.is_connected(_on_resolved):
		GameEvents.battle_resolved.disconnect(_on_resolved)
	get_tree().paused = false
	_free_stage()
	_teardown()
	for n in get_tree().root.get_children():
		if n is StoryGameOverScreen or n is DuelStub or n is EvolutionScreen:
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
	ReplayRecorder.recording_enabled = _prev_recording
	ReplayPlayback.end_playback()
	PortraitCache.reset()
	_clear_globals()
	CombatServices.match_rng = null
	_guard.restore()
	await get_tree().process_frame
	await get_tree().process_frame


func _restore_shipped_launchers() -> void:
	DuelLauncher.reset()
	DuelController.register_story_launcher()
	StoryController.register_debug_duel_stub()


func _on_resolved(outcome, _ctx) -> void:
	_resolved.append(String(outcome))


func _clear_globals() -> void:
	PlayerManager.reset_for_new_game()
	TurnSystemManager.reset_for_new_game()
	CombatServices.clear()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _until(pred: Callable, max_frames: int = 900) -> bool:
	for i in range(max_frames):
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return bool(pred.call())


func _mount(scene: PackedScene) -> Node:
	_teardown()
	var w: Node = scene.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	return w


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


func _boot_overworld(area: String, cell: Vector3i, facing: String) -> OverworldController:
	var s: StoryState = StoryController.state()
	if area != s.location_area():
		s.on_area_changed()
	s.set_location(area, cell, facing)
	_mount(OVERWORLD_SCENE)
	await _frames(2)
	return _world as OverworldController


## Read every dialogue through; answer choices with [param pick].
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


func _journey(tier: String) -> StoryState:
	StoryController.new_journey(1, tier)
	return StoryFixture.past_opening(StoryController.state())


func _bram_request() -> BattleRequest:
	var moss := StoryController.load_area("mossway")
	var bram := moss.entity("bram") as TrainerEntity
	return bram.battle.to_request(BattleRequest.SOURCE_TRAINER, bram.encounter_id("mossway"))


## The first StartBattle / StartDuel command in [param commands] (nested lists searched).
func _find_battle(commands: Array, want_spar: bool = false) -> StartBattleCommand:
	for c in commands:
		if c is StartBattleCommand and (c as StartBattleCommand).spec != null \
				and (not want_spar or (c as StartBattleCommand).spec.spar):
			return c
		if c is StoryCommand:
			for lst in (c as StoryCommand).child_lists():
				var found := _find_battle(lst, want_spar)
				if found != null:
					return found
	return null


func _party_units() -> Array:
	var out: Array = []
	for u in CombatServices.board().all_units():
		if u.has_meta(StoryBattleBridge.MEMBER_META):
			out.append(u)
	return out


func _unit_of(member_id: String):
	for u in _party_units():
		if String(u.get_meta(StoryBattleBridge.MEMBER_META)) == member_id:
			return u
	return null


func _player_side(u) -> bool:
	return u.get_parent() != null and u.get_parent().name == "Player1"


func _end_screen() -> GameOverScreen:
	var screens: Array = _world.find_children("*", "GameOverScreen", true, false)
	return screens[0] as GameOverScreen if not screens.is_empty() else null


func _boot_battle(members: int) -> bool:
	_clear_globals()
	_mount(WORLD_SCENE)
	return await _until(func() -> bool:
		return TurnSystemManager.has_active_turn_system() and _party_units().size() == members)


# =====================================================================================
#  CLASSIC: a member falls on the board
# =====================================================================================

func test_classic_tactical_fall_shows_in_party_returns_the_item_and_sits_out_next_battle() -> void:
	var s := _journey(StoryState.TIER_CLASSIC)
	assert_eq(s.tier, StoryState.TIER_CLASSIC, "a Classic journey")
	s.set_location("mossway", Vector3i(19, 6, 0), "north")
	s.member("vineweave").item_id = "heartwood_charm"
	assert_true(bool(StoryController.begin_battle(_bram_request(), false)["success"]), "Bram's battle stages")
	var up: bool = await _boot_battle(2)
	assert_true(up, "both members on the board")
	if not up:
		return
	_unit_of("vineweave").take_damage(99999)
	await _frames(2)
	assert_true(_resolved.is_empty(), "one member down: the battle goes on")
	for u in CombatServices.board().all_units():
		if not _player_side(u):
			u.take_damage(99999)
	assert_true(await _until(func() -> bool: return _resolved.size() > 0), "the battle resolves")
	assert_eq(_resolved, ["victory"], "a victory")
	await _frames(1)
	var screen := _end_screen()
	var buttons: Array[Button] = screen.mode_action_buttons()
	assert_eq(buttons[0].text, "Continue Journey", "an ordinary win: Continue Journey")
	buttons[0].pressed.emit()
	assert_null(s.member("vineweave"), "Vineweave fell: out of the party")
	var f: StoryPartyMember = s.fallen_member("vineweave")
	assert_not_null(f, "kept as a fallen record")
	assert_eq(s.item_count("heartwood_charm"), 1, "its charm is back in the bag")
	assert_eq(String(f.fallen_info["foe"]), "Bram", "fell against Bram")
	var saved: Dictionary = StorySaveManager.peek(1)
	assert_eq((saved["fallen"] as Array).size(), 1, "the fall is saved")

	# Journey -> Party shows it under Fallen.
	var jm := JourneyMenu.new()
	jm.session = StoryController
	add_child_autofree(jm)
	jm.open(s)
	jm.show_party()
	await _frames(1)
	assert_not_null(jm.find_child("FallenHeading", true, false), "a Fallen section")
	var card := jm.find_child("Fallen_vineweave", true, false)
	assert_not_null(card, "Vineweave's fallen card")
	var where := card.find_child("FellWhere", true, false) as Label if card != null else null
	assert_true(where != null and where.text.contains("Bram"), "saying where / whom (%s)" % (where.text if where != null else ""))
	assert_null(jm.member_card("vineweave"), "no living card for it")
	jm.close()

	# The next battle leaves it out.
	_teardown()
	assert_true(bool(StoryController.begin_battle(_bram_request(), false)["success"]), "the next battle stages")
	assert_eq(StoryController.active_request().party_member_ids(), ["blightcap"], "only the living are fielded")
	assert_eq(GameSettings.selected_squad, ["blightcap"], "the squad leaves the fallen out")


# =====================================================================================
#  CASUAL: the Wayshrine's gold revive
# =====================================================================================

func test_casual_wayshrine_revives_the_knocked_out_for_gold() -> void:
	var s := _journey(StoryState.TIER_CASUAL)
	s.gold = 100
	s.member("blightcap").wounded = true
	s.member("vineweave").current_hp = 5
	var ow := await _boot_overworld("oakvale", Vector3i(10, 10, 0), "north")
	assert_true(ow.interact(), "touch the Wayshrine")
	await _drain(ow, 1)
	assert_eq(s.member("vineweave").current_hp, StoryPartyMember.HP_FULL, "the living rest for free")
	assert_true(s.member("blightcap").wounded, "Not now: the knocked-out stay down")
	assert_eq(s.gold, 100, "and nothing is charged")
	assert_true(ow.interact(), "touch it again")
	await _drain(ow, 0)
	assert_false(s.member("blightcap").wounded, "paid: revived")
	assert_eq(s.gold, 50, "50 gold for one member (story_ruleset revive_fee_per_member)")
	assert_eq(int(StorySaveManager.peek(1)["gold"]), 50, "and the journey saved")


# =====================================================================================
#  SPAR
# =====================================================================================

func test_the_shipped_spar_never_marks_anyone_fallen() -> void:
	var s := _journey(StoryState.TIER_CLASSIC)
	s.set_location("crownhaven", Vector3i(7, 10, 0), "north")
	var rowan = StoryController.load_area("crownhaven").entity("rowan")
	var cmd := _find_battle(rowan.on_interact, true)
	assert_not_null(cmd, "Sergeant Rowan offers a friendly spar")
	if cmd == null:
		return
	assert_true(cmd is StartDuelCommand, "a duel")
	var req: BattleRequest = cmd.spec.to_request(BattleRequest.SOURCE_SCRIPT)
	req.kind = BattleRequest.KIND_DUEL
	assert_true(req.is_spar(), "tagged spar")
	assert_true(bool(StoryController.begin_battle(req)["success"]), "the spar launches")
	var dr: DuelRequest = DuelController.active_request()
	assert_true(dr.is_spar(), "the duel knows it is a spar")
	dr.player_is_ai = true
	dr.player_party[0].strength = 0.1
	dr.foe_party[0].strength = 4.0
	_stage = STAGE.instantiate()
	_stage.instant = true
	get_tree().root.add_child(_stage)
	var stage := _stage
	assert_true(await _until(func() -> bool: return stage.battle.is_over), "the spar ends")
	assert_eq(stage.battle.result.outcome, DuelResult.OUTCOME_DEFEAT, "the partner is knocked out")
	assert_true(await _until(func() -> bool: return stage.hud.results_visible()), "the results card")
	stage.hud.continue_button().pressed.emit()
	await _frames(3)
	var br: BattleResult = StoryController.last_result()
	assert_true(br.spar, "reported as a spar")
	assert_false(br.is_game_over(), "never a game over")
	var lead: StoryPartyMember = s.member("vineweave")
	assert_not_null(lead, "nobody fell -- even in Classic")
	assert_eq(s.fallen.size(), 0, "no fallen at all")
	assert_false(lead.wounded, "the knocked-out partner is back up")
	assert_eq(lead.current_hp, 1, "at 1 HP")
	assert_eq(s.location_area(), "crownhaven", "no whiteout from a friendly")


func test_a_tactical_spar_shows_friendly_spar_on_the_banner() -> void:
	var s := _journey(StoryState.TIER_CLASSIC)
	s.set_location("mossway", Vector3i(19, 6, 0), "north")
	var req := _bram_request()
	req.rules["spar"] = true
	StoryController.begin_battle(req, false)
	var up: bool = await _boot_battle(2)
	assert_true(up, "boots")
	if not up:
		return
	var banners: Array = _world.find_children("*", "ObjectiveBanner", true, false)
	assert_false(banners.is_empty(), "the objective banner")
	if banners.is_empty():
		return
	var banner := banners[0] as ObjectiveBanner
	assert_true(banner.is_spar_shown(), "tagged Friendly spar")
	var tag := banner.find_child(ObjectiveBanner.SPAR_NAME, true, false) as Control
	assert_true(tag != null and tag.visible, "the green tag is drawn")
	_unit_of("vineweave").take_damage(99999)
	for u in CombatServices.board().all_units():
		if not _player_side(u):
			u.take_damage(99999)
	assert_true(await _until(func() -> bool: return _resolved.size() > 0), "resolves")
	await _frames(1)
	_end_screen().mode_action_buttons()[0].pressed.emit()
	assert_not_null(s.member("vineweave"), "a spar KO never falls")
	assert_eq(s.member("vineweave").current_hp, 1, "it gets up at 1 HP")


# =====================================================================================
#  PROTECT -> GAME OVER -> Load Last Save
# =====================================================================================

func test_losing_the_protected_guest_is_a_game_over_and_load_last_save_rewinds() -> void:
	var s := _journey(StoryState.TIER_CLASSIC)
	s.set_location("oakvale_ruins", Vector3i(12, 9, 0), "east")
	var rowan = StoryController.load_area("oakvale_ruins").entity("rowan")
	var cmd := _find_battle(rowan.on_interact)
	assert_not_null(cmd, "the first fight's spec (the Sergeant's Geode as a guest)")
	if cmd == null:
		return
	var req: BattleRequest = cmd.spec.to_request(BattleRequest.SOURCE_SCRIPT)
	req.rules["protect"] = ["gem_knight"]
	var gold_before: int = s.gold
	assert_true(bool(StoryController.begin_battle(req, false)["success"]), "stages (and autosaves)")
	s.gold = 1   # changed AFTER the pre-battle autosave: a reload must undo it
	var up: bool = await _boot_battle(2)
	assert_true(up, "boots")
	if not up:
		return
	var banner := _world.find_children("*", "ObjectiveBanner", true, false)[0] as ObjectiveBanner
	assert_eq(banner.guard_text(), "Protect Geode", "the banner names who to protect")
	var guest = null
	for u in CombatServices.board().all_units():
		if _player_side(u) and not u.has_meta(StoryBattleBridge.MEMBER_META) \
				and String(u.character_resource.character_id) == "gem_knight":
			guest = u
	assert_not_null(guest, "the guest Geode is on the board")
	if guest == null:
		return
	guest.take_damage(99999)
	assert_true(await _until(func() -> bool: return _resolved.size() > 0), "its fall decides the battle")
	assert_eq(_resolved, ["defeat"], "as a DEFEAT, with the party still standing")
	await _frames(1)
	var br: BattleResult = StoryController.last_result()
	assert_true(br.is_game_over(), "a game over")
	assert_eq(br.game_over_reason, "protect:Geode", "because the protected guest fell")
	var screen := _end_screen()
	assert_eq(screen._banner_label.text, "GAME OVER", "the card says GAME OVER")
	assert_true(screen._subtitle_label.text.begins_with("Geode has fallen"), "and why")
	var buttons: Array[Button] = screen.mode_action_buttons()
	assert_eq(buttons.size(), 2, "two ways on")
	assert_eq(buttons[0].text, "Load Last Save", "Load Last Save")
	assert_eq(buttons[1].text, "Return to Title", "Return to Title")
	var old_state: StoryState = s
	buttons[0].pressed.emit()
	var t: StoryState = StoryController.state()
	assert_ne(t, old_state, "a fresh journey from the slot")
	assert_eq(t.gold, gold_before, "exactly as the pre-battle autosave had it")
	assert_null(StoryController.active_request(), "the battle is disarmed")
	assert_eq(t.fallen.size(), 0, "nothing of the lost battle is applied (nobody fell)")
	assert_eq(t.location_area(), "oakvale_ruins", "back in front of the fight")


# =====================================================================================
#  THE HERO rule (a stub hero party member)
# =====================================================================================

func test_a_stub_hero_falling_on_the_board_is_a_game_over() -> void:
	var s := _journey(StoryState.TIER_CASUAL)
	s.set_location("mossway", Vector3i(19, 6, 0), "north")
	s.member("vineweave").is_hero = true
	StoryController.begin_battle(_bram_request(), false)
	var up: bool = await _boot_battle(2)
	assert_true(up, "boots")
	if not up:
		return
	var hero = _unit_of("vineweave")
	assert_true(hero.has_meta(StoryBattleBridge.HERO_META), "the hero unit is tagged")
	hero.take_damage(99999)
	assert_true(await _until(func() -> bool: return _resolved.size() > 0), "the hero's fall decides it")
	assert_eq(_resolved, ["defeat"], "a defeat, though Blightcap stands")
	await _frames(1)
	assert_eq(StoryController.last_result().game_over_reason, StoryPermadeath.REASON_HERO, "the hero rule")
	var screen := _end_screen()
	assert_eq(screen._banner_label.text, "GAME OVER", "GAME OVER")
	assert_eq(screen.mode_action_buttons()[0].text, "Load Last Save", "offers the last save")


func test_a_stub_hero_fainting_in_a_duel_opens_the_game_over_card() -> void:
	var s := _journey(StoryState.TIER_CASUAL)
	s.set_location("mossway", Vector3i(6, 3, 0), "east")
	s.member("vineweave").is_hero = true
	var entry := EncounterEntry.new()
	entry.character_id = &"petalfang"
	assert_true(bool(StoryController.begin_battle(entry.to_request("mossway"))["success"]), "a wild duel")
	var dr: DuelRequest = DuelController.active_request()
	dr.player_is_ai = true
	dr.player_party[0].strength = 0.1
	dr.foe_party[0].strength = 4.0
	_stage = STAGE.instantiate()
	_stage.instant = true
	get_tree().root.add_child(_stage)
	var stage := _stage
	assert_true(await _until(func() -> bool: return stage.battle.is_over), "the duel ends")
	assert_true(await _until(func() -> bool: return stage.hud.results_visible()), "the results card")
	stage.hud.continue_button().pressed.emit()
	await _frames(3)
	var card: StoryGameOverScreen = StoryController.game_over_screen()
	assert_not_null(card, "the grove GAME OVER card is up")
	if card == null:
		return
	assert_true(card.message().begins_with("Wren has fallen") or card.message().contains("has fallen"),
		"saying the hero fell (%s)" % card.message())
	assert_eq(card.buttons().size(), 2, "Load Last Save / Return to Title")
	assert_eq(card.buttons()[0].text, "Load Last Save", "load first")
	assert_false(s.member("vineweave").wounded, "the loss was NOT applied")
	card.buttons()[1].pressed.emit()
	await _frames(1)
	assert_false(StoryController.has_session(), "back to the title: the session is closed")
	assert_true(StorySaveManager.has_save(1), "the slot keeps its last save")
	assert_eq(String(StorySaveManager.peek(1)["location"]["area_id"]), "mossway", "the pre-battle autosave")
	assert_null(StoryController.game_over_screen(), "the card is gone")


# =====================================================================================
#  The New Journey tier picker, and lowering the tier
# =====================================================================================

func test_new_journey_asks_for_the_tier() -> void:
	var screen := Control.new()
	screen.set_script(load("res://game/overworld/ui/StoryStartScreen.gd"))
	add_child_autofree(screen)
	await _frames(4)
	var slot1 := screen.find_child("Slot1Card", true, false) as Button
	slot1.pressed.emit()
	await _frames(2)
	assert_true(screen.is_tier_picker_open(), "an empty slot asks for the difficulty first")
	assert_false(StoryController.has_session(), "no journey yet")
	var classic := screen.find_child("ClassicCard", true, false) as Button
	var casual := screen.find_child("CasualCard", true, false) as Button
	assert_true(classic != null and classic.is_visible_in_tree(), "a Classic card")
	assert_true(casual != null and casual.is_visible_in_tree(), "a Casual card")
	var text: String = ""
	for l in classic.find_children("*", "Label", true, false):
		text += (l as Label).text + " "
	assert_true(text.contains("Permadeath") or text.contains("PERMADEATH"), "Classic is explained (%s)" % text)
	assert_true(text.contains("never raise"), "including that it can only go down")
	assert_true(casual.has_focus() or classic.has_focus(), "a card has keyboard focus")
	for c in [classic, casual]:
		assert_true((c as Control).get_global_rect().end.x <= DESIGN.x + 0.5, "the cards fit 1280 wide")
	screen._on_back()
	assert_false(screen.is_tier_picker_open(), "Back returns to the slots")
	slot1.pressed.emit()
	await _frames(1)
	classic.pressed.emit()
	assert_true(StoryController.has_session(), "picking a tier starts the journey")
	assert_eq(StoryController.tier(), StoryState.TIER_CLASSIC, "as Classic")
	assert_eq(String(StorySaveManager.peek(1)["tier"]), StoryState.TIER_CLASSIC, "saved with its tier")


func test_lowering_the_tier_from_the_journey_menu() -> void:
	_journey(StoryState.TIER_CLASSIC)
	var jm := JourneyMenu.new()
	jm.session = StoryController
	add_child_autofree(jm)
	jm.open(StoryController.state())
	jm.show_tier()
	await _frames(1)
	assert_true(jm.is_tier_open(), "Journey -> Difficulty")
	var name_l := jm.find_child("TierName", true, false) as Label
	assert_eq(name_l.text, "Classic", "shows the tier")
	(jm.find_child("LowerTierButton", true, false) as Button).pressed.emit()
	await _frames(1)
	var note := jm.find_child("ConfirmNote", true, false) as Label
	assert_true(note != null and note.text.contains("can't go back up"), "a confirm: you can't go back up")
	(jm.find_child("CancelLowerButton", true, false) as Button).pressed.emit()
	await _frames(1)
	assert_eq(StoryController.tier(), StoryState.TIER_CLASSIC, "cancel keeps Classic")
	(jm.find_child("LowerTierButton", true, false) as Button).pressed.emit()
	await _frames(1)
	(jm.find_child("ConfirmLowerButton", true, false) as Button).pressed.emit()
	await _frames(1)
	assert_eq(StoryController.tier(), StoryState.TIER_CASUAL, "now Casual")
	assert_eq(String(StorySaveManager.peek(1)["tier"]), StoryState.TIER_CASUAL, "and saved")
	assert_null(jm.find_child("LowerTierButton", true, false), "no way further down")
	assert_not_null(jm.find_child("LowestNote", true, false), "and it says a journey never moves back up")
	var up: Dictionary = StoryController.lower_tier(StoryState.TIER_CLASSIC)
	assert_false(bool(up["success"]), "raising it back is refused")
	assert_eq(String(up["reason"]), "cannot_raise", "cannot_raise")
	jm.close()
