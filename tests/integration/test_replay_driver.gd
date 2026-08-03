extends GutTest

# THE PLAYBACK ENGINE, driven headless.
#
# ReplayDriver's whole job is: apply the recorded commands IN ORDER, at a watchable pace, and
# STOP the instant the live state stops matching what was recorded. All three are exercised
# here against a fake applier -- no board, no units, no clock. That is the point of the
# driver's injection seams (applier / board_provider / rows_provider / animation_gate): the
# stepping logic is a pure core with the live game bolted on at four named places, so what a
# replay DOES is testable without a battle.
#
# The one thing deliberately NOT faked is ReplayLog.decode_command: every entry goes through
# the real gate on its way to the applier, exactly as it does in a live playback.

const REAL_CHECKSUM_ROWS: Array = [
	{ "id": 1, "cell": Vector2i(2, 3), "hp": 20 },
	{ "id": 2, "cell": Vector2i(5, 1), "hp": 14 },
]


## Stands in for the live [CommandApplier]. Records every command it is handed, in order, and
## answers with the same result shape.
class FakeApplier extends RefCounted:
	var applied: Array = []
	var ok: bool = true

	func apply_command(cmd: Dictionary, _board, _ctx = null) -> Dictionary:
		applied.append(cmd)
		return { "ok": ok, "type": int(cmd.get(NetProtocol.KEY_TYPE, -1)), "seq": 0, "reason": "", "events": [] }

	## The command types applied so far, which is what "in order" means for a replay.
	func types() -> Array:
		var out: Array = []
		for cmd in applied:
			out.append(int((cmd as Dictionary).get(NetProtocol.KEY_TYPE, -1)))
		return out

	## The unit ids addressed so far, in order.
	func unit_ids() -> Array:
		var out: Array = []
		for cmd in applied:
			var data: Dictionary = (cmd as Dictionary).get(NetProtocol.KEY_DATA, {})
			out.append(int(data.get(NetProtocol.KEY_UNIT_ID, -1)))
		return out


const Guard := preload("res://tests/helpers/global_state_guard.gd")

var _fake: FakeApplier = null
## Untyped on purpose (tests/README rule 3): a `: RefCounted` annotation makes the static
## analyser reject _guard.watch_setting().
var _guard


func before_each() -> void:
	_fake = FakeApplier.new()
	_guard = Guard.new()
	_guard.watch_setting("game_mode")
	# Spectator mode is process-wide static state. Cleared in BOTH hooks so neither a previous
	# suite's leftovers answer here nor ours leak onward (tests/README rule 3).
	ReplayPlayback.end_playback()
	_clear_combat_services()

func after_each() -> void:
	ReplayPlayback.end_playback()
	ReplayRecorder.recording_enabled = true
	MatchLoadouts.clear()
	_clear_combat_services()
	_guard.restore()

func _clear_combat_services() -> void:
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("clear"):
		CombatServices.clear()


# --- fixtures ----------------------------------------------------------------

## A driver wired to the fake applier and to a board/rows/animation world that never
## interferes. PROCESS_MODE_DISABLED so _process cannot advance playback behind the test's
## back -- every beat in this suite is spent explicitly by advance().
func _driver(log: Dictionary, rows: Array = REAL_CHECKSUM_ROWS) -> ReplayDriver:
	var driver: ReplayDriver = ReplayDriver.new()
	driver.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(driver)
	driver.applier = _fake
	driver.board_provider = func(): return null
	driver.rows_provider = func(): return rows
	driver.animation_gate = func(): return false
	driver.setup(log)
	return driver


## A log of [param commands] (already NetProtocol commands), with [param checksums] as its
## per-turn hashes and a recorded victory in [param turns] turns.
func _log(commands: Array, checksums: Array = [], turns: int = 3) -> Dictionary:
	var log: Dictionary = ReplayLog.make_log({
		"game_version": NetProtocol.local_game_version(),
		"map": { "path": "res://game/maps/resources/proving_grounds.tres" },
	})
	var entries: Array = []
	var turn: int = 1
	for cmd in commands:
		entries.append(ReplayLog.make_entry(turn, 0, cmd))
		if int((cmd as Dictionary).get(NetProtocol.KEY_TYPE, -1)) == NetProtocol.Action.END_TURN:
			turn += 1
	log["entries"] = entries
	log["checksums"] = checksums
	log["outcome"] = ReplayLog.make_outcome(ReplayLog.RESULT_VICTORY, 0, turns)
	return log


## The four-command shape of one recorded turn: move, cast, wait, end turn.
func _one_turn() -> Array:
	return [
		NetProtocol.make_move_unit(1, Vector2i(2, 3), 0),
		NetProtocol.make_cast_move(1, 0, Vector2i(4, 3), 0),
		NetProtocol.make_wait_unit(2, 0),
		NetProtocol.make_end_turn(0, 0),
	]


## Spend enough playback time for [param count] commands at any pacing, in small slices so the
## driver's own beat accounting decides when each one lands (never one giant delta).
func _run(driver: ReplayDriver, seconds: float) -> int:
	var applied: int = 0
	var slices: int = int(ceil(seconds / 0.05))
	for _i in slices:
		applied += driver.advance(0.05)
	return applied


# --- 1. Order is the contract -------------------------------------------------

func test_commands_are_applied_in_recorded_order() -> void:
	var driver: ReplayDriver = _driver(_log(_one_turn()))
	driver.play()
	_run(driver, 6.0)

	assert_eq(_fake.types(), [
		NetProtocol.Action.MOVE_UNIT,
		NetProtocol.Action.CAST_MOVE,
		NetProtocol.Action.WAIT_UNIT,
		NetProtocol.Action.END_TURN,
	], "a replay is the recorded commands re-issued in exactly the order they were committed")
	assert_true(driver.is_finished(), "and the log ended when the last one was applied")

func test_commands_reach_the_applier_decoded() -> void:
	var driver: ReplayDriver = _driver(_log([NetProtocol.make_move_unit(7, Vector2i(9, 4), 0)]))
	driver.play()
	_run(driver, 2.0)

	assert_eq(_fake.applied.size(), 1, "the one recorded command was applied")
	var data: Dictionary = (_fake.applied[0] as Dictionary).get(NetProtocol.KEY_DATA, {})
	assert_eq(data.get(NetProtocol.KEY_DEST_CELL), Vector2i(9, 4),
		"with its cell decoded back to a Vector2i -- the applier takes the command AS-IS")
	assert_eq(int(data.get(NetProtocol.KEY_UNIT_ID, -1)), 7, "addressing the recorded unit")

func test_an_applier_refusal_does_not_stop_playback() -> void:
	# The CHECKSUM is the authority on drift, not an individual apply result: a refused command
	# keeps stepping and the turn boundary decides. Otherwise one unlucky refusal would end a
	# replay that is actually fine.
	_fake.ok = false
	var driver: ReplayDriver = _driver(_log(_one_turn()))
	driver.play()
	_run(driver, 6.0)

	assert_eq(_fake.applied.size(), 4, "every recorded command was still offered to the applier")
	assert_false(driver.is_diverged(), "a refusal is not by itself a divergence")


# --- 2. Pacing ----------------------------------------------------------------

func test_the_beat_is_a_pure_function_of_command_and_speed() -> void:
	assert_gt(ReplayDriver.beat_for(NetProtocol.Action.CAST_MOVE),
		ReplayDriver.beat_for(NetProtocol.Action.MOVE_UNIT),
		"a cast holds longest -- the cut-in, the hit and the numbers all have to land")
	assert_gt(ReplayDriver.beat_for(NetProtocol.Action.MOVE_UNIT),
		ReplayDriver.beat_for(NetProtocol.Action.WAIT_UNIT),
		"a visible slide gets longer than a silent wait, which produced nothing to watch")
	assert_almost_eq(ReplayDriver.beat_for(NetProtocol.Action.MOVE_UNIT, 2.0),
		ReplayDriver.beat_for(NetProtocol.Action.MOVE_UNIT) / 2.0, 0.001,
		"x2 spends the same beat twice as fast")
	assert_gte(ReplayDriver.beat_for(NetProtocol.Action.WAIT_UNIT, 4.0), ReplayDriver.BEAT_MIN,
		"and no speed can collapse a beat below the floor")

func test_a_command_waits_out_its_beat() -> void:
	var driver: ReplayDriver = _driver(_log(_one_turn()))
	driver.play()

	assert_eq(driver.advance(0.0), 1,
		"the first command lands immediately -- nothing is owed yet")
	assert_eq(driver.advance(0.01), 0,
		"and the next one waits: 10ms is not the cast beat this one bought")
	_run(driver, ReplayDriver.BEAT_CAST + 0.1)
	assert_eq(_fake.applied.size(), 2, "once the beat is spent, the next command lands")

func test_speed_cycles_through_the_three_rungs() -> void:
	var driver: ReplayDriver = _driver(_log(_one_turn()))
	assert_eq(driver.speed(), 1.0, "playback starts at x1")
	assert_eq(driver.cycle_speed(), 2.0, "the button steps to x2")
	assert_eq(driver.cycle_speed(), 4.0, "then x4")
	assert_eq(driver.cycle_speed(), 1.0, "then wraps back to x1")

func test_higher_speed_applies_more_of_the_log_in_the_same_time() -> void:
	var slow: ReplayDriver = _driver(_log(_one_turn()))
	slow.play()
	_run(slow, 1.0)
	var slow_count: int = _fake.applied.size()

	_fake = FakeApplier.new()
	var fast: ReplayDriver = _driver(_log(_one_turn()))
	fast.speed_index = 2   # x4
	fast.play()
	_run(fast, 1.0)

	assert_gt(_fake.applied.size(), slow_count,
		"x4 is faster because the same beats are SPENT faster -- not because time_scale changed")

func test_the_animation_gate_holds_the_next_command() -> void:
	var busy: Array = [true]   # Array, not bool: GUT lambdas capture BY VALUE
	var driver: ReplayDriver = _driver(_log(_one_turn()))
	driver.animation_gate = func(): return bool(busy[0])
	driver.play()

	assert_eq(driver.advance(0.1), 0,
		"nothing is applied while the previous action is still animating")
	busy[0] = false
	assert_eq(driver.advance(0.1), 1, "and playback resumes the moment the screen goes quiet")


# --- 3. Pause / step ----------------------------------------------------------

func test_pause_stops_the_clock() -> void:
	var driver: ReplayDriver = _driver(_log(_one_turn()))
	driver.play()
	driver.advance(0.0)
	driver.pause()
	_run(driver, 5.0)

	assert_eq(_fake.applied.size(), 1, "a paused replay applies nothing, however long it waits")
	assert_true(driver.toggle_play(), "the same button resumes it")
	_run(driver, 5.0)
	assert_gt(_fake.applied.size(), 1, "and playback carries on from where it was held")

func test_step_applies_exactly_one_command_and_only_while_paused() -> void:
	var driver: ReplayDriver = _driver(_log(_one_turn()))
	assert_true(driver.step(), "stepping from PAUSED applies one command")
	assert_eq(_fake.applied.size(), 1, "exactly one -- frame-stepping ignores the beat")
	assert_true(driver.step(), "and again")
	assert_eq(_fake.applied.size(), 2, "one per press")

	driver.play()
	assert_false(driver.step(), "stepping is meaningless while PLAYING, so it is refused")
	assert_eq(_fake.applied.size(), 2, "and applies nothing")


# --- 4. The divergence tripwire ----------------------------------------------

func test_a_matching_checksum_lets_playback_continue() -> void:
	var expected: String = ReplayLog.state_checksum(REAL_CHECKSUM_ROWS)
	var driver: ReplayDriver = _driver(_log(_one_turn(), [ReplayLog.make_checksum(1, expected)]))

	assert_true(driver.verify_next_checksum(),
		"the live board hashes to exactly what was recorded for that turn")
	assert_false(driver.is_diverged(), "so playback is untouched")

func test_a_mismatched_checksum_stops_playback_dead() -> void:
	var reports: Array = []   # Array, not int: GUT lambdas capture BY VALUE
	var driver: ReplayDriver = _driver(_log(_one_turn(), [ReplayLog.make_checksum(4, "deadbeefdeadbeef")]))
	driver.diverged.connect(func(turn, expected, actual): reports.append([turn, expected, actual]))
	driver.play()

	assert_false(driver.verify_next_checksum(),
		"the live board no longer hashes to what was recorded")
	assert_true(driver.is_diverged(), "so playback STOPS -- it is no longer a recording of anything")
	assert_eq(driver.diverged_turn(), 4, "naming the turn it diverged on")
	assert_eq(reports.size(), 1, "and reporting it exactly once")
	assert_eq(String(reports[0][1]), "deadbeefdeadbeef", "carrying the recorded hash")

	_run(driver, 5.0)
	assert_eq(_fake.applied.size(), 0,
		"and NOTHING is applied afterwards -- never keep playing a lie")

func test_a_diverged_replay_cannot_be_resumed() -> void:
	var driver: ReplayDriver = _driver(_log(_one_turn(), [ReplayLog.make_checksum(1, "0000000000000000")]))
	driver.verify_next_checksum()
	driver.play()
	assert_true(driver.is_diverged(), "play() cannot un-diverge a replay")
	assert_false(driver.step(), "and neither can stepping")

func test_the_divergence_banner_names_the_suspect() -> void:
	var driver: ReplayDriver = _driver(_log(_one_turn(), [ReplayLog.make_checksum(2, "0000000000000000")]))
	driver.verify_next_checksum()
	assert_string_contains(driver.status_text(), ReplayDriver.DIVERGED_MESSAGE,
		"the player is told the replay diverged, and that a build mismatch is the likely cause")

func test_a_log_with_no_checksums_left_is_not_a_divergence() -> void:
	# A TRUNCATED recording simply stops being checkable. That is a known outcome, not a fault.
	var driver: ReplayDriver = _driver(_log(_one_turn(), []))
	assert_true(driver.verify_next_checksum(), "no recorded hash means nothing to disagree with")
	assert_false(driver.is_diverged(), "so playback continues")


# --- 5. The end of the log ----------------------------------------------------

func test_the_end_of_the_log_reports_the_recorded_outcome() -> void:
	var outcomes: Array = []   # Array, not Dictionary: GUT lambdas capture BY VALUE
	var driver: ReplayDriver = _driver(_log(_one_turn(), [], 9))
	driver.finished.connect(func(outcome): outcomes.append(outcome))
	driver.play()
	_run(driver, 6.0)

	assert_true(driver.is_finished(), "playback ends when the log runs out")
	assert_eq(outcomes.size(), 1, "reporting the outcome exactly once")
	assert_eq(String((outcomes[0] as Dictionary).get("result", "")), ReplayLog.RESULT_VICTORY,
		"and it is the RECORDED outcome -- what actually happened in that battle")
	assert_string_contains(driver.outcome_text(), "VICTORY", "which is what the bar then shows")
	assert_string_contains(driver.outcome_text(), "9 turns", "along with how long it took")

func test_the_turn_counter_tracks_the_playhead() -> void:
	var commands: Array = _one_turn()
	commands.append_array(_one_turn())   # a second recorded turn
	var driver: ReplayDriver = _driver(_log(commands, [], 2))

	assert_eq(driver.turn_label(), "Turn 1/2", "the counter opens on the first recorded turn")
	for _i in 4:
		driver.step()
	assert_eq(driver.turn_label(), "Turn 2/2",
		"and follows the playhead across the recorded END_TURN")

func test_an_unfinished_recording_still_describes_itself() -> void:
	var log: Dictionary = _log(_one_turn(), [], 0)
	log["outcome"] = ReplayLog.make_outcome(ReplayLog.RESULT_UNKNOWN, -1, 0)
	log["truncated"] = true
	var driver: ReplayDriver = _driver(log)
	assert_string_contains(driver.outcome_text(), "UNFINISHED",
		"a battle that was quit mid-match says so rather than claiming a result")
	assert_string_contains(driver.outcome_text(), "truncated",
		"and a capped recording admits its tail is missing")


# --- 6. The spectator gates ---------------------------------------------------
#
# Watching a replay must take exactly two things away -- the player's ability to command, and
# the AI's ability to act -- and nothing else. Both hang off ReplayPlayback.is_playing().

func test_playback_locks_the_human_out_of_commanding() -> void:
	# UnitActionsPanel._player_is_human is THE gate: _human_may_command ends in it, and End
	# Player Turn calls it directly, so one false answer closes the whole command loop.
	var panel: UnitActionsPanel = autofree(UnitActionsPanel.new())
	var player: Player = Player.new(0, "Rowan")
	player.is_ai = false
	# Assigned, never through a setter: several GameSettings setters persist to the player's
	# real settings.cfg (tests/README rule 3). The guard restores it from after_each.
	GameSettings.game_mode = GameSettings.GameMode.SINGLE_PLAYER

	assert_true(panel._player_is_human(player),
		"in an ordinary battle the local human commands their own units")
	ReplayPlayback.begin_playback()
	assert_false(panel._player_is_human(player),
		"but a replay viewer is a SPECTATOR -- every command comes from the log instead")
	ReplayPlayback.end_playback()
	assert_true(panel._player_is_human(player),
		"and control comes back the moment playback ends")

func test_playback_frees_the_bot_driver() -> void:
	var root: Node = Node.new()
	add_child_autofree(root)
	var bot: BotTurnDriver = BotTurnDriver.new()
	bot.name = "BotTurnDriver"
	root.add_child(bot)
	var bystander: Node = Node.new()
	bystander.name = "SpawnManager"
	root.add_child(bystander)

	assert_eq(ReplayPlayback.disable_ai_drivers(root), 1, "the AI driver is removed")
	assert_null(root.get_node_or_null("BotTurnDriver"),
		"so the AI cannot take its recorded actions a SECOND time on top of the replayed ones")
	assert_not_null(root.get_node_or_null("SpawnManager"),
		"and nothing else in the battle is touched")


# --- 7. Against a REAL board --------------------------------------------------
#
# Everything above proves the transport. This proves the one thing a fake applier cannot: that
# a recorded command, decoded by the real gate and applied by the real CommandApplier, moves a
# real unit on a real map -- and that the checksum computed from THAT board is the same
# quantity the recorder stamps.

const MAP_PATH := "res://game/maps/resources/proving_grounds.tres"

## Load the real map, register its units the way the battle's command seam does, and hand back
## { board, applier, unit, cell }. Empty when the fixture could not be built.
func _live_seam() -> Dictionary:
	var root3d: Node3D = Node3D.new()
	add_child_autofree(root3d)
	var loader: MapLoader = MapLoader.new()
	root3d.add_child(loader)
	loader.load_map(load(MAP_PATH), root3d)
	if loader.map_root == null:
		return {}
	CombatServices.rebuild(loader.map_root)
	var board = CombatServices.board()
	if board == null or not board.has_method("all_units"):
		return {}
	var units: Array = board.all_units()
	if units.is_empty():
		return {}
	# Deterministic ids in load order, ids from 1 -- exactly what _setup_command_seam does.
	var registry := CommandApplier.UnitRegistry.new()
	registry.assign_map_units(units)
	return {
		"board": board,
		"applier": CommandApplier.new(registry, null),
		"unit": registry.unit_for(1),
		"cell": board.cell_of(registry.unit_for(1)),
	}

func test_a_recorded_move_moves_a_real_unit() -> void:
	var seam: Dictionary = _live_seam()
	if seam.is_empty():
		pending("the proving_grounds fixture could not be built in this environment")
		return
	var board = seam["board"]
	var origin: Vector2i = seam["cell"]
	var destination: Vector2i = origin + Vector2i(0, 1)

	var driver: ReplayDriver = ReplayDriver.new()
	driver.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(driver)
	driver.applier = seam["applier"]
	driver.board_provider = func(): return board
	driver.animation_gate = func(): return false
	# Through the STRICT importer first, exactly as a replay read off disk would be.
	driver.setup(ReplayLog.validate(_log([NetProtocol.make_move_unit(1, destination, 0)])))

	assert_true(driver.step(), "the recorded command was applied")
	assert_eq(board.cell_of(seam["unit"]), destination,
		"and the real unit is where the recording says it went")

func test_the_checksum_over_a_real_board_is_the_recorders_quantity() -> void:
	var seam: Dictionary = _live_seam()
	if seam.is_empty():
		pending("the proving_grounds fixture could not be built in this environment")
		return

	# The rows playback hashes are gathered by the SAME static the recorder stamps from, so the
	# tripwire compares like with like.
	var live_hash: String = ReplayLog.state_checksum(ReplayRecorder.board_state_rows())
	assert_eq(live_hash.length(), 16, "a state checksum is a 16-char hex string")

	var matching: ReplayDriver = ReplayDriver.new()
	matching.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(matching)
	matching.applier = _fake
	matching.setup(_log([], [ReplayLog.make_checksum(1, live_hash)]))
	assert_true(matching.verify_next_checksum(),
		"a board that still matches the recording passes the turn-boundary check")
	assert_false(matching.is_diverged(), "so playback carries on")

	var drifted: ReplayDriver = ReplayDriver.new()
	drifted.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(drifted)
	drifted.applier = _fake
	drifted.setup(_log([], [ReplayLog.make_checksum(1, "ffffffffffffffff")]))
	assert_false(drifted.verify_next_checksum(), "one that does not is caught")
	assert_true(drifted.is_diverged(),
		"and playback stops rather than showing a battle that never happened")


# --- 8. The transport bar -----------------------------------------------------

## A mounted HUD bound to [param driver]. The bar builds its own UI in _ready.
func _hud(driver: ReplayDriver) -> ReplayHUD:
	var hud: ReplayHUD = ReplayHUD.new()
	add_child_autofree(hud)
	hud.bind_driver(driver)
	return hud

func test_the_transport_bar_stays_off_screen_outside_playback() -> void:
	var hud: ReplayHUD = _hud(_driver(_log(_one_turn())))
	assert_false(hud.is_showing(),
		"an ordinary battle mounts the bar and never sees it -- it costs one hidden layer")

func test_the_transport_bar_reads_the_driver() -> void:
	ReplayPlayback.begin_playback()
	var driver: ReplayDriver = _driver(_log(_one_turn(), [], 5))
	var hud: ReplayHUD = _hud(driver)

	assert_true(hud.is_showing(), "the bar is on screen while a replay is being watched")
	assert_eq(hud.turn_text(), "Turn 1/5", "showing which recorded turn is playing")
	assert_eq(hud.status_text(), "",
		"with no banner: 'paused' is chrome, not news -- the play button already says it")

	driver.step()
	assert_eq(hud.turn_text(), "Turn 1/5",
		"and it redraws off the driver's own read-outs as commands are applied")

func test_the_transport_bar_banners_a_divergence() -> void:
	ReplayPlayback.begin_playback()
	var driver: ReplayDriver = _driver(_log(_one_turn(), [ReplayLog.make_checksum(3, "0000000000000000")]))
	var hud: ReplayHUD = _hud(driver)
	driver.verify_next_checksum()

	assert_string_contains(hud.status_text(), ReplayDriver.DIVERGED_MESSAGE,
		"a divergence is the one thing the bar MUST say out loud")

func test_the_transport_bar_announces_the_recorded_outcome() -> void:
	ReplayPlayback.begin_playback()
	var driver: ReplayDriver = _driver(_log(_one_turn(), [], 6))
	var hud: ReplayHUD = _hud(driver)
	driver.play()
	_run(driver, 6.0)

	assert_string_contains(hud.status_text(), "VICTORY",
		"when the log runs out the bar reports how the recorded battle ended")


# --- 9. The battle wiring compiles -------------------------------------------

func test_the_battle_boot_and_hud_layout_still_load() -> void:
	# Both files gained replay wiring (the boot phases, the transport-bar mount) and neither is
	# instantiable in a test -- GameWorldManager's _ready loads a map and awaits frames. Loading
	# the scripts is what proves the wiring parses and its class references resolve; without it,
	# a typo in either would only surface when a player started a battle.
	assert_not_null(load("res://game/world/GameWorldManager.gd"),
		"the battle boot (replay phases 1-3) compiles")
	assert_not_null(load("res://game/ui/layout/UILayoutManager.gd"),
		"and so does the HUD layout that mounts the transport bar")
