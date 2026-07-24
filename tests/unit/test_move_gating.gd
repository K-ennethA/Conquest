extends GutTest

# Verifies the move-once economy: a unit may move once per turn (then re-moving
# is blocked), but moving does not consume its action, and an ability/effect can
# grant another move.

func _make_unit(display_name: String) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = display_name
	res.unit_type = "warrior"
	res.max_health = 100
	res.base_speed = 8
	u.stats_resource = res
	add_child_autofree(u)
	return u

func _make_system(u: Unit) -> TraditionalTurnSystem:
	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	var player := Player.new(0, "P1")
	player.add_unit(u)
	ts.register_player(player)
	ts.start_turn_system()
	return ts

func test_can_move_before_moving():
	var u := _make_unit("Rook")
	var ts := _make_system(u)
	assert_true(u.can_move(), "unit can move at start of turn")
	assert_true(ts.validate_turn_action(u, "move"), "turn system allows first move")

func test_move_blocked_after_moving():
	var u := _make_unit("Rook")
	var ts := _make_system(u)
	u.mark_moved()
	assert_false(u.can_move(), "can_move() is false after moving")
	assert_false(ts.validate_turn_action(u, "move"), "turn system blocks a second move")

func test_action_still_allowed_after_moving():
	var u := _make_unit("Rook")
	var ts := _make_system(u)
	u.mark_moved()
	assert_true(u.can_act(), "unit can still take its action after moving")
	assert_true(ts.validate_turn_action(u, "attack"), "non-move actions still allowed after moving")

func test_extra_move_grant_reenables_movement():
	var u := _make_unit("Rook")
	var ts := _make_system(u)
	u.mark_moved()
	assert_false(u.can_move(), "blocked after first move")
	u.grant_extra_move()
	assert_true(u.can_move(), "ability/effect grant re-enables movement")
	assert_true(ts.validate_turn_action(u, "move"), "turn system allows the granted extra move")

func test_reset_clears_moved_flag():
	var u := _make_unit("Rook")
	u.mark_moved()
	u.reset_turn_actions()
	assert_false(u.has_moved_this_turn, "reset clears has_moved")
	assert_true(u.can_move(), "unit can move again next turn")
