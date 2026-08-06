extends SceneTree

## Headless check: load the shipped maps through MapLoader and let any
## "invalid UID" warnings surface in the console. Run:
##   godot --headless --script dev_scripts/check_uid_warnings.gd
##
## Everything is loaded by path at runtime, AFTER the first frame -- referencing
## MapLoader/MapResource as identifiers would compile the whole gameplay script
## chain before the autoloads (GameSettings, GameEvents) are registered and fail.

const MAP_PATHS: Array[String] = [
	"res://game/maps/resources/riftwood.tres",
	"res://game/maps/resources/forgotten_forest.tres",
]


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var loader: Node = load("res://game/maps/MapLoader.gd").new()
	for map_path: String in MAP_PATHS:
		var parent: Node3D = Node3D.new()
		root.add_child(parent)
		var map_resource: Resource = load(map_path)
		var ok: bool = loader.load_map(map_resource, parent)
		print("MAP %s loaded=%s" % [map_path, ok])
		root.remove_child(parent)
		parent.free()
	loader.free()
	print("UID_CHECK_DONE")
	quit(0)
