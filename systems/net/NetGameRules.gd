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
## THE ONE APPLY PATH. This is also where the command-log features live, so every
## consumer shares them: replay recording ([method ReplayRecorder.note_command]),
## the ultimate cut-in announcement on every peer (GameEvents.ultimate_casting),
## cooldown / charge booking for casts ([method MovesetController.on_used] -- including
## dynamic waits a resolution charged for itself, e.g. Voidstep's teleport), canto
## hand-off on WAIT, and ids for mid-match arrivals. [CommandApplier] (the battle seam
## replays drive) is a thin subclass of this class, never a second implementation.
##
## DETERMINISM + FAIR RANDOMNESS: every accepted action carries a 64-bit seed
## ([constant NetProtocol.KEY_RNG]) that each peer derived itself from the
## verified commit-reveal shares of that action ([NetCommitReveal], stamped by
## [NetSession]). The generator seeded from it is passed to the executor AND
## installed as [member CombatServices.match_rng], where it STAYS until the next
## action -- so secondary contexts (abilities, status ticks, tile effects, and the
## turn-start ticks deferred after an END_TURN / last WAIT) all draw from the same
## verified stream and roll identically on every peer. Before the first action,
## [method install_setup_rng] installs a generator from the public setup seed
## (derived from the commitments) for anything rolled while the board is built.
## Offline (solo / replay playback) an action without a stamped seed draws from the
## solo [member match_rng] stream ([MatchRng]) by seq, or (match_seed, seq).

## Emitted on every peer after an accepted action was applied.
signal action_applied(action: Dictionary, result: Dictionary)

## Public setup seed (config "seed", derived from the RNG commitments). Only
## seeds rolls made BEFORE the first accepted action.
var match_seed: int = 0
## Solo / replay stream ([MatchRng]) for actions that carry no stamped seed. Null in
## network play (every accepted action carries its own verified seed).
var match_rng = null
## Highest seq applied so far (informational; folded into nothing that must agree
## between a live match and a replay).
var last_applied_seq: int = 0
var _board_provider: Callable
var _turn_provider: Callable
## In/out counter for ids of units that appear mid-match (see [NetUnitIds]).
var _spawn_counter: Array = [0]


func _init(board_provider: Callable = Callable(), turn_provider: Callable = Callable(), seed_value: int = 0) -> void:
	_board_provider = board_provider
	_turn_provider = turn_provider
	match_seed = seed_value


## Rules over the LIVE battle: CombatServices' board and the active turn system.
static func for_live_battle(seed_value: int = 0) -> NetGameRules:
	return NetGameRules.new(live_board_provider(), live_turn_provider(), seed_value)


static func live_board_provider() -> Callable:
	return func(): return CombatServices.board() if CombatServices != null else null


static func live_turn_provider() -> Callable:
	return func():
		if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null \
				and TurnSystemManager.has_active_turn_system():
			return TurnSystemManager.get_active_turn_system()
		return null


func board():
	return _board_provider.call() if _board_provider.is_valid() else null


func turn_system():
	return _turn_provider.call() if _turn_provider.is_valid() else null


## Assign the match-start unit ids. Call once, after the map loaded and players
## were assigned, on every peer. Units that already carry an id keep it, so calling
## it from both the battle seam and the network attach is harmless.
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
# Validation (host; clients re-run it on their own state)
# ---------------------------------------------------------------------------

## Return "" when [param action] is legal for [param actor_slot], else one of the
## [code]NetProtocol.INTENT_*[/code] reasons (machine-readable; see
## [method NetProtocol.describe_intent_rejection] for the player-facing line).
func validate_intent(action: Dictionary, actor_slot: int) -> String:
	if not NetProtocol.is_well_formed(action):
		return NetProtocol.INTENT_MALFORMED
	var ts = turn_system()
	var b = board()
	if ts == null or b == null:
		return NetProtocol.INTENT_NO_GAME
	if "is_active" in ts and not bool(ts.is_active):
		return NetProtocol.INTENT_NO_ACTIVE_TURN
	if actor_slot < 0 or current_turn_slot() != actor_slot:
		return NetProtocol.INTENT_NOT_YOUR_TURN

	var t: int = action[NetProtocol.KEY_TYPE]
	var d: Dictionary = action[NetProtocol.KEY_DATA]
	if t == NetProtocol.Action.END_TURN:
		if ts.has_method("can_end_turn_manually") and not ts.can_end_turn_manually():
			return NetProtocol.INTENT_CANNOT_END_TURN
		return NetProtocol.INTENT_OK

	var unit = find_unit(String(d[NetProtocol.K_UNIT]))
	if unit == null:
		return NetProtocol.INTENT_UNKNOWN_UNIT
	if NetUnitIds.owner_slot(unit) != actor_slot:
		return NetProtocol.INTENT_NOT_YOUR_UNIT
	if unit.has_method("is_alive") and not unit.is_alive():
		return NetProtocol.INTENT_UNIT_DEAD

	match t:
		NetProtocol.Action.MOVE:
			return _validate_move(unit, NetProtocol.cell_from_wire(d[NetProtocol.K_TO]), ts, b)
		NetProtocol.Action.USE_MOVE:
			return _validate_use_move(unit, int(d[NetProtocol.K_SLOT]),
				NetProtocol.cell_from_wire(d[NetProtocol.K_AIM]), ts, b)
		NetProtocol.Action.WAIT:
			if ts.has_method("can_unit_act") and not ts.can_unit_act(unit):
				return NetProtocol.INTENT_UNIT_CANNOT_ACT
			return NetProtocol.INTENT_OK
		NetProtocol.Action.USE_ITEM:
			return _validate_use_item(unit, d, ts, b)
	return NetProtocol.INTENT_UNKNOWN_ACTION


func _validate_move(unit, to: Vector3i, ts, b) -> String:
	if ts.has_method("validate_turn_action") and not ts.validate_turn_action(unit, "move"):
		return NetProtocol.INTENT_UNIT_CANNOT_MOVE
	if unit.has_method("can_move") and not unit.can_move():
		return NetProtocol.INTENT_UNIT_CANNOT_MOVE
	var profile = unit.get_movement_profile() if unit.has_method("get_movement_profile") else null
	if profile == null:
		return NetProtocol.INTENT_NO_MOVEMENT_PROFILE
	var origin: Vector3i = b.cell_of(unit)
	if to == origin:
		return NetProtocol.INTENT_ILLEGAL_DESTINATION
	var reachable: Array[Vector3i] = MovementResolver.new().reachable_cells(origin, profile, b, unit)
	if not reachable.has(to):
		return NetProtocol.INTENT_ILLEGAL_DESTINATION
	return NetProtocol.INTENT_OK


## USE_ITEM: the user may act, the item is a battle consumable, the target is a living ally (or
## the user) the item would actually help. How MANY the user holds is the owning mode's ledger
## (the duel's bag, [DuelBattle.use_item]) -- the rules only know what an item does.
func _validate_use_item(unit, d: Dictionary, ts, b) -> String:
	if ts.has_method("can_unit_act") and not ts.can_unit_act(unit):
		return NetProtocol.INTENT_UNIT_CANNOT_ACT
	var item: ItemResource = ItemLibrary.get_item(String(d.get(NetProtocol.K_ITEM, "")))
	if item == null or item.consumable == null or not item.consumable.usable_in_battle:
		return NetProtocol.INTENT_ILLEGAL_TARGET
	var target = find_unit(String(d.get(NetProtocol.K_TARGET, "")))
	if target == null:
		return NetProtocol.INTENT_UNKNOWN_UNIT
	if target != unit and not (b.has_method("are_allies") and b.are_allies(unit, target)):
		return NetProtocol.INTENT_ILLEGAL_TARGET
	if not bool(item.consumable.check_unit(target)["ok"]):
		return NetProtocol.INTENT_ILLEGAL_TARGET
	return NetProtocol.INTENT_OK


func _validate_use_move(unit, slot: int, aim: Vector3i, ts, b) -> String:
	if ts.has_method("can_unit_act") and not ts.can_unit_act(unit):
		return NetProtocol.INTENT_UNIT_CANNOT_ACT
	if unit.has_method("can_act") and not unit.can_act():
		return NetProtocol.INTENT_UNIT_CANNOT_ACT
	var move = unit.get_move(slot) if unit.has_method("get_move") else null
	if move == null or move.targeting_for(unit) == null:
		return NetProtocol.INTENT_NO_MOVE_IN_SLOT
	var controller = unit.get_moveset_controller() if unit.has_method("get_moveset_controller") else null
	if controller != null and controller.has_method("can_use") and not controller.can_use(move):
		return NetProtocol.INTENT_MOVE_UNAVAILABLE
	var origin: Vector3i = b.cell_of(unit)
	# Floor-aware: range = Cells.distance, melee only on-floor or across a link,
	# line of sight / elevation rules via the pattern (same checks MoveExecutor runs).
	# Two-mode moves (e.g. Voidstep: place an anchor on free ground / teleport onto an
	# own anchor) resolve their mode from the aim inside the pattern's aim rule, so the
	# same check covers both.
	if not move.can_aim_at(origin, aim, unit, b) or not move.can_target(origin, aim, unit, b):
		return NetProtocol.INTENT_ILLEGAL_TARGET
	if requires_unit_target(move, unit) and not has_eligible_unit_at(b, move, unit, aim):
		return NetProtocol.INTENT_ILLEGAL_TARGET
	return NetProtocol.INTENT_OK


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
static func has_eligible_unit_at(b, move, caster, aim: Vector3i) -> bool:
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

## The RNG for an accepted action: a pure function of its stamped seed
## ([constant NetProtocol.KEY_RNG]). An action without one (solo play / replays of
## solo battles / tests -- NetSession always stamps) draws from the solo
## [member match_rng] stream by seq, else from (match_seed, seq).
func rng_for_action(action: Dictionary) -> RandomNumberGenerator:
	var stamped: int = int(action.get(NetProtocol.KEY_RNG, 0))
	if stamped != 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = stamped
		return rng
	var seq: int = int(action.get(NetProtocol.KEY_SEQ, 0))
	if match_rng != null and match_rng.has_method("rng_for"):
		return match_rng.rng_for(seq)
	var fallback := RandomNumberGenerator.new()
	fallback.seed = hash([match_seed, seq])
	return fallback


## Install the setup generator (public seed) for rolls made while the match is
## being set up, before any accepted action. Call on every peer before the turn
## system starts.
static func install_setup_rng(setup_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = setup_seed
	_install_rng(rng)


## Apply an ACCEPTED action. Runs on every peer in host order. Never validates
## (the host already did, and clients re-validated in NetSession) beyond
## null-safety, so peers cannot diverge on a re-check that reads presentation state.
## Result: { ok:bool, type:int, seq:int, reason:String, events:Array, ... }.
func apply_action(action: Dictionary) -> Dictionary:
	var seq: int = int(action.get(NetProtocol.KEY_SEQ, 0))
	last_applied_seq = maxi(last_applied_seq, seq)
	# REPLAY RECORDING, apply-side: every networked action passes through here exactly
	# once on every peer, so this records a networked match completely. A no-op (one
	# compare) when no recorder is mounted -- and never during playback, which mounts none.
	ReplayRecorder.note_command(action, int(action.get(NetProtocol.KEY_ACTOR, -1)))
	var rng := rng_for_action(action)
	_install_rng(rng)
	var result := _apply(action, rng)
	# Units that appeared as a consequence (summons, reinforcements) get ids now,
	# in the same order on every peer.
	NetUnitIds.assign(board(), false, _spawn_counter)
	result["type"] = int(action.get(NetProtocol.KEY_TYPE, -1))
	result["seq"] = seq
	if not result.has("reason"):
		result["reason"] = ""
	if not result.has("events"):
		result["events"] = []
	action_applied.emit(action, result)
	return result


func _apply(action: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ts = turn_system()
	var b = board()
	var t: int = int(action.get(NetProtocol.KEY_TYPE, -1))
	var d: Dictionary = action.get(NetProtocol.KEY_DATA, {})
	if t == NetProtocol.Action.END_TURN:
		var ended: bool = ts != null and ts.has_method("end_turn_manually") and ts.end_turn_manually()
		return {"ok": ended, "events": [{"effect": "end_turn", "player_id": int(d.get(NetProtocol.K_PLAYER, -1)), "advanced": ended}]}
	if t == NetProtocol.Action.SWITCH:
		# PARTY DUELS: the incoming member is BENCHED (not on the board), so the board that owns
		# the party resolves it ([method DuelBoard.apply_switch]). A board without parties
		# (tactical) has no switch.
		if b != null and b.has_method("apply_switch"):
			return b.apply_switch(d, ts)
		return {"ok": false, "reason": NetProtocol.INTENT_UNKNOWN_ACTION}

	var unit = find_unit(String(d.get(NetProtocol.K_UNIT, "")))
	if unit == null or b == null:
		# A handled rejection: the reason is the return value (CONQUEST.md coding convention 1).
		# In a live match a real divergence still surfaces through the digest checkpoint.
		print_verbose("NetGameRules: accepted action references missing unit/board: %s" % str(action))
		return {"ok": false, "reason": NetProtocol.INTENT_UNKNOWN_UNIT}

	match t:
		NetProtocol.Action.MOVE:
			var from: Vector3i = b.cell_of(unit)
			var to: Vector3i = NetProtocol.cell_from_wire(d.get(NetProtocol.K_TO))
			# Same primitive the AI uses (BotTurnDriver._relocate): an ABSOLUTE set of the
			# unit onto the destination (idempotent even if a local tentative slide raced
			# ahead); UnitAnimator glides the mesh off unit_moved.
			b.move_unit(unit, to)
			# unit_moved in GRID space (Cells.to_grid: Vector3(col, floor, row)) -- the space
			# every listener decodes: tile ON_EXIT / ON_ENTER (traps, Voidstep anchors being
			# stomped), fog-of-war vision, the animator. Headless test doubles (not Nodes)
			# skip it: its listeners are typed to Unit.
			if GameEvents and unit is Node:
				GameEvents.unit_moved.emit(unit, Cells.to_grid(from), Cells.to_grid(to))
			# mark_moved() consumes only the MOVE (not the action) and closes an owed canto.
			if is_instance_valid(unit) and unit.has_method("mark_moved"):
				unit.mark_moved()
			return {"ok": true, "from": from, "to": to,
				"events": [{"effect": "move_unit", "unit_id": NetUnitIds.id_of(unit), "from": from, "to": to}]}
		NetProtocol.Action.USE_MOVE:
			var slot: int = int(d.get(NetProtocol.K_SLOT, -1))
			var aim: Vector3i = NetProtocol.cell_from_wire(d.get(NetProtocol.K_AIM))
			if not unit.has_method("perform_move"):
				return {"ok": false, "reason": "unit_cannot_cast"}
			var move = unit.get_move(slot) if unit.has_method("get_move") else null
			# ULTIMATE CUT-IN, apply-side: every peer (the caster's own included) funnels the
			# accepted cast through here, so the full-screen flash plays exactly once per peer
			# -- and never for a cast the host refused. Fire-and-forget (apply is synchronous).
			_announce_ultimate_cast(unit, move, slot)
			var res: Dictionary = unit.perform_move(slot, aim, b, rng)
			if bool(res.get("success", false)):
				# COOLDOWN / CHARGE booking, in the order the local path books it: on_used
				# AFTER resolution (so a wait the resolution charged for itself -- Voidstep's
				# teleport -- is never stamped back down to the authored one), THEN the action
				# is consumed (greys the unit, advances Speed First).
				_book_move_use(unit, move)
				if is_instance_valid(unit) and unit.has_method("mark_action_completed"):
					unit.mark_action_completed("move")
			res["ok"] = bool(res.get("success", false))
			if not res.has("events"):
				res["events"] = []
			return res
		NetProtocol.Action.WAIT:
			# Mirrors UnitActionsPanel._on_end_unit_turn_pressed (local WAIT): a unit that
			# still owes a canto step gives it up, then its turn is marked done.
			if unit.has_method("finish_canto") and "canto_pending" in unit and bool(unit.canto_pending):
				unit.finish_canto("wait")
			if ts != null and ts.has_method("mark_unit_acted"):
				ts.mark_unit_acted(unit)
			if GameEvents and unit is Node and is_instance_valid(unit):
				GameEvents.unit_action_completed.emit(unit, "end_turn")
			return {"ok": true, "events": [{"effect": "wait", "unit_id": NetUnitIds.id_of(unit)}]}
		NetProtocol.Action.USE_ITEM:
			return _apply_use_item(unit, d, ts, b)
	return {"ok": false, "reason": NetProtocol.INTENT_UNKNOWN_ACTION}


## USE_ITEM, apply-side (every peer / every replay identically): the consumable's effect on the
## target ([method ConsumableEffect.apply_to_unit] -- cure, then a clamped heal; no RNG), the
## heal annotated for the floating text like any heal, then the user's turn is SPENT exactly as
## a WAIT spends it. A use that would do nothing is refused (ok false) and spends nothing.
func _apply_use_item(unit, d: Dictionary, ts, b) -> Dictionary:
	var item_id: String = String(d.get(NetProtocol.K_ITEM, ""))
	var item: ItemResource = ItemLibrary.get_item(item_id)
	if item == null or item.consumable == null:
		return {"ok": false, "reason": "unknown_item"}
	var target = find_unit(String(d.get(NetProtocol.K_TARGET, "")))
	if target == null:
		target = unit
	var check: Dictionary = item.consumable.check_unit(target)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": String(check.get("reason", "no_effect"))}
	var before: int = int(target.get_stat("health")) if target.has_method("get_stat") else 0
	var max_hp: int = int(target.get_base_stat("health")) if target.has_method("get_base_stat") else before
	var heal: int = mini(item.consumable.heal_for(max_hp), maxi(0, max_hp - before))
	if item.consumable.heals() and heal > 0 and target is Object:
		CombatText.annotate(target, {"kind": CombatText.KIND_HEAL, "amount": heal,
			"source": item.display_name, "source_kind": &"item", "source_id": StringName(item_id)})
	var res: Dictionary = item.consumable.apply_to_unit(target, b)
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": String(res.get("reason", "no_effect"))}
	var healed: int = int(res.get("healed", 0))
	if healed > 0 and typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and GameEvents.has_signal(&"unit_healed") and target is Node:
		GameEvents.unit_healed.emit(target, healed)
	# Spend the turn exactly like WAIT (a unit owing a canto step gives it up).
	if unit.has_method("finish_canto") and "canto_pending" in unit and bool(unit.canto_pending):
		unit.finish_canto("wait")
	if ts != null and ts.has_method("mark_unit_acted"):
		ts.mark_unit_acted(unit)
	if GameEvents and unit is Node and is_instance_valid(unit):
		GameEvents.unit_action_completed.emit(unit, "end_turn")
	return {"ok": true, "events": [{"effect": "use_item", "unit_id": NetUnitIds.id_of(unit),
		"item_id": item_id, "target": target, "target_id": NetUnitIds.id_of(target),
		"healed": healed, "hp_before": before, "cured": res.get("cured", [])}]}


## Fire GameEvents.ultimate_casting when the applied cast is an ULTIMATE (the 4th
## moveset slot, or a move flagged is_ultimate -- [method MoveResource.is_ultimate_move]
## is the single authority). [UltimateCutIn] listens and plays the flash, so a REMOTE
## opponent's ultimate lights up this client exactly like a local one. The battle UI's
## networked submit branch deliberately does NOT play it, so the caster flashes once.
## Null-safe: a unit without get_move, an empty slot, an absent GameEvents autoload
## (unit tests, dedicated server) all return without emitting.
static func _announce_ultimate_cast(unit, move, slot: int) -> void:
	if unit == null or move == null:
		return
	if not MoveResource.is_ultimate_move(move, slot):
		return
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and GameEvents.has_signal(&"ultimate_casting"):
		GameEvents.ultimate_casting.emit(unit, move)


## Spend a charge and start the cooldown for the move just resolved --
## [method MovesetController.on_used], the exact call the local path makes after a
## successful perform_move. Duck-typed and null-safe (headless doubles, empty slots).
static func _book_move_use(unit, move) -> void:
	if move == null or not is_instance_valid(unit) or not unit.has_method("get_moveset_controller"):
		return
	var mc = unit.get_moveset_controller()
	if mc != null and mc.has_method("on_used"):
		mc.on_used(move)


static func _install_rng(rng: RandomNumberGenerator) -> void:
	if CombatServices != null and "match_rng" in CombatServices:
		CombatServices.match_rng = rng


# ---------------------------------------------------------------------------
# Desync detection
# ---------------------------------------------------------------------------

## A hash of the gameplay state every peer must agree on: every live unit's id,
## cell, HP, per-turn flags, active statuses (with stacks) and move cooldowns, plus
## whose turn it is, the turn number and the weather. Compared against the host's
## value after each action (see NetSession checkpoints). Statuses and cooldowns are
## part of it because a divergence there (e.g. an unbooked cooldown) otherwise hides
## until it changes a roll several turns later.
func state_digest() -> int:
	var b = board()
	var rows: Array = []
	if b != null and b.has_method("all_units"):
		for u in b.all_units():
			if u == null or not is_instance_valid(u):
				continue
			var cell: Vector3i = b.cell_of(u)
			rows.append([
				NetUnitIds.id_of(u),
				cell.x, cell.y, cell.z,
				int(u.get_hp()) if u.has_method("get_hp") else 0,
				bool(u.has_acted_this_turn) if "has_acted_this_turn" in u else false,
				bool(u.has_moved_this_turn) if "has_moved_this_turn" in u else false,
				statuses_sorted(u),
				cooldowns_sorted(u),
			])
	rows.sort_custom(func(a, c): return String(a[0]) < String(c[0]))
	var ts = turn_system()
	var turn_no: int = int(ts.current_turn) if ts != null and "current_turn" in ts else 0
	return hash([rows, current_turn_slot(), turn_no, weather_digest()])


## The battle weather's comparable state ([method WeatherState.digest]): weather id,
## round, and any summoned override. Folded into [method state_digest] so a peer
## whose weather diverged (a seed or schedule mismatch) is caught as a desync.
static func weather_digest() -> Array:
	if CombatServices != null and "weather" in CombatServices and CombatServices.weather != null:
		return CombatServices.weather.digest()
	return []


## Sorted [ [status_id, stacks], ... ] for a unit's active statuses.
static func statuses_sorted(unit) -> Array:
	var counts: Dictionary = {}
	if unit.has_method("get_status_controller"):
		var sc = unit.get_status_controller()
		if sc != null and sc.has_method("stacks_by_id"):
			counts = sc.stacks_by_id()
	elif unit.has_method("stacks_by_id"):
		counts = unit.stacks_by_id()
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, c): return String(a) < String(c))
	var out: Array = []
	for k in keys:
		out.append([String(k), int(counts[k])])
	return out


## Sorted [ [move_id, cooldown_remaining], ... ] for a unit's moveset.
static func cooldowns_sorted(unit) -> Array:
	var out: Array = []
	if not unit.has_method("get_moveset_controller"):
		return out
	var mc = unit.get_moveset_controller()
	if mc == null:
		return out
	var cds = mc.get("_cooldowns")
	if not (cds is Dictionary):
		return out
	var keys: Array = cds.keys()
	keys.sort_custom(func(a, c): return String(a) < String(c))
	for k in keys:
		out.append([String(k), int(cds[k])])
	return out
