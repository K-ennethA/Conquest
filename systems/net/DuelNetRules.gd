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
##     items / running are local and story actions (online duels carry no bag and never flee);
##   - PARTY DUELS (the config's format): SWITCH names one of the SENDER's benched, healthy team
##     members. While a side's KO replacement is pending, that side's seat may only send its pick
##     (any other action: INTENT_MUST_PICK) and the other seat waits (INTENT_NOT_YOUR_TURN); a
##     voluntary switch needs the format's switching, the sender's own turn and a combatant that
##     is free to act ([method DuelBattle.switch_problem] -- the local duel's own rule).
##
## APPLY (every peer, host order): [method DuelBattle.apply_command] with the action as
## NetSession stamped it (seq + the verified commit-reveal seed), so a network duel rolls
## exactly as its replay does. A kept CANTO move's follow-up WAIT is applied inside the same
## call on every peer (deterministic, no new roll). The result is the MAIN action's record
## (cmd, result, actor, move, hp ...) plus [code]records[/code] (everything that applied) and,
## when [member presentation] is on, a pre-apply [code]forecast[/code] for the narration.
##
## DIGEST: the board digest (units, HP, statuses, cooldowns, turn, weather) plus the duel's
## own state -- round, decided flag, winner, command count, whose turn it is and both PARTIES
## (every member's HP / statuses / cooldowns / fainted flag, the pending replacements:
## [method DuelBattle.party_digest]) -- so a peer whose duel diverged is caught at the next
## checkpoint, a benched unit included.
##
## TURN CLOCK HOOK (bottom of this file): each action is timed (a SWITCH is the action), a
## pending KO replacement pick has its own short clock; a timeout PASSES the acting combatant, or
## AUTO-PICKS the first healthy benched member in team order ([method timeout_action]).
## [method default_intent] is the seat's sensible default (the brain's pick / the first legal
## move -- what a bot or a stand-in plays), not the clock's timeout.

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


## The acting combatant's side, or -1 (not started / decided). While a KO replacement is
## pending, the side that must pick (side 0 first when both must).
func current_turn_slot() -> int:
	if battle == null or not is_instance_valid(battle):
		return -1
	var pending := battle.pending_replacements()
	if not pending.is_empty():
		return pending[0]
	var actor = battle.current_actor()
	return battle.side_of(actor) if actor != null else -1


func validate_intent(action: Dictionary, actor_slot: int) -> String:
	if not NetProtocol.is_well_formed(action):
		return NetProtocol.INTENT_MALFORMED
	if battle == null or not is_instance_valid(battle) or battle.board == null or battle.turn_system == null:
		return NetProtocol.INTENT_NO_GAME
	if battle.is_over:
		return NetProtocol.INTENT_DUEL_OVER
	var t0: int = int(action[NetProtocol.KEY_TYPE])
	if battle.has_pending_replacement():
		# A fainted combatant's owner picks first; nothing else is legal meanwhile.
		if actor_slot < 0 or not battle.is_pending(actor_slot):
			return NetProtocol.INTENT_NOT_YOUR_TURN
		if t0 != NetProtocol.Action.SWITCH:
			return NetProtocol.INTENT_MUST_PICK
		return _validate_switch(action, actor_slot, true)
	var actor = battle.current_actor()
	if actor == null:
		return NetProtocol.INTENT_NO_ACTIVE_TURN
	if actor_slot < 0 or battle.side_of(actor) != actor_slot:
		return NetProtocol.INTENT_NOT_YOUR_TURN
	var t: int = t0
	match t:
		NetProtocol.Action.MOVE:
			return NetProtocol.INTENT_UNIT_CANNOT_MOVE
		NetProtocol.Action.END_TURN:
			return NetProtocol.INTENT_CANNOT_END_TURN
		NetProtocol.Action.USE_ITEM:
			return NetProtocol.INTENT_NOT_ONLINE
	var d: Dictionary = action[NetProtocol.KEY_DATA]
	if t == NetProtocol.Action.SWITCH:
		return _validate_switch(action, actor_slot, false)
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


## SWITCH (a voluntary switch, or with [param replacement] a KO replacement pick): the named
## member must be on the SENDER's team, benched and healthy, and the duel must allow it now.
func _validate_switch(action: Dictionary, actor_slot: int, replacement: bool) -> String:
	var d: Dictionary = action[NetProtocol.KEY_DATA]
	var rec: Dictionary = battle.member_by_id(String(d.get(NetProtocol.K_UNIT, "")))
	if rec.is_empty():
		return NetProtocol.INTENT_UNKNOWN_UNIT
	if int(rec["side"]) != actor_slot:
		return NetProtocol.INTENT_NOT_YOUR_UNIT
	return battle.switch_problem(actor_slot, int(rec["index"]), replacement)


## The SWITCH a seat submits to bring its bench member [param index] in (its own turn).
func switch_intent(index: int) -> Dictionary:
	var actor = battle.current_actor() if battle != null else null
	if actor == null:
		return {}
	return NetProtocol.switch_to(DuelBattle.member_id(battle.side_of(actor), index))


## The SWITCH seat [param side] submits as its KO replacement pick (member [param index]).
func replacement_intent(side: int, index: int) -> Dictionary:
	return NetProtocol.switch_to(DuelBattle.member_id(side, index))


## The legal default action for seat [param slot] right now, or {} when that seat has nothing to
## do: its KO replacement pick (the brain's best-matched member) when one is pending, else its
## forced pass, else the first legal move (a bot / stand-in's play). NOT the clock's timeout: an
## expired clock passes / auto-picks in team order ([method timeout_action]).
func default_intent(slot: int) -> Dictionary:
	if battle == null or not is_instance_valid(battle) or battle.is_over:
		return {}
	if battle.has_pending_replacement():
		if not battle.is_pending(slot):
			return {}
		var pick := battle.decide_replacement(slot)
		return replacement_intent(slot, pick) if pick >= 0 else {}
	var actor = battle.current_actor()
	if actor == null or battle.side_of(actor) != slot:
		return {}
	if battle.must_pass(actor):
		return pass_intent()
	var legal := battle.legal_slots(actor)
	return use_move_intent(legal[0]) if not legal.is_empty() else pass_intent()


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
		NetUnitIds.id_of(actor) if actor != null else "", battle.party_digest()])


# --- ONLINE TURN CLOCK hook (NetSession's host clock; NetTurnClock) -----------------------------
# The duel's only say in the clock. Everything else (deadlines, broadcast, expiry, the anti-AFK
# strike count and forfeit) is the generic clock in NetSession.
#   * Each ACTION is timed with the duel budget (KIND_ACTION). A voluntary SWITCH is the action
#     (it spends the turn), so it answers that clock like a move does. Running out PASSES the
#     acting combatant's turn (a WAIT -- no damage and no roll for the idle seat; the opponent
#     simply gets the tempo). Deliberately NOT default_intent's "first legal move".
#   * A pending KO replacement pick gets its OWN short clock (KIND_PICK), opened when the faint
#     settles (nobody acts until it is picked), keyed by the picking side and how many of its
#     members have fainted -- so the other seat's simultaneous pick does not restart it.
#     Running out AUTO-PICKS the seat's first healthy benched member in team order (the same
#     "next in order" the engine uses when ko_replacement is off): a pure read of the identical
#     party state, so every peer derives the same SWITCH, and validate_timeout re-checks it.
#   Timed-out actions and picks are strikes; any real action of the seat (a move, a switch, its
#   own pick) clears them (NetSession._apply_now).

func clock_kind() -> String:
	if not is_match_over() and battle.has_pending_replacement():
		return NetTurnClock.KIND_PICK
	return NetTurnClock.KIND_ACTION


## A new key per applied command (and acting combatant): every action gets a fresh clock. While
## a KO replacement is pending: "pick:<side>:<members of that side fainted so far>".
func clock_turn_key() -> String:
	if is_match_over():
		return ""
	if battle.has_pending_replacement():
		var side: int = battle.pending_replacements()[0]
		return "pick:%d:%d" % [side, _fainted_count(side)]
	var actor = battle.current_actor()
	if actor == null:
		return ""
	return "%d:%s" % [battle.result.turns if battle.result != null else 0, NetUnitIds.id_of(actor)]


## The timeout for [param slot] (without the stamp), or {} when its clock is not the open one:
## its KO replacement auto-pick while one is pending, else the acting combatant's pass.
func timeout_action(slot: int) -> Dictionary:
	if is_match_over() or slot < 0 or current_turn_slot() != slot:
		return {}
	if battle.has_pending_replacement():
		var index := auto_pick_index(slot)
		return replacement_intent(slot, index) if index >= 0 else {}
	return pass_intent()


## The member a timed-out KO replacement pick brings in for [param side]: the first healthy
## benched member in team order (-1 when none can come in / nothing is pending).
func auto_pick_index(side: int) -> int:
	if battle == null or not is_instance_valid(battle) or not battle.is_pending(side):
		return -1
	var bench := battle.usable_bench(side)
	return bench[0] if not bench.is_empty() else -1


func _fainted_count(side: int) -> int:
	var n := 0
	for rec in battle.team(side):
		if bool(rec.get("fainted", false)):
			n += 1
	return n
