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
# TURN SOURCE: it counts fires of PlayerManager.player_turn_ended -- spawning at the
# END of a turn (not the start) so the owner's units have already vacated their spawn
# cells, and an Endless wave lands on a cleared home cell once per its OWNER's turn
# instead of deferring on the occupied cell. A unit that spawns this way is marked
# already-acted, so it holds its post the turn it appears and only moves next turn.
# We keep our OWN counter (one increment per fire) rather than reading turn_number, which
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

# Optional board seam. When null the live board is read off CombatServices; tests
# inject a lightweight fake here so the occupancy guard / spill search can run
# headless without an autoload or a live scene. See _board().
var _board_override = null

# How far (Chebyshev rings) a spawner will look for a free cell when its home cell
# is occupied, before giving up and deferring. Radius 2 covers the 24 cells around
# the home, which is plenty of breathing room for a loitering occupant.
const SPILL_RADIUS: int = 2

# Monotonic per-turn counter: 0 before the first turn, incremented once per
# player_turn_started fire (or per process_turn() call in tests).
var _current_turn: int = 0

# Per-point runtime state, keyed by Vector3i(pos.x, pos.y, player_id) -- a cell holds
# exactly one spawn point per player, so that triple is a stable identity. Each value
# is a Dictionary; see _register_point for the exact fields.
var _points: Dictionary = {}

# The turn system we're currently listening to for turn_ended (re-wired if it switches).
var _watched_ts = null


# --- Setup ------------------------------------------------------------------

func setup(map_loader, map_resource) -> void:
	"""Live entry point: build per-point state, adopt the load-time seed units so we
	can watch them die, and subscribe to the per-turn signal. Called by
	GameWorldManager once the board has been rebuilt for the new map."""
	initialize(map_loader, map_resource)
	_resolve_seed_units()
	# Spawn at the END of each turn, driven by the ACTIVE TURN SYSTEM's turn_ended --
	# the reliable per-turn signal that fires for EVERY player's turn (human and AI).
	# (PlayerManager.player_turn_ended only fires on the human's End-Turn button, never
	# for AI turns, so endless waves never ran off it -- the "endless doesn't spawn" bug.)
	# Mirrors how TurnIndicator wires to the turn system.
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())


## (Re)wire to the active turn system's turn_ended when it activates or switches.
func _on_turn_system_activated(ts) -> void:
	if _watched_ts == ts:
		return
	if _watched_ts != null and is_instance_valid(_watched_ts) \
			and _watched_ts.turn_ended.is_connected(_on_turn_ended):
		_watched_ts.turn_ended.disconnect(_on_turn_ended)
	_watched_ts = ts
	if ts != null and not ts.turn_ended.is_connected(_on_turn_ended):
		ts.turn_ended.connect(_on_turn_ended)


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

func _on_turn_ended(player) -> void:
	# Fire at the END of a turn, not the start: by now the owner's units have moved
	# off their spawn cells (endless seeds are force-aggressive and charge away), so
	# the home cell is clear and the wave actually lands instead of deferring on an
	# occupied cell. Endless is gated to the OWNER whose turn just ended, so it spawns
	# exactly once per that player's turn.
	var pid: int = -1
	if player != null and "player_id" in player:
		pid = int(player.player_id)
	process_turn(pid)


func process_turn(ending_player_id: int = -1) -> void:
	"""Advance the turn clock by one and evaluate every scheduled point. Public so
	tests can drive it directly without a live turn system.

	[param ending_player_id] is the id of the player whose turn just ended (the live
	caller passes it); Endless points are only evaluated for their owner so an endless
	wave fires once per owner turn, not on every player's turn. The default of -1
	(tests / no owner context) evaluates every point, preserving the old behaviour."""
	_current_turn += 1
	for key in _points.keys():
		_evaluate_point(_points[key], ending_player_id)


func _evaluate_point(state: Dictionary, ending_player_id: int = -1) -> void:
	match String(state["kind"]):
		MapResource.SPAWN_KIND_REINFORCEMENT:
			_evaluate_reinforcement(state)
		MapResource.SPAWN_KIND_RESPAWN:
			_evaluate_respawn(state)
		MapResource.SPAWN_KIND_ENDLESS:
			# Only the owner's own turn-end drives their endless wave. -1 = no owner
			# context (tests) -> evaluate regardless.
			if ending_player_id < 0 or int(state["player_id"]) == ending_player_id:
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
	true on success and updates the point's produced count / timers / tracked unit.

	Occupancy: one cell holds exactly one living unit, so we never stack onto a home
	cell that is already occupied. Instead of deferring FOREVER (the old behaviour --
	an Endless/Respawn point whose seed loiters on its home cell would then never
	produce again), we SPILL to the nearest free, in-bounds, passable cell in a small
	ring around home (see _find_spill_cell). Only when the whole neighbourhood is full
	do we defer to a later turn. Headless (no board) never blocks, exactly as before."""
	var home: Vector2i = state["position"]
	var spawn_cell: Vector2i = home
	if _cell_blocked(home):
		var spill: Vector2i = _find_spill_cell(home)
		if spill.x < 0:
			return false
		spawn_cell = spill

	if _map_loader == null:
		return false

	# When spilling, hand spawn_unit_now a home-cell override so the unit materialises
	# on the free cell rather than the blocked home. The raw spawn dict is copied so
	# the authored point is never mutated; every other key (character, player, kind...)
	# is preserved.
	var spawn_data = state["spawn"]
	if spawn_cell != home:
		var override: Dictionary = (state["spawn"] as Dictionary).duplicate()
		override["position"] = spawn_cell
		spawn_data = override

	var new_unit = _map_loader.spawn_unit_now(spawn_data, int(state["produced"]))
	if new_unit == null:
		return false

	# Hand the fresh unit to its owning player and the turn system before anything else
	# touches it (see _adopt_spawned_unit -- without this a scheduled wave is inert).
	_adopt_spawned_unit(new_unit, int(state["player_id"]))

	# A unit that spawns mid/end-turn does NOT get to act on the turn it appeared --
	# it stands its post this turn and can move next turn. Mark it acted (duck-typed so
	# the test doubles, which have no turn state, are unaffected).
	if new_unit != null and new_unit.has_method("mark_action_completed"):
		new_unit.mark_action_completed("spawn")

	state["produced"] = int(state["produced"]) + 1
	state["last_spawn_turn"] = _current_turn
	state["death_turn"] = -1
	_track_unit(state, new_unit)
	return true


## Give a freshly scheduled unit an OWNER and a place in the turn order.
##
## [method MapLoader.spawn_unit_now] deliberately only materialises a node on the
## board -- it assigns neither, exactly as documented on
## [code]GameWorldManager.summon_unit[/code], which does both by hand for the
## Necromancer's summons. The load-time flood gets away with it because
## [code]PlayerManager.assign_units_by_parent[/code] sweeps the whole board once
## afterwards; a wave that arrives on turn 7 has no such sweep, so it stayed
## OWNERLESS -- and an ownerless unit is not merely cosmetically odd:
## [code]BoardAdapter.are_enemies[/code] returns false the moment EITHER side has no
## owner, so the unit could neither attack nor be attacked, and the turn system never
## knew about it. Every reinforcement / respawn / endless wave in the game was landing
## as scenery. Doing the same two follow-ups here fixes it at the one point every
## scheduled spawn passes through.
##
## Fully guarded: the test doubles are plain RefCounteds (not [Unit]s) and are skipped,
## an out-of-range player_id is rejected by PlayerManager itself, and a battle with no
## active turn system simply skips registration.
func _adopt_spawned_unit(unit, player_id: int) -> void:
	if unit == null or not (unit is Unit):
		return
	if PlayerManager != null and PlayerManager.has_method("assign_unit_to_player"):
		PlayerManager.assign_unit_to_player(unit, player_id)
	if TurnSystemManager != null and TurnSystemManager.has_method("has_active_turn_system") \
			and TurnSystemManager.has_active_turn_system():
		var ts = TurnSystemManager.get_active_turn_system()
		if ts != null and ts.has_method("register_unit"):
			ts.register_unit(unit)


func _find_spill_cell(home: Vector2i) -> Vector2i:
	"""Nearest free, in-bounds, passable cell in a ring around `home` (Chebyshev rings
	outward to SPILL_RADIUS), or (-1,-1) when the whole neighbourhood is blocked.

	Null-safe: with no board (headless) there is nothing to spill onto, but there is
	also nothing blocking home, so this path is never reached in that case."""
	var board = _board()
	if board == null:
		return Vector2i(-1, -1)
	for r in range(1, SPILL_RADIUS + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				# Only the cells ON this ring (Chebyshev distance == r); inner cells
				# were already tested by a smaller ring.
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell: Vector2i = Vector2i(home.x + dx, home.y + dy)
				if _cell_free_for_spawn(board, cell):
					return cell
	return Vector2i(-1, -1)


func _cell_free_for_spawn(board, cell: Vector2i) -> bool:
	"""True when `cell` can hold a freshly spawned unit: in bounds, passable terrain,
	and not already occupied by a living unit. Each board query is feature-detected so
	lightweight fakes need only provide what they exercise."""
	if board.has_method("in_bounds") and not board.in_bounds(cell):
		return false
	if board.has_method("is_blocked") and board.is_blocked(cell):
		return false
	if board.has_method("is_occupied") and board.is_occupied(cell):
		return false
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
	var board = _board()
	if board == null:
		return false
	return board.is_occupied(cell)


func _board():
	"""The board this scheduler queries: an injected fake (tests) takes priority,
	otherwise the live shared board off CombatServices. Null when neither exists
	(headless with no override, or before the first map load)."""
	if _board_override != null:
		return _board_override
	if CombatServices == null:
		return null
	return CombatServices.board()


# --- Misc -------------------------------------------------------------------

func _point_key(pos: Vector2i, player_id: int) -> Vector3i:
	return Vector3i(pos.x, pos.y, player_id)


func _exit_tree() -> void:
	# Freeing the node already auto-disconnects it from the autoload, but disconnect
	# explicitly so intent is clear and a reused instance can't double-subscribe.
	if TurnSystemManager != null and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	if _watched_ts != null and is_instance_valid(_watched_ts) and _watched_ts.turn_ended.is_connected(_on_turn_ended):
		_watched_ts.turn_ended.disconnect(_on_turn_ended)
