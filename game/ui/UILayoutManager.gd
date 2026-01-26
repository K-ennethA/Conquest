extends Node

class_name UILayoutManager

# UI Layout Manager
# Ensures proper positioning and prevents overlaps between UI elements

# Define UI zones to prevent overlaps
enum UIZone {
	TOP_LEFT,
	TOP_CENTER, 
	TOP_RIGHT,
	MIDDLE_LEFT,
	MIDDLE_CENTER,
	MIDDLE_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_CENTER,
	BOTTOM_RIGHT
}

# UI element registry
var ui_elements: Dictionary = {}
var zone_occupancy: Dictionary = {}

func _ready() -> void:
	name = "UILayoutManager"
	print("UILayoutManager initialized")

func register_ui_element(element: Control, zone: UIZone, priority: int = 0) -> bool:
	"""Register a UI element in a specific zone"""
	var element_name = element.name
	
	# Check if zone is already occupied by higher priority element
	if zone_occupancy.has(zone):
		var existing_element = zone_occupancy[zone]
		if existing_element.priority > priority:
			print("UILayoutManager: Zone " + UIZone.keys()[zone] + " occupied by higher priority element")
			return false
	
	# Register the element
	ui_elements[element_name] = {
		"element": element,
		"zone": zone,
		"priority": priority
	}
	
	zone_occupancy[zone] = {
		"element": element,
		"priority": priority
	}
	
	print("UILayoutManager: Registered " + element_name + " in zone " + UIZone.keys()[zone])
	return true

func unregister_ui_element(element: Control) -> void:
	"""Unregister a UI element"""
	var element_name = element.name
	
	if ui_elements.has(element_name):
		var element_data = ui_elements[element_name]
		var zone = element_data.zone
		
		ui_elements.erase(element_name)
		zone_occupancy.erase(zone)
		
		print("UILayoutManager: Unregistered " + element_name)

func get_zone_bounds(zone: UIZone, screen_size: Vector2) -> Rect2:
	"""Get the bounds for a specific UI zone"""
	var margin = 20.0
	var third_width = (screen_size.x - margin * 4) / 3.0
	var third_height = (screen_size.y - margin * 4) / 3.0
	
	match zone:
		UIZone.TOP_LEFT:
			return Rect2(margin, margin, third_width, third_height)
		UIZone.TOP_CENTER:
			return Rect2(margin + third_width + margin, margin, third_width, third_height)
		UIZone.TOP_RIGHT:
			return Rect2(margin + (third_width + margin) * 2, margin, third_width, third_height)
		UIZone.MIDDLE_LEFT:
			return Rect2(margin, margin + third_height + margin, third_width, third_height)
		UIZone.MIDDLE_CENTER:
			return Rect2(margin + third_width + margin, margin + third_height + margin, third_width, third_height)
		UIZone.MIDDLE_RIGHT:
			return Rect2(margin + (third_width + margin) * 2, margin + third_height + margin, third_width, third_height)
		UIZone.BOTTOM_LEFT:
			return Rect2(margin, margin + (third_height + margin) * 2, third_width, third_height)
		UIZone.BOTTOM_CENTER:
			return Rect2(margin + third_width + margin, margin + (third_height + margin) * 2, third_width, third_height)
		UIZone.BOTTOM_RIGHT:
			return Rect2(margin + (third_width + margin) * 2, margin + (third_height + margin) * 2, third_width, third_height)
	
	return Rect2()

func position_element_in_zone(element: Control, zone: UIZone) -> void:
	"""Position an element within its assigned zone"""
	var screen_size = get_viewport().get_visible_rect().size
	var zone_bounds = get_zone_bounds(zone, screen_size)
	
	# Set element position and size constraints
	element.position = zone_bounds.position
	element.size = Vector2(min(element.custom_minimum_size.x, zone_bounds.size.x), 
						   min(element.custom_minimum_size.y, zone_bounds.size.y))
	
	print("UILayoutManager: Positioned " + element.name + " at " + str(element.position) + " with size " + str(element.size))

func check_overlaps() -> Array:
	"""Check for overlapping UI elements"""
	var overlaps = []
	var elements = ui_elements.values()
	
	for i in range(elements.size()):
		for j in range(i + 1, elements.size()):
			var element1 = elements[i].element
			var element2 = elements[j].element
			
			if _elements_overlap(element1, element2):
				overlaps.append({
					"element1": element1.name,
					"element2": element2.name
				})
	
	return overlaps

func _elements_overlap(element1: Control, element2: Control) -> bool:
	"""Check if two elements overlap"""
	var rect1 = Rect2(element1.global_position, element1.size)
	var rect2 = Rect2(element2.global_position, element2.size)
	
	return rect1.intersects(rect2)

func print_layout_status() -> void:
	"""Print current UI layout status"""
	print("\n=== UI Layout Status ===")
	print("Registered elements: " + str(ui_elements.size()))
	
	for element_name in ui_elements:
		var data = ui_elements[element_name]
		var element = data.element
		print("  " + element_name + ": Zone " + UIZone.keys()[data.zone] + 
			  " | Pos: " + str(element.position) + " | Size: " + str(element.size) + 
			  " | Visible: " + str(element.visible))
	
	var overlaps = check_overlaps()
	if overlaps.size() > 0:
		print("OVERLAPS DETECTED:")
		for overlap in overlaps:
			print("  " + overlap.element1 + " overlaps with " + overlap.element2)
	else:
		print("No overlaps detected")
	
	print("=== End Layout Status ===\n")

# Utility methods for common UI positioning
func position_ui_elements() -> void:
	"""Position all registered UI elements in their zones"""
	for element_name in ui_elements:
		var data = ui_elements[element_name]
		position_element_in_zone(data.element, data.zone)