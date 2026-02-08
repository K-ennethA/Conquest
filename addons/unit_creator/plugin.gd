@tool
extends EditorPlugin

const UnitCreatorDock = preload("res://addons/unit_creator/unit_creator_dock.gd")

var dock

func _enter_tree():
	# Add the custom dock to the editor
	dock = UnitCreatorDock.new()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	print("Unit Creator Tool loaded")

func _exit_tree():
	# Clean up
	if dock:
		remove_control_from_docks(dock)
		dock = null
	print("Unit Creator Tool unloaded")