extends Node

# Simple script to force client debugging
# Attach this to MainMenu scene as a child node

func _ready() -> void:
	print("=== FORCE CLIENT DEBUG ===")
	
	# Wait a moment for everything to initialize
	await get_tree().create_timer(0.5).timeout
	
	# Check command line arguments
	var args = OS.get_cmdline_args()
	print("Command line args: " + str(args))
	
	# Check for auto-join flag
	var has_auto_join = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			has_auto_join = true
			break
	
	print("Has auto-join flag: " + str(has_auto_join))
	
	if has_auto_join:
		print("*** CLIENT INSTANCE DETECTED ***")
		
		# Check MultiplayerLauncher
		var launcher = MultiplayerLauncher
		if launcher:
			print("MultiplayerLauncher found")
			print("Is auto-join enabled: " + str(launcher.is_auto_join_enabled()))
			
			if not launcher.is_auto_join_enabled():
				print("Auto-join not enabled - forcing manual parsing...")
				launcher._parse_command_line_args()
				print("After parsing - enabled: " + str(launcher.is_auto_join_enabled()))
				
				if launcher.is_auto_join_enabled():
					print("Manually triggering auto-join...")
					launcher._auto_join_multiplayer()
				else:
					print("Still not enabled - forcing it...")
					launcher.force_auto_join()
			else:
				print("Auto-join already enabled")
		else:
			print("ERROR: MultiplayerLauncher not found!")
	else:
		print("*** HOST INSTANCE ***")
	
	print("=== END FORCE CLIENT DEBUG ===")

# Add keyboard shortcut for manual testing
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F9:
			print("F9 pressed - Forcing client test...")
			_ready()