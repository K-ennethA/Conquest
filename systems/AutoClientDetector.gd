extends RefCounted
class_name AutoClientDetector

## Dev helper: spawn a SECOND game instance that auto-joins this one as a client --
## the "Host + Auto Client" button of the network setup screen (dev-gated there).
##
## The spawned process is told what to do on its COMMAND LINE
## ([code]-- --multiplayer-auto-join --multiplayer-port N ...[/code], handled by the
## MultiplayerLauncher autoload), so a normal launch can never be turned into a client.
## (This used to be an autoload that watched for a user://auto_client.flag file; a
## leftover flag turned the next ordinary launch into a client, so that mechanism is
## gone -- MultiplayerLauncher deletes such a file on sight.)
##
## For two instances without this button: Godot's Debug > Customize Run Instances (2),
## or [code]dev_scripts/net_multiprocess_check.sh[/code] for headless bots.

## Launch a client instance that joins 127.0.0.1:[param port] as [param player_name].
## Returns true when the process was started.
static func launch_client(port: int = NetSessionNode.DEFAULT_PORT, player_name: String = "Client Player") -> bool:
	var executable_path := OS.get_executable_path()
	var arguments: PackedStringArray = PackedStringArray()
	if not OS.has_feature("template"):   # an editor / source run needs the project path
		arguments.append("--path")
		arguments.append(ProjectSettings.globalize_path("res://"))
	arguments.append("--")
	arguments.append("--multiplayer-auto-join")
	arguments.append("--multiplayer-address=127.0.0.1")
	arguments.append("--multiplayer-port=%d" % port)
	arguments.append("--multiplayer-player-name=%s" % player_name)
	var pid := OS.create_process(executable_path, arguments)
	if pid <= 0:
		push_warning("AutoClientDetector: failed to launch a client instance")
		return false
	print("[HOST] Client instance launched (PID %d): %s" % [pid, " ".join(arguments)])
	return true
