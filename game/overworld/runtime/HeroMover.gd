class_name HeroMover
extends RefCounted

## FREE MOVEMENT for the hero -- the Sun/Moon read (artist directive 2026-10-04: "real world
## movement", not tile by tile). The hero walks at any angle at a continuous speed, eases in /
## out over a few frames, and slides along walls. Logic still lives in cells: the controller
## turns the hero's position into his cell every frame and fires the arrival (warps, triggers,
## trainers, wild creatures, the grass roll) the moment his centre crosses into a new one.
##
## Collision is a circle of [constant RADIUS] against every BLOCKED cell's square (impassable
## terrain, a blocking NPC / prop, a visible wild creature, off the map): the push-out keeps
## the circle outside the squares, so the hero's centre is always inside a walkable cell, and
## the velocity loses its into-the-wall part (pushing at a wall idles, gliding along it slides).
##
## Pure maths on value types (no nodes, no allocation per frame): phone-viable and testable
## headless ([method advance] with a Callable for the walkability rule).

## Body radius in metres: about the hero's shoulder half-width (a 2 m cell is a wide lane).
const RADIUS: float = 0.42
## Longest sub-step per collision pass, so a slow frame never tunnels through a cell edge.
const MAX_SUBSTEP: float = 0.2
## Below this speed (m/s) with no input the hero is standing still.
const REST_SPEED: float = 0.05
## Heading error (radians) under which a turn has finished.
const TURN_DONE: float = 0.01

## Ground speeds in m/s at full input (an analog stick scales them down).
var walk_speed: float = 2.0
var run_speed: float = 4.2
## Exponential rates (per second): speeding up, slowing down, and turning toward the input.
## 1 - exp(-rate x delta) per frame, so the feel is the same at 30 / 60 / 144 fps.
var accel_rate: float = 14.0
var decel_rate: float = 22.0
var turn_rate: float = 18.0

## Current world velocity (y always 0).
var velocity: Vector3 = Vector3.ZERO
## World heading of the body in radians (atan2(x, z): 0 = south / +Z). Turns toward
## [member target_heading], the last input direction -- and keeps turning after the input is
## released, so a quick tap turns the hero all the way round with barely a step.
var heading: float = 0.0
var target_heading: float = 0.0


## Take the free-movement knobs of a resolved feel ([method OverworldFeel.resolve]).
func apply_feel(feel: Dictionary) -> void:
	walk_speed = float(feel.get("walk_speed_mps", walk_speed))
	run_speed = float(feel.get("run_speed_mps", run_speed))
	accel_rate = float(feel.get("accel_rate", accel_rate))
	decel_rate = float(feel.get("decel_rate", decel_rate))
	turn_rate = float(feel.get("free_turn_rate", turn_rate))


## Stop dead (a script, a menu, a warp took over).
func stop() -> void:
	velocity = Vector3.ZERO
	target_heading = heading


func speed() -> float:
	return velocity.length()


func is_at_rest() -> bool:
	return velocity.length() < REST_SPEED


## At rest and done turning: nothing left to integrate until the next input.
func is_settled() -> bool:
	return is_at_rest() and absf(wrapf(target_heading - heading, -PI, PI)) < TURN_DONE


## Set the heading to face cardinal [param dir] (area boot, a scripted turn).
func face(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO:
		heading = atan2(float(dir.x), float(dir.y))
		target_heading = heading


## The cardinal facing nearest the heading (what Confirm uses, what a door / trainer reads).
func cardinal() -> Vector2i:
	var x: float = sin(heading)
	var z: float = cos(heading)
	if absf(x) > absf(z):
		return Vector2i(1 if x > 0.0 else -1, 0)
	return Vector2i(0, 1 if z > 0.0 else -1)


## One frame. [param wish]: the input direction on the ground (x = east, y = south), length
## 0..1 (an analog stick's tilt; keys are 0 or 1). [param blocked]: Callable(Vector3i) -> bool,
## true for a cell the hero may not overlap. Returns the new position (y kept from [param pos]).
func advance(pos: Vector3, wish: Vector2, running: bool, delta: float, blocked: Callable, floor_index: int = 0) -> Vector3:
	if delta <= 0.0:
		return pos
	var w: Vector2 = wish.limit_length(1.0)
	var top: float = run_speed if running else walk_speed
	var target := Vector3(w.x, 0.0, w.y) * top
	if w.length() > 0.01:
		target_heading = atan2(w.x, w.y)
	heading = lerp_angle(heading, target_heading, 1.0 - exp(-turn_rate * delta))
	if absf(wrapf(target_heading - heading, -PI, PI)) < TURN_DONE:
		heading = target_heading
	var rate: float = accel_rate if target.length() >= velocity.length() else decel_rate
	velocity = velocity.lerp(target, 1.0 - exp(-rate * delta))
	if target == Vector3.ZERO and velocity.length() < REST_SPEED:
		velocity = Vector3.ZERO
		return pos
	var move: Vector3 = velocity * delta
	var steps: int = maxi(1, ceili(move.length() / MAX_SUBSTEP))
	var p: Vector3 = pos
	for i in range(steps):
		p += move / float(steps)
		p = _resolve(p, blocked, floor_index)
	return p


## Push [param p] out of every blocked cell square round it (two passes settle a corner).
func _resolve(p: Vector3, blocked: Callable, floor_index: int) -> Vector3:
	var cs: float = Cells.CELL_SIZE
	for _pass in range(2):
		var cx: int = floori(p.x / cs)
		var cz: int = floori(p.z / cs)
		var pushed: bool = false
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var c := Vector3i(cx + dx, cz + dz, floor_index)
				if not bool(blocked.call(c)):
					continue
				var lo := Vector2(c.x * cs, c.y * cs)
				var hi := lo + Vector2(cs, cs)
				var q := Vector2(p.x, p.z)
				var near := Vector2(clampf(q.x, lo.x, hi.x), clampf(q.y, lo.y, hi.y))
				var d: Vector2 = q - near
				var dist: float = d.length()
				if dist >= RADIUS:
					continue
				var n: Vector2
				if dist > 1e-5:
					n = d / dist
				else:
					# Centre inside the square (only after a teleport): leave by the nearest side.
					var exits := [q.x - lo.x, hi.x - q.x, q.y - lo.y, hi.y - q.y]
					var k: int = exits.find(exits.min())
					n = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN][k]
					dist = -float(exits[k])
				var push: Vector2 = n * (RADIUS - dist)
				p.x += push.x
				p.z += push.y
				# Lose the into-the-wall part of the velocity: pushing at a wall idles.
				var into: float = velocity.x * n.x + velocity.z * n.y
				if into < 0.0:
					velocity.x -= n.x * into
					velocity.z -= n.y * into
				pushed = true
		if not pushed:
			break
	return p
