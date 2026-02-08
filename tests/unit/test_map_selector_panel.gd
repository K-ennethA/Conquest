extends GutTest

# Unit tests for MapSelectorPanel

var map_selector: Node
var map_selector_script: Script

func before_each():
	"""Setup before each test"""
	map_selector_script = load("res://game/ui/MapSelectorPanel.gd")
	map_selector = VBoxContainer.new()
	map_selector.set_script(map_selector_script)
	add_child_autofree(map_selector)
	
	# Wait for _ready to complete
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame for map loading

func after_each():
	"""Cleanup after each test"""
	if map_selector and is_instance_valid(map_selector):
		map_selector.queue_free()
	map_selector = null

# Initialization Tests
func test_map_selector_initializes():
	"""Test map selector initializes without errors"""
	assert_not_null(map_selector, "Map selector should be created")
	assert_not_null(map_selector.available_maps, "Available maps array should exist")
	assert_not_null(map_selector.map_resources, "Map resources array should exist")

func test_loads_available_maps():
	"""Test that available maps are loaded"""
	# Should have at least the default map
	assert_gt(map_selector.get_map_count(), 0, "Should have at least one map")

func test_gallery_mode_property():
	"""Test gallery mode can be set"""
	map_selector.set_gallery_mode(true)
	assert_true(map_selector.gallery_mode, "Gallery mode should be enabled")
	
	map_selector.set_gallery_mode(false)
	assert_false(map_selector.gallery_mode, "Gallery mode should be disabled")

func test_preview_size_property():
	"""Test preview size can be set"""
	var test_size = Vector2(300, 200)
	map_selector.set_preview_size(test_size)
	assert_eq(map_selector.preview_size, test_size, "Preview size should be updated")

func test_columns_property():
	"""Test columns can be set"""
	map_selector.set_columns(4)
	assert_eq(map_selector.columns, 4, "Columns should be updated")
	
	# Test minimum of 1
	map_selector.set_columns(0)
	assert_true(map_selector.columns >= 1, "Columns should be at least 1")

# Map Selection Tests
func test_get_selected_map_path():
	"""Test getting selected map path"""
	var selected_path = map_selector.get_selected_map_path()
	assert_not_null(selected_path, "Should return a map path")

func test_get_selected_map_resource():
	"""Test getting selected map resource"""
	var selected_resource = map_selector.get_selected_map_resource()
	# May be null if no maps, but should not crash
	pass_test("Get selected map resource doesn't crash")

func test_set_selected_map():
	"""Test setting selected map by path"""
	if map_selector.get_map_count() > 0:
		var first_map_path = map_selector.available_maps[0]
		var result = map_selector.set_selected_map(first_map_path)
		assert_true(result, "Should successfully set map")
		assert_eq(map_selector.get_selected_map_path(), first_map_path, "Selected map should match")

func test_set_invalid_map_returns_false():
	"""Test setting invalid map path returns false"""
	var result = map_selector.set_selected_map("res://invalid/path.tres")
	assert_false(result, "Should return false for invalid path")

# Signal Tests
func test_map_changed_signal_exists():
	"""Test map_changed signal exists"""
	assert_has_signal(map_selector, "map_changed", "Should have map_changed signal")

func test_map_changed_signal_emits():
	"""Test map_changed signal emits when map selected"""
	var signal_watcher = watch_signals(map_selector)
	
	if map_selector.get_map_count() > 0:
		map_selector._on_map_selected(0)
		await get_tree().process_frame
		
		assert_signal_emitted(map_selector, "map_changed", "Should emit map_changed signal")

# UI Mode Tests
func test_compact_mode():
	"""Test compact mode uses dropdown"""
	map_selector.compact_mode = true
	map_selector._build_ui()
	await get_tree().process_frame
	
	# In compact mode, should use dropdown not gallery
	assert_not_null(map_selector.map_dropdown, "Should have dropdown in compact mode")

func test_gallery_mode_creates_gallery():
	"""Test gallery mode creates gallery container"""
	map_selector.gallery_mode = true
	map_selector.compact_mode = false
	map_selector._build_ui()
	await get_tree().process_frame
	
	# Should have gallery container
	assert_not_null(map_selector.gallery_container, "Should have gallery container in gallery mode")

# Refresh Tests
func test_refresh_maps():
	"""Test refreshing map list"""
	var initial_count = map_selector.get_map_count()
	
	map_selector.refresh_maps()
	await get_tree().process_frame
	
	var after_count = map_selector.get_map_count()
	assert_eq(initial_count, after_count, "Map count should be consistent after refresh")

# Edge Cases
func test_handles_no_maps_gracefully():
	"""Test handles case with no maps available"""
	# This is hard to test without mocking, but we can verify it doesn't crash
	map_selector._load_available_maps()
	await get_tree().process_frame
	
	pass_test("Handles map loading without crashing")

func test_handles_null_map_resource():
	"""Test handles null map resource gracefully"""
	# Try to format a null map name
	var result = map_selector._format_map_name(null)
	
	# Should not crash and return something
	assert_not_null(result, "Should handle null map resource")

func test_preview_loading_with_invalid_path():
	"""Test preview loading with invalid path"""
	var mock_map = MapResource.new()
	mock_map.preview_image_path = "res://invalid/path.png"
	
	var texture = map_selector._load_map_preview(mock_map)
	
	# Should return default or null, not crash
	pass_test("Invalid preview path handled gracefully")

# Configuration Tests
func test_show_title_property():
	"""Test show_title property"""
	map_selector.show_title = false
	map_selector._build_ui()
	await get_tree().process_frame
	
	assert_false(map_selector.show_title, "show_title should be false")

func test_show_description_property():
	"""Test show_description property"""
	map_selector.show_description = false
	map_selector._build_ui()
	await get_tree().process_frame
	
	assert_false(map_selector.show_description, "show_description should be false")

func test_show_details_property():
	"""Test show_details property"""
	map_selector.show_details = false
	map_selector._build_ui()
	await get_tree().process_frame
	
	assert_false(map_selector.show_details, "show_details should be false")

func test_auto_select_first():
	"""Test auto_select_first property"""
	map_selector.auto_select_first = true
	map_selector._load_available_maps()
	await get_tree().process_frame
	
	if map_selector.get_map_count() > 0:
		assert_true(map_selector.current_map_index >= 0, "Should auto-select first map")
