extends WinCondition
class_name CaptureBase

## MET when [member faction] has CAPTURED the enemy base cell; FAILED when the enemy has
## captured ours.
##
## The SIEGE objective. A Siege map authors two things ([MapResource] `lanes` and
## `base_cells`, added by the map layer): one capture cell per side, and the lanes creeps
## march down. This condition scores the capture; [SiegeController] owns the state machine
## that produces it.
##
## THE CAPTURE RULE, in full, because the whole mode hangs off it:
##
##   1. A HERO of side A ends its turn standing on side B's `base_cells` entry
##      -> the base begins CAPTURING (side A, that unit, that cell).
##   2. If that SAME unit is still alive and still on that SAME cell when its NEXT turn
##      starts, the base is captured and side A wins.
##   3. Anything else -- the unit dies, is knocked off, walks off, is swapped out -- cancels
##      the capture outright. There is no partial progress and no second timer: the enemy
##      gets exactly one turn to answer.
##
## WHAT COUNTS AS A HERO. A member of the side's picked SQUAD, and nothing else:
##   * a CREEP never captures (rule 4 of the mode). Creeps are stamped at spawn by
##     [SiegeController] and recognised here through [method is_creep] -- the mark is on the
##     unit itself rather than inferred from its spawn kind, so a creep stays a creep no
##     matter what later moves it;
##   * a NEUTRAL never captures. Neutral camps are third parties (see [DestroyBase]'s note);
##     letting one wander onto a base and hand a side the match would be absurd;
##   * an UNOWNED unit never captures -- a unit the board holds before ownership is assigned
##     has no side to win for.
## Everything else on a side is that side's squad, which is why the test is written as three
## exclusions rather than a positive "was this in the squad pick" flag: a squad unit that
## respawns is a NEW node (see [SiegeController]'s respawn) and would fail any such flag,
## while it obviously must still be able to capture.
##
## WHERE THE VERDICT COMES FROM. The capture is a TURN-BOUNDARY event, not a board fact, so
## it cannot be re-derived from a snapshot of live units the way [DestroyBase] re-derives
## "the base is rubble". [SiegeController] latches it and this condition reads that latch --
## preferring an explicit key in the scored [param state] (which is how every test drives it)
## and falling back to the live controller node. With neither, it reports ONGOING, so a
## Siege objective on a non-Siege board is inert rather than wrong.

## State key carrying the id of the side that has COMPLETED a capture (-1 / absent = none).
const STATE_CAPTURED_BY: StringName = &"siege_captured_by"
## State key carrying the id of the side currently mid-capture (-1 / absent = none).
const STATE_CAPTURING: StringName = &"siege_capturing"

## Metadata key stamped on every creep [SiegeController] spawns. Lives here, on the rule that
## cares, so the objective can be scored without the runtime being loaded.
const CREEP_META: StringName = &"siege_creep"

## Node name [SiegeController] installs itself under in the scene-tree root; the live
## fallback resolves the latch through it WITHOUT a class reference (that would be a cycle:
## the controller compiles this condition's rules).
const CONTROLLER_NODE: String = "SiegeController"

## The friendly faction this objective is scored for.
@export var faction: int = 0


func evaluate(state: Dictionary) -> int:
	var owner: int = captured_owner(state)
	if owner < 0:
		return Status.ONGOING
	if owner == faction:
		return Status.MET
	# The enemy took OUR base. A FAILED win condition IS a defeat (see GameModeRules.evaluate),
	# so Siege needs no separate lose condition -- exactly as DestroyBase does it.
	return Status.FAILED


func describe() -> String:
	return "Capture the enemy base"


func describe_progress(state: Dictionary) -> String:
	var owner: int = captured_owner(state)
	if owner == faction:
		return "Enemy base captured!"
	if owner >= 0:
		return "Your base has fallen"

	var capturing: int = capturing_owner(state)
	if capturing == faction:
		return "Capturing - survive 1 turn!"
	if capturing >= 0:
		return "Enemy is capturing your base!"
	return describe()


# --- The latch ---------------------------------------------------------------

## Side that has COMPLETED a capture, or -1. Reads [param state] first (tests, and any caller
## that assembles its own state), then the live controller.
static func captured_owner(state: Dictionary) -> int:
	if state.has(STATE_CAPTURED_BY):
		return int(state[STATE_CAPTURED_BY])
	var ctrl = _live_controller()
	if ctrl != null and ctrl.has_method("captured_by"):
		return int(ctrl.captured_by())
	return -1


## Side currently mid-capture (its unit is standing on the enemy base, awaiting its next
## turn), or -1. Same two sources, same order.
static func capturing_owner(state: Dictionary) -> int:
	if state.has(STATE_CAPTURING):
		return int(state[STATE_CAPTURING])
	var ctrl = _live_controller()
	if ctrl != null and ctrl.has_method("capturing_by"):
		return int(ctrl.capturing_by())
	return -1


static func _live_controller():
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var root := (loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null(CONTROLLER_NODE)


# --- Who may capture ----------------------------------------------------------

## Stamp [param unit] as a CREEP -- it may fight and it may stand on a base cell, but it can
## never capture one. Idempotent; silently skips anything that cannot hold metadata.
static func mark_creep(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if not unit.has_method("set_meta"):
		return
	unit.set_meta(CREEP_META, true)


## True when [param unit] carries the creep mark.
static func is_creep(unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if not unit.has_method("has_meta"):
		return false
	return unit.has_meta(CREEP_META) and bool(unit.get_meta(CREEP_META))


## True when [param unit] is a HERO of [param side]: alive, owned by that side, not a creep
## and not a neutral. This is the ONLY predicate that gates a capture.
static func is_capturing_hero(unit, side: int) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if not _is_alive(unit):
		return false
	var team: int = _team_of(unit)
	if team < 0 or team != side:
		return false
	if is_creep(unit):
		return false
	if is_neutral(unit):
		return false
	return true


## True when [param unit] belongs to the NEUTRAL faction. Same duck-typed shape
## [DestroyBase._is_neutral] uses: the owning [Player]'s flag on a live unit, a bare
## `is_neutral` property on a mock.
static func is_neutral(unit) -> bool:
	if unit == null:
		return false
	var direct = unit.get("is_neutral")
	if direct != null:
		return bool(direct)
	if unit.has_method("get_owner_player"):
		var owner_player = unit.get_owner_player()
		if owner_player != null:
			var flag = owner_player.get("is_neutral")
			if flag != null:
				return bool(flag)
	return false
