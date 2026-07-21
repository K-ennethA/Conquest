extends Node

class_name SpawnManager

# SpawnManager - runtime scheduler that makes the authored spawn KINDS actually
# fire during a battle. MapLoader._load_units() only ever runs once at map load and
# only materialises the INITIAL units (Start points, plus the first unit of every
# Respawn/Endless point and any Reinforcement due on turn 1). Everything that must
# happen LATER lives here:
#
#   Reinforcement : spawns once when the running turn reaches spawn_turn (>1 only;
#                   a Reinforcement at spawn_turn <= 1 was already placed at load).
#   Respawn       : after its current unit dies, waits respawn_interval turns and
#                   spawns a replacement, up to max_spawns total from that point.
#   Endless       : a spawn portal -- produces a fresh unit every respawn_interval
#                   turns (unbounded), throttled by the interval so it staggers its
#                   reinforcements instead of flooding one per turn.
#   Start         : nothing to do at runtime (handled entirely at load).
#
# OWNERSHIP / LIFETIME: GameWorldManager creates one SpawnManager per battle as a
# child node (see GameWorldManager._setup_spawn_manager) right after the board is
# rebuilt, and frees + recreates it on the next map load. That ties its lifetime to
# a single battle, so its per-point state and turn counter reset cleanly between
# games without any manual teardown (autoloads persist; this node deliberately does
# not).
#
# TURN SOURCE: it counts fires of PlayerManager.player_turn_started -- the exact
# per-turn signal the tile-effect runtime already rides
# (GameWorldManager._on_player_turn_started_tile_effects). We keep our OWN counter
# (one increment per fire) rather than reading PlayerManager.turn_number, which
# counts full rounds, not individual turns -- the scheduler wants a monotonic
# per-turn clock and counting fires is the deterministic, testable choice.
#
# DEATH DETECTION: for Respawn timing we watch the unit's `unit_died` signal (Unit
# emits `signal unit_died(unit)`) -- precise and event-driven, it records the exact
# turn a unit fell. Units this scheduler spawns are wired up as they are created;
# the load-time SEED of a Respawn point (made by MapLoader before this node existed)
# is resolved off the fresh board at setup, while every seed still stands on its
# home cell, and watched the same way. A per-turn liveness fallback
# (is_instance_valid) also stamps a death time if a tracked node ever vanishes
# without our catching the signal, so the timer never wedges.

# Injected collaborators. In the live game these are the real MapLoader and the
# loaded MapResource; in tests they are lightweight fakes / a real MapResource with
# a fake MapLoader, so no live scene is needed.
var _map_loader = null
var _map_resource = null

# Monotonic per-turn counter: 0 before the first turn, incremented once per
# player_turn_started fire (or per process_turn() call in tests).
var _current_turn: int = 0

# Per-point runtime state, keyed by Vector3i(pos.x, pos.y, player_id) -- a cell holds
# exactly one spawn point per player, so that triple is a stable identity. Each value
# is a Dictionary; see _register_point for the exact fields.
var _points: Dictionary = {}


# --- Setup ------------------------------------------------------------------

func setup(map_loader, map_resource) -> void:
	"""Live entry point: build per-point state, adopt the load-time seed units so we
	can watch them die, and subscribe to the per-turn signal. Called by
	GameWorldManager once the board has been rebuilt for the new map."""
	initialize(map_loader, map_resource)
	_resolve_seed_units()
	if PlayerManager != null and not PlayerManager.player_turn_started.is_connected(_on_player_turn_started):
		PlayerManager.player_turn_started.connect(_on_player_turn_started)


func initialize(map_loader, map_resource) -> void:
	"""Build the per-point schedule WITHOUT touching PlayerManager or the board.
	Split out from setup() so tests can drive the scheduler with a fake MapLoader and
	explicit process_turn() calls, no autoloads or live scene required."""
	_map_loader = map_loader
	_map_resource = map_resource
	_current_turn = 0
	_points.clear()
	if _map_resource == null:
		return
	for spawn_data in _map_resource.unit_spawns:
		_register_point(spawn_data)


func _register_point(spawn_data: Dictionary) -> void:
	"""Record one authored spawn point, unless there is nothing to schedule for it."""
	var norm: Dictionary = _map_resource.normalize_spawn(spawn_data)
	var kind: String = String(norm["spawn_kind"])

	# Start points are placed entirely at load -- nothing to do at runtime.
	if kind == MapResource.SPAWN_KIND_START:
		return

	# A spawner with no unit reference can never produce anything (validate_map()
	# already flags this as a map error); skip it so it can't loop uselessly.
	if not _map_resource.spawn_has_unit_reference(spawn_data):
		return

	var pos: Vector2i = norm["position"]
	var player_id: int = int(norm["player_id"])
	var key: Vector3i = _point_key(pos, player_id)

	# CRITICAL double-count guard: MapLoader already materialised the FIRST unit for
	# every point is_initial_spawn() reports true (Start, Respawn/Endless seeds, and a
	# Reinforcement due on turn 1). Start that unit at produced = 1 so the scheduler
	# only ever produces the SUBSEQUENT ones. A Reinforcement scheduled past turn 1
	# was NOT placed at load, so it starts at 0.
	var produced: int = 0
	if _map_resource.is_initial_spawn(spawn_data):
		produced = 1

	_points[key] = {
		"key": key,
		"spawn": spawn_data,                              # RAW dict -> spawn_unit_now
		"kind": kind,
		"position": pos,
		"player_id": player_id,
		"produced": produced,
		"max_spawns": int(norm["max_spawns"]),           # -1 = unlimited
		"respawn_interval": maxi(1, int(norm["respawn_interval"])),
		"spawn_turn": int(norm["spawn_turn"]),
		"last_spawn_turn": 0,                            # turn of the most recent spawn (load == turn 0)
		"current_unit": null,                            # live node this point last produced
		"death_turn": -1,                                # turn current_unit died, or -1
	}


func _resolve_seed_units() -> void:
	"""Adopt the load-time seed of each Respawn point off the fresh board so its death
	can be timed. Only Respawn needs this -- Reinforcement never respawns and Endless
	is periodic (it doesn't wait on a death). At setup, right after the board rebuild,
	every seed still stands on its home cell, so units_at(home) finds it."""
	if CombatServices == null:
		return
	var board = CombatServices.board()
	if board == null:
		return
	for key in _points.keys():
		var state: Dictionary = _points[key]
		if String(state["kind"]) != MapResource.SPAWN_KIND_RESPAWN:
			continue
		if int(state["produced"]) <= 0 or state["current_unit"] != null:
			continue
		var cell: Vector2i = state["position"]
		var seed = _find_unit_at(board, cell, int(state["player_id"]))
		if seed != null:
			_track_unit(state, seed)


func _find_unit_at(board, cell: Vector2i, player_id: int):
	"""First living unit standing on `cell` that belongs to `player_id` (ownership is
	only checked when the unit exposes an owner, so mocks without one still match)."""
	for u in board.units_at(cell):
		if u == null:
			continue
		if u.has_method("get_owner_player"):
			var owner = u.get_owner_player()
			if owner != null and int(owner.player_id) != player_id:
				continue
		return u
	return null


# --- Per-turn scheduling ----------------------------------------------------

func _on_player_turn_started(_player) -> void:
	process_turn()


func process_turn() -> void:
	"""Advance the turn clock by one and evaluate every scheduled point. Public so
	tests can drive it directly without a live turn system."""
	_current_turn += 1
	for key in _points.keys():
		_evaluate_point(_points[key])


func _evaluate_point(state: Dictionary) -> void:
	match String(state["kind"]):
		MapResource.SPAWN_KIND_REINFORCEMENT:
			_evaluate_reinforcement(state)
		MapResource.SPAWN_KIND_RESPAWN:
			_evaluate_respawn(state)
		MapResource.SPAWN_KIND_ENDLESS:
			_evaluate_endless(state)


func _evaluate_reinforcement(state: Dictionary) -> void:
	"""One-shot: fire once the running turn reaches spawn_turn (and only if the point
	still has spawns left -- normally exactly one)."""
	if not _under_cap(state):
		return
	if _current_turn < int(state["spawn_turn"]):
		return
	_try_spawn(state)


func _evaluate_respawn(state: Dictionary) -> void:
	"""Death-gated: replace the fallen unit respawn_interval turns after it died, up
	to max_spawns total from this point."""
	if not _under_cap(state):
		return
	# Still have a living unit -> nothing to do.
	if _point_has_live_unit(state):
		return
	# No living unit: we need a death timestamp to run the interval from. The
	# unit_died handler normally sets it; if a tracked node simply vanished, the
	# liveness check above already stamped it. If we never had/adopted a unit
	# (death_turn still -1), wait rather than guessing.
	var death_turn: int = int(state["death_turn"])
	if death_turn < 0:
		return
	if _current_turn - death_turn < int(state["respawn_interval"]):
		return
	_try_spawn(state)


func _evaluate_endless(state: Dictionary) -> void:
	"""Periodic: produce a fresh unit every respawn_interval turns since the last
	spawn (load counts as turn 0). Unbounded -- max_spawns is -1 for Endless."""
	if not _under_cap(state):
		return
	if _current_turn - int(state["last_spawn_turn"]) < int(state["respawn_interval"]):
		return
	_try_spawn(state)


func _under_cap(state: Dictionary) -> bool:
	"""True while this point may still produce another unit (-1 max = unlimited)."""
	var cap: int = int(state["max_spawns"])
	if cap < 0:
		return true
	return int(state["produced"]) < cap


func _try_spawn(state: Dictionary) -> bool:
	"""Materialise one unit for this point, honouring the occupancy guard. Returns
	true on success and updates the point's produced count / timers / tracked unit."""
	# Occupancy guard: never stack onto a home cell that already holds a living unit,
	# which would break the board (one cell, one occupant). Defer to a later eligible
	# turn instead of stacking. Endless especially can catch its own previous unit
	# loitering on the home cell -- deferring is the natural throttle there.
	var cell: Vector2i = state["position"]
	if _cell_blocked(cell):
		print("[SpawnManager] Home cell %s occupied; deferring %s spawn to a later turn." % [
			str(cell), String(state["kind"])])
		return false

	if _map_loader == null:
		return false

	var new_unit = _map_loader.spawn_unit_now(state["spawn"], int(state["produced"]))
	if new_unit == null:
		print("[SpawnManager] spawn_unit_now returned null for point at %s; will retry." % str(cell))
		return false

	state["produced"] = int(state["produced"]) + 1
	state["last_spawn_turn"] = _current_turn
	state["death_turn"] = -1
	_track_unit(state, new_unit)
	return true


# --- Death tracking ---------------------------------------------------------

func track_seed_unit(position: Vector2i, player_id: int, unit) -> bool:
	"""Adopt an already-existing unit (a load-time seed) as the current unit of the
	point at (position, player_id), so its death is watched. This is the seam
	_resolve_seed_units() uses live -- pulling the node off the board -- and that tests
	use to inject a fake seed. Returns false when no scheduled point matches."""
	var key: Vector3i = _point_key(position, player_id)
	if not _points.has(key):
		return false
	_track_unit(_points[key], unit)
	return true


func _track_unit(state: Dictionary, unit) -> void:
	"""Start watching `unit` for this point: record it as the point's current unit and
	connect its death signal so we can time a respawn."""
	state["current_unit"] = unit
	if unit == null:
		return
	if unit.has_signal("unit_died"):
		var cb := Callable(self, "_on_tracked_unit_died").bind(state["key"])
		if not unit.unit_died.is_connected(cb):
			unit.unit_died.connect(cb)


func _on_tracked_unit_died(_dead_unit, key) -> void:
	"""Record the turn a tracked unit fell so the Respawn interval can run from it."""
	if not _points.has(key):
		return
	var state: Dictionary = _points[key]
	state["death_turn"] = _current_turn
	state["current_unit"] = null


func _point_has_live_unit(state: Dictionary) -> bool:
	"""True while this point's tracked unit is still alive. Doubles as the liveness
	fallback: if the node vanished without our catching unit_died, drop it and stamp
	the death turn so the respawn timer still starts."""
	var unit = state["current_unit"]
	if unit == null:
		return false
	if not is_instance_valid(unit):
		state["current_unit"] = null
		if int(state["death_turn"]) < 0:
			state["death_turn"] = _current_turn
		return false
	if unit.has_method("is_alive"):
		return unit.is_alive()
	return true


# --- Occupancy guard --------------------------------------------------------

func _cell_blocked(cell: Vector2i) -> bool:
	"""True when the live board reports a living unit on `cell`. Null-safe: before the
	first board rebuild (or in headless tests) there is no board, so nothing blocks."""
	if CombatServices == null:
		return false
	var board = CombatServices.board()
	if board == null:
		return false
	return board.is_occupied(cell)


# --- Misc -------------------------------------------------------------------

func _point_key(pos: Vector2i, player_id: int) -> Vector3i:
	return Vector3i(pos.x, pos.y, player_id)


func _exit_tree() -> void:
	# Freeing the node already auto-disconnects it from the autoload, but disconnect
	# explicitly so intent is clear and a reused instance can't double-subscribe.
	if PlayerManager != null and PlayerManager.player_turn_started.is_connected(_on_player_turn_started):
		PlayerManager.player_turn_started.disconnect(_on_player_turn_started)
