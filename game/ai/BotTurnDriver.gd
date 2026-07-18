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
## Character-backed units ([method Unit.has_character]) PLAN through [BotController]
## / [BossController] and EXECUTE real moves via [Unit.perform_move] (which runs
## [MoveExecutor]) and the shared live [BoardAdapter] from [CombatServices]. All
## board/cell math goes through that adapter -- there is no private grid.
##
## Legacy units without a [CharacterResource] (and the defensive case where no
## board is loaded yet) fall back to the simple take_damage behaviour so the game
## stays playable during the data-driven migration.

## Seconds between AI unit actions.
@export var action_interval: float = 0.4

var _timer: Timer
var _busy: bool = false


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = maxf(0.05, action_interval)
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_tick)
	_timer.start()


func _tick() -> void:
	# _act() is synchronous and never awaits, so no earlier _tick() can still be on
	# the stack when the Timer fires again. If _busy is somehow still set here, a
	# previous _act() errored out before clearing it -- self-heal instead of wedging
	# the driver inert for the rest of the match. A stranded _busy is exactly what
	# would leave the AI player's turn permanently incomplete (the AI never acts, so
	# the turn never advances back to the human): the primary "AI inert" failure.
	if _busy:
		_busy = false
	act_one_ai_unit()


## Perform ONE AI action for the currently-active turn system (the Timer's entry
## point). Returns true if an AI unit acted; false (harmlessly) when it is not an
## AI turn. Public so tests can drive the AI a step at a time without the Timer.
func act_one_ai_unit() -> bool:
	if not TurnSystemManager or not TurnSystemManager.has_active_turn_system():
		return false
	return act_for_turn_system(TurnSystemManager.get_active_turn_system())


## Perform ONE AI action against a SPECIFIC turn system. This is the shared core
## used by BOTH Traditional (all units per player) and Speed First (one unit at a
## time): it acts the current active player's next actable unit whenever that
## player is AI, then lets the unit's completion signal advance the turn. Only the
## turn ORDER differs between systems -- the AI driving is identical. Directly
## callable (no autoload, no Timer) so headless tests can assert autonomy.
func act_for_turn_system(ts: TurnSystemBase) -> bool:
	if _busy:
		return false
	if ts == null or not ts.is_active:
		return false
	var player: Player = ts.get_current_active_player()
	if player == null or not player.is_ai:
		return false

	var unit := _next_actable_ai_unit(ts, player)
	if unit == null:
		return false

	_busy = true
	_act(unit)
	_busy = false
	return true


## First unit the AI player can still act with this turn.
func _next_actable_ai_unit(ts: TurnSystemBase, player: Player) -> Unit:
	for u in ts.get_active_units():
		if u and is_instance_valid(u) and u.get_owner_player() == player:
			return u
	return null


## Route the unit to the planning path (character-backed + live board) or to the
## take_damage fallback (legacy units, or no board loaded yet).
func _act(unit: Unit) -> void:
	var board := CombatServices.board()
	if board != null and unit.has_character():
		_act_character(unit, board)
	else:
		_act_fallback(unit, board)


# --- Character planning path -----------------------------------------------

## The configured AI difficulty from the shared game settings, defaulting to
## NORMAL when the settings singleton is unavailable (e.g. isolated tests).
func _ai_difficulty() -> int:
	var gs = get_node_or_null("/root/GameSettings")
	if gs != null and "ai_difficulty" in gs:
		return int(gs.ai_difficulty)
	return BotController.Difficulty.NORMAL



## Plan via [BotController]/[BossController] and execute a real move / step.
func _act_character(unit: Unit, board) -> void:
	var controller = BossController.new() if unit.is_boss() else BotController.new()
	controller.difficulty = _ai_difficulty()
	var decision = controller.decide(unit, unit.get_moveset(), board)
	if decision == null or decision.is_empty():
		_finish(unit, "wait")
		return

	match int(decision.get("action", BotController.ActionType.WAIT)):
		BotController.ActionType.MOVE:
			if not _execute_move_decision(unit, decision, board):
				_finish(unit, "wait")
		BotController.ActionType.STEP:
			_execute_step(unit, decision, controller, board)
		_:
			_finish(unit, "wait")


## Execute an attack/use-move decision (a chosen move + aim cell) through
## [Unit.perform_move] / [MoveExecutor]. Returns true if the move resolved
## successfully AND the unit's action was consumed (turn ended).
func _execute_move_decision(unit: Unit, decision: Dictionary, board) -> bool:
	var move = decision.get("move", null)
	if move == null:
		return false
	var aim_cell: Vector2i = decision.get("aim_cell", board.cell_of(unit))
	# BotController hands back the MoveResource; perform_move wants its slot index.
	var slot := _slot_of_move(unit, move)
	if slot < 0:
		return false
	var result: Dictionary = unit.perform_move(slot, aim_cell, board)
	if result != null and bool(result.get("success", false)):
		var mc := unit.get_moveset_controller()
		if mc != null and mc.has_method("on_used"):
			mc.on_used(move)
		unit.mark_action_completed("move")
		print("[BotAI] %s uses %s at %s" % [unit.get_display_name(), _move_name(move), str(aim_cell)])
		return true
	return false


## Execute a one-cell advance toward the nearest hostile. Validates the target
## cell is actually reachable under the unit's movement profile, moves via the
## shared adapter, then optionally attacks if a move is now in range.
func _execute_step(unit: Unit, decision: Dictionary, controller, board) -> void:
	var origin: Vector2i = board.cell_of(unit)
	var step_cell: Vector2i = decision.get("step_to", origin)
	if step_cell == origin:
		_finish(unit, "wait")
		return

	var profile = unit.get_movement_profile()
	if profile == null:
		# Without a movement profile we cannot validate reachability; do nothing
		# rather than teleport the unit onto a possibly-illegal cell.
		_finish(unit, "wait")
		return

	var reachable := MovementResolver.new().reachable_cells(origin, profile, board)
	if not reachable.has(step_cell):
		_finish(unit, "wait")
		return

	board.move_unit(unit, step_cell)
	unit.mark_moved()
	print("[BotAI] %s advances to %s" % [unit.get_display_name(), str(step_cell)])

	# Now in a new position: if a damaging move can reach an enemy, take it;
	# otherwise end the turn.
	var follow = controller.decide(unit, unit.get_moveset(), board)
	if follow != null and not follow.is_empty() \
			and int(follow.get("action", BotController.ActionType.WAIT)) == BotController.ActionType.MOVE:
		if _execute_move_decision(unit, follow, board):
			return
	_finish(unit, "move")


## Index of [param move] within the unit's moveset (what [Unit.perform_move]
## expects), or -1 if the move is not part of the unit's authored kit.
func _slot_of_move(unit: Unit, move) -> int:
	var moveset := unit.get_moveset()
	for i in range(moveset.size()):
		if moveset[i] == move:
			return i
	return -1


func _move_name(move) -> String:
	if move != null and "display_name" in move and String(move.display_name) != "":
		return String(move.display_name)
	return "move"


# --- Legacy take_damage fallback -------------------------------------------

## Simple attack/advance behaviour for units the move system does not back yet.
## Uses the shared [BoardAdapter] for cell math when a board is present; when no
## board is loaded (defensive) it degrades to a direct take_damage on the nearest
## hostile.
func _act_fallback(unit: Unit, board) -> void:
	var target := _nearest_hostile(unit)
	if not target:
		_finish(unit, "wait")
		return

	if board == null:
		# No live board -> no reliable cell math. Just apply the legacy attack so
		# AI units are not inert; movement is skipped in this degraded path.
		_fallback_attack(unit, target)
		_finish(unit, "attack")
		return

	var ucell: Vector2i = board.cell_of(unit)
	var tcell: Vector2i = board.cell_of(target)
	var dist := _cell_manhattan(ucell, tcell)
	var atk_range: int = maxi(1, _stat(unit, "range", 1))

	if dist <= atk_range:
		_fallback_attack(unit, target)
		_finish(unit, "attack")
	else:
		var move_range: int = maxi(1, _stat(unit, "movement", 3))
		var dest := _step_toward_cell(ucell, tcell, move_range)
		board.move_unit(unit, dest)
		print("[BotAI] %s moves toward %s" % [unit.get_display_name(), target.get_display_name()])
		_finish(unit, "move")


func _fallback_attack(unit: Unit, target: Unit) -> void:
	var dmg: int = _stat(unit, "attack", 10)
	if target.has_method("take_damage"):
		target.take_damage(dmg)
	print("[BotAI] %s attacks %s for %d" % [unit.get_display_name(), target.get_display_name(), dmg])


func _finish(unit: Unit, action: String) -> void:
	if unit.has_method("mark_action_completed"):
		unit.mark_action_completed(action)


## Nearest living unit owned by a non-AI (human) player, ranked by squared world
## distance (grid-independent, so it needs no adapter).
func _nearest_hostile(unit: Unit) -> Unit:
	if not TurnSystemManager or not TurnSystemManager.has_active_turn_system():
		return null
	var ts: TurnSystemBase = TurnSystemManager.get_active_turn_system()
	var best: Unit = null
	var best_dist: float = INF
	var upos: Vector3 = unit.position
	for u in ts.registered_units:
		if not u or not is_instance_valid(u) or u == unit:
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		var owner := u.get_owner_player()
		if owner == null or owner == unit.get_owner_player() or owner.is_ai:
			continue
		var d: float = upos.distance_squared_to(u.position)
		if d < best_dist:
			best_dist = d
			best = u
	return best


## Step from [param from] toward [param to] up to [param steps] cells, stopping one
## cell short (so the unit ends adjacent, ready to attack next turn).
func _step_toward_cell(from: Vector2i, to: Vector2i, steps: int) -> Vector2i:
	var cell := from
	var budget: int = mini(steps, maxi(0, _cell_manhattan(from, to) - 1))
	for _i in range(budget):
		if absi(to.x - cell.x) >= absi(to.y - cell.y) and cell.x != to.x:
			cell.x += signi(to.x - cell.x)
		elif cell.y != to.y:
			cell.y += signi(to.y - cell.y)
	return cell


func _cell_manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _stat(unit: Unit, stat_name: String, fallback: int) -> int:
	if unit.has_method("get_stat"):
		var v: int = unit.get_stat(stat_name)
		return v if v > 0 else fallback
	return fallback
