extends GutTest

## SIEGE CONTROL POINTS -- the midpoints a side takes and holds -- plus the two things holding
## one pays, and the TIMED conversion of the neutral-camp reward that ships with them.
##
## The shape being pinned:
##
##   * a control point is claimed by the SAME state machine that takes a base ([CaptureBase]'s
##     rule, [SiegeController]'s latch): end your turn on it, still be there at your next turn
##     start, and it is yours. A creep can no more claim one than it can capture a base;
##   * ownership is a per-cell latch that PERSISTS through its claimant's death and is lost only
##     by being flipped;
##   * what it pays is [SiegeRuleset] DATA -- extra creeps entering AT the point down the
##     nearest lane (bounded by the same live cap), and a round-start heal for the OWNER's units
##     standing on it;
##   * a felled neutral camp pays a TIMED buff in a mode that declares `camp_buff_turns`, and
##     the permanent bounty everywhere else (CONQUEST.md rule 11);
##   * every multi-point pass walks the cells in SORTED order, so two runs are identical.
##
## Headless throughout, on the harness `test_siege_waves.gd` / `test_mode_pacing.gd` established:
## a fake board and spawner, a fake MapResource carrying `lanes` / `base_cells` /
## `control_points`, and rounds stepped with [method SiegeController.observe_round]. The heal and
## buff suites use REAL [Unit]s, because they exercise the real heal pipeline and the real
## [StatusController].
##
## [ModeTuning]'s registration is a STATIC -- global state -- so it is cleared in `after_each`
## (tests/README rule 3).

# ==============================================================================
# Doubles
# ==============================================================================

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


## Carries the two hooks [MoveContext] needs on top of the capture machine's `cell_of` /
## `all_units`, so the control-point HEAL can resolve through the real effect pipeline.
class FakeBoard extends RefCounted:
	var cells: Dictionary = {}

	func place(unit, cell: Vector2i) -> void:
		cells[unit] = cell

	func cell_of(unit) -> Vector2i:
		return cells.get(unit, Vector2i(-999, -999))

	func all_units() -> Array:
		return cells.keys()

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for unit in cells:
			if cells[unit] == cell:
				out.append(unit)
		return out


## Records the exact spawn requests the controller makes, in order, and places each result on
## [member board] so the live-creep cap sees it.
class FakeSpawner extends RefCounted:
	var board: FakeBoard = null
	var calls: Array = []
	var units: Array = []

	func _init(p_board: FakeBoard = null) -> void:
		board = p_board

	func spawn_and_adopt(spawn_data, player_id, hint = 0):
		var cell: Vector2i = spawn_data.get("position", Vector2i(-1, -1))
		calls.append({
			"cell": cell,
			"player_id": player_id,
			"character_id": String(spawn_data.get("character_id", "")),
			"hint": hint,
		})
		var u := FakeUnit.new(player_id)
		units.append(u)
		if board != null:
			board.place(u, cell)
		return u

	## The spawn requests reduced to the tuple that must be identical run to run.
	func signature() -> Array:
		var out: Array = []
		for c in calls:
			out.append("%d|%d,%d|%s" % [c["player_id"], c["cell"].x, c["cell"].y,
				c["character_id"]])
		return out


class FakeMap extends RefCounted:
	var lanes: Array = []
	var base_cells: Dictionary = {}
	var control_points: Array = []


## The shape a MapResource build that predates the midpoint schema has: no `control_points`
## property at all. The controller must read it as "this map has none", never as an error.
class LegacyMap extends RefCounted:
	var lanes: Array = []
	var base_cells: Dictionary = {}


## Traditional's shape: a running player-switch counter, no acting unit.
class FakeTraditionalTS extends RefCounted:
	var current_turn: int = 1
	var registered_players: Array = []


## Speed First's shape: a real round counter and the unit whose turn it is.
class FakeSpeedTS extends RefCounted:
	var round_number: int = 1
	var current_acting_unit = null


# ==============================================================================
# Fixture
# ==============================================================================

const LANE_A: Array = [Vector2i(1, 1), Vector2i(5, 1), Vector2i(9, 1)]
const LANE_B: Array = [Vector2i(1, 7), Vector2i(5, 7), Vector2i(9, 7)]
const P0_BASE := Vector2i(0, 0)
const P1_BASE := Vector2i(10, 10)

## Two midpoints, authored OUT of sorted order on purpose: the controller is what canonicalises
## them, so the payout order is a property of the map rather than of the authoring.
const POINT_NEAR_B := Vector2i(5, 6)
const POINT_NEAR_A := Vector2i(4, 2)

const BASE_MOVEMENT := 3
const BASE_HEALTH := 40

var _board: FakeBoard
var _p0: FakePlayer
var _p1: FakePlayer


func before_each() -> void:
	_board = FakeBoard.new()
	_p0 = FakePlayer.new(0)
	_p1 = FakePlayer.new(1)


func after_each() -> void:
	# The registration is a static on ModeTuning: leaking it would make every later suite in the
	# run resolve knobs off a dead Siege ruleset.
	ModeTuning.clear()


func _map(points: Array = [POINT_NEAR_B, POINT_NEAR_A], two_lanes: bool = true) -> FakeMap:
	var m := FakeMap.new()
	m.lanes = [LANE_A.duplicate()]
	if two_lanes:
		m.lanes.append(LANE_B.duplicate())
	m.base_cells = {0: P0_BASE, 1: P1_BASE}
	m.control_points = points.duplicate()
	return m


func _ruleset() -> SiegeRuleset:
	var rs := SiegeRuleset.new()
	rs.wave_every_rounds = 3
	rs.creeps_per_lane = 0          # midpoint reinforcements are what this suite measures
	rs.max_live_creeps_per_side = 8
	rs.wave_on_first_round = false
	rs.creep_character_ids = PackedStringArray(["tree_grunt", "blightcap"])
	rs.respawn_enabled = false
	rs.hero_move_bonus = 0          # keep real Units at their character's movement
	rs.creep_move_bonus = 0
	rs.control_point_extra_creeps = 1
	rs.control_point_heal = 5
	return rs


func _controller(map = null, rs: SiegeRuleset = null, spawner = null, board = null) -> SiegeController:
	var c := SiegeController.new()
	c.name = "SiegeControlPointTestController"
	add_child_autofree(c)
	c.set_ruleset(rs if rs != null else _ruleset())
	c.set_armed(true)
	c.configure_from_map(map if map != null else _map())
	c.set_board_override(board if board != null else _board)
	c.set_spawner_override(spawner)
	return c


## Drive a full claim of [param cell] by [param side] under Traditional: the hero ends its turn
## on the cell, and the side's next turn start resolves it.
func _claim(c: SiegeController, ts: FakeTraditionalTS, player: FakePlayer, unit, cell: Vector2i) -> void:
	_board.place(unit, cell)
	c.handle_turn_ended(player, ts)
	ts.current_turn += 2
	c.handle_turn_started(player, ts)


func _run_rounds(c: SiegeController, first: int, last: int) -> void:
	for r in range(first, last + 1):
		c.observe_round(r)


# ==============================================================================
# 1. The map schema
# ==============================================================================

func test_a_map_that_authors_no_midpoints_has_none() -> void:
	var c := _controller(_map([]))
	assert_true(c.is_active(), "it is still a Siege map -- lanes and bases are what make one")
	assert_false(c.has_control_points(), "but it declares no midpoints")
	assert_eq(c.control_points(), [], "so there is nothing to own")
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1, "and every cell reads NEUTRAL")


func test_a_map_resource_without_the_field_at_all_is_read_as_none() -> void:
	# The map schema is owned by the map layer and lands separately: a build whose MapResource
	# predates it must resolve to an inert midpoint machine, never to an error.
	var legacy := LegacyMap.new()
	legacy.lanes = [LANE_A.duplicate()]
	legacy.base_cells = {0: P0_BASE, 1: P1_BASE}
	var c := _controller(legacy)
	assert_true(c.is_active(), "the mode still runs on a map without the new field")
	assert_false(c.has_control_points(), "it simply has no midpoints")


func test_the_authored_points_are_deduplicated_and_sorted() -> void:
	var c := _controller(_map([POINT_NEAR_B, POINT_NEAR_A, POINT_NEAR_B]))
	assert_eq(c.control_points(), [POINT_NEAR_A, POINT_NEAR_B],
		"a duplicate cell is one point, and the order is canonical (x then y) rather than "
		+ "however the map happened to list them -- that is what makes every payout pass "
		+ "reproducible on both peers")


func test_every_point_starts_neutral() -> void:
	var c := _controller()
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1, "nobody owns a midpoint at the opening")
	assert_eq(c.control_points_owned(0), [], "so neither side's owned list has anything in it")
	assert_eq(c.control_points_owned(1), [], "on either side")


# ==============================================================================
# 2. The claim lifecycle -- Traditional (a turn belongs to a PLAYER)
# ==============================================================================

func test_standing_on_a_midpoint_at_turn_end_begins_a_claim_not_an_ownership() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, POINT_NEAR_A)

	assert_eq(c.control_point_claimer(POINT_NEAR_A), -1, "nothing is being claimed yet")
	c.handle_turn_ended(_p0, ts)
	assert_eq(c.control_point_claimer(POINT_NEAR_A), 0, "ending the turn on it begins the claim")
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1,
		"but the point is NOT owned until the claimant survives to its own next turn")


func test_surviving_to_the_next_turn_start_takes_the_point() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, POINT_NEAR_A)

	c.handle_turn_ended(_p0, ts)
	ts.current_turn = 2
	c.handle_turn_started(_p1, ts)
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1,
		"the ENEMY's turn never completes our claim")

	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.control_point_owner(POINT_NEAR_A), 0, "our own next turn start takes it")
	assert_eq(c.control_point_claimer(POINT_NEAR_A), -1, "and consumes the pending claim")
	assert_eq(c.control_points_owned(0), [POINT_NEAR_A], "it shows up in our owned list")
	assert_eq(c.control_points_owned(1), [], "and not the enemy's")


func test_walking_off_before_the_claim_lands_interrupts_it() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, POINT_NEAR_A)
	c.handle_turn_ended(_p0, ts)

	_board.place(hero, Vector2i(6, 6))
	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1,
		"a claimant that is no longer ON the cell takes nothing")


func test_dying_interrupts_a_claim() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_board.place(hero, POINT_NEAR_A)
	c.handle_turn_ended(_p0, ts)
	assert_eq(c.control_point_claimer(POINT_NEAR_A), 0, "the claim is in flight")

	hero.hp = 0
	c.handle_unit_eliminated(hero)
	assert_eq(c.control_point_claimer(POINT_NEAR_A), -1, "the claimant dying drops it at once")

	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1, "and no dead unit ever claims anything")


func test_ownership_outlives_the_unit_that_won_it() -> void:
	# The one place a midpoint deliberately differs from a base capture. A capture is a moment;
	# ownership is a STATE, and one that evaporated with its holder would make every midpoint a
	# camping spot rather than something to take and defend.
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_claim(c, ts, _p0, hero, POINT_NEAR_A)
	assert_eq(c.control_point_owner(POINT_NEAR_A), 0, "the point is ours")

	hero.hp = 0
	c.handle_unit_eliminated(hero)
	assert_eq(c.control_point_owner(POINT_NEAR_A), 0,
		"and stays ours after the unit that took it falls -- a point is lost by being TAKEN")


func test_the_enemy_flips_a_held_point_by_repeating_the_claim() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var mine := FakeUnit.new(0)
	_claim(c, ts, _p0, mine, POINT_NEAR_A)
	assert_eq(c.control_point_owner(POINT_NEAR_A), 0, "ours to begin with")

	# Our holder is dislodged, and an enemy hero repeats the trick on the same cell.
	_board.place(mine, Vector2i(2, 2))
	var theirs := FakeUnit.new(1)
	_claim(c, ts, _p1, theirs, POINT_NEAR_A)

	assert_eq(c.control_point_owner(POINT_NEAR_A), 1, "the same rule flips it, with no special case")
	assert_eq(c.control_points_owned(0), [], "it leaves our owned list")
	assert_eq(c.control_points_owned(1), [POINT_NEAR_A], "and joins theirs")


func test_standing_on_a_point_you_already_own_is_a_hold_not_a_claim() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_claim(c, ts, _p0, hero, POINT_NEAR_A)

	c.handle_turn_ended(_p0, ts)
	assert_eq(c.control_point_claimer(POINT_NEAR_A), -1,
		"there is nothing left to claim, so the machine does not re-latch every turn")
	assert_eq(c.control_point_owner(POINT_NEAR_A), 0, "and it is still ours")


func test_two_points_are_claimed_independently() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var mine := FakeUnit.new(0)
	var theirs := FakeUnit.new(1)
	_claim(c, ts, _p0, mine, POINT_NEAR_A)
	_claim(c, ts, _p1, theirs, POINT_NEAR_B)

	assert_eq(c.control_point_owner(POINT_NEAR_A), 0, "each side holds what it took")
	assert_eq(c.control_point_owner(POINT_NEAR_B), 1, "and only that")
	assert_eq(c.control_points_owned(0), [POINT_NEAR_A], "owned lists stay sorted per side")
	assert_eq(c.control_points_owned(1), [POINT_NEAR_B], "on both sides")


# ==============================================================================
# 3. Who may claim
# ==============================================================================

func test_a_creep_standing_on_a_midpoint_never_claims_it() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var creep := FakeUnit.new(0)
	SiegeController.stamp_creep(creep, LANE_A.duplicate(), 3)
	_board.place(creep, POINT_NEAR_A)

	c.handle_turn_ended(_p0, ts)
	assert_eq(c.control_point_claimer(POINT_NEAR_A), -1,
		"creeps push the lane; the midpoints are the squad's to fight over")
	ts.current_turn = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1,
		"and no amount of standing there changes that -- the same predicate that bars a creep "
		+ "from capturing a base bars it here")


func test_a_neutral_standing_on_a_midpoint_never_claims_it() -> void:
	var c := _controller()
	var ts := FakeTraditionalTS.new()
	var wild := FakeUnit.new(0)
	wild.is_neutral = true
	_board.place(wild, POINT_NEAR_A)

	c.handle_turn_ended(_p0, ts)
	assert_eq(c.control_point_claimer(POINT_NEAR_A), -1,
		"a jungle camp is a third party and decides nothing")


# ==============================================================================
# 4. The claim lifecycle -- Speed First (a turn belongs to a UNIT)
# ==============================================================================

func test_speed_first_only_the_claimants_own_turn_completes_it() -> void:
	var c := _controller()
	var ts := FakeSpeedTS.new()
	var holder := FakeUnit.new(0)
	var other := FakeUnit.new(0)
	_board.place(holder, POINT_NEAR_A)
	_board.place(other, Vector2i(3, 3))

	ts.current_acting_unit = holder
	c.handle_turn_ended(_p0, ts)
	assert_eq(c.control_point_claimer(POINT_NEAR_A), 0, "the holder's own turn end begins it")

	# A different unit of the SAME side acts. It must neither complete nor cancel the claim.
	ts.current_acting_unit = other
	ts.round_number = 2
	c.handle_turn_started(_p0, ts)
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1,
		"another unit's turn must not complete the claim early")
	c.handle_turn_ended(_p0, ts)
	assert_eq(c.control_point_claimer(POINT_NEAR_A), 0,
		"and must not cancel it either -- it is not the claimant")

	ts.current_acting_unit = holder
	ts.round_number = 3
	c.handle_turn_started(_p0, ts)
	assert_eq(c.control_point_owner(POINT_NEAR_A), 0, "the holder's OWN next turn takes the point")


func test_speed_first_the_claimant_being_dislodged_still_interrupts() -> void:
	var c := _controller()
	var ts := FakeSpeedTS.new()
	var holder := FakeUnit.new(0)
	_board.place(holder, POINT_NEAR_A)
	ts.current_acting_unit = holder
	c.handle_turn_ended(_p0, ts)

	_board.place(holder, POINT_NEAR_A + Vector2i(1, 0))
	ts.round_number = 2
	c.handle_turn_started(_p0, ts)
	assert_eq(c.control_point_owner(POINT_NEAR_A), -1,
		"knocked one cell off, it claims nothing under Speed First either")


# ==============================================================================
# 5. What an owned point pays -- reinforcements
# ==============================================================================

func test_the_nearest_lane_is_pure_arithmetic_over_the_map() -> void:
	var c := _controller()
	assert_eq(c.nearest_lane_index(POINT_NEAR_A), 0,
		"(4,2) is one cell off lane A, so lane A is the one its reinforcements join")
	assert_eq(c.nearest_lane_index(POINT_NEAR_B), 1, "and (5,6) sits beside lane B")
	assert_eq(c.nearest_lane_index(Vector2i(5, 4)), 0,
		"a cell exactly between the two lanes breaks the tie on the LOWER index, so the answer "
		+ "is fixed rather than whichever lane was visited first")


func test_an_owned_point_adds_exactly_the_knobs_creeps_at_its_own_cell() -> void:
	var spawner := FakeSpawner.new(_board)
	var rs := _ruleset()
	rs.control_point_extra_creeps = 2
	var c := _controller(_map(), rs, spawner, _board)
	var ts := FakeTraditionalTS.new()

	var hero := FakeUnit.new(0)
	_claim(c, ts, _p0, hero, POINT_NEAR_B)
	assert_eq(spawner.calls.size(), 0, "claiming a point spawns nothing by itself")

	_run_rounds(c, 1, 3)
	assert_eq(spawner.calls.size(), 2, "the wave round adds exactly the knob's 2 creeps")
	for call in spawner.calls:
		assert_eq(call["cell"], POINT_NEAR_B, "each one enters AT the point, not at a lane end")
		assert_eq(int(call["player_id"]), 0, "for the side that holds it, and only that side")

	assert_eq(BotController.march_lane(spawner.units[0]), LANE_B,
		"and marches the lane NEAREST the point -- lane B, in player 0's authored direction")
	assert_true(CaptureBase.is_creep(spawner.units[0]),
		"a midpoint reinforcement is a creep like any other: it can never claim anything")


func test_a_neutral_point_reinforces_nobody() -> void:
	var spawner := FakeSpawner.new(_board)
	var c := _controller(_map(), _ruleset(), spawner, _board)
	_run_rounds(c, 1, 6)
	assert_eq(spawner.calls.size(), 0,
		"two unclaimed midpoints and no lane creeps means no wave at all -- the payout is for "
		+ "HOLDING one, not for the map having one")


func test_the_reinforcements_are_bounded_by_the_same_live_creep_cap() -> void:
	var spawner := FakeSpawner.new(_board)
	var rs := _ruleset()
	rs.control_point_extra_creeps = 3
	rs.max_live_creeps_per_side = 1
	var c := _controller(_map(), rs, spawner, _board)
	var ts := FakeTraditionalTS.new()

	var hero := FakeUnit.new(0)
	_claim(c, ts, _p0, hero, POINT_NEAR_A)
	_run_rounds(c, 1, 3)

	assert_eq(spawner.calls.size(), 1,
		"holding a midpoint raises how FAST a side reaches its cap, never the cap itself")
	assert_eq(c.live_creep_count(0), 1, "so the side fields exactly its cap and no more")


func test_lane_creeps_come_first_then_the_midpoints_in_sorted_order() -> void:
	var spawner := FakeSpawner.new(_board)
	var rs := _ruleset()
	rs.creeps_per_lane = 1
	rs.control_point_extra_creeps = 1
	var c := _controller(_map(), rs, spawner, _board)
	var ts := FakeTraditionalTS.new()

	var a := FakeUnit.new(0)
	var b := FakeUnit.new(0)
	_claim(c, ts, _p0, a, POINT_NEAR_B)
	_claim(c, ts, _p0, b, POINT_NEAR_A)
	_run_rounds(c, 1, 3)

	var p0_cells: Array = []
	for call in spawner.calls:
		if int(call["player_id"]) == 0:
			p0_cells.append(call["cell"])
	assert_eq(p0_cells, [LANE_A[0], LANE_B[0], POINT_NEAR_A, POINT_NEAR_B],
		"lanes in authored order first, then the held midpoints in SORTED cell order -- one "
		+ "fixed sequence, so both peers spawn the same wave")


func test_a_side_with_no_points_still_gets_its_ordinary_wave() -> void:
	var spawner := FakeSpawner.new(_board)
	var rs := _ruleset()
	rs.creeps_per_lane = 1
	var c := _controller(_map(), rs, spawner, _board)
	var ts := FakeTraditionalTS.new()
	var hero := FakeUnit.new(0)
	_claim(c, ts, _p0, hero, POINT_NEAR_A)
	_run_rounds(c, 1, 3)

	var p1: int = 0
	for call in spawner.calls:
		if int(call["player_id"]) == 1:
			p1 += 1
	assert_eq(p1, 2, "the side holding nothing pushes its 1 creep down each of the 2 lanes, "
		+ "exactly as it did before midpoints existed")


# ==============================================================================
# 6. What an owned point pays -- the round-start heal (real Units, real pipeline)
# ==============================================================================

func _character() -> CharacterResource:
	var ch := CharacterResource.new()
	ch.character_id = &"vineweave"
	ch.display_name = "Torvald"
	ch.base_health = BASE_HEALTH
	ch.base_attack = 20
	ch.base_defense = 15
	ch.base_speed = 12
	ch.base_movement = BASE_MOVEMENT
	return ch


## A live unit owned by [param player_id], on the tree so its stats and StatusController exist.
func _unit(player_id: int) -> Unit:
	var u := Unit.new()
	u.character_resource = _character()
	var p := Player.new()
	p.player_id = player_id
	u.owner_player = p
	add_child_autofree(u)
	return u


func _wound(u: Unit, to_health: int) -> void:
	u.unit_stats.set_stat("health", to_health)


func test_the_round_start_heal_restores_the_owners_units_on_the_point() -> void:
	var rs := _ruleset()
	rs.control_point_heal = 5
	var c := _controller(_map(), rs, null, _board)
	var ts := FakeTraditionalTS.new()

	var hero := _unit(0)
	_wound(hero, 10)
	_claim(c, ts, _p0, hero, POINT_NEAR_A)
	assert_eq(c.control_point_owner(POINT_NEAR_A), 0, "the point is held")
	assert_eq(hero.current_health, 10, "and nothing has healed it yet")

	c.observe_round(1)
	assert_eq(hero.current_health, 15,
		"the round boundary restores exactly the ruleset's 5, through the ordinary heal "
		+ "pipeline -- so the number floats and every heal rule applies")
	c.observe_round(2)
	assert_eq(hero.current_health, 20, "and again on the next round, for as long as it is held")


func test_an_enemy_standing_on_your_point_is_healed_by_nothing() -> void:
	var c := _controller(_map(), _ruleset(), null, _board)
	var ts := FakeTraditionalTS.new()

	var mine := _unit(0)
	_wound(mine, 10)
	_claim(c, ts, _p0, mine, POINT_NEAR_A)

	# The enemy takes the cell (the point stays OURS until it completes a claim of its own).
	var theirs := _unit(1)
	_wound(theirs, 10)
	_board.place(theirs, POINT_NEAR_A)

	c.observe_round(1)
	assert_eq(theirs.current_health, 10,
		"taking the cell takes the cell -- the sustain belongs to whoever OWNS the point")
	assert_eq(mine.current_health, 15,
		"while our own unit, still on it, is topped up as usual")


func test_a_unit_standing_off_the_point_is_healed_by_nothing() -> void:
	var c := _controller(_map(), _ruleset(), null, _board)
	var ts := FakeTraditionalTS.new()

	var holder := _unit(0)
	_wound(holder, 10)
	_claim(c, ts, _p0, holder, POINT_NEAR_A)

	var elsewhere := _unit(0)
	_wound(elsewhere, 10)
	_board.place(elsewhere, Vector2i(7, 7))

	c.observe_round(1)
	assert_eq(elsewhere.current_health, 10,
		"owning a midpoint heals the units STANDING on it, not the whole army")
	assert_eq(holder.current_health, 15, "which the holder proves it is doing at all")


func test_the_heal_never_overfills_and_the_knob_can_switch_it_off() -> void:
	var rs := _ruleset()
	rs.control_point_heal = 5
	var c := _controller(_map(), rs, null, _board)
	var ts := FakeTraditionalTS.new()
	var hero := _unit(0)
	_wound(hero, BASE_HEALTH - 2)
	_claim(c, ts, _p0, hero, POINT_NEAR_A)

	c.observe_round(1)
	assert_eq(hero.current_health, BASE_HEALTH,
		"the unit's own heal() clamps to its max -- the point cannot overfill it")

	rs.control_point_heal = 0
	_wound(hero, 10)
	c.observe_round(2)
	assert_eq(hero.current_health, 10,
		"and a heal of 0 is a knob turned off, not a heal of nothing that still runs")


# ==============================================================================
# 7. The neutral-camp reward becomes TIMED in this mode
# ==============================================================================

func _runtime(board) -> BaseAssaultRuntime:
	var r := BaseAssaultRuntime.new()
	r.name = "CampBuffTestRuntime"
	add_child_autofree(r)
	r.set_armed(true)
	r.set_board_override(board)
	return r


func test_the_shipped_siege_ruleset_declares_the_camp_buff_timer() -> void:
	var rs := SiegeRuleset.new()
	assert_eq(rs.camp_buff_turns, 5, "Siege pays a camp kill in 5 turns of buff, out of the box")
	assert_eq(rs.camp_buff_duration(), 5, "and the accessor floors rather than inventing a number")
	var broken := SiegeRuleset.new()
	broken.camp_buff_turns = -3
	assert_eq(broken.camp_buff_duration(), 0,
		"a negative timer is 'no timer' -- i.e. the permanent bounty -- never a buff that has "
		+ "already run out")


func test_with_no_mode_armed_the_camp_kill_still_pays_the_permanent_bounty() -> void:
	ModeTuning.clear()
	var runtime := _runtime(_board)
	assert_eq(runtime.camp_buff_turns(), 0, "no mode declares a timer, so there is none")

	var killer := FakeUnit.new(0)
	var camp := FakeUnit.new(2)
	camp.is_neutral = true
	_board.place(killer, Vector2i(2, 2))

	runtime._on_damage_dealt(killer, camp, 40)
	camp.hp = 0
	runtime._on_unit_eliminated(camp, null)
	assert_eq(runtime.team_bonus(0), BaseAssaultRuntime.BOUNTY_AMOUNT,
		"base assault, campaign and skirmish are byte-identical to before the knob existed")


func test_in_siege_the_camp_kill_pays_a_timed_buff_instead_of_the_ledger() -> void:
	var rs := _ruleset()
	rs.camp_buff_turns = 5
	_controller(_map(), rs, null, _board)     # arming Siege is what declares the knob

	var runtime := _runtime(_board)
	assert_eq(runtime.camp_buff_turns(), 5, "the mode's ruleset is where the timer comes from")

	var killer := _unit(0)
	_board.place(killer, Vector2i(2, 2))
	var camp := FakeUnit.new(2)
	camp.is_neutral = true

	runtime._on_damage_dealt(killer, camp, 40)
	camp.hp = 0
	runtime._on_unit_eliminated(camp, null)

	assert_true(killer.get_status_controller().has_status(ModeTuning.CAMP_BUFF_STATUS_ID),
		"the killer's side carries the camp buff as a real status")
	assert_eq(runtime.team_bonus(0), 0,
		"and NOTHING went into the permanent ledger -- a timed reward that also accrued forever "
		+ "would be both rewards at once")


func test_the_timed_buff_expires_after_exactly_the_knobs_turns() -> void:
	var rs := _ruleset()
	rs.camp_buff_turns = 5
	_controller(_map(), rs, null, _board)
	var runtime := _runtime(_board)

	var killer := _unit(0)
	_board.place(killer, Vector2i(2, 2))
	var camp := FakeUnit.new(2)
	camp.is_neutral = true
	runtime._on_damage_dealt(killer, camp, 40)
	camp.hp = 0
	runtime._on_unit_eliminated(camp, null)

	var sc := killer.get_status_controller()
	for i in range(4):
		sc.tick_all(null)
	assert_true(sc.has_status(ModeTuning.CAMP_BUFF_STATUS_ID),
		"four turns in, the buff is still on the unit")
	sc.tick_all(null)
	assert_false(sc.has_status(ModeTuning.CAMP_BUFF_STATUS_ID),
		"and it is gone on the fifth -- exactly camp_buff_turns, not one more")


func test_a_second_camp_kill_refreshes_the_buff_and_never_stacks_it() -> void:
	# CONQUEST.md rule 6, on the reward a push mode pays over and over.
	var rs := _ruleset()
	rs.camp_buff_turns = 5
	_controller(_map(), rs, null, _board)
	var runtime := _runtime(_board)

	var killer := _unit(0)
	_board.place(killer, Vector2i(2, 2))
	var sc := killer.get_status_controller()

	for kill in range(2):
		var camp := FakeUnit.new(2)
		camp.is_neutral = true
		runtime._on_damage_dealt(killer, camp, 40)
		camp.hp = 0
		runtime._on_unit_eliminated(camp, null)
		sc.tick_all(null)

	assert_eq(sc.stack_count(ModeTuning.CAMP_BUFF_STATUS_ID), 1,
		"two camp kills leave exactly ONE instance on the unit")
	for i in range(4):
		sc.tick_all(null)
	assert_false(sc.has_status(ModeTuning.CAMP_BUFF_STATUS_ID),
		"and the second kill reset the timer rather than adding a second five turns")


func test_only_the_killers_side_is_paid() -> void:
	var rs := _ruleset()
	rs.camp_buff_turns = 5
	_controller(_map(), rs, null, _board)
	var runtime := _runtime(_board)

	var killer := _unit(0)
	var bystander := _unit(0)
	var enemy := _unit(1)
	_board.place(killer, Vector2i(2, 2))
	_board.place(bystander, Vector2i(3, 3))
	_board.place(enemy, Vector2i(8, 8))

	var camp := FakeUnit.new(2)
	camp.is_neutral = true
	runtime._on_damage_dealt(killer, camp, 40)
	camp.hp = 0
	runtime._on_unit_eliminated(camp, null)

	assert_true(bystander.get_status_controller().has_status(ModeTuning.CAMP_BUFF_STATUS_ID),
		"the reward keeps its SIDE-WIDE scope: it is the team's prize, not the killer's")
	assert_false(enemy.get_status_controller().has_status(ModeTuning.CAMP_BUFF_STATUS_ID),
		"and only the side that earned it")


func test_the_buff_vehicle_is_the_authored_status_with_the_modes_duration_stamped_on() -> void:
	var status := ModeTuning.camp_buff_status(7)
	assert_not_null(status, "a positive timer builds a real status")
	assert_eq(status.id, ModeTuning.CAMP_BUFF_STATUS_ID,
		"reusing the buff the Arena's camps already pay, rather than authoring a second one")
	assert_eq(status.duration_turns, 7, "with the MODE's number stamped onto the copy")
	assert_eq(status.stacking, StatusCondition.Stacking.REFRESH, "and refresh, never stack")
	assert_null(ModeTuning.camp_buff_status(0),
		"while 0 turns is not a timed buff at all -- that is the permanent-bounty case")

	var authored = load(ModeTuning.CAMP_BUFF_STATUS_PATH)
	if authored is StatusCondition:
		assert_ne(int((authored as StatusCondition).duration_turns), 7,
			"and the shared authoring resource was DUPLICATED, never restamped in place "
			+ "(CONQUEST.md rule 7)")


# ==============================================================================
# 8. Neutral defaults -- a battle with no mode ruleset
# ==============================================================================

func test_a_plain_skirmish_has_no_control_point_machinery_at_all() -> void:
	ModeTuning.clear()
	assert_false(ModeTuning.has_mode(), "no mode is armed")
	assert_eq(ModeTuning.camp_buff_turns(), 0,
		"so a camp kill pays what it always paid -- there is no timer to read")
	assert_eq(ModeTuning.get_int(&"control_point_extra_creeps", 0), 0,
		"and no midpoint reinforcement knob resolves to anything")
	assert_eq(ModeTuning.get_int(&"control_point_heal", 0), 0, "nor a midpoint heal")
	var live := SiegeController.instance()
	assert_true(live == null or not live.is_armed(),
		"and nothing has the mode's runtime armed, so no round boundary can run a midpoint pass")


func test_the_shipped_control_point_defaults_are_ruleset_data() -> void:
	var rs := SiegeRuleset.new()
	assert_eq(rs.control_point_extra_creeps, 1, "a held midpoint sends one extra creep per wave")
	assert_eq(rs.control_point_heal, 5, "and restores 5 to the units holding it")
	var broken := SiegeRuleset.new()
	broken.control_point_extra_creeps = -2
	broken.control_point_heal = -9
	assert_eq(broken.control_point_creeps(), 0, "a negative reinforcement is none...")
	assert_eq(broken.control_point_heal_amount(), 0, "...and a negative heal is none, never harm")


# ==============================================================================
# 9. Determinism
# ==============================================================================

func test_two_identical_runs_resolve_the_midpoints_identically() -> void:
	var signatures: Array = []
	for run in range(2):
		var board := FakeBoard.new()
		var spawner := FakeSpawner.new(board)
		var rs := _ruleset()
		rs.creeps_per_lane = 1
		rs.control_point_extra_creeps = 2
		var c := SiegeController.new()
		c.name = "SiegeDeterminismController%d" % run
		add_child_autofree(c)
		c.set_ruleset(rs)
		c.set_armed(true)
		c.configure_from_map(_map())
		c.set_board_override(board)
		c.set_spawner_override(spawner)

		var ts := FakeTraditionalTS.new()
		var a := FakeUnit.new(0)
		var b := FakeUnit.new(1)
		board.place(a, POINT_NEAR_B)
		c.handle_turn_ended(_p0, ts)
		ts.current_turn += 2
		c.handle_turn_started(_p0, ts)
		board.place(b, POINT_NEAR_A)
		c.handle_turn_ended(_p1, ts)
		ts.current_turn += 2
		c.handle_turn_started(_p1, ts)

		var sig: Array = []
		for r in range(1, 10):
			c.observe_round(r)
			sig.append("r%d|%d|%d" % [r, c.control_point_owner(POINT_NEAR_A),
				c.control_point_owner(POINT_NEAR_B)])
		sig.append_array(spawner.signature())
		signatures.append(sig)
		ModeTuning.clear()

	assert_gt((signatures[0] as Array).size(), 0, "the run produced something to compare")
	assert_eq(signatures[0], signatures[1],
		"same map + same ruleset + same turn sequence => identical ownership and an identical "
		+ "spawn sequence, every round (no RNG anywhere in the midpoint machine)")
