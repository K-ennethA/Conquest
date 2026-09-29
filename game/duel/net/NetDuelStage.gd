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
	hud.replacement_chosen.connect(_on_replacement_chosen)
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
	_mount_turn_clock()


func _exit_tree() -> void:
	_unmount_turn_clock()
	if session != null and is_instance_valid(session):
		for pair in [[session.action_applied, _on_applied], [session.intent_rejected, _on_rejected],
				[session.opponent_left, _on_opponent_left], [session.opponent_forfeited, _on_opponent_forfeited]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
	super._exit_tree()


# --- ONLINE TURN CLOCK hook (NetSession's host clock; DuelNetRules: a timeout = a pass, or the
# --- team-order auto-pick while a KO replacement is pending) ------------------------------------

## The host's clock + a visible Forfeit, for the seats (a dedicated server shows nothing).
var clock_bar: NetMatchBar = null


func _mount_turn_clock() -> void:
	if session == null or local_slot < 0:
		return
	clock_bar = NetMatchBar.new()
	clock_bar.name = "NetMatchBar"
	clock_bar.session = session
	clock_bar.pause_menu = _pause
	add_child(clock_bar)
	if not session.clock_forfeit.is_connected(_on_clock_forfeit):
		session.clock_forfeit.connect(_on_clock_forfeit)


func _unmount_turn_clock() -> void:
	if session != null and is_instance_valid(session) and session.clock_forfeit.is_connected(_on_clock_forfeit):
		session.clock_forfeit.disconnect(_on_clock_forfeit)


## A seat ran out of time too many actions in a row: it concedes (either seat).
func _on_clock_forfeit(slot: int) -> void:
	if local_slot < 0 or battle == null or battle.is_over or slot < 0 or slot > 1:
		return
	_conceded_text = "You ran out of time too many turns in a row." if slot == local_slot \
		else "Your opponent ran out of time and forfeited."
	battle.concede(slot)


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
	if _party_duel():
		hud.show_team_preview(_seat_names())
		await _beat(BEAT_PREVIEW)
		hud.hide_team_preview()
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


## Whose turn: prompt our seat (or submit its forced pass), otherwise say who we wait for. A
## pending KO replacement comes first: the fainted combatant's seat picks, the other waits.
func _update_turn() -> void:
	var pending := battle.pending_replacements()
	if not pending.is_empty():
		_update_replacement(pending)
		return
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


## PARTY DUELS: a combatant fainted -- our seat picks its replacement (the picker, no way back),
## or we wait for the other seat's pick.
func _update_replacement(pending: Array[int]) -> void:
	var mine: bool = local_slot >= 0 and local_slot in pending
	if not mine:
		_prompted = false
		_set_waiting(_waiting_for_pick(pending[0]))
		return
	var settled: bool = session != null and not session.has_pending_actions() \
		and Engine.get_process_frames() > _last_apply_frame + 1
	if _pending or not settled or _prompted:
		return
	_prompted = true
	_waiting_text = ""
	hud.narrate("Choose who fights next.")
	hud.show_replacement(local_slot)


func _waiting_for_pick(side: int) -> String:
	if local_slot < 0:
		return "Side %d is choosing a partner…" % (side + 1)
	var names: Dictionary = session.get_match_config().get("slots", {}) if session != null else {}
	var who: String = String(names.get(side, ""))
	return "Waiting for %s to send out a partner…" % (who if who != "" else "your opponent")


## The seats' names for the team preview (the local seat reads "Your team").
func _seat_names() -> Array:
	var names: Dictionary = session.get_match_config().get("slots", {}) if session != null else {}
	var out: Array = []
	for side in 2:
		out.append("" if side == local_slot else String(names.get(side, "")))
	return out


## The picker handed back our replacement: send it as an intent.
func _on_replacement_chosen(index: int) -> void:
	if not _prompted or _pending or battle.is_over or local_slot < 0:
		return
	var intent := rules.replacement_intent(local_slot, index)
	var why := rules.validate_intent(intent, local_slot)
	if why != "":
		hud.narrate(NetProtocol.describe_intent_rejection(why, intent))
		hud.show_replacement(local_slot)
		return
	_submit(intent)


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
	if slot == DuelHUD.SWITCH_SLOT and actor != null:
		var sw := rules.switch_intent(hud.chosen_member)
		var bad := rules.validate_intent(sw, local_slot)
		if bad != "":
			hud.narrate(NetProtocol.describe_intent_rejection(bad, sw))
			hud.show_commands(actor)
			return
		_submit(sw)
		return
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
		if NetProtocol.is_timeout(action) and _prompted:
			# The host's clock played our turn / pick for us: the open grid or replacement
			# picker is stale (a late click must not become the next turn's intent).
			_prompted = false
			hud.show_waiting("")
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
		hud.narrate("Time's up! %s passes." % who if NetProtocol.is_timeout(cmd) else "%s can't move!" % who)
		await _beat(BEAT_PASS)
		return
	if int(cmd.get(NetProtocol.KEY_TYPE, -1)) == NetProtocol.Action.SWITCH:
		hud.narrate(("Time's up! " if NetProtocol.is_timeout(cmd) else "") + switch_line(rec))
		await _beat(BEAT_AFTER)
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
