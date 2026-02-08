extends Node

# Test script to verify multiplayer fixes

func _ready() -> void:
	print("=== Testing Multiplayer Fixes ===")
	
	# Test PlayerManager methods
	test_player_manager()
	
	# Test GameModeManager
	test_game_mode_manager()
	
	print("=== Multiplayer Fix Tests Complete ===")
	get_tree().quit()

func test_player_manager() -> void:
	print("\n--- Testing PlayerManager ---")
	
	# Test basic functionality
	if PlayerManager:
		print("PlayerManager found: " + str(PlayerManager))
		
		# Test get_current_player_index method
		if PlayerManager.has_method("get_current_player_index"):
			var index = PlayerManager.get_current_player_index()
			print("Current player index: " + str(index))
		else:
			print("ERROR: get_current_player_index method not found!")
		
		# Test player setup
		PlayerManager.setup_default_players()
		print("Players after setup: " + str(PlayerManager.players.size()))
		
		# Test current player
		var current_player = PlayerManager.get_current_player()
		if current_player:
			print("Current player: " + current_player.get_display_name())
		else:
			print("No current player")
	else:
		print("ERROR: PlayerManager not found!")

func test_game_mode_manager() -> void:
	print("\n--- Testing GameModeManager ---")
	
	if GameModeManager:
		print("GameModeManager found: " + str(GameModeManager))
		
		# Test basic methods
		var is_active = GameModeManager.is_game_active()
		print("Game active: " + str(is_active))
		
		var is_multiplayer = GameModeManager.is_multiplayer_active()
		print("Multiplayer active: " + str(is_multiplayer))
		
		var status = GameModeManager.get_multiplayer_status()
		print("Multiplayer status: " + str(status))
	else:
		print("ERROR: GameModeManager not found!")