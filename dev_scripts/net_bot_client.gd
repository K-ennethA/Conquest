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
##
## ONLINE DUEL: add [code]--mode duel [--unit <character_id>] [--team a,b,c][/code] (every bot of
## the match, and the dedicated server's [code]--mode duel [--duel-format trio][/code]). The bot
## announces its team preference on the lobby channel (DuelNetConfig.MSG_PICK) before readying
## (default: the seat's default Full-party order, which the start trims to the format); a hosting
## bot sets [code]--duel-format[/code] and folds both picks into the start
## ([method DuelNetConfig.final_config]). On its turn it submits what the duel brain
## ([method DuelBattle.decide_for], NORMAL -- deterministic; it switches on a bad matchup) would
## pick (a forced WAIT is left to the seat's NetDuelStage); every [constant SWITCH_EVERY]th own action it switches to its first
## healthy bench member when it can (so SWITCH rides every multi-process run); after a faint it
## submits the brain's KO replacement pick.
##
## TURN CLOCK: the bot respects the host's clock -- when little time is left on its own clock
## ([constant CLOCK_MARGIN_MS]) it plays the safe move (end the turn / wait / the canonical
## auto-pick) instead of deliberating. [code]--idle-turns N[/code] makes it sit out its first N
## timed turns so the HOST times it out (the idle-bot check); [code]--idle-picks N[/code] makes a
## duel bot also sit out its first N KO replacement picks (the host then auto-picks for it -- a
## timeout-stamped SWITCH). A hosting bot also takes [code]--turn-clock
## rapid|standard|relaxed[/code], [code]--turn-clock-ms MS[/code] and [code]--afk-limit N[/code].
## The FINAL line counts the timeouts applied in the match ([code]timeouts=K[/code]) and the
## timed-out KO replacement picks among them ([code]autopicks=K[/code]).

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
var _was_in_match := false
## --mode duel: an online-duel bot.
var _duel := false
## --unit: this bot's duel lead ("" = the slot's default).
var _unit := ""
## --team a,b,c: this bot's team preference (overrides --unit).
var _team: Array = []
## --duel-format (a hosting bot): the format it sets for the lobby.
var _format_id := ""
## Hosting duel bot: the seats' announced teams {slot: [ids]}.
var _picks: Dictionary = {}
## --idle-turns: timed turns of ours still to sit out (the host times them out).
var _idle_turns := 0
## The clock key we are sitting out ("" = none).
var _idle_key := ""
## --idle-picks (duel): KO replacement picks of ours still to sit out (the host auto-picks).
var _idle_picks := 0
## Timeouts applied in this match (any seat), and the timed-out KO picks among them.
var _timeouts := 0
var _autopicks := 0
## Play the safe move when our own clock has less than this left.
const CLOCK_MARGIN_MS := 1200
## Duel actions this bot submitted (drives the periodic switch).
var _duel_actions := 0
## A duel bot switches (when it legally can) on every Nth of its own actions.
const SWITCH_EVERY := 4


func start(args: PackedStringArray) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep reporting after the game-over pause
	var opts := DedicatedServer.parse_args(args)
	bot_name = String(opts.get("name", "Bot"))
	_ns = get_node("/root/NetSession")
	_duel = String(opts.get("mode", NetProtocol.MODE_CONQUEST)) == NetProtocol.MODE_DUEL
	_unit = String(opts.get("unit", ""))
	_idle_turns = maxi(0, int(opts.get("idle_turns", 0)))
	_idle_picks = maxi(0, int(opts.get("idle_picks", 0)))
	_ns.turn_timed_out.connect(func(slot, a, strikes):
		_timeouts += 1
		var pick: bool = int(a.get(NetProtocol.KEY_TYPE, -1)) == NetProtocol.Action.SWITCH
		if pick:
			_autopicks += 1
		_log("timeout: slot %d ran out of time (strike %d)%s" % [slot, strikes,
			" -- auto-picked %s" % String(a.get(NetProtocol.KEY_DATA, {}).get(NetProtocol.K_UNIT, "")) if pick else ""]))
	if opts.has("team"):
		_team = DuelNetConfig.clean_team(Array(String(opts["team"]).split(",", false)))
	_format_id = String(opts.get("duel_format", ""))
	_ns.lobby_mode = NetProtocol.MODE_DUEL if _duel else NetProtocol.MODE_CONQUEST
	_ns.lobby_message.connect(func(t, data, from_slot):
		if t == DuelNetConfig.MSG_PICK and from_slot >= 0:
			var team := DuelNetConfig.clean_team(data.get("team", []))
			_picks[from_slot] = team if not team.is_empty() else DuelNetConfig.clean_team(data.get("character_id", "")))
	_ns.joined.connect(func(slot):
		_log("seated in slot %d" % slot)
		if _duel:
			_announce_pick(slot)
		_ns.set_ready(true))
	_ns.join_rejected.connect(func(reason, _info): _finish("rejected:" + reason))
	_ns.connection_failed.connect(func(): _finish("connection_failed"))
	_ns.match_started.connect(func(cfg):
		_was_in_match = true
		_log("match started (setup seed %d)" % int(cfg.get("seed", 0))))
	# A duel seat can act twice running (a KO replacement pick, then its turn), so it waits for
	# ITS OWN action to land before choosing again (another seat's apply says nothing about it).
	_ns.action_applied.connect(func(a, _r):
		if not _duel or int(a.get(NetProtocol.KEY_ACTOR, -1)) == _ns.local_slot():
			_busy = false)
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
		_ns.turn_clock_preset = NetTurnClock.normalise_preset(opts.get("turn_clock", NetTurnClock.DEFAULT_PRESET))
		_ns.turn_clock_override_ms = int(opts.get("turn_clock_ms", 0))
		if opts.has("afk_limit"):
			_ns.afk_limit = NetTurnClock.normalise_afk_limit(int(opts["afk_limit"]))
		err = _ns.host_game(bot_name, port)
		if err == OK:
			if _duel:
				if _format_id != "":
					_ns.set_match_config({DuelNetConfig.KEY_FORMAT: DuelNetConfig.format_config(_format_id)})
				_announce_pick(0)
			else:
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
		_ns.start_match(_duel_final_config() if _duel else {})
	if not _ns.is_in_match():
		# The game itself closed the session after the match started (e.g. every peer
		# refused an offline-only map: GameModeManager.apply_match_config) -- report it
		# instead of idling until the harness times out.
		if _was_in_match and not _ns.is_active():
			_finish("session_closed: %s" % GameModeManager.pending_menu_message)
		return
	var decided: bool = PlayerManager.current_game_state == PlayerManager.GameState.FINISHED
	var live_rules = GameModeManager.get_rules()
	if live_rules != null and live_rules.has_method("is_match_over"):
		decided = live_rules.is_match_over()   # an online duel ends on its own KO
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
	if _sitting_out():
		return
	var intent := _choose(rules, _ns.local_slot())
	# Respect the clock: with (almost) no time left, play the safe move rather than deliberate.
	var left := _ns.turn_clock_remaining_ms()
	if left >= 0 and left < CLOCK_MARGIN_MS and _ns.turn_clock_slot() == _ns.local_slot():
		var safe: Dictionary = rules.timeout_action(_ns.local_slot()) if rules.has_method("timeout_action") else {}
		if not safe.is_empty() and rules.validate_intent(safe, _ns.local_slot()) == "":
			intent = safe
	if intent.is_empty():
		return
	_busy = true
	_ns.submit_intent(intent)


## --idle-turns: true while we sit out the current timed turn of ours (the host will time it
## out). Each new clock of ours spends one idle turn until none are left.
func _sitting_out() -> bool:
	var clock: Dictionary = _ns.turn_clock()
	if clock.is_empty() or int(clock.get("slot", -1)) != _ns.local_slot():
		return false
	var key := "%s@%d" % [String(clock.get("key", "")), int(clock.get("seq", 0))]
	if key == _idle_key:
		return true
	# A duel KO replacement pick has its own clock (DuelNetRules.clock_kind "pick"): --idle-picks.
	if String(clock.get("kind", "")) == NetTurnClock.KIND_PICK:
		if _idle_picks <= 0:
			return false
		_idle_picks -= 1
		_idle_key = key
		_log("idling through this KO replacement pick (%d more to sit out)" % _idle_picks)
		return true
	if _idle_turns <= 0:
		return false
	_idle_turns -= 1
	_idle_key = key
	_log("idling through this turn (%d more to sit out)" % _idle_turns)
	return true


## Hosting duel bot: both teams for the lobby's format (the one --duel-format set, else Singles).
func _duel_final_config() -> Dictionary:
	var cfg := _ns.get_match_config()
	var f: DuelFormat = DuelNetConfig.format_of(cfg) if cfg.has(DuelNetConfig.KEY_FORMAT) else null
	return DuelNetConfig.final_config(_picks, "", "", f)


## Duel bot: announce this seat's team preference on the lobby channel (and remember our own).
func _announce_pick(slot: int) -> void:
	var team: Array = _team.duplicate()
	if team.is_empty():
		var lead := _unit if DuelNetConfig.is_eligible(_unit) else DuelNetConfig.default_unit(slot)
		team = DuelNetConfig.fill_team([lead], slot, DuelFormat.preset(DuelFormat.FULL))
	_picks[slot] = team
	_log("duel pick: %s" % ",".join(team))
	_ns.send_lobby_message(DuelNetConfig.MSG_PICK, {"character_id": String(team[0]), "team": team})


## Duel bot: the brain's pick for our combatant (NORMAL is deterministic), else the first legal
## slot; a stunned / controlled combatant passes.
func _choose_duel(rules: DuelNetRules, me: int) -> Dictionary:
	var b: DuelBattle = rules.battle
	if b == null:
		return {}
	if b.has_pending_replacement():
		# Our combatant fainted: the brain's KO replacement pick (or nothing: the other seat picks).
		return rules.default_intent(me)
	var actor = b.current_actor()
	if actor == null or b.side_of(actor) != me:
		return {}
	if b.must_pass(actor):
		# The seat's NetDuelStage submits its forced pass by itself (a second WAIT would be refused).
		return {}
	_duel_actions += 1
	var decision := b.decide_for(actor)
	if _duel_actions % SWITCH_EVERY == 0 and b.can_switch(actor) and not decision.has("switch"):
		decision = {"switch": b.usable_bench(me)[0]}
	if decision.has("switch"):
		var sw := rules.switch_intent(int(decision["switch"]))
		if rules.validate_intent(sw, me) == "":
			_log("switch -> %s" % String(sw[NetProtocol.KEY_DATA][NetProtocol.K_UNIT]))
			return sw
	var intent := rules.use_move_intent(int(decision.get("slot", DuelBrain.NO_SLOT)))
	if rules.validate_intent(intent, me) != "":
		var legal := b.legal_slots(actor)
		intent = rules.use_move_intent(legal[0]) if not legal.is_empty() else {}
	return intent if not intent.is_empty() and rules.validate_intent(intent, me) == "" else {}


func _choose(rules: NetGameRules, me: int) -> Dictionary:
	if rules is DuelNetRules:
		return _choose_duel(rules as DuelNetRules, me)
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
	_log("FINAL reason=%s seq=%d digest=%d desyncs=%d timeouts=%d autopicks=%d" % [str(reason), _last_seq, _last_digest, _desyncs, _timeouts, _autopicks])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(2 if bad else 0)


func _log(msg: String) -> void:
	print("[net-bot %s] %s" % [bot_name, msg])
