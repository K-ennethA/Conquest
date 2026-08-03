extends GutTest

## BATTLE MUSIC: does entering a battle actually select the battle bed?
##
## The bug this pins: [signal GameEvents.game_started] and [signal GameEvents.game_ended] are
## DECLARED in systems/game_events.gd but have never had a single emitter anywhere in the
## project -- so [AudioManager]'s `_in_battle` latch was never set, [method
## AudioManager.play_music] was never called, and every battle was silent while the menus had
## music. [AudioManager] now decides which bed is owed from the SCENE that was swapped in
## ([member AudioManager.battle_scene_paths]), which is a fact that is always available.
##
## ASSERTS CONFIGURATION AND STATE, NEVER SOUND. Every test here is a call plus an identity
## check on the AudioStream that WOULD be played -- no timers, no `create_timer`, no waiting on
## a fade to finish (tests/README.md rule 7), and no audio device required.
##
## THE AUTOLOAD IS NEVER TOUCHED. Each test builds its own [AudioManager] off the script, so the
## player's live music never changes and no state leaks into another suite. Most of them build
## it OFF-TREE (`autofree`, so `_ready` never runs): the whole cue-selection decision is pure,
## and an off-tree manager has no music player at all, which proves the decision does not depend
## on one. The single tree-mounted test is the headless-safety check -- it is the one that would
## go red if any of this errored without an audio device.

const AUDIO_MANAGER := preload("res://game/audio/AudioManager.gd")
## The save layer's own name for the battle scene. Asserted against AudioManager's list so the
## two constants can never drift apart silently.
const SAVE_MANAGER := preload("res://systems/save/BattleSaveManager.gd")

const MENU_SCENE := "res://menus/MainMenu.tscn"


## A manager that has never entered the tree: no `_ready`, so no players, no signal wiring and
## no boot kick. Everything the cue decision needs is the exported library, which the script's
## own default initialiser supplies.
func _off_tree_manager() -> Node:
	return autofree(AUDIO_MANAGER.new())


# --- The asset actually exists and is registered ----------------------------

func test_the_default_library_carries_a_battle_track() -> void:
	var audio: Node = _off_tree_manager()
	assert_not_null(audio.library, "the manager always resolves a library, assigned or fallback")
	assert_not_null(audio.library.music_battle,
		"default_audio_library.tres must reference a battle track -- an unassigned slot is silence no wiring can fix")


func test_the_battle_bed_is_a_different_track_from_the_menu_bed() -> void:
	var audio: Node = _off_tree_manager()
	assert_not_null(audio.library.music_menu, "the menu bed is still registered")
	assert_ne(audio.library.music_battle, audio.library.music_menu,
		"a battle must not simply keep looping the menu theme -- they are two authored cues")


# --- What counts as a battle -------------------------------------------------

func test_the_game_world_scene_is_recognised_as_a_battle() -> void:
	var audio: Node = _off_tree_manager()
	assert_true(audio.is_battle_scene(SAVE_MANAGER.GAME_WORLD_SCENE),
		"the scene the save layer calls the battle scene is the one the audio layer scores as a battle")


func test_a_menu_scene_is_not_a_battle() -> void:
	var audio: Node = _off_tree_manager()
	assert_false(audio.is_battle_scene(MENU_SCENE),
		"a menu swap must never be mistaken for a battle starting")


func test_a_node_with_no_scene_file_is_never_a_battle() -> void:
	var audio: Node = _off_tree_manager()
	assert_false(audio.is_battle_scene(""),
		"a code-built node landing under the root is not a scene swap, so it must not flip the bed")


# --- Entering and leaving a battle -------------------------------------------

func test_a_fresh_manager_is_not_in_battle_and_owes_the_menu_bed() -> void:
	var audio: Node = _off_tree_manager()
	assert_false(audio.in_battle(), "nothing has started yet")
	assert_eq(audio.resolve_music_for_state(), audio.library.music_menu,
		"outside a battle the menu bed is what is owed")


func test_entering_a_battle_sets_the_state_and_selects_the_battle_cue() -> void:
	var audio: Node = _off_tree_manager()
	audio.enter_battle()
	assert_true(audio.in_battle(), "the battle latch is set -- this is the flag that was never set before")
	assert_eq(audio.resolve_music_for_state(), audio.library.music_battle,
		"and the cue selected for that state is the BATTLE track, not the menu one")


func test_leaving_a_battle_crossfades_back_to_the_menu_bed() -> void:
	var audio: Node = _off_tree_manager()
	audio.enter_battle()
	audio.exit_battle()
	assert_false(audio.in_battle(), "the battle is over")
	assert_eq(audio.resolve_music_for_state(), audio.library.music_menu,
		"leaving a battle returns to the menu bed rather than cutting to silence")


func test_entering_twice_is_harmless() -> void:
	var audio: Node = _off_tree_manager()
	audio.enter_battle()
	audio.enter_battle()
	assert_true(audio.in_battle(),
		"enter_battle is idempotent, so every seam that can detect a battle may call it freely")


func test_leaving_when_never_in_a_battle_is_harmless() -> void:
	var audio: Node = _off_tree_manager()
	audio.exit_battle()
	assert_false(audio.in_battle(), "exit_battle is idempotent too -- a menu-to-menu swap costs nothing")


# --- Runtime overrides -------------------------------------------------------

func test_a_battle_music_override_wins_over_the_library_slot() -> void:
	var audio: Node = _off_tree_manager()
	var custom := AudioStreamWAV.new()
	audio.set_battle_music(custom)
	audio.enter_battle()
	assert_eq(audio.resolve_music_for_state(), custom,
		"a runtime override re-skins the battle bed without editing default_audio_library.tres")


func test_clearing_the_override_falls_back_to_the_library_slot() -> void:
	var audio: Node = _off_tree_manager()
	audio.set_battle_music(AudioStreamWAV.new())
	audio.set_battle_music(null)
	audio.enter_battle()
	assert_eq(audio.resolve_music_for_state(), audio.library.music_battle,
		"passing null clears the override rather than silencing the slot")


# --- Headless safety ---------------------------------------------------------

func test_a_mounted_manager_starts_the_battle_stream_without_an_audio_device() -> void:
	# The only tree-mounted manager in this suite. GUT fails a test on ANY engine error, so if
	# building the voice pool, crossfading or play()ing errored on the headless dummy audio
	# driver, this test is what goes red.
	var audio: Node = add_child_autofree(AUDIO_MANAGER.new())
	audio.enter_battle()
	assert_eq(audio.current_music_stream(), audio.library.music_battle,
		"with nothing yet playing the crossfade starts the battle track immediately, headless and all")

	# Leaving does NOT swap the stream on this line: something IS playing now, so the crossfade
	# fades it out first and only then assigns the next one. Asserting the fade's OUTCOME here
	# would mean waiting on wall-clock time (tests/README.md rule 7), so what is pinned is the
	# decision -- which bed is owed -- and that the transition itself raised nothing.
	audio.exit_battle()
	assert_false(audio.in_battle(), "the battle state is dropped on the spot")
	assert_eq(audio.resolve_music_for_state(), audio.library.music_menu,
		"and the menu bed is what the crossfade is on its way to")
