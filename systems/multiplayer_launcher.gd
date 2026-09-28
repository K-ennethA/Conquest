extends Node

## MultiplayerLauncher (autoload) -- the two-instances-on-one-machine DEV auto-join.
##
## A second game instance started with
##   godot --path . -- --multiplayer-auto-join [--multiplayer-address 127.0.0.1]
##         [--multiplayer-port 8910] [--multiplayer-player-name "Client Player"]
## skips the menus, opens the network setup screen and presses its Join for it
## ([method NetworkMultiplayerSetup.begin_auto_join]) -- the SAME code path a human
## takes (NetSession over localhost ENet, version handshake, collaborative lobby), so
## the harness can never drift from what ships. [AutoClientDetector.launch_client]
## spawns such an instance from the host's "Host + Auto Client" dev button.
##
## Only an EXPLICIT command-line flag turns this on. (It used to also react to a
## leftover user://auto_client.flag file, which could turn a normal launch into a
## client; that file is now deleted on sight and never acted on.)
##
## The headless roles (--server dedicated server, --net-bot scripted client) are booted
## by GameModeManager; this is only the interactive dev affordance.

const LEGACY_CLIENT_FLAG_FILE := "user://auto_client.flag"
const SETUP_SCENE := "res://menus/NetworkMultiplayerSetup.tscn"
const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
## Seconds to give the host instance to open its socket before dialling.
const HOST_GRACE_SEC := 2.0

var auto_join_enabled: bool = false
var auto_join_address: String = "127.0.0.1"
var auto_join_port: int = 8910
var auto_join_player_name: String = "Auto Client"


func _ready() -> void:
	name = "MultiplayerLauncher"
	# A stale flag file from an older build must never hijack a normal launch.
	if FileAccess.file_exists(LEGACY_CLIENT_FLAG_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_CLIENT_FLAG_FILE))
	_parse_command_line_args()
	if auto_join_enabled:
		print("[CLIENT] Auto-join enabled: %s:%d as %s" % [auto_join_address, auto_join_port, auto_join_player_name])
		call_deferred("_auto_join_multiplayer")


## Parse the auto-join flags from the user args (after "--") and, for older launch
## scripts, the engine args. Both "--flag value" and "--flag=value" forms work.
func _parse_command_line_args() -> void:
	auto_join_enabled = false
	auto_join_address = "127.0.0.1"
	auto_join_port = 8910
	auto_join_player_name = "Auto Client"
	var args: Array = []
	args.append_array(Array(OS.get_cmdline_args()))
	args.append_array(Array(OS.get_cmdline_user_args()))
	for i in range(args.size()):
		var arg := String(args[i])
		var next := String(args[i + 1]) if i + 1 < args.size() else ""
		if arg == "--multiplayer-auto-join":
			auto_join_enabled = true
		elif arg == "--multiplayer-address" and next != "":
			auto_join_address = next
		elif arg.begins_with("--multiplayer-address="):
			auto_join_address = arg.get_slice("=", 1)
		elif arg == "--multiplayer-port" and next != "":
			auto_join_port = int(next)
		elif arg.begins_with("--multiplayer-port="):
			auto_join_port = int(arg.get_slice("=", 1))
		elif arg == "--multiplayer-player-name" and next != "":
			auto_join_player_name = next
		elif arg.begins_with("--multiplayer-player-name="):
			auto_join_player_name = arg.get_slice("=", 1)
	if auto_join_port <= 0 or auto_join_port > 65535:
		auto_join_port = 8910


## Manually force the auto-join (debugging).
func force_auto_join() -> void:
	auto_join_enabled = true
	call_deferred("_auto_join_multiplayer")


func _auto_join_multiplayer() -> void:
	if get_window() != null:
		get_window().title = "CONQUEST - CLIENT INSTANCE"
	# Give the host process a moment to finish opening its socket.
	await get_tree().create_timer(HOST_GRACE_SEC).timeout
	get_tree().change_scene_to_file(SETUP_SCENE)
	# change_scene_to_file is deferred, so poll (bounded) for the new scene.
	var setup: Node = null
	for _frame in range(60):
		await get_tree().process_frame
		var current: Node = get_tree().current_scene
		if current != null and current.has_method("begin_auto_join"):
			setup = current
			break
	if setup != null:
		setup.begin_auto_join(auto_join_address, auto_join_port, auto_join_player_name)
	else:
		push_warning("MultiplayerLauncher: the network setup screen never came up (no begin_auto_join)")
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func is_auto_join_enabled() -> bool:
	return auto_join_enabled


func get_auto_join_info() -> Dictionary:
	return {
		"enabled": auto_join_enabled,
		"address": auto_join_address,
		"port": auto_join_port,
		"player_name": auto_join_player_name,
	}
