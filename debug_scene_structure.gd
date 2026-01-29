extends Node

# Debug script to explore scene structure - press F8 to run

func _ready() -> void:
	print("🔍 Scene Structure Debug Ready - Press F8 to explore")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F8:
			print("F8 pressed - exploring scene structure")
			_explore_scene_structure()

func _explore_scene_structure() -> void:
	"""Explore the actual scene structure to find UnitActionsPanel"""
	
	print("=== Scene Structure Exploration ===")
	
	var scene_root = get_tree().current_scene
	print("Scene root: " + scene_root.name)
	
	# Explore UI structure
	var ui_node = scene_root.get_node_or_null("UI")
	if ui_node:
		print("\nUI node found, exploring children:")
		_print_node_tree(ui_node, 1)
	else:
		print("❌ No UI node found")
	
	# Search for UnitActionsPanel anywhere in the scene
	print("\n=== Searching for UnitActionsPanel anywhere in scene ===")
	var found_panels = _find_nodes_by_name(scene_root, "UnitActionsPanel")
	
	if found_panels.size() > 0:
		print("✅ Found " + str(found_panels.size()) + " UnitActionsPanel(s):")
		for i in range(found_panels.size()):
			var panel = found_panels[i]
			var path = _get_node_path(scene_root, panel)
			print("  " + str(i + 1) + ". Path: " + path)
			print("     Type: " + panel.get_class())
			print("     Visible: " + str(panel.visible))
	else:
		print("❌ No UnitActionsPanel found anywhere in scene")
	
	print("\n=== Exploration Complete ===")

func _print_node_tree(node: Node, depth: int) -> void:
	"""Print node tree structure"""
	var indent = ""
	for i in range(depth):
		indent += "  "
	
	print(indent + "- " + node.name + " (" + node.get_class() + ")")
	
	if depth < 4:  # Limit depth to avoid spam
		for child in node.get_children():
			_print_node_tree(child, depth + 1)

func _find_nodes_by_name(root: Node, target_name: String) -> Array[Node]:
	"""Recursively find all nodes with a specific name"""
	var found_nodes: Array[Node] = []
	
	if root.name == target_name:
		found_nodes.append(root)
	
	for child in root.get_children():
		found_nodes.append_array(_find_nodes_by_name(child, target_name))
	
	return found_nodes

func _get_node_path(root: Node, target: Node) -> String:
	"""Get the path from root to target node"""
	if root == target:
		return root.name
	
	for child in root.get_children():
		if child == target:
			return root.name + "/" + child.name
		
		var child_path = _get_node_path(child, target)
		if child_path != "":
			return root.name + "/" + child_path
	
	return ""