extends GutTest

## Regression: in Speed (initiative) mode, units can register AFTER the turn system starts
## -- an Arena round spawns its actors around activation. The system used to bail out of
## start_turn_system() on an empty queue and never recover, leaving current_acting_unit
## (and therefore the current player) null forever, so every unit was selectable but
## UNCOMMANDABLE. It must now stay active and kick the order off on the first registration.

func _real_unit(name: String, player: Player) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = name
	res.unit_type = "warrior"
	res.max_health = 100
	res.base_speed = 10
	res.movement_range = 3
	u.stats_resource = res
	add_child_autofree(u)
	player.add_unit(u)
	return u


func test_speed_mode_recovers_when_units_register_after_start():
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	var player := Player.new(0, "Human")
	ts.register_player(player)

	# Start with NOTHING registered yet (the Arena-round race).
	ts.start_turn_system()
	assert_true(ts.is_active, "the system stays ACTIVE even started empty (no more permanent bail-out)")
	assert_null(ts.get_current_active_player(), "nothing is acting yet, so there is no current player")

	# Now the round's actors arrive, in the same frame.
	var a := _real_unit("First", player)
	var b := _real_unit("Second", player)
	ts.register_unit(a)
	ts.register_unit(b)

	# The kickoff is deferred so the whole batch is queued before the order is chosen.
	await get_tree().process_frame

	assert_not_null(ts.get_current_active_player(), "a unit is now acting, so there IS a current player")
	assert_eq(ts.get_current_active_player(), player, "and it is the player who owns the newly-registered units")
	assert_true(ts.can_unit_act(ts.current_acting_unit), "the acting unit can actually act (turn in progress)")
