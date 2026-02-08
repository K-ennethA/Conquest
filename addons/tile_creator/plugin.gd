@tool
extends EditorPlugin

# Tile Creator Plugin - Main plugin file

var dock

func _enter_tree():
	# Add the custom dock to the editor
	dock = load("res://addons/tile_creator/tile_creator_dock.gd").new()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	print("Tile Creator Tool loaded")

func _exit_tree():
	# Clean up
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
	print("Tile Creator Tool unloaded")