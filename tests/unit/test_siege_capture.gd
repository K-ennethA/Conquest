extends GutTest

## The SIEGE capture rule: [CaptureBase] (the objective) + [SiegeController]'s state machine.
##
## Everything is headless. The controller takes an injected BOARD (its documented test seam),
## turns are driven by calling handle_turn_started / handle_turn_ended directly with a fake
## turn system, and a fake MapResource carries the `lanes` / `base_cells` schema the map layer
## authors. No live scene, no CombatServices, no PlayerManager.
##
## BOTH TURN SYSTEMS are covered by the same tests through two fake systems, because the two
## halves of the rule ("begins at the unit's turn end", "completes at its next turn start")
## mean different things under each: Traditional's turn belongs to a PLAYER (no
## `current_acting_unit`), Speed First's belongs to a UNIT.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

# --- Doubles -----------------------------------------------------------------

class FakePlayer extends RefCounted:
	var player_id: int
	func _init(id: int) -> void:
		player_id = id


## A squad HERO by default. `is_neutral` / the creep mark are what disqualify one.
class FakeUnit extends RefCounted:
	var team: int
	var hp: int = 100
	var is_neutral: bool = false
	var character_id: String = "vineweave"

	func _init(p_team: int) -> void:
		team = p_team

	func get_team() -> int:
		return team

	func is_alive() -> bool:
		return hp > 0


class FakeBoard extends RefCounted:
	var cells: Dictionary = {}

	func place(unit, cell: Vector2i) -> void:
		cells[unit] = cell

	func cell_of(unit) -> Vector2i:
		return cells.get(unit, Vector2i(-999, -999))

	func all_units() -> Array:
		return cells.keys()


## Traditional's shape: a running player-switch counter, no acting unit.
class FakeTraditionalTS extends RefCounted:
	var current_turn: int = 1
	var registered_players: Array = []


## Speed First's shape: a real round counter and the unit whose turn it is.
class FakeSpeedTS extends RefCounted:
	var round_number: int = 1
	var current_acting_unit = null


class FakeMap extends RefCounted:
	var lanes: Array = []
	var base_cells: Dictionary = {}


## Never spawns anything -- the capture tests must not depend on waves.
class NullSpawner extends RefCounted:
	func spawn_and_adopt(_spawn_data, _player_id, _hint = 0):
		return null


# --- Fixture -----------------------------------------------------------------

const P0_BASE := Vector2i(1, 1)
const P1_BASE := Vector2i(9, 9)

var _board: FakeBoard
var _p0: FakePlayer
var _p1: FakePlayer


func before_each() -> void:
	_board = FakeBoard.new()
	_p0 = FakePlayer.new(0)
	_p1 = FakePlayer.new(1)


func after_each() -> void:
	# A test that compiled real rules installs BOTH push-map singletons on the scene-tree root
	# (a capture map arms the Siege runtime AND the neutral-camp/bounty runtime). Let the
	# deferred add_child land, then take them back down so neither leaks into the next suite as
	# an orphan or as a live listener.
	await get_tree().process_frame
	var ctrl := SiegeController.instance()
	if ctrl != null and is_instance_valid(ctrl):
		ctrl.set_armed(false)
	BaseAssaultRuntime.sync(null)
	for node_name in [SiegeController.NODE_NAME, BaseAssaultRuntime.NODE_NAME]:
		var runtime := get_tree().root.get_node_or_null(node_name)
		if runtime != null:
			get_tree().root.remove_child(runtime)
			runtime.free()
	SiegeController._instance = null


func _make_map() -> FakeMap:
	var m := FakeMap.new()
	m.lanes = [[Vector2i(1, 1), Vector2i(5, 5), Vector2i(9, 9)]]
	m.base_cells = {0: P0_BASE, 1: P1_BASE}
	return m


func _make_controller() -> SiegeController:
	var c := SiegeController.new()
	c.name = "SiegeCaptureTestController"
	add_child_autofree(c)
	var rs := SiegeRuleset.new()
	rs.creeps_per_lane = 0        # waves are a different suite's business
	rs.respawn_enabled = false
	c.set_ruleset(rs)
	c.set_armed(true)
	c.configure_from_map(_make_map())
	c.set_board_override(_board)
	c.set_spawner_override(NullSpawner.new())
	return c


# --- Map schema ---------------------------------------------------------------

func test_a_map_without_lanes_or_bases_is_not_a_siege_map() -> void:
	var c := SiegeController.new()
	add_child_autofree(c)
	c.set_armed(true)
	c.configure_from_map(FakeMap.new())
	assert_false(c.is_active(), "a map that authored no lanes and no base cells is not Siege")


func test_the_controller_reads_the_authored_lanes_and_base_cells() -> void:
	var c := _make_controller()
	assert_true(c.is_active(), "lanes + base cells + armed is what makes a battle a Siege")
	assert_eq(c.base_cell_for(0), P0_BASE, "player 0 defends the cell the map gave it")
	assert_eq(c.enemy_base_cell_for(0), P1_BASE, "and pushes toward the other side's cell")
	assert_eq(c.enemy_base_cell_for(1), P0_BASE, "which is symmetric for the other side")


# --- Traditional: the full capture sequence -----------------------------------

func test_a_hero_on_the_enemy_base_begins_capturing_at_its_turn_end() -> void:
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, P1_BASE)

	assert_eq(c.capturing_by(), -1, "nothing is being captured before the turn ends")
	c.handle_turn_ended(_p0, ts)
	assert_eq(c.capturing_by(), 0, "a hero standing on the enemy base begins the capture")
	assert_eq(c.captured_by(), -1, "but the base is NOT taken until it survives a turn")


func test_the_capture_completes_on_the_capturing_side_s_next_turn_start() -> void:
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, P1_BASE)

	c.handle_turn_ended(_p0, ts)
	# The enemy's whole turn passes without dislodging the hero.
	ts.current_turn = 2
	c.handle_turn_started(_p1, ts)
	c.handle_turn_ended(_p1, ts)
	assert_eq(c.captured_by(), -1, "the enemy's turn never completes OUR capture")

	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.captured_by(), 0, "surviving to its own next turn takes the base")
	assert_eq(c.capturing_by(), -1, "and the pending capture is consumed")


func test_death_cancels_the_capture() -> void:
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, P1_BASE)

	c.handle_turn_ended(_p0, ts)
	assert_eq(c.capturing_by(), 0, "capture is in flight")

	hero.hp = 0
	c.handle_unit_eliminated(hero)
	assert_eq(c.capturing_by(), -1, "the holder dying drops the capture immediately")

	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.captured_by(), -1, "a dead unit never captures anything")


func test_a_dead_holder_that_was_never_announced_still_fails_the_final_check() -> void:
	# Belt to the eager cancel's braces: even if the elimination signal never reached us, the
	# completion re-check is authoritative.
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, P1_BASE)
	c.handle_turn_ended(_p0, ts)

	hero.hp = 0
	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.captured_by(), -1, "the completion check re-verifies the holder is alive")


func test_displacement_cancels_the_capture() -> void:
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, P1_BASE)
	c.handle_turn_ended(_p0, ts)

	# Knocked one cell off the base during the enemy's turn.
	_board.place(hero, P1_BASE + Vector2i(1, 0))
	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.captured_by(), -1, "a holder that is no longer ON the cell captures nothing")


func test_walking_off_the_base_clears_the_pending_capture() -> void:
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, P1_BASE)
	c.handle_turn_ended(_p0, ts)

	_board.place(hero, Vector2i(4, 4))
	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	c.handle_turn_ended(_p0, ts)
	assert_eq(c.capturing_by(), -1, "the side's own turn end re-samples: nobody is holding it")


# --- Who may capture ----------------------------------------------------------

func test_a_creep_standing_on_the_enemy_base_never_captures() -> void:
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var creep := FakeUnit.new(0)
	SiegeController.stamp_creep(creep, [Vector2i(1, 1), Vector2i(9, 9)], 3)
	_board.place(creep, P1_BASE)

	c.handle_turn_ended(_p0, ts)
	assert_eq(c.capturing_by(), -1, "creeps push the lane; they never take the base")
	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.captured_by(), -1, "and no amount of standing there changes that")


func test_a_neutral_standing_on_a_base_never_captures() -> void:
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var wild := FakeUnit.new(0)
	wild.is_neutral = true
	_board.place(wild, P1_BASE)

	c.handle_turn_ended(_p0, ts)
	assert_eq(c.capturing_by(), -1, "a neutral is a third party and decides nothing")


func test_a_hero_on_its_OWN_base_captures_nothing() -> void:
	var c := _make_controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, P0_BASE)

	c.handle_turn_ended(_p0, ts)
	assert_eq(c.capturing_by(), -1, "you capture the ENEMY's base, not your own")


# --- Speed First: the turn belongs to a UNIT ----------------------------------

func test_speed_first_only_the_holder_s_own_turn_completes_the_capture() -> void:
	var c := _make_controller()
	var ts := FakeSpeedTS.new()
	var holder := FakeUnit.new(0)
	var other := FakeUnit.new(0)
	_board.place(holder, P1_BASE)
	_board.place(other, Vector2i(3, 3))

	ts.current_acting_unit = holder
	c.handle_turn_ended(_p0, ts)
	assert_eq(c.capturing_by(), 0, "the holder's own turn end begins the capture")

	# A different unit of the SAME side acts. It must neither complete nor cancel.
	ts.current_acting_unit = other
	ts.round_number = 2
	c.handle_turn_started(_p0, ts)
	assert_eq(c.captured_by(), -1, "another unit's turn must not complete the capture early")
	c.handle_turn_ended(_p0, ts)
	assert_eq(c.capturing_by(), 0, "and must not cancel it either -- it is not the holder")

	ts.current_acting_unit = holder
	ts.round_number = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.captured_by(), 0, "the holder's OWN next turn is what takes the base")


func test_speed_first_the_holder_dying_still_cancels() -> void:
	var c := _make_controller()
	var ts := FakeSpeedTS.new()
	var holder := FakeUnit.new(0)
	_board.place(holder, P1_BASE)
	ts.current_acting_unit = holder
	c.handle_turn_ended(_p0, ts)

	holder.hp = 0
	ts.round_number = 2
	c.handle_turn_started(_p0, ts)
	assert_eq(c.captured_by(), -1, "a dead holder captures nothing under Speed First either")


# --- The objective itself -----------------------------------------------------

func test_capture_base_scores_the_latch() -> void:
	var cond := CaptureBase.new()
	cond.faction = 0

	assert_eq(cond.evaluate({CaptureBase.STATE_CAPTURED_BY: -1}), WinCondition.Status.ONGOING,
		"nothing captured yet -> the battle continues")
	assert_eq(cond.evaluate({CaptureBase.STATE_CAPTURED_BY: 0}), WinCondition.Status.MET,
		"our side took the enemy base -> victory")
	assert_eq(cond.evaluate({CaptureBase.STATE_CAPTURED_BY: 1}), WinCondition.Status.FAILED,
		"the enemy took ours -> a FAILED win condition IS the defeat")


func test_capture_base_describes_the_objective_and_its_progress() -> void:
	var cond := CaptureBase.new()
	cond.faction = 0

	assert_eq(cond.describe(), "Capture the enemy base", "the banner's static line")
	assert_eq(cond.describe_progress({CaptureBase.STATE_CAPTURED_BY: -1, CaptureBase.STATE_CAPTURING: -1}),
		"Capture the enemy base", "with nothing in flight it falls back to describe()")
	assert_eq(cond.describe_progress({CaptureBase.STATE_CAPTURED_BY: -1, CaptureBase.STATE_CAPTURING: 0}),
		"Capturing - survive 1 turn!", "our capture in flight names the one thing left to do")
	assert_eq(cond.describe_progress({CaptureBase.STATE_CAPTURED_BY: -1, CaptureBase.STATE_CAPTURING: 1}),
		"Enemy is capturing your base!", "and the enemy's is the warning that matters")


func test_the_capture_marks_are_what_gate_the_rule() -> void:
	var hero := FakeUnit.new(0)
	var creep := FakeUnit.new(0)
	CaptureBase.mark_creep(creep)

	assert_true(CaptureBase.is_capturing_hero(hero, 0), "an owned, living squad unit may capture")
	assert_false(CaptureBase.is_capturing_hero(hero, 1), "but only for the side that owns it")
	assert_true(CaptureBase.is_creep(creep), "the creep mark is readable back off the unit")
	assert_false(CaptureBase.is_capturing_hero(creep, 0), "and a marked creep is disqualified")

	hero.hp = 0
	assert_false(CaptureBase.is_capturing_hero(hero, 0), "a dead unit captures nothing")


# --- Mode selection -----------------------------------------------------------

func test_the_library_compiles_the_capture_objective_from_the_map_string() -> void:
	var c := WinConditionLibrary.build_one("Capture Enemy Base", 0)
	assert_true(c is CaptureBase, "'Capture Enemy Base' is the Siege objective")
	assert_eq((c as CaptureBase).faction, 0, "scored for the side it was compiled for")

	var loose := WinConditionLibrary.build_one("capture the base", 1)
	assert_true(loose is CaptureBase, "matched on both words, so phrasing cannot fall through")
	assert_eq((loose as CaptureBase).faction, 1, "and carries the requested faction")


func test_compiling_a_siege_map_arms_the_runtime_and_any_other_map_silences_it() -> void:
	var rules := WinConditionLibrary.build_rules(["Capture Enemy Base"])
	var carries := false
	for c in rules.win_conditions:
		if c is CaptureBase:
			carries = true
	assert_true(carries, "a Siege map's compiled rules carry CaptureBase")

	var ctrl := SiegeController.instance()
	assert_not_null(ctrl, "compiling that objective installs the Siege runtime")
	assert_true(ctrl.is_armed(), "and arms it for this battle")

	WinConditionLibrary.build_rules(["Eliminate All Enemies"])
	assert_false(SiegeController.instance().is_armed(),
		"loading any other map silences it, so no other mode's behaviour changes")


# --- Versus: a capture has to decide a shared-screen battle too ---------------

func test_a_versus_battle_is_decided_by_a_map_authored_objective() -> void:
	var rules := WinConditionLibrary.build_rules(["Capture Enemy Base"])

	assert_true(WinConditionLibrary.rules_are_map_authored(rules),
		"a named objective is something the MAP asked for")
	assert_true(WinConditionLibrary.should_score_map_objectives(true, rules),
		"solo scores it, exactly as it always did")
	assert_true(WinConditionLibrary.should_score_map_objectives(false, rules),
		"and VERSUS now does too -- a capture resolves on a turn boundary, so "
		+ "last-side-standing would never see it, and on a push map nobody is ever wiped out")

	# And it really resolves: two living units on the board so the derived lose condition
	# ("the other side defeated everyone") stays ONGOING and only the capture decides.
	var board_units: Array = [Doubles.ObjectiveUnit.new(0, 100), Doubles.ObjectiveUnit.new(1, 100)]
	assert_eq(rules.evaluate({"units": board_units, CaptureBase.STATE_CAPTURED_BY: -1}),
		GameModeRules.Outcome.ONGOING, "nothing captured -> the battle runs on")
	assert_eq(rules.evaluate({"units": board_units, CaptureBase.STATE_CAPTURED_BY: 0}),
		GameModeRules.Outcome.VICTORY, "player 1 took the base -> decided")
	assert_eq(rules.evaluate({"units": board_units, CaptureBase.STATE_CAPTURED_BY: 1}),
		GameModeRules.Outcome.DEFEAT, "player 2 took it -> decided the other way")


func test_a_plain_versus_skirmish_still_ends_by_last_side_standing() -> void:
	# The qualifier that keeps the widening surgical. build_rules NEVER returns an empty rule
	# set -- a map that names nothing still gets a DefeatAllEnemies so it can be won at all --
	# and scoring THAT in versus would reroute every skirmish on every map through a different
	# path for an identical outcome.
	var unnamed := WinConditionLibrary.build_rules([])
	assert_false(unnamed.win_conditions.is_empty(), "the fallback objective is still compiled")
	assert_false(WinConditionLibrary.rules_are_map_authored(unnamed),
		"but a bare fallback is not something the map ASKED for")
	assert_false(WinConditionLibrary.should_score_map_objectives(false, unnamed),
		"so versus leaves it to the last-side-standing path, unchanged")
	assert_true(WinConditionLibrary.should_score_map_objectives(true, unnamed),
		"while solo is byte-identical to before: rules present -> score them")

	var spelled_out := WinConditionLibrary.build_rules(["Eliminate All Enemies"])
	assert_false(WinConditionLibrary.rules_are_map_authored(spelled_out),
		"and a map that spells out the fallback gets the same treatment, not a special case")

	assert_false(WinConditionLibrary.should_score_map_objectives(true, null),
		"no rules at all is never the map-driven path, in either mode")


# --- The neutral-camp bounty follows the MODE, not one objective --------------

func test_the_push_map_runtime_arms_for_a_capture_map_too() -> void:
	# Riftwood fields jungle camps on slot 2. BaseAssaultRuntime is what REGISTERS that
	# faction (an unowned guardian can neither attack nor be attacked) and what pays the
	# team bounty for felling one. It used to key off DestroyBase alone, so flipping a Siege
	# map to "Capture Enemy Base" would have silently dropped both.
	var capture_rules := WinConditionLibrary.build_rules(["Capture Enemy Base"])
	assert_true(BaseAssaultRuntime._rules_want_runtime(capture_rules),
		"a capture map is a push map: it arms the neutral registration + bounty runtime")

	var destroy_rules := WinConditionLibrary.build_rules(["Destroy Enemy Base"])
	assert_true(BaseAssaultRuntime._rules_want_runtime(destroy_rules),
		"and base-assault still does, unchanged")

	var plain_rules := WinConditionLibrary.build_rules(["Eliminate All Enemies"])
	assert_false(BaseAssaultRuntime._rules_want_runtime(plain_rules),
		"while an ordinary skirmish still arms nothing")


func test_the_bounty_is_still_paid_for_a_camp_kill_on_a_capture_map() -> void:
	var runtime := BaseAssaultRuntime.new()
	add_child_autofree(runtime)
	runtime.set_armed(true)

	var killer := FakeUnit.new(0)
	var camp := FakeUnit.new(2)
	camp.is_neutral = true

	assert_eq(runtime.team_bonus(0), 0, "no bounty before anything falls")
	runtime._on_damage_dealt(killer, camp, 40)
	camp.hp = 0
	runtime._on_unit_eliminated(camp, null)

	assert_eq(runtime.team_bonus(0), BaseAssaultRuntime.BOUNTY_AMOUNT,
		"felling a jungle camp still pays the killer's WHOLE SIDE, on a capture map as much "
		+ "as on a base-assault one -- the reward follows the mode, not the objective")
	assert_eq(runtime.team_bonus(1), 0, "and only the side that earned it")
