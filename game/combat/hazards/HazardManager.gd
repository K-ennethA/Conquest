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
