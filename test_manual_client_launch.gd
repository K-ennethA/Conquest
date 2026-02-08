extends Node

# Manual test script to launch a client instance
# Run this from the host to test client launching

func _ready() -> void:
	print("=== MANUAL CLIENT LAUNCH TEST ===")
	
	# Wait a moment for the scene to load
	await get_tree().create_timer(2.0).timeout
	
	print("Starting manual client launch test...")
	
	# Get the executable path
	var executable_path = OS.get_executable_path()
	print("Executable path: " + executable_path)
	
	# Check if we're in editor
	var is_editor = OS.is_debug_build() and executable_path.ends_with("Godot_v4.6-stable_win64.exe")
	print("Running in editor: " + str(is_editor))
	
	var arguments = []
	
	if is_editor:
		# When running in editor, we need to launch Godot with the project path
		var project_path = ProjectSettings.globalize_path("res://")
		print("Project path: " + project_path)
		
		arguments = [
			"--path", project_path,
			"--multiplayer-auto-join",
			"--multiplayer-address=127.0.0.1",
			"--multiplayer-port=8910",
			"--multiplayer-player-name=Test Client"
		]
	else:
		arguments = [
			"--multiplayer-auto-join",
			"--multiplayer-address=127.0.0.1",
			"--multiplayer-port=8910",
			"--multiplayer-player-name=Test Client"
		]
	
	print("Launch arguments: " + str(arguments))
	
	# Launch the client
	print("Launching client instance...")
	var pid = OS.create_process(executable_path, arguments)
	
	if pid > 0:
		print("Client launched successfully with PID: " + str(pid))
	else:
		print("Failed to launch client instance")
	
	print("=== END MANUAL CLIENT LAUNCH TEST ===")