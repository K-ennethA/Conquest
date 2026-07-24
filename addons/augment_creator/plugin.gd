@tool
extends EditorPlugin

const AugmentCreatorDock = preload("res://addons/augment_creator/augment_creator_dock.gd")

var dock

func _enter_tree():
	# Add the custom dock to the editor
	dock = AugmentCreatorDock.new()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	print("Augment Creator Tool loaded")

func _exit_tree():
	# Clean up
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	print("Augment Creator Tool unloaded")
