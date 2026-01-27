extends Node

# Quick test script to debug unit selection issue

func _ready():
	print("=== Unit Selection Debug Test ===")
	
	# Wait a moment for everything to initialize
	await get_tree().create_timer(2.0).timeout
	
	# Check if GameEvents exists
	if GameEvents:
		print("✓ GameEvents found")
		
		# Connect to unit selection events
		GameEvents.unit_selected.connect(_on_unit_selected_debug)
		GameEvents.unit_deselected.connect(_on_unit_deselected_debug)
		print("✓ Connected to GameEvents signals")
	else:
		print("✗ GameEvents not found!")
	
	# Check if UnitActionsPanel exists
	var ui_layout = get_tree().current_scene.get_node_or_null("UI/GameUILayout")
	if ui_layout:
		var unit_actions_panel = ui_layout.get_node_or_null("MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel")
		if unit_actions_panel:
			print("✓ UnitActionsPanel found at: " + unit_actions_panel.get_path())
		else:
			print("✗ UnitActionsPanel not found in expected location")
	else:
		print("✗ UI Layout not found")
	
	# Check if cursor exists
	var cursor = get_tree().current_scene.get_node_or_null("Map/Cursor")
	if cursor:
		print("✓ Cursor found at: " + cursor.get_path())
	else:
		print("✗ Cursor not found")
	
	print("=== Debug Test Complete ===")

func _on_unit_selected_debug(unit: Unit, position: Vector3):
	print("=== DEBUG: Unit selected signal received ===")
	print("Unit: " + unit.name)
	print("Position: " + str(position))

func _on_unit_deselected_debug(unit: Unit):
	print("=== DEBUG: Unit deselected signal received ===")
	print("Unit: " + unit.name)