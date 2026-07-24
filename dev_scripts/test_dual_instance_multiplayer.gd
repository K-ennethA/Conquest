extends Node

# Test script for dual-instance multiplayer functionality
# Tests launching host + client automatically

func _ready() -> void:
	print("=== Dual Instance Multiplayer Test ===")
	
	# Add some debug info
	print("Command line args: " + str(OS.get_cmdline_args()))
	print("Auto-join enabled: " + str(MultiplayerLauncher.is_auto_join_enabled()))
	
	if MultiplayerLauncher.is_auto_join_enabled():
		var info = MultiplayerLauncher.get_auto_join_info()
		print("Auto-join info: " + str(info))
	
	print("=== Test Ready ===")

# Test input handling
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_T:
				_test_dual_instance()
			KEY_H:
				_print_help()

func _test_dual_instance() -> void:
	"""Test launching dual instances"""
	print("\n--- Testing Dual Instance Launch ---")
	
	# Simulate what the NetworkMultiplayerSetup does
	var executable_path = OS.get_executable_path()
	print("Executable path: " + executable_path)
	
	var arguments = [
		"--multiplayer-auto-join",
		"--multiplayer-address=127.0.0.1",
		"--multiplayer-port=8910",
		"--multiplayer-player-name=Test Client"
	]
	
	print("Launching with arguments: " + str(arguments))
	
	var pid = OS.create_process(executable_path, arguments)
	if pid > 0:
		print("✓ Client instance launched with PID: " + str(pid))
	else:
		print("✗ Failed to launch client instance")

func _print_help() -> void:
	"""Print help information"""
	print("\n=== Dual Instance Test Controls ===")
	print("T - Test launching dual instance")
	print("H - Show this help")
	print("=====================================\n")