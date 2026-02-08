extends Node

# GameSettings Singleton
# Stores game configuration and settings across scenes

enum GameMode {
	SINGLE_PLAYER,
	VERSUS,
	MULTIPLAYER  # For future expansion
}

# Game configuration
var game_mode: GameMode = GameMode.VERSUS
var selected_turn_system: TurnSystemBase.TurnSystemType = TurnSystemBase.TurnSystemType.TRADITIONAL
var selected_map_path: String = "res://game/maps/resources/default_skirmish.tres"  # Default map

# Player configuration
var player_count: int = 2
var player_names: Array[String] = ["Player 1", "Player 2"]

# Game settings
var auto_end_turn: bool = false  # Whether to automatically end turns when all units have acted
var show_turn_indicators: bool = true
var enable_undo: bool = false  # For future expansion

func _ready() -> void:
	name = "GameSettings"
	print("GameSettings initialized")

# Configuration methods
func set_game_mode(mode: GameMode) -> void:
	"""Set the game mode"""
	game_mode = mode
	print("Game mode set to: " + GameMode.keys()[mode])

func set_turn_system(turn_system: TurnSystemBase.TurnSystemType) -> void:
	"""Set the selected turn system"""
	selected_turn_system = turn_system
	print("Turn system set to: " + TurnSystemBase.TurnSystemType.keys()[turn_system])

func set_player_count(count: int) -> void:
	"""Set the number of players"""
	player_count = clamp(count, 2, 4)  # Support 2-4 players
	
	# Adjust player names array
	while player_names.size() < player_count:
		player_names.append("Player " + str(player_names.size() + 1))
	
	print("Player count set to: " + str(player_count))

func set_player_name(player_index: int, name: String) -> void:
	"""Set a specific player's name"""
	if player_index >= 0 and player_index < player_names.size():
		player_names[player_index] = name
		print("Player " + str(player_index + 1) + " name set to: " + name)

func set_selected_map(map_path: String) -> void:
	"""Set the selected map path"""
	selected_map_path = map_path
	print("Selected map set to: " + map_path)

func get_selected_map() -> String:
	"""Get the selected map path"""
	# Return default map if none selected
	if selected_map_path.is_empty():
		return "res://game/maps/resources/default_skirmish.tres"
	return selected_map_path

# Query methods
func get_game_mode_string() -> String:
	"""Get the current game mode as a string"""
	return GameMode.keys()[game_mode]

func get_turn_system_string() -> String:
	"""Get the current turn system as a string"""
	return TurnSystemBase.TurnSystemType.keys()[selected_turn_system]

func is_single_player() -> bool:
	"""Check if this is a single player game"""
	return game_mode == GameMode.SINGLE_PLAYER

func is_versus() -> bool:
	"""Check if this is a versus game"""
	return game_mode == GameMode.VERSUS

# Game initialization
func apply_settings_to_game() -> void:
	"""Apply current settings to the game systems"""
	print("Applying game settings...")
	
	# Set up PlayerManager with configured players
	if PlayerManager:
		# Only set up players if they don't exist yet
		if PlayerManager.players.is_empty():
			# Create players based on configuration
			for i in range(player_count):
				var player_name = player_names[i] if i < player_names.size() else "Player " + str(i + 1)
				PlayerManager.register_player(player_name)
	
	# Set up TurnSystemManager with selected turn system
	if TurnSystemManager:
		# Create and register the selected turn system (but don't activate yet)
		# The turn system will be activated when PlayerManager.start_game() is called
		match selected_turn_system:
			TurnSystemBase.TurnSystemType.TRADITIONAL:
				var traditional_system = TraditionalTurnSystem.new()
				TurnSystemManager.register_turn_system(traditional_system)
			
			TurnSystemBase.TurnSystemType.INITIATIVE:
				var speed_first_system = SpeedFirstTurnSystem.new()
				TurnSystemManager.register_turn_system(speed_first_system)
			
			# TODO: Add other turn systems when implemented
			_:
				print("Turn system not implemented: " + get_turn_system_string())
				# Fallback to traditional
				var traditional_system = TraditionalTurnSystem.new()
				TurnSystemManager.register_turn_system(traditional_system)
	
	print("Game settings applied successfully")

# Reset and defaults
func reset_to_defaults() -> void:
	"""Reset all settings to default values"""
	game_mode = GameMode.VERSUS
	selected_turn_system = TurnSystemBase.TurnSystemType.TRADITIONAL
	selected_map_path = "res://game/maps/resources/default_skirmish.tres"  # Default map
	player_count = 2
	player_names = ["Player 1", "Player 2"]
	auto_end_turn = false
	show_turn_indicators = true
	enable_undo = false
	
	print("Game settings reset to defaults")

# Debug and info
func get_settings_info() -> Dictionary:
	"""Get all current settings as a dictionary"""
	return {
		"game_mode": get_game_mode_string(),
		"turn_system": get_turn_system_string(),
		"selected_map": selected_map_path,
		"player_count": player_count,
		"player_names": player_names.duplicate(),
		"auto_end_turn": auto_end_turn,
		"show_turn_indicators": show_turn_indicators,
		"enable_undo": enable_undo
	}

func print_settings() -> void:
	"""Print current settings for debugging"""
	print("=== Game Settings ===")
	var info = get_settings_info()
	for key in info:
		print(key + ": " + str(info[key]))