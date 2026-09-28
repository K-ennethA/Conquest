class_name HealPartyCommand
extends StoryCommand

## Full heal + clear wounds (Wayshrines, healer NPCs).


func run(ctx: ScriptContext) -> void:
	ctx.state.heal_party()


func describe() -> String:
	return "Heal party"
