extends Node

## GameModeManager -- live-game glue for NETWORK versus.
##
## [NetSession] (autoload) is the transport / lobby / ordering layer and knows
## nothing about units; [NetGameRules] is the deterministic validate/apply layer.
## This autoload wires them into the running game:
##   * on [signal NetSession.match_started] it copies the host's match config into
##     [GameSettings] (map, turn system, player names) and loads the battle scene;
##   * [method on_network_world_ready] (called by GameWorldManager once the map,
##     players and turn system exist) builds the NetGameRules over the LIVE board
##     (CombatServices) and turn system (TurnSystemManager) and attaches it;
##   * the UI submits intents through request_move / request_use_move /
##     request_wait / request_end_turn instead of mutating state directly;
##   * disconnects / desyncs end the match and return to the main menu with a
##     message; [method end_network_session] closes the session and restores the
##     local game mode so single-player / hotseat afterwards is unaffected.
##
## Outside a network match every query answers like local play (local player id 0,
## always "my turn"), so hotseat and single-player code paths are unchanged.

signal network_action_applied(action: Dictionary, result: Dictionary)
signal network_intent_rejected(action: Dictionary, reason: String)
signal network_turn_changed(slot: int)

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
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
## network seat after a session ends.
func get_local_player_id() -> int:
	if is_multiplayer_active():
		return _session().local_slot()
	return 0


func is_local_player(player_id: int) -> bool:
	return player_id == get_local_player_id()


## Network: true when the (deterministically derived) active slot is ours.
## Local play: always true (turn gating is the turn system's job there).
func is_my_turn() -> bool:
	if not is_multiplayer_active():
		return true
	var slot := _rules.current_turn_slot() if _rules != null else _session().current_turn_slot()
	return slot != -1 and slot == _session().local_slot()


func get_rules() -> NetGameRules:
	return _rules


# ---------------------------------------------------------------------------
# Intents (network only; each returns false outside a network match)
# ---------------------------------------------------------------------------

func request_move(unit, cell: Vector3i) -> bool:
	return submit_intent(NetProtocol.move(NetUnitIds.id_of(unit), cell))


func request_use_move(unit, slot: int, aim_cell: Vector3i) -> bool:
	return submit_intent(NetProtocol.use_move(NetUnitIds.id_of(unit), slot, aim_cell))


func request_wait(unit) -> bool:
	return submit_intent(NetProtocol.wait(NetUnitIds.id_of(unit)))


func request_end_turn() -> bool:
	return submit_intent(NetProtocol.end_turn())


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
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.set_selected_map(String(config.get("map_path", GameSettings.get_selected_map())))
	GameSettings.set_turn_system(int(config.get("turn_system", TurnSystemBase.TurnSystemType.TRADITIONAL)))
	GameSettings.player_count = 2
	var slots: Dictionary = config.get("slots", {})
	var names: Array[String] = []
	for s in range(2):
		names.append(String(slots.get(s, "Player %d" % (s + 1))))
	GameSettings.player_names = names
	# Every peer must build the IDENTICAL board: the map's authored rosters, not a
	# locally picked squad; and identical rules toggles.
	GameSettings.clear_selected_squad()
	GameSettings.auto_end_turn = bool(config.get("auto_end_turn", true))
	# Forced-control (mind-control) turns are planned by BotController; EASY rolls a
	# private RNG, so pin the deterministic NORMAL planner for the match.
	if _saved_ai_difficulty < 0:
		_saved_ai_difficulty = GameSettings.ai_difficulty
	GameSettings.ai_difficulty = 1
	get_tree().change_scene_to_file(GAME_WORLD_SCENE)


## Called by GameWorldManager once the battle scene has loaded the map, seated
## both players and started the turn system (every peer).
func on_network_world_ready() -> void:
	if not is_multiplayer_active():
		return
	var seed_value := int(_session().get_match_config().get("seed", 1))
	_rules = NetGameRules.new(
		func(): return CombatServices.board(),
		func(): return TurnSystemManager.get_active_turn_system() if TurnSystemManager.has_active_turn_system() else null,
		seed_value)
	_rules.assign_initial_ids()
	_session().attach_game(_rules)


func _on_action_applied(action: Dictionary, result: Dictionary) -> void:
	var scene := get_tree().current_scene
	var vm = scene.get_node_or_null("UnitVisualManager") if scene != null else null
	if vm != null and vm.has_method("update_all_unit_visuals"):
		vm.update_all_unit_visuals()
	network_action_applied.emit(action, result)


func _on_intent_rejected(action: Dictionary, reason: String) -> void:
	push_warning("Network intent %s rejected by host: %s" % [NetProtocol.type_name(int(action.get("type", -1))), reason])
	network_intent_rejected.emit(action, reason)
	show_toast(REJECTION_TEXT.get(reason, "Action not allowed (%s)." % reason))


const REJECTION_TEXT := {
	"not_your_turn": "It is not your turn.",
	"not_your_unit": "That unit is not yours.",
	"illegal_destination": "That unit cannot move there.",
	"illegal_target": "That target is not valid.",
	"unit_cannot_move": "That unit has already moved.",
	"unit_cannot_act": "That unit has already acted.",
	"move_unavailable": "That move is not ready yet.",
	"unknown_unit": "That unit is no longer on the board.",
	"cannot_end_turn": "The turn cannot be ended right now.",
}


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


func _on_match_aborted(reason: String) -> void:
	if _match_finished:
		# The battle was already decided; keep the end screen up, just drop the link.
		end_network_session()
		return
	var msg := "Opponent disconnected. The match has ended." if reason == "opponent_disconnected" \
		else "Lost connection to the host. The match has ended."
	end_network_session(msg)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


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
