extends GutTest

## CAMPAIGN <-> STORY WIRING: that a chapter's authored intro really plays BEFORE the battle
## is loaded, that a replay of a campaign battle plays no story at all, and that the two
## shipped chapter-1 scenes load and parse.
##
## THE ORDERING PROOF is the point of this suite: [method CampaignController.play_story]
## takes the "load the battle" continuation as a [Callable] and must not call it until the
## overlay has finished. So the test hands it a lambda that appends to an [Array] (captured
## BY VALUE -- the Array reference is what is captured, and appending mutates the same
## instance) and asserts the array is still EMPTY while the overlay is up.
##
## Real autoload ([CampaignController]), real resources, real overlay -- integration.

const Guard := preload("res://tests/helpers/global_state_guard.gd")

const INTRO_PATH := "res://game/campaign/story/ch1_blighted_clearing_intro.tres"
const OUTRO_PATH := "res://game/campaign/story/ch1_blighted_clearing_outro.tres"
const TEMP_PROGRESS_PATH := "user://test_campaign_story_progress.json"

## Untyped on purpose -- see tests/README.md rule 3.
var _guard


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	# Never touch the player's real campaign.json, even though nothing here should write.
	CampaignController.set_progress_path(TEMP_PROGRESS_PATH)


func after_each() -> void:
	# Any overlay this test mounted comes down with the run it belonged to.
	CampaignController.cancel()
	# Replay spectator mode is process-wide static state (it also flips
	# ReplayRecorder.recording_enabled) -- always disarm it, including on a failing test.
	ReplayPlayback.end_playback()
	CampaignController.set_progress_path(CampaignController.DEFAULT_PROGRESS_PATH)
	if FileAccess.file_exists(TEMP_PROGRESS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PROGRESS_PATH))
	PortraitCache.reset()
	_guard.restore()
	# Let the overlay's queue_free actually run before the suite tallies orphans.
	await get_tree().process_frame
	await get_tree().process_frame


# --- The authored chapter-1 scenes --------------------------------------------

func test_chapter_one_declares_both_story_scenes() -> void:
	var chapter: Dictionary = CampaignData.get_chapter(0)
	assert_eq(String(chapter.get("id", "")), "ch1_blighted_clearing",
		"chapter 0 is the Blighted Clearing")
	assert_eq(String(chapter.get(CampaignController.INTRO_SCENE_KEY, "")), INTRO_PATH,
		"and it names its intro scene")
	assert_eq(String(chapter.get(CampaignController.OUTRO_SCENE_KEY, "")), OUTRO_PATH,
		"and its outro scene")


func test_a_chapter_without_story_keys_resolves_to_no_scene() -> void:
	var chapter: Dictionary = CampaignData.get_chapter(1)
	assert_null(CampaignController.story_scene_for(chapter, CampaignController.INTRO_SCENE_KEY),
		"an unscripted chapter simply has no intro -- that is the normal case, not an error")


func test_a_missing_story_file_resolves_to_null_rather_than_erroring() -> void:
	var chapter: Dictionary = { "intro_scene": "res://game/campaign/story/does_not_exist.tres" }
	assert_null(CampaignController.story_scene_for(chapter, CampaignController.INTRO_SCENE_KEY),
		"a dangling path is a handled miss returned as a value (CONQUEST.md #1)")


func test_the_shipped_intro_scene_loads_with_its_beats_intact() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	assert_not_null(scene, "the shipped intro resource loads as a StoryScene")
	assert_false(scene.is_empty(), "and it has beats to play")
	var beats: Array[StoryBeat] = scene.playable_beats()
	assert_eq(beats.size(), 5, "the authored intro is five beats long")
	assert_true(beats[0].is_narrator(), "it opens on an unattributed scene-setting line")
	assert_eq(beats[1].speaker_id, &"vineweave", "then the player's champion speaks")
	assert_eq(beats[2].resolved_side(), StoryBeat.SIDE_RIGHT,
		"and the thing in the ferns answers from the other side of the screen")
	assert_eq(beats[2].resolved_speaker_name(), "Something in the Ferns",
		"under its authored name, not its roster one")


func test_the_shipped_outro_scene_loads_with_its_beats_intact() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.OUTRO_SCENE_KEY)
	assert_not_null(scene, "the shipped outro resource loads as a StoryScene")
	var beats: Array[StoryBeat] = scene.playable_beats()
	assert_eq(beats.size(), 5, "the authored outro is five beats long")
	assert_eq(beats[2].music_cue, &"sfx_death",
		"the dying barkling's line carries an audio cue")
	assert_true(beats[4].is_narrator(), "and it closes on an unattributed sting")


func test_arming_a_resumed_chapter_still_resolves_its_story() -> void:
	assert_true(CampaignController.arm_for_resume(CampaignData.get_chapter(0), 0),
		"chapter 1 arms for a resumed battle")
	assert_not_null(CampaignController.story_scene_for(
			CampaignController.active_chapter(), CampaignController.INTRO_SCENE_KEY),
		"and the ACTIVE chapter -- the one play_intro_then_launch reads -- carries the intro")


# --- The gate -----------------------------------------------------------------

func test_the_gate_refuses_nothing_to_play() -> void:
	assert_false(CampaignController.can_play_story(null), "there is no scene")
	var empty := StoryScene.new()
	assert_false(CampaignController.can_play_story(empty), "and an empty scene is not a scene")


func test_a_replay_suppresses_story_outright() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	assert_true(CampaignController.can_play_story(scene), "normally the intro would play")

	ReplayPlayback.begin_playback()
	assert_true(CampaignController.story_suppressed(), "a replay is playing")
	assert_false(CampaignController.can_play_story(scene),
		"so the same scene is refused -- a replay viewer has already seen this cutscene")


# --- The ordering proof: intro BEFORE the battle loads -------------------------

func test_the_intro_holds_the_battle_launch_until_the_scene_finishes() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	# Array, so the lambda's by-value capture still mutates the instance the test reads.
	var launched: Array = []

	var started: bool = CampaignController.play_story(scene,
		func() -> void: launched.append("battle"))
	assert_true(started, "the intro went up, so the caller must NOT change scene itself")

	await get_tree().process_frame
	var overlay: StoryDialogue = CampaignController.story_overlay()
	assert_not_null(overlay, "an overlay is mounted")
	assert_true(overlay.root_control().visible, "and it is on screen, blocking the world behind it")
	assert_eq(launched.size(), 0,
		"THE POINT: the battle has NOT been loaded while the story is still playing")

	overlay.skip()
	await get_tree().process_frame

	assert_eq(launched, ["battle"], "the battle loads exactly once, AFTER the story ends")
	assert_false(CampaignController.is_story_playing(), "and the overlay is taken back down")


func test_reading_the_intro_to_the_end_also_launches_exactly_once() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	var launched: Array = []
	assert_true(CampaignController.play_story(scene, func() -> void: launched.append("battle")),
		"the intro went up")

	var overlay: StoryDialogue = CampaignController.story_overlay()
	overlay.auto_tick = false
	# Walk every beat on the injected clock: complete the reveal, then advance.
	for i in range(scene.playable_beats().size()):
		overlay.advance_clock(10.0)
		overlay.advance()
	await get_tree().process_frame

	assert_eq(launched, ["battle"], "reading through launches the battle once, not per beat")
	assert_false(CampaignController.is_story_playing(), "and the overlay came down")


func test_replay_mode_launches_the_battle_with_no_story_at_all() -> void:
	ReplayPlayback.begin_playback()
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	var launched: Array = []

	var started: bool = CampaignController.play_story(scene,
		func() -> void: launched.append("battle"))
	await get_tree().process_frame

	assert_false(started,
		"play_story reports 'nothing went up', which is the caller's signal to launch NOW")
	assert_false(CampaignController.is_story_playing(), "no overlay was mounted")
	assert_eq(launched.size(), 0,
		"and the continuation is not fired either -- the caller owns the immediate launch")


func test_mounting_a_second_story_dismisses_the_first() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	CampaignController.play_story(scene, Callable())
	var first: StoryDialogue = CampaignController.story_overlay()
	assert_not_null(first, "the first overlay is up")

	CampaignController.play_story(scene, Callable())
	var second: StoryDialogue = CampaignController.story_overlay()
	assert_ne(second, first, "a second play replaces it rather than stacking two blockers")
	assert_false(first.is_inside_tree(), "and the first is out of the tree immediately")
	await get_tree().process_frame


func test_cancelling_a_run_takes_its_story_down() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	CampaignController.play_story(scene, Callable())
	assert_true(CampaignController.is_story_playing(), "a story is up")

	CampaignController.cancel()
	assert_false(CampaignController.is_story_playing(),
		"walking away from the run takes its story with it")
	await get_tree().process_frame
