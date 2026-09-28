class_name SaveGameCommand
extends StoryCommand

## Write the journey to its slot (Wayshrines).


func run(ctx: ScriptContext) -> void:
	if ctx.has_session_method(&"save_game"):
		ctx.session.save_game()


func describe() -> String:
	return "Save game"
