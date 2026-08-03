extends Node
class_name ReplayDriver

## THE PLAYBACK ENGINE: steps a recorded command log back through the live game.
##
## Mounted once per replay battle by [method GameWorldManager._mount_replay_driver], after the
## board, the players and the command seam exist. Every entry goes through
## [method ReplayLog.decode_command] and then through the SAME
## [method CommandApplier.apply_command] a networked command takes -- there is no second
## simulator, no "replay mode" branch inside gameplay, and therefore nothing that can drift
## from live play. The turn system advances exactly as it does in a real battle: the recorded
## END_TURN commands drive it, and a unit's recorded wait/cast marks its action, which is what
## makes Speed First's queue tick over. Nothing here calls into the turn system directly.
##
## PACING, and why it is delays rather than [member Engine.time_scale]. The animations, the
## camera and the FX are the whole point of watching a replay, so playback does not rush them:
## each command buys a BEAT sized by what it is (a cast holds longest, a silent wait is nearly
## free), and the next command waits out that beat. Speed multiplies how fast the beat is spent
## -- x4 means the beats pass four times faster -- and never touches [member Engine.time_scale],
## which would also speed up (and desynchronise) the animations, the tweens and the audio it is
## meant to let you watch. Before each beat is spent the driver also waits for the animation
## registry to go quiet, exactly as [BotTurnDriver] does, so a command never lands on top of
## the previous one's flourish. That wait is capped, so a stuck busy flag cannot wedge playback.
##
## THE DIVERGENCE TRIPWIRE. At every turn boundary -- the ACTIVE turn system's
## [signal TurnSystemBase.turn_ended], the same signal the recorder stamped its checksums on,
## never [PlayerManager]'s (project convention #2) -- the driver recomputes
## [method ReplayLog.state_checksum] over the live board and compares it against the recorded
## hash for that boundary. A mismatch means this build re-simulated the commands into a
## DIFFERENT battle, so playback STOPS dead and says so. It never keeps playing: a replay that
## has drifted is no longer a recording of anything, and showing it as one is the single worst
## thing this system could do.
##
## TESTABILITY. The stepping logic is a pure-as-possible core -- [method advance] takes a delta
## and returns how many commands it applied, [method step_one] applies exactly one, and
## [method beat_for] is a static function of the command type and the speed. The three things
## that reach into the live game (the applier, the board, the checksum rows) are injectable
## fields, so the whole transport can be driven headless against a fake applier.

## Group the battle HUD finds this node by.
const GROUP := &"replay_driver"

## Emitted whenever anything the transport bar draws has changed (a command applied, the
## speed cycled, play/pause toggled, the log ended, a divergence).
signal state_changed()
## Playback stopped because the live state no longer matches what was recorded, at
## [param turn]. Carries both hashes for a log line / bug report.
signal diverged(turn: int, expected: String, actual: String)
## The log ran out. [param outcome] is the RECORDED outcome dictionary (see
## [method ReplayLog.make_outcome]) -- what actually happened in the recorded battle.
signal finished(outcome: Dictionary)

enum State {
	PLAYING,   ## Beats are being spent and commands applied.
	PAUSED,    ## Held. [method step] applies exactly one command from here.
	DIVERGED,  ## Stopped for good: the live state no longer matches the recording.
	FINISHED,  ## The log ran out. The recorded outcome is on screen.
}

## The transport's speed rungs. Multiplies how fast a beat is spent -- see the class docs for
## why this is never [member Engine.time_scale].
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

# --- Beats (seconds at x1) ---------------------------------------------------
# Sized by what the player needs to SEE. A cast is the moment of the turn (the cut-in, the
# hit, the numbers); a plain relocation wants long enough to read the slide; a wait produced
# nothing visible at all, so it costs almost nothing; a turn end covers the transition wipe.

const BEAT_CAST: float = 0.90
const BEAT_MOVE: float = 0.55
const BEAT_WAIT: float = 0.12
const BEAT_END_TURN: float = 0.70
## Floor on any beat after the speed divide, so even x4 cannot collapse playback into one frame.
const BEAT_MIN: float = 0.02

## How long a single [method advance] will wait for animations before proceeding anyway --
## the same belt-and-braces [BotTurnDriver] uses so a stuck busy flag cannot deadlock playback.
const ANIM_WAIT_CAP: float = 3.0

## What the HUD says when the tripwire fires.
const DIVERGED_MESSAGE := "Replay diverged — recorded on a different version?"

## UnitAnimator's script, referenced for its STATIC busy registry (not the autoload), so the
## gate resolves headless exactly as [BotTurnDriver]'s does.
const ANIMATOR_SCRIPT = preload("res://game/visuals/UnitAnimator.gd")

# --- The log -----------------------------------------------------------------

## The validated log being played.
var log: Dictionary = {}
## Its body, in order. Read directly by [method step_one].
var entries: Array = []
## Its per-turn checksums, consumed in order at each turn boundary.
var checksums: Array = []
## How many entries have been consumed -- the playhead.
var index: int = 0

# --- Transport ---------------------------------------------------------------

var state: int = State.PAUSED
## Index into [constant SPEEDS].
var speed_index: int = 0

# --- Injection seams (live defaults resolved lazily; a test hands in doubles) --

## Anything with [code]apply_command(cmd, board)[/code]. Defaults to the battle's live
## [CommandApplier], installed on [NetSession] by the command seam.
var applier: Object = null
## [code]func() -> board[/code]. Defaults to the shared live board.
var board_provider: Callable = Callable()
## [code]func() -> Array[/code] of checksum rows. Defaults to
## [method ReplayRecorder.board_state_rows] -- the identical rows recording hashed.
var rows_provider: Callable = Callable()
## [code]func() -> bool[/code], "is an animation still playing". Defaults to the shared
## animation registry; a headless test injects one that is never busy.
var animation_gate: Callable = Callable()

# --- Internals ---------------------------------------------------------------

## Seconds of beat still owed before the next command may be applied.
var _beat_left: float = 0.0
## Seconds already spent waiting for animations on the CURRENT beat (capped).
var _anim_waited: float = 0.0
## How many recorded checksums have been consumed (one per turn boundary).
var _checksum_index: int = 0
## The turn a divergence was detected on, or -1.
var _diverged_turn: int = -1
var _turn_system: TurnSystemBase = null


func _ready() -> void:
	add_to_group(GROUP)
	_bind_turn_system_manager()
	_bind_hud()


func _exit_tree() -> void:
	_unbind_turn_system()
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null \
			and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	# Battle teardown is the LAST moment playback exists, so this is where spectator mode is
	# disarmed and recording switched back on -- whichever way the player left (exit button,
	# pause menu, game over). See ReplayPlayback.end_playback.
	ReplayPlayback.end_playback()


func _process(delta: float) -> void:
	advance(delta)


# --- Setup -------------------------------------------------------------------

## Load [param replay_log] (already validated) and hold at the first command. Playback starts
## PAUSED and is started by [method play]; the boot does that once the battle has settled, so
## the first command never lands on the same frame as the map finishing loading.
func setup(replay_log: Dictionary) -> void:
	log = replay_log
	entries = log.get("entries", [])
	checksums = log.get("checksums", [])
	index = 0
	_checksum_index = 0
	_beat_left = 0.0
	state = State.PAUSED
	state_changed.emit()


# --- Transport controls ------------------------------------------------------

func play() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	state_changed.emit()


func pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	state_changed.emit()


## Play/pause button. A stopped replay (diverged / finished) cannot be resumed -- there is
## nothing left to play, and a diverged one must never resume.
func toggle_play() -> bool:
	if state == State.PLAYING:
		pause()
	elif state == State.PAUSED:
		play()
	return state == State.PLAYING


## Cycle x1 -> x2 -> x4 -> x1 and report the new multiplier. Takes effect on the NEXT beat;
## the beat already owed is not retimed, so the command being watched is not cut short.
func cycle_speed() -> float:
	speed_index = (speed_index + 1) % SPEEDS.size()
	state_changed.emit()
	return speed()


func speed() -> float:
	return SPEEDS[clampi(speed_index, 0, SPEEDS.size() - 1)]


## Apply exactly ONE command, only while PAUSED. This is frame-stepping: it deliberately
## ignores beats and the animation gate, because the player asked for the next command NOW.
## Returns true when a command was consumed.
func step() -> bool:
	if state != State.PAUSED:
		return false
	var res: Dictionary = step_one()
	_beat_left = 0.0
	return bool(res.get("stepped", false))


# --- The stepping core -------------------------------------------------------

## Spend [param delta] seconds of playback time and apply whatever commands come due. Returns
## how many were applied. This is the whole clock: [method _process] is a one-line caller, so a
## test drives playback by handing it deltas instead of waiting on a real one.
func advance(delta: float) -> int:
	if state != State.PLAYING:
		return 0
	# Let the previous command's animation finish before the next one lands on top of it.
	if _defer_for_animations(delta):
		return 0
	_beat_left -= maxf(0.0, delta) * speed()
	var applied: int = 0
	while _beat_left <= 0.0:
		if state != State.PLAYING:
			break
		var res: Dictionary = step_one()
		if not bool(res.get("stepped", false)):
			break
		applied += 1
		_beat_left += float(res.get("beat", BEAT_MIN))
	return applied


## Consume the next entry and apply it. Returns
## [code]{ stepped, applied, beat, type, reason }[/code]:
##   * [code]stepped[/code] false means the playhead did not move -- the log ended (which
##     FINISHES playback) or playback is stopped.
##   * [code]applied[/code] false with [code]stepped[/code] true means the entry was consumed
##     but the applier refused it (an unknown unit, a cast that no longer resolves). That is a
##     drift signal, but the CHECKSUM is the authority on drift, so this keeps stepping rather
##     than guessing -- the turn boundary will catch it.
func step_one() -> Dictionary:
	if state == State.DIVERGED or state == State.FINISHED:
		return { "stepped": false, "applied": false, "beat": BEAT_MIN, "reason": "stopped" }
	if index >= entries.size():
		_finish()
		return { "stepped": false, "applied": false, "beat": BEAT_MIN, "reason": "end_of_log" }

	var entry: Dictionary = entries[index] if entries[index] is Dictionary else {}
	index += 1
	var cmd: Dictionary = ReplayLog.decode_command(entry.get("cmd", null))
	if cmd.is_empty():
		# validate() already dropped undecodable entries, so this is unreachable for a log that
		# came through the gate -- and it is still handled, because "skip it" is the only sane
		# answer and it must not cost a beat.
		state_changed.emit()
		return { "stepped": true, "applied": false, "beat": BEAT_MIN, "reason": "undecodable" }

	var type: int = int(cmd.get(NetProtocol.KEY_TYPE, -1))
	var result: Dictionary = _apply(cmd)
	state_changed.emit()
	return {
		"stepped": true,
		"applied": bool(result.get("ok", false)),
		"beat": beat_for(type, speed()),
		"type": type,
		"reason": String(result.get("reason", "")),
	}


## The beat [param type] buys, already divided by [param speed_scale] and floored. Pure --
## the pacing MODEL is a function, so it is assertable without a clock or a board.
static func beat_for(type: int, speed_scale: float = 1.0) -> float:
	var base: float = BEAT_WAIT
	match type:
		NetProtocol.Action.CAST_MOVE:
			base = BEAT_CAST
		NetProtocol.Action.MOVE_UNIT:
			base = BEAT_MOVE
		NetProtocol.Action.END_TURN:
			base = BEAT_END_TURN
		NetProtocol.Action.WAIT_UNIT:
			base = BEAT_WAIT
	return maxf(BEAT_MIN, base / maxf(0.01, speed_scale))


# --- The divergence tripwire -------------------------------------------------

## Compare the live board against the next recorded checksum. Called at every turn boundary.
## Returns true when they agree (or when there is nothing recorded left to compare against --
## a truncated log simply stops being checkable, which is not a divergence).
func verify_next_checksum() -> bool:
	if state == State.DIVERGED or state == State.FINISHED:
		return true
	if _checksum_index >= checksums.size():
		return true
	var recorded: Dictionary = checksums[_checksum_index] if checksums[_checksum_index] is Dictionary else {}
	_checksum_index += 1
	var expected: String = String(recorded.get("hash", ""))
	if expected.is_empty():
		return true
	var actual: String = ReplayLog.state_checksum(_rows())
	if actual == expected:
		return true
	_diverge(int(recorded.get("turn", -1)), expected, actual)
	return false


func is_diverged() -> bool:
	return state == State.DIVERGED


func is_finished() -> bool:
	return state == State.FINISHED


## The turn a divergence was found on, or -1.
func diverged_turn() -> int:
	return _diverged_turn


func _diverge(turn: int, expected: String, actual: String) -> void:
	_diverged_turn = turn
	state = State.DIVERGED
	diverged.emit(turn, expected, actual)
	state_changed.emit()


func _finish() -> void:
	if state == State.FINISHED:
		return
	state = State.FINISHED
	finished.emit(recorded_outcome())
	state_changed.emit()


# --- What the HUD reads ------------------------------------------------------

## The turn currently being watched: the turn stamped on the NEXT command to apply, or the
## last recorded turn once the log has run out.
func current_turn() -> int:
	if index < entries.size() and entries[index] is Dictionary:
		return int((entries[index] as Dictionary).get("turn", 0))
	return total_turns()


## How many turns the recorded battle lasted. The outcome's tally is authoritative; a log
## whose battle never finished falls back to the highest turn its body mentions.
func total_turns() -> int:
	var turns: int = int(recorded_outcome().get("turns", 0))
	if turns > 0:
		return turns
	var last: int = 0
	for entry in entries:
		if entry is Dictionary:
			last = maxi(last, int((entry as Dictionary).get("turn", 0)))
	return last


## "Turn 4/12" -- the transport bar's counter.
func turn_label() -> String:
	return "Turn %d/%d" % [current_turn(), maxi(total_turns(), current_turn())]


func recorded_outcome() -> Dictionary:
	var outcome: Variant = log.get("outcome", {})
	return outcome if outcome is Dictionary else {}


## One line describing how the recorded battle ended -- shown when the log runs out.
func outcome_text() -> String:
	var outcome: Dictionary = recorded_outcome()
	var result: String = String(outcome.get("result", ReplayLog.RESULT_UNKNOWN))
	var turns: int = int(outcome.get("turns", 0))
	var winner: int = int(outcome.get("winner_slot", -1))
	var headline: String = ""
	match result:
		ReplayLog.RESULT_VICTORY:
			headline = "VICTORY" if winner < 0 else "VICTORY — Player %d" % (winner + 1)
		ReplayLog.RESULT_DEFEAT:
			headline = "DEFEAT"
		ReplayLog.RESULT_DRAW:
			headline = "DRAW"
		_:
			headline = "UNFINISHED"
	if bool(log.get("truncated", false)):
		headline += " (recording was truncated)"
	return "%s · %d turns" % [headline, turns] if turns > 0 else headline


## The one line the transport bar shows about playback itself.
func status_text() -> String:
	match state:
		State.DIVERGED:
			return DIVERGED_MESSAGE if _diverged_turn < 0 \
				else "%s (turn %d)" % [DIVERGED_MESSAGE, _diverged_turn]
		State.FINISHED:
			return outcome_text()
		State.PAUSED:
			return "Paused"
		_:
			return ""


# --- Live wiring -------------------------------------------------------------

func _apply(cmd: Dictionary) -> Dictionary:
	var target: Object = _resolve_applier()
	if target == null or not target.has_method("apply_command"):
		return { "ok": false, "reason": "no_applier" }
	return target.call("apply_command", cmd, _board())


## The battle's live [CommandApplier], resolved once and cached. Read off [NetSession] because
## that is where [method GameWorldManager._setup_command_seam] installs the applier bound to
## THIS battle's board -- playback drives the very same seam networked play does.
func _resolve_applier() -> Object:
	if applier != null and is_instance_valid(applier):
		return applier
	if typeof(NetSession) == TYPE_OBJECT and NetSession != null:
		applier = NetSession.command_applier
	return applier


func _board():
	if board_provider.is_valid():
		return board_provider.call()
	return CombatServices.board() if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null else null


func _rows() -> Array:
	if rows_provider.is_valid():
		var rows: Variant = rows_provider.call()
		return rows if rows is Array else []
	return ReplayRecorder.board_state_rows()


## True while an animation is still playing AND the wait budget for this beat is not spent.
## [param delta] advances that budget, so the cap is real time rather than a frame count.
func _defer_for_animations(delta: float) -> bool:
	if not _animations_busy():
		_anim_waited = 0.0
		return false
	if _anim_waited >= ANIM_WAIT_CAP:
		_anim_waited = 0.0
		return false
	_anim_waited += maxf(0.0, delta)
	return true


func _animations_busy() -> bool:
	if animation_gate.is_valid():
		return bool(animation_gate.call())
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and GameSettings.has_method("animations_on") and not GameSettings.animations_on():
		return false
	return ANIMATOR_SCRIPT.is_any_animation_playing()


# --- Turn plumbing (the ACTIVE turn system, never PlayerManager) -------------

func _bind_turn_system_manager() -> void:
	if typeof(TurnSystemManager) != TYPE_OBJECT or TurnSystemManager == null:
		return
	if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
	if TurnSystemManager.has_active_turn_system():
		_bind_turn_system(TurnSystemManager.get_active_turn_system())


func _on_turn_system_activated(system: TurnSystemBase) -> void:
	_bind_turn_system(system)


func _bind_turn_system(system: TurnSystemBase) -> void:
	if system == _turn_system:
		return
	_unbind_turn_system()
	_turn_system = system
	if _turn_system == null:
		return
	if not _turn_system.turn_ended.is_connected(_on_turn_ended):
		_turn_system.turn_ended.connect(_on_turn_ended)


func _unbind_turn_system() -> void:
	if _turn_system == null or not is_instance_valid(_turn_system):
		_turn_system = null
		return
	if _turn_system.turn_ended.is_connected(_on_turn_ended):
		_turn_system.turn_ended.disconnect(_on_turn_ended)
	_turn_system = null


func _on_turn_ended(_player) -> void:
	verify_next_checksum()


## Hand ourselves to the transport bar if it is already mounted. The HUD is built with the
## rest of the battle UI (before this driver exists) and also looks US up in its own _ready,
## so whichever lands second completes the binding.
func _bind_hud() -> void:
	var hud: Node = get_tree().get_first_node_in_group(&"replay_hud") if get_tree() != null else null
	if hud != null and hud.has_method("bind_driver"):
		hud.call("bind_driver", self)
