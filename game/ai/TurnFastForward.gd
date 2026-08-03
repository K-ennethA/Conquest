extends RefCounted
class_name TurnFastForward

## FAST-FORWARD THE ENEMY TURN. The policy object behind the battle HUD's skip button.
##
## WHAT IT IS NOT. It is not a "skip": the AI still plans and issues EVERY command through the
## ordinary path ([BotTurnDriver] -> [Unit.perform_move] -> [MoveExecutor]), so the battle log,
## the replay recorder, statuses, cooldowns, items and win conditions all see exactly what they
## would have seen at full speed. Nothing is teleported, nothing is resolved out of band, and
## the turn ends in the same state either way. All that changes is how long the presentation
## dwells on each beat.
##
## WHAT IT ACTUALLY DOES, in three places, all reading this one latch:
##   1. PACING. [BotTurnDriver]'s deliberate beats -- the inter-action interval, the post-ATTACK
##      dwell and the post-MOVE dwell, each of which is floored so a strike stays watchable --
##      are divided by [constant SPEED_MULTIPLIER] and floored at [constant MIN_BEAT] instead
##      (see [method scale_delay]). The driver still spends one beat per action, so the actions
##      keep their order; the beat is just ~1 frame long.
##   2. ANIMATION GATES. The driver's animation-quiet gate (wait for the screen to go quiet,
##      up to `anim_wait_cap`, then proceed anyway) collapses to its MINIMUM: the cap becomes 0
##      (see [method scale_anim_cap]), so the gate proceeds on its first check rather than
##      spending up to 3 real seconds per action waiting on animations nobody is watching.
##   3. CAMERA. [CameraController] suppresses event-driven auto-focus while this is armed (see
##      its `_should_auto_focus`), so the camera does not fly around chasing hits during the
##      fast-forward.
##
## NEVER IN A NETWORKED MATCH. Both peers run the same clock; letting one of them shorten its
## own AI pacing would desync the two players' experience of a live match and hand a
## real-time advantage to whoever pressed the button. [method allows] refuses, [method arm]
## refuses with it, and the HUD button hides itself.
##
## AUTO-DISARM. Fast-forward is scoped to the ENEMY turn that was in flight when it was armed:
## [method note_turn_started] drops it the moment a non-AI player's turn begins, so the player
## never returns to a board that is still racing. Every turn-signal subscriber that knows about
## this latch calls it, and it is idempotent, so whichever one is connected first wins.
##
## STATE IS STATIC AND PROCESS-WIDE, deliberately: the readers (the AI driver, the camera) are
## in the 3D scene and the writer (the HUD button) is on a CanvasLayer, with no sane node path
## between them, and the latch is a single bool. Tests MUST call [method reset] from both
## `before_each` and `after_each` -- see tests/README.md rule 3 on static registries.

## How much faster than authored the AI's beats run while armed. Applied as a DIVISOR to each
## authored delay, then floored by [constant MIN_BEAT]; a multiplier (rather than a flat zero)
## is what keeps this a fast-forward rather than a teleport -- every action still gets its own
## beat, just a very short one.
const SPEED_MULTIPLIER: float = 24.0

## Floor (seconds) on any scaled beat. A Timer armed at 0 fires on the next frame anyway, so
## this is really "one frame-ish", but naming it keeps the driver's contract ("the one-shot
## timer always has a positive wait") explicit rather than accidental.
const MIN_BEAT: float = 0.01

## Whether fast-forward is currently running. Static: see the class doc.
static var _armed: bool = false


# --- The latch ---------------------------------------------------------------

static func is_armed() -> bool:
	return _armed


## Arm fast-forward. Returns whether it is now armed -- false (changing nothing) when
## [method can_arm] refuses, which is the quiet-failure contract: a refused arm is a foreseeable
## condition (a networked match), not an engine error. Idempotent.
static func arm() -> bool:
	if not can_arm():
		return false
	_armed = true
	return true


## Drop fast-forward. Always succeeds; idempotent.
static func disarm() -> void:
	_armed = false


## Flip the latch, returning its new value. The button's and the hotkey's shared entry point.
static func toggle() -> bool:
	if _armed:
		disarm()
		return false
	return arm()


## Clear the process-wide latch. For tests (before_each AND after_each) and for a battle
## teardown that wants to be certain nothing survives into the next one.
static func reset() -> void:
	_armed = false


# --- Who may arm -------------------------------------------------------------

## The PURE decision behind [method can_arm], split out so the refusal can be tested without
## standing up a networked session or a replay. [param networked] is the only hard exclusion
## (see the class doc); [param replaying] is refused because a replay already has its own
## transport bar with its own speed control ([ReplayHUD]), and two competing speed controls on
## one screen is a bug waiting to happen.
static func allows(networked: bool, replaying: bool) -> bool:
	if networked:
		return false
	if replaying:
		return false
	return true


## True when fast-forward may be armed in the CURRENT session. Reads the live autoloads
## defensively (both may be absent in a headless test), so a bare harness always allows it.
static func can_arm() -> bool:
	return allows(_is_networked(), _is_replaying())


static func _is_networked() -> bool:
	var net = _node("/root/NetSession")
	return net != null and net.has_method("is_networked_match") and bool(net.is_networked_match())


static func _is_replaying() -> bool:
	return ReplayPlayback.is_playing()


## Resolve an autoload by PATH rather than by its global identifier, so this script runs in a
## headless/test context where the autoload may be absent. Mirrors BattleSaveManager._node.
static func _node(path: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(path)
	return null


# --- What the readers ask for ------------------------------------------------

## An authored pacing delay, scaled for the current state: unchanged when disarmed, divided by
## [constant SPEED_MULTIPLIER] and floored at [constant MIN_BEAT] while armed. Every one of
## [BotTurnDriver]'s beats passes through here as its LAST step, so fast-forward overrides the
## driver's own watchability floors (min_attack_dwell / min_move_dwell) rather than being
## clamped back up by them.
static func scale_delay(seconds: float) -> float:
	if not _armed:
		return seconds
	return maxf(MIN_BEAT, seconds / SPEED_MULTIPLIER)


## An authored animation-wait cap, scaled for the current state: unchanged when disarmed, 0.0
## while armed. A cap of 0 makes the driver's gate proceed on its very first check (its
## `_anim_wait_elapsed >= cap` branch), which is the "collapse the animation gate to its
## minimum" half of fast-forward -- without removing the gate, so ordinary play is untouched.
static func scale_anim_cap(seconds: float) -> float:
	return 0.0 if _armed else seconds


# --- Auto-disarm --------------------------------------------------------------

## A turn began. Drops fast-forward the moment a NON-AI player is up, so the player is never
## handed back a board that is still racing. [param player] is duck-typed (`is_ai`) so a test
## can pass a stub and a null player is simply ignored.
##
## Called from every turn-signal subscriber that knows about this latch (the HUD button, the
## camera). It is idempotent, so whichever one the ACTIVE turn system happens to have connected
## first is the one that does the work -- and per the project convention this must ride the
## ACTIVE turn system's `turn_started`, never PlayerManager's, which does not fire on AI turns.
static func note_turn_started(player) -> void:
	if player == null:
		return
	if "is_ai" in player and bool(player.is_ai):
		return
	disarm()


## True when [param player] is an AI whose turn the button should be offered for. Duck-typed and
## null-safe, like [method note_turn_started].
static func is_ai_player(player) -> bool:
	if player == null:
		return false
	return "is_ai" in player and bool(player.is_ai)
