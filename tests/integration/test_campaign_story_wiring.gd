extends GutTest

## CAMPAIGN <-> STORY WIRING: that a chapter's authored intro is STAGED (never shown) when the
## squad is confirmed, that a replay of a campaign battle plays no story at all, and that the
## two shipped chapter-1 scenes load and parse.
##
## THE INTRO NO LONGER PLAYS AT CHARACTER SELECT TIME. It used to mount over the squad picker
## and change scene when it finished; it now goes into a latch that the battle boot consumes,
## so the portraits come up over the LOADED BATTLE MAP. That the boot really mounts it, really
## holds the first turn and really skips it on a resumed save is proven against a booted
## GameWorld in integration/test_campaign_intro_boot.gd -- this suite owns the latch itself.
##
## THE ORDERING PROOF below still covers [method CampaignController.play_story], which is what
## the chapter OUTRO (unchanged: it already plays over the live battle) rides on: it takes its
## continuation as a [Callable] and must not call it until the overlay has finished. The test
## hands it a lambda that appends to an [Array] (captured BY VALUE -- the Array reference is
## what is captured, and appending mutates the same instance) and asserts the array is still
## EMPTY while the overlay is up.
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
		"and the ACTIVE chapter -- the one stage_intro_for_launch reads -- carries the intro")


# --- The latch: staged at confirm, consumed by the battle boot ------------------

func test_staging_the_intro_shows_nothing_at_all() -> void:
	# THE REGRESSION THIS FILE EXISTS FOR: confirming a squad used to mount the cutscene over
	# the Character Select screen. Staging must be a pure latch -- no overlay, anywhere.
	CampaignController.arm_for_resume(CampaignData.get_chapter(0), 0)

	assert_true(CampaignController.stage_intro_for_launch(),
		"a scripted chapter stages its intro for the battle that is about to boot")
	assert_true(CampaignController.has_staged_intro(), "and the latch is holding it")
	assert_false(CampaignController.is_story_playing(),
		"THE POINT: nothing is on screen -- the story does NOT play over Character Select")
	assert_null(CampaignController.story_overlay(), "no overlay was mounted by staging")


func test_the_boot_consumes_the_staged_intro_exactly_once() -> void:
	CampaignController.arm_for_resume(CampaignData.get_chapter(0), 0)
	CampaignController.stage_intro_for_launch()

	var scene: StoryScene = CampaignController.consume_staged_intro()
	assert_not_null(scene, "the battle boot picks up the chapter's authored intro")
	assert_false(scene.is_empty(), "with its beats intact")
	assert_false(CampaignController.has_staged_intro(), "and the latch is spent")
	assert_null(CampaignController.consume_staged_intro(),
		"so a rematch on the same map can never replay the chapter's opening")


func test_an_unscripted_chapter_stages_nothing() -> void:
	CampaignController.arm_for_resume(CampaignData.get_chapter(1), 0)
	assert_false(CampaignController.stage_intro_for_launch(),
		"chapter 2 has no authored intro, so there is nothing to stage")
	assert_false(CampaignController.has_staged_intro(), "and the latch stays empty")
	assert_null(CampaignController.consume_staged_intro(), "the boot is handed nothing to play")


func test_a_replay_is_refused_at_consumption_time() -> void:
	# The staging call happens in a menu; whether this battle is a spectated replay is a fact
	# about the BATTLE. So the guard lives on the consume side.
	CampaignController.arm_for_resume(CampaignData.get_chapter(0), 0)
	assert_true(CampaignController.stage_intro_for_launch(), "the intro stages as normal")

	ReplayPlayback.begin_playback()
	assert_null(CampaignController.consume_staged_intro(),
		"a replay viewer is handed no cutscene -- they have already lived through it")
	assert_false(CampaignController.has_staged_intro(),
		"and the slot is still cleared, so it cannot leak into the next battle")


func test_cancelling_a_run_drops_its_staged_intro() -> void:
	CampaignController.arm_for_resume(CampaignData.get_chapter(0), 0)
	CampaignController.stage_intro_for_launch()

	CampaignController.cancel()
	assert_false(CampaignController.has_staged_intro(),
		"backing out of a chapter drops the opening it had queued")
	assert_null(CampaignController.consume_staged_intro(),
		"so an unrelated battle booted later never opens with it")


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


# --- The ordering proof: play_story holds its continuation ---------------------
#
# This is the mount contract the chapter OUTRO rides on (and, before the fix, the intro).
# The continuation must not fire while the overlay is still up.

func test_play_story_holds_its_continuation_until_the_scene_finishes() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	# Array, so the lambda's by-value capture still mutates the instance the test reads.
	var launched: Array = []

	var started: bool = CampaignController.play_story(scene,
		func() -> void: launched.append("after"))
	assert_true(started, "the story went up, so the caller must NOT run its follow-up itself")

	await get_tree().process_frame
	var overlay: StoryDialogue = CampaignController.story_overlay()
	assert_not_null(overlay, "an overlay is mounted")
	assert_true(overlay.root_control().visible, "and it is on screen, blocking the world behind it")
	assert_eq(launched.size(), 0,
		"THE POINT: nothing after the story has run while the story is still playing")

	overlay.skip()
	await get_tree().process_frame

	assert_eq(launched, ["after"], "the continuation fires exactly once, AFTER the story ends")
	assert_false(CampaignController.is_story_playing(), "and the overlay is taken back down")


func test_reading_a_story_to_the_end_also_continues_exactly_once() -> void:
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	var launched: Array = []
	assert_true(CampaignController.play_story(scene, func() -> void: launched.append("after")),
		"the story went up")

	var overlay: StoryDialogue = CampaignController.story_overlay()
	overlay.auto_tick = false
	# Walk every beat on the injected clock: complete the reveal, then advance.
	for i in range(scene.playable_beats().size()):
		overlay.advance_clock(10.0)
		overlay.advance()
	await get_tree().process_frame

	assert_eq(launched, ["after"], "reading through continues once, not per beat")
	assert_false(CampaignController.is_story_playing(), "and the overlay came down")


func test_replay_mode_plays_no_story_at_all() -> void:
	ReplayPlayback.begin_playback()
	var scene: StoryScene = CampaignController.story_scene_for(
		CampaignData.get_chapter(0), CampaignController.INTRO_SCENE_KEY)
	var launched: Array = []

	var started: bool = CampaignController.play_story(scene,
		func() -> void: launched.append("after"))
	await get_tree().process_frame

	assert_false(started,
		"play_story reports 'nothing went up', which is the caller's signal to carry on NOW")
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
