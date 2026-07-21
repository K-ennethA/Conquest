extends GutTest

# Tests for the runtime spawn scheduler (game/maps/SpawnManager.gd), which fires the
# authored spawn KINDS that MapLoader leaves inert: staggered Reinforcements, Respawns
# after a unit dies, and endless waves.
#
# Everything is headless: a real MapResource carries the authored points (so the real
# normalize_spawn / is_initial_spawn / spawn_has_unit_reference contract is exercised),
# a FakeMapLoader stands in for MapLoader.spawn_unit_now (just counting calls and
# handing back fake units), and turns are driven by calling SpawnManager.process_turn()
# directly -- no live turn system, board, or scene tree required. Deaths are simulated
# by killing a FakeUnit, which emits the same `unit_died(unit)` signal a real Unit does.

# --- Test doubles ----------------------------------------------------------

# A stand-in for a spawned Unit: exposes the `unit_died` signal and is_alive() that the
# scheduler watches, and a kill() that flips it to dead and emits the signal.
class FakeUnit extends RefCounted:
	signal unit_died(unit)
	var alive: bool = true

	func is_alive() -> bool:
		return alive

	func kill() -> void:
		alive = false
		unit_died.emit(self)


# A stand-in for MapLoader: records how many times spawn_unit_now was asked to produce
# a unit and returns a fresh FakeUnit each time.
class FakeMapLoader extends RefCounted:
	var spawn_calls: int = 0
	var produced: Array = []

	func spawn_unit_now(_spawn_data, _count_hint = 0):
		spawn_calls += 1
		var u := FakeUnit.new()
		produced.append(u)
		return u


var _loader: FakeMapLoader
var _manager: SpawnManager


func before_each() -> void:
	_loader = FakeMapLoader.new()
	_manager = SpawnManager.new()


func after_each() -> void:
	if is_instance_valid(_manager):
		_manager.free()


# --- Helpers ----------------------------------------------------------------

func _map_with(kind: String, pos: Vector2i, player_id: int, opts: Dictionary) -> MapResource:
	# A unit reference is required for every spawner kind, so every point names a
	# character id. (The FakeMapLoader ignores what is spawned; it only counts.)
	var full_opts: Dictionary = opts.duplicate()
	if not full_opts.has("character_id"):
		full_opts["character_id"] = "torvald_ironhide"
	var map := MapResource.new()
	map.set_spawn_point_at_position(pos, player_id, kind, full_opts)
	return map


func _tick(n: int) -> void:
	for i in range(n):
		_manager.process_turn()


# --- Reinforcement ----------------------------------------------------------

func test_reinforcement_spawns_only_on_its_turn() -> void:
	var map := _map_with(MapResource.SPAWN_KIND_REINFORCEMENT, Vector2i(1, 1), 0, {
		"spawn_turn": 3,
	})
	_manager.initialize(_loader, map)

	# Turns 1 and 2: nothing yet.
	_manager.process_turn()
	assert_eq(_loader.spawn_calls, 0, "Reinforcement must not spawn on turn 1")
	_manager.process_turn()
	assert_eq(_loader.spawn_calls, 0, "Reinforcement must not spawn on turn 2")

	# Turn 3: exactly one unit.
	_manager.process_turn()
	assert_eq(_loader.spawn_calls, 1, "Reinforcement spawns exactly one unit on turn 3")

	# It is one-shot (max_spawns defaults to 1): later turns add nothing.
	_tick(4)
	assert_eq(_loader.spawn_calls, 1, "Reinforcement never spawns a second unit")


func test_reinforcement_due_turn_one_is_not_double_spawned() -> void:
	# A Reinforcement at spawn_turn <= 1 was already placed at map load
	# (is_initial_spawn == true), so the scheduler must NOT produce another.
	var map := _map_with(MapResource.SPAWN_KIND_REINFORCEMENT, Vector2i(0, 0), 0, {
		"spawn_turn": 1,
	})
	_manager.initialize(_loader, map)

	_tick(5)
	assert_eq(_loader.spawn_calls, 0,
		"A turn-1 Reinforcement was placed at load and must not be re-spawned at runtime")


# --- Endless ----------------------------------------------------------------

func test_endless_staggers_by_respawn_interval() -> void:
	# Endless is periodic: one new unit every respawn_interval turns, not one per turn.
	var map := _map_with(MapResource.SPAWN_KIND_ENDLESS, Vector2i(2, 2), 1, {
		"respawn_interval": 2,
	})
	_manager.initialize(_loader, map)

	# Six turns at interval 2, seed placed at load (turn 0): spawns on turns 2, 4, 6.
	_tick(6)
	assert_eq(_loader.spawn_calls, 3,
		"Endless with interval 2 produces one unit every two turns (turns 2, 4, 6)")
	assert_true(_loader.spawn_calls < 6, "Endless must stagger, not flood one per turn")


func test_endless_does_not_spawn_before_first_interval() -> void:
	var map := _map_with(MapResource.SPAWN_KIND_ENDLESS, Vector2i(2, 2), 1, {
		"respawn_interval": 3,
	})
	_manager.initialize(_loader, map)

	_manager.process_turn()
	_manager.process_turn()
	assert_eq(_loader.spawn_calls, 0, "Endless with interval 3 spawns nothing on turns 1-2")
	_manager.process_turn()
	assert_eq(_loader.spawn_calls, 1, "Endless with interval 3 spawns its first extra on turn 3")


# --- Respawn ----------------------------------------------------------------

func test_respawn_stops_after_max_spawns() -> void:
	# max_spawns = 3 counts the load-time seed, so only TWO respawns may follow.
	var map := _map_with(MapResource.SPAWN_KIND_RESPAWN, Vector2i(3, 3), 0, {
		"max_spawns": 3,
		"respawn_interval": 1,
	})
	_manager.initialize(_loader, map)

	# Adopt the load-time seed (in the live game this comes off the board).
	var seed := FakeUnit.new()
	assert_true(_manager.track_seed_unit(Vector2i(3, 3), 0, seed),
		"scheduler should adopt the seed unit for the Respawn point")

	# Kill each unit and let the interval elapse; expect exactly two respawns, no more.
	var last := seed
	for round_i in range(5):
		last.kill()
		_manager.process_turn()  # interval 1 -> replacement on the next turn
		if _loader.produced.size() > 0 and _loader.spawn_calls == _loader.produced.size():
			last = _loader.produced[_loader.produced.size() - 1]

	assert_eq(_loader.spawn_calls, 2,
		"Respawn with max_spawns 3 produces 2 replacements after the load-time seed, then stops")


func test_respawn_waits_the_full_interval_after_death() -> void:
	var map := _map_with(MapResource.SPAWN_KIND_RESPAWN, Vector2i(4, 4), 0, {
		"max_spawns": -1,
		"respawn_interval": 3,
	})
	_manager.initialize(_loader, map)

	var seed := FakeUnit.new()
	_manager.track_seed_unit(Vector2i(4, 4), 0, seed)

	# Seed alive: no respawn no matter how long we wait.
	_tick(4)
	assert_eq(_loader.spawn_calls, 0, "A living unit is never replaced")

	# It dies at turn 4; interval 3 -> replacement is due on turn 7, not before.
	seed.kill()
	_manager.process_turn()  # turn 5
	_manager.process_turn()  # turn 6
	assert_eq(_loader.spawn_calls, 0, "Respawn waits the full interval before replacing")
	_manager.process_turn()  # turn 7
	assert_eq(_loader.spawn_calls, 1, "Respawn produces the replacement once the interval elapses")


func test_max_spawns_one_respawn_never_produces_a_second() -> void:
	# The load-time seed is counted, so a max_spawns = 1 Respawn is already "full".
	var map := _map_with(MapResource.SPAWN_KIND_RESPAWN, Vector2i(0, 4), 0, {
		"max_spawns": 1,
		"respawn_interval": 1,
	})
	_manager.initialize(_loader, map)

	var seed := FakeUnit.new()
	_manager.track_seed_unit(Vector2i(0, 4), 0, seed)

	seed.kill()
	_tick(5)
	assert_eq(_loader.spawn_calls, 0,
		"A max_spawns 1 Respawn already spent its only unit at load and never respawns")


# --- Start ------------------------------------------------------------------

func test_start_points_are_never_scheduled() -> void:
	var map := _map_with(MapResource.SPAWN_KIND_START, Vector2i(1, 0), 0, {})
	_manager.initialize(_loader, map)
	_tick(10)
	assert_eq(_loader.spawn_calls, 0, "Start points do nothing at runtime")
