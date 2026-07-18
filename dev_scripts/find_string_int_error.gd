extends Node

# Script to help identify String + int concatenation errors
# Add this as an autoload to track all errors

func _ready():
	print("=== STRING + INT ERROR TRACKER ACTIVE ===")
	print("This will help identify where the error occurs")
	
	# Enable verbose error reporting
	ProjectSettings.set_setting("debug/gdscript/warnings/enable", true)
	ProjectSettings.set_setting("debug/gdscript/warnings/treat_warnings_as_errors", false)

func _process(_delta):
	# Check for errors in the output
	pass

# Helper function to safely convert to int
static func safe_int(value) -> int:
	if value is String:
		print("[SAFE_INT] Converting String '%s' to int" % value)
		return int(value)
	elif value is int:
		return value
	else:
		print("[SAFE_INT] WARNING: Unexpected type %s, value: %s" % [typeof(value), str(value)])
		return int(value)

# Helper function to safely format player display
static func safe_player_display(player_id) -> String:
	var id_int = safe_int(player_id)
	return "Player " + str(id_int + 1)
