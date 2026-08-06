extends StatusCondition
class_name StatModifierStatus

## A [StatusCondition] that holds a temporary STAT MODIFIER on its unit for exactly as
## long as the condition is active, then takes it back when the condition expires.
##
## It exists because a plain [StatModifierEffect] (fire-once, never revoked) STACKS on
## every re-application -- stepping onto a rubble field twice would pile up -2, -4, -6
## movement. Routing the modifier through a status instead makes re-application obey the
## project's REFRESH rule: [method StatusController.add_status] only calls [method on_apply]
## for a NEWLY-added instance; a REFRESH of an already-active copy of the same id just
## resets its timer and never re-enters here, so the modifier lands exactly once and the
## timer is what gets extended. This is the same "refresh, never compound" contract the
## damage-reduction statuses follow.
##
## Because the live modifier lowers [method Unit.get_stat] ("movement"), it is picked up
## everywhere the game reads the stat -- the HUD, the AI's reach estimates, and
## [MovementResolver], whose flood budget IS that stat, so the slow visibly shrinks the
## reachable set the same turn with no arithmetic of its own.

## Which stat to shift while active (matches [member StatModifierEffect.stat_name]).
@export var stat_name: String = "movement"
## Signed amount applied to that stat; negative debuffs, positive buffs.
@export var amount: int = -2

## Id of the live modifier this instance owns on its unit (-1 = none applied yet). A
## runtime var, so [method Resource.duplicate] resets it to -1 on every fresh copy.
var _modifier_id: int = -1


## Add the modifier when the condition first lands on the unit. Duration -1 (permanent
## from UnitStats' view) hands lifetime control entirely to this status: nothing else
## expires it, and [method on_expire] is the sole point that removes it. Null-safe for
## a mock target that cannot take a modifier.
func on_apply(target, _board) -> void:
	if target == null or not target.has_method("add_stat_modifier"):
		return
	_modifier_id = int(target.add_stat_modifier(stat_name, amount, -1))


## Revoke the modifier when the condition expires or is cleared, so the stat returns to
## normal. Guards against double-removal and a target that never received one.
func on_expire(target, _board) -> void:
	if _modifier_id < 0:
		return
	if target != null and target.has_method("remove_stat_modifier"):
		target.remove_stat_modifier(_modifier_id)
	_modifier_id = -1
