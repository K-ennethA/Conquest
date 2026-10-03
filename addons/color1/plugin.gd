@tool
extends EditorPlugin
## Registers Color1Ext for the editor import path (also `--headless --import`).
## Imported .scn files already carry CUSTOM0, so nothing is needed at runtime.

var ext: Color1Ext


func _enter_tree() -> void:
	ext = Color1Ext.new()
	GLTFDocument.register_gltf_document_extension(ext, true)


func _exit_tree() -> void:
	GLTFDocument.unregister_gltf_document_extension(ext)
