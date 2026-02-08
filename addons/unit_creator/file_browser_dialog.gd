@tool
extends AcceptDialog

# File browser dialog for the Unit Creator tool

signal file_selected(path: String)

var file_dialog: FileDialog
var file_type: String = ""

func _init(title: String = "Select File", file_filters: PackedStringArray = []):
	set_title(title)
	set_size(Vector2(600, 400))
	
	# Create file dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Set file filters
	for filter in file_filters:
		file_dialog.add_filter(filter)
	
	# Connect signals
	file_dialog.file_selected.connect(_on_file_selected)
	
	# Add to dialog
	add_child(file_dialog)

func _on_file_selected(path: String):
	"""Handle file selection"""
	file_selected.emit(path)
	hide()

func show_dialog():
	"""Show the file browser dialog"""
	popup_centered()
	file_dialog.popup_centered(Vector2(580, 380))