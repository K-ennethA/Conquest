extends SceneTree

## Exports the roster / moves / abilities as the Conquest Roster page's roster.json (the owner's
## web editor; evolutions and portrait links are added beside it). Writes to $ROSTER_OUT:
##   ROSTER_OUT=/path/roster.json godot --headless --path . -s res://dev_scripts/export_roster_page.gd

const IMPL := "res://dev_scripts/export_roster_page_impl.gd"


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var impl: Object = (load(IMPL) as GDScript).new()
	impl.call("run", OS.get_environment("ROSTER_OUT"))
	quit(0)
