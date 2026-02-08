extends Control

# Simple lobby test to isolate issues

func _ready() -> void:
	print("[TEST] Simple lobby test starting...")
	
	# Create a simple label
	var label = Label.new()
	label.text = "LOBBY TEST - If you see this, UI works!"
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	
	print("[TEST] Label created successfully")
	
	# Test button
	var button = Button.new()
	button.text = "Test Button"
	button.position = Vector2(400, 300)
	button.pressed.connect(_on_test_pressed)
	add_child(button)
	
	print("[TEST] Button created successfully")

func _on_test_pressed() -> void:
	print("[TEST] Button pressed!")
