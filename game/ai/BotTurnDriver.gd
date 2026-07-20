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

## When true, log extra diagnostics (e.g. "AI turn but no actable unit"). Off by
## default so a normal match only prints the concise one-line-per-action summary
## the execute paths emit.
@export var verbose: bool = false

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
		# STUN STALL GUARD. A stunned unit is skipped by the turn system but stays in
		# the turn order (that is what lets its statuses tick and the stun expire).
		# Under Speed First that unit is still `current_acting_unit`, so with nothing
		# actable the AI would sit here forever and the match would wedge -- the
		# human's End Turn button has no AI equivalent. Advance past it explicitly.
		# Deliberately narrow: it fires only when a stun is actually the cause, and
		# advancing always makes progress (the next unit / player takes over), so it
		# cannot loop.
		if _has_stun_skipped_unit(ts, player):
			if verbose:
				print("[BotAI] %s's units are stunned this turn -- advancing past the skip"
					% player.get_display_name())
			ts.advance_turn()
			return true
		# Rare once the AI acts every unit; only surface it when diagnosing.
		if verbose:
			print("[BotAI] %s's turn but no actable unit (active_units=%d)"
				% [player.get_display_name(), ts.get_active_units().size()])
		return false

	_busy = true
	_act(unit)
	_busy = false
	return true


## First unit the AI player can still act with this turn.
##
## get_active_units() already filters stunned units out (both turn systems check
## is_turn_skipped in can_unit_act), but the check is repeated here explicitly: this
## is the one place that decides what the AI touches, and a stunned unit reaching
## the action path would act during a turn it is supposed to be skipping.
func _next_actable_ai_unit(ts: TurnSystemBase, player: Player) -> Unit:
	for u in ts.get_active_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.get_owner_player() != player:
			continue
		if ts.has_method("is_turn_skipped") and ts.is_turn_skipped(u):
			continue
		return u
	return null


## True if any of [param player]'s registered units is having its turn skipped by a
## stun right now -- i.e. "there is nothing to act BECAUSE of a stun".
func _has_stun_skipped_unit(ts: TurnSystemBase, player: Player) -> bool:
	if ts == null or player == null or not ts.has_method("is_turn_skipped"):
		return false
	for u in ts.registered_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.get_owner_player() == player and ts.is_turn_skipped(u):
			return true
	return false


## Relocate a unit AND announce it, mirroring the player's movement contract.
##
## [BoardAdapter.move_unit] deliberately does not emit [signal GameEvents.unit_moved]:
## [UnitActionsPanel] calls it and emits separately, so emitting inside the shared
## primitive would fire every consumer TWICE for the player (double trap damage,
## double ON_MOVE ability, double glide) and would even fire on a tentative-move
## REVERT, which is not a move at all.
##
## The AI moved units through the bare primitive, so nothing downstream ever heard
## about it -- enemy units walked over vine traps for free, their ON_MOVE abilities
## never fired, and terrain enter/exit never ran for them. Emitting HERE keeps the
## player and AI paths symmetric without touching the primitive. Grid coords match
## the legacy contract: Vector3(col, 0, row).
func _relocate(unit, board, from_cell: Vector2i, to_cell: Vector2i) -> void:
	board.move_unit(unit, to_cell)
	if GameEvents:
		GameEvents.unit_moved.emit(
			unit,
			Vector3(from_cell.x, 0, from_cell.y),
			Vector3(to_cell.x, 0, to_cell.y))


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



## Plan via [BotController]/[BossController] using the unit's FULL reachable cell
## set, then execute a move-then-attack or a full advance.
func _act_character(unit: Unit, board) -> void:
	var controller = BossController.new() if unit.is_boss() else BotController.new()
	controller.difficulty = _ai_difficulty()

	var origin: Vector2i = board.cell_of(unit)
	# Cells the unit can actually reach this turn (movement profile + terrain +
	# blockers + occupancy), via the live board. The planner walks up to an enemy
	# and strikes the same turn instead of creeping one cell.
	var reachable := _reachable_cells(unit, origin, board)
	var decision = controller.plan(unit, unit.get_moveset(), board, reachable)
	if decision == null or decision.is_empty():
		_finish(unit, "wait")
		return

	match int(decision.get("action", BotController.ActionType.WAIT)):
		BotController.ActionType.MOVE:
			_execute_plan_attack(unit, decision, board)
		BotController.ActionType.STEP:
			_execute_plan_advance(unit, decision, board)
		_:
			if verbose:
				print("[BotAI] %s waits (%s)" % [unit.get_display_name(), str(decision.get("reason", ""))])
			_finish(unit, "wait")


## Cells [param unit] can reach this turn under its movement profile, via the live
## board. Empty when the unit has no profile -- planning then considers only the
## origin cell (attack in place, or wait).
func _reachable_cells(unit: Unit, origin: Vector2i, board) -> Array:
	# A rooted unit reaches nothing. The AI movement path walks the unit with
	# board.move_unit() directly and therefore never consults Unit.can_move(), so
	# immobilisation has to be honoured HERE -- returning an empty reachable set
	# leaves the planner with only the origin cell (exactly the no-profile case),
	# which makes the AI attack in place or wait instead of sliding out of the
	# vines. Gated on immobilisation alone, not the whole can_move(), so the
	# planner's existing behaviour is untouched for every other unit.
	if _is_immobilized(unit):
		return []
	var profile = unit.get_movement_profile()
	if profile == null:
		return []
	# Pass the unit so a multi-cell unit (e.g. a 2x2 boss) only considers cells where
	# its WHOLE footprint fits; omitting it would path the boss as if it were 1x1.
	return MovementResolver.new().reachable_cells(origin, profile, board, unit)


## Move the unit to the planned stand cell (if any), then resolve the chosen attack
## from there. The destination came from the reachable set (already validated as a
## legal stopping cell) and the move was validated to hit the target FROM it.
func _execute_plan_attack(unit: Unit, decision: Dictionary, board) -> void:
	var origin: Vector2i = board.cell_of(unit)
	var dest: Vector2i = decision.get("dest_cell", origin)
	# Second gate on the same rule _reachable_cells applies. The planner should
	# never hand back a foreign dest_cell for a rooted unit (its reachable set was
	# empty), but this is the line that actually relocates the unit, so it refuses
	# to walk one that cannot move rather than trusting the plan.
	var moved := dest != origin and not _is_immobilized(unit)
	if moved:
		_relocate(unit, board, origin, dest)
		unit.mark_moved()

	if _execute_move_decision(unit, decision, board):
		if moved:
			print("[BotAI] %s advances to %s then %s at %s"
				% [unit.get_display_name(), str(dest), _move_name(decision.get("move")), str(decision.get("aim_cell"))])
		else:
			print("[BotAI] %s uses %s at %s"
				% [unit.get_display_name(), _move_name(decision.get("move")), str(decision.get("aim_cell"))])
		return

	# The move failed to resolve after moving (rare). End the turn cleanly -- the
	# unit still spent its move if it walked.
	_finish(unit, "move" if moved else "wait")


## Move the unit its full advance toward the nearest enemy. The destination is a
## reachable cell the planner chose to minimize distance to that enemy.
func _execute_plan_advance(unit: Unit, decision: Dictionary, board) -> void:
	var origin: Vector2i = board.cell_of(unit)
	var dest: Vector2i = decision.get("dest_cell", origin)
	if dest == origin or _is_immobilized(unit):
		_finish(unit, "wait")
		return
	_relocate(unit, board, origin, dest)
	unit.mark_moved()
	var target = decision.get("target", null)
	var tname: String = target.get_display_name() if target != null and target.has_method("get_display_name") else "enemy"
	print("[BotAI] %s advances to %s toward %s" % [unit.get_display_name(), str(dest), tname])
	_finish(unit, "move")


## Execute an attack/use-move decision (a chosen move + aim cell) through
## [Unit.perform_move] / [MoveExecutor]. Returns true if the move resolved
## successfully AND the unit's action was consumed (turn ended). Logging is left to
## the caller so a move-then-attack reports as a single concise line.
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
		# Concise, diagnosable proof the attack LANDED: target + damage + target HP
		# after. Mirrors the take_damage log in the fallback path so both AI attack
		# routes are visible in the live game's output.
		_log_attack_landed(unit, move, result)
		var mc := unit.get_moveset_controller()
		if mc != null and mc.has_method("on_used"):
			mc.on_used(move)
		unit.mark_action_completed("move")
		return true
	return false


## Log the damage a resolved move dealt (one line per damaged target), reading the
## structured events MoveExecutor returned. Silent when the move dealt no damage
## (e.g. a pure buff/move) so only real hits print.
func _log_attack_landed(unit: Unit, move, result: Dictionary) -> void:
	var events = result.get("events", [])
	if not (events is Array):
		return
	for ev in events:
		if not (ev is Dictionary):
			continue
		if ev.get("effect", "") != "damage" or ev.get("missed", false):
			continue
		var target = ev.get("target", null)
		if target == null:
			continue
		var amount: int = int(ev.get("amount", 0))
		var hp_after: int = target.get_hp() if target.has_method("get_hp") else -1
		var tname: String = target.get_display_name() if target.has_method("get_display_name") else "enemy"
		var crit_tag: String = " CRIT" if ev.get("crit", false) else ""
		print("[BotAI] %s hits %s with %s for %d%s (%s HP now %d)"
			% [unit.get_display_name(), tname, _move_name(move), amount, crit_tag, tname, hp_after])


## Index of [param move] within the unit's moveset (what [Unit.perform_move]
## expects), or -1 if the move is not part of the unit's authored kit.
func _slot_of_move(unit: Unit, move) -> int:
	var moveset := unit.get_moveset()
	for i in range(moveset.size()):
		if moveset[i] == move:
			return i
	return -1


## True while a status roots [param unit] in place. Duck-typed and null-safe so
## the legacy/mocked units this driver also handles simply report false.
func _is_immobilized(unit) -> bool:
	if unit == null:
		return false
	if unit.has_method("is_immobilized"):
		return bool(unit.is_immobilized())
	return false


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
		_relocate(unit, board, ucell, dest)
		print("[BotAI] %s moves toward %s" % [unit.get_display_name(), target.get_display_name()])
		_finish(unit, "move")


func _fallback_attack(unit: Unit, target: Unit) -> void:
	var dmg: int = _stat(unit, "attack", 10)
	if target.has_method("take_damage"):
		target.take_damage(dmg)
	var hp_after: int = target.get_hp() if target.has_method("get_hp") else -1
	print("[BotAI] %s attacks %s for %d (%s HP now %d)"
		% [unit.get_display_name(), target.get_display_name(), dmg, target.get_display_name(), hp_after])


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
