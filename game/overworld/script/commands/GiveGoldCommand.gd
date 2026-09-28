class_name GiveGoldCommand
extends StoryCommand

@export var amount: int = 0


func run(ctx: ScriptContext) -> void:
	if amount <= 0:
		return
	ctx.state.add_gold(amount)
	if ctx.has_host_method(&"toast"):
		ctx.host.toast("+%d gold" % amount, "gold")


func describe() -> String:
	return "Give %d gold" % amount
