extends StatModifierStatus
class_name CantoStatus

## A [StatModifierStatus] that ALSO grants its unit CANTO -- "you have acted, but you may
## still take ONE movement" (Duskmaw's Shadow Dash: comes out the far side still moving,
## though slower).
##
## Built on top of the stat-modifier status rather than beside it because the two halves
## are one design: the free reposition is only balanced while it is PAID FOR by the
## movement debuff, and expressing them as a single status guarantees they arrive and
## leave together -- there is no state in which a unit holds the extra step without the
## shortened leash.
##
## MOVEMENT ONLY, AND THAT IS THE POINT. The previous build used the Arena's
## [member Unit.arena_extra_actions] budget, because "you may walk again but not strike
## again" was not expressible. It now is: [method Unit.grant_canto] arms a flag BOTH turn
## systems ask about, [method Unit.can_act] stays false (no moves, no attack, no second
## dash) and [method Unit.can_move] returns true exactly once. The Arena budget is
## untouched and still means what it always meant -- a full extra action.
##
## THE ORDER THAT MAKES IT WORK, and why the grant is deferred. Move effects resolve
## INSIDE [method Unit.perform_move] and the caller marks the action complete AFTERWARDS
## (UnitActionsPanel / CommandApplier / BotTurnDriver all do). A canto that armed the
## instant this status landed would therefore be wiped by its own casting action, so
## [method Unit.grant_canto] only ARMS it and [method Unit.mark_action_completed] promotes
## it. The mirror of that rule is what closes the turn: any LATER completed action clears
## an armed canto, so a plain Wait (and the networked WAIT_UNIT command) ends a canto turn
## with no special case anywhere in the command layer.
##
## REFRESH, NEVER STACK (CONQUEST.md rule 6). [method StatusController.add_status] only
## calls [method on_apply] for a NEWLY-added instance, so re-applying while it is live
## resets the timer and grants NOTHING further -- two dashes in one turn can never bank
## two movements or double the slow. Canto is a boolean rather than a counter, which makes
## that structurally true rather than merely arithmetically true.
##
## EXPIRY IS THE UNIT'S NEXT TURN START, from the ordinary status tick, which hands the
## movement debuff back. The canto flag itself is turn-scoped state on the unit and is
## cleared by [method Unit.reset_turn_actions], so it can never leak into a later turn even
## if the status is dispelled early.


## Landed: take the stat modifier (the debuff half, from [StatModifierStatus]) and arm the
## canto movement. Duck-typed and null-safe, so a mock target that carries neither simply
## receives nothing.
func on_apply(target, board) -> void:
	super.on_apply(target, board)
	if target == null:
		return
	if target.has_method("grant_canto"):
		target.grant_canto()


## Expired or cleared: give the movement modifier back. The canto flag is deliberately NOT
## revoked here -- it belongs to the turn, not to the status, and by the time this runs
## (the unit's next turn start) [method Unit.reset_turn_actions] has already cleared it.
func on_expire(target, board) -> void:
	super.on_expire(target, board)
