extends RefCounted
class_name NetGameRules

## The game-rules half of a network match: host-side intent VALIDATION and the
## ONE deterministic APPLY function every peer (host included) runs for each
## accepted action. [NetSession] is transport + ordering only; it hands actions
## to an object with this interface:
##
##   validate_intent(action: Dictionary, actor_slot: int) -> String   ("" = legal)
##   apply_action(action: Dictionary) -> Dictionary                  (result)
##   current_turn_slot() -> int
##   state_digest() -> int
##
## It works on whatever board / turn system its two providers return, so the
## live game passes CombatServices.board() + the active TurnSystemManager system
## while tests pass a per-peer [BoardAdapter] over a throwaway map and their own
## [TraditionalTurnSystem] / [SpeedFirstTurnSystem] node. The apply path uses the
## SAME primitives as local play (board.move_unit + GameEvents.unit_moved +
## mark_moved; Unit.perform_move -> MoveExecutor + MovesetController.on_used +
## mark_action_completed; turn_system.mark_unit_acted; end_turn_manually), so a
## network move behaves exactly like a hotseat move.
##
## DETERMINISM: combat rolls come from an RNG seeded from (match_seed, seq) and
## installed as [member CombatServices.match_rng] for the whole apply, so the
## executor AND secondary contexts (abilities, status ticks, tile effects that
## build their own MoveContext) roll identically on every peer.

## Emitted on every peer after an accepted action was applied.
signal action_applied(action: Dictionary, result: Dictionary)

var match_seed: int = 0
var _board_provider: Callable
var _turn_provider: Callable
## In/out counter for ids of units that appear mid-match (see [NetUnitIds]).
var _spawn_counter: Array = [0]


func _init(board_provider: Callable, turn_provider: Callable, seed_value: int = 0) -> void:
	_board_provider = board_provider
	_turn_provider = turn_provider
	match_seed = seed_value


func board():
	return _board_provider.call() if _board_provider.is_valid() else null


func turn_system():
	return _turn_provider.call() if _turn_provider.is_valid() else null


## Assign the match-start unit ids. Call once, after the map loaded and players
## were assigned, on every peer.
func assign_initial_ids() -> void:
	NetUnitIds.assign(board(), true)


func find_unit(unit_id: String):
	return NetUnitIds.find(board(), unit_id)


## Slot whose turn it is (owner of the active player / acting unit), -1 if none.
func current_turn_slot() -> int:
	var ts = turn_system()
	if ts == null or not ts.has_method("get_current_active_player"):
		return -1
	var p = ts.get_current_active_player()
	if p == null or not ("player_id" in p):
		return -1
	return int(p.player_id)


# ---------------------------------------------------------------------------
# Validation (host only)
# ---------------------------------------------------------------------------

## Return "" when [param action] is legal for [param actor_slot], else a short
## machine-readable rejection reason.
func validate_intent(action: Dictionary, actor_slot: int) -> String:
	if not NetProtocol.is_well_formed(action):
		return "malformed"
	var ts = turn_system()
	var b = board()
	if ts == null or b == null:
		return "no_game"
	if "is_active" in ts and not bool(ts.is_active):
		return "no_active_turn"
	if actor_slot < 0 or current_turn_slot() != actor_slot:
		return "not_your_turn"

	var t: int = action[NetProtocol.KEY_TYPE]
	var d: Dictionary = action[NetProtocol.KEY_DATA]
	if t == NetProtocol.Action.END_TURN:
		if ts.has_method("can_end_turn_manually") and not ts.can_end_turn_manually():
			return "cannot_end_turn"
		return ""

	var unit = find_unit(String(d[NetProtocol.K_UNIT]))
	if unit == null:
		return "unknown_unit"
	if NetUnitIds.owner_slot(unit) != actor_slot:
		return "not_your_unit"
	if unit.has_method("is_alive") and not unit.is_alive():
		return "unit_dead"

	match t:
		NetProtocol.Action.MOVE:
			return _validate_move(unit, NetProtocol.cell_from_wire(d[NetProtocol.K_TO]), ts, b)
		NetProtocol.Action.USE_MOVE:
			return _validate_use_move(unit, int(d[NetProtocol.K_SLOT]),
				NetProtocol.cell_from_wire(d[NetProtocol.K_AIM]), ts, b)
		NetProtocol.Action.WAIT:
			if ts.has_method("can_unit_act") and not ts.can_unit_act(unit):
				return "unit_cannot_act"
			return ""
	return "unknown_action"


func _validate_move(unit, to: Vector2i, ts, b) -> String:
	if ts.has_method("validate_turn_action") and not ts.validate_turn_action(unit, "move"):
		return "unit_cannot_move"
	if unit.has_method("can_move") and not unit.can_move():
		return "unit_cannot_move"
	var profile = unit.get_movement_profile() if unit.has_method("get_movement_profile") else null
	if profile == null:
		return "no_movement_profile"
	var origin: Vector2i = b.cell_of(unit)
	if to == origin:
		return "illegal_destination"
	var reachable: Array[Vector2i] = MovementResolver.new().reachable_cells(origin, profile, b, unit)
	if not reachable.has(to):
		return "illegal_destination"
	return ""


func _validate_use_move(unit, slot: int, aim: Vector2i, ts, b) -> String:
	if ts.has_method("can_unit_act") and not ts.can_unit_act(unit):
		return "unit_cannot_act"
	if unit.has_method("can_act") and not unit.can_act():
		return "unit_cannot_act"
	var move = unit.get_move(slot) if unit.has_method("get_move") else null
	if move == null or move.targeting_for(unit) == null:
		return "no_move_in_slot"
	var controller = unit.get_moveset_controller() if unit.has_method("get_moveset_controller") else null
	if controller != null and controller.has_method("can_use") and not controller.can_use(move):
		return "move_unavailable"
	var origin: Vector2i = b.cell_of(unit)
	if not move.can_aim_at(origin, aim, unit) or not move.can_target(origin, aim, unit, b):
		return "illegal_target"
	if requires_unit_target(move, unit) and not has_eligible_unit_at(b, move, unit, aim):
		return "illegal_target"
	return ""


## Mirrors UnitActionsPanel._move_requires_unit_target: unit-target kinds must be
## aimed at an occupied cell, unless the pattern lands on an EMPTY cell (a leap).
static func requires_unit_target(move, caster) -> bool:
	var pattern = move.targeting_for(caster) if move != null else null
	if pattern == null or pattern.requires_empty_cell:
		return false
	match pattern.target_kind:
		CombatTypes.TargetKind.ENEMY, CombatTypes.TargetKind.ALLY, CombatTypes.TargetKind.ANY_UNIT:
			return true
	return false


## Mirrors UnitActionsPanel._has_eligible_unit_at (allegiance via the board).
static func has_eligible_unit_at(b, move, caster, aim: Vector2i) -> bool:
	var pattern = move.targeting_for(caster)
	for occupant in b.units_at(aim):
		if occupant == null:
			continue
		match pattern.target_kind:
			CombatTypes.TargetKind.ENEMY:
				if b.are_enemies(caster, occupant):
					return true
			CombatTypes.TargetKind.ALLY:
				if occupant == caster:
					if pattern.affects_caster_tile:
						return true
				elif b.are_allies(caster, occupant):
					return true
			_:
				return true
	return false


# ---------------------------------------------------------------------------
# Apply (every peer, identical)
# ---------------------------------------------------------------------------

## The RNG for accepted action [param seq]: a pure function of (match_seed, seq)
## so every peer rolls the same numbers for the same action.
func rng_for(seq: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([match_seed, seq])
	return rng


## Apply an ACCEPTED action. Runs on every peer in host order. Never validates
## (the host already did) beyond null-safety, so peers cannot diverge on a
## re-check that reads presentation state.
func apply_action(action: Dictionary) -> Dictionary:
	var seq: int = int(action.get(NetProtocol.KEY_SEQ, 0))
	var rng := rng_for(seq)
	_install_rng(rng)
	var result := _apply(action, rng)
	# Units that appeared as a consequence (summons, reinforcements) get ids now,
	# in the same order on every peer.
	NetUnitIds.assign(board(), false, _spawn_counter)
	action_applied.emit(action, result)
	return result


func _apply(action: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ts = turn_system()
	var b = board()
	var t: int = int(action.get(NetProtocol.KEY_TYPE, -1))
	var d: Dictionary = action.get(NetProtocol.KEY_DATA, {})
	if t == NetProtocol.Action.END_TURN:
		var ended: bool = ts != null and ts.has_method("end_turn_manually") and ts.end_turn_manually()
		return {"ok": ended}

	var unit = find_unit(String(d.get(NetProtocol.K_UNIT, "")))
	if unit == null or b == null:
		push_warning("NetGameRules: accepted action references missing unit/board: %s" % str(action))
		return {"ok": false, "reason": "unknown_unit"}

	match t:
		NetProtocol.Action.MOVE:
			var from: Vector2i = b.cell_of(unit)
			var to: Vector2i = NetProtocol.cell_from_wire(d.get(NetProtocol.K_TO))
			# Same primitive the AI uses (BotTurnDriver._relocate): the board snaps
			# the unit's root; UnitAnimator glides the mesh off unit_moved.
			b.move_unit(unit, to)
			if GameEvents:
				GameEvents.unit_moved.emit(unit, Vector3(from.x, 0, from.y), Vector3(to.x, 0, to.y))
			if unit.has_method("mark_moved"):
				unit.mark_moved()
			return {"ok": true, "from": from, "to": to}
		NetProtocol.Action.USE_MOVE:
			var slot: int = int(d.get(NetProtocol.K_SLOT, -1))
			var aim: Vector2i = NetProtocol.cell_from_wire(d.get(NetProtocol.K_AIM))
			var move = unit.get_move(slot)
			var res: Dictionary = unit.perform_move(slot, aim, b, rng)
			if bool(res.get("success", false)):
				var mc = unit.get_moveset_controller() if unit.has_method("get_moveset_controller") else null
				if mc != null and mc.has_method("on_used"):
					mc.on_used(move)
				if is_instance_valid(unit) and unit.has_method("mark_action_completed"):
					unit.mark_action_completed("move")
			res["ok"] = bool(res.get("success", false))
			return res
		NetProtocol.Action.WAIT:
			# Mirrors UnitActionsPanel._on_end_unit_turn_pressed (local WAIT).
			if ts != null and ts.has_method("mark_unit_acted"):
				ts.mark_unit_acted(unit)
			if GameEvents and is_instance_valid(unit):
				GameEvents.unit_action_completed.emit(unit, "end_turn")
			return {"ok": true}
	return {"ok": false, "reason": "unknown_action"}


static func _install_rng(rng: RandomNumberGenerator) -> void:
	if CombatServices != null and "match_rng" in CombatServices:
		CombatServices.match_rng = rng


# ---------------------------------------------------------------------------
# Desync detection
# ---------------------------------------------------------------------------

## A hash of the gameplay state both peers must agree on: every live unit's id,
## cell, HP and per-turn flags, plus whose turn it is. Compared against the
## host's value after each action (see NetSession checkpoints).
func state_digest() -> int:
	var b = board()
	var rows: Array = []
	if b != null and b.has_method("all_units"):
		for u in b.all_units():
			if u == null or not is_instance_valid(u):
				continue
			var cell: Vector2i = b.cell_of(u)
			rows.append([
				NetUnitIds.id_of(u),
				cell.x, cell.y,
				int(u.get_hp()) if u.has_method("get_hp") else 0,
				bool(u.has_acted_this_turn) if "has_acted_this_turn" in u else false,
				bool(u.has_moved_this_turn) if "has_moved_this_turn" in u else false,
			])
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	var ts = turn_system()
	var turn_no: int = int(ts.current_turn) if ts != null and "current_turn" in ts else 0
	return hash([rows, current_turn_slot(), turn_no])
