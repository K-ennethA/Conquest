@tool
extends EditorPlugin

## The QUEST EDITOR (docs/STORY_MODE.md "Quest tracking"): a bottom-panel tab ("Quests") over
## game/overworld/content/quests.json. See quest_editor_panel.gd.

const QuestEditorPanel = preload("res://addons/quest_editor/quest_editor_panel.gd")

var panel: Control = null


func _enter_tree() -> void:
	panel = QuestEditorPanel.new()
	add_control_to_bottom_panel(panel, "Quests")


func _exit_tree() -> void:
	if panel != null:
		remove_control_from_bottom_panel(panel)
		panel.queue_free()
		panel = null
