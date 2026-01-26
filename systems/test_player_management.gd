extends Node

# Test script for Player Management System
# Tests player registration, unit assignment, and turn management

func _ready():
	print("=== Player Management System Test ===")
	print("Testing player registration, unit assignment, and turn management...")
	
	# Wait for scene to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	_test_player_registration()
	_test_unit_assignment()
	_test_turn_management()
	_test_player_validation()
	
	print("=== Player Management Test Complete ===")
	print("Interactive Test Keys:")
	print("  Key 1: Print game status")
	print("  Key 2: End current player's turn (or use End Turn button)")
	print("  Key 3: Test unit selection validation")
	print("  Key 4: Reset game")
	print("")
	print("UI Controls:")
	print("  Unit Actions Panel: Appears when unit is selected")
	print("  - Move Button: Move the selected unit")
	print("  - End Turn Button: End current player's turn")
	print("  - Cancel Button: Deselect the unit")
	print("  Arrow Keys + Enter: Move cursor and select units")

func _test_player_registration():
	print("\n--- Test 1: Player Registration ---")
	
	# Test default player setup
	PlayerManager.setup_default_players()
	
	var player_count = PlayerManager.get_player_count()
	print("Players registered: " + str(player_count))
	
	if player_count == 2:
		print("✓ Correct number of players registered")
	else:
		print("❌ Expected 2 players, got " + str(player_count))
	
	# Test player properties
	for i in range(player_count):
		var player = PlayerManager.get_player_by_id(i)
		if player:
			print("Player " + str(i) + ": " + player.get_display_name())
			print("  Team Color: " + str(player.get_team_color()))
			print("  State: " + Player.PlayerState.keys()[player.current_state])
		else:
			print("❌ Player " + str(i) + " not found")

func _test_unit_assignment():
	print("\n--- Test 2: Unit Assignment ---")
	
	# Auto-assign units based on scene structure
	PlayerManager.assign_units_by_parent()
	
	# Check unit assignments
	for i in range(PlayerManager.get_player_count()):
		var player = PlayerManager.get_player_by_id(i)
		if player:
			var unit_count = player.get_unit_count()
			print("Player " + str(i + 1) + " units: " + str(unit_count))
			
			for unit in player.owned_units:
				print("  - " + unit.get_display_name() + " (Health: " + str(unit.current_health) + "/" + str(unit.max_health) + ")")
			
			if unit_count > 0:
				print("  ✓ Units assigned successfully")
			else:
				print("  ❌ No units assigned")

func _test_turn_management():
	print("\n--- Test 3: Turn Management ---")
	
	# Start the game
	PlayerManager.start_game()
	
	var current_player = PlayerManager.get_current_player()
	if current_player:
		print("Current player: " + current_player.get_display_name())
		print("Player state: " + Player.PlayerState.keys()[current_player.current_state])
		
		if current_player.current_state == Player.PlayerState.ACTIVE:
			print("✓ Game started successfully")
		else:
			print("❌ Current player is not active")
	else:
		print("❌ No current player found")
	
	# Test game state
	var game_info = PlayerManager.get_game_state_info()
	print("Game State: " + game_info.game_state)
	print("Turn Number: " + str(game_info.turn_number))

func _test_player_validation():
	print("\n--- Test 4: Player Validation ---")
	
	var current_player = PlayerManager.get_current_player()
	if not current_player:
		print("❌ No current player for validation test")
		return
	
	# Test unit selection validation
	var player1 = PlayerManager.get_player_by_id(0)
	var player2 = PlayerManager.get_player_by_id(1)
	
	if player1 and player1.owned_units.size() > 0:
		var player1_unit = player1.owned_units[0]
		
		# Test current player can select their own unit
		var can_select_own = PlayerManager.can_current_player_select_unit(player1_unit)
		if current_player == player1:
			if can_select_own:
				print("✓ Current player can select their own unit")
			else:
				print("❌ Current player cannot select their own unit")
		else:
			if not can_select_own:
				print("✓ Current player cannot select opponent's unit")
			else:
				print("❌ Current player can select opponent's unit (should not be allowed)")

# Input handling for interactive testing
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_print_game_status()
			KEY_2:
				_end_current_turn()
			KEY_3:
				_test_unit_selection()
			KEY_4:
				_reset_game()

func _print_game_status():
	print("\n=== Current Game Status ===")
	PlayerManager.print_game_status()

func _end_current_turn():
	print("\n--- Ending Current Player's Turn ---")
	var current_player = PlayerManager.get_current_player()
	if current_player:
		print("Ending turn for: " + current_player.get_display_name())
		PlayerManager.end_current_player_turn()
	else:
		print("No current player to end turn for")

func _test_unit_selection():
	print("\n--- Testing Unit Selection Validation ---")
	
	var current_player = PlayerManager.get_current_player()
	if not current_player:
		print("No current player")
		return
	
	print("Current player: " + current_player.get_display_name())
	
	# Test selecting own units
	if current_player.owned_units.size() > 0:
		var own_unit = current_player.owned_units[0]
		var can_select = PlayerManager.can_current_player_select_unit(own_unit)
		print("Can select own unit (" + own_unit.get_display_name() + "): " + str(can_select))
	
	# Test selecting opponent units
	for player in PlayerManager.players:
		if player != current_player and player.owned_units.size() > 0:
			var opponent_unit = player.owned_units[0]
			var can_select = PlayerManager.can_current_player_select_unit(opponent_unit)
			print("Can select opponent unit (" + opponent_unit.get_display_name() + "): " + str(can_select))

func _reset_game():
	print("\n--- Resetting Game ---")
	
	# Reset all players to setup state
	for player in PlayerManager.players:
		player.set_state(Player.PlayerState.WAITING)
	
	PlayerManager.current_game_state = PlayerManager.GameState.SETUP
	PlayerManager.turn_number = 0
	PlayerManager.current_player_index = 0
	
	print("Game reset to setup state")
	print("Use Key 2 to start a new game")