extends Node

# Debug script to test client connection issues
# Run this to verify client instance is actually starting and connecting

func _ready() -> void:
	print("=== CLIENT CONNECTION DEBUG ===")
	
	# Check command line arguments
	var args = OS.get_cmdline_args()
	print("Command line arguments: " + str(args))
	
	# Check if auto-join is enabled
	var auto_join_enabled = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			auto_join_enabled = true
			break
	
	print("Auto-join enabled: " + str(auto_join_enabled))
	
	# Check MultiplayerLauncher
	var launcher = get_node_or_null("/root/MultiplayerLauncher")
	if launcher:
		print("MultiplayerLauncher found: " + str(launcher))
		print("Auto-join info: " + str(launcher.get_auto_join_info()))
	else:
		print("ERROR: MultiplayerLauncher not found!")
	
	# Check GameModeManager
	var gmm = get_node_or_null("/root/GameModeManager")
	if gmm:
		print("GameModeManager found: " + str(gmm))
		print("Game mode: " + str(gmm.get_current_game_mode()))
		print("Is multiplayer active: " + str(gmm.is_multiplayer_active()))
	else:
		print("ERROR: GameModeManager not found!")
	
	# Wait and check connection status
	await get_tree().create_timer(5.0).timeout
	
	print("=== 5 SECONDS LATER ===")
	if gmm:
		print("Game status: " + str(gmm.get_game_status()))
		print("Multiplayer status: " + str(gmm.get_multiplayer_status()))
	
	print("=== END DEBUG ===")