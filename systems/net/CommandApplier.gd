extends RefCounted
class_name CommandApplier

## The ONE mutation point for authoritative-seed lockstep.
##
## Every peer (host included, via NetSession's call_local apply RPC) funnels every
## resolved command through [method apply_command], which drives the EXISTING
## deterministic resolution layer (unit.perform_move -> MoveExecutor) rather than
## re-implementing gameplay. Because all randomness is injected as a seeded RNG
## derived from the command's server-stamped seq, applying the same command from the
## same starting state produces the same result on every peer. Single-player later
## becomes the degenerate case: one local applier, no sockets.
##
## Unit identity: instance ids are NOT stable across peers, so commands reference a
## [UnitRegistry] net_id instead. Map units get ids in deterministic spawn order at
## load; summoned units get ids derived from the summoning command's seq (assigned
## reactively from the resolved event log, which is itself deterministic).
##
## [method hash_match_state] is the desync detector and the test oracle: a stable,
## sort-ordered hash of every unit's (hp, cell, statuses, cooldowns) plus the turn seq.

## move_id/status-id string hashes and Vector2i components are all ints by the time
## they reach the mixer. This marker separates variable-length sub-lists (a unit's
## statuses, its cooldowns) so two different layouts can never hash the same.
const _SEP := 0x7FFFFFF1


## id <-> unit lookup shared by the applier and the checksum. Kept a plain inner
## class (no autoload) so it is trivially constructible in tests and per-match in the
## live game.
class UnitRegistry extends RefCounted:
	## Summoned-unit ids live far above map-unit ids (which start at 1) so the two
	## ranges can never collide. id = BASE + seq*STRIDE + index_within_command.
	const SUMMON_ID_BASE := 1000000
	const SUMMON_STRIDE := 1000

	var _id_to_unit: Dictionary = {}   ## int net_id -> unit
	var _unit_to_id: Dictionary = {}   ## unit (Object) -> int net_id

	func clear() -> void:
		_id_to_unit.clear()
		_unit_to_id.clear()

	## Bind [param unit] to [param net_id]. Also stamps the id as node/object metadata
	## so other systems can read it without the registry, but the registry dicts are
	## the source of truth.
	func register(unit, net_id: int) -> void:
		if unit == null:
			return
		_id_to_unit[net_id] = unit
		_unit_to_id[unit] = net_id
		if unit is Object:
			(unit as Object).set_meta("net_id", net_id)

	## Assign ids to map-spawned [param units] in the given order (which mirrors the
	## deterministic load order for identical match settings). Ids start at 1.
	func assign_map_units(units: Array, start_id: int = 1) -> void:
		var nid: int = start_id
		for u in units:
			if u == null:
				continue
			register(u, nid)
			nid += 1

	## Deterministic id for the [param index]-th unit summoned by command [param seq].
	func summon_id(seq: int, index: int) -> int:
		return SUMMON_ID_BASE + seq * SUMMON_STRIDE + index

	## The unit bound to [param net_id], or null if none / it has been freed.
	func unit_for(net_id: int):
		var u = _id_to_unit.get(net_id, null)
		if u == null:
			return null
		if u is Object and not is_instance_valid(u):
			return null
		return u

	## The net_id bound to [param unit], or -1 if unknown.
	func id_for(unit) -> int:
		return int(_unit_to_id.get(unit, -1))

	func has_id(net_id: int) -> bool:
		return _id_to_unit.has(net_id)

	## Every known net_id in ascending order — the fixed iteration order the state
	## checksum relies on (never scene order).
	func all_ids_sorted() -> Array:
		var ids: Array = _id_to_unit.keys()
		ids.sort()
		return ids


var registry: UnitRegistry
var match_rng: MatchRng
## Highest seq applied so far; folded into the state hash as the "turn/seq" component.
var last_applied_seq: int = 0


func _init(p_registry: UnitRegistry = null, p_match_rng: MatchRng = null) -> void:
	registry = p_registry if p_registry != null else UnitRegistry.new()
	match_rng = p_match_rng


# ---------------------------------------------------------------------------
# The single mutation point
# ---------------------------------------------------------------------------

## Apply one resolved [param cmd] against [param board], mutating game state through
## the existing deterministic resolution layer. [param ctx] is optional injection for
## headless/test use — a Dictionary that may carry { "turn_system": <obj with
## advance_turn()> }; null uses the live autoloads. Returns
## { ok:bool, type:int, seq:int, reason:String, events:Array }.
func apply_command(cmd: Dictionary, board, ctx = null) -> Dictionary:
	if not NetProtocol.is_command_well_formed(cmd):
		return _fail(cmd, "malformed")
	var seq: int = int(cmd.get(NetProtocol.KEY_SEQ, 0))
	last_applied_seq = maxi(last_applied_seq, seq)
	# REPLAY RECORDING, apply-side. This is the ONE mutation point every networked command
	# passes through on every peer, so recording here captures a networked match completely
	# and exactly once (the acting peer's UI submit path deliberately does not also record).
	# A no-op -- one integer compare, no allocation -- when no recorder is mounted.
	ReplayRecorder.note_command(cmd, int(cmd.get(NetProtocol.KEY_ACTOR, -1)))
	var data: Dictionary = cmd[NetProtocol.KEY_DATA]

	match int(cmd[NetProtocol.KEY_TYPE]):
		NetProtocol.Action.CAST_MOVE:
			return _apply_cast_move(cmd, data, board, seq)
		NetProtocol.Action.MOVE_UNIT:
			return _apply_move_unit(cmd, data, board)
		NetProtocol.Action.WAIT_UNIT:
			return _apply_wait_unit(cmd, data)
		NetProtocol.Action.END_TURN:
			return _apply_end_turn(cmd, data, ctx)
	return _fail(cmd, "unsupported_command")


func _apply_cast_move(cmd: Dictionary, data: Dictionary, board, seq: int) -> Dictionary:
	var unit = registry.unit_for(int(data[NetProtocol.KEY_UNIT_ID]))
	if unit == null:
		return _fail(cmd, "unknown_unit")
	if not unit.has_method("perform_move"):
		return _fail(cmd, "unit_cannot_cast")
	# ULTIMATE CUT-IN, APPLY-SIDE. Every peer -- the caster's own client included -- funnels a
	# resolved cast through here, so this is the ONE place the full-screen flash can fire in
	# sync on all of them. See _announce_ultimate_cast for why it emits without awaiting.
	_announce_ultimate_cast(unit, int(data[NetProtocol.KEY_MOVE_SLOT]))
	var rng: RandomNumberGenerator = _rng_for_cmd(cmd)
	var res: Dictionary = unit.perform_move(int(data[NetProtocol.KEY_MOVE_SLOT]), data[NetProtocol.KEY_AIM_CELL], board, rng)
	var events: Array = res.get("events", [])
	# Summoned bodies get deterministic ids from THIS command's seq + their order in
	# the (deterministic) event log.
	_register_summons(events, seq)
	# A successful cast CONSUMES the unit's ACTION for the turn -- exactly what the local
	# UI path (UnitActionsPanel._execute_move_on_target) does after a successful
	# perform_move. This is what greys the unit and, in Speed First, advances the queue
	# (mark_action_completed -> unit_action_completed -> the turn system's completion
	# check) identically on EVERY peer. Without it a networked cast left the unit still
	# lit and never advanced Speed First. Guarded so headless/mock units lacking the hook
	# are skipped. The move (if any) arrives as a SEPARATE MOVE_UNIT command that marks
	# the move, so this only spends the action -- never double-consuming the move.
	if bool(res.get("success", false)):
		# COOLDOWN / CHARGE ACCOUNTING, APPLY-SIDE, and in the SAME ORDER the local path books
		# it (UnitActionsPanel._execute_move_on_target: on_used, THEN mark_action_completed).
		# Without this a networked cast started no cooldown and spent no charge on EITHER peer,
		# so every cooldown move could be spammed and every max_uses move was unlimited. Booking
		# here rather than at the submit site is what keeps it identical on all peers: the local
		# UI's networked branch returns BEFORE its own perform_move/on_used, so apply is the only
		# booking point and a cast can never be booked twice.
		_book_move_use(unit, int(data[NetProtocol.KEY_MOVE_SLOT]))
		if unit.has_method("mark_action_completed"):
			unit.mark_action_completed("move")
	return {
		"ok": bool(res.get("success", false)),
		"type": NetProtocol.Action.CAST_MOVE,
		"seq": seq,
		"reason": String(res.get("reason", "")),
		"events": events,
	}


func _apply_move_unit(cmd: Dictionary, data: Dictionary, board) -> Dictionary:
	var unit = registry.unit_for(int(data[NetProtocol.KEY_UNIT_ID]))
	if unit == null:
		return _fail(cmd, "unknown_unit")
	var dest: Vector2i = data[NetProtocol.KEY_DEST_CELL]
	var from_cell: Vector2i = _cell_of(board, unit)
	# Whether this is a live unit (real world Vector3 position) or a headless/mock one.
	# Only live units emit unit_moved -- mocks (no position) skip it, exactly as before.
	var is_live_unit: bool = unit.get("position") is Vector3
	if board != null and board.has_method("move_unit"):
		board.move_unit(unit, dest)
	# mark_moved() consumes only the MOVE for the turn (not the action) -- mirrors the
	# local commit path (UnitActionsPanel._commit_tentative_move).
	if unit.has_method("mark_moved"):
		unit.mark_moved()
	# Emit GameEvents.unit_moved in GRID space -- Vector3(col, 0, row) -- the SAME space
	# UnitActionsPanel._commit_tentative_move emits and the space every listener decodes
	# (GameWorldManager._on_unit_moved_tile_effects reads round(pos.x)/round(pos.z) as a
	# cell). The old code emitted the unit's WORLD position, so tile ON_EXIT/ON_ENTER fired
	# on the wrong cells in networked play. Every peer (the acting peer's local commit is
	# skipped in networked mode) now fires this identically, so tile effects land on the
	# same cells across all peers.
	if is_live_unit:
		_emit_unit_moved(unit, Vector3(from_cell.x, 0, from_cell.y), Vector3(dest.x, 0, dest.y))
	return _ok(cmd, [{
		"effect": "move_unit",
		"unit_id": int(data[NetProtocol.KEY_UNIT_ID]),
		"from": from_cell,
		"to": dest,
	}])


func _apply_wait_unit(cmd: Dictionary, data: Dictionary) -> Dictionary:
	var unit = registry.unit_for(int(data[NetProtocol.KEY_UNIT_ID]))
	if unit == null:
		return _fail(cmd, "unknown_unit")
	if unit.has_method("mark_action_completed"):
		unit.mark_action_completed("wait")
	return _ok(cmd, [{
		"effect": "wait",
		"unit_id": int(data[NetProtocol.KEY_UNIT_ID]),
	}])


func _apply_end_turn(cmd: Dictionary, data: Dictionary, ctx) -> Dictionary:
	var advanced: bool = _advance_turn(ctx)
	return _ok(cmd, [{
		"effect": "end_turn",
		"player_id": int(data[NetProtocol.KEY_PLAYER_ID]),
		"advanced": advanced,
	}])


# ---------------------------------------------------------------------------
# State checksum — the desync detector and the test oracle
# ---------------------------------------------------------------------------

## Stable hash over every registered unit, in ascending net_id order (never scene
## order), of (hp, cell, sorted statuses, sorted cooldowns), plus the applied seq.
## Identical on two peers iff their gameplay state is identical.
func hash_match_state(board) -> int:
	var parts: Array = [last_applied_seq, _SEP]
	for id in registry.all_ids_sorted():
		parts.append(id)
		var u = registry.unit_for(id)
		if u == null:
			parts.append(-1)   # tombstone: unit gone (dead/despawned)
			parts.append(_SEP)
			continue
		parts.append(_hp(u))
		var cell: Vector2i = _cell_of(board, u)
		parts.append(cell.x)
		parts.append(cell.y)
		for s in _statuses_sorted(u):
			parts.append(s[0])
			parts.append(s[1])
		parts.append(_SEP)
		for c in _cooldowns_sorted(u):
			parts.append(c[0])
			parts.append(c[1])
		parts.append(_SEP)
	return MatchRng._mix(parts)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _rng_for_cmd(cmd: Dictionary) -> RandomNumberGenerator:
	# Prefer the seed the authority stamped onto the command, so every peer builds
	# the identical generator even without a live MatchRng instance.
	if cmd.has(NetProtocol.KEY_RNG_SEED) and int(cmd[NetProtocol.KEY_RNG_SEED]) != 0:
		var r := RandomNumberGenerator.new()
		r.seed = int(cmd[NetProtocol.KEY_RNG_SEED])
		return r
	if match_rng != null:
		return match_rng.rng_for(int(cmd.get(NetProtocol.KEY_SEQ, 0)))
	return null


## Fire [signal GameEvents.ultimate_casting] when the cast being applied is an ULTIMATE (the
## 4th moveset slot, or a move flagged is_ultimate -- [method MoveResource.is_ultimate_move]
## is the single authority). [UltimateCutIn] listens to that signal and plays the full-screen
## flash itself, so a REMOTE opponent's ultimate lights up this client exactly like a local one.
##
## Why HERE and not at the submit site: [UnitActionsPanel] deliberately does NOT play the
## cut-in on its networked branch (it returns before its own `_await_ultimate_cutin`), because
## the submitter has no idea yet whether the server will accept the cast. Apply is the one
## moment every peer agrees the cast is happening, so emitting here plays the flash exactly
## ONCE per peer -- including on the caster's own client, which never double-plays. (The
## overlay's own `_busy` re-entrancy guard drops a second overlapping play regardless.)
##
## Fire-and-forget, deliberately: [method apply_command] is synchronous and returns the applied
## result to [NetSession], so it must not await. The flash therefore runs ALONGSIDE resolution
## rather than strictly before it, which is the local path's only behavioural difference and is
## purely presentational -- no game state depends on it.
##
## Null-safe end to end: a headless/mock unit with no get_move, an absent GameEvents autoload
## (unit tests, dedicated server) and a non-ultimate slot all return without emitting.
func _announce_ultimate_cast(unit, move_slot: int) -> void:
	if unit == null or not unit.has_method("get_move"):
		return
	var move = unit.get_move(move_slot)
	if not MoveResource.is_ultimate_move(move, move_slot):
		return
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and GameEvents.has_signal(&"ultimate_casting"):
		GameEvents.ultimate_casting.emit(unit, move)


## Spend a charge and start the cooldown for the move the caster just resolved --
## [method MovesetController.on_used], the exact call the local path makes after a successful
## perform_move.
##
## ORDERING IS THE WHOLE POINT. It runs AFTER resolution (the effects already ran inside
## perform_move), because on_used starts the wait at `maxi(authored, remaining)` and so never
## shortens one a resolution set for itself through [method MovesetController.cooldown_started]
## -- Duskmaw's Voidstep charges 4 turns to step to its anchor where the move authors 1. Booking
## before resolution would stamp that straight back down to the authored number, on every peer.
##
## Duck-typed and null-safe end to end: a headless/mock unit with no get_move or no
## MovesetController, an empty slot, and a legacy controller lacking on_used all return without
## touching anything, so the mock-driven apply suites are unchanged.
func _book_move_use(unit, move_slot: int) -> void:
	if unit == null or not unit.has_method("get_move") or not unit.has_method("get_moveset_controller"):
		return
	var move = unit.get_move(move_slot)
	if move == null:
		return
	var mc = unit.get_moveset_controller()
	if mc == null or not mc.has_method("on_used"):
		return
	mc.on_used(move)


func _register_summons(events: Array, seq: int) -> void:
	var index: int = 0
	for ev in events:
		if ev is Dictionary and String(ev.get("effect", "")) == "summon":
			var u = ev.get("target", null)
			if u != null:
				registry.register(u, registry.summon_id(seq, index))
				index += 1


func _advance_turn(ctx) -> bool:
	var ts = _turn_system_from(ctx)
	if ts != null and ts.has_method("advance_turn"):
		ts.advance_turn()
		return true
	return false


func _turn_system_from(ctx):
	if ctx is Dictionary and ctx.has("turn_system"):
		return ctx["turn_system"]
	# Live game: the TurnSystemManager autoload owns the active turn system.
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null \
			and TurnSystemManager.has_method("advance_turn"):
		return TurnSystemManager
	return null


func _emit_unit_moved(unit, from_grid, to_grid) -> void:
	# [param from_grid]/[param to_grid] are GRID-space Vector3(col, 0, row) (see the caller),
	# matching UnitActionsPanel._commit_tentative_move. Best-effort + guarded exactly as
	# unit.perform_move guards move_performed, so headless runs without the autoload skip it.
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and from_grid is Vector3 and to_grid is Vector3:
		GameEvents.unit_moved.emit(unit, from_grid, to_grid)


func _cell_of(board, unit) -> Vector2i:
	if board != null and board.has_method("cell_of"):
		return board.cell_of(unit)
	return Vector2i.ZERO


func _hp(unit) -> int:
	if unit.has_method("get_hp"):
		return int(unit.get_hp())
	var h = unit.get("hp")
	if h != null:
		return int(h)
	var ch = unit.get("current_health")
	if ch != null:
		return int(ch)
	if unit.has_method("get_stat"):
		return int(unit.get_stat("health"))
	return 0


## Sorted [ [str_hash(id), stack_count], ... ] for a unit's active statuses.
func _statuses_sorted(unit) -> Array:
	var counts: Dictionary = {}
	if unit.has_method("get_status_controller"):
		var sc = unit.get_status_controller()
		if sc != null and sc.has_method("stacks_by_id"):
			counts = sc.stacks_by_id()
	elif unit.has_method("stacks_by_id"):
		counts = unit.stacks_by_id()
	else:
		var raw = unit.get("statuses")
		if raw is Array:
			for s in raw:
				var sid = s.get("id") if (s is Object) else null
				if sid != null:
					counts[sid] = int(counts.get(sid, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return String(a) < String(b))
	var out: Array = []
	for k in keys:
		out.append([hash(String(k)), int(counts[k])])
	return out


## Sorted [ [str_hash(move_id), cooldown_remaining], ... ] for a unit's moveset.
func _cooldowns_sorted(unit) -> Array:
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
	keys.sort_custom(func(a, b): return String(a) < String(b))
	for k in keys:
		out.append([hash(String(k)), int(cds[k])])
	return out


func _ok(cmd: Dictionary, events: Array) -> Dictionary:
	return {
		"ok": true,
		"type": int(cmd.get(NetProtocol.KEY_TYPE, -1)),
		"seq": int(cmd.get(NetProtocol.KEY_SEQ, 0)),
		"reason": "",
		"events": events,
	}


func _fail(cmd: Dictionary, reason: String) -> Dictionary:
	return {
		"ok": false,
		"type": int(cmd.get(NetProtocol.KEY_TYPE, -1)) if cmd is Dictionary else -1,
		"seq": int(cmd.get(NetProtocol.KEY_SEQ, 0)) if cmd is Dictionary else 0,
		"reason": reason,
		"events": [],
	}
