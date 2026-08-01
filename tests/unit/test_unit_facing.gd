extends GutTest

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
