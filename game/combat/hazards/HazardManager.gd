extends Node

class_name HazardManager

# HazardManager -- the per-battle runtime that ticks every live [TravelingHazard]
# forward. It mirrors [SpawnManager] deliberately, point for point, because they
# solve the same shape of problem (a GameWorldManager-owned, per-turn-ticked,
# headless-testable manager whose state must reset between battles):
#
#   OWNERSHIP / LIFETIME: GameWorldManager creates one per battle as a child node
#     (see GameWorldManager._setup_hazard_manager, beside _setup_spawn_manager) and
#     frees + recreates it on the next map load, so in-flight vines never leak from
#     one battle into the next. Autoloads persist; this node deliberately does not.
#
#   TURN SOURCE: it advances every hazard once per PlayerManager.player_turn_started
#     -- the SAME per-turn signal SpawnManager and the tile-effect runtime ride. A
#     vine cast during the boss's turn therefore resolves its first segment at cast
#     (in SpawnHazardEffect) and then crawls one band per following player-turn.
#     Cadence assumption: per player-turn, NOT per full round.
#
#   EFFECT -> MANAGER SEAM: the casting effect does not hold a reference to this
#     node. It emits GameEvents.hazard_spawn_requested(hazard); this manager listens
#     and adopts the vine. That keeps SpawnHazardEffect free of any hard dependency
#     on a live manager (it degrades to a no-op when nothing listens) and lets a
#     headless test capture the signal instead of standing up a manager.
#
#   TELEGRAPH: each advance re-emits GameEvents.hazard_advanced with the band just
#     entered AND the band the next tick will enter, so a visual layer can show
#     players where the lane is going and let them step out -- the counterplay that
#     makes a wide, accuracy-less vine fair. Full VFX (a vine mesh) is out of scope;
#     a signal (+ optional cell highlight) is enough. TODO(art): render the lane.
#
#   TESTABILITY: initialize() + register() + process_turn() are split out so tests
#     drive the whole lifecycle with a mock board and NO autoloads / live scene,
#     exactly like SpawnManager.initialize() / process_turn().

## Active vines, advanced in registration order each tick.
var _hazards: Array = []

# The turn system we're currently listening to for turn_started (re-wired on switch).
var _watched_ts = null


# --- Setup ------------------------------------------------------------------

func setup() -> void:
	"""Live entry point: clear state, then subscribe to the per-turn tick and the
	spawn-request seam. Called by GameWorldManager once per battle."""
	initialize()
	# Tick on the ACTIVE TURN SYSTEM's turn_started -- the reliable per-turn signal that
	# fires every turn (human and AI). PlayerManager.player_turn_started only fires on
	# game start + the human End-Turn button, so hazards never advanced during AI turns.
	# Mirrors SpawnManager / TurnIndicator wiring.
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())
	if GameEvents != null and GameEvents.has_signal(&"hazard_spawn_requested") \
			and not GameEvents.hazard_spawn_requested.is_connected(_on_hazard_spawn_requested):
		GameEvents.hazard_spawn_requested.connect(_on_hazard_spawn_requested)


## (Re)wire to the active turn system's turn_started when it activates or switches.
func _on_turn_system_activated(ts) -> void:
	if _watched_ts == ts:
		return
	if _watched_ts != null and is_instance_valid(_watched_ts) \
			and _watched_ts.turn_started.is_connected(_on_player_turn_started):
		_watched_ts.turn_started.disconnect(_on_player_turn_started)
	_watched_ts = ts
	if ts != null and not ts.turn_started.is_connected(_on_player_turn_started):
		ts.turn_started.connect(_on_player_turn_started)


func initialize() -> void:
	"""Reset the active-hazard list WITHOUT touching PlayerManager or GameEvents, so
	tests can drive register()/process_turn() with no autoloads or live scene."""
	_hazards.clear()


## Adopt [param hazard] so it advances on subsequent ticks. Public so both the live
## seam and tests can add vines directly.
func register(hazard) -> void:
	if hazard == null:
		return
	_hazards.append(hazard)


## Number of vines still travelling (test/inspection convenience).
func active_count() -> int:
	return _hazards.size()


func _on_hazard_spawn_requested(hazard) -> void:
	register(hazard)


# --- Per-turn tick ----------------------------------------------------------

func _on_player_turn_started(_player) -> void:
	process_turn()


func process_turn() -> void:
	"""Advance every live hazard one step, apply its band damage, telegraph it, and
	drop the ones that have finished. Public so tests drive it without a turn system.
	Resolves the board null-safely via CombatServices (there is none before the first
	rebuild / in a headless test)."""
	var board = _board()
	var survivors: Array = []
	for hazard in _hazards:
		if hazard == null:
			continue
		if hazard.is_expired():
			_emit_expired(hazard)
			continue
		var result: Dictionary = hazard.advance(board)
		_emit_advanced(hazard, result)
		if hazard.is_expired():
			_emit_expired(hazard)
		else:
			survivors.append(hazard)
	_hazards = survivors


func _board():
	if CombatServices == null:
		return null
	return CombatServices.board()


# --- Telegraph signals ------------------------------------------------------

func _emit_advanced(hazard, result: Dictionary) -> void:
	if GameEvents == null or not GameEvents.has_signal(&"hazard_advanced"):
		return
	var cells: Array = result.get("cells", [])
	var next_cells: Array = result.get("next_cells", [])
	var total: int = 0
	for d in result.get("damaged", []):
		total += int(d.get("amount", 0))
	GameEvents.emit_signal(&"hazard_advanced", hazard, cells, next_cells, total)


func _emit_expired(hazard) -> void:
	if GameEvents != null and GameEvents.has_signal(&"hazard_expired"):
		GameEvents.emit_signal(&"hazard_expired", hazard)


# --- Mid-battle save / resume -----------------------------------------------
#
# An in-flight vine is pure data ([TravelingHazard]) apart from its `source` unit, so it
# serialises cleanly for the battle snapshot ([BattleSaveManager]). The source is stored as
# the unit's INDEX in the snapshot's unit list -- node references cannot be written to a file,
# and the restore re-spawns those units in that same order. `_hit_units` is deliberately NOT
# stored: it exists so a vine never hits the same unit twice, and every unit it has already
# passed is behind the front, so the geometry alone keeps that promise across a resume.

## A JSON-safe copy of every live vine. [param index_of_unit] maps a source [Unit] to its
## snapshot index (return -1 for "not on the board"), so this stays free of any dependency on
## how the snapshot numbers its units.
func snapshot_state(index_of_unit: Callable) -> Dictionary:
	var out: Array = []
	for hazard in _hazards:
		if hazard == null or hazard.is_expired():
			continue
		var source_index: int = -1
		if hazard.source != null and index_of_unit.is_valid():
			source_index = int(index_of_unit.call(hazard.source))
		out.append({
			"origin": [hazard.origin.x, hazard.origin.y],
			"facing": [hazard.facing.x, hazard.facing.y],
			"half_width": int(hazard.half_width),
			"speed": int(hazard.speed),
			"remaining": int(hazard.remaining),
			"damage": int(hazard.damage),
			"category": int(hazard.category),
			"affiliation": int(hazard.affiliation),
			"front": int(hazard.front),
			"source_index": source_index,
		})
	return { "hazards": out }


## Rebuild the vines [method snapshot_state] captured. [param unit_at_index] resolves a
## stored source index back to a live [Unit] (return null when it no longer exists -- a
## sourceless vine still crawls and still damages, it simply spares nobody by affiliation).
func restore_state(state: Dictionary, unit_at_index: Callable) -> void:
	_hazards.clear()
	var raw: Variant = state.get("hazards", [])
	if not (raw is Array):
		return
	for item in raw as Array:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var origin: Vector2i = _to_cell(d.get("origin", []))
		var facing: Vector2i = _to_cell(d.get("facing", []))
		var source = null
		var source_index: int = int(d.get("source_index", -1))
		if source_index >= 0 and unit_at_index.is_valid():
			source = unit_at_index.call(source_index)
		var hazard := TravelingHazard.new(
			origin, facing,
			int(d.get("half_width", 2)),
			int(d.get("speed", 2)),
			int(d.get("remaining", 0)),
			int(d.get("damage", 0)),
			int(d.get("category", 0)),
			int(d.get("affiliation", 0)),
			source)
		# `remaining` is set by _init from the travel range; `front` is how far it has already
		# crawled and must be written back separately or the vine would restart its lane.
		hazard.front = int(d.get("front", 0))
		if not hazard.is_expired():
			_hazards.append(hazard)


func _to_cell(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i.ZERO


# --- Teardown ---------------------------------------------------------------

func _exit_tree() -> void:
	# Freeing the node auto-disconnects it, but disconnect explicitly so intent is
	# clear and a reused instance can't double-subscribe (mirrors SpawnManager).
	if TurnSystemManager != null and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	if _watched_ts != null and is_instance_valid(_watched_ts) and _watched_ts.turn_started.is_connected(_on_player_turn_started):
		_watched_ts.turn_started.disconnect(_on_player_turn_started)
	if GameEvents != null and GameEvents.has_signal(&"hazard_spawn_requested") \
			and GameEvents.hazard_spawn_requested.is_connected(_on_hazard_spawn_requested):
		GameEvents.hazard_spawn_requested.disconnect(_on_hazard_spawn_requested)
