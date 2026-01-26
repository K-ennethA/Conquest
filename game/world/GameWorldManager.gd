extends Node

# GameWorldManager
# Manages the initialization and setup of the game world based on GameSettings

func _ready() -> void:
	print("=== GameWorld Initializing ===")
	
	# Wait a frame for all singletons to be ready
	await get_tree().process_frame
	
	# Initialize player management first
	_setup_players()
	
	# Wait another frame to ensure units are properly assigned
	await get_tree().process_frame
	
	# Apply game settings (this will set up turn systems with units already assigned)
	if GameSettings:
		GameSettings.apply_settings_to_game()
	
	# Wait one more frame before starting the game
	await get_tree().process_frame
	
	# Start the game
	_start_game()
	
	print("=== GameWorld Initialization Complete ===")

func _setup_players() -> void:
	"""Set up players and assign units"""
	print("Setting up players...")
	
	# Ensure we have the right number of players
	if PlayerManager.players.is_empty():
		PlayerManager.setup_default_players()
	
	# Assign units to players based on scene structure
	PlayerManager.assign_units_by_parent()
	
	print("Players set up: " + str(PlayerManager.players.size()) + " players")

func _start_game() -> void:
	"""Start the game"""
	print("Starting game...")
	
	# Start the game in PlayerManager
	PlayerManager.start_game()
	
	print("Game started successfully!")

# Current UI Layout (1920x1080 reference):
# 
# TOP ROW:
# - UnitInfoPanel: (20, 20) to (320, 360) - 300x340
# - TurnIndicator: (1670, 20) to (1900, 100) - 230x80
#
# MIDDLE ROW:  
# - UnitActionsPanel: (1700, 120) to (1900, 340) - 200x220
#
# BOTTOM ROW:
# - TurnSystemIndicator: (20, 960) to (320, 1060) - 300x100
# - PlayerTurnPanel: (340, 960) to (620, 1060) - 280x100

# Debug input handling
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_M:
				_return_to_main_menu()
			KEY_S:
				_print_game_status()
			KEY_V:
				_refresh_unit_visuals()
			KEY_T:
				_toggle_mouse_mode()
			KEY_U:
				_test_unit_action()
			KEY_O:
				_debug_unit_ownership()
			KEY_I:
				_test_ui_separation()
			KEY_L:
				_check_ui_layout()

func _test_unit_action() -> void:
	"""Test unit action for debugging"""
	print("\n=== Testing Unit Action ===")
	
	if not TurnSystemManager.has_active_turn_system():
		print("No active turn system")
		return
	
	var turn_system = TurnSystemManager.get_active_turn_system()
	var units_that_can_act = []
	
	if turn_system is TraditionalTurnSystem:
		var trad_system = turn_system as TraditionalTurnSystem
		units_that_can_act = trad_system.get_units_that_can_act()
	
	if units_that_can_act.is_empty():
		print("No units can act")
		return
	
	var test_unit = units_that_can_act[0]
	print("Testing action with unit: " + test_unit.get_display_name())
	
	if turn_system is TraditionalTurnSystem:
		var trad_system = turn_system as TraditionalTurnSystem
		trad_system.mark_unit_acted(test_unit)
		print("Marked unit as acted")
	
	# Update visuals
	var visual_manager = get_node_or_null("../UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()
		print("Updated unit visuals")
	
	print("=== Unit Action Test Complete ===")

func _debug_unit_ownership() -> void:
	"""Debug unit ownership issues"""
	print("\n=== DEBUGGING UNIT OWNERSHIP ===")
	
	# Check PlayerManager
	if PlayerManager:
		print("PlayerManager players: " + str(PlayerManager.players.size()))
		for i in range(PlayerManager.players.size()):
			var player = PlayerManager.players[i]
			print("Player " + str(i) + ": " + player.get_display_name())
			print("  Owned units: " + str(player.owned_units.size()))
			for unit in player.owned_units:
				print("    - " + unit.get_display_name() + " (owner: " + (unit.get_owner_player().get_display_name() if unit.get_owner_player() else "None") + ")")
	
	# Check TurnSystem
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("Turn system registered units: " + str(turn_system.registered_units.size()))
		for unit in turn_system.registered_units:
			var owner = unit.get_owner_player()
			print("  - " + unit.get_display_name() + " (owner: " + (owner.get_display_name() if owner else "None") + ")")
	
	print("=== UNIT OWNERSHIP DEBUG COMPLETE ===")

func _test_ui_separation() -> void:
	"""Test the separation between unit actions and player turn actions"""
	print("\n=== TESTING UI SEPARATION ===")
	
	# Find UI panels
	var unit_panel = get_tree().current_scene.get_node_or_null("UI/UnitActionsPanel")
	var player_panel = get_tree().current_scene.get_node_or_null("UI/PlayerTurnPanel")
	
	if unit_panel:
		print("UnitActionsPanel found: " + str(unit_panel.visible))
	else:
		print("UnitActionsPanel NOT found")
	
	if player_panel:
		print("PlayerTurnPanel found: " + str(player_panel.visible))
	else:
		print("PlayerTurnPanel NOT found")
	
	print("=== UI SEPARATION TEST COMPLETE ===")

func _check_ui_layout() -> void:
	"""Check UI layout for overlaps"""
	print("\n=== CHECKING UI LAYOUT ===")
	
	var ui_manager = get_node_or_null("UILayoutManager")
	if ui_manager:
		ui_manager.print_layout_status()
	else:
		print("UILayoutManager not found - checking manually")
		
		var ui_layer = get_tree().current_scene.get_node_or_null("UI")
		if ui_layer:
			print("UI Elements found:")
			for child in ui_layer.get_children():
				if child is Control:
					print("  " + child.name + ": Pos " + str(child.position) + " Size " + str(child.size) + " Visible: " + str(child.visible))
		else:
			print("No UI layer found")
	
	print("=== UI LAYOUT CHECK COMPLETE ===")

func _return_to_main_menu() -> void:
	"""Return to the main menu"""
	print("Returning to main menu...")
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _print_game_status() -> void:
	"""Print current game status"""
	print("\n=== Game Status ===")
	if GameSettings:
		GameSettings.print_settings()
	if PlayerManager:
		PlayerManager.print_game_status()
	if TurnSystemManager:
		TurnSystemManager.print_turn_system_status()
	
	# Print detailed turn system info
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("\n=== Turn System Details ===")
		print("System: " + turn_system.system_name)
		print("Registered units: " + str(turn_system.registered_units.size()))
		print("Registered players: " + str(turn_system.registered_players.size()))
		
		if turn_system is TraditionalTurnSystem:
			var trad_system = turn_system as TraditionalTurnSystem
			var progress = trad_system.get_current_turn_progress()
			print("Current player: " + str(progress.get("current_player", "None")))
			print("Total units: " + str(progress.get("total_units", 0)))
			print("Units acted: " + str(progress.get("units_acted", 0)))
			print("Units can act: " + str(progress.get("units_can_act", 0)))
			print("Turn complete: " + str(progress.get("turn_complete", false)))
			
			print("Units that acted this turn:")
			for unit in trad_system.get_units_that_acted():
				print("  - " + unit.get_display_name())
			
			print("Units that can still act:")
			for unit in trad_system.get_units_that_can_act():
				print("  - " + unit.get_display_name())

func _refresh_unit_visuals() -> void:
	"""Refresh unit visuals for testing"""
	var visual_manager = get_node_or_null("../UnitVisualManager")
	if visual_manager:
		visual_manager.refresh_unit_visuals()
	else:
		print("UnitVisualManager not found")

func _toggle_mouse_mode() -> void:
	"""Toggle mouse cursor movement mode"""
	var cursor = get_tree().current_scene.get_node_or_null("Map/Cursor")
	if cursor:
		cursor.toggle_mouse_mode()
	else:
		print("Cursor not found")