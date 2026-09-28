extends NetGameRules
class_name DuelNetRules

## The rules object an ONLINE DUEL attaches to [NetSession] (docs/design/DECISIONS.md #32):
## the same interface as [NetGameRules] (validate_intent / apply_action / current_turn_slot /
## state_digest), bound to one [DuelBattle] -- which already applies every action as a command
## through its [CommandApplier] (THE apply path). Nothing here computes damage or rolls a die.
##
## VALIDATION (the host; every client re-runs it on its own identical state before applying):
##   - the duel is live and it is [param actor_slot]'s combatant's turn (the speed-order
##     [DuelTurnSystem] decides; a slot IS a side: host / first seat = side A = slot 0);
##   - USE_MOVE names the acting combatant, a slot [method DuelBattle.legal_slots] offers (its
##     ready moves, or the struggle when none is), aimed exactly where the local duel aims it
##     ([method DuelBrain.aim_for] -- a duel has no free aiming);
##   - WAIT only while the combatant must pass (stunned / controlled) -- the local duel never
##     lets a free combatant skip, so neither does the wire;
##   - MOVE / END_TURN / USE_ITEM are refused: stations never change, turns end by acting, and
##     items / running are local and story actions (online duels carry no bag and never flee).
##
## APPLY (every peer, host order): [method DuelBattle.apply_command] with the action as
## NetSession stamped it (seq + the verified commit-reveal seed), so a network duel rolls
## exactly as its replay does. A kept CANTO move's follow-up WAIT is applied inside the same
## call on every peer (deterministic, no new roll). The result is the MAIN action's record
## (cmd, result, actor, move, hp ...) plus [code]records[/code] (everything that applied) and,
## when [member presentation] is on, a pre-apply [code]forecast[/code] for the narration.
##
## DIGEST: the board digest (units, HP, statuses, cooldowns, turn, weather) plus the duel's
## own state -- round, decided flag, winner, command count and whose turn it is -- so a peer
## whose duel diverged is caught at the next checkpoint.

## The duel this rules object drives.
var battle: DuelBattle = null
## Compute a pre-apply damage forecast for the narration (a presenting peer only; the
## dedicated server leaves it off). Pure preview -- never changes state.
var presentation: bool = false


func _init(p_battle: DuelBattle = null) -> void:
	super(func(): return battle.board if battle != null and is_instance_valid(battle) else null,
		func(): return battle.turn_system if battle != null and is_instance_valid(battle) else null,
		0)
	battle = p_battle
	if battle != null and battle.request != null:
		match_seed = battle.request.seed


## True once the duel is decided (the dedicated server / net bot end the match on it).
func is_match_over() -> bool:
	return battle == null or not is_instance_valid(battle) or battle.is_over


## The acting combatant's side, or -1 (not started / decided).
func current_turn_slot() -> int:
	if battle == null or not is_instance_valid(battle):
		return -1
	var actor = battle.current_actor()
	return battle.side_of(actor) if actor != null else -1


func validate_intent(action: Dictionary, actor_slot: int) -> String:
	if not NetProtocol.is_well_formed(action):
		return NetProtocol.INTENT_MALFORMED
	if battle == null or not is_instance_valid(battle) or battle.board == null or battle.turn_system == null:
		return NetProtocol.INTENT_NO_GAME
	if battle.is_over:
		return NetProtocol.INTENT_DUEL_OVER
	var actor = battle.current_actor()
	if actor == null:
		return NetProtocol.INTENT_NO_ACTIVE_TURN
	if actor_slot < 0 or battle.side_of(actor) != actor_slot:
		return NetProtocol.INTENT_NOT_YOUR_TURN
	var t: int = int(action[NetProtocol.KEY_TYPE])
	match t:
		NetProtocol.Action.MOVE:
			return NetProtocol.INTENT_UNIT_CANNOT_MOVE
		NetProtocol.Action.END_TURN:
			return NetProtocol.INTENT_CANNOT_END_TURN
		NetProtocol.Action.USE_ITEM:
			return NetProtocol.INTENT_NOT_ONLINE
	var d: Dictionary = action[NetProtocol.KEY_DATA]
	var unit = find_unit(String(d.get(NetProtocol.K_UNIT, "")))
	if unit == null:
		return NetProtocol.INTENT_UNKNOWN_UNIT
	if unit != actor:
		return NetProtocol.INTENT_NOT_YOUR_UNIT
	if t == NetProtocol.Action.WAIT:
		return NetProtocol.INTENT_OK if battle.must_pass(actor) else NetProtocol.INTENT_REJECTED_BY_GAME
	if t != NetProtocol.Action.USE_MOVE:
		return NetProtocol.INTENT_UNKNOWN_ACTION
	if battle.must_pass(actor):
		return NetProtocol.INTENT_MUST_PASS
	var slot: int = int(d.get(NetProtocol.K_SLOT, -1))
	if actor.get_move(slot) == null:
		return NetProtocol.INTENT_NO_MOVE_IN_SLOT
	if not (slot in battle.legal_slots(actor)):
		return NetProtocol.INTENT_MOVE_UNAVAILABLE
	var aim: Vector3i = NetProtocol.cell_from_wire(d.get(NetProtocol.K_AIM))
	if aim != DuelBrain.aim_for(actor, battle.foe_of(actor), battle.board, slot):
		return NetProtocol.INTENT_ILLEGAL_TARGET
	return NetProtocol.INTENT_OK


## The USE_MOVE for [param slot] by the acting combatant, aimed as the duel aims it (the
## intent a seat submits). Empty when there is no actor.
func use_move_intent(slot: int) -> Dictionary:
	var actor = battle.current_actor() if battle != null else null
	if actor == null:
		return {}
	return NetProtocol.use_move(NetUnitIds.id_of(actor), slot,
		DuelBrain.aim_for(actor, battle.foe_of(actor), battle.board, slot))


## The WAIT a seat submits for its stunned / controlled combatant. Empty when there is no actor.
func pass_intent() -> Dictionary:
	var actor = battle.current_actor() if battle != null else null
	return NetProtocol.wait(NetUnitIds.id_of(actor)) if actor != null else {}


func apply_action(action: Dictionary) -> Dictionary:
	var seq: int = int(action.get(NetProtocol.KEY_SEQ, 0))
	last_applied_seq = maxi(last_applied_seq, seq)
	if battle == null or not is_instance_valid(battle):
		return {"ok": false, "reason": NetProtocol.INTENT_NO_GAME, "type": int(action.get(NetProtocol.KEY_TYPE, -1)),
			"seq": seq, "events": [], "records": []}
	# The duel's board is THE live board (the combat core reads CombatServices for secondary
	# contexts). Always true in a live duel; re-bound when several peers share a process (tests).
	if CombatServices.board() != battle.board:
		CombatServices.install_board(battle.board)
	var forecast := _forecast(action) if presentation else {}
	var records: Array = []
	var collect := func(rec: Dictionary) -> void: records.append(rec)
	battle.action_resolved.connect(collect)
	var rec: Dictionary = battle.apply_command(action)
	if battle.action_resolved.is_connected(collect):
		battle.action_resolved.disconnect(collect)
	var out: Dictionary = (records[0] as Dictionary).duplicate() if not records.is_empty() else rec.duplicate()
	var res: Dictionary = out.get("result", {}) if out.get("result", {}) is Dictionary else {}
	out["ok"] = bool(out.get("ok", false))
	out["type"] = int(action.get(NetProtocol.KEY_TYPE, -1))
	out["seq"] = seq
	out["reason"] = String(out.get("reason", res.get("reason", "")))
	out["events"] = res.get("events", [])
	out["records"] = records
	out["forecast"] = forecast
	action_applied.emit(action, out)
	return out


func _forecast(action: Dictionary) -> Dictionary:
	if int(action.get(NetProtocol.KEY_TYPE, -1)) != NetProtocol.Action.USE_MOVE:
		return {}
	var d: Dictionary = action.get(NetProtocol.KEY_DATA, {})
	var unit = find_unit(String(d.get(NetProtocol.K_UNIT, "")))
	if unit == null:
		return {}
	var move: MoveResource = unit.get_move(int(d.get(NetProtocol.K_SLOT, -1)))
	var foe = battle.foe_of(unit)
	if move == null or foe == null:
		return {}
	return MoveExecutor.preview_vs(move, unit, foe, battle.board)


func state_digest() -> int:
	var base := super.state_digest()
	if battle == null or not is_instance_valid(battle):
		return base
	var actor = battle.current_actor()
	var winner: int = battle.result.winner_side if battle.result != null else -2
	var turns: int = battle.result.turns if battle.result != null else 0
	return hash([base, battle.round_number(), battle.is_over, winner, turns,
		NetUnitIds.id_of(actor) if actor != null else ""])
