extends Node
class_name DedicatedServer

## Headless DEDICATED SERVER driver (no seat, no window).
##
## Started by [code]GameModeManager[/code] when the process was launched with
## [code]-- --server[/code] (or is an export carrying the [code]dedicated_server[/code]
## feature tag):
##
##   godot --headless --path . -- --server --port 8910 \
##         [--map res://game/maps/resources/default_skirmish.tres] \
##         [--turn-system traditional|speed_first] [--rng all|server] \
##         [--max-matches N] [--end-after-actions N] [--transport enet] \
##         [--reveal-timeout SECONDS]
##
## It hosts [NetSession] in dedicated mode: the first two clients are seated as
## slots 0 and 1, ready up, and the match auto-starts. The battle runs through
## the SAME GameWorld scene as a client (rendered by the headless dummy
## renderer; nothing is drawn, nothing waits for input), so the server applies
## accepted actions with exactly the same systems -- tile effects, turn ticks,
## deaths, win conditions -- as the players do, and its checkpoints are the
## authority for desync detection. When the match is decided (or a seat drops,
## or randomness verification fails) the server tells the clients, drops them,
## unloads the battle and reopens an empty lobby for the next pair.
##
## Lobby leader: --map (and --turn-system) LOCK the config. Without --map the
## slot-0 client is the lobby leader and picks map + turn system from its lobby
## screen; the server sanitises what it receives. Either way only maps
## [method MapCatalog.network_eligible] accepts are played: an offline-only map
## (AI neutral faction / AI-driven Siege creeps) is refused at --map and dropped
## from a leader pick.

const DEFAULT_MAP := "res://game/maps/resources/default_skirmish.tres"
## Seconds the finished battle stays loaded before the server closes the match
## (lets the clients apply the final action + show their end screen).
const FINISH_GRACE_MS := 1500

var port: int = NetSessionNode.DEFAULT_PORT
var max_matches: int = 0          # 0 = run forever
var end_after_actions: int = 0    # 0 = play to the end (test/benchmark knob)
var matches_done: int = 0

var _ns: NetSessionNode = null
var _finish_at: int = -1
var _in_match: bool = false
var _last_seq: int = 0   # survives NetSession's reset when a match is aborted


## Parse [param args] (OS.get_cmdline_user_args()) and start listening.
func start(args: PackedStringArray, session: NetSessionNode) -> Error:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the game-over screen pauses the tree
	_ns = session
	var opts := parse_args(args)
	port = int(opts.get("port", NetSessionNode.DEFAULT_PORT))
	max_matches = int(opts.get("max_matches", 0))
	end_after_actions = int(opts.get("end_after_actions", 0))
	var transport_id := String(opts.get("transport", "enet"))
	var t := NetTransport.create(transport_id)
	if t == null:
		_log("unknown transport '%s' (available: %s)" % [transport_id, ", ".join(NetTransport.available())])
		return ERR_INVALID_PARAMETER
	_ns.transport = t
	if opts.has("reveal_timeout"):
		_ns.reveal_timeout_ms = int(float(opts["reveal_timeout"]) * 1000.0)
	var cfg := {}
	if opts.has("map"):
		cfg["map_path"] = String(opts["map"])
		if not ResourceLoader.exists(cfg["map_path"]):
			_log("map not found: %s" % cfg["map_path"])
			return ERR_FILE_NOT_FOUND
		# Only maps a two-seat, AI-free network match can run (MapCatalog.network_refusal):
		# refuse an offline-only map (an AI neutral faction, AI-driven Siege creeps) up front
		# rather than seat two players on a battle that would stall mid-match.
		var refusal := MapCatalog.network_refusal(cfg["map_path"])
		if refusal != "":
			_log("map refused for network play: %s -- %s (%s)" % [cfg["map_path"],
				MapCatalog.describe_network_refusal(refusal), refusal])
			return ERR_INVALID_PARAMETER
	if opts.has("turn_system"):
		cfg["turn_system"] = int(opts["turn_system"])
	cfg["auto_end_turn"] = true
	var mode := NetSessionNode.RngMode.SERVER_ONLY if String(opts.get("rng", "all")) == "server" \
		else NetSessionNode.RngMode.ALL
	var err := _ns.host_dedicated(port, cfg, mode)
	if err != OK:
		_log("could not listen on %d: %s" % [port, error_string(err)])
		return err
	_ns.max_actions = end_after_actions
	_ns.player_joined.connect(func(pid, slot, pname): _log("seated '%s' (peer %d) in slot %d" % [pname, pid, slot]))
	_ns.player_left.connect(func(pid, slot): _log("peer %d (slot %d) left" % [pid, slot]))
	_ns.match_started.connect(_on_match_started)
	_ns.action_applied.connect(func(a, _r): _last_seq = int(a.get(NetProtocol.KEY_SEQ, 0)))
	_ns.match_aborted.connect(_on_match_aborted)
	_ns.cheat_detected.connect(func(pid, reason): _log("RANDOMNESS VERIFICATION FAILED: peer %d (%s)" % [pid, reason]))
	if PlayerManager:
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
	_log("dedicated server listening on %s:%d  map=%s  turn_system=%s  rng=%s%s" % [
		t.id(), port, cfg.get("map_path", "<lobby leader>"),
		cfg.get("turn_system", "<lobby leader>"), "server" if mode == NetSessionNode.RngMode.SERVER_ONLY else "all",
		"" if max_matches == 0 else "  max_matches=%d" % max_matches])
	return OK


## --key value / --flag parsing into a Dictionary with snake_case keys.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var a := String(args[i])
		if a.begins_with("--"):
			var key := a.substr(2).replace("-", "_")
			var eq := key.find("=")
			if eq >= 0:
				out[key.substr(0, eq)] = key.substr(eq + 1)
			elif i + 1 < args.size() and not String(args[i + 1]).begins_with("--"):
				out[key] = String(args[i + 1])
				i += 1
			else:
				out[key] = true
		i += 1
	if out.has("turn_system"):
		out["turn_system"] = turn_system_from_string(String(out["turn_system"]))
	return out


static func turn_system_from_string(s: String) -> int:
	match s.to_lower():
		"traditional", "trad", "0":
			return TurnSystemBase.TurnSystemType.TRADITIONAL
		"speed_first", "speed", "initiative", "1":
			return TurnSystemBase.TurnSystemType.INITIATIVE
	return TurnSystemBase.TurnSystemType.TRADITIONAL


const HEARTBEAT_MS := 60000
var _next_heartbeat: int = 0


func _process(_delta: float) -> void:
	if _ns == null:
		return
	# A liveness line for server logs / container health checks.
	if Time.get_ticks_msec() >= _next_heartbeat:
		_next_heartbeat = Time.get_ticks_msec() + HEARTBEAT_MS
		_log("heartbeat state=%s players=%d seq=%d matches_done=%d" % [
			NetSessionNode.State.keys()[_ns.state], _ns.player_count(), _ns.last_applied_seq(), matches_done])
	if not _in_match or _ns == null or not _ns.is_in_match():
		return
	if _finish_at < 0 and end_after_actions > 0 and _ns.last_applied_seq() >= end_after_actions \
			and not _ns.has_pending_actions():
		_finish_at = Time.get_ticks_msec() + 300
	if _finish_at >= 0 and Time.get_ticks_msec() >= _finish_at:
		_finish_match("match_complete")


func _on_match_started(config: Dictionary) -> void:
	_in_match = true
	_finish_at = -1
	_last_seq = 0
	_log("match %d starting: %s, turn system %d, players %s, rng contributors %s" % [
		matches_done + 1, config.get("map_path", DEFAULT_MAP), int(config.get("turn_system", 0)),
		str(config.get("slots", {})), str(config.get("rng_contributors", []))])


func _on_game_state_changed(state) -> void:
	if _in_match and state == PlayerManager.GameState.FINISHED and _finish_at < 0:
		_finish_at = Time.get_ticks_msec() + FINISH_GRACE_MS


func _finish_match(reason: String) -> void:
	_log_final(reason)
	_ns.end_match(reason)   # tells the clients, drops them, reopens the lobby
	_after_match()


func _on_match_aborted(reason: String) -> void:
	if not _in_match:
		return
	_log_final(reason)
	# NetSession already told the clients and reset to an empty lobby.
	_after_match()


func _log_final(reason: String) -> void:
	var rules = GameModeManager.get_rules() if GameModeManager else null
	var digest: int = int(rules.state_digest()) if rules != null else 0
	_log("FINAL match=%d reason=%s seq=%d digest=%d" % [matches_done + 1, reason, _last_seq, digest])


func _after_match() -> void:
	_in_match = false
	_finish_at = -1
	matches_done += 1
	if GameModeManager:
		GameModeManager.reset_server_match()
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	get_tree().paused = false
	if max_matches > 0 and matches_done >= max_matches:
		_log("served %d match(es); exiting" % matches_done)
		# Give the goodbye packets a moment to flush.
		await get_tree().create_timer(0.7).timeout
		_ns.leave()
		get_tree().quit(0)
		return
	_log("lobby open for the next match")


func _log(msg: String) -> void:
	print("[server] ", msg)
