extends Node

# Debug script to test multiplayer turn synchronization
# This will help us understand what's happening with the turn sync

func _ready() -> void:
	print(_get_log_prefix() + "=== MULTIPLAYER TURN SYNC DEBUG TEST ===")
	
	# Wait for systems to initialize
	await get_tree().create_timer(1.0).timeout
	
	# Check if we're in multiplayer mode
	if GameModeManager and GameModeManager.is_multiplayer_active():
		print(_get_log_prefix() + "Multiplayer mode detected")
		_debug_multiplayer_state()
	else:
		print(_get_log_prefix() + "Not in multiplayer mode")
		_debug_single_player_state()

func _get_log_prefix() -> String:
	"""Get a log prefix to identify host vs client"""
	var prefix = "[UNKNOWN] "
	
	if GameModeManager and GameModeManager.is_multiplayer_active():
		var local_player_id = GameModeManager.get_local_player_id()
		if local_player_id == 0:
			prefix = "[HOST] "
		elif local_player_id == 1:
			prefix = "[CLIENT] "
		else:
			prefix = "[PLAYER" + str(local_player_id) + "] "
	else:
		prefix = "[SINGLE] "
	
	return prefix

func _debug_multiplayer_state() -> void:
	"""Debug multiplayer state"""
	print(_get_log_prefix() + "\n--- MULTIPLAYER STATE DEBUG ---")
	
	# Check GameModeManager
	if GameModeManager:
		print(_get_log_prefix() + "GameModeManager exists")
		print(_get_log_prefix() + "  Current game mode: " + str(GameModeManager.get_current_game_mode()))
		print(_get_log_prefix() + "  Is game active: " + str(GameModeManager.is_game_active()))
		print(_get_log_prefix() + "  Local player ID: " + str(GameModeManager.get_local_player_id()))
		print(_get_log_prefix() + "  Is my turn: " + str(GameModeManager.is_my_turn()))
		
		# Check GameManager
		var game_manager = GameModeManager._game_manager
		if game_manager:
			print(_get_log_prefix() + "GameManager exists")
			print(_get_log_prefix() + "  Current player ID: " + str(game_manager.get_current_player_id()))
			print(_get_log_prefix() + "  Players: " + str(game_manager.get_players()))
		else:
			print(_get_log_prefix() + "GameManager is null")
	else:
		print(_get_log_prefix() + "GameModeManager is null")
	
	# Check PlayerManager
	if PlayerManager:
		print(_get_log_prefix() + "PlayerManager exists")
		print(_get_log_prefix() + "  Current player index: " + str(PlayerManager.get_current_player_index()))
		print(_get_log_prefix() + "  Player count: " + str(PlayerManager.get_player_count()))
		
		var current_player = PlayerManager.get_current_player()
		if current_player:
			print(_get_log_prefix() + "  Current player: " + current_player.get_display_name())
		else:
			print(_get_log_prefix() + "  Current player is null")
		
		# List all players
		for i in range(PlayerManager.get_player_count()):
			var player = PlayerManager.get_player_by_id(i)
			if player:
				print(_get_log_prefix() + "  Player " + str(i) + ": " + player.get_display_name() + " (" + str(player.current_state) + ")")
	else:
		print(_get_log_prefix() + "PlayerManager is null")

func _debug_single_player_state() -> void:
	"""Debug single player state"""
	print(_get_log_prefix() + "\n--- SINGLE PLAYER STATE DEBUG ---")
	
	# Check PlayerManager
	if PlayerManager:
		print(_get_log_prefix() + "PlayerManager exists")
		print(_get_log_prefix() + "  Current player index: " + str(PlayerManager.get_current_player_index()))
		print(_get_log_prefix() + "  Player count: " + str(PlayerManager.get_player_count()))
		
		var current_player = PlayerManager.get_current_player()
		if current_player:
			print(_get_log_prefix() + "  Current player: " + current_player.get_display_name())
		else:
			print(_get_log_prefix() + "  Current player is null")
	else:
		print(_get_log_prefix() + "PlayerManager is null")

func _input(event: InputEvent) -> void:
	"""Handle input for manual testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				print(_get_log_prefix() + "\n=== MANUAL TURN ADVANCE TEST ===")
				_test_turn_advance()
			KEY_2:
				print(_get_log_prefix() + "\n=== MANUAL NETWORK ACTION TEST ===")
				_test_network_action()
			KEY_3:
				print(_get_log_prefix() + "\n=== REFRESH STATE DEBUG ===")
				if GameModeManager and GameModeManager.is_multiplayer_active():
					_debug_multiplayer_state()
				else:
					_debug_single_player_state()

func _test_turn_advance() -> void:
	"""Test manual turn advancement"""
	if PlayerManager:
		print(_get_log_prefix() + "Attempting to advance turn...")
		PlayerManager.end_current_player_turn()
	else:
		print(_get_log_prefix() + "PlayerManager not available")

func _test_network_action() -> void:
	"""Test sending a network action"""
	if GameModeManager and GameModeManager.is_multiplayer_active():
		print(_get_log_prefix() + "Sending test network action...")
		var success = GameModeManager.submit_action("test_action", {"test": "data"})
		print(_get_log_prefix() + "Network action result: " + str(success))
	else:
		print(_get_log_prefix() + "Not in multiplayer mode")