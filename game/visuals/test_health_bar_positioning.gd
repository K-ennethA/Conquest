extends Node

# Test script to verify Fire Emblem-style health bar positioning and integration
# Run this in TestVisualSystem scene to validate health bar improvements

func _ready():
	print("=== Health Bar Positioning Test ===")
	print("Testing Fire Emblem-style health bar positioning and text integration...")
	
	# Wait a frame for scene to initialize
	await get_tree().process_frame
	
	_test_health_bar_positioning()
	_test_health_bar_text_integration()
	_test_health_bar_spacing()
	
	print("=== Health Bar Test Complete ===")
	print("Manual verification needed:")
	print("1. Health bars should be positioned at Y=1.8 (high enough to clear taller units)")
	print("2. Health text should be ABOVE the health bar (Pokemon style)")
	print("3. Health bars should be readable (1.2x0.25 size) with 16pt font")
	print("4. Text should be very readable with thick black outline (3px)")
	print("5. Press keys 1-4 to test damage/healing and health bar updates")

func _test_health_bar_positioning():
	print("\n--- Test 1: Health Bar Positioning ---")
	
	var units = [
		get_node("../Player1/Warrior1"),
		get_node("../Player1/Archer1"),
		get_node("../Player2/Warrior2"),
		get_node("../Player2/Archer2")
	]
	
	for unit in units:
		if unit:
			var health_bar = _find_health_bar(unit)
			if health_bar:
				print("Unit: " + unit.name + " - Health bar position: " + str(health_bar.position))
				print("  Expected Y=1.8, Actual Y=" + str(health_bar.position.y))
				if abs(health_bar.position.y - 1.8) < 0.1:
					print("  ✓ Position correct")
				else:
					print("  ❌ Position incorrect")
			else:
				print("❌ No health bar found for " + unit.name)

func _test_health_bar_text_integration():
	print("\n--- Test 2: Health Bar Text Integration ---")
	
	var unit = get_node("../Player1/Warrior1")
	if unit:
		var health_bar = _find_health_bar(unit)
		if health_bar:
			var label = health_bar.get_node("Label")
			if label:
				print("Health bar text position: " + str(label.position))
				print("Health bar text: '" + label.text + "'")
				print("Font size: " + str(label.font_size))
				print("Text should be at Y=0.2 (above health bar, Pokemon style)")
				if abs(label.position.y - 0.2) < 0.01:
					print("✓ Text properly positioned above health bar")
				else:
					print("❌ Text not properly positioned")
			else:
				print("❌ No label found in health bar")

func _test_health_bar_spacing():
	print("\n--- Test 3: Health Bar Spacing ---")
	
	var warrior1 = get_node("../Player1/Warrior1")
	var archer1 = get_node("../Player1/Archer1")
	
	if warrior1 and archer1:
		var hb1 = _find_health_bar(warrior1)
		var hb2 = _find_health_bar(archer1)
		
		if hb1 and hb2:
			var world_pos1 = warrior1.global_position + hb1.position
			var world_pos2 = archer1.global_position + hb2.position
			var distance = world_pos1.distance_to(world_pos2)
			
			print("Distance between health bars: " + str(distance))
			print("Unit distance: " + str(warrior1.global_position.distance_to(archer1.global_position)))
			
			if distance > 1.5:  # Should have clear separation
				print("✓ Health bars have proper spacing")
			else:
				print("❌ Health bars may be too close/overlapping")

func _find_health_bar(unit: Node) -> Node:
	"""Find the health bar child node of a unit"""
	for child in unit.get_children():
		if child.name == "HealthBar" or child.get_script() and child.get_script().get_global_name() == "HealthBar":
			return child
	return null