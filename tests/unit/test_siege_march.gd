extends GutTest

## The MARCH stance -- [BotController]'s creep-push branch.
##
## A marching unit walks an authored lane of waypoints and ignores the board until something
## hostile comes inside its aggro radius, at which point it drops straight into the ORDINARY
## planner (attack / support / trap / advance) and fights like anything else; when the board
## goes quiet again it resumes. The whole stance is a gate plus a destination -- there is no
## second AI -- and these tests pin exactly that: what it does while marching, what makes it
## stop, and that nothing which does not opt in is affected.
##
## Same MockUnit / MockBoard duck typing as test_bot_controller.gd. `plan()` takes the
## reachable set explicitly, so lanes and movement ranges are crafted directly.

class MockUnit extends RefCounted:
	var team: int
	var stats: Dictionary
	var hp: int

	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))

	func get_stat(name: String) -> int:
		return int(stats.get(name, 0))

	func take_damage(n: int) -> void:
		hp -= n


class MockBoard extends RefCounted:
	var placements: Array = []

	func place(unit, cell: Vector2i) -> void:
		placements.append({"unit": unit, "cell": cell})

	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out

	func are_enemies(a, b) -> bool:
		return a.team != b.team

	func are_allies(a, b) -> bool:
		return a.team == b.team

	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out


# The crafted lane every test pushes down: a straight run along x.
const LANE: Array = [Vector2i(0, 0), Vector2i(4, 0), Vector2i(8, 0)]


func _make_creep(aggro: int = 3) -> MockUnit:
	var creep := MockUnit.new(0, {"attack": 10, "health": 100})
	creep.set_meta(BotController.MARCH_LANE_META, LANE.duplicate())
	creep.set_meta(BotController.MARCH_AGGRO_META, aggro)
	return creep


## The cells a unit standing on [param origin] can reach, [param range] cells along x.
func _row_reachable(origin: Vector2i, cells: int) -> Array:
	var out: Array = []
	for dx in range(1, cells + 1):
		out.append(Vector2i(origin.x + dx, origin.y))
		out.append(Vector2i(origin.x - dx, origin.y))
	return out


# --- The waypoint the creep is walking toward ---------------------------------

func test_march_target_is_the_nearest_waypoint_it_is_not_already_standing_on() -> void:
	assert_eq(BotController.march_target(LANE, Vector2i(1, 0)), Vector2i(0, 0),
		"just past the first waypoint, the nearest one is still the one to walk to")
	assert_eq(BotController.march_target(LANE, Vector2i(0, 0)), Vector2i(4, 0),
		"standing ON a waypoint advances to the next")
	assert_eq(BotController.march_target(LANE, Vector2i(4, 0)), Vector2i(8, 0),
		"and again at the middle waypoint")


func test_march_target_ties_break_toward_the_later_waypoint() -> void:
	# Exactly between waypoints 0 and 1 -- the tie must never drag a creep backwards.
	assert_eq(BotController.march_target(LANE, Vector2i(2, 0)), Vector2i(4, 0),
		"a creep midway between two waypoints keeps pushing forward, never back")


func test_the_final_waypoint_is_the_end_of_the_march() -> void:
	assert_eq(BotController.march_target(LANE, Vector2i(8, 0)), Vector2i(8, 0),
		"standing on the last waypoint returns itself -- there is nowhere further to push")


# --- Marching ------------------------------------------------------------------

func test_a_creep_advances_along_its_lane_with_nothing_on_the_board() -> void:
	var creep := _make_creep()
	var board := MockBoard.new()
	board.place(creep, Vector2i(0, 0))

	var bot := BotController.new()
	var decision := bot.plan(creep, [MoveLibrary.basic_strike()], board, _row_reachable(Vector2i(0, 0), 3))

	assert_eq(decision["action"], BotController.ActionType.STEP,
		"a creep pushes its lane whether or not there is anyone to fight")
	assert_eq(decision["dest_cell"], Vector2i(3, 0),
		"closing its whole movement range toward the next waypoint at (4,0)")
	assert_eq(String(decision["reason"]), "march", "and it reports WHY it moved")


func test_a_creep_ignores_an_enemy_outside_its_aggro_radius() -> void:
	var creep := _make_creep(3)
	var far_enemy := MockUnit.new(1, {"health": 100})
	var board := MockBoard.new()
	board.place(creep, Vector2i(0, 0))
	board.place(far_enemy, Vector2i(0, 9))   # 9 away, well beyond radius 3

	var bot := BotController.new()
	var decision := bot.plan(creep, [MoveLibrary.basic_strike()], board, _row_reachable(Vector2i(0, 0), 3))

	assert_eq(decision["action"], BotController.ActionType.STEP, "still marching")
	assert_eq(decision["dest_cell"], Vector2i(3, 0),
		"toward the WAYPOINT, not toward the enemy -- an out-of-radius enemy is not its problem")


func test_a_creep_breaks_off_to_fight_an_enemy_inside_its_aggro_radius() -> void:
	var creep := _make_creep(3)
	var near_enemy := MockUnit.new(1, {"health": 100, "defense": 0})
	var board := MockBoard.new()
	board.place(creep, Vector2i(0, 0))
	board.place(near_enemy, Vector2i(1, 0))   # adjacent: inside radius, and strikeable

	var bot := BotController.new()
	var decision := bot.plan(creep, [MoveLibrary.basic_strike()], board, _row_reachable(Vector2i(0, 0), 3))

	assert_eq(decision["action"], BotController.ActionType.MOVE,
		"inside the radius the creep falls through to the ORDINARY combat planner")
	assert_eq(decision["target"], near_enemy, "and attacks what came to meet it")


func test_the_aggro_radius_is_the_knob_that_decides_which_it_does() -> void:
	var enemy_cell := Vector2i(0, 3)

	# Radius 3: the enemy at distance 3 is inside -> fight (advance toward it, off-lane).
	var tight := _make_creep(3)
	var board_tight := MockBoard.new()
	board_tight.place(tight, Vector2i(0, 0))
	board_tight.place(MockUnit.new(1, {"health": 100}), enemy_cell)
	var engaged := BotController.new().plan(
		tight, [MoveLibrary.basic_strike()], board_tight,
		[Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(engaged["dest_cell"], Vector2i(0, 2),
		"radius 3 reaches the enemy at distance 3, so the creep closes on IT")

	# Radius 2: the same enemy is outside -> keep marching down the lane.
	var loose := _make_creep(2)
	var board_loose := MockBoard.new()
	board_loose.place(loose, Vector2i(0, 0))
	board_loose.place(MockUnit.new(1, {"health": 100}), enemy_cell)
	var marching := BotController.new().plan(
		loose, [MoveLibrary.basic_strike()], board_loose,
		[Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(marching["dest_cell"], Vector2i(2, 0),
		"radius 2 does not, so the identical board is marched past instead")


func test_a_creep_resumes_the_march_once_the_enemy_is_gone() -> void:
	var creep := _make_creep(3)
	var enemy := MockUnit.new(1, {"health": 100})
	var board := MockBoard.new()
	board.place(creep, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))

	var bot := BotController.new()
	var fighting := bot.plan(creep, [MoveLibrary.basic_strike()], board, _row_reachable(Vector2i(0, 0), 3))
	assert_eq(fighting["action"], BotController.ActionType.MOVE, "engaged while the enemy stands")

	# The enemy dies and leaves the board; the very next plan is a march again.
	board.placements = [{"unit": creep, "cell": Vector2i(0, 0)}]
	var resumed := bot.plan(creep, [MoveLibrary.basic_strike()], board, _row_reachable(Vector2i(0, 0), 3))
	assert_eq(resumed["action"], BotController.ActionType.STEP, "and back to marching once it is not")
	assert_eq(String(resumed["reason"]), "march", "explicitly the march branch, not a generic advance")


func test_a_creep_that_has_arrived_holds_instead_of_capturing() -> void:
	var creep := _make_creep(3)
	var board := MockBoard.new()
	board.place(creep, LANE[LANE.size() - 1])   # standing on the far end of the lane

	var bot := BotController.new()
	var decision := bot.plan(creep, [MoveLibrary.basic_strike()], board, _row_reachable(LANE[2], 3))

	assert_eq(decision["action"], BotController.ActionType.WAIT,
		"a creep at the end of its lane has nothing left to push -- it never captures")
	assert_eq(String(decision["reason"]), "march_arrived", "and says so")


func test_a_boxed_in_creep_waits_rather_than_wandering() -> void:
	var creep := _make_creep(3)
	var board := MockBoard.new()
	board.place(creep, Vector2i(0, 0))

	var bot := BotController.new()
	var decision := bot.plan(creep, [MoveLibrary.basic_strike()], board, [])

	assert_eq(decision["action"], BotController.ActionType.WAIT,
		"no reachable cell gets it closer, so it holds")
	assert_eq(String(decision["reason"]), "march_blocked", "and says why")


# --- Nothing that did not opt in changes -------------------------------------

func test_a_unit_without_a_lane_plans_exactly_as_before() -> void:
	var actor := MockUnit.new(0, {"attack": 10})
	var enemy := MockUnit.new(1, {"health": 100, "defense": 0})
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(0, 6))

	var decision := BotController.new().plan(
		actor, [MoveLibrary.basic_strike()], board, [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0)])

	assert_eq(decision["action"], BotController.ActionType.STEP, "the ordinary full advance")
	assert_eq(String(decision["reason"]), "advance_full",
		"unmarked units never touch the march branch")


func test_an_empty_lane_is_not_a_march() -> void:
	var actor := MockUnit.new(0, {"attack": 10})
	actor.set_meta(BotController.MARCH_LANE_META, [])
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))

	var decision := BotController.new().plan(actor, [MoveLibrary.basic_strike()], board, [Vector2i(1, 0)])
	assert_eq(decision["action"], BotController.ActionType.WAIT,
		"an empty lane disables the branch, so this is the plain no-hostiles wait")
	assert_eq(String(decision["reason"]), "no_hostiles", "through the ordinary path")


func test_the_ai_driven_mark_is_readable_and_defaults_off() -> void:
	var plain := MockUnit.new(0, {})
	var creep := MockUnit.new(0, {})
	BotTurnDriver.mark_ai_driven(creep)

	assert_false(BotTurnDriver.is_ai_driven(plain),
		"a unit the player commands is never AI-driven")
	assert_true(BotTurnDriver.is_ai_driven(creep),
		"a marked one is -- this is what makes the driver act it on its owner's own turn")
