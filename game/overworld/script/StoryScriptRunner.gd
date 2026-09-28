class_name StoryScriptRunner
extends RefCounted

## Walks a [StoryCommand] list (pure RefCounted, like [StorySequencer]) and holds the
## "a script is running" LOCK the overworld reads to block walking, menus and new interactions.
##
## [method run] is a coroutine: it awaits each command in turn (dialogue, a choice, a battle
## round trip) and releases the lock when the list ends OR the context is stopped (a warp, a
## whiteout, a command reporting an error). One runner runs one script at a time; a second
## [method run] while busy is refused (returns false immediately) rather than interleaved.
##
## The runner never touches the world itself -- commands go through [member ScriptContext.host]
## and [member ScriptContext.session] -- so tests drive it with a fake host (see
## tests/unit/test_story_script_runner.gd).

signal started()
signal finished(stopped: bool, reason: String)

var _running: bool = false
var _ctx: ScriptContext = null


func is_running() -> bool:
	return _running


## The context of the script in flight (or the last one), for the owner to retarget the host
## after a scene change.
func context() -> ScriptContext:
	return _ctx


## Run [param commands] with [param ctx]. Returns true when the script ran (after it finished),
## false when refused because another script holds the lock.
func run(commands: Array, ctx: ScriptContext) -> bool:
	if _running:
		return false
	_running = true
	_ctx = ctx
	started.emit()
	await run_list(commands, ctx)
	_running = false
	finished.emit(ctx.stopped, ctx.stop_reason)
	return true


## Run a nested list (If / Choice branches) in the same context. Stops at the first command
## after the context was stopped.
static func run_list(commands: Array, ctx: ScriptContext) -> void:
	for c in commands:
		if ctx.stopped:
			return
		var cmd := c as StoryCommand
		if cmd == null:
			continue
		await cmd.run(ctx)
