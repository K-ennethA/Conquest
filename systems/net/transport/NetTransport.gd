extends RefCounted
class_name NetTransport

## Transport abstraction for [NetSessionNode]: the ONLY place a concrete
## [MultiplayerPeer] is created. NetSession talks to Godot's high-level
## multiplayer API (RPCs, peer ids, peer_connected / disconnected), which every
## MultiplayerPeer implementation supports, so swapping ENet for Steam relay,
## WebSocket or WebRTC is a matter of adding a subclass here -- the lobby, the
## commit-reveal RNG and the rules never see the difference.
##
## Contract for implementations:
##   * [method create_host] returns a peer that is ALREADY listening / hosting and
##     has the multiplayer authority id 1 (every MultiplayerPeer server does).
##   * [method create_client] returns a peer that is connecting; NetSession waits
##     for connected_to_server / connection_failed.
##   * On failure return null and set [member last_error].
##   * [param address] / [param port] are transport-specific: ENet = IP/hostname +
##     UDP port; Steam = host SteamID64 (as a String) + virtual port; WebSocket =
##     "ws(s)://host" + TCP port; etc. The lobby UI passes them through verbatim.
##
## See systems/net/README.md ("Adding a transport").

## Error of the last failed create_* call (OK when it succeeded).
var last_error: Error = OK


## Short id used by the command line (--transport <id>) and logs.
func id() -> String:
	return "abstract"


## Open a hosting peer accepting up to [param max_clients] remote peers.
func create_host(_port: int, _max_clients: int) -> MultiplayerPeer:
	last_error = ERR_UNAVAILABLE
	return null


## Open a client peer connecting to [param address]:[param port].
func create_client(_address: String, _port: int) -> MultiplayerPeer:
	last_error = ERR_UNAVAILABLE
	return null


## Registry: transport id -> script path. Add new transports here (or register
## them at runtime with [method register]) -- nothing else in NetSession changes.
static var _registry: Dictionary = {
	"enet": "res://systems/net/transport/ENetTransport.gd",
}


static func register(transport_id: String, script_path: String) -> void:
	_registry[transport_id] = script_path


static func available() -> Array:
	return _registry.keys()


## Instantiate the transport registered as [param transport_id] (null if unknown).
static func create(transport_id: String) -> NetTransport:
	var path: String = _registry.get(transport_id, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var script = load(path)
	return script.new() if script != null else null
