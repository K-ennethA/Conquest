@tool
extends EditorPlugin

const MapCreatorDock = preload("res://addons/map_creator/map_creator_dock.gd")

var dock

func _enter_tree():
	# Add the custom dock to the editor
	dock = MapCreatorDock.new()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	print("Map Creator Tool loaded")

func _exit_tree():
	# Clean up
	if dock:
		remove_control_from_docks(dock)
		dock = null
	print("Map Creator Tool unloaded")