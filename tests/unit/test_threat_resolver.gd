extends GutTest

## ThreatResolver (danger zone / attack fringe) and MovementResolver's
## walk-through-allies rule. Headless: a BoardAdapter over mock units on a plain
## Grid (flat, cost-1 terrain), plus the multi-floor bridge fixture for floors.

const BRIDGE_MAP := "res://game/maps/resources/test_bridge_map.tres"


class MockOwner extends RefCounted:
	var id: int = 0


class MockUnit extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var owner_player = null
	var hp: int = 10
	var moves: Array[MoveResource] = []
	var profile: MovementProfile = null
	var moved: bool = false
	var controller = null
	func is_alive() -> bool:
		return hp > 0
	func get_moveset() -> Array[MoveResource]:
		return moves
	func get_movement_profile():
		return profile
	func get_moveset_controller():
		return controller
	func can_move() -> bool:
		return not moved


var grid: Grid
var p0: MockOwner
var p1: MockOwner


func before_each() -> void:
	grid = Grid.new()
	grid.size = Vector3(10, 0, 10)
	p0 = MockOwner.new()
	p1 = MockOwner.new()
	p1.id = 1


func _unit(cell: Vector3i, owner, move_range: int, moves: Array = []) -> MockUnit:
	var u := MockUnit.new()
	u.position = Cells.cell_to_world(cell) + Vector3(0, 0.1, 0)
	u.owner_player = owner
	u.profile = MovementProfile.create(&"t", "t", CombatTypes.MovementKind.GROUND, move_range, MovementProfile.Shape.ORTHOGONAL)
	for m in moves:
		u.moves.append(m)
	return u


func _attack(min_r: int, max_r: int, kind := CombatTypes.TargetKind.ENEMY, damage := true) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = StringName("atk_%d_%d_%d" % [min_r, max_r, kind])
	var p := TargetingPattern.new()
	p.target_kind = kind
	p.min_range = min_r
	p.max_range = max_r
	m.targeting = p
	if damage:
		var d := DamageEffect.new()
		d.power = 5
		m.effects = [d]
	else:
		m.effects = [HealEffect.new()]
	return m


func _board(units: Array) -> BoardAdapter:
	return BoardAdapter.new(grid, units)


# --- offensive_moves --------------------------------------------------------------

func test_offensive_moves_skip_heals_and_self_moves() -> void:
	var strike := _attack(1, 1)
	var heal := _attack(1, 2, CombatTypes.TargetKind.ALLY, false)
	var buff := _attack(0, 0, CombatTypes.TargetKind.SELF)
	var u := _unit(Vector3i(0, 0, 0), p0, 3, [strike, heal, buff])
	var got := ThreatResolver.offensive_moves(u)
	assert_eq(got.size(), 1)
	assert_eq(got[0], strike)


func test_offensive_moves_skip_exhausted_and_long_cooldowns() -> void:
	var strike := _attack(1, 1)
	var nuke := _attack(1, 3)
	nuke.cooldown = 3
	var u := _unit(Vector3i(0, 0, 0), p0, 3, [strike, nuke])
	var ctl := MovesetController.new()
	ctl.on_used(nuke)  # 3 turns of cooldown left
	u.controller = ctl
	assert_eq(ThreatResolver.offensive_moves(u), [strike] as Array[MoveResource])
	ctl.tick_cooldowns()
	ctl.tick_cooldowns()  # 1 left -> ready again next turn
	assert_eq(ThreatResolver.offensive_moves(u).size(), 2)
	autofree(ctl)


# --- unit_threat ------------------------------------------------------------------

func test_melee_threat_is_move_range_plus_one() -> void:
	var u := _unit(Vector3i(5, 5, 0), p1, 2, [_attack(1, 1)])
	var t := ThreatResolver.unit_threat(u, _board([u]))
	# Stand diamond radius 2 + reach 1 = diamond radius 3 (25 cells incl. centre).
	assert_eq(t["attack"].size(), 25)
	assert_true(t["attack"].has(Vector3i(5, 8, 0)))
	assert_false(t["attack"].has(Vector3i(5, 9, 0)))
	assert_eq(t["move"][0], Vector3i(5, 5, 0), "own cell is the first stand cell")
	assert_eq(t["move"].size(), 13, "diamond radius 2")
	assert_eq(t["fringe"].size(), 12, "the ring at distance 3")
	for c in t["fringe"]:
		assert_eq(Cells.distance(c, Vector3i(5, 5, 0)), 3)


func test_ranged_min_range_still_covered_from_other_cells() -> void:
	# Range 2..2 bow, no movement: the cells at distance 1 are NOT threatened.
	var u := _unit(Vector3i(5, 5, 0), p1, 0, [_attack(2, 2)])
	var t := ThreatResolver.unit_threat(u, _board([u]))
	assert_false(t["attack"].has(Vector3i(5, 6, 0)), "dead zone up close")
	assert_true(t["attack"].has(Vector3i(5, 7, 0)))
	assert_true(t["attack"].has(Vector3i(6, 6, 0)))
	# With 1 move it can step back and cover the adjacent cells.
	var u2 := _unit(Vector3i(5, 5, 0), p1, 1, [_attack(2, 2)])
	var t2 := ThreatResolver.unit_threat(u2, _board([u2]))
	assert_true(t2["attack"].has(Vector3i(5, 6, 0)))


func test_threat_respects_blockers_and_bounds() -> void:
	# An enemy wall of player units boxes the attacker in a corner.
	var att := _unit(Vector3i(0, 0, 0), p1, 3, [_attack(1, 1)])
	var b1 := _unit(Vector3i(1, 0, 0), p0, 0)
	var b2 := _unit(Vector3i(0, 1, 0), p0, 0)
	var t := ThreatResolver.unit_threat(att, _board([att, b1, b2]))
	assert_eq(t["move"], [Vector3i(0, 0, 0)] as Array[Vector3i], "cannot move through enemies")
	assert_eq(t["attack"].size(), 2, "only the two adjacent blockers are in reach")
	for c in t["attack"]:
		assert_true(c.x >= 0 and c.y >= 0, "never off the board")


func test_respect_turn_state_uses_current_cell_only() -> void:
	var u := _unit(Vector3i(5, 5, 0), p0, 3, [_attack(1, 1)])
	u.moved = true
	var t := ThreatResolver.unit_threat(u, _board([u]), true)
	assert_eq(t["move"].size(), 1)
	assert_eq(t["attack"].size(), 4)
	var fresh := ThreatResolver.unit_threat(u, _board([u]), false)
	assert_gt(fresh["attack"].size(), 4, "danger zone assumes a fresh turn")


func test_no_offensive_moves_means_no_threat() -> void:
	var u := _unit(Vector3i(5, 5, 0), p1, 3, [_attack(1, 2, CombatTypes.TargetKind.ALLY, false)])
	var t := ThreatResolver.unit_threat(u, _board([u]))
	assert_eq(t["attack"].size(), 0)
	assert_gt(t["move"].size(), 1)


func test_area_move_threatens_its_footprint() -> void:
	var blast := _attack(2, 2, CombatTypes.TargetKind.TILE)
	blast.targeting.area_shape = CombatTypes.AreaShape.DIAMOND
	blast.targeting.area_size = 1
	var u := _unit(Vector3i(5, 5, 0), p1, 0, [blast])
	var t := ThreatResolver.unit_threat(u, _board([u]))
	assert_true(t["attack"].has(Vector3i(5, 8, 0)), "footprint reaches one past the aim")
	assert_true(t["attack"].has(Vector3i(5, 6, 0)), "and one short of it")
	assert_false(t["attack"].has(Vector3i(5, 5, 0)), "caster tile excluded")


func test_combined_threat_is_union() -> void:
	var a := _unit(Vector3i(1, 1, 0), p1, 0, [_attack(1, 1)])
	var b := _unit(Vector3i(8, 8, 0), p1, 0, [_attack(1, 1)])
	var board := _board([a, b])
	var all := ThreatResolver.combined_threat([a, b], board)
	assert_eq(all.size(), 8)
	assert_true(all.has(Vector3i(1, 2, 0)))
	assert_true(all.has(Vector3i(8, 7, 0)))
	var sorted := all.duplicate()
	sorted.sort_custom(Cells.less)
	assert_eq(all, sorted, "deterministic order")


func test_hostile_units_filter() -> void:
	var a := _unit(Vector3i(1, 1, 0), p1, 0)
	var b := _unit(Vector3i(2, 2, 0), p0, 0)
	var dead := _unit(Vector3i(3, 3, 0), p1, 0)
	dead.hp = 0
	var board := _board([a, b, dead])
	var hostile := ThreatResolver.hostile_units(board, func(u): return u.owner_player == p1)
	assert_eq(hostile, [a])


# --- Multi-floor ------------------------------------------------------------------

func test_melee_threat_climbs_stairs_but_not_straight_up() -> void:
	var g := Grid.new()
	g.size = Vector3(9, 0, 7)
	grid = g
	var u := _unit(Vector3i(0, 1, 0), p1, 1, [_attack(1, 1)])
	var board := BoardAdapter.new(g, [u]).configure_from_map(load(BRIDGE_MAP))
	var t := ThreatResolver.unit_threat(u, board)
	# Moves to the stair foot (1,1,0); the melee reaches the stair top across the link.
	assert_true(t["attack"].has(Vector3i(2, 1, 1)), "stair top is in melee reach from the foot")
	assert_false(t["attack"].has(Vector3i(1, 1, 1)), "air above the foot is never a target")


# --- Walk through allies ------------------------------------------------------------

func test_ground_walks_through_ally_but_not_enemy() -> void:
	var mover := _unit(Vector3i(0, 0, 0), p0, 3)
	var ally := _unit(Vector3i(1, 0, 0), p0, 0)
	var g := Grid.new()
	g.size = Vector3(6, 0, 1)
	grid = g
	var board := BoardAdapter.new(g, [mover, ally])
	var r := MovementResolver.new()
	var cells := r.reachable_cells(Vector3i(0, 0, 0), mover.profile, board, mover)
	assert_false(cells.has(Vector3i(1, 0, 0)), "may not STOP on the ally")
	assert_true(cells.has(Vector3i(2, 0, 0)), "walks through the ally")
	assert_true(cells.has(Vector3i(3, 0, 0)))
	assert_eq(r.path_to(Vector3i(2, 0, 0)),
		[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)] as Array[Vector3i],
		"the path goes through the ally's cell")

	var enemy := _unit(Vector3i(1, 0, 0), p1, 0)
	var board2 := BoardAdapter.new(g, [mover, enemy])
	var cells2 := MovementResolver.new().reachable_cells(Vector3i(0, 0, 0), mover.profile, board2, mover)
	assert_eq(cells2.size(), 0, "an enemy still blocks the corridor")


func test_no_mover_keeps_old_blocking_rule() -> void:
	var mover := _unit(Vector3i(0, 0, 0), p0, 3)
	var ally := _unit(Vector3i(1, 0, 0), p0, 0)
	var g := Grid.new()
	g.size = Vector3(6, 0, 1)
	var board := BoardAdapter.new(g, [mover, ally])
	var cells := MovementResolver.new().reachable_cells(Vector3i(0, 0, 0), mover.profile, board)
	assert_eq(cells.size(), 0, "without a mover, every occupant blocks")


func test_flyer_passes_allies_too() -> void:
	var g := Grid.new()
	g.size = Vector3(6, 0, 1)
	var mover := _unit(Vector3i(0, 0, 0), p0, 3)
	mover.profile = MovementProfile.create(&"f", "f", CombatTypes.MovementKind.FLYING, 3, MovementProfile.Shape.ORTHOGONAL)
	var ally := _unit(Vector3i(1, 0, 0), p0, 0)
	var board := BoardAdapter.new(g, [mover, ally])
	assert_true(MovementResolver.new().reachable_cells(Vector3i(0, 0, 0), mover.profile, board, mover).has(Vector3i(2, 0, 0)))


# --- Fast path == reference, snapshot ------------------------------------------------

func test_offset_stamp_matches_per_aim_reference() -> void:
	var arc := _attack(1, 1, CombatTypes.TargetKind.ENEMY)
	arc.targeting.area_shape = CombatTypes.AreaShape.ARC
	var line := _attack(1, 2, CombatTypes.TargetKind.ENEMY)
	line.targeting.area_shape = CombatTypes.AreaShape.LINE
	line.targeting.area_size = 2
	var bow := _attack(2, 3)
	var u := _unit(Vector3i(4, 4, 0), p1, 3, [arc, line, bow])
	var blocker := _unit(Vector3i(5, 4, 0), p0, 0)
	var board := _board([u, blocker])
	var stands := ThreatResolver.stand_cells(u, board)
	var fast := ThreatResolver.attack_set_from(stands, u, board)
	var ref := {}
	for s in stands:
		for m in [arc, line, bow]:
			ThreatResolver.move_threat_from(s, m, u, board, ref)
	assert_eq(fast.size(), ref.size(), "same cell count as the per-aim reference")
	for c in ref:
		assert_true(fast.has(c), "fast path covers %s" % str(c))


func test_board_snapshot_indexes_occupancy() -> void:
	var a := _unit(Vector3i(1, 1, 0), p0, 2)
	var b := _unit(Vector3i(2, 1, 0), p1, 2)
	var board := _board([a, b])
	var snap = BoardSnapshot.of(board)
	assert_true(snap is BoardSnapshot)
	assert_eq(BoardSnapshot.of(snap), snap, "never double-wrapped")
	assert_true(snap.is_occupied(Vector3i(2, 1, 0)))
	assert_false(snap.is_occupied(Vector3i(3, 1, 0)))
	assert_eq(snap.units_at(Vector3i(1, 1, 0)), [a])
	assert_true(snap.are_enemies(a, b))
	assert_false(snap.can_fit(a, Vector3i(2, 1, 0)))
	assert_true(snap.can_fit(a, Vector3i(1, 1, 0)), "its own cell fits")
	assert_eq(snap.cols, 10)
	var plain := MovementResolver.new().reachable_cells(Vector3i(1, 1, 0), a.profile, board, a)
	var fast := MovementResolver.new().reachable_cells(Vector3i(1, 1, 0), a.profile, snap, a)
	assert_eq(fast, plain, "same flood through the snapshot")
