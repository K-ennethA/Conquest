extends GutTest

## STORY LEVELS IN BOTH BATTLE TYPES (docs/design/PROGRESSION.md §2): one stat-at-level function
## ([method Progression.apply_level]) on a private copy, for the player side and the enemy side.
##   * the DUEL compiles each combatant at its level (strength still multiplies on top), and a
##     level-0 combatant -- every open-mode duel -- is the roster base exactly as before;
##   * the TACTICAL board (a real booted GameWorld running Bram's story battle) spawns party
##     members at their own level and foes at the battle's enemy level, tags them "Lv N", never
##     mutates the shared roster resource, shows the XP rows on the end screen and pays XP on
##     Continue; the same board as a plain skirmish spawns no levels at all.

const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const TEMP_DIR := "user://test_story_levels_live/"
const TEMP_BATTLE_SAVE := "user://test_story_levels_live_battle.json"

var _guard
var _world: Node = null
var _prev_scene: Node = null
var _prev_recording: bool = true
var _resolved: Array = []


func before_all() -> void:
	BattleSaveManager.set_save_path(TEMP_BATTLE_SAVE)


func after_all() -> void:
	BattleSaveManager.delete_save()
	BattleSaveManager.set_save_path(BattleSaveManager.DEFAULT_SAVE_PATH)


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
	_resolved = []
	GameEvents.battle_resolved.connect(_on_resolved)
	_clear_globals()


func after_each() -> void:
	if GameEvents.battle_resolved.is_connected(_on_resolved):
		GameEvents.battle_resolved.disconnect(_on_resolved)
	get_tree().paused = false
	_teardown_world()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	ReplayRecorder.recording_enabled = _prev_recording
	ReplayPlayback.end_playback()
	PortraitCache.reset()
	_clear_globals()
	_guard.restore()
	await get_tree().process_frame
	await get_tree().process_frame


func _on_resolved(outcome, _ctx) -> void:
	_resolved.append(String(outcome))


func _clear_globals() -> void:
	PlayerManager.reset_for_new_game()
	TurnSystemManager.reset_for_new_game()
	CombatServices.clear()
	CombatServices.match_rng = null


func _boot_world() -> Node:
	var world: Node = WORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	_world = world
	return world


func _teardown_world() -> void:
	if _world == null or not is_instance_valid(_world):
		_world = null
		return
	get_tree().current_scene = _prev_scene
	if _world.get_parent() != null:
		_world.get_parent().remove_child(_world)
	_world.free()
	_world = null


func _await_until(pred: Callable, max_frames: int = 900) -> bool:
	for i in range(max_frames):
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return false


func _bram_request() -> BattleRequest:
	var moss := load(StoryController.area_path("mossway")) as OverworldAreaResource
	var bram := moss.entity("bram") as TrainerEntity
	return bram.battle.to_request(BattleRequest.SOURCE_TRAINER, bram.encounter_id("mossway"))


func _party_units() -> Array:
	var out: Array = []
	for u in CombatServices.board().all_units():
		if u.has_meta(StoryBattleBridge.MEMBER_META):
			out.append(u)
	return out


# --- Duel ------------------------------------------------------------------------------

func _duel(player_level: int, foe_level: int, foe_strength: float = 1.0) -> DuelBattle:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight")
	req.seed = 77
	req.foe_is_ai = false
	req.player_party[0].level = player_level
	req.foe_party[0].level = foe_level
	req.foe_party[0].strength = foe_strength
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(req)
	assert_true(bool(ok["success"]), str(ok.get("reason", "")))
	return battle


func test_duel_compiles_each_side_at_its_level() -> void:
	var vine: CharacterResource = CharacterLibrary.get_character(&"vineweave")
	var geode: CharacterResource = CharacterLibrary.get_character(&"gem_knight")
	var base_hp: int = vine.base_health
	var b := _duel(20, 0)
	var mine = b.unit_of(0)
	var theirs = b.unit_of(1)
	assert_eq(int(mine.max_health), Progression.max_hp_at(vine, 20), "the player's unit has its level-20 HP")
	assert_eq(int(mine.get_meta(StoryBattleBridge.LEVEL_META)), 20, "and is tagged with its level")
	assert_eq(int(theirs.max_health), geode.base_health, "a level-0 combatant is the roster base, as before")
	assert_false((theirs as Node).has_meta(StoryBattleBridge.LEVEL_META), "and carries no level tag")
	assert_eq(vine.base_health, base_hp, "the shared roster resource is never touched (rule 7)")
	b.teardown()


func test_duel_strength_multiplies_on_top_of_level() -> void:
	var geode: CharacterResource = CharacterLibrary.get_character(&"gem_knight")
	var b := _duel(1, 10, 1.5)
	var expected: int = roundi(float(Progression.max_hp_at(geode, 10)) * 1.5)
	assert_eq(int(b.unit_of(1).max_health), expected, "level first, then the strength multiplier")
	b.teardown()


# --- Tactical ----------------------------------------------------------------------------

func test_tactical_story_battle_spawns_both_sides_at_their_levels_and_pays_xp() -> void:
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())
	var s: StoryState = StoryController.state()
	s.set_location("mossway", Vector3i(19, 6, 0), "north")
	s.member("vineweave").set_level(12)
	s.member("blightcap").set_level(9)
	var vine_res: CharacterResource = CharacterLibrary.get_character(&"vineweave")
	var vine_base_hp: int = vine_res.base_health
	var req := _bram_request()
	req.enemy_level = 7
	for t in req.opponent.get("team", []):
		(t as Dictionary).erase("level")
	var began: Dictionary = StoryController.begin_battle(req, false)
	assert_true(bool(began["success"]), "Bram's battle stages")
	_boot_world()
	var up: bool = await _await_until(func() -> bool:
		return TurnSystemManager.has_active_turn_system() and _party_units().size() == 3)
	assert_true(up, "the battle boots with the hero and both party members tagged")
	if not up:
		return
	for u in _party_units():
		var mid: String = String(u.get_meta(StoryBattleBridge.MEMBER_META))
		var lv: int = s.member(mid).level
		assert_eq(int(u.get_meta(StoryBattleBridge.LEVEL_META)), lv, "%s spawns at its party level" % mid)
		assert_eq(int(u.max_health), s.member(mid).max_hp(), "%s has its level's max HP" % mid)
	var foes: int = 0
	for u in CombatServices.board().all_units():
		if u.has_meta(StoryBattleBridge.MEMBER_META):
			continue
		foes += 1
		assert_eq(int(u.get_meta(StoryBattleBridge.LEVEL_META, 0)), 7, "a foe spawns at the battle's enemy level")
		assert_eq(int(u.max_health), Progression.max_hp_at(CharacterLibrary.get_character(u.character_resource.character_id), 7),
			"with its level-7 HP")
	assert_gt(foes, 0, "the board has foes")
	assert_eq(vine_res.base_health, vine_base_hp, "the roster resource is never mutated (a duplicate was levelled)")

	var xp_before: int = s.member("vineweave").xp
	for u in CombatServices.board().all_units():
		if not u.has_meta(StoryBattleBridge.MEMBER_META):
			u.take_damage(99999)
	var shown: bool = await _await_until(func() -> bool: return _resolved.size() > 0)
	assert_true(shown, "the battle resolves")
	await get_tree().process_frame
	var result: BattleResult = StoryController.last_result()
	assert_eq(result.defeated_levels.size(), result.defeated.size(), "the board reports each defeated foe's level")
	assert_false(StoryController.battle_progress_rows().is_empty(), "the end screen has XP rows to show")
	var screen: GameOverScreen = _world.find_children("*", "GameOverScreen", true, false)[0]
	var box := screen.find_child("ProgressRows", true, false) as VBoxContainer
	assert_not_null(box, "the end screen has the XP rows box")
	if box != null:
		assert_true(box.visible, "showing this battle's XP")
	var buttons: Array[Button] = screen.mode_action_buttons()
	buttons[0].pressed.emit()
	assert_gt(s.member("vineweave").xp, xp_before, "Continue pays the XP")


func test_plain_skirmish_on_the_same_board_spawns_no_levels() -> void:
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_selected_map("res://game/overworld/content/battles/ow_mossway_clearing.tres")
	GameSettings.set_selected_squad(["vineweave"])
	_boot_world()
	var up: bool = await _await_until(func() -> bool: return TurnSystemManager.has_active_turn_system())
	assert_true(up, "boots")
	if not up:
		return
	for u in CombatServices.board().all_units():
		assert_false(u.has_meta(StoryBattleBridge.LEVEL_META), "no story level outside a story battle")
		assert_eq(u.character_resource, CharacterLibrary.get_character(u.character_resource.character_id),
			"the unit uses the shared roster resource itself (nothing was levelled)")
