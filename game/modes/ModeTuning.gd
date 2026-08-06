extends RefCounted
class_name ModeTuning

## THE ONE SURFACE the engine reads PER-MODE tuning through.
##
## Every number a game MODE turns on lives on that mode's own ruleset RESOURCE --
## [SiegeRuleset] for Siege, [ArenaRuleset] for the Arena -- so retuning a mode is a `.tres`
## edit rather than a code change (CONQUEST.md rule 11). This class is how the ENGINE asks
## for one of those numbers WITHOUT knowing which mode is running, or that any mode is
## running at all:
##
##   [code]var expiry: int = ModeTuning.get_int(&"trap_expiry_rounds", 0)[/code]
##
## THREE PROPERTIES, all deliberate.
##
## 1. NEUTRAL BY DEFAULT. With no mode armed there is no ruleset, every knob resolves to the
##    caller's own neutral fallback, and every engine path behaves exactly as it did before
##    this file existed. A plain skirmish is therefore not "Siege with the knobs at zero" --
##    it never consults a ruleset at all.
##
## 2. DECLARED, NOT REQUIRED. A knob is read off the active ruleset only when that resource
##    actually DECLARES a property of that name. A mode that says nothing about trap expiry
##    gets the neutral answer for it while still supplying its own movement knobs, and a
##    ruleset authored before a knob existed keeps working. That is what makes this ONE
##    accessor rather than one accessor per mode: adding a knob is an `@export` on a ruleset
##    plus a `get_int` at the reading site.
##
## 3. REGISTERED BY THE MODE'S OWN CONTROLLER. [SiegeController] registers itself when it
##    ARMS and unregisters when it disarms or leaves the tree, so "which mode is active" has
##    exactly one answer and it is the same latch the mode already keeps. A future mode gets
##    the whole surface by doing the same two calls; nothing here knows what Siege is.
##
## DETERMINISM. Nothing here rolls, reads the wall clock, or branches on which peer is
## running: it is a property lookup on an authored resource plus the mode's own round
## counter, which is itself derived from the ACTIVE turn system's signals (CONQUEST.md
## rule 2). Two peers stepping the same command stream read the same numbers.

## Id of the mode-granted movement status. One id for every mode and both unit kinds, which
## is what makes a re-grant a REFRESH rather than a second modifier (CONQUEST.md rule 6).
const MARCH_STATUS_ID := &"mode_march"

## Authored resource backing [method march_status]. A code factory mirrors it (see that
## method) so the grant still works in a build where the .tres is missing.
const MARCH_STATUS_PATH := "res://game/combat/status/mode_march.tres"

## Id of the buff a felled neutral camp pays, and the resource it is built from. The SAME
## status the Arena's camps already hand their killer ([ArenaRoundBuilder.CAMP_REWARD_PATH]),
## reused rather than re-authored, so "what a camp kill is worth" has one definition. One id
## for every mode, which is what makes a second camp kill a REFRESH (CONQUEST.md rule 6).
const CAMP_BUFF_STATUS_ID := &"empowered"
const CAMP_BUFF_STATUS_PATH := "res://game/combat/status/empowered.tres"

## Fallback camp-buff shape, mirroring `empowered.tres` for a build where the resource failed
## to load. Kept beside the path it mirrors so the two cannot silently drift.
const CAMP_BUFF_STAT := "attack"
const CAMP_BUFF_AMOUNT := 8

## The answer every knob gives when no mode is armed. Documented here rather than scattered
## across call sites so "what a plain skirmish does" is readable in one place; each caller
## still passes its own fallback, so this table is a reference, not a hidden default.
const NEUTRAL_INTS := {
	&"hero_move_bonus": 0,
	&"creep_move_bonus": 0,
	&"trap_expiry_rounds": 0,
	&"camp_buff_turns": 0,
}

## Weak handle on the active mode controller. WEAK because the controller is a Node that is
## freed between battles and a static strong reference would keep a dead battle's runtime
## alive for the whole app run -- the same reason a [StatusCondition] holds its applier
## weakly.
static var _provider_ref: WeakRef = null


# --- Registration -------------------------------------------------------------

## Declare [param mode_controller] the ACTIVE mode. Called by a mode controller when it arms.
##
## The provider is duck-typed and every hook is optional:
##   [code]ruleset()[/code]        -> the mode's tuning [Resource]
##   [code]rounds_elapsed()[/code] -> the mode's own round counter
##   [code]is_armed()[/code]       -> false silences the whole surface without unregistering
static func register(mode_controller) -> void:
	if mode_controller == null or not is_instance_valid(mode_controller):
		return
	_provider_ref = weakref(mode_controller)


## Stand [param mode_controller] down. A no-op when somebody else has since registered, so a
## disarming controller can never silence the mode that replaced it.
static func unregister(mode_controller) -> void:
	if mode_controller == null:
		return
	if provider() == mode_controller:
		_provider_ref = null


## Drop the registration outright. The seam a test resets between suites -- a static that
## survives a suite is global state (tests/README rule 3).
static func clear() -> void:
	_provider_ref = null


## The active mode controller, or null. Resolves through the weak handle, so a freed
## controller reads as "no mode" rather than as a dangling object.
static func provider():
	if _provider_ref == null:
		return null
	var p = _provider_ref.get_ref()
	if p == null or not is_instance_valid(p):
		return null
	if p.has_method("is_armed") and not bool(p.is_armed()):
		return null
	return p


## True while a mode is armed AND has a ruleset to read.
static func has_mode() -> bool:
	return active_ruleset() != null


## The active mode's tuning resource, or null when no mode is armed.
static func active_ruleset() -> Resource:
	var p = provider()
	if p == null or not p.has_method("ruleset"):
		return null
	var rs = p.ruleset()
	return rs if rs is Resource else null


# --- The generic knob read -----------------------------------------------------

## The active mode's integer value for [param key], or [param neutral].
##
## Returns [param neutral] whenever the answer is not an authored number: no mode armed, no
## ruleset, or a ruleset that does not DECLARE a property called [param key]. That last case
## is the one that makes this generic -- the engine names a knob, and any mode that wants to
## turn it on declares it.
static func get_int(key: StringName, neutral: int = 0) -> int:
	var rs: Resource = active_ruleset()
	if rs == null:
		return neutral
	if not (String(key) in rs):
		return neutral
	var value = rs.get(String(key))
	if value == null:
		return neutral
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return neutral


## [method get_int]'s boolean twin, for a knob a mode simply switches on.
static func get_bool(key: StringName, neutral: bool = false) -> bool:
	var rs: Resource = active_ruleset()
	if rs == null:
		return neutral
	if not (String(key) in rs):
		return neutral
	var value = rs.get(String(key))
	if value == null:
		return neutral
	return bool(value)


# --- The round clock ------------------------------------------------------------

## The ROUND the battle is on, as the active mode counts it (0 outside a battle).
##
## The mode's own counter first: it is EDGE-DETECTED off the active turn system's signals, so
## it is the number the mode's other schedules (waves, respawns) already run on and nothing
## placed this round can disagree with them. With no mode armed it falls back to deriving the
## round from the active turn system directly, the same arithmetic
## [method SiegeController.system_round] uses -- Speed First keeps a real `round_number`,
## Traditional's `current_turn` is a player-switch counter.
static func current_round() -> int:
	var p = provider()
	if p != null and p.has_method("rounds_elapsed"):
		var r: int = int(p.rounds_elapsed())
		if r > 0:
			return r
	return _turn_system_round()


static func _turn_system_round() -> int:
	if typeof(TurnSystemManager) != TYPE_OBJECT or TurnSystemManager == null:
		return 0
	if not TurnSystemManager.has_method("get_active_turn_system"):
		return 0
	var ts = TurnSystemManager.get_active_turn_system()
	if ts == null or not is_instance_valid(ts):
		return 0
	if "round_number" in ts:
		return int(ts.round_number)
	var turn: int = int(ts.get("current_turn")) if "current_turn" in ts else 0
	if turn <= 0:
		return 0
	var players: int = 1
	if "registered_players" in ts:
		players = maxi(1, (ts.registered_players as Array).size())
	return ((turn - 1) / players) + 1


# --- Named knobs ----------------------------------------------------------------
#
# Thin readers over get_int, so a call site says WHAT it wants rather than spelling a key.
# Each one is the neutral value in the no-mode case, which is the whole "a battle with no
# mode ruleset gets neutral defaults" contract.

## Extra movement squad HEROES are granted by the active mode (0 = none).
static func hero_move_bonus() -> int:
	return get_int(&"hero_move_bonus", int(NEUTRAL_INTS[&"hero_move_bonus"]))


## Extra movement mode-spawned CREEPS are granted by the active mode (0 = none).
static func creep_move_bonus() -> int:
	return get_int(&"creep_move_bonus", int(NEUTRAL_INTS[&"creep_move_bonus"]))


## Full ROUNDS a runtime-placed tile effect (a trap a move planted) survives before it
## expires. 0 -- the neutral answer, and the answer everywhere outside a mode that declares
## otherwise -- means a placed trap NEVER expires, exactly as it always did.
static func trap_expiry_rounds() -> int:
	return maxi(0, get_int(&"trap_expiry_rounds", int(NEUTRAL_INTS[&"trap_expiry_rounds"])))


## Full TURNS the buff a felled neutral camp pays lasts under the active mode.
##
## 0 -- the neutral answer, and the answer everywhere outside a mode that declares otherwise
## -- means NO TIMER, which is the PERMANENT team bounty [BaseAssaultRuntime] has always paid.
## A mode that declares the knob converts its own camp reward to a timed status of this many
## turns without any other mode's behaviour changing.
static func camp_buff_turns() -> int:
	return maxi(0, get_int(&"camp_buff_turns", int(NEUTRAL_INTS[&"camp_buff_turns"])))


# --- The movement grant -----------------------------------------------------------

## A fresh, permanent, REFRESH-safe movement status worth [param amount].
##
## Built by DUPLICATING the authored resource (never mutating it -- CONQUEST.md rule 7) and
## stamping the mode's amount onto the copy, because the number is ruleset data while the
## vehicle is content. Falls back to a code factory that mirrors the .tres, so the mode still
## paces correctly in a build where the resource failed to load.
##
## duration_turns -1 makes it PERMANENT: the mode granted it, so only the mode takes it away.
static func march_status(amount: int) -> StatusCondition:
	var status: StatModifierStatus = null
	if ResourceLoader.exists(MARCH_STATUS_PATH):
		var res = load(MARCH_STATUS_PATH)
		if res is StatModifierStatus:
			status = (res as StatModifierStatus).duplicate() as StatModifierStatus
	if status == null:
		status = StatModifierStatus.new()
		status.id = MARCH_STATUS_ID
		status.display_name = "March"
		status.duration_turns = -1
		status.stacking = StatusCondition.Stacking.REFRESH
		status.stat_name = "movement"
	status.amount = amount
	return status


## Grant [param unit] the mode's movement bonus, through the ORDINARY status machinery.
##
## WHY A STATUS AND NOT A RAW MODIFIER. [StatModifierStatus] holds one live stat modifier for
## exactly as long as it is active and takes it back on expiry, and
## [method StatusController.add_status] only runs [method StatusCondition.on_apply] for a
## NEWLY-added instance -- so a second grant REFRESHES the one instance instead of stacking a
## second +2 (CONQUEST.md rule 6). Re-granting every round is therefore free, which is what
## lets the mode simply re-sweep its units rather than track who it has already boosted.
##
## Because the modifier moves [method Unit.get_stat]("movement"), every reader picks it up for
## free: [MovementResolver] folds (current - base) into its flood budget so the reachable set
## really grows, the AI's reach estimate grows with it, and the card's MOV chip shows the
## boosted value through the shared effective-stat helpers.
##
## Returns true when a status was handed to the unit. Null-safe end to end: an amount of 0 is
## not a buff and is never granted, and a unit with no [StatusController] (a mock, a
## non-character prop) simply takes nothing.
static func grant_move_bonus(unit, amount: int) -> bool:
	if amount == 0:
		return false
	if unit == null or not is_instance_valid(unit):
		return false
	if not unit.has_method("get_status_controller"):
		return false
	var controller = unit.get_status_controller()
	if controller == null or not is_instance_valid(controller):
		return false
	if not controller.has_method("add_status"):
		return false
	controller.add_status(march_status(amount))
	return true


# --- The camp buff ----------------------------------------------------------------

## A fresh copy of the camp-kill buff, timed to [param turns].
##
## Built exactly the way [method march_status] is: DUPLICATE the authored resource (never
## mutate it -- CONQUEST.md rule 7) and stamp the mode's number onto the copy, because the
## DURATION is ruleset data while the buff itself is content. Forced to
## [constant StatusCondition.Stacking.REFRESH] so a second camp kill resets the timer on the
## one instance and can never deepen the buff (CONQUEST.md rule 6) -- the authored resource
## already says REFRESH; this is the belt that keeps it true if the .tres is ever retuned.
##
## Returns null for a non-positive [param turns]: "no timer" is the permanent-bounty case,
## which is not this vehicle at all.
static func camp_buff_status(turns: int) -> StatusCondition:
	if turns <= 0:
		return null
	var status: StatusCondition = null
	if ResourceLoader.exists(CAMP_BUFF_STATUS_PATH):
		var res = load(CAMP_BUFF_STATUS_PATH)
		if res is StatusCondition:
			status = (res as StatusCondition).duplicate(true) as StatusCondition
	if status == null:
		status = StatusCondition.new()
		status.id = CAMP_BUFF_STATUS_ID
		status.display_name = "Empowered"
		var bump := StatModifierEffect.new()
		bump.stat_name = CAMP_BUFF_STAT
		bump.amount = CAMP_BUFF_AMOUNT
		bump.duration = 1
		status.tick_effects = [bump] as Array[MoveEffect]
	status.duration_turns = turns
	status.stacking = StatusCondition.Stacking.REFRESH
	return status


## Hand [param unit] the camp-kill buff for [param turns] turns, through the ORDINARY status
## machinery -- so it expires on the unit's own turn clock like every other timed buff, and a
## re-grant REFRESHES rather than stacks.
##
## Returns true when a status was handed over. Null-safe end to end: 0 turns is not a timed
## buff and is never granted, and a unit with no [StatusController] simply takes nothing.
static func grant_camp_buff(unit, turns: int) -> bool:
	var status: StatusCondition = camp_buff_status(turns)
	if status == null:
		return false
	if unit == null or not is_instance_valid(unit):
		return false
	if not unit.has_method("get_status_controller"):
		return false
	var controller = unit.get_status_controller()
	if controller == null or not is_instance_valid(controller):
		return false
	if not controller.has_method("add_status"):
		return false
	controller.add_status(status)
	return true
