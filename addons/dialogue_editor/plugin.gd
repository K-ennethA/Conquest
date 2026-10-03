@tool
extends EditorPlugin

# Dialogue Editor - a MAIN-SCREEN tab ("Dialogue", beside 2D / 3D / Script / AssetLib) for the
# story's NPC dialogue bank (game/overworld/content/dialogue.json, read at runtime by DialogueBank).
# The whole UI is built in code (dialogue_editor_panel.gd), like the other Conquest tools.

const DialogueEditorPanel = preload("res://addons/dialogue_editor/dialogue_editor_panel.gd")

var panel


func _enter_tree():
	panel = DialogueEditorPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)
	print("Dialogue Editor loaded")


func _exit_tree():
	if panel:
		panel.queue_free()
		panel = null
	print("Dialogue Editor unloaded")


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if panel:
		panel.visible = visible


func _get_plugin_name() -> String:
	return "Dialogue"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("RichTextLabel", "EditorIcons")
