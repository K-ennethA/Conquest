@tool
extends EditorScript

# DOCUMENTATION FILE - NOT A RUNNABLE SCRIPT
# This file contains example code for integrating MapSelectorPanel
# Copy the relevant functions into your NetworkMultiplayerSetup.gd file

# Example: How to integrate MapSelectorPanel into NetworkMultiplayerSetup lobby
# This shows how to replace the hardcoded map dropdown with the MapSelectorPanel

# In NetworkMultiplayerSetup._create_lobby_ui(), replace the map selection section with:

func _run() -> void:
	print("This is a documentation file with integration examples.")
	print("Copy the example functions below into NetworkMultiplayerSetup.gd")
	print("See MAP_SELECTION_GALLERY_IMPLEMENTATION.md for full details.")

# ============================================================================
# EXAMPLE FUNCTIONS - COPY THESE INTO NetworkMultiplayerSetup.gd
# ============================================================================

# EXAMPLE 1: Full lobby UI with map selector
# Copy this function into NetworkMultiplayerSetup.gd and adapt as needed
"""
func _create_lobby_ui_with_map_selector() -> void:
	# Example of creating lobby UI with MapSelectorPanel
	
	# ... existing lobby setup code ...
	
	# Add map selection section title
	var map_section_title = Label.new()
	map_section_title.text = "Select Map:"
	map_section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_container.add_child(map_section_title)
	
	# OPTION 1: Compact dropdown mode (recommended for lobby)
	var map_selector = preload("res://game/ui/MapSelectorPanel.tscn").instantiate()
	map_selector.compact_mode = true  # Uses dropdown
	map_selector.show_title = false  # We have our own title above
	map_selector.show_details = false  # Keep lobby clean
	map_selector.map_changed.connect(_on_lobby_map_selected)
	lobby_container.add_child(map_selector)
	
	# OPTION 2: Full gallery mode (if you have space)
	# var map_selector = preload("res://game/ui/MapSelectorPanel.tscn").instantiate()
	# map_selector.gallery_mode = true
	# map_selector.preview_size = Vector2(150, 100)  # Smaller for lobby
	# map_selector.columns = 2  # Fewer columns
	# map_selector.show_title = false
	# map_selector.map_changed.connect(_on_lobby_map_selected)
	# lobby_container.add_child(map_selector)
	
	# Add spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	lobby_container.add_child(spacer)
	
	# ... rest of lobby UI (players list, start button, etc.) ...

func _on_lobby_map_selected(map_path: String, map_resource: MapResource) -> void:
	# Handle map selection in lobby
	print("[HOST] Map selected: " + map_resource.map_name + " (" + map_path + ")")
	
	# Update GameSettings
	GameSettings.set_selected_map(map_path)
	
	# Optional: Show map info in lobby
	var map_info = map_resource.get_display_info()
	print("[HOST] Map info: " + str(map_info))
	
	# Optional: Broadcast to clients that map changed (for real-time updates)
	if is_hosting:
		_broadcast_map_selection(map_path)

func _broadcast_map_selection(map_path: String) -> void:
	# Broadcast map selection to connected clients (optional)
	if not game_mode_manager:
		return
	
	game_mode_manager.submit_action("map_changed", {
		"map": map_path
	})
"""

# ============================================================================
# EXAMPLE 2: Simple integration
# ============================================================================
"""
func _add_map_selector_to_lobby() -> void:
	# Add map selector to lobby (compact mode)
	# Title
	var map_title = Label.new()
	map_title.text = "Map Selection:"
	map_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_container.add_child(map_title)
	
	# Map selector (compact dropdown)
	var map_selector = preload("res://game/ui/MapSelectorPanel.tscn").instantiate()
	map_selector.compact_mode = true
	map_selector.show_title = false
	map_selector.show_details = false
	map_selector.map_changed.connect(_on_lobby_map_selected)
	lobby_container.add_child(map_selector)
	
	# Spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	lobby_container.add_child(spacer)
"""

# ============================================================================
# WHAT TO REMOVE from NetworkMultiplayerSetup._create_lobby_ui()
# ============================================================================
"""
# ❌ REMOVE THIS OLD CODE:
# var map_section_title = Label.new()
# map_section_title.text = "Map Selection:"
# ...
# var map_dropdown = OptionButton.new()
# map_dropdown.name = "MapDropdown"
# ...
# map_dropdown.item_selected.connect(_on_map_selected)
# ...

# ✅ REPLACE WITH:
# _add_map_selector_to_lobby()
"""
