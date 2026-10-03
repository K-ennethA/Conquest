@tool
extends EditorPlugin
## Registers Color1Ext for the editor import path (also `--headless --import`).
## Imported .scn files already carry CUSTOM0, so nothing is needed at runtime.
## Listed FIRST in project.godot [editor_plugins]: later plugins (map_creator) load the
## roster during plugin init, which imports missing model glbs on demand.

const COLOR1_EXT: Script = preload("res://addons/color1/color1_ext.gd")

var ext: GLTFDocumentExtension


func _enter_tree() -> void:
	ext = COLOR1_EXT.new()
	GLTFDocument.register_gltf_document_extension(ext, true)


func _exit_tree() -> void:
	GLTFDocument.unregister_gltf_document_extension(ext)
