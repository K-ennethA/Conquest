extends Node

# Test script for the unified game system
# Demonstrates single-player, local multiplayer, and network multiplayer

var status_label: Label

func _ready() -> void:
	print("=== Unified Game System Test ===")
	
	# Get UI elements
	status_label = $UI/VBoxContainer/StatusLabel
	
	# Connect UI buttons
	$UI/VBoxContainer/SinglePlayerButton.pressed.connect(_on_single_player_pressed)
	$UI/VBoxContainer/LocalMultiplayerButton.pressed.connect(_on_local_multiplayer_pressed)
	$UI/VBoxContainer/NetworkHostButton.pressed.connect(_on_network_host_pressed)
	$UI/VBoxContainer/NetworkJoinButton.pressed.connect(_on_network_join_pressed)
	$UI/VBoxContainer/TestActionButton.pressed.connect(_on_test_action_pressed)
	$UI/VBoxContainer/EndGameButton.pressed.connect(_on_end_game_pressed)
	
	# Wait for GameModeManager autoload to be ready
	await get_tree().process_frame
	
	# Connect signals
	GameModeManager.game_started.connect(_on_game_started)
	GameModeManager.game_ended.connect(_on_game_ended)
	GameModeManager.game_mode_changed.connect(_on_game_mode_changed)
	
	_update_status("Unified game system ready")

func _update_status(text: String) -> void:
	"""Update status label"""
	if status_label:
		status_label.text = "Status: " + text
	print("Status: " + text)

func _on_single_player_pressed() -> void:
	"""Start single player game"""
	print("Starting single player game...")
	_update_status("Starting single player...")
	
	var success = GameModeManager.start_single_player("Player", 1)
	if success:
		_update_status("Single player game started!")
	else:
		_update_status("Failed to start single player game")

func _on_local_multiplayer_pressed() -> void:
	"""Start local multiplayer game"""
	print("Starting local multiplayer game...")
	_update_status("Starting local multiplayer...")
	
	var player_names = ["Alice", "Bob"]
	var success = GameModeManager.start_local_multiplayer(player_names)
	if success:
		_update_status("Local multiplayer game started!")
	else:
		_update_status("Failed to start local multiplayer game")

func _on_network_host_pressed() -> void:
	"""Start network host"""
	print("Starting network host...")
	_update_status("Starting network host...")
	
	var success = await GameModeManager.start_network_multiplayer_host("Host Player", "local")
	if success:
		_update_status("Network host started! Others can join at localhost:8910")
	else:
		_update_status("Failed to start network host")

func _on_network_join_pressed() -> void:
	"""Join network game"""
	print("Joining network game...")
	_update_status("Joining network game...")
	
	var success = await GameModeManager.join_network_multiplayer("127.0.0.1", 8910, "Client Player", "local")
	if success:
		_update_status("Joined network game!")
	else:
		_update_status("Failed to join network game")

func _on_test_action_pressed() -> void:
	"""Test submitting a game action"""
	if not GameModeManager.is_game_active():
		_update_status("No active game to test action")
		return
	
	if not GameModeManager.can_i_act():
		_update_status("Cannot act - not your turn")
		return
	
	# Submit a test action
	var action_data = {
		"unit_id": "test_unit_1",
		"from_position": Vector3(0, 0, 0),
		"to_position": Vector3(1, 0, 0)
	}
	
	var success = GameModeManager.submit_action("unit_move", action_data)
	if success:
		_update_status("Test action submitted successfully!")
	else:
		_update_status("Failed to submit test action")

func _on_end_game_pressed() -> void:
	"""End current game"""
	if GameModeManager.is_game_active():
		GameModeManager.end_current_game()
		_update_status("Game ended")
	else:
		_update_status("No active game to end")

# Signal handlers
func _on_game_started(mode: GameManager.GameMode) -> void:
	"""Handle game started"""
	var mode_name = GameManager.GameMode.keys()[mode]
	_update_status("Game started in %s mode" % mode_name)

func _on_game_ended(winner_id: int) -> void:
	"""Handle game ended"""
	_update_status("Game ended, winner: %d" % winner_id)

func _on_game_mode_changed(new_mode: GameManager.GameMode) -> void:
	"""Handle game mode changed"""
	var mode_name = GameManager.GameMode.keys()[new_mode]
	print("Game mode changed to: %s" % mode_name)

# Input handling for debug and help
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_D:
				_print_debug_info()
			KEY_H:
				_print_help()
			KEY_1:
				_on_single_player_pressed()
			KEY_2:
				_on_local_multiplayer_pressed()
			KEY_3:
				_on_network_host_pressed()
			KEY_4:
				_on_network_join_pressed()
			KEY_T:
				_on_test_action_pressed()
			KEY_E:
				_on_end_game_pressed()

func _print_debug_info() -> void:
	"""Print comprehensive debug information"""
	print("\n=== Unified Game System Debug Info ===")
	
	var status = GameModeManager.get_game_status()
	print("Game Status:")
	for key in status:
		print("  %s: %s" % [key, str(status[key])])
	
	print("\nGame State:")
	print("  Is Active: %s" % GameModeManager.is_game_active())
	print("  Current Mode: %s" % GameManager.GameMode.keys()[GameModeManager.get_current_game_mode()])
	print("  Is My Turn: %s" % GameModeManager.is_my_turn())
	print("  Can I Act: %s" % GameModeManager.can_i_act())
	
	print("=== End Debug Info ===\n")

func _print_help() -> void:
	"""Print help information"""
	print("\n=== Unified Game System Controls ===")
	print("1 - Start Single Player Game")
	print("2 - Start Local Multiplayer Game")
	print("3 - Start Network Host")
	print("4 - Join Network Game (localhost:8910)")
	print("T - Test Game Action")
	print("E - End Current Game")
	print("D - Print Debug Info")
	print("H - Show this help")
	print("=====================================\n")

# Cleanup
func _exit_tree() -> void:
	if GameModeManager:
		GameModeManager.end_current_game()
	print("Unified game test cleanup complete")