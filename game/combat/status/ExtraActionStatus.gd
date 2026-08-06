extends StatModifierStatus
class_name ExtraActionStatus

## A [StatModifierStatus] that ALSO hands its unit one more action for the turn, then
## takes it back when it expires (Monster's Shadow Dash grants "move again, but slower").
##
## Built on top of the stat-modifier status rather than beside it because the two halves
## are one design: the extra action is only balanced while it is PAID FOR by the debuff,
## and expressing them as a single status guarantees they arrive and leave together --
## there is no state in which a unit holds the free action without the penalty.
##
## THE ACTION HALF is [member Unit.arena_extra_actions], the existing "act twice" budget
## the Arena's [ExtraActionEffect] augment already drives. [method Unit.mark_action_completed]
## consumes it: while the budget lasts the unit does NOT latch "done" on acting, and its
## move is refreshed, so it can be commanded again. Reusing that budget means the turn
## systems, the HUD and the AI driver all already understand this grant and needed no
## changes.
##
## IT IS A FULL ACTION, NOT A MOVEMENT-ONLY ONE, and that is a deliberate concession.
## [method Unit.can_move] requires `not has_acted_this_turn`, so there is no cheap way to
## say "you may walk again but not strike again" without reworking the action economy --
## which is core turn-system surface, not character content. The movement debuff carried
## by the same status is what keeps the grant honest: the second action comes with a
## shortened leash. If a movement-only grant is ever wanted, it belongs in [Unit] as its
## own flag, not bolted on here.
##
## THE ORDER THAT MAKES IT WORK: move effects resolve inside
## [method Unit.perform_move], and the caller marks the action complete AFTERWARDS
## (UnitActionsPanel / CommandApplier / BotTurnDriver all do). So the budget is already
## raised by the time the casting action is counted, and that action spends the grant
## instead of ending the turn.
##
## REFRESH, NEVER STACK (CONQUEST.md rule 6). [method StatusController.add_status] only
## calls [method on_apply] for a NEWLY-added instance, so re-applying while it is live
## resets the timer and grants NOTHING further -- two casts can never bank two extra
## actions or double the slow. [method on_expire] therefore always returns exactly what
## [method on_apply] took, once.
##
## EXPIRY IS THE UNIT'S NEXT TURN START, from the ordinary status tick, which is also
## when [method Unit.reset_turn_actions] has already given the unit its normal action
## back -- so the budget is handed back at the one moment nothing is mid-spend.

## Additional actions granted while this status is live (1 = one more action this turn).
@export var extra_actions: int = 1


## Landed: take the stat modifier (the debuff half, from [StatModifierStatus]) and raise
## the action budget. Duck-typed and null-safe at every step, so a mock target that
## carries neither simply receives nothing.
func on_apply(target, board) -> void:
	super.on_apply(target, board)
	if target == null or extra_actions == 0:
		return
	if "arena_extra_actions" in target:
		target.arena_extra_actions = int(target.arena_extra_actions) + extra_actions
	# Hand the movement back immediately as well, so a unit that had already walked this
	# turn can use the grant to reposition rather than only to strike again.
	if target.has_method("grant_extra_move"):
		target.grant_extra_move()


## Expired or cleared: give the modifier back and lower the budget by exactly what this
## instance raised it by. Floored at 0 so a unit that also carries an Arena grant can
## never be driven negative by an out-of-order teardown.
func on_expire(target, board) -> void:
	super.on_expire(target, board)
	if target == null or extra_actions == 0:
		return
	if "arena_extra_actions" in target:
		target.arena_extra_actions = maxi(0, int(target.arena_extra_actions) - extra_actions)
