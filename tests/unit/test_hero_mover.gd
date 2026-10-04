extends GutTest

## HeroMover -- the hero's FREE MOVEMENT maths (the Sun/Moon feel): pace, ease in / out,
## turning, and the circle-vs-blocked-cell collision that keeps his centre in walkable cells
## and slides him along walls. Pure value maths against a Callable walkability rule.

const CS: float = Cells.CELL_SIZE
const DT: float = 1.0 / 60.0

## Blocked cells of the synthetic map (Vector3i -> true); everything else is open floor.
var _walls: Dictionary = {}


func before_each() -> void:
	_walls.clear()


func _blocked(c: Vector3i) -> bool:
	return _walls.has(c)


func _mover() -> HeroMover:
	var m := HeroMover.new()
	m.walk_speed = 1.8
	m.run_speed = 4.2
	return m


## Run [param seconds] of frames at [param dt] with a constant [param wish]; returns the end
## position, and appends every frame's position to [param trail] when given.
func _run(m: HeroMover, from: Vector3, wish: Vector2, seconds: float, dt: float = DT,
		running: bool = false, trail: Array = []) -> Vector3:
	var p: Vector3 = from
	var frames: int = roundi(seconds / dt)
	for i in range(frames):
		p = m.advance(p, wish, running, dt, _blocked)
		trail.append(p)
	return p


func _centre(c: Vector3i) -> Vector3:
	return Cells.cell_to_world(c)


func test_holding_reaches_walk_speed_and_holds_it() -> void:
	var m := _mover()
	_run(m, _centre(Vector3i(0, 0, 0)), Vector2.RIGHT, 0.5)
	assert_almost_eq(m.speed(), 1.8, 0.01, "a held direction reaches the walk speed within half a second")
	var trail: Array = []
	var start: Vector3 = _centre(Vector3i(0, 0, 0))
	var p: Vector3 = _run(m, start, Vector2.RIGHT, 1.0, DT, false, trail)
	assert_almost_eq(p.x - start.x, 1.8, 0.02, "and holds it: 1.8 m in a second, no per-cell pauses")
	for i in range(1, trail.size()):
		var step: float = (trail[i] as Vector3).x - (trail[i - 1] as Vector3).x
		assert_almost_eq(step, 1.8 * DT, 0.0005, "every frame advances the same distance")
		if absf(step - 1.8 * DT) > 0.0005:
			break


func test_running_is_faster_and_release_stops_quickly() -> void:
	var m := _mover()
	_run(m, Vector3.ZERO, Vector2.RIGHT, 0.6, DT, true)
	assert_almost_eq(m.speed(), 4.2, 0.02, "run speed")
	var stop_from: Vector3 = Vector3(10.0, 0.0, 1.0)
	var p: Vector3 = _run(m, stop_from, Vector2.ZERO, 0.4)
	assert_true(m.is_at_rest(), "released: at rest within 0.4 s")
	assert_lt(p.x - stop_from.x, 0.3, "and coasts only a few centimetres")


func test_the_ease_is_frame_rate_independent() -> void:
	var a := _mover()
	var b := _mover()
	var pa: Vector3 = _run(a, Vector3.ZERO, Vector2.RIGHT, 1.0, 1.0 / 30.0)
	var pb: Vector3 = _run(b, Vector3.ZERO, Vector2.RIGHT, 1.0, 1.0 / 144.0)
	assert_almost_eq(pa.x, pb.x, 0.05, "30 fps and 144 fps cover the same ground")


func test_diagonals_and_analog_tilt() -> void:
	var m := _mover()
	var p: Vector3 = _run(m, Vector3.ZERO, Vector2(1, -1), 1.0)
	assert_almost_eq(m.speed(), 1.8, 0.01, "a key diagonal is not faster than a straight walk")
	assert_almost_eq(p.x, -p.z, 0.001, "and goes at 45 degrees")
	var half := _mover()
	_run(half, Vector3.ZERO, Vector2(0.5, 0.0), 1.0)
	assert_almost_eq(half.speed(), 0.9, 0.01, "half a stick's tilt walks at half speed")


func test_heading_follows_the_input_and_reads_as_a_cardinal() -> void:
	var m := _mover()
	m.face(Vector2i(0, 1))
	assert_eq(m.cardinal(), Vector2i(0, 1), "south")
	_run(m, Vector3.ZERO, Vector2.LEFT, 0.5)
	assert_almost_eq(wrapf(m.heading - atan2(-1.0, 0.0), -PI, PI), 0.0, 0.01, "turned to the input")
	assert_eq(m.cardinal(), Vector2i(-1, 0), "west")
	_run(m, Vector3.ZERO, Vector2(0.9, -0.3), 0.5)
	assert_eq(m.cardinal(), Vector2i(1, 0), "a shallow up-right angle faces east")
	_run(m, Vector3.ZERO, Vector2(0.3, -0.9), 0.5)
	assert_eq(m.cardinal(), Vector2i(0, -1), "a steep one faces north")


func test_a_wall_stops_him_at_his_radius_and_he_idles_against_it() -> void:
	_walls[Vector3i(2, 0, 0)] = true
	var m := _mover()
	var p: Vector3 = _run(m, _centre(Vector3i(0, 0, 0)), Vector2.RIGHT, 3.0)
	assert_almost_eq(p.x, 2.0 * CS - HeroMover.RADIUS, 0.001, "stops with his body against the wall")
	assert_true(m.is_at_rest(), "pushing at a wall is standing still (the walk clip settles)")


func test_a_diagonal_into_a_wall_slides_along_it() -> void:
	for x in range(-3, 6):
		_walls[Vector3i(x, -1, 0)] = true
	var m := _mover()
	var start: Vector3 = _centre(Vector3i(0, 0, 0))
	var p: Vector3 = _run(m, start, Vector2(1, -1), 2.0)
	assert_almost_eq(p.z, 0.0 + HeroMover.RADIUS, 0.001, "held against the north wall")
	assert_gt(p.x - start.x, 1.5, "while still sliding east along it")


func test_a_corner_never_traps_or_leaks() -> void:
	# A 1-cell doorway in a wall: approaching off-centre, he squeezes through.
	for x in range(-3, 6):
		if x != 1:
			_walls[Vector3i(x, -1, 0)] = true
	var m := _mover()
	var start := Vector3(1.0 * CS + 0.2, 0.0, 1.0)
	var p: Vector3 = _run(m, start, Vector2.UP, 2.0)
	assert_lt(p.z, -CS * 0.5, "an push that clips the corner still rounds it into the 1-cell gap")


func test_his_centre_never_enters_a_blocked_cell() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(30):
		var c := Vector3i(rng.randi_range(-4, 4), rng.randi_range(-4, 4), 0)
		if c != Vector3i.ZERO:
			_walls[c] = true
	var m := _mover()
	var p: Vector3 = _centre(Vector3i.ZERO)
	var leaks: Array = []
	for frame in range(1200):
		var ang: float = float(frame / 40) * 1.7
		var wish := Vector2(cos(ang), sin(ang))
		p = m.advance(p, wish, frame % 3 == 0, DT if frame % 7 else 0.1, _blocked)
		var cell := Vector3i(floori(p.x / CS), floori(p.z / CS), 0)
		if _walls.has(cell):
			leaks.append("frame %d at %s in %s" % [frame, p, cell])
	assert_eq(leaks, [], "random walking (slow frames included) never puts his centre in a wall")
