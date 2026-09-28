class_name IfCommand
extends StoryCommand

## Branch on a condition ([ConditionContext]; outcome() reads the last battle's result).

@export var condition: String = ""
@export var then_commands: Array[Resource] = []
@export var else_commands: Array[Resource] = []


static func make(p_condition: String, p_then: Array, p_else: Array = []) -> IfCommand:
	var c := IfCommand.new()
	c.condition = p_condition
	c.then_commands = StoryCommand.list(p_then)
	c.else_commands = StoryCommand.list(p_else)
	return c


func run(ctx: ScriptContext) -> void:
	if ctx.condition(condition):
		await StoryScriptRunner.run_list(then_commands, ctx)
	else:
		await StoryScriptRunner.run_list(else_commands, ctx)


func child_lists() -> Array:
	return [then_commands, else_commands]


func describe() -> String:
	return "If %s (%d / %d)" % [condition, then_commands.size(), else_commands.size()]


func validate(issues: Array[String]) -> void:
	StoryCommand.check_condition(condition, issues)
