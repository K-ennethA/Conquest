extends Node
class_name FacingController

## Fire Emblem-style unit ORIENTATION, centralised. Purely visual: it only calls
## [method Unit.set_facing] (which turns the CharacterModel child), never touches
## board / turn / net state, so every peer can run it freely (the net digest never
## reads facing). Created per battle by GameWorldManager. Rules: CONQUEST.md
## "Unit facing"; math: [UnitFacing].
##
## - REST facing (toward the nearest enemy, 4-way) is re-evaluated for every unit
##   when something that can change it happens -- a unit moved, died or spawned, a
##   turn started, the board loaded -- once all walks/lunges have finished, and a
##   unit only turns when its target direction actually changed (no churn).
## - ATTACK facing (GameEvents.move_aimed, every path incl. AI + network apply): the
##   caster turns to its aim, the units in the area turn to the caster; rest facing
##   resumes after [constant ATTACK_HOLD].
## - WALK facing (each step) lives in [UnitAnimator] (it owns the walk tween);
##   undoing a staged move restores the old facing (UnitActionsPanel).
## Selection / hover never re-face anybody.

## Seconds (battle-speed scaled) after the last walk before units settle.
const SETTLE_DELAY := 0.2
## Seconds (scaled) attacker and targets keep facing each other after a move.
const ATTACK_HOLD := 0.9

var _settle_pending: bool = false
var _settle_at_ms: int = 0


func _ready() -> void:
	name = "FacingController"
	var bus := get_node_or_null("/root/GameEvents")
	if bus != null:
		_connect(bus, &"unit_moved", _on_unit_moved)
		_connect(bus, &"unit_eliminated", _on_unit_eliminated)
		_connect(bus, &"turn_started", _on_turn_started)
		_connect(bus, &"unit_spawned", _on_unit_spawned)
		_connect(bus, &"move_aimed", _on_move_aimed)
	var pm := get_node_or_null("/root/PlayerManager")
	if pm != null:
		_connect(pm, &"player_turn_started", _on_turn_started)
	var services := get_node_or_null("/root/CombatServices")
	if services != null:
		_connect(services, &"board_ready", _on_board_ready)


func _on_unit_moved(_u = null, _from = null, _to = null) -> void:
	request_settle(SETTLE_DELAY)


func _on_unit_eliminated(_u = null, _killer = null) -> void:
	request_settle(SETTLE_DELAY)


func _on_turn_started(_who = null) -> void:
	request_settle(0.0)


func _on_board_ready() -> void:
	call_deferred("settle_all", true)


func _connect(obj: Object, sig: StringName, c: Callable) -> void:
	if obj.has_signal(sig) and not obj.is_connected(sig, c):
		obj.connect(sig, c)


## Schedule a rest-facing pass [param delay] (battle-speed scaled) seconds from now,
## or later if one is already scheduled further out. It runs once no unit is still
## walking / lunging.
func request_settle(delay: float) -> void:
	var at := Time.get_ticks_msec() + int(_scaled(delay) * 1000.0)
	_settle_at_ms = maxi(_settle_at_ms, at) if _settle_pending else at
	_settle_pending = true


func _process(_delta: float) -> void:
	if not _settle_pending or Time.get_ticks_msec() < _settle_at_ms:
		return
	var board = _board()
	if board == null:
		_settle_pending = false
		return
	var animator := get_node_or_null("/root/UnitAnimator")
	if animator != null and animator.has_method("is_moving"):
		for u in board.all_units():
			if is_instance_valid(u) and animator.is_moving(u):
				return  # wait for the walk / lunge to finish
	_settle_pending = false
	settle_all(false)


## Turn every live unit to its rest facing ([param instant] snaps, else a quick
## turn). Units already facing that way are left alone.
func settle_all(instant: bool = false) -> void:
	var board = _board()
	if board == null:
		return
	var units: Array = []
	for u in board.all_units():
		if u != null and is_instance_valid(u) and u.has_method("set_facing"):
			units.append(u)
	var forward := team_forwards(units, board)
	for u in units:
		var want := rest_facing_for(u, units, board, forward)
		if want != Vector2i.ZERO and want != u.get_facing():
			u.set_facing(want, 0.0 if instant else -1.0)
		elif instant:
			u.set_facing(u.get_facing(), 0.0)  # snap the model onto its facing


## [param unit]'s rest facing among [param units] (see UnitFacing.rest_facing).
## [param forward] maps an owner key to its team forward (team_forwards()).
func rest_facing_for(unit, units: Array, board, forward: Dictionary = {}) -> Vector2i:
	var me := UnitFacing.unit_center(unit, board)
	var enemies: Array = []
	for o in units:
		if o != unit and is_instance_valid(o) and _hostile(unit, o):
			enemies.append(UnitFacing.unit_center(o, board))
	var fallback: Vector2i = forward.get(_owner_key(unit), Vector2i.ZERO)
	return UnitFacing.rest_facing(me, enemies, unit.get_facing(), fallback)


## Owner key -> the team's default forward (from its centroid toward the board
## center) -- used when a unit has no enemy left to look at.
func team_forwards(units: Array, board) -> Dictionary:
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for u in units:
		var k = _owner_key(u)
		var c := UnitFacing.unit_center(u, board)
		sums[k] = sums.get(k, Vector2.ZERO) + Vector2(c.x, c.y)
		counts[k] = int(counts.get(k, 0)) + 1
	var center := _board_center(board)
	var out: Dictionary = {}
	for k in sums:
		out[k] = UnitFacing.team_forward(sums[k] / float(counts[k]), center)
	return out


func _on_unit_spawned(unit = null, _runtime = null) -> void:
	# Face the right way from the first frame; the board-wide pass follows.
	var board = _board()
	if board == null or unit == null or not is_instance_valid(unit) or not unit.has_method("set_facing"):
		return
	var units: Array = board.all_units()
	if not units.has(unit):
		return
	var want := rest_facing_for(unit, units, board, team_forwards(units, board))
	if want != Vector2i.ZERO:
		unit.set_facing(want, 0.0)
	request_settle(SETTLE_DELAY)


func _on_move_aimed(caster = null, _move = null, origin_cell = null, aim_cell = null, targets = null) -> void:
	var board = _board()
	if board == null or caster == null or not is_instance_valid(caster):
		return
	face_for_move(caster, origin_cell, aim_cell, targets if targets is Array else [], board)
	request_settle(ATTACK_HOLD)


## Attack facing: [param caster] (cast from [param origin_cell]) turns toward
## [param aim_cell]; each target turns toward the caster (its CURRENT spot -- a
## leap/teleport may have moved it), falling back to the aim center.
func face_for_move(caster, origin_cell, aim_cell, targets: Array, board) -> void:
	if not (aim_cell is Vector3i):
		return
	var fp: Vector2i = caster.get_footprint() if caster.has_method("get_footprint") else Vector2i.ONE
	var from: Vector3 = UnitFacing.center_of(origin_cell, fp) if origin_cell is Vector3i \
		else UnitFacing.unit_center(caster, board)
	var aim := UnitFacing.cell_center(aim_cell)
	if caster.has_method("set_facing"):
		caster.set_facing(UnitFacing.toward(from, aim, [caster.get_facing()]))
	var caster_now := UnitFacing.unit_center(caster, board)
	for t in targets:
		if t == null or t == caster or not is_instance_valid(t) or not t.has_method("set_facing"):
			continue
		var tc := UnitFacing.unit_center(t, board)
		var d := UnitFacing.toward(tc, caster_now, [t.get_facing()])
		if d == Vector2i.ZERO:
			d = UnitFacing.toward(tc, from, [t.get_facing()])
		t.set_facing(d)


func _hostile(a, b) -> bool:
	return _owner_key(a) != _owner_key(b)


func _owner_key(u):
	var p = u.get_owner_player() if u.has_method("get_owner_player") else u.get("owner_player")
	return p.get_instance_id() if p != null else 0


func _board():
	var services := get_node_or_null("/root/CombatServices") if is_inside_tree() else null
	if services != null and services.has_method("board"):
		return services.board()
	return null


func _board_center(board = null) -> Vector2:
	var g = board.get("_grid") if board != null else null
	if g == null and is_inside_tree():
		var services := get_node_or_null("/root/CombatServices")
		g = services.get("GRID") if services != null else null
	if g != null and "size" in g:
		return Vector2((g.size.x - 1) * 0.5, (g.size.z - 1) * 0.5)
	return Vector2.ZERO


func _scaled(seconds: float) -> float:
	var gs := get_node_or_null("/root/GameSettings") if is_inside_tree() else null
	if gs != null and gs.has_method("scaled_time"):
		return float(gs.scaled_time(seconds))
	return seconds
