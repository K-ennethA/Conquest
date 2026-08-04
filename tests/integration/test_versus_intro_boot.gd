extends GutTest

## THE PRE-BATTLE VS CLASH INTRO, PROVEN AGAINST A REAL BOOTED BATTLE.
##
## This project has been bitten twice by screen work that passed on helper statics while the
## live screen was wrong, so the rule is that a screen is only proven by an integration test
## that boots the REAL scene and asserts the RENDERED nodes. That is what this suite does:
##
##   * it instantiates the real res://game/world/GameWorld.tscn (which carries the real
##     GameUILayout on its "UI" CanvasLayer) and makes it the current scene, so
##     [GameWorldManager] runs its ORDINARY boot -- real map load, real players, real turn
##     system -- exactly as it does in game (integration/test_net_host_squad.gd's real
##     map-load discipline, integration/test_battle_hud_layout.gd's real-scene discipline);
##   * it then reads the intro's ACTUAL Labels off their real node paths, not a helper.
##
## What it pins:
##   1. a hotseat VERSUS boot MOUNTS the intro, and both player names are rendered on it;
##   2. the hotseat guest's rank chip is genuinely NOT RENDERED (the never-fabricate rule);
##   3. while the intro is up the FIRST TURN IS HELD -- there is no active turn system at all;
##   4. skipping reaches the end state, lifts the pause, and the turn system then STARTS;
##   5. a solo battle never mounts it;
##   6. a networked opponent's announced rank chip IS rendered, and a missing card degrades to
##      a name-only card, both read off the real mounted overlay.
##
## The pure decisions (the whole eligibility matrix, the assembler's rules) live in
## unit/test_versus_intro.gd; this suite is deliberately only about the live screen.

const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const LAYOUT_SCENE := preload("res://game/ui/layout/GameUILayout.tscn")
const Intro := preload("res://game/ui/screens/VersusIntro.gd")

## A real shipped 2-side map, the same fixture integration/test_net_host_squad.gd loads.
const MAP_PATH := "res://game/maps/resources/proving_grounds.tres"

## Node paths INSIDE a mounted intro. Spelled out here (rather than found by name) so a
## rename in the overlay breaks this suite loudly instead of silently finding nothing.
const LEFT_COLUMN := "IntroRoot/Shaker/LeftCard/Margin/Column"
const RIGHT_COLUMN := "IntroRoot/Shaker/RightCard/Margin/Column"

const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose (tests/README.md rule 3): a `: RefCounted` annotation makes the static
## analyser reject _guard.set_setting().
var _guard

var _world: Node = null
var _prev_scene: Node = null
var _prev_recording: bool = true


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("selected_map_path", MAP_PATH)
	_guard.set_setting("selected_squad", [])
	_guard.set_setting("host_squad", [])
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	# The boot mounts a ReplayRecorder, which WRITES user://replays when the battle is torn
	# down. A test must never leave files in the player's library.
	_prev_recording = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = false
	# Process-wide static bags a previous suite may have left cards in.
	MatchPeerInfo.clear()
	MatchLoadouts.clear()
	_clear_globals()


func after_each() -> void:
	# The overlay pauses the tree while it plays. Lift it FIRST and unconditionally: a test
	# that fails mid-play must never hand a paused tree to the next suite.
	if get_tree() != null:
		get_tree().paused = false
	_teardown_world()
	ReplayRecorder.recording_enabled = _prev_recording
	MatchPeerInfo.clear()
	MatchLoadouts.clear()
	_clear_globals()
	_guard.restore()


func _clear_globals() -> void:
	if PlayerManager != null:
		PlayerManager.reset_for_new_game()
	_reset_turn_systems()
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("clear"):
		CombatServices.clear()
	PortraitCache.reset()


## Tear the turn systems down.
##
## reset_for_new_game() also FREES the manager-owned (parentless) instances now -- the
## per-boot orphan this helper used to sweep up is fixed in the runtime itself (see
## TurnSystemManager._free_owned_system), and integration/test_turn_system_lifecycle.gd pins
## that. The call stays so a failed boot never hands an active system to the next suite.
func _reset_turn_systems() -> void:
	if TurnSystemManager == null:
		return
	TurnSystemManager.reset_for_new_game()


# =====================================================================================
#  Booting the real battle scene
# =====================================================================================

## Instantiate the real GameWorld and make it the current scene, which is what
## GameWorldManager mounts all of its overlays against. Returns the world root.
func _boot_world() -> Node:
	var world: Node = WORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(world)
	# Set BEFORE GameWorldManager's first awaited frame resumes -- everything it mounts is
	# resolved off current_scene.
	get_tree().current_scene = world
	_world = world
	return world


## Tear the booted world down. Only ever called once the boot has finished (see
## _await_until callers), so no GameWorldManager coroutine is left suspended on a freed node.
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
## rule 7). Returns whether it ever came true. Mirrors integration/test_mp_loopback.gd.
func _await_until(predicate: Callable, max_frames: int = 900) -> bool:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return false


## The mounted overlay, or null. UNTYPED on purpose (tests/README rule 3's cousin): a
## `-> Node` annotation would make the static analyser reject is_playing() / skip() as "not
## found in base Node", because the overlay is reached by path-preloaded script.
func _mounted_intro():
	if _world == null or not is_instance_valid(_world):
		return null
	return _world.get_node_or_null("VersusIntro")


func _turn_system_running() -> bool:
	return TurnSystemManager != null and TurnSystemManager.has_active_turn_system()


## Read a Label off a mounted intro by its real node path. Fails loudly (returns null) rather
## than silently answering "" when the path moved.
func _label(intro: Node, column: String, leaf: String) -> Label:
	return intro.get_node_or_null("%s/%s" % [column, leaf]) as Label


# =====================================================================================
#  1-4. A hotseat VERSUS boot
# =====================================================================================

func test_a_hotseat_versus_boot_mounts_the_intro_and_holds_the_first_turn() -> void:
	_boot_world()

	var mounted: bool = await _await_until(func() -> bool: return _mounted_intro() != null)
	assert_true(mounted, "a local versus battle mounts the VS clash intro during its boot")
	if not mounted:
		return

	var intro = _mounted_intro()
	assert_true(intro.is_playing(), "and it is on screen, playing")

	# THE HOLD. _start_game() -- which is what makes TurnSystemManager activate a system -- is
	# behind the await on this overlay, so while it is up there is no turn system at all.
	assert_false(_turn_system_running(),
		"no turn system is active while the reveal is up -- the first turn is genuinely held")

	# THE RENDERED CARDS. Both sides are named, on the real Labels.
	var left_name: Label = _label(intro, LEFT_COLUMN, "NameLabel")
	var right_name: Label = _label(intro, RIGHT_COLUMN, "NameLabel")
	assert_not_null(left_name, "the left card renders a NameLabel at its declared path")
	assert_not_null(right_name, "and so does the right card")
	gut.p("left '%s'   right '%s'" % [left_name.text, right_name.text])
	assert_eq(left_name.text, "Player 1", "the left card is the local player")
	assert_eq(right_name.text, "Player 2", "and the right card is the hotseat opponent")

	# THE NEVER-FABRICATE RULE, rendered: the local player has a real profile behind them, the
	# guest in seat two does not.
	var left_chip: Label = _label(intro, LEFT_COLUMN + "/RankRow", "RankChip")
	var right_chip: Label = _label(intro, RIGHT_COLUMN + "/RankRow", "RankChip")
	assert_not_null(left_chip, "the left card carries a rank chip node")
	assert_not_null(right_chip, "and so does the right card")
	assert_true(left_chip.visible,
		"the local player's chip is shown -- PlayerProfile really does back a rank")
	assert_false(right_chip.visible,
		"the hotseat guest's chip is NOT rendered -- no profile on this box backs a rank")
	assert_false((_label(intro, RIGHT_COLUMN, "PointsLabel")).visible,
		"and no lifetime-points line is invented for them either")

	# 4. SKIP reaches the end state and releases the hold.
	intro.skip()
	assert_false(intro.is_playing(), "any input skips straight to the end state")
	assert_false(get_tree().paused, "and the tree is handed back unpaused")

	var started: bool = await _await_until(func() -> bool: return _turn_system_running())
	assert_true(started,
		"and the battle then actually starts -- a turn system is activated once the hold lifts")


func test_skipping_the_intro_is_what_starts_the_battle() -> void:
	# The same hold, stated as a before/after so a regression that starts the turn system
	# EARLY (mounting the intro after _start_game, say) fails here even if the mount itself
	# still works.
	_boot_world()

	var mounted: bool = await _await_until(func() -> bool: return _mounted_intro() != null)
	if not mounted:
		assert_true(false, "the intro must mount for this test to mean anything")
		return

	# Give the boot plenty of frames to prove it is not going to start the turn system on its
	# own while the overlay is still up.
	for _i in range(30):
		await get_tree().process_frame
	assert_false(_turn_system_running(),
		"30 frames into the reveal and still no turn system -- the hold is real, not a race")

	(_mounted_intro()).skip()
	var started: bool = await _await_until(func() -> bool: return _turn_system_running())
	assert_true(started, "the skip is what releases it")


# =====================================================================================
#  5. Suppressed modes
# =====================================================================================

func test_a_solo_battle_never_mounts_the_intro() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)

	_boot_world()

	# A solo boot is NOT held, so waiting for the turn system is the honest "the boot got all
	# the way through" signal -- and by then any intro would long since have mounted.
	var started: bool = await _await_until(func() -> bool: return _turn_system_running())
	assert_true(started, "a solo battle boots straight through to its first turn")
	assert_null(_mounted_intro(),
		"and never mounts a two-player clash card -- there is no second player")


func test_the_live_context_really_reads_the_running_autoloads() -> void:
	# The gate itself is pinned exhaustively in unit/test_versus_intro.gd. What THAT cannot
	# prove is that live_context() is wired to the real autoloads at all -- a probe that silently
	# read nothing would score every battle as "show it". So: drive the two facts that decide a
	# versus battle and watch the live context follow them.
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	var versus_ctx: Dictionary = Intro.live_context()
	assert_eq(int(versus_ctx["game_mode"]), int(GameSettings.GameMode.VERSUS),
		"live_context reads the real GameSettings mode")
	assert_false(bool(versus_ctx["replay"]), "and reports an ordinary battle as not a replay")
	assert_false(bool(versus_ctx["networked"]),
		"and reports no live networked match in a headless harness")
	assert_true(Intro.should_show(versus_ctx), "so a local versus battle qualifies")

	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	assert_false(Intro.should_show(Intro.live_context()),
		"flipping the real setting to single player suppresses it, through the live probe")

	# Replay playback is the same static fact the AI-driver gate reads. Armed and disarmed here
	# rather than in a booted battle, because GameWorldManager disarms an unstaged playback
	# during its own boot (see _maybe_begin_replay_playback).
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	ReplayPlayback.begin_playback()
	var replay_ctx: Dictionary = Intro.live_context()
	ReplayPlayback.end_playback()

	assert_true(bool(replay_ctx["replay"]), "live_context sees spectator mode armed")
	assert_false(Intro.should_show(replay_ctx),
		"and watching a recording never shows the intro")
	assert_false(bool(Intro.live_context()["replay"]),
		"and the flag is back down once playback ends")


# =====================================================================================
#  6. The networked card, rendered
# =====================================================================================
#
# A live networked match cannot be stood up in a headless suite without dialling a socket, so
# the NETWORKED half is proven the other way round: the real overlay is mounted into a real
# battle-HUD scene (the same GameUILayout.tscn the battle scene carries) and played with the
# sources a networked boot would collect. Everything asserted below is read off the overlay's
# real, rendered Labels.

## Mount the real GameUILayout plus a real intro, play it, and let a few frames settle.
## Untyped return, for the same static-analyser reason as _mounted_intro().
func _mount_intro_over_the_hud(sources: Dictionary):
	var layout: Control = LAYOUT_SCENE.instantiate()
	add_child_autofree(layout)
	var intro = Intro.new()
	intro.name = "VersusIntro"
	add_child_autofree(intro)
	for _i in range(4):
		await get_tree().process_frame
	intro.play(sources)
	for _i in range(4):
		await get_tree().process_frame
	return intro


func test_a_networked_opponents_announced_rank_chip_is_rendered() -> void:
	var intro = await _mount_intro_over_the_hud({
		"networked": true,
		"local_name": "Ardent",
		"local_rank": "Veteran",
		"local_points": 1800,
		"peer_card": { "name": "Ivy", "rank_name": "Knight", "lifetime_points": 4200 },
	})

	assert_eq((_label(intro, LEFT_COLUMN, "NameLabel")).text, "Ardent",
		"the left card renders this machine's player")
	assert_eq((_label(intro, RIGHT_COLUMN, "NameLabel")).text, "Ivy",
		"and the right card renders the opponent's announced name")

	var right_chip: Label = _label(intro, RIGHT_COLUMN + "/RankRow", "RankChip")
	assert_true(right_chip.visible,
		"a networked opponent's chip IS rendered -- their own announced card backs it")
	assert_eq(right_chip.text, "KNIGHT", "carrying the rank they announced")

	var right_points: Label = _label(intro, RIGHT_COLUMN, "PointsLabel")
	assert_true(right_points.visible, "and their lifetime points line is rendered too")
	assert_true(right_points.text.contains("4200"), "with the figure from their card")

	intro.skip()


func test_a_networked_opponent_with_no_card_renders_a_name_only() -> void:
	var intro = await _mount_intro_over_the_hud({
		"networked": true,
		"local_name": "Ardent",
		"local_rank": "Veteran",
		"peer_card": {},
		"roster_name": "Ivy",
	})

	assert_eq((_label(intro, RIGHT_COLUMN, "NameLabel")).text, "Ivy",
		"an older peer that never announced a card is still named from the roster")
	assert_false((_label(intro, RIGHT_COLUMN + "/RankRow", "RankChip")).visible,
		"with no rank chip -- missing cosmetic data is never invented")
	assert_false((_label(intro, RIGHT_COLUMN, "PointsLabel")).visible,
		"and no points line -- and the intro still plays, so the match is never blocked")

	intro.skip()


func test_the_overlay_always_releases_its_finished_signal() -> void:
	# The boot AWAITS `finished`; if it could ever be dropped, a battle would hang at the very
	# start. Lambdas capture by value, so the counter is an Array (tests/README).
	var fired: Array = []
	var intro = Intro.new()
	add_child_autofree(intro)
	await get_tree().process_frame
	intro.finished.connect(func() -> void: fired.append(true))

	intro.play({"local_name": "Ardent", "opponent_name": "Ivy"})
	assert_true(intro.is_playing(), "the intro is up")
	assert_eq(fired.size(), 0, "and has not finished yet")

	intro.skip()
	assert_eq(fired.size(), 1, "a skip emits finished exactly once")

	intro.skip()
	intro.skip()
	assert_eq(fired.size(), 1, "and further skips can never emit it again")


func test_leaving_the_tree_mid_play_still_releases_the_boot() -> void:
	# A scene change (Main Menu, Rematch) frees the overlay mid-reveal. If `finished` were lost
	# there, GameWorldManager's await would never return.
	var fired: Array = []
	var intro = Intro.new()
	add_child_autofree(intro)
	await get_tree().process_frame
	intro.finished.connect(func() -> void: fired.append(true))
	intro.play({})
	assert_true(intro.is_playing(), "the intro is up")

	remove_child(intro)
	assert_eq(fired.size(), 1, "leaving the tree releases the awaiting boot exactly once")
	assert_false(get_tree().paused, "and hands the tree back unpaused")
	add_child(intro)   # put it back so add_child_autofree still frees it
