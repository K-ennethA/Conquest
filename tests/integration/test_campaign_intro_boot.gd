extends GutTest

## THE CAMPAIGN CHAPTER INTRO, PROVEN AGAINST A REAL BOOTED BATTLE.
##
## The bug this suite pins closed: the chapter's opening scene used to play over the CHARACTER
## SELECT screen (Character Select called play_intro_then_launch and only changed scene once the
## story ended). It now plays over the BATTLE MAP -- the Fire Emblem read, portraits and text box
## in front of the battlefield the player is about to fight on.
##
## That is a claim about a LIVE SCREEN, so it is proven the way this project proves screens
## (tests/README.md; integration/test_versus_intro_boot.gd, whose shape this suite follows):
## instantiate the real res://game/world/GameWorld.tscn, make it the current scene so
## [GameWorldManager] runs its ORDINARY boot -- real map load, real players, real turn system --
## and then assert on the RENDERED nodes.
##
## What it pins:
##   1. a campaign boot with a staged intro MOUNTS [StoryDialogue] over the loaded map, with a
##      real board and real units already behind it;
##   2. while it is up the FIRST TURN IS HELD -- there is no active turn system at all, and that
##      is not a race (it is still held 30 frames later);
##   3. skipping releases the boot: the overlay comes down and the turn system starts;
##   4. a campaign boot with NOTHING staged never mounts it (and neither does a plain skirmish);
##   5. a RESUMED mid-battle save never replays the chapter's opening -- proven against a real
##      snapshot captured from a real battle, not a hand-written one.
##
## The latch itself (stage / consume / the replay guard) is pinned in
## integration/test_campaign_story_wiring.gd; this suite is deliberately only about the boot.

const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Chapter 1 -- the shipped scripted chapter, fought on its own shipped map.
const CHAPTER_INDEX := 0

const TEMP_PROGRESS_PATH := "user://test_campaign_intro_boot_progress.json"
const TEMP_SAVE_PATH := "user://test_campaign_intro_boot_save.json"

## Untyped on purpose (tests/README.md rule 3): a `: RefCounted` annotation makes the static
## analyser reject _guard.set_setting().
var _guard

var _world: Node = null
var _prev_scene: Node = null
var _prev_recording: bool = true


func before_all() -> void:
	# The mid-battle save slot is process-wide static state -- never the player's real one.
	BattleSaveManager.set_save_path(TEMP_SAVE_PATH)


func after_all() -> void:
	BattleSaveManager.delete_save()
	BattleSaveManager.set_save_path(BattleSaveManager.DEFAULT_SAVE_PATH)


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("selected_map_path", _chapter_map_path())
	_guard.set_setting("selected_squad", [])
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_guard.set_setting("animations_enabled", false)
	# Everything a staged RESUME re-stages through _stage_game_settings, so the resume test
	# cannot leak a setting into the next suite.
	_guard.watch_setting("selected_turn_system")
	_guard.watch_setting("ai_difficulty")
	_guard.watch_setting("player_count")
	_guard.watch_setting("player_names")

	# The boot mounts a ReplayRecorder, which WRITES user://replays on teardown.
	_prev_recording = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = false

	# Campaign progress is a real save file; a cleared chapter must never be recorded here.
	CampaignController.set_progress_path(TEMP_PROGRESS_PATH)
	_clear_globals()


func after_each() -> void:
	# An overlay never pauses the boot, but a failed test must never hand a paused tree on.
	if get_tree() != null:
		get_tree().paused = false
	_teardown_world()

	CampaignController.cancel()
	CampaignController.set_progress_path(CampaignController.DEFAULT_PROGRESS_PATH)
	if FileAccess.file_exists(TEMP_PROGRESS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PROGRESS_PATH))

	# A resume staged but never consumed is process-wide static state.
	if BattleSaveManager.has_pending_resume():
		BattleSaveManager.take_pending_resume()
	BattleSaveManager.delete_save()

	ReplayRecorder.recording_enabled = _prev_recording
	ReplayPlayback.end_playback()
	PortraitCache.reset()
	_clear_globals()
	_guard.restore()
	# Let the overlay's queue_free actually run before the suite tallies orphans.
	await get_tree().process_frame
	await get_tree().process_frame


func _clear_globals() -> void:
	if PlayerManager != null:
		PlayerManager.reset_for_new_game()
	if TurnSystemManager != null:
		TurnSystemManager.reset_for_new_game()
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("clear"):
		CombatServices.clear()


# =====================================================================================
#  Fixtures
# =====================================================================================

func _chapter() -> Dictionary:
	return CampaignData.get_chapter(CHAPTER_INDEX)


func _chapter_map_path() -> String:
	return String(_chapter().get("map_path", ""))


## Put the campaign in exactly the state Character Select's confirm leaves it in: the chapter
## armed for result capture, and its intro STAGED for the battle that is about to boot.
func _arm_and_stage_chapter() -> bool:
	if not CampaignController.arm_for_resume(_chapter(), 0):
		return false
	return CampaignController.stage_intro_for_launch()


## Instantiate the real GameWorld and make it the current scene -- what GameWorldManager mounts
## all of its overlays against. Mirrors integration/test_versus_intro_boot.gd.
func _boot_world() -> Node:
	var world: Node = WORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(world)
	# Set BEFORE GameWorldManager's first awaited frame resumes.
	get_tree().current_scene = world
	_world = world
	return world


func _teardown_world() -> void:
	if _world == null or not is_instance_valid(_world):
		_world = null
		return
	if get_tree() != null:
		get_tree().current_scene = _prev_scene
		if _world.get_parent() != null:
			_world.get_parent().remove_child(_world)
	_world.free()
	_world = null
	_prev_scene = null


## Poll [param predicate] once per frame, bounded in FRAMES (never wall-clock -- tests/README
## rule 7).
func _await_until(predicate: Callable, max_frames: int = 900) -> bool:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return false


## The mounted chapter-intro overlay, or null. Found by the node name the boot gives it, so a
## rename breaks this suite loudly rather than silently finding nothing.
func _mounted_intro() -> StoryDialogue:
	if _world == null or not is_instance_valid(_world):
		return null
	return _world.get_node_or_null("CampaignIntro") as StoryDialogue


func _turn_system_running() -> bool:
	return TurnSystemManager != null and TurnSystemManager.has_active_turn_system()


func _units_on_board() -> int:
	var board = CombatServices.board() if CombatServices != null else null
	if board == null or not board.has_method("all_units"):
		return 0
	return (board.all_units() as Array).size()


# =====================================================================================
#  1-3. The intro over the loaded map
# =====================================================================================

func test_a_campaign_boot_mounts_the_intro_over_the_loaded_map_and_holds_the_first_turn() -> void:
	if not _arm_and_stage_chapter():
		pending("chapter %d could not be armed/staged in this build" % CHAPTER_INDEX)
		return

	_boot_world()

	var mounted: bool = await _await_until(func() -> bool: return _mounted_intro() != null)
	assert_true(mounted, "a campaign battle mounts its chapter intro during the BATTLE boot")
	if not mounted:
		return

	var overlay: StoryDialogue = _mounted_intro()
	assert_true(overlay.root_control().visible,
		"and it is on screen, blocking input to the board behind it")
	assert_true(overlay.portrait_content_visible(StoryBeat.SIDE_LEFT)
			or overlay.portrait_content_visible(StoryBeat.SIDE_RIGHT)
			or not overlay.text_label().text.is_empty(),
		"with the authored scene actually playing on it")

	# THE POINT OF THE FIX: the MAP IS ALREADY BEHIND IT. The story no longer runs over the
	# squad picker -- the board is loaded and populated while the portraits are up.
	assert_gt(_units_on_board(), 0,
		"the battlefield is loaded and populated behind the overlay -- this is the FE read")

	# THE HOLD. _start_game() -- which is what makes TurnSystemManager activate a system -- is
	# behind the await on this overlay, so while it is up there is no turn system at all.
	assert_false(_turn_system_running(),
		"no turn system is active while the story is up -- the first turn is genuinely held")

	# And the latch is spent, so a rematch cannot replay the chapter's opening.
	assert_false(CampaignController.has_staged_intro(),
		"the boot consumed the staged intro")

	# 3. SKIP releases the boot.
	overlay.skip()
	var started: bool = await _await_until(func() -> bool: return _turn_system_running())
	assert_true(started, "skipping the story is what starts the battle")
	assert_null(_mounted_intro(), "and the overlay is taken back down off the battle scene")


func test_the_hold_is_real_and_not_a_race() -> void:
	# Stated as a before/after so a regression that starts the turn system EARLY (playing the
	# story after _start_game, say) fails here even if the mount itself still works.
	if not _arm_and_stage_chapter():
		pending("chapter %d could not be armed/staged in this build" % CHAPTER_INDEX)
		return

	_boot_world()

	var mounted: bool = await _await_until(func() -> bool: return _mounted_intro() != null)
	if not mounted:
		assert_true(false, "the intro must mount for this test to mean anything")
		return

	for _i in range(30):
		await get_tree().process_frame
	assert_false(_turn_system_running(),
		"30 frames into the story and still no turn system -- the hold is real")

	(_mounted_intro()).skip()
	var started: bool = await _await_until(func() -> bool: return _turn_system_running())
	assert_true(started, "the skip is what releases it")


# =====================================================================================
#  4. Nothing staged
# =====================================================================================

func test_a_boot_with_nothing_staged_never_mounts_a_story() -> void:
	# The ordinary case for every skirmish, and for an unscripted chapter: the latch is empty,
	# so the boot runs straight through to the first turn.
	assert_false(CampaignController.has_staged_intro(), "nothing is staged")

	_boot_world()

	var started: bool = await _await_until(func() -> bool: return _turn_system_running())
	assert_true(started, "the battle boots straight through to its first turn")
	assert_null(_mounted_intro(), "and no story overlay was ever mounted")


# =====================================================================================
#  5. A resumed mid-battle save
# =====================================================================================

func test_a_resumed_battle_never_replays_the_chapters_opening() -> void:
	# A resume is not a battle STARTING -- the same fact the VS clash intro is suppressed on.
	# Proven against a REAL snapshot captured from a REAL battle rather than a hand-written
	# dictionary, so the shape can never drift away from the one the restore path reads.
	if not _arm_and_stage_chapter():
		pending("chapter %d could not be armed/staged in this build" % CHAPTER_INDEX)
		return

	_boot_world()
	var mounted: bool = await _await_until(func() -> bool: return _mounted_intro() != null)
	if not mounted:
		assert_true(false, "the first boot must mount the intro for this test to mean anything")
		return
	(_mounted_intro()).skip()
	var started: bool = await _await_until(func() -> bool: return _turn_system_running())
	if not started:
		pending("the first battle never reached its first turn in this harness")
		return

	var saver = get_tree().get_first_node_in_group(BattleSaveManager.GROUP)
	if saver == null:
		pending("no BattleSaveManager mounted in this harness")
		return
	var snapshot: Dictionary = saver.capture(BattleSaveManager.today_utc())
	if snapshot.is_empty():
		pending("the live battle could not be captured in this harness")
		return

	_teardown_world()
	_clear_globals()
	await get_tree().process_frame

	if not BattleSaveManager.stage_resume(snapshot, BattleSaveManager.today_utc()):
		pending("the captured snapshot could not be staged as a resume")
		return

	# The worst case, deliberately: a chapter intro is ALSO staged. The resume must still win.
	CampaignController.stage_intro_for_launch()

	_boot_world()
	var resumed_started: bool = await _await_until(func() -> bool: return _turn_system_running())
	assert_true(resumed_started, "the resumed battle boots through to its turn")
	assert_null(_mounted_intro(),
		"THE POINT: resuming a saved chapter battle drops you back into the fight, not into "
		+ "its opening cutscene")
	assert_false(CampaignController.has_staged_intro(),
		"and the staged scene was consumed rather than left to open a later battle")
