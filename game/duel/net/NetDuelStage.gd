extends DuelStage
class_name NetDuelStage

## The ONLINE duel's scene (docs/design/DECISIONS.md #32): the [DuelStage] (same stage, camera,
## presentation layers and [DuelHUD]) driven by the NETWORK instead of by itself. Loaded on
## every peer (both seats and a dedicated server) by GameModeManager when a duel match starts;
## the request is the one [DuelNetConfig] built from the host's config.
##
## THE DIFFERENCE: this stage never applies anything. On its seat's turn it asks the HUD for a
## slot and SUBMITS the intent ([method DuelNetRules.use_move_intent]) to [NetSession]; the host
## validates it, the commit-reveal round stamps its seed, and every peer -- this one included --
## applies it through [DuelNetRules] (THE apply path). Applied actions queue here and are
## NARRATED in order (who used what, the cut-in, the outcome line), whoever acted. A stunned /
## controlled combatant of ours submits its WAIT by itself. Off-turn the panel says whose turn
## it is; a refused intent shows the network toast and the grid comes back.
##
## Leaving: the pause menu's Forfeit (NetSession.forfeit_match) is a loss; the opponent
## forfeiting or dropping is this seat's win ([method DuelBattle.concede]) -- the same rules as
## Conquest online. The results card's only way on is back to the Online screens.
##
## Tests inject [member session] / [member net_request] before adding the stage (several peers
## in one process); the live game uses the NetSession autoload and DuelController's request.

const VERSUS_SCENE := "res://menus/MultiplayerModeSelection.tscn"

## The session this stage plays over (default: the NetSession autoload).
var session: NetSessionNode = null
## The request to build (default: the one DuelController staged).
var net_request: DuelRequest = null
## The rules object attached to [member session].
var rules: DuelNetRules = null
## This peer's seat (= side); -1 on a dedicated server (it only applies and watches).
var local_slot: int = -1

var _records: Array = []
var _prompted: bool = false
var _pending: bool = false
var _waiting_text: String = ""
var _last_apply_frame: int = -1
var _conceded_text: String = ""
var _results_shown: bool = false
var _final: DuelResult = null


func _ready() -> void:
	if session == null:
		session = get_node_or_null("/root/NetSession") as NetSessionNode
	local_slot = session.local_slot() if session != null else -1
	super._ready()
	if battle == null or battle.turn_system == null:
		return
	hud.results_menu_only = true
	hud.slot_chosen.connect(_on_slot_chosen)
	if session != null:
		session.action_applied.connect(_on_applied)
		session.intent_rejected.connect(_on_rejected)
		session.opponent_left.connect(_on_opponent_left)
		session.opponent_forfeited.connect(_on_opponent_forfeited)
	if session != null and session == get_node_or_null("/root/NetSession"):
		# The standard refusal toast (NetSession.intent_rejected -> "Attack rejected -- ...").
		add_child(NetToast.new())
	# Start at once (the intro plays over it) so the rules can attach: the host queues intents
	# and actions until every peer's game is up.
	battle.start()
	rules = DuelNetRules.new(battle)
	rules.presentation = local_slot >= 0
	var gmm := get_node_or_null("/root/GameModeManager")
	if session != null and session == get_node_or_null("/root/NetSession") and gmm != null \
			and gmm.has_method("on_network_duel_ready") and gmm.is_multiplayer_active():
		gmm.on_network_duel_ready(rules)
	elif session != null:
		session.attach_game(rules)


func _exit_tree() -> void:
	if session != null and is_instance_valid(session):
		for pair in [[session.action_applied, _on_applied], [session.intent_rejected, _on_rejected],
				[session.opponent_left, _on_opponent_left], [session.opponent_forfeited, _on_opponent_forfeited]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
	super._exit_tree()


func _staged_request() -> DuelRequest:
	if net_request != null:
		return net_request
	return super._staged_request()


func _configure_hud() -> void:
	hud.perspective_side = maxi(local_slot, 0)


## Online, each seat has its own screen: never the shared-screen (hot-seat) presentation.
func is_hotseat() -> bool:
	return false


# --- The director (network-driven) ---------------------------------------------------

func _run() -> void:
	if _driving:
		return
	_driving = true
	hud.show_intro(versus_intro(battle))
	hud.set_command_panel_visible(false)
	await _beat(BEAT_INTRO)
	if not is_inside_tree():
		return
	hud.show_intro("")
	hud.set_command_panel_visible(true)
	while is_inside_tree():
		if not _records.is_empty():
			await _present(_records.pop_front())
			continue
		if battle.is_over:
			break
		_update_turn()
		await get_tree().process_frame
	if is_inside_tree() and battle.is_over:
		_show_final()
	_driving = false


## Whose turn: prompt our seat (or submit its forced pass), otherwise say who we wait for.
func _update_turn() -> void:
	var actor = battle.current_actor()
	var mine: bool = actor != null and local_slot >= 0 and battle.side_of(actor) == local_slot
	if not mine:
		_prompted = false
		_set_waiting(_waiting_for(actor))
		return
	# Let the previous action (and anything it deferred) settle before choosing on it.
	var settled: bool = session != null and not session.has_pending_actions() \
		and Engine.get_process_frames() > _last_apply_frame + 1
	if _pending or not settled:
		return
	if battle.must_pass(actor):
		hud.narrate("%s can't move!" % actor.get_display_name())
		_submit(rules.pass_intent())
		return
	if not _prompted:
		_prompted = true
		_waiting_text = ""
		hud.narrate("What will %s do?" % actor.get_display_name())
		hud.show_commands(actor)


func _waiting_for(actor) -> String:
	if actor == null:
		return ""
	if local_slot < 0:
		return "%s is choosing…" % actor.get_display_name()
	var names: Dictionary = session.get_match_config().get("slots", {}) if session != null else {}
	var who: String = String(names.get(battle.side_of(actor), ""))
	return "Waiting for %s…" % (who if who != "" else "your opponent")


func _set_waiting(text: String) -> void:
	if text == _waiting_text:
		return
	_waiting_text = text
	hud.show_waiting(text)


## The HUD handed back a pick (only while prompted): send it as an intent.
func _on_slot_chosen(slot: int) -> void:
	if not _prompted or _pending or battle.is_over:
		return
	var actor = battle.current_actor()
	if slot < 0 or actor == null:
		# Items / Flee are never offered online (the buttons stay disabled); re-offer the grid.
		if actor != null:
			hud.show_commands(actor)
		return
	var intent := rules.use_move_intent(slot)
	var why := rules.validate_intent(intent, local_slot)
	if why != "":
		hud.narrate(NetProtocol.describe_intent_rejection(why, intent))
		hud.show_commands(actor)
		return
	_submit(intent)


func _submit(intent: Dictionary) -> void:
	if intent.is_empty() or session == null:
		return
	_pending = true
	_prompted = false
	_waiting_text = ""
	hud.show_waiting("")
	if not session.submit_intent(intent):
		_pending = false


func _on_applied(action: Dictionary, result: Dictionary) -> void:
	_last_apply_frame = Engine.get_process_frames()
	if int(action.get(NetProtocol.KEY_ACTOR, -1)) == local_slot:
		_pending = false
	_waiting_text = ""
	_records.append(result)


func _on_rejected(_action: Dictionary, _reason: String) -> void:
	# The toast says why (NetToast); the grid comes back on the next frame.
	_pending = false
	_prompted = false


## Narrate one applied action: who did what, the cut-in, the outcome line.
func _present(rec: Dictionary) -> void:
	var cmd: Dictionary = rec.get("cmd", {})
	var actor = rec.get("actor")
	var who: String = actor.get_display_name() if actor != null and is_instance_valid(actor) else "The foe"
	hud.refresh()
	if int(cmd.get(NetProtocol.KEY_TYPE, -1)) == NetProtocol.Action.WAIT:
		hud.narrate("%s can't move!" % who)
		await _beat(BEAT_PASS)
		return
	var move: MoveResource = rec.get("move")
	if move == null:
		return
	hud.narrate("%s used %s!" % [who, move.display_name_for(actor) if actor != null and is_instance_valid(actor) else move.display_name])
	if MoveResource.is_ultimate_move(move, int(rec.get("slot", -1))) and not instant and _cutin != null \
			and actor != null and is_instance_valid(actor):
		_cutin.play(actor, move)
		await _cutin.finished
	if camera != null:
		camera.punch(0.0 if instant else 0.35 * _scale())
	await _settle()
	var line := _outcome_line(rec, rec.get("forecast", {}))
	if line != "":
		hud.narrate(line)
		await _beat(BEAT_AFTER)


# --- Leaving / the end -------------------------------------------------------------------

func _on_opponent_forfeited(slot: int) -> void:
	_opponent_gone(slot if slot >= 0 else 1 - local_slot, "Your opponent forfeited the duel.")


func _on_opponent_left() -> void:
	_opponent_gone(1 - local_slot, "Your opponent left the duel.")


func _opponent_gone(side: int, text: String) -> void:
	if local_slot < 0 or battle == null or battle.is_over or side == local_slot:
		return
	_conceded_text = text
	battle.concede(side)


## The duel ended (KO or concede): remember the result; the director shows it once every
## queued action has been narrated.
func _on_finished(result: DuelResult) -> void:
	_final = result
	var gmm := get_node_or_null("/root/GameModeManager")
	if gmm != null and gmm.has_method("mark_network_match_finished") and session == get_node_or_null("/root/NetSession"):
		gmm.mark_network_match_finished()
	var ctrl := get_node_or_null("/root/DuelController")
	# Headless processes (a dedicated server, scripted net bots) never write a player profile.
	var record: bool = (ctrl == null or bool(ctrl.get("record_profile"))) \
		and DisplayServer.get_name() != "headless"
	if record and local_slot >= 0 and result.outcome != DuelResult.OUTCOME_ABORTED:
		var profile := get_node_or_null("/root/PlayerProfile")
		if profile != null and profile.has_method("notify_battle_result"):
			profile.notify_battle_result("duel", result.winner_side == local_slot, {"rounds": result.rounds, "online": true})
	if not _driving:
		_show_final.call_deferred()


func _show_final() -> void:
	if _results_shown or _final == null or not is_inside_tree():
		return
	_results_shown = true
	if camera != null:
		camera.impulse_shake(0.5)
	if _conceded_text != "":
		hud.narrate(_conceded_text)
	_show_results(_final, false)


func _on_menu() -> void:
	var gmm := get_node_or_null("/root/GameModeManager")
	if gmm != null and gmm.has_method("end_network_session"):
		gmm.end_network_session()
	var ctrl := get_node_or_null("/root/DuelController")
	if ctrl != null and ctrl.has_method("reset"):
		ctrl.reset()
	if is_inside_tree():
		get_tree().change_scene_to_file(VERSUS_SCENE)


func _on_rematch() -> void:
	_on_menu()


func _on_setup() -> void:
	_on_menu()
