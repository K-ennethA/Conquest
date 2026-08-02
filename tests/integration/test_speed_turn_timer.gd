extends GutTest

## Speed First per-unit move clock (the "make Speed mode speedier" feature).
##
## The clock arms only for HUMAN-owned units, force-ends a turn EXACTLY like End Turn on
## expiry, never double-advances, and cancels cleanly when the unit acts or dies mid-turn.
## The turn system owns the arm/disarm STATE + the expiry entry point (it is not in the
## scene tree, so the HUD drives the real countdown and calls expire_turn_timer()); these
## tests exercise that state directly.

const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose: a `: RefCounted` annotation would make the static analyser reject
## _guard.set_setting() / .watch_file() as "not found in base RefCounted".
var _guard

func before_each() -> void:
	# Pin the global clock setting so tests are deterministic regardless of any persisted
	# user setting. The guard restores it from after_each, which runs on failures too.
	_guard = Guard.new()
	_guard.set_setting("speed_turn_timer_seconds", 30)

func after_each() -> void:
	_guard.restore()

# --- Helpers ----------------------------------------------------------------

func _make_system() -> SpeedFirstTurnSystem:
	return add_child_autofree(SpeedFirstTurnSystem.new())

func _unit(name: String, player: Player, speed: int) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = name
	res.unit_type = "warrior"
	res.max_health = 100
	res.base_speed = speed
	res.movement_range = 3
	u.stats_resource = res
	add_child_autofree(u)
	player.add_unit(u)
	return u

# --- Tests ------------------------------------------------------------------

func test_clock_arms_for_human_unit_but_never_for_ai() -> void:
	var ts := _make_system()
	var human := Player.new(0, "Human")
	var ai := Player.new(1, "AI")
	ai.is_ai = true
	ts.register_player(human)
	ts.register_player(ai)

	# Human unit is faster, so it acts first.
	var h := _unit("Human1", human, 20)
	var a := _unit("Ai1", ai, 10)
	ts.register_unit(h)
	ts.register_unit(a)
	ts.start_turn_system()

	assert_eq(ts.current_acting_unit, h, "the fast human unit acts first")
	assert_true(ts.turn_timer_active, "a human unit's move clock arms")
	assert_eq(ts.turn_timer_unit, h, "and it belongs to that human unit")
	assert_almost_eq(ts.turn_timer_seconds, 30.0, 0.001, "armed with the configured duration")

	# Advance to the AI unit -> the clock must NOT be armed (AI is paced by BotTurnDriver).
	ts.mark_unit_acted(h)
	assert_eq(ts.current_acting_unit, a, "the AI unit acts next")
	assert_false(ts.turn_timer_active, "an AI unit is never clocked")

func test_off_setting_never_arms() -> void:
	GameSettings.speed_turn_timer_seconds = 0
	var ts := _make_system()
	var human := Player.new(0, "Human")
	ts.register_player(human)
	var h := _unit("Human1", human, 20)
	ts.register_unit(h)
	ts.start_turn_system()

	assert_eq(ts.current_acting_unit, h, "the human unit is acting")
	assert_false(ts.turn_timer_active, "with the clock OFF (0) it never arms")

func test_expiry_force_ends_turn_and_advances_exactly_once() -> void:
	var ts := _make_system()
	var human := Player.new(0, "Human")
	ts.register_player(human)
	var a := _unit("A", human, 20)
	var b := _unit("B", human, 10)
	ts.register_unit(a)
	ts.register_unit(b)
	ts.start_turn_system()

	watch_signals(ts)
	assert_eq(ts.current_acting_unit, a, "A acts first")
	assert_true(ts.turn_timer_active, "A's clock is armed")

	# Clock runs out -> force-end A's turn, advancing to B ONCE.
	ts.expire_turn_timer(a)
	assert_signal_emitted(ts, "turn_timer_expired", "expiry fires the expired signal")
	assert_eq(ts.current_acting_unit, b, "expiry advanced to the next unit exactly once")

	# A stale expiry for the unit that already ended must be a harmless no-op (B is now the
	# armed unit); it must NOT advance the queue again.
	ts.expire_turn_timer(a)
	assert_eq(ts.current_acting_unit, b, "a stale expiry for A does not double-advance")

func test_expiry_is_noop_when_unit_already_acted_same_instant() -> void:
	# Reentrancy guard: the unit acts and the clock expires "at the same time". The act
	# advances the queue; the expiry for the now-acted unit must do nothing.
	var ts := _make_system()
	var human := Player.new(0, "Human")
	ts.register_player(human)
	var a := _unit("A", human, 20)
	var b := _unit("B", human, 10)
	ts.register_unit(a)
	ts.register_unit(b)
	ts.start_turn_system()

	assert_eq(ts.current_acting_unit, a)
	ts.mark_unit_acted(a)  # A acts -> advance to B; B (human) re-arms.
	assert_eq(ts.current_acting_unit, b, "acting advanced to B")
	assert_eq(ts.turn_timer_unit, b, "the clock re-armed for the next human unit")

	# The late expiry for A (which already acted) is guarded out: A != armed unit.
	ts.expire_turn_timer(a)
	assert_eq(ts.current_acting_unit, b, "stale expiry for the acted unit is a no-op")

func test_clock_cancels_when_unit_acts_mid_countdown() -> void:
	var ts := _make_system()
	var human := Player.new(0, "Human")
	ts.register_player(human)
	var a := _unit("A", human, 20)
	var b := _unit("B", human, 10)
	ts.register_unit(a)
	ts.register_unit(b)
	ts.start_turn_system()

	assert_eq(ts.turn_timer_unit, a, "A's clock is armed")
	watch_signals(ts)
	ts.mark_unit_acted(a)  # A acts before its clock runs out.
	assert_signal_emitted(ts, "turn_timer_disarmed", "acting cancels A's clock")
	assert_true(ts.turn_timer_unit != a, "A's clock no longer belongs to A")

func test_clock_disarms_when_acting_unit_dies_mid_turn() -> void:
	var ts := _make_system()
	var human := Player.new(0, "Human")
	ts.register_player(human)
	var a := _unit("A", human, 20)
	var b := _unit("B", human, 10)
	ts.register_unit(a)
	ts.register_unit(b)
	ts.start_turn_system()

	assert_eq(ts.current_acting_unit, a)
	assert_true(ts.turn_timer_active, "A's clock is armed")

	watch_signals(ts)
	# A dies mid-turn without completing an action (poison tick / lethal hazard). This is
	# the override path that hands off to the next unit -- the clock must stop cleanly.
	a.unit_died.emit(a)
	assert_signal_emitted(ts, "turn_timer_disarmed", "mid-turn death cancels the clock")
	assert_false(ts.turn_timer_active, "the clock is disarmed after the acting unit dies")

	# The queue hands off next idle frame; the clock must not resurrect for the dead unit.
	await get_tree().process_frame
	assert_true(ts.turn_timer_unit != a, "the clock never points back at the dead unit")
