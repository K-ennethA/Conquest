extends Node

## GameModeManager -- live-game glue for NETWORK versus.
##
## [NetSession] (autoload) is the transport / lobby / ordering layer and knows
## nothing about units; [NetGameRules] is the deterministic validate/apply layer.
## This autoload wires them into the running game:
##   * on [signal NetSession.match_started] it copies the host's match config into
##     [GameSettings] (map -- a custom map's shipped content is validated and
##     installed first --, turn system, player names, best-of rounds, the host's
##     squad) and loads the battle scene on every peer;
##   * [method on_network_world_ready] (called by GameWorldManager once the map,
##     players and turn system exist) builds the NetGameRules over the LIVE board
##     (CombatServices) and turn system (TurnSystemManager) and attaches it;
##   * the UI submits intents through request_move / request_use_move /
##     request_wait / request_end_turn instead of mutating state directly;
##   * an opponent leaving a live battle is a WIN for the one who stayed (the battle
##     HUD resolves it off [signal NetSession.opponent_left]); desyncs, failed
##     verification and disconnects before the battle is up end the match and return
##     to the main menu with a message; [method end_network_session] closes the
##     session and restores the local game mode so single-player / hotseat afterwards
##     is unaffected.
##
## Outside a network match every query answers like local play (local player id 0,
## always "my turn"), so hotseat and single-player code paths are unchanged.
##
## Command line (after "--"): [code]--server[/code] boots a dedicated server,
## [code]--net-bot[/code] a scripted headless client. The two-instance dev auto-join
## ([code]--multiplayer-auto-join[/code]) is handled by the MultiplayerLauncher autoload.

signal network_action_applied(action: Dictionary, result: Dictionary)
signal network_intent_rejected(action: Dictionary, reason: String)
signal network_turn_changed(slot: int)

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
## The online duel's scene (a [DuelStage] driven by the network).
const NET_DUEL_STAGE_SCENE := "res://game/duel/net/NetDuelStage.tscn"
const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

## A message for the main menu to show once (e.g. "Opponent disconnected.").
var pending_menu_message: String = ""

var _rules: NetGameRules = null
var _match_finished: bool = false
var _saved_ai_difficulty: int = -1


func _ready() -> void:
	name = "GameModeManager"
	var ns := _session()
	if ns != null:
		ns.match_started.connect(_on_match_started)
		ns.match_aborted.connect(_on_match_aborted)
		ns.action_applied.connect(_on_action_applied)
		ns.intent_rejected.connect(_on_intent_rejected)
		ns.turn_changed.connect(func(slot): network_turn_changed.emit(slot))
		ns.desync_detected.connect(_on_desync_detected)
	if PlayerManager:
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
	# Headless roles chosen on the command line (after "--"): a dedicated server
	# or (dev / CI) a scripted network client. Deferred: the main scene is not
	# in the tree yet while autoloads run _ready.
	var args := OS.get_cmdline_user_args()
	if args.has("--server") or OS.has_feature("dedicated_server"):
		call_deferred("_boot_dedicated_server", args)
	elif args.has("--net-bot"):
		call_deferred("_boot_net_bot", args)


# ---------------------------------------------------------------------------
# Headless roles
# ---------------------------------------------------------------------------

const NET_BOT_SCRIPT := "res://dev_scripts/net_bot_client.gd"

var _server: DedicatedServer = null


## True in a dedicated-server process (no seat, no menus).
func is_dedicated_server_process() -> bool:
	return _server != null


func _boot_dedicated_server(args: PackedStringArray) -> void:
	# No menus on a server: drop the main scene; battles are loaded per match.
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	_server = DedicatedServer.new()
	_server.name = "DedicatedServer"
	get_tree().root.add_child(_server)
	if _server.start(args, _session()) != OK:
		get_tree().quit(1)


func _boot_net_bot(args: PackedStringArray) -> void:
	if not ResourceLoader.exists(NET_BOT_SCRIPT):
		push_error("--net-bot: %s missing" % NET_BOT_SCRIPT)
		get_tree().quit(1)
		return
	var bot: Node = load(NET_BOT_SCRIPT).new()
	bot.name = "NetBotClient"
	get_tree().root.add_child(bot)
	bot.call("start", args)


## Dedicated server: forget the finished match (the session itself stays open).
func reset_server_match() -> void:
	_rules = null
	_match_finished = false
	if GameSettings != null and GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
		GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	if CombatServices != null:
		CombatServices.match_rng = null


func _session() -> NetSessionNode:
	return get_node_or_null("/root/NetSession") as NetSessionNode


# ---------------------------------------------------------------------------
# Queries (safe in every mode)
# ---------------------------------------------------------------------------

## True while a NETWORK match is running on this instance.
func is_multiplayer_active() -> bool:
	var ns := _session()
	return ns != null and ns.is_in_match() \
		and GameSettings != null and GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER


## The local player's slot: the seat in a network match, 0 otherwise (single
## player / hotseat), so outlines and ownership checks never inherit a stale
## network seat after a session ends. (The roster slot IS the player id: host /
## first seat = player 0, second seat = player 1.)
func get_local_player_id() -> int:
	if is_multiplayer_active():
		return _session().local_slot()
	return 0


func is_local_player(player_id: int) -> bool:
	return player_id == get_local_player_id()


## Network: true when the (deterministically derived) active slot is ours --
## the same verdict the host's validator will give an intent submitted now.
## Local play: always true (turn gating is the turn system's job there).
func is_my_turn() -> bool:
	if not is_multiplayer_active():
		return true
	var slot := _rules.current_turn_slot() if _rules != null else _session().current_turn_slot()
	return slot != -1 and slot == _session().local_slot()


func get_rules() -> NetGameRules:
	return _rules


## Lobby-era envelope, kept for callers that still use it as a permission check.
## Real state changes never travel here (they are intents, see request_*): inside a
## network match this reports "granted"; outside one there is no legacy session to
## deliver to, so it refuses.
func submit_action(_action_type: String, _action_data: Dictionary) -> bool:
	return is_multiplayer_active()


## Status summary in the shape older callers read (network_stats.connected_peers /
## connection_status). Derived from NetSession; the old GameManager session is gone.
func get_game_status() -> Dictionary:
	var ns := _session()
	var connected := ns != null and ns.is_connected_session()
	var peers := maxi(0, ns.player_count() - 1) if ns != null else 0
	return {
		"is_active": is_multiplayer_active(),
		"game_mode": "NETWORK_MULTIPLAYER" if is_multiplayer_active() else "LOCAL",
		"local_player_id": get_local_player_id(),
		"network_stats": {
			"connected_peers": peers,
			"connection_status": "CONNECTED" if connected else "disconnected",
		},
	}


# ---------------------------------------------------------------------------
# Intents (network only; each returns false outside a network match)
# ---------------------------------------------------------------------------

func request_move(unit, cell) -> bool:
	return submit_intent(NetProtocol.move(NetUnitIds.id_of(unit), cell))


func request_use_move(unit, slot: int, aim_cell) -> bool:
	return submit_intent(NetProtocol.use_move(NetUnitIds.id_of(unit), slot, aim_cell))


func request_wait(unit) -> bool:
	return submit_intent(NetProtocol.wait(NetUnitIds.id_of(unit)))


func request_end_turn() -> bool:
	return submit_intent(NetProtocol.end_turn(get_local_player_id()))


func submit_intent(action: Dictionary) -> bool:
	if not is_multiplayer_active():
		return false
	return _session().submit_intent(action)


# ---------------------------------------------------------------------------
# Match lifecycle
# ---------------------------------------------------------------------------

func _on_match_started(config: Dictionary) -> void:
	_match_finished = false
	_rules = null
	if DuelNetConfig.is_duel(config):
		_start_network_duel(config)
		return
	if apply_match_config(config) == "":
		var ns := _session()
		if _offline_only_refusal != "" and ns != null and ns.is_host():
			# Every peer runs the same rule, but the host says so on the wire too, so a seat
			# learns WHY rather than seeing its host vanish. A dedicated server reopens its lobby.
			ns.end_match(OFFLINE_ONLY_MAP_REASON)
			if is_dedicated_server_process():
				return
		end_network_session(ABORT_TEXT[OFFLINE_ONLY_MAP_REASON] if _offline_only_refusal != "" \
			else "The host's map could not be verified -- the match was not started.")
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return
	get_tree().change_scene_to_file(GAME_WORLD_SCENE)


## ONLINE DUEL (DECISIONS.md #32): build the duel from the host's [param config] on this peer
## and open the online duel stage -- or refuse the match (every peer runs the same check) when
## the config names a unit that is not duel-eligible or a stage / weather this build lacks.
func _start_network_duel(config: Dictionary) -> void:
	var req := apply_duel_config(config)
	if req == null:
		var ns := _session()
		if ns != null and ns.is_host():
			ns.end_match(DUEL_REFUSED_REASON)
			if is_dedicated_server_process():
				return
		end_network_session(ABORT_TEXT[DUEL_REFUSED_REASON])
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return
	get_tree().change_scene_to_file(NET_DUEL_STAGE_SCENE)


## The duel half of [method apply_match_config]: [DuelNetConfig.build_request] (strict: a
## non-eligible pick refuses), then GameSettings for a network match, and the request staged
## on DuelController (the online stage reads it). Returns the request, or null to refuse.
func apply_duel_config(config: Dictionary) -> DuelRequest:
	_duel_refusal = ""
	var res := DuelNetConfig.build_request(config)
	if not bool(res["success"]):
		_duel_refusal = String(res["reason"])
		return null
	var req: DuelRequest = res["request"]
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.player_count = 2
	var slots: Dictionary = config.get("slots", {})
	var names: Array[String] = []
	for s in range(2):
		names.append(String(slots.get(s, "Player %d" % (s + 1))))
	GameSettings.player_names = names
	# No squads, items or skins ride an online duel: the picks are in the config itself.
	MatchLoadouts.clear()
	var ctrl := get_node_or_null("/root/DuelController")
	if ctrl != null and ctrl.has_method("start"):
		ctrl.start(req, false)
	return req


## Called by the online duel stage once its [DuelBattle] is set up and started (every peer):
## the rules become the session's game.
func on_network_duel_ready(rules: NetGameRules) -> void:
	if not is_multiplayer_active() or rules == null:
		return
	_rules = rules
	_session().attach_game(rules)


## The live network battle was decided (the online duel's KO / concede): a disconnect from
## here on only drops the link, it never throws the player off the results.
func mark_network_match_finished() -> void:
	if is_multiplayer_active():
		_match_finished = true


## Copy the host's authoritative match [param config] into this peer's GameSettings
## (no scene change -- that is [method _on_match_started]'s job, so this is testable).
## Returns the map path this peer boots from, or "" when the match must be refused.
func apply_match_config(config: Dictionary) -> String:
	_offline_only_refusal = ""
	var ns := _session()
	# WHICH FILE THIS PEER BOOTS FROM. A builtin map is on every machine. A custom /
	# community map travels as CONTENT ("map_payload", shipped by the player-host) and
	# is untrusted peer input: it goes through the catalog-strict gate and is
	# materialised into the session directory, or the match does not start at all --
	# never fall through to a same-named local file (two different boards).
	var map_path := String(config.get("map_path", GameSettings.get_selected_map()))
	var boot_path := map_path
	if ns == null or not ns.is_host():
		boot_path = resolve_boot_map(map_path, config.get("map_payload", {}))
	if boot_path == "":
		return ""
	# LAST LINE, every peer: a map a two-seat, AI-free match cannot run (an AI neutral faction,
	# AI-driven Siege creeps -- MapCatalog.network_play_blocker) is never booted online. The
	# lobby lists, the dedicated server's --map and its leader-config sanitiser already refuse
	# it; this catches any other path (a scripted host, an older lobby) before a battle that
	# would stall mid-match.
	var refusal := MapCatalog.network_refusal(boot_path)
	if refusal == MapCatalog.NET_REFUSAL_THIRD_FACTION or refusal == MapCatalog.NET_REFUSAL_AI_CREEPS:
		_offline_only_refusal = refusal
		return ""
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.set_selected_map(boot_path)
	GameSettings.set_turn_system(int(config.get("turn_system", TurnSystemBase.TurnSystemType.TRADITIONAL)))
	GameSettings.player_count = 2
	var slots: Dictionary = config.get("slots", {})
	var names: Array[String] = []
	for s in range(2):
		names.append(String(slots.get(s, "Player %d" % (s + 1))))
	GameSettings.player_names = names
	if config.has("versus_rounds") and GameSettings.has_method("set_versus_rounds"):
		GameSettings.set_versus_rounds(int(config.get("versus_rounds", 1)))
	var custom_json := String(config.get("map_json", ""))
	if custom_json != "" and GameSettings.has_method("set_custom_map_json"):
		GameSettings.set_custom_map_json(custom_json)
	# SQUADS. Every peer must build the IDENTICAL board. A player-hosted lobby
	# replicates both sides' Character Select picks (the host's rides "host_squad";
	# every other seat's rides its match_loadout card in MatchLoadouts) and MapLoader
	# resolves each slot from the right source. Without that exchange (a dedicated
	# server, which runs no lobby UI and has no seat, or a lobby that skipped it)
	# every peer fields the map's authored rosters.
	var replicated := ns != null and not ns.is_dedicated_server() and MatchLoadouts.is_active()
	if replicated:
		if ns.local_slot() >= 0:
			MatchLoadouts.set_local_slot(ns.local_slot())
		if GameSettings.has_method("set_host_squad"):
			GameSettings.set_host_squad(MatchLoadouts.normalise_squad(config.get("host_squad", [])))
	else:
		MatchLoadouts.clear()
		GameSettings.clear_selected_squad()
		if GameSettings.has_method("set_host_squad"):
			GameSettings.set_host_squad([])
	GameSettings.auto_end_turn = bool(config.get("auto_end_turn", true))
	# Forced-control (mind-control) turns are planned by BotController; EASY rolls a
	# private RNG, so pin the deterministic NORMAL planner for the match.
	if _saved_ai_difficulty < 0:
		_saved_ai_difficulty = GameSettings.ai_difficulty
	GameSettings.ai_difficulty = 1
	# Anything rolled while the battle is set up (before the first accepted
	# action) uses the public setup seed; every accepted action then installs its
	# own commit-reveal generator (see NetGameRules / NetCommitReveal).
	NetGameRules.install_setup_rng(int(config.get("seed", 1)))
	return boot_path


## The path THIS peer boots the battle from, or "" to refuse the match.
## [param map_path] is the host's identifier; [param raw_payload] the map content it
## shipped (untrusted). Content shipped -> strict-validate + materialise it and boot
## from THAT copy; no content + builtin path -> the builtin; anything else -> refuse.
static func resolve_boot_map(map_path: String, raw_payload: Variant) -> String:
	if raw_payload is Dictionary and not (raw_payload as Dictionary).is_empty():
		return MapCatalog.install_session_payload(raw_payload as Dictionary)
	if map_path != "" and MapCatalog.is_builtin(map_path):
		return map_path
	return ""


## Called by GameWorldManager once the battle scene has loaded the map, seated
## both players and started the turn system (every peer).
func on_network_world_ready() -> void:
	if not is_multiplayer_active():
		return
	var seed_value := int(_session().get_match_config().get("seed", 1))
	_rules = NetGameRules.for_live_battle(seed_value)
	_rules.assign_initial_ids()
	_session().attach_game(_rules)


func _on_action_applied(action: Dictionary, result: Dictionary) -> void:
	var scene := get_tree().current_scene
	var vm = scene.get_node_or_null("UnitVisualManager") if scene != null else null
	if vm != null and vm.has_method("update_all_unit_visuals"):
		vm.update_all_unit_visuals()
	network_action_applied.emit(action, result)


## A refused intent is surfaced to the player. The battle HUD's [NetToast] listens to
## NetSession.intent_rejected itself; this only draws a fallback line when no NetToast
## is mounted (so a refusal is never silent, and never shown twice).
func _on_intent_rejected(action: Dictionary, reason: String) -> void:
	network_intent_rejected.emit(action, reason)
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null and not _has_net_toast(scene):
		show_toast(NetProtocol.describe_intent_rejection(reason, action))


static func _has_net_toast(node: Node) -> bool:
	if node is NetToast:
		return true
	for child in node.get_children():
		if _has_net_toast(child):
			return true
	return false


## Brief on-screen message (top-center, fades out). Self-contained: builds its own
## CanvasLayer on the current scene; a no-op when there is no scene (tests).
func show_toast(text: String, seconds: float = 2.0) -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	var layer := scene.get_node_or_null("NetToastLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "NetToastLayer"
		layer.layer = 50
		scene.add_child(layer)
	for old in layer.get_children():
		old.queue_free()
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.offset_top = 90
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	var tween := label.create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


func _on_game_state_changed(state) -> void:
	if is_multiplayer_active() and state == PlayerManager.GameState.FINISHED:
		_match_finished = true
		# The battle is decided: no timed turn is open any more (the host stops the clock).
		if _rules != null:
			_rules.decided = true


func _on_match_aborted(reason: String) -> void:
	if _match_finished:
		# The battle was already decided; keep the end screen up, just drop the link.
		end_network_session()
		return
	if is_dedicated_server_process():
		return  # DedicatedServer reopens the lobby itself
	if (reason == "opponent_disconnected" or reason == "host_disconnected" \
			or reason == NetSessionNode.ABORT_CLOCK_FORFEIT) and _rules != null:
		# The other side left a LIVE battle: that is a loss for them. NetSession raised
		# opponent_left first and the battle HUD resolves it as this player's victory
		# (the standard game-over flow), so stay on the battle and just drop the link. A clock
		# forfeit (a seat ran out of time too often) was resolved the same way before the end.
		_match_finished = true
		end_network_session()
		return
	end_network_session(ABORT_TEXT.get(reason, "Lost connection to the host. The match has ended."))
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Why a match refused to boot on this peer: the map is playable offline only. Also the
## reason the host broadcasts (NetSession.end_match) so every seat shows the same line.
const OFFLINE_ONLY_MAP_REASON := "offline_only_map"

## Set by [method apply_match_config] when it refused the map as offline-only
## ([code]MapCatalog.NET_REFUSAL_*[/code]), "" otherwise.
var _offline_only_refusal: String = ""

## Why the host's duel config was refused on this peer ([method DuelNetConfig.build_request]
## reasons), "" otherwise. Also the reason the host broadcasts ([constant DUEL_REFUSED_REASON]).
const DUEL_REFUSED_REASON := "duel_refused"
var _duel_refusal: String = ""

const ABORT_TEXT := {
	"opponent_disconnected": "Opponent disconnected. The match has ended.",
	"host_disconnected": "Lost connection to the host. The match has ended.",
	"rng_verification_failed": "A player's dice rolls failed verification (possible tampering). The match has ended.",
	"host_verification_failed": "The host sent dice rolls or actions that failed verification (possible tampering). The match has ended.",
	"reveal_timeout": "A player stopped responding. The match has ended.",
	"match_complete": "The server closed the match.",
	OFFLINE_ONLY_MAP_REASON: "That map is offline only (it needs AI-controlled units, and online matches run no AI). The match was not started.",
	DUEL_REFUSED_REASON: "The duel's settings could not be verified (a unit that cannot duel, or an unknown stage). The match was not started.",
	NetSessionNode.ABORT_CLOCK_FORFEIT: "A player ran out of time too many turns in a row and forfeited. The match has ended.",
	NetSessionNode.ABORT_UNDRIVEN_TURN: "The battle reached a turn no player controls (an AI or neutral side), which online matches cannot run. The match has ended.",
}


func _on_desync_detected(seq: int, _local: int, _host: int) -> void:
	if not is_multiplayer_active():
		return
	end_network_session("Game state went out of sync with the host (action %d). The match has ended." % seq)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Close any network session and restore local play defaults. Idempotent; call
## whenever leaving a network match (menu, game over, disconnect).
func end_network_session(message: String = "") -> void:
	if message != "":
		pending_menu_message = message
	var ns := _session()
	if ns != null and ns.is_active():
		ns.leave()
	_rules = null
	_match_finished = false
	if GameSettings != null and GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
		GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	if _saved_ai_difficulty >= 0 and GameSettings != null:
		GameSettings.ai_difficulty = _saved_ai_difficulty
	_saved_ai_difficulty = -1
	if CombatServices != null:
		CombatServices.match_rng = null


## Return (and clear) the one-shot main-menu message.
func consume_menu_message() -> String:
	var m := pending_menu_message
	pending_menu_message = ""
	return m
