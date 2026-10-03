extends SceneTree

## Runs the story content builder AFTER the autoloads are registered:
##   godot --headless --path . -s res://game/overworld/build/run_builder.gd
##
## Why: a `-s` main script is compiled before the project's autoload names (GameEvents,
## TurnSystemManager, ...) are known to the GDScript analyzer, and build_story_content.gd reaches
## them through its typed dependencies (MapResource -> CharacterLibrary -> ...), so running it
## directly fails to compile. This runner names no game class: it waits one frame, then loads the
## builder and runs its _initialize() on a detached instance.

const BUILDER := "res://game/overworld/build/build_story_content.gd"


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var script: GDScript = load(BUILDER)
	if script == null:
		printerr("[run_builder] cannot load %s" % BUILDER)
		quit(1)
		return
	var builder = script.new()
	builder._initialize()
	var ok: bool = bool(builder.get("_ok"))
	builder.free()
	quit(0 if ok else 1)
