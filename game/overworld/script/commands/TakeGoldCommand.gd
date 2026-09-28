class_name TakeGoldCommand
extends StoryCommand

## Spend gold. When short nothing is taken, ctx.vars["paid"] is false and (by default) the script
## stops -- a toll you cannot pay turns you back.

@export var amount: int = 0
@export var stop_if_short: bool = true


func run(ctx: ScriptContext) -> void:
	var paid: bool = ctx.state.take_gold(amount)
	ctx.vars["paid"] = paid
	if not paid and stop_if_short:
		ctx.stop("not_enough_gold")


func describe() -> String:
	return "Take %d gold" % amount
