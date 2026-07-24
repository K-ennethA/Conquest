extends Node

# Test script for the new lobby system

func _ready() -> void:
	print("=== LOBBY SYSTEM TEST ===")
	print("This test verifies the new lobby functionality")
	print("")
	print("Test Instructions:")
	print("1. Go to Main Menu → Versus → Network Multiplayer")
	print("2. Click 'Host Game' - should show lobby instead of auto-starting")
	print("3. Verify lobby shows:")
	print("   - Host address")
	print("   - Connected players list")
	print("   - START GAME button (disabled until 2+ players)")
	print("4. Click 'Host + Auto Client' - should show lobby and wait for client")
	print("5. When client connects, START GAME button should enable")
	print("6. Click START GAME to begin the match")
	print("")
	print("Press F8 to run lobby UI test")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F8:
			_test_lobby_ui()

func _test_lobby_ui() -> void:
	"""Test the lobby UI components"""
	print("\n=== TESTING LOBBY UI ===")
	
	# Check if we're in the NetworkMultiplayerSetup scene
	var current_scene = get_tree().current_scene
	if not current_scene or current_scene.get_script() != load("res://menus/NetworkMultiplayerSetup.gd"):
		print("✗ Not in NetworkMultiplayerSetup scene")
		print("Navigate to Main Menu → Versus → Network Multiplayer first")
		return
	
	print("✓ In NetworkMultiplayerSetup scene")
	
	# Check if lobby UI exists
	var lobby_container = current_scene.get_node_or_null("CenterContainer/VBoxContainer/LobbyContainer")
	if lobby_container:
		print("✓ Lobby container found")
		
		# Check lobby components
		var connection_info = lobby_container.get_node_or_null("ConnectionInfo")
		if connection_info:
			print("✓ Connection info label found")
		else:
			print("✗ Connection info label missing")
		
		var players_list = lobby_container.get_node_or_null("PlayersList")
		if players_list:
			print("✓ Players list label found")
		else:
			print("✗ Players list label missing")
		
		# Check for start game button
		var button_found = false
		for child in lobby_container.get_children():
			if child is HBoxContainer:
				for grandchild in child.get_children():
					if grandchild is Button and grandchild.text == "START GAME":
						print("✓ START GAME button found")
						button_found = true
						break
		
		if not button_found:
			print("✗ START GAME button missing")
		
		print("✓ Lobby UI test complete")
	else:
		print("✗ Lobby container not found")
		print("The lobby UI may not have been created yet")
	
	print("=== LOBBY UI TEST COMPLETE ===")

func _exit_tree() -> void:
	"""Clean up when exiting"""
	pass