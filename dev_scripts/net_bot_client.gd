extends Node

## DEV / CI: a scripted headless network client, for multi-process checks of the
## network stack (see dev_scripts/net_multiprocess_check.sh and
## systems/net/README.md). Launched by GameModeManager for
##
##   godot --headless --path . -- --net-bot --connect 127.0.0.1 --port 8910 --name BotA
##
## or, as a PLAYER-HOST (listen server, seat 0; starts once the other bot is ready):
##
##   godot --headless --path . -- --net-bot --host --port 8910 --name Host \
##         [--map res://...] [--turn-system traditional] [--end-after-actions N]
##
## It joins, readies up, and -- when it is its turn -- submits one legal intent at
## a time (attack an enemy in range > move toward the nearest enemy > wait > end
## turn), chosen deterministically from its local copy of the game and
## pre-checked with the local NetGameRules.validate_intent. Every applied
## action updates its last digest; when the match ends (any reason) it prints
##   [net-bot <name>] FINAL reason=<r> seq=<n> digest=<d> desyncs=<k>
## and exits (code 0; 2 if a desync or a randomness-verification failure was seen).

var bot_name := "Bot"
var _ns: NetSessionNode = null
var _busy := false
var _rejections := 0
var _last_seq := 0
var _last_digest := 0
var _desyncs := 0
var _cheats := 0
var _done := false
var _host_map := ""
var _host_end_after := 0


func start(args: PackedStringArray) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep reporting after the game-over pause
	var opts := DedicatedServer.parse_args(args)
	bot_name = String(opts.get("name", "Bot"))
	_ns = get_node("/root/NetSession")
	_ns.joined.connect(func(slot):
		_log("seated in slot %d" % slot)
		_ns.set_ready(true))
	_ns.join_rejected.connect(func(reason): _finish("rejected:" + reason))
	_ns.connection_failed.connect(func(): _finish("connection_failed"))
	_ns.match_started.connect(func(cfg): _log("match started (setup seed %d)" % int(cfg.get("seed", 0))))
	_ns.action_applied.connect(func(_a, _r): _busy = false)
	_ns.intent_rejected.connect(func(_a, reason):
		_rejections += 1
		_log("intent rejected: %s" % reason)
		_busy = false)
	_ns.desync_detected.connect(func(_s, _l, _h): _desyncs += 1)
	_ns.cheat_detected.connect(func(_p, _r): _cheats += 1)
	_ns.match_aborted.connect(_finish)
	_ns.disconnected.connect(_finish)
	var port := int(opts.get("port", NetSessionNode.DEFAULT_PORT))
	var err: Error
	if opts.has("host"):
		# PLAYER-HOSTED: this bot is the listen server AND seat 0.
		_host_map = String(opts.get("map", "res://game/maps/resources/default_skirmish.tres"))
		err = _ns.host_game(bot_name, port)
		if err == OK:
			_ns.set_match_config({"map_path": _host_map, "turn_system": int(opts.get("turn_system", 0)), "auto_end_turn": true})
			_ns.set_ready(true)
			_host_end_after = int(opts.get("end_after_actions", 0))
	else:
		err = _ns.join_game(String(opts.get("connect", "127.0.0.1")), bot_name, port)
	if err != OK:
		_finish("join_failed")


func _process(_delta: float) -> void:
	if _done or _ns == null:
		return
	if _ns.is_host() and _ns.can_start_match():
		_ns.start_match()
	if not _ns.is_in_match():
		return
	var decided: bool = PlayerManager.current_game_state == PlayerManager.GameState.FINISHED
	if _ns.is_host() and (decided or (_host_end_after > 0 and _ns.last_applied_seq() >= _host_end_after)) \
			and not _ns.has_pending_actions() and _last_seq == _ns.last_applied_seq() \
			and GameModeManager.get_rules() != null:
		# At least one frame after the last apply: deferred turn logic has settled.
		_last_digest = GameModeManager.get_rules().state_digest()
		_ns.end_match("match_complete")
		_finish("match_complete")
		return
	var rules: NetGameRules = GameModeManager.get_rules()
	if rules == null:
		return
	# Track the settled state (the session records its digest one frame after
	# applying; by then deferred turn logic has run here too).
	_last_seq = _ns.last_applied_seq()
	_last_digest = rules.state_digest()
	# Act only when both the local turn system AND the host's last checkpoint say
	# it is our turn (avoids racing the deferred auto end-of-turn).
	if _busy or _ns.has_pending_actions() or not GameModeManager.is_my_turn() or not _ns.is_my_turn():
		return
	var intent := _choose(rules, _ns.local_slot())
	if intent.is_empty():
		return
	_busy = true
	_ns.submit_intent(intent)


func _choose(rules: NetGameRules, me: int) -> Dictionary:
	var b = rules.board()
	if b == null:
		return {}
	if _rejections > 3:
		_rejections = 0
		return NetProtocol.end_turn()
	var mine: Array = []
	var enemies: Array = []
	for u in b.all_units():
		if u == null or not is_instance_valid(u) or (u.has_method("is_alive") and not u.is_alive()):
			continue
		if NetUnitIds.id_of(u) == "":
			continue
		if NetUnitIds.owner_slot(u) == me:
			mine.append(u)
		elif NetUnitIds.owner_slot(u) >= 0:
			enemies.append(u)
	mine.sort_custom(func(x, y): return NetUnitIds.id_of(x) < NetUnitIds.id_of(y))
	enemies.sort_custom(func(x, y): return NetUnitIds.id_of(x) < NetUnitIds.id_of(y))
	for u in mine:
		var uid := NetUnitIds.id_of(u)
		# 1. Attack anything in range.
		for slot in range(4):
			for e in enemies:
				var a := NetProtocol.use_move(uid, slot, b.cell_of(e))
				if rules.validate_intent(a, me) == "":
					return a
		# 2. Step toward the nearest enemy.
		var mv := _approach(rules, b, u, enemies, me)
		if not mv.is_empty():
			return mv
		# 3. Done with this unit.
		var w := NetProtocol.wait(uid)
		if rules.validate_intent(w, me) == "":
			return w
	var et := NetProtocol.end_turn()
	return et if rules.validate_intent(et, me) == "" else {}


func _approach(rules: NetGameRules, b, u, enemies: Array, me: int) -> Dictionary:
	if enemies.is_empty() or not u.has_method("get_movement_profile"):
		return {}
	var profile = u.get_movement_profile()
	if profile == null or (u.has_method("can_move") and not u.can_move()):
		return {}
	var origin: Vector3i = b.cell_of(u)
	var best_d := _nearest(origin, b, enemies)
	var best := Vector3i(-1, -1, -1)
	var cells: Array = MovementResolver.new().reachable_cells(origin, profile, b, u)
	cells.sort()
	for c in cells:
		var d := _nearest(c, b, enemies)
		if d < best_d:
			best_d = d
			best = c
	if best == Vector3i(-1, -1, -1):
		return {}
	var a := NetProtocol.move(NetUnitIds.id_of(u), best)
	return a if rules.validate_intent(a, me) == "" else {}


static func _nearest(c: Vector3i, b, enemies: Array) -> int:
	var best := 1 << 30
	for e in enemies:
		var ec: Vector3i = b.cell_of(e)
		best = mini(best, absi(ec.x - c.x) + absi(ec.y - c.y) + absi(ec.z - c.z))
	return best


func _finish(reason = "") -> void:
	if _done:
		return
	_done = true
	var bad := _desyncs > 0 or _cheats > 0 or String(reason).contains("verification")
	_log("FINAL reason=%s seq=%d digest=%d desyncs=%d" % [str(reason), _last_seq, _last_digest, _desyncs])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(2 if bad else 0)


func _log(msg: String) -> void:
	print("[net-bot %s] %s" % [bot_name, msg])
