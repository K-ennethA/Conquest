extends GutTest

## Unit facing math (game/visuals/UnitFacing.gd) and the FacingController rules on
## a headless board of duck-typed mocks. See CONQUEST.md "Unit facing".

const S := Vector2i(0, 1)
const N := Vector2i(0, -1)
const E := Vector2i(1, 0)
const W := Vector2i(-1, 0)


class MockOwner extends RefCounted:
	var id: int = 0


class MockUnit extends Node3D:
	var owner_player = null
	var hp: int = 10
	var footprint: Vector2i = Vector2i.ONE
	var facing: Vector2i = Vector2i(0, 1)
	var turns: int = 0
	func is_alive() -> bool:
		return hp > 0
	func get_owner_player():
		return owner_player
	func get_footprint() -> Vector2i:
		return footprint
	func get_facing() -> Vector2i:
		return facing
	func set_facing(d: Vector2i, _t: float = -1.0) -> void:
		if d != Vector2i.ZERO:
			if d != facing:
				turns += 1
			facing = d


# --- cardinal ---------------------------------------------------------------

func test_cardinal_from_delta() -> void:
	assert_eq(UnitFacing.cardinal(Vector2(3, 1)), E)
	assert_eq(UnitFacing.cardinal(Vector2(-3, 2)), W)
	assert_eq(UnitFacing.cardinal(Vector2(1, 4)), S)
	assert_eq(UnitFacing.cardinal(Vector2(0, -1)), N)
	assert_eq(UnitFacing.cardinal(Vector2.ZERO), Vector2i.ZERO, "no delta -> keep current")


func test_cardinal_diagonal_tie_breaks() -> void:
	# Exact diagonal: row axis by default (reads best from the south camera) ...
	assert_eq(UnitFacing.cardinal(Vector2(2, -2)), N)
	# ... unless a preferred candidate is given (e.g. the current facing / enemy side).
	assert_eq(UnitFacing.cardinal(Vector2(2, -2), [E]), E)
	# A preference that is not one of the two candidates is ignored.
	assert_eq(UnitFacing.cardinal(Vector2(2, -2), [W]), N)


func test_cardinal_eight_way_option() -> void:
	assert_eq(UnitFacing.cardinal(Vector2(2, 2), [], true), Vector2i(1, 1))
	assert_eq(UnitFacing.cardinal(Vector2(5, 1), [], true), E)
	assert_false(UnitFacing.ALLOW_DIAGONAL, "4-way is the default look")


func test_yaw_turns_a_plus_z_model_to_the_facing() -> void:
	assert_almost_eq(UnitFacing.yaw_for(S), 0.0, 0.0001)
	assert_almost_eq(UnitFacing.yaw_for(E), PI / 2, 0.0001)
	assert_almost_eq(absf(UnitFacing.yaw_for(N)), PI, 0.0001)
	assert_almost_eq(UnitFacing.yaw_for(W), -PI / 2, 0.0001)
	# The rotated +Z axis really points along the facing.
	for d in [S, E, N, W]:
		var fwd := Basis(Vector3.UP, UnitFacing.yaw_for(d)) * Vector3(0, 0, 1)
		assert_almost_eq(fwd.x, float(d.x), 0.0001)
		assert_almost_eq(fwd.z, float(d.y), 0.0001)
	# The per-character correction is added on top.
	assert_almost_eq(UnitFacing.model_yaw(180.0, S), PI, 0.0001)


# --- footprint / vertical ----------------------------------------------------

func test_footprint_center() -> void:
	assert_eq(UnitFacing.center_of(Vector3i(3, 4, 0), Vector2i(2, 2)), Vector3(3.5, 4.5, 0))
	assert_eq(UnitFacing.center_of(Vector3i(3, 4, 1)), Vector3(3, 4, 1))


func test_boss_faces_from_its_footprint_center() -> void:
	# 2x2 boss anchored (2,2) covers (2..3, 2..3), center (2.5, 2.5): directions
	# are measured from that center, not the anchor corner.
	var boss := UnitFacing.center_of(Vector3i(2, 2, 0), Vector2i(2, 2))
	assert_eq(UnitFacing.rest_facing(boss, [Vector3(2, 5, 0)], N), S)
	# (5,0) is 3 east / 2 north of the ANCHOR (would be east) but an exact diagonal
	# from the center -> the row axis (north).
	assert_eq(UnitFacing.rest_facing(boss, [Vector3(5, 0, 0)], S), N)
	assert_eq(UnitFacing.rest_facing(UnitFacing.cell_center(Vector3i(2, 2, 0)), [Vector3(5, 0, 0)], S), E)


func test_same_column_keeps_current_facing() -> void:
	var me := Vector3(3, 3, 0)
	assert_eq(UnitFacing.toward(me, Vector3(3, 3, 1)), Vector2i.ZERO, "directly above")
	assert_eq(UnitFacing.rest_facing(me, [Vector3(3, 3, 1)], W), W)


func test_vertical_is_ignored_for_direction() -> void:
	# On the floor above but to the east: face east.
	assert_eq(UnitFacing.toward(Vector3(1, 1, 0), Vector3(4, 1, 2)), E)


# --- rest facing ---------------------------------------------------------------

func test_rest_faces_the_nearest_enemy() -> void:
	var me := Vector3(5, 5, 0)
	var enemies := [Vector3(5, 1, 0), Vector3(7, 5, 0), Vector3(0, 9, 0)]
	assert_eq(UnitFacing.rest_facing(me, enemies, S), E, "the (7,5) enemy is 2 away")


func test_rest_distance_counts_floors() -> void:
	var me := Vector3(5, 5, 0)
	# (5,3) on floor 2 = 2 + 2 = 4 away; (1,5) on the ground = 4 -> tie; the tie
	# faces their combined direction (-4, -2) = west.
	assert_eq(UnitFacing.rest_facing(me, [Vector3(5, 3, 2), Vector3(1, 5, 0)], S), W)
	# Move the high one a floor lower: now it alone is nearest (3) -> north.
	assert_eq(UnitFacing.rest_facing(me, [Vector3(5, 3, 1), Vector3(1, 5, 0)], S), N)


func test_rest_tie_breaks_toward_the_enemy_side() -> void:
	var me := Vector3(5, 5, 0)
	# Nearest enemy exactly diagonal (2 east, 2 north); the rest of the enemy army
	# sits far east -> face east (their side), not the default row axis.
	var enemies := [Vector3(7, 3, 0), Vector3(12, 5, 0), Vector3(12, 6, 0)]
	assert_eq(UnitFacing.rest_facing(me, enemies, S), E)
	# Army north instead -> north.
	enemies = [Vector3(7, 3, 0), Vector3(5, -3, 0), Vector3(6, -4, 0)]
	assert_eq(UnitFacing.rest_facing(me, enemies, S), N)


func test_rest_opposed_equidistant_enemies_use_the_centroid_then_current() -> void:
	var me := Vector3(5, 5, 0)
	# Two equally near enemies on opposite sides cancel -> the whole army's side.
	var enemies := [Vector3(3, 5, 0), Vector3(7, 5, 0), Vector3(9, 9, 0)]
	var d := UnitFacing.rest_facing(me, enemies, W)
	assert_true(d == E or d == S, "leans toward the far (9,9) enemy: %s" % d)
	# Perfectly symmetric -> keep whatever the unit faced (no churn).
	assert_eq(UnitFacing.rest_facing(me, [Vector3(3, 5, 0), Vector3(7, 5, 0)], N), N)


func test_rest_without_enemies_uses_team_forward_or_current() -> void:
	assert_eq(UnitFacing.rest_facing(Vector3(1, 1, 0), [], W, E), E)
	assert_eq(UnitFacing.rest_facing(Vector3(1, 1, 0), [], W), W)
	assert_eq(UnitFacing.team_forward(Vector2(5, 9), Vector2(5, 4.5)), N)
	assert_eq(UnitFacing.team_forward(Vector2(5, 4.5), Vector2(5, 4.5)), Vector2i.ZERO)


# --- FacingController on a mock board --------------------------------------------

func _board(units: Array) -> BoardAdapter:
	var grid := Grid.new()
	grid.size = Vector3(10, 0, 10)
	return BoardAdapter.new(grid, units)


func _unit(owner, cell: Vector3i) -> MockUnit:
	var u := MockUnit.new()
	autofree(u)
	u.owner_player = owner
	u.position = Cells.cell_to_world(cell)
	return u


func test_controller_rest_facing_per_team() -> void:
	var p0 := MockOwner.new()
	var p1 := MockOwner.new()
	var a := _unit(p0, Vector3i(1, 8, 0))
	var b := _unit(p0, Vector3i(6, 8, 0))
	var foe := _unit(p1, Vector3i(6, 2, 0))
	var board := _board([a, b, foe])
	var fc := FacingController.new()
	autofree(fc)
	var units := [a, b, foe]
	assert_eq(fc.rest_facing_for(a, units, board), N, "(6,2) is 5 east / 6 north -> north")
	assert_eq(fc.rest_facing_for(b, units, board), N)
	# The foe's nearest is b (6,8): straight south.
	assert_eq(fc.rest_facing_for(foe, units, board), S)
	# Allies are never looked at.
	var lonely := [a, b]
	var fw := fc.team_forwards(lonely, board)
	assert_eq(fc.rest_facing_for(a, lonely, board, fw), fw.values()[0], "no enemy -> team forward")


func test_controller_move_facing_attacker_and_targets() -> void:
	var p0 := MockOwner.new()
	var p1 := MockOwner.new()
	var caster := _unit(p0, Vector3i(4, 4, 0))
	var t1 := _unit(p1, Vector3i(4, 2, 0))
	var t2 := _unit(p1, Vector3i(5, 2, 0))
	var ally := _unit(p0, Vector3i(2, 4, 0))
	var board := _board([caster, t1, t2, ally])
	var fc := FacingController.new()
	autofree(fc)
	fc.face_for_move(caster, Vector3i(4, 4, 0), Vector3i(4, 2, 0), [t1, t2, ally], board)
	assert_eq(caster.facing, N, "caster turns to its aim")
	assert_eq(t1.facing, S, "target turns to the caster")
	assert_eq(t2.facing, S, "(5,2) -> (4,4): 1 west, 2 south -> south")
	assert_eq(ally.facing, E, "a buffed / healed ally turns to the caster too")


func test_controller_self_cast_keeps_facing() -> void:
	var p0 := MockOwner.new()
	var caster := _unit(p0, Vector3i(4, 4, 0))
	caster.facing = W
	var board := _board([caster])
	var fc := FacingController.new()
	autofree(fc)
	fc.face_for_move(caster, Vector3i(4, 4, 0), Vector3i(4, 4, 0), [], board)
	assert_eq(caster.facing, W)


func test_settle_only_turns_units_whose_target_changed() -> void:
	# settle_all reads the live CombatServices board; emulate with rest_facing_for
	# and count turns: calling it twice must not re-turn anybody.
	var p0 := MockOwner.new()
	var p1 := MockOwner.new()
	var a := _unit(p0, Vector3i(1, 1, 0))
	var foe := _unit(p1, Vector3i(1, 5, 0))
	var board := _board([a, foe])
	var fc := FacingController.new()
	autofree(fc)
	for i in 3:
		for u in [a, foe]:
			var want: Vector2i = fc.rest_facing_for(u, [a, foe], board)
			if want != u.get_facing():
				u.set_facing(want)
	assert_eq(a.facing, S)
	assert_eq(foe.facing, N)
	assert_eq(a.turns, 0, "already facing south: no turn")
	assert_eq(foe.turns, 1, "one turn, then stable")


func test_undo_restores_the_original_facing() -> void:
	# The staged-move contract (UnitActionsPanel): remember the facing before the
	# walk, the walk turns the unit, undo puts the remembered facing back.
	var u := _unit(MockOwner.new(), Vector3i(1, 1, 0))
	u.facing = W
	var saved := u.get_facing()
	u.set_facing(E)  # the walk
	u.set_facing(saved)  # the undo
	assert_eq(u.get_facing(), W)
## Pure-function tests for Unit's spawn-facing decision and world-direction yaw helper.
##
## Convention (see Unit.spawn_facing_yaw / facing_yaw_for_delta): the returned yaw is the
## WORLD-facing component, composed additively with the authored model_yaw_deg. 0 rad =
## world -Z (north / up-board / AWAY from the south-side camera); PI rad = world +Z
## (south / down-board / TOWARD the camera). The camera views the board from high Z (south),
## so a unit in the TOP/north half must turn to +Z to face the camera.

const EPS: float = 0.0001


# --- spawn_facing_yaw: half-of-board rule ------------------------------------

func test_top_half_faces_south_toward_camera():
	# Rows above the midline of a 9-row map (midline row = 4) are the top/north half.
	assert_almost_eq(Unit.spawn_facing_yaw(0, 9, []), PI, EPS, "row 0 -> face +Z (camera)")
	assert_almost_eq(Unit.spawn_facing_yaw(3, 9, []), PI, EPS, "row 3 (< 4) -> face +Z")


func test_bottom_half_faces_north_away_from_camera():
	assert_almost_eq(Unit.spawn_facing_yaw(8, 9, []), 0.0, EPS, "row 8 -> face -Z (back to camera)")
	assert_almost_eq(Unit.spawn_facing_yaw(5, 9, []), 0.0, EPS, "row 5 (> 4) -> face -Z")


func test_even_height_midline_is_fractional_no_exact_tie():
	# 8-row map: midline = 3.5. Row 3 is top half (< 3.5) -> PI; row 4 is bottom (> 3.5) -> 0.
	assert_almost_eq(Unit.spawn_facing_yaw(3, 8, []), PI, EPS, "row 3 of 8 -> top half")
	assert_almost_eq(Unit.spawn_facing_yaw(4, 8, []), 0.0, EPS, "row 4 of 8 -> bottom half")


# --- spawn_facing_yaw: dead-center midline tie-break -------------------------

func test_midline_tiebreak_uses_enemy_majority():
	# 9-row map: midline row = 4 (odd height -> an exact center row exists).
	assert_almost_eq(Unit.spawn_facing_yaw(4, 9, [6, 7, 8]), PI, EPS, "enemies below -> face +Z")
	assert_almost_eq(Unit.spawn_facing_yaw(4, 9, [0, 1, 2]), 0.0, EPS, "enemies above -> face -Z")


func test_midline_no_enemies_defaults_south():
	assert_almost_eq(Unit.spawn_facing_yaw(4, 9, []), PI, EPS, "no enemy hint -> face south/camera")


func test_midline_balanced_enemies_defaults_south():
	assert_almost_eq(Unit.spawn_facing_yaw(4, 9, [1, 7]), PI, EPS, "balanced enemies -> face south")


# --- facing_yaw_for_delta: cardinal directions -------------------------------

func test_facing_yaw_for_delta_cardinals():
	# rotate(-Z, yaw) = (-sin yaw, -cos yaw); solving gives atan2(-dx, -dz).
	# +Z compares by ANGULAR distance: atan2(-0.0, -1.0) returns -PI, which is the
	# same physical facing as +PI - either sign is correct.
	var south_yaw: float = Unit.facing_yaw_for_delta(0.0, 1.0)
	assert_almost_eq(absf(wrapf(south_yaw - PI, -PI, PI)), 0.0, EPS, "+Z (south) -> PI (mod 2PI)")
	assert_almost_eq(Unit.facing_yaw_for_delta(0.0, -1.0), 0.0, EPS, "-Z (north) -> 0")
	assert_almost_eq(Unit.facing_yaw_for_delta(1.0, 0.0), -PI / 2.0, EPS, "+X (east) -> -PI/2")
	assert_almost_eq(Unit.facing_yaw_for_delta(-1.0, 0.0), PI / 2.0, EPS, "-X (west) -> PI/2")


# --- ONE facing system: the yaw API is a view onto get_facing() ----------------
# Both branches built unit facing; the merge keeps the grid facing (get_facing /
# set_facing) as the single state and the yaw API (facing_yaw / set_facing_yaw /
# spawn_facing_yaw) as a view onto it in its original convention.

func test_yaw_view_maps_onto_grid_facings() -> void:
	assert_eq(Unit.facing_for_yaw(PI), S, "yaw PI (+Z) is south, toward the camera")
	assert_eq(Unit.facing_for_yaw(0.0), N, "yaw 0 (-Z) is north")
	assert_eq(Unit.facing_for_yaw(-PI / 2.0), E, "yaw -PI/2 is east")
	assert_eq(Unit.facing_for_yaw(PI / 2.0), W, "yaw PI/2 is west")


func test_spawner_yaw_sets_the_grid_facing() -> void:
	var u: Unit = autofree(Unit.new())
	u.facing_yaw = Unit.spawn_facing_yaw(0, 9, [])  # top half -> faces the camera
	assert_eq(u.get_facing(), S, "a top-half spawn faces south")
	u.facing_yaw = Unit.spawn_facing_yaw(8, 9, [])
	assert_eq(u.get_facing(), N, "a bottom-half spawn faces north")
	assert_almost_eq(u.facing_yaw, 0.0, EPS, "and reads back in the yaw convention")


func test_set_facing_and_set_facing_yaw_share_state() -> void:
	var u: Unit = autofree(Unit.new())
	u.set_facing(E, 0.0)
	assert_almost_eq(u.facing_yaw, -PI / 2.0, EPS, "the yaw view follows set_facing")
	u.set_facing_yaw(PI / 2.0)
	assert_eq(u.get_facing(), W, "and set_facing_yaw drives get_facing")
	u.face_direction(0.0, -3.0)
	assert_eq(u.get_facing(), N, "face_direction snaps a world delta to a facing")
