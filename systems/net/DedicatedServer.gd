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
##         [--reveal-timeout SECONDS] [--turn-clock rapid|standard|relaxed]
##         [--afk-limit N] [--turn-clock-ms MS]
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
##
## TURN CLOCK (every online match has one; see NetTurnClock): the server is the clock's
## authority. --turn-clock FIXES the preset (the leader's pick is ignored; without it the
## leader picks, default Standard); --afk-limit sets how many consecutive expiries forfeit
## (default 3, 0 = never); --turn-clock-ms (testing) gives every timed turn that many ms.

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
## --mode duel: this server runs online DUELS (NetProtocol.MODE_DUEL lobbies).
var duel: bool = false
## Duel lobby: each seat's announced pick {slot: [character_id, ...]} (lead first).
var _picks: Dictionary = {}
## Timeouts the clock played this match (logged on the FINAL line).
var _timeouts: int = 0


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
	if opts.has("turn_clock"):
		if not NetTurnClock.is_preset(String(opts["turn_clock"]).to_lower()):
			_log("unknown --turn-clock '%s' (use %s)" % [str(opts["turn_clock"]), " | ".join(NetTurnClock.PRESET_IDS)])
			return ERR_INVALID_PARAMETER
		_ns.turn_clock_preset = String(opts["turn_clock"]).to_lower()
		_ns.turn_clock_locked = true
	if opts.has("afk_limit"):
		_ns.afk_limit = NetTurnClock.normalise_afk_limit(int(opts["afk_limit"]))
	if opts.has("turn_clock_ms"):
		_ns.turn_clock_override_ms = maxi(0, int(opts["turn_clock_ms"]))
	var cfg := {}
	duel = String(opts.get("mode", NetProtocol.MODE_CONQUEST)) == NetProtocol.MODE_DUEL
	_ns.lobby_mode = NetProtocol.MODE_DUEL if duel else NetProtocol.MODE_CONQUEST
	if duel:
		# An online DUEL lobby: no map. --stage / --weather / --duel-format (singles | trio |
		# full) lock those; each seat picks its team (lobby message DuelNetConfig.MSG_PICK) and the
		# picks ride the auto-start.
		for key in [["stage", DuelNetConfig.KEY_STAGE], ["weather", DuelNetConfig.KEY_WEATHER]]:
			if opts.has(key[0]):
				cfg[key[1]] = String(opts[key[0]])
		if opts.has("duel_format"):
			var fcfg := DuelNetConfig.format_config(String(opts["duel_format"]))
			if fcfg.is_empty():
				_log("unknown duel format: %s (singles | trio | full)" % String(opts["duel_format"]))
				return ERR_INVALID_PARAMETER
			cfg[DuelNetConfig.KEY_FORMAT] = fcfg
		var clean := DuelNetConfig.sanitize(cfg)
		if clean.size() != cfg.size():
			_log("unknown duel stage / weather: %s" % str(cfg))
			return ERR_INVALID_PARAMETER
		cfg = clean
	elif opts.has("map"):
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
	if opts.has("turn_system") and not duel:
		cfg["turn_system"] = int(opts["turn_system"])
	if not duel:
		cfg["auto_end_turn"] = true
	var mode := NetSessionNode.RngMode.SERVER_ONLY if String(opts.get("rng", "all")) == "server" \
		else NetSessionNode.RngMode.ALL
	var err := _ns.host_dedicated(port, cfg, mode)
	if err != OK:
		_log("could not listen on %d: %s" % [port, error_string(err)])
		return err
	if duel and (cfg.has(DuelNetConfig.KEY_STAGE) or cfg.has(DuelNetConfig.KEY_FORMAT)):
		_ns.config_locked = true
	if duel:
		_ns.lobby_message.connect(_on_lobby_message)
		_ns.player_left.connect(func(_pid, slot): _picks.erase(slot))
		# The teams are sized for the lobby's CURRENT format (the operator's, or the leader's pick).
		_ns.auto_start_config = func() -> Dictionary:
			var lobby_cfg := _ns.get_match_config()
			var f: DuelFormat = DuelNetConfig.format_of(lobby_cfg) if lobby_cfg.has(DuelNetConfig.KEY_FORMAT) else null
			return DuelNetConfig.final_config(_picks, "", "", f)
	_ns.max_actions = end_after_actions
	_ns.player_joined.connect(func(pid, slot, pname): _log("seated '%s' (peer %d) in slot %d" % [pname, pid, slot]))
	_ns.player_left.connect(func(pid, slot): _log("peer %d (slot %d) left" % [pid, slot]))
	_ns.match_started.connect(_on_match_started)
	_ns.action_applied.connect(func(a, _r): _last_seq = int(a.get(NetProtocol.KEY_SEQ, 0)))
	_ns.match_aborted.connect(_on_match_aborted)
	_ns.cheat_detected.connect(func(pid, reason): _log("RANDOMNESS VERIFICATION FAILED: peer %d (%s)" % [pid, reason]))
	_ns.turn_timed_out.connect(func(slot, _a, strikes):
		_timeouts += 1
		_log("turn clock ran out for slot %d (strike %d)" % [slot, strikes]))
	_ns.clock_forfeit.connect(func(slot): _log("slot %d forfeits on time" % slot))
	if PlayerManager:
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
	if duel:
		_log("dedicated DUEL server listening on %s:%d  format=%s  stage=%s  weather=%s  rng=%s%s" % [
			t.id(), port, DuelNetConfig.format_of(cfg).summary() if cfg.has(DuelNetConfig.KEY_FORMAT) else "<lobby leader>",
			cfg.get(DuelNetConfig.KEY_STAGE, "<lobby leader>"),
			cfg.get(DuelNetConfig.KEY_WEATHER, "<lobby leader>"),
			"server" if mode == NetSessionNode.RngMode.SERVER_ONLY else "all",
			"" if max_matches == 0 else "  max_matches=%d" % max_matches])
		return OK
	_log("dedicated server listening on %s:%d  map=%s  turn_system=%s  rng=%s%s" % [
		t.id(), port, cfg.get("map_path", "<lobby leader>"),
		cfg.get("turn_system", "<lobby leader>"), "server" if mode == NetSessionNode.RngMode.SERVER_ONLY else "all",
		"" if max_matches == 0 else "  max_matches=%d" % max_matches])
	return OK


## Duel lobby: a seat announced its pick (untrusted -- whitelisted here and at the start by
## DuelNetConfig, and re-validated by every peer): its team preference list, else its lead.
func _on_lobby_message(message_type: String, data: Dictionary, from_slot: int) -> void:
	if message_type != DuelNetConfig.MSG_PICK or from_slot < 0 or from_slot > 1:
		return
	var team := DuelNetConfig.clean_team(data.get("team", []))
	if team.is_empty():
		team = DuelNetConfig.clean_team(data.get("character_id", ""))
	if not team.is_empty():
		_picks[from_slot] = team


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
	# An online duel is decided by its own rules (a KO), not PlayerManager's game state.
	var rules = GameModeManager.get_rules() if GameModeManager else null
	if _finish_at < 0 and rules != null and rules.has_method("is_match_over") and rules.is_match_over() \
			and not _ns.has_pending_actions():
		_finish_at = Time.get_ticks_msec() + FINISH_GRACE_MS
	if _finish_at >= 0 and Time.get_ticks_msec() >= _finish_at:
		_finish_match("match_complete")


func _on_match_started(config: Dictionary) -> void:
	_in_match = true
	_finish_at = -1
	_last_seq = 0
	_timeouts = 0
	_log("turn clock: %s (%s), forfeit after %d consecutive expiries" % [
		NetTurnClock.label(config.get(NetTurnClock.CONFIG_PRESET, "")),
		NetTurnClock.describe(config.get(NetTurnClock.CONFIG_PRESET, "")) if _ns.turn_clock_override_ms <= 0 \
			else "%d ms per timed turn (test override)" % _ns.turn_clock_override_ms,
		int(config.get(NetTurnClock.CONFIG_AFK_LIMIT, 0))])
	if DuelNetConfig.is_duel(config):
		_log("match %d starting: DUEL %s, %s vs %s on %s, players %s, rng contributors %s" % [
			matches_done + 1, DuelNetConfig.format_of(config).summary(),
			",".join(DuelNetConfig.team_of(config, 0)), ",".join(DuelNetConfig.team_of(config, 1)),
			String(config.get(DuelNetConfig.KEY_STAGE, DuelNetConfig.DEFAULT_STAGE)),
			str(config.get("slots", {})), str(config.get("rng_contributors", []))])
		return
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
	_log("FINAL match=%d reason=%s seq=%d digest=%d timeouts=%d" % [matches_done + 1, reason, _last_seq, digest, _timeouts])


func _after_match() -> void:
	_in_match = false
	_finish_at = -1
	_picks.clear()
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
