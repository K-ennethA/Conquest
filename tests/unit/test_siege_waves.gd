extends GutTest

## SIEGE creep waves and squad respawns -- [SiegeController]'s two scheduled jobs.
##
## Headless: a fake spawner stands in for [method SpawnManager.spawn_and_adopt] (recording
## every spawn it is asked for and placing the result on a fake board so the live-creep cap
## can be counted), a fake MapResource carries the `lanes` / `base_cells` schema, and rounds
## are stepped with [method SiegeController.observe_round] instead of a turn system.
##
## The point of most of these tests is DETERMINISM. Nothing in the wave scheduler may consult
## an RNG or the wall clock, because a Siege match has to stay in lockstep: the same board and
## the same round sequence must produce the same creeps, on the same cells, in the same order,
## every single time.

# --- Doubles -----------------------------------------------------------------

class FakeUnit extends RefCounted:
	var team: int
	var hp: int = 100
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
			"kind": String(spawn_data.get("spawn_kind", "")),
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
			out.append("%d|%d,%d|%s|%s" % [c["player_id"], c["cell"].x, c["cell"].y,
				c["character_id"], c["kind"]])
		return out


class FakeMap extends RefCounted:
	var lanes: Array = []
	var base_cells: Dictionary = {}


# --- Fixture -----------------------------------------------------------------

const LANE_A: Array = [Vector2i(1, 1), Vector2i(5, 1), Vector2i(9, 1)]
const LANE_B: Array = [Vector2i(1, 7), Vector2i(5, 7), Vector2i(9, 7)]
const P0_BASE := Vector2i(0, 0)
const P1_BASE := Vector2i(10, 10)


func _make_map(two_lanes: bool = false) -> FakeMap:
	var m := FakeMap.new()
	m.lanes = [LANE_A.duplicate()]
	if two_lanes:
		m.lanes.append(LANE_B.duplicate())
	m.base_cells = {0: P0_BASE, 1: P1_BASE}
	return m


func _make_ruleset() -> SiegeRuleset:
	var rs := SiegeRuleset.new()
	rs.wave_every_rounds = 3
	rs.creeps_per_lane = 2
	rs.max_live_creeps_per_side = 8
	rs.wave_on_first_round = false
	rs.creep_character_ids = PackedStringArray(["tree_grunt", "blightcap"])
	rs.creep_aggro_radius = 3
	rs.respawn_base_delay = 1
	rs.respawn_rounds_per_step = 6
	rs.respawn_max_delay = 3
	rs.respawn_enabled = true
	return rs


func _make_controller(map: FakeMap, rs: SiegeRuleset, spawner, board) -> SiegeController:
	var c := SiegeController.new()
	c.name = "SiegeWaveTestController"
	add_child_autofree(c)
	c.set_ruleset(rs)
	c.set_armed(true)
	c.configure_from_map(map)
	c.set_board_override(board)
	c.set_spawner_override(spawner)
	return c


## Step [param c] through rounds 1..[param last].
func _run_rounds(c: SiegeController, last: int) -> void:
	for r in range(1, last + 1):
		c.observe_round(r)


# --- Cadence ------------------------------------------------------------------

func test_no_wave_before_the_cadence_lands() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var c := _make_controller(_make_map(), _make_ruleset(), spawner, board)

	_run_rounds(c, 2)
	assert_eq(spawner.calls.size(), 0, "a cadence of 3 pushes nothing on rounds 1 and 2")


func test_a_wave_lands_on_the_cadence_round_for_both_sides() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var c := _make_controller(_make_map(), _make_ruleset(), spawner, board)

	_run_rounds(c, 3)
	# 1 lane x 2 creeps x 2 sides.
	assert_eq(spawner.calls.size(), 4, "round 3 pushes a full wave for each side")

	var p0_cells: Array = []
	var p1_cells: Array = []
	for call in spawner.calls:
		if int(call["player_id"]) == 0:
			p0_cells.append(call["cell"])
		else:
			p1_cells.append(call["cell"])
	assert_eq(p0_cells, [LANE_A[0], LANE_A[0]],
		"player 0's creeps enter at ITS end of the lane (the first waypoint)")
	assert_eq(p1_cells, [LANE_A[2], LANE_A[2]],
		"player 1's enter at the other end -- lanes are authored 0-to-1 and reversed per side")


func test_wave_cadence_is_a_ruleset_knob() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var rs := _make_ruleset()
	rs.wave_every_rounds = 2
	var c := _make_controller(_make_map(), rs, spawner, board)

	_run_rounds(c, 4)
	# Waves on rounds 2 and 4: 2 waves x 2 sides x 2 creeps.
	assert_eq(spawner.calls.size(), 8, "a cadence of 2 pushes on rounds 2 and 4")


func test_wave_size_is_a_ruleset_knob() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var rs := _make_ruleset()
	rs.creeps_per_lane = 1
	var c := _make_controller(_make_map(true), rs, spawner, board)

	_run_rounds(c, 3)
	assert_eq(spawner.calls.size(), 4, "1 creep per lane x 2 lanes x 2 sides")


func test_the_first_round_wave_is_opt_in() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var rs := _make_ruleset()
	rs.wave_on_first_round = true
	var c := _make_controller(_make_map(), rs, spawner, board)

	c.observe_round(1)
	assert_eq(spawner.calls.size(), 4, "with the opener enabled, round 1 pushes a wave")


func test_the_live_creep_cap_truncates_a_wave_instead_of_skipping_it() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var rs := _make_ruleset()
	rs.creeps_per_lane = 3
	rs.max_live_creeps_per_side = 2
	var c := _make_controller(_make_map(), rs, spawner, board)

	_run_rounds(c, 3)
	assert_eq(spawner.calls.size(), 4, "each side is capped at 2 live creeps, not 3")
	assert_eq(c.live_creep_count(0), 2, "player 0 fields exactly its cap")
	assert_eq(c.live_creep_count(1), 2, "and so does player 1")

	# Kill one of player 0's creeps: the next wave refills the freed slot, and only that slot.
	spawner.units[0].hp = 0
	assert_eq(c.live_creep_count(0), 1, "a dead creep stops counting against the cap")
	_run_rounds_from(c, 4, 6)
	assert_eq(c.live_creep_count(0), 2, "the next wave tops player 0 back up to the cap")


# --- Determinism --------------------------------------------------------------

func test_two_identical_runs_spawn_the_same_creeps_on_the_same_cells_in_the_same_order() -> void:
	var runs: Array = []
	for i in range(2):
		var board := FakeBoard.new()
		var spawner := FakeSpawner.new(board)
		var c := _make_controller(_make_map(true), _make_ruleset(), spawner, board)
		_run_rounds(c, 9)
		runs.append(spawner.signature())

	assert_gt((runs[0] as Array).size(), 0, "the run actually produced spawns to compare")
	assert_eq(runs[0], runs[1],
		"same map + same ruleset + same rounds => byte-identical spawn sequence (no RNG anywhere)")


func test_the_creep_roster_is_a_fixed_cycle_not_a_roll() -> void:
	var rs := _make_ruleset()   # ["tree_grunt", "blightcap"]
	var c := _make_controller(_make_map(), rs, null, null)

	assert_eq(c.wave_creep_id(0), "tree_grunt", "slot 0 is the first roster entry")
	assert_eq(c.wave_creep_id(1), "blightcap", "slot 1 the second")
	assert_eq(c.wave_creep_id(2), "tree_grunt", "and it wraps -- a cycle, never a draw")
	assert_eq(c.wave_creep_id(7), "blightcap", "arbitrarily far along, still pure arithmetic")


# --- What a creep is stamped with ---------------------------------------------

func test_a_spawned_creep_carries_its_lane_its_aggro_and_both_marks() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var c := _make_controller(_make_map(), _make_ruleset(), spawner, board)
	_run_rounds(c, 3)

	var p0_creep = spawner.units[0]
	var p1_creep = null
	for i in range(spawner.calls.size()):
		if int(spawner.calls[i]["player_id"]) == 1:
			p1_creep = spawner.units[i]
			break

	assert_true(CaptureBase.is_creep(p0_creep), "a wave creep carries the creep mark")
	assert_true(BotTurnDriver.is_ai_driven(p0_creep),
		"and the AI-driven mark, which is what makes the driver act it on its owner's turn")
	assert_eq(BotController.march_lane(p0_creep), LANE_A,
		"player 0's creep walks the lane as authored")
	var reversed: Array = LANE_A.duplicate()
	reversed.reverse()
	assert_eq(BotController.march_lane(p1_creep), reversed,
		"player 1's walks it backwards, so both sides push toward the other's base")
	assert_eq(int(p0_creep.get_meta(BotController.MARCH_AGGRO_META)), 3,
		"the ruleset's aggro radius is stamped on the creep the planner reads")


func test_creeps_spawn_as_reinforcements_so_they_charge_on_arrival() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var c := _make_controller(_make_map(), _make_ruleset(), spawner, board)
	_run_rounds(c, 3)
	assert_eq(String(spawner.calls[0]["kind"]), "Reinforcement",
		"Reinforcement is the kind MapLoader resolves AGGRESSIVE -- the right fallback the "
		+ "moment the march branch declines and the creep enters the ordinary planner")


# --- Squad respawns -----------------------------------------------------------

func _respawn_fixture() -> Dictionary:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var rs := _make_ruleset()
	rs.creeps_per_lane = 0        # isolate respawns from waves
	var c := _make_controller(_make_map(), rs, spawner, board)
	return {"board": board, "spawner": spawner, "ruleset": rs, "controller": c}


func test_an_early_death_costs_one_round() -> void:
	var f := _respawn_fixture()
	var c: SiegeController = f["controller"]
	var spawner: FakeSpawner = f["spawner"]

	c.observe_round(1)
	var hero := FakeUnit.new(0)
	hero.character_id = "vineweave"
	hero.hp = 0
	c.handle_unit_eliminated(hero)
	assert_eq(c.respawn_queue().size(), 1, "the death is queued, not resolved on the spot")
	assert_eq(int(c.respawn_queue()[0]["delay"]), 1,
		"a round-1 death is the cheapest the curve gets -- one round out")

	c.observe_round(2)
	assert_eq(spawner.calls.size(), 1, "so it is back on the very next round")
	assert_eq(spawner.calls[0]["cell"], P0_BASE, "at its OWN base cell")
	assert_eq(String(spawner.calls[0]["character_id"]), "vineweave", "as the same character")
	assert_eq(int(spawner.calls[0]["player_id"]), 0, "for the same side")
	assert_eq(c.respawn_queue().size(), 0, "and leaves the queue")


func test_the_wait_escalates_as_the_match_runs_long() -> void:
	var rs := _make_ruleset()   # base 1, step 6, max 3
	assert_eq(rs.respawn_delay_for_round(1), 1, "round 1: one round out")
	assert_eq(rs.respawn_delay_for_round(5), 1, "still 1 at the end of the first step")
	assert_eq(rs.respawn_delay_for_round(6), 2, "the first step lands on round 6")
	assert_eq(rs.respawn_delay_for_round(11), 2, "and holds for that whole step")
	assert_eq(rs.respawn_delay_for_round(12), 3, "the second step lands on round 12")
	assert_eq(rs.respawn_delay_for_round(13), 3, "a round-13 death is out for three rounds")
	assert_eq(rs.respawn_delay_for_round(60), 3,
		"and the ceiling holds however long the match runs -- nobody is ever out of the match")


func test_a_late_death_really_waits_the_escalated_time_on_the_board() -> void:
	var f := _respawn_fixture()
	var c: SiegeController = f["controller"]
	var spawner: FakeSpawner = f["spawner"]

	_run_rounds(c, 13)
	var hero := FakeUnit.new(0)
	hero.hp = 0
	c.handle_unit_eliminated(hero)
	assert_eq(int(c.respawn_queue()[0]["delay"]), 3, "a round-13 death is stamped with 3")

	_run_rounds_from(c, 14, 15)
	assert_eq(spawner.calls.size(), 0, "two rounds later it is still out")
	c.observe_round(16)
	assert_eq(spawner.calls.size(), 1, "and returns on the third")


func test_a_queued_respawn_keeps_the_wait_it_was_given_at_death() -> void:
	# The determinism half of the escalating timer: the wait is a function of the DEATH round
	# only, so a unit that fell early is never retroactively punished for a long match, and no
	# peer can disagree about when it is due.
	var f := _respawn_fixture()
	var c: SiegeController = f["controller"]
	(f["ruleset"] as SiegeRuleset).respawn_base_delay = 5   # long enough to still be queued

	c.observe_round(1)
	var hero := FakeUnit.new(0)
	hero.hp = 0
	c.handle_unit_eliminated(hero)
	var stamped: int = int(c.respawn_queue()[0]["delay"])

	_run_rounds_from(c, 2, 4)
	assert_eq(int(c.respawn_queue()[0]["delay"]), stamped,
		"three rounds of play later, the wait it was given has not moved")
	assert_eq(int(c.respawn_queue()[0]["rounds_remaining"]), stamped - 3,
		"only the REMAINING time counts down")


func test_the_respawn_curve_is_three_ruleset_knobs() -> void:
	var rs := SiegeRuleset.new()
	rs.respawn_base_delay = 2
	rs.respawn_rounds_per_step = 3
	rs.respawn_max_delay = 4

	assert_eq(rs.respawn_delay_for_round(0), 2, "the base is the floor")
	assert_eq(rs.respawn_delay_for_round(3), 3, "a step of 3 escalates three times as fast")
	assert_eq(rs.respawn_delay_for_round(6), 4, "and the ceiling is reached sooner")
	assert_eq(rs.respawn_delay_for_round(99), 4, "then holds")

	# Degenerate authoring is clamped rather than exploding.
	var broken := SiegeRuleset.new()
	broken.respawn_base_delay = 0
	broken.respawn_rounds_per_step = 0
	broken.respawn_max_delay = -5
	assert_eq(broken.respawn_delay_for_round(0), 1,
		"a base of 0 would return a unit on the round it died, so it floors at 1")
	assert_gte(broken.respawn_delay_for_round(4), 1,
		"a step of 0 is a division by zero, so it floors at 1 too")


func test_the_respawn_queue_is_the_hud_contract() -> void:
	var f := _respawn_fixture()
	var c: SiegeController = f["controller"]

	_run_rounds(c, 6)
	var mine := FakeUnit.new(0)
	mine.character_id = "vineweave"
	mine.hp = 0
	c.handle_unit_eliminated(mine)
	var theirs := FakeUnit.new(1)
	theirs.character_id = "blightcap"
	theirs.hp = 0
	c.handle_unit_eliminated(theirs)

	var mine_pending: Array = c.pending_respawns(0)
	assert_eq(mine_pending.size(), 1, "pending_respawns filters to one side")
	var entry: Dictionary = mine_pending[0]
	assert_eq(String(entry["character_id"]), "vineweave", "naming the character coming back")
	assert_eq(int(entry["round"]), 6, "the round it died on")
	assert_eq(int(entry["delay"]), 2, "the REAL escalated wait it was given, not a default")
	assert_eq(int(entry["rounds_remaining"]), 2, "and the live countdown, in rounds")

	c.observe_round(7)
	assert_eq(int(c.pending_respawns(0)[0]["rounds_remaining"]), 1, "which ticks down")
	assert_eq(c.pending_respawns(1).size(), 1, "the other side's queue is its own")

	c.observe_round(8)
	assert_eq(c.pending_respawns(0).size(), 0, "and empties when the unit actually returns")


func test_respawns_can_be_switched_off_entirely() -> void:
	var f := _respawn_fixture()
	var c: SiegeController = f["controller"]
	(f["ruleset"] as SiegeRuleset).respawn_enabled = false

	c.observe_round(1)
	var hero := FakeUnit.new(0)
	hero.hp = 0
	c.handle_unit_eliminated(hero)
	assert_eq(c.respawn_queue().size(), 0, "with respawns off a death is never queued")
	_run_rounds_from(c, 2, 6)
	assert_eq((f["spawner"] as FakeSpawner).calls.size(), 0, "and nothing ever comes back")


func test_a_creep_is_never_queued_for_respawn() -> void:
	var f := _respawn_fixture()
	var c: SiegeController = f["controller"]

	c.observe_round(1)
	var creep := FakeUnit.new(0)
	CaptureBase.mark_creep(creep)
	creep.hp = 0
	c.handle_unit_eliminated(creep)
	assert_eq(c.respawn_queue().size(), 0,
		"a creep is replaced by the next wave, never by the respawn queue")


func test_a_side_with_no_base_cell_never_queues_a_respawn() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board)
	var rs := _make_ruleset()
	rs.creeps_per_lane = 0
	var map := _make_map()
	map.base_cells = {0: P0_BASE}   # player 1 has nowhere to come back to
	var c := _make_controller(map, rs, spawner, board)

	c.observe_round(1)
	var enemy := FakeUnit.new(1)
	enemy.hp = 0
	c.handle_unit_eliminated(enemy)
	assert_eq(c.respawn_queue().size(), 0, "no base cell means no respawn point, so no queue")


func test_a_respawn_that_cannot_be_placed_stays_queued() -> void:
	var f := _respawn_fixture()
	var c: SiegeController = f["controller"]
	# A spawner that refuses everything stands in for a base cell whose whole neighbourhood
	# is occupied (SpawnManager.spawn_and_adopt returns null there).
	c.set_spawner_override(_RefusingSpawner.new())

	c.observe_round(1)
	var hero := FakeUnit.new(0)
	hero.hp = 0
	c.handle_unit_eliminated(hero)
	_run_rounds_from(c, 2, 5)
	assert_eq(c.respawn_queue().size(), 1,
		"a unit that could not be placed keeps its slot rather than vanishing")


class _RefusingSpawner extends RefCounted:
	func spawn_and_adopt(_spawn_data, _player_id, _hint = 0):
		return null


func _run_rounds_from(c: SiegeController, first: int, last: int) -> void:
	for r in range(first, last + 1):
		c.observe_round(r)


# --- The save gate ------------------------------------------------------------

func test_siege_battles_are_excluded_from_save_and_quit() -> void:
	# The pure gate, exercised exactly as the arena exclusion is: everything else says yes.
	assert_true(BattleSaveManager.gate(true, false, false, true, true, true, false, false),
		"an ordinary solo battle in progress may be saved")
	assert_false(BattleSaveManager.gate(true, false, false, true, true, true, false, true),
		"a SIEGE battle may not -- its round clock, wave cadence, respawn queue and any "
		+ "capture in flight live in SiegeController and are in no snapshot")
	assert_true(BattleSaveManager.gate(true, false, false, true, true, true),
		"and the exclusion defaults off, so base-assault / campaign / challenge are untouched")
