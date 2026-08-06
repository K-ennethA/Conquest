extends Node
class_name MovesetController

## Per-unit component that tracks move availability: cooldown-remaining and
## uses-left, keyed by [member MoveResource.move_id].
##
## The turn system calls [method tick_cooldowns] once per turn to count cooldowns
## down; the action system calls [method can_use] before offering a move and
## [method on_used] after resolving one. Respects both [member MoveResource.cooldown]
## and [member MoveResource.max_uses] (-1 = unlimited). Deterministic and
## side-effect free apart from the two tracking dictionaries.

## move_id -> remaining cooldown turns (0 = ready).
var _cooldowns: Dictionary = {}
## move_id -> uses already spent this battle.
var _uses_spent: Dictionary = {}

## move_id -> the LENGTH the wait currently running started with.
##
## Almost always [member MoveResource.cooldown], and then this dictionary says nothing at
## all. It exists for a move whose RESOLUTION decides its own wait -- Duskmaw's Voidstep
## charges 1 turn to plant an anchor and 4 to step to one -- so the recharge bar can show
## "3/4" rather than "3/1". Cleared the moment the wait runs out, so a move is always back
## to quoting its authored number when it is ready.
var _cooldown_totals: Dictionary = {}


## True if [param move] can be used right now: not on cooldown and not out of
## charges. A null/invalid move is never usable.
func can_use(move: MoveResource) -> bool:
	if move == null:
		return false
	if remaining(move) > 0:
		return false
	if move.max_uses >= 0 and _spent(move.move_id) >= move.max_uses:
		return false
	return true


## Record that [param move] was used: spend a charge and start its cooldown.
##
## NEVER SHORTENS A WAIT RESOLUTION ALREADY STARTED. A move's effects run BEFORE its
## caller books the use (see [method UnitActionsPanel._execute_move_on_target] and
## [method BotTurnDriver]), so an effect that called [method cooldown_started] for a
## longer wait would otherwise have it stamped straight back down to the authored number.
## The rule is safe in every other case because a move cannot be used while it is on
## cooldown at all ([method can_use]) -- so a non-zero remaining here can only have been
## set by the resolution that just ran.
func on_used(move: MoveResource) -> void:
	if move == null:
		return
	_uses_spent[move.move_id] = _spent(move.move_id) + 1
	var started: int = maxi(move.cooldown, remaining(move))
	if started > 0:
		_cooldowns[move.move_id] = started
		_cooldown_totals[move.move_id] = started


## Start (or replace) [param move]'s cooldown at exactly [param turns], and remember that
## length as what the recharge bar is counting down from.
##
## THE HOOK A RESOLUTION USES TO CHARGE ITS OWN PRICE. Authoring a second cooldown number
## on the move would not do: the choice is made by what the cast actually DID, which only
## the effect knows. Everything downstream is unchanged -- [method remaining] and
## [method total] are the same two readers the HUD already had -- and it is deterministic
## resolution state, so it lands identically on every lockstep peer and rides the
## mid-battle save through [method snapshot_state].
##
## [param turns] of 0 or less clears the wait outright (the move is ready).
func cooldown_started(move: MoveResource, turns: int) -> void:
	if move == null:
		return
	if turns <= 0:
		_cooldowns.erase(move.move_id)
		_cooldown_totals.erase(move.move_id)
		return
	_cooldowns[move.move_id] = turns
	_cooldown_totals[move.move_id] = turns


## Count every active cooldown down by one turn. Call once per turn.
func tick_cooldowns() -> void:
	for move_id in _cooldowns.keys():
		var left: int = _cooldowns[move_id]
		if left > 0:
			left -= 1
			_cooldowns[move_id] = left
		# A finished wait forgets the length it ran for, so the move goes back to quoting
		# its authored cooldown the instant it is ready again.
		if left <= 0:
			_cooldown_totals.erase(move_id)


## Cooldown turns still remaining on [param move] (0 = ready).
func remaining(move: MoveResource) -> int:
	if move == null:
		return 0
	return int(_cooldowns.get(move.move_id, 0))


## The length the wait currently running on [param move] started from -- what a "2/4"
## recharge readout divides by.
##
## The move's authored [member MoveResource.cooldown] unless a resolution charged a
## different price (see [method cooldown_started]); a READY move always reports the
## authored number, so nothing lingers past the wait it belonged to.
func total(move: MoveResource) -> int:
	if move == null:
		return 0
	var authored: int = int(move.cooldown)
	if remaining(move) <= 0:
		return authored
	return maxi(authored, int(_cooldown_totals.get(move.move_id, 0)))


## Charges left before [param move] hits [member MoveResource.max_uses].
## Returns -1 for unlimited moves.
func uses_left(move: MoveResource) -> int:
	if move == null or move.max_uses < 0:
		return -1
	return maxi(0, move.max_uses - _spent(move.move_id))


## Forget all cooldown/use tracking (e.g. at the start of a new battle).
func reset() -> void:
	_cooldowns.clear()
	_uses_spent.clear()
	_cooldown_totals.clear()


## A JSON-safe copy of this controller's whole state, for the mid-battle save
## ([BattleSnapshot]). Keys are stringified move_ids so the dictionary survives a
## JSON round trip (a [StringName] key would come back as a String anyway).
func snapshot_state() -> Dictionary:
	var cooldowns: Dictionary = {}
	for move_id in _cooldowns:
		var left: int = int(_cooldowns[move_id])
		if left > 0:
			cooldowns[String(move_id)] = left
	var spent: Dictionary = {}
	for move_id in _uses_spent:
		var n: int = int(_uses_spent[move_id])
		if n > 0:
			spent[String(move_id)] = n
	# The DYNAMIC wait lengths ride along, so a battle resumed (or a Siege respawn that
	# keeps its cooldowns) still shows "3/4" on a move whose resolution charged 4 rather
	# than silently reverting the bar to the authored number. Only entries for waits still
	# running are emitted, mirroring the cooldown map above.
	var totals: Dictionary = {}
	for move_id in _cooldown_totals:
		if int(_cooldowns.get(move_id, 0)) > 0:
			totals[String(move_id)] = int(_cooldown_totals[move_id])
	return { "cooldowns": cooldowns, "uses_spent": spent, "cooldown_totals": totals }


## The exact inverse of [method snapshot_state]: replaces the tracking dictionaries with
## [param state]. Keys are re-interned as [StringName]s, which is what [method remaining] /
## [method _spent] look up by. Missing or malformed sections simply clear that half.
func restore_state(state: Dictionary) -> void:
	_cooldowns.clear()
	_uses_spent.clear()
	_cooldown_totals.clear()
	var totals: Variant = state.get("cooldown_totals", {})
	if totals is Dictionary:
		for key in totals as Dictionary:
			_cooldown_totals[StringName(String(key))] = int((totals as Dictionary)[key])
	var cooldowns: Variant = state.get("cooldowns", {})
	if cooldowns is Dictionary:
		for key in cooldowns as Dictionary:
			_cooldowns[StringName(String(key))] = int((cooldowns as Dictionary)[key])
	var spent: Variant = state.get("uses_spent", {})
	if spent is Dictionary:
		for key in spent as Dictionary:
			_uses_spent[StringName(String(key))] = int((spent as Dictionary)[key])


func _spent(move_id: StringName) -> int:
	return int(_uses_spent.get(move_id, 0))
