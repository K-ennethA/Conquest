extends GutTest

## Focused coverage for combat DEATH resolution (the "health bar depletes but the
## unit never dies" bug). Proves, end to end at the data/turn-system level:
##   1. take_damage reduces HP and emits the health change the visuals listen to.
##   2. Lethal damage marks the unit not-alive and fires unit_died exactly once
##      (idempotent -- no double death from take_damage + the health_changed signal).
##   3. A dead unit is dropped from its owner Player and, after the deferred cleanup
##      unwinds, from the turn system's active/registered units so it can neither act
##      nor stall turn completion.
##
## Visual despawn (health bar removal + node free) is driven from the same
## Unit._on_unit_died path; it is exercised implicitly here (the unit frees itself)
## and directly in live play. These asserts stay at the headless data layer so they
## do not depend on a UnitVisualManager / scene being present.


func _make_stats(hp: int) -> UnitStatsResource:
	var res := UnitStatsResource.new()
	res.unit_name = "Grunt"
	res.unit_type = "warrior"
	res.max_health = hp
	res.base_attack = 10
	res.base_defense = 0
	res.base_speed = 5
	res.movement_range = 3
	res.attack_range = 1
	return res


func _spawn_unit(hp: int) -> Unit:
	var unit := Unit.new()
	unit.stats_resource = _make_stats(hp)
	add_child_autofree(unit)  # triggers _ready() so the UnitStats component initializes
	return unit


# --- take_damage reduces HP and emits the change ----------------------------

func test_take_damage_reduces_hp_and_emits_health_changed() -> void:
	var unit := _spawn_unit(40)
	watch_signals(unit.unit_stats)

	unit.take_damage(15)

	assert_eq(unit.get_hp(), 25, "take_damage should subtract from current health")
	assert_true(unit.is_alive(), "a unit above 0 HP is still alive")
	assert_signal_emitted(unit.unit_stats, "health_changed",
		"take_damage must emit health_changed so the health bar updates")


# --- lethal damage: dead, and death resolves exactly once -------------------

func test_lethal_damage_marks_dead_and_emits_unit_died_once() -> void:
	var unit := _spawn_unit(30)
	watch_signals(unit)

	unit.take_damage(999)

	assert_eq(unit.get_hp(), 0, "HP floors at 0")
	assert_false(unit.is_alive(), "a unit at 0 HP is not alive")
	assert_signal_emit_count(unit, "unit_died", 1,
		"death must resolve exactly once even though both take_damage and the "
		+ "health_changed signal observe HP hitting 0")


func test_further_damage_after_death_does_not_re_emit() -> void:
	var unit := _spawn_unit(20)
	unit.take_damage(999)
	watch_signals(unit)

	unit.take_damage(999)  # already dead

	assert_signal_emit_count(unit, "unit_died", 0,
		"a unit that is already dead must not fire unit_died again")


# --- turn system + owner drop the dead unit ---------------------------------

func test_dead_unit_removed_from_owner_and_turn_system() -> void:
	var player := Player.new(0, "P1")
	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)

	var unit := _spawn_unit(25)
	player.add_unit(unit)          # ownership + wires Player._on_unit_died
	ts.register_player(player)     # registers the unit with the turn system
	ts.start_turn_system()

	assert_eq(ts.registered_units.size(), 1, "unit is registered before it dies")

	unit.take_damage(999)  # lethal

	# Ownership AND turn-system unregister happen synchronously inside the unit_died
	# emission (the unit is still a valid instance here -- queue_free is end-of-frame
	# -- so we assert on counts while it is valid, not on the soon-freed reference).
	# Only the turn-completion re-check is deferred.
	assert_false(player.owns_unit(unit),
		"the owning player drops a dead unit from owned_units immediately")
	assert_eq(ts.registered_units.size(), 0,
		"the dead unit is unregistered from the turn system")
	assert_eq(ts.get_active_units().size(), 0,
		"a dead unit is not returned as an active/actable unit")

	# Let the deferred completion check + node free unwind cleanly.
	await get_tree().process_frame
	await get_tree().process_frame
