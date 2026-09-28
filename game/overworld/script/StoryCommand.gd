class_name StoryCommand
extends Resource

## ONE STEP OF A STORY SCRIPT (docs/design/OVERWORLD.md §4.4) -- the MoveEffect philosophy
## applied to interactions: compose a list of these in the Inspector (or a builder script),
## add behaviour with one small subclass.
##
## [method run] may await (dialogue, a choice, a walk, a whole battle). Commands reach the world
## only through the [ScriptContext] (its host / session), never through a global, so the whole
## interaction layer runs headless against a fake host.
##
## Subclasses override:
##   run(ctx)          -- do the thing (may await)
##   describe()        -- the Inspector row text, e.g. "Say: Elder (3 lines)"
##   validate(issues)  -- content checks (conditions parse, ids exist); appends strings
##   child_lists()     -- nested command lists (If / Choice branches), so validators recurse


func run(_ctx: ScriptContext) -> void:
	pass


func describe() -> String:
	return "Command"


func validate(_issues: Array[String]) -> void:
	pass


func child_lists() -> Array:
	return []


func _to_string() -> String:
	return describe()


## Validate a whole command list recursively (content tests + the area validator).
static func validate_list(commands: Array, issues: Array[String], where: String = "") -> void:
	for c in commands:
		var cmd := c as StoryCommand
		if cmd == null:
			if c != null:
				issues.append("%s: a non-command entry (%s) in a script" % [where, str(c)])
			continue
		var own: Array[String] = []
		cmd.validate(own)
		for msg in own:
			issues.append("%s: %s -- %s" % [where, cmd.describe(), msg])
		for sub in cmd.child_lists():
			if sub is Array:
				validate_list(sub, issues, where)


## Check a condition string, appending an issue when it does not parse/run.
static func check_condition(condition: String, issues: Array[String], label: String = "condition") -> void:
	var r: Dictionary = ConditionContext.check(condition)
	if not bool(r.get("valid", false)):
		issues.append("%s '%s' is invalid (%s)" % [label, condition, String(r.get("error", ""))])


## Array[Resource] helper for builders (a plain Array literal cannot be assigned to a typed one).
static func list(items: Array) -> Array[Resource]:
	var out: Array[Resource] = []
	for i in items:
		if i is Resource:
			out.append(i)
	return out
