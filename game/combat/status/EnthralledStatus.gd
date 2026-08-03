extends StatusCondition
class_name EnthralledStatus

## The MIND-CONTROL status (Mycothrall's Enthralled): while it is active its unit
## carries the "controlled" rule flag, and when it lapses it WIPES the infestation
## counter that produced it.
##
## Modelled on [StatModifierStatus] / [RegenStatus]: a tiny subclass that carries one
## exported id and overrides one hook, so everything else -- the 1-turn duration, the
## rule flag, the tick that expires it -- stays authored data in `enthralled.tres` and
## rides the ordinary [StatusController] machinery.
##
## WHY THE WIPE EXISTS. Control is deliberately short (one turn of the controlling
## side), and the infestation that earns it is a two-stack run-up. Without this hook a
## host that had been taken over once would come out of it still carrying whatever
## infestation had accumulated, so the SECOND takeover would cost fewer bites than the
## first, and every one after that fewer still -- a unit bitten enough times would
## effectively never be its own again. Clearing the counter as control lapses resets the
## run-up: re-taking a host always costs TWO FRESH BITES.
##
## THIS IS A DELIBERATE EXCEPTION TO THE REFRESH CONVENTION (CONQUEST.md rule 6), and it
## is the second half of one: [InfestEffect] refuses to plant stacks at all while control
## is up, and this wipes what is left when control ends. The convention says a second
## application must never DEEPEN an effect; it says nothing about a counter that has
## already been SPENT, and a spent counter that lingers is what would deepen this one.
##
## The wipe runs from [method on_expire], so it fires however the control ends -- timing
## out on the turn tick, being cleansed, or the whole controller being cleared.

## The counter status cleared when control lapses. Authored (rather than hard-coded)
## so the pairing lives in the .tres next to the effect that plants it; blank disables
## the wipe entirely.
@export var clears_status_id: StringName = &"infested"


## Control has ended. Wipe the leftover infestation counter off the host.
##
## Null-safe and duck-typed at every step: a mock target with no status controller, or a
## controller mid-teardown, simply skips the wipe. Re-entrant by contract --
## [method StatusController.remove_status] is being called from inside that controller's
## own expiry pass, which is why [method StatusController.tick_all] edits its list in
## place instead of rebuilding it from a survivors array.
func on_expire(target, board) -> void:
	if target == null or clears_status_id == &"":
		return
	var controller = _controller_of(target)
	if controller == null or not controller.has_method("remove_status"):
		return
	controller.remove_status(clears_status_id, board)


## The host's [StatusController] through whichever accessor it exposes, or null.
func _controller_of(target):
	if target.has_method("get_status_controller"):
		return target.get_status_controller()
	return null
