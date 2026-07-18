extends Node
class_name BotTurnDriver

## Drives turns for AI-controlled players in single-player.
##
## Polls the active turn system each tick; when the current player is AI
## ([member Player.is_ai]) it makes ONE of that player's actable units act, then
## lets the turn system advance. Acting one unit per tick (rather than looping in
## a signal handler) keeps it re-entrancy-safe across both the Traditional
## (all units per player) and Speed (one unit at a time) systems, and paces the
## AI visibly.
##
## This uses the live unit action API (take_damage + mark_action_completed) so it
## works with the current game. When units migrate to the data-driven move system
## (CharacterResource + MoveExecutor), swap [method _act] to plan via BotController.

## Seconds between AI unit actions.
@export var action_interval: float = 0.4

var _grid: Grid
var _timer: Timer
var _busy: bool = false


func _ready() -> void:
	_grid = Grid.new()
	# Match MapLoader's world placement (cells are 2 units wide).
	_grid.cell_size = Vector3(2, 0, 2)
	_grid.size = Vector3(9999, 0, 9999)

	_timer = Timer.new()
	_timer.wait_time = maxf(0.05, action_interval)
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_tick)
	_timer.start()


func _tick() -> void:
	if _busy:
		return
	if not TurnSystemManager or not TurnSystemManager.has_active_turn_system():
		return
	var ts: TurnSystemBase = TurnSystemManager.get_active_turn_system()
	if not ts.is_active:
		return
	var player: Player = ts.get_current_active_player()
	if not player or not player.is_ai:
		return

	var unit := _next_actable_ai_unit(ts, player)
	if not unit:
		return

	_busy = true
	_act(unit)
	_busy = false


## First unit the AI player can still act with this turn.
func _next_actable_ai_unit(ts: TurnSystemBase, player: Player) -> Unit:
	for u in ts.get_active_units():
		if u and is_instance_valid(u) and u.get_owner_player() == player:
			return u
	return null


func _act(unit: Unit) -> void:
	var target := _nearest_enemy(unit)
	if not target:
		_finish(unit, "wait")
		return

	var ucell := _cell(unit)
	var tcell := _cell(target)
	var dist: int = _manhattan(ucell, tcell)
	var atk_range: int = maxi(1, _stat(unit, "range", 1))

	if dist <= atk_range:
		var dmg: int = _stat(unit, "attack", 10)
		if target.has_method("take_damage"):
			target.take_damage(dmg)
		print("[BotAI] %s attacks %s for %d" % [unit.get_display_name(), target.get_display_name(), dmg])
		_finish(unit, "attack")
	else:
		var move_range: int = maxi(1, _stat(unit, "movement", 3))
		var dest := _step_toward(ucell, tcell, move_range)
		var world := _grid.calculate_map_position(dest)
		world.y = unit.position.y  # keep unit's hover height
		unit.position = world
		print("[BotAI] %s moves toward %s" % [unit.get_display_name(), target.get_display_name()])
		_finish(unit, "move")


func _finish(unit: Unit, action: String) -> void:
	if unit.has_method("mark_action_completed"):
		unit.mark_action_completed(action)


## Nearest living unit owned by a non-AI (human) player.
func _nearest_enemy(unit: Unit) -> Unit:
	if not TurnSystemManager or not TurnSystemManager.has_active_turn_system():
		return null
	var ts: TurnSystemBase = TurnSystemManager.get_active_turn_system()
	var best: Unit = null
	var best_dist: int = 1 << 30
	var ucell := _cell(unit)
	for u in ts.registered_units:
		if not u or not is_instance_valid(u) or u == unit:
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		var owner := u.get_owner_player()
		if owner == null or owner == unit.get_owner_player() or owner.is_ai:
			continue
		var d := _manhattan(ucell, _cell(u))
		if d < best_dist:
			best_dist = d
			best = u
	return best


## Step from [param from] toward [param to] up to [param steps] cells, stopping one
## cell short (so the unit ends adjacent, ready to attack next turn).
func _step_toward(from: Vector3, to: Vector3, steps: int) -> Vector3:
	var cell := from
	var budget: int = mini(steps, maxi(0, _manhattan(from, to) - 1))
	for _i in range(budget):
		if absf(to.x - cell.x) >= absf(to.z - cell.z) and cell.x != to.x:
			cell.x += signf(to.x - cell.x)
		elif cell.z != to.z:
			cell.z += signf(to.z - cell.z)
	return cell


func _cell(unit: Node3D) -> Vector3:
	return _grid.calculate_grid_coordinates(unit.position)


func _manhattan(a: Vector3, b: Vector3) -> int:
	return int(absf(a.x - b.x) + absf(a.z - b.z))


func _stat(unit: Unit, stat_name: String, fallback: int) -> int:
	if unit.has_method("get_stat"):
		var v: int = unit.get_stat(stat_name)
		return v if v > 0 else fallback
	return fallback
