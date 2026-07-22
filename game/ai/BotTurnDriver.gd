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

## Seconds between VISIBLE AI unit actions (a move or an attack). Silent no-op
## waits are fast-forwarded within a single tick and do NOT cost an interval each.
## The effective wait is additionally divided by the player's battle-speed setting
## (see [method _effective_wait]) so "Fast" also speeds the AI.
@export var action_interval: float = 0.18

## Longer beat AFTER a visible ATTACK, so the player can actually watch the strike
## (the attacker's shake + the hit flash + the camera framing it) instead of the AI
## blowing past it. A plain move or a skipped wait uses action_interval; only an
## attack gets this dwell. Also divided by battle-speed.
@export var attack_dwell: float = 0.55

## Hard cap on how many silent no-op waits a single tick will fast-forward before
## yielding back to the frame. Bounds the worst case (a huge army entirely out of
## range) so the AI can never freeze a frame chewing through waits.
@export var max_waits_per_tick: int = 32

## When true, log extra diagnostics (e.g. "AI turn but no actable unit"). Off by
## default so a normal match only prints the concise one-line-per-action summary
## the execute paths emit.
@export var verbose: bool = false

## When true (default), a DEFENSIVE guard that is provably going to WAIT this turn is
## short-circuited to a silent wait WITHOUT running the expensive reachable-cell flood
## (a MovementResolver flood) or BotController.plan. On a big map most enemy units are
## idle defenders far from the player, so skipping their planning is the bulk of the
## enemy-turn cost. Behaviour-preserving -- it only fires when the planner would ALSO
## have made the unit wait (see [method _defender_certain_to_wait]). Toggle off to
## profile / debug the full planning path for every unit.
@export var skip_idle_defender_planning: bool = true

var _timer: Timer
var _busy: bool = false
# Set by _act() (via act_for_turn_system) to record whether the LAST resolved
# action was visible (a move/attack) or a silent wait. _tick() reads it to decide
# whether to keep fast-forwarding waiting units or yield and let the Timer pace the
# unit that just did something.
var _last_action_visible: bool = false
# Set true when the last resolved action was an ATTACK (a move that resolved through
# perform_move), as opposed to a plain advance. _tick() reads it to give attacks a
# longer, watchable beat.
var _last_action_was_attack: bool = false


func _ready() -> void:
	_timer = Timer.new()
	# One-shot, re-armed at the end of every _tick with the NEXT beat's length, so an
	# attack can dwell longer than a move without a second timer.
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_tick)
	_timer.start(_effective_wait())
	# Update the pacing live if the player changes battle speed mid-match. Null-safe:
	# GameSettings may be absent in headless tests, in which case the wait just stays
	# at the unscaled action_interval floor.
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null:
		if GameSettings.has_signal("settings_changed") \
				and not GameSettings.settings_changed.is_connected(_on_settings_changed):
			GameSettings.settings_changed.connect(_on_settings_changed)


## Effective Timer wait: the base interval scaled DOWN by battle speed (so faster
## battle speed -> shorter AI beats), with a hard floor so it can never hit zero.
## Reads the GameSettings autoload null-safely; when it is absent (headless tests)
## the unscaled interval is used.
func _effective_wait() -> float:
	var scaled: float = action_interval
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null and "battle_speed" in GameSettings:
		var speed: float = clampf(float(GameSettings.battle_speed), 0.5, 3.0)
		scaled = action_interval / speed
	return maxf(0.05, scaled)


## Recompute and apply the Timer's wait. Call whenever the interval or battle speed
## could have changed (startup, live settings change).
func _apply_wait() -> void:
	if _timer != null:
		_timer.wait_time = _effective_wait()


func _on_settings_changed() -> void:
	_apply_wait()


func _tick() -> void:
	# _act() is synchronous and never awaits, so no earlier _tick() can still be on
	# the stack when the Timer fires again. If _busy is somehow still set here, a
	# previous _act() errored out before clearing it -- self-heal instead of wedging
	# the driver inert for the rest of the match. A stranded _busy is exactly what
	# would leave the AI player's turn permanently incomplete (the AI never acts, so
	# the turn never advances back to the human): the primary "AI inert" failure.
	if _busy:
		_busy = false

	# FAST-FORWARD SILENT WAITS. Each visible action (move/attack) should get its own
	# Timer-paced beat so the turn stays readable, but a unit that just WAITs (nothing
	# visible happened) must not burn a whole interval of dead air. So loop the single
	# synchronous act step while it keeps resolving to silent waits, and stop the
	# instant one of these is true:
	#   * a visible action happened  -> break, next unit is paced by the next tick;
	#   * act_one_ai_unit() returned false -> it is no longer an AI turn (or nothing
	#     is actable), so there is nothing to pace;
	#   * we hit max_waits_per_tick   -> yield back to the frame so a huge out-of-range
	#     army can never freeze it (the remaining waits resume on the next tick).
	# Each iteration still performs exactly ONE synchronous act() that never awaits,
	# preserving the re-entrancy contract; the loop just skips the idle delay between
	# back-to-back non-events.
	var next_wait: float = _effective_wait()
	var waits: int = 0
	while waits < max_waits_per_tick:
		_last_action_visible = false
		_last_action_was_attack = false
		var acted: bool = act_one_ai_unit()
		if not acted:
			break
		if _last_action_visible:
			# Pace this action. An attack dwells longer so the player can watch the
			# strike land; a plain advance uses the shorter interval.
			if _last_action_was_attack:
				next_wait = _effective_dwell()
			break
		waits += 1

	# Re-arm the one-shot timer for the next beat.
	if _timer != null:
		_timer.start(next_wait)


## Effective post-attack dwell: attack_dwell scaled DOWN by battle speed, floored.
func _effective_dwell() -> float:
	var scaled: float = attack_dwell
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null and "battle_speed" in GameSettings:
		var speed: float = clampf(float(GameSettings.battle_speed), 0.5, 3.0)
		scaled = attack_dwell / speed
	return maxf(0.08, scaled)


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
			# Advancing is progress but nothing visible happened, so leave
			# _last_action_visible false: _tick() may fast-forward straight on to the
			# next player's units in the same beat instead of spending an interval here.
			_last_action_visible = false
			ts.advance_turn()
			return true
		# Rare once the AI acts every unit; only surface it when diagnosing.
		if verbose:
			print("[BotAI] %s's turn but no actable unit (active_units=%d)"
				% [player.get_display_name(), ts.get_active_units().size()])
		return false

	_busy = true
	# _act reports whether the action was visible (move/attack) or a silent wait; the
	# tick loop reads _last_action_visible to decide whether to fast-forward the next
	# waiting unit or yield and let the Timer pace this one.
	_last_action_visible = _act(unit)
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
## take_damage fallback (legacy units, or no board loaded yet). Returns true when the
## action was VISIBLE (the unit moved or attacked), false for a silent no-op wait --
## the tick loop uses this to fast-forward past waits without spending an interval.
func _act(unit: Unit) -> bool:
	var board := CombatServices.board()
	if board != null and unit.has_character():
		return _act_character(unit, board)
	return _act_fallback(unit, board)


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
func _act_character(unit: Unit, board) -> bool:
	# IDLE-DEFENDER EARLY-OUT. A defensive guard that cannot wake (no hostile within its
	# aggro range of home) AND cannot strike anything this turn is CERTAIN to wait, so
	# resolve that wait now and skip the reachable-cell flood + BotController.plan --
	# the expensive work this whole optimisation exists to avoid. Returning false marks
	# it a silent wait so the tick loop fast-forwards past it. See the helper for why
	# this is behaviour-preserving (it fires only when plan() would also have waited).
	if _defender_certain_to_wait(unit, board):
		if verbose:
			print("[BotAI] %s holds (idle defender, skipped planning)" % unit.get_display_name())
		_finish(unit, "wait")
		return false

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
		return false

	match int(decision.get("action", BotController.ActionType.WAIT)):
		BotController.ActionType.MOVE:
			return _execute_plan_attack(unit, decision, board)
		BotController.ActionType.STEP:
			return _execute_plan_advance(unit, decision, board)
		_:
			if verbose:
				print("[BotAI] %s waits (%s)" % [unit.get_display_name(), str(decision.get("reason", ""))])
			_finish(unit, "wait")
			return false


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


## True when [param unit] is a DEFENSIVE guard that will DEMONSTRABLY wait this turn,
## so the driver may skip the reachable-cell flood + [method BotController.plan] for it
## and resolve the wait directly. Mirrors the TWO ways plan() waits a defensive actor:
##
##   * IT WON'T WAKE. A defensive actor only advances when a hostile has come within
##     its [method Unit.get_aggro_range] Manhattan cells of its HOME cell -- exactly
##     BotController._hostile_within_aggro (inclusive `<=`), measured from the same
##     reference (its authored home, or the cell it stands on when it has none, per
##     BotController._effective_home). No hostile inside that radius -> it holds.
##   * IT CAN'T STRIKE. plan()'s attack branch runs for EVERY stance BEFORE the hold
##     check, so a held guard still attacks anything it can reach (a turret with
##     aggro_range 0 acts ONLY through that branch). We therefore ALSO require that no
##     hostile is within the unit's max strike reach -- movement_range + the kit's
##     longest reach. Any reachable stand cell is within movement_range Manhattan of the
##     origin, so that sum is a sound UPPER bound on attack reach: it can never under-
##     estimate, hence never skips a unit that could actually strike.
##
## Only when EVERY hostile is beyond BOTH radii is the unit certain to wait. Everything
## is duck-typed and null-safe: a missing board, home, stance, or hostile list, or an
## aggressive/boss/legacy unit, all fall through to normal planning (never a wrong skip).
func _defender_certain_to_wait(unit: Unit, board) -> bool:
	if not skip_idle_defender_planning:
		return false
	if unit == null or board == null or not board.has_method("cell_of"):
		return false
	# Bosses plan through BossController, which has its own engagement logic -- never
	# short-circuit it with BotController's defensive rule.
	if unit.has_method("is_boss") and unit.is_boss():
		return false
	# ONLY defensive units. Aggressive (and legacy/mock units reporting neither) always
	# charge the nearest hostile, so they must still run the full plan.
	if not (unit.has_method("is_defensive") and unit.is_defensive()):
		return false
	# A defensive unit with a READY trap-placement move must reach the planner so it can
	# proactively lay its trap even with no enemy in aggro / strike range -- so it is NOT
	# certain to wait, and we must not short-circuit it here. Same generic trap detection
	# BotController._move_is_trap uses (an ApplyTileEffect on an EMPTY_TILE-targeted move).
	if _has_ready_trap_move(unit):
		return false
	if not TurnSystemManager or not TurnSystemManager.has_active_turn_system():
		return false

	var ucell: Vector2i = board.cell_of(unit)
	# Effective home: authored guard post if set, else the current cell (mirror
	# BotController._effective_home so an unanchored guard reads home == origin).
	var home: Vector2i = ucell
	if unit.has_method("has_home_cell") and unit.has_home_cell() and unit.has_method("get_home_cell"):
		home = unit.get_home_cell()
	var aggro: int = 0
	if unit.has_method("get_aggro_range"):
		aggro = maxi(0, int(unit.get_aggro_range()))
	var strike_reach: int = _defender_strike_reach(unit)

	# Scan the same hostile set _nearest_hostile uses (living, human-owned, not self).
	# Bail to normal planning the instant ANY hostile could wake OR be struck.
	var ts: TurnSystemBase = TurnSystemManager.get_active_turn_system()
	var saw_hostile: bool = false
	for h in ts.registered_units:
		if h == null or not is_instance_valid(h) or h == unit:
			continue
		if h.has_method("is_alive") and not h.is_alive():
			continue
		var owner := h.get_owner_player()
		if owner == null or owner == unit.get_owner_player() or owner.is_ai:
			continue
		saw_hostile = true
		var hcell: Vector2i = board.cell_of(h)
		# WAKE (inclusive, home-referenced) -- would advance, so not certain to wait.
		if _cell_manhattan(home, hcell) <= aggro:
			return false
		# STRIKE (origin-referenced upper bound) -- attack branch could fire.
		if _cell_manhattan(ucell, hcell) <= strike_reach:
			return false
	# No hostiles at all -> fall through (task contract; don't skip on a bare board).
	if not saw_hostile:
		return false
	# Every hostile is beyond both the wake radius and the strike reach: plan() would
	# have returned a WAIT ("holding" / no reachable attack), so we can wait for free.
	return true


## Sound UPPER bound (Manhattan cells) on how far [param unit] could reach to STRIKE a
## hostile this turn: its movement range plus its longest-reaching move. Any reachable
## stand cell is within movement_range Manhattan of the origin, so a hostile farther
## than this sum from the unit cannot be attacked this turn under any plan. Null-safe:
## a unit with no moves contributes 0 reach beyond its movement.
func _defender_strike_reach(unit: Unit) -> int:
	var move_range: int = 0
	if unit.has_method("get_movement_range"):
		move_range = maxi(0, int(unit.get_movement_range()))
	var max_atk: int = 0
	if unit.has_method("get_moveset"):
		for m in unit.get_moveset():
			if m == null:
				continue
			if m.has_method("effective_max_range"):
				max_atk = maxi(max_atk, int(m.effective_max_range(unit)))
	return move_range + max_atk


## True when [param unit] carries a READY trap-placement move -- detected exactly as
## BotController does (an ApplyTileEffect on an EMPTY_TILE-targeted move) AND usable this
## turn per its MovesetController. Used by [method _defender_certain_to_wait] to exempt a
## trap-layer from the idle-defender skip so it still reaches [method BotController.plan]
## and lays its trap. Duck-typed / null-safe: a unit with no moveset (or no controller)
## reports its trap moves as ready, so it is exempted rather than wrongly skipped.
func _has_ready_trap_move(unit) -> bool:
	if unit == null or not unit.has_method("get_moveset"):
		return false
	var mc = null
	if unit.has_method("get_moveset_controller"):
		mc = unit.get_moveset_controller()
	for m in unit.get_moveset():
		if not _is_trap_move(m):
			continue
		if mc != null and mc.has_method("can_use") and not bool(mc.can_use(m)):
			continue
		return true
	return false


## Generic trap-move test, mirroring BotController._move_is_trap: an ApplyTileEffect
## carried by an EMPTY_TILE-targeted move. Never keyed to a move id.
func _is_trap_move(move) -> bool:
	if move == null or move.targeting == null:
		return false
	if int(move.targeting.target_kind) != CombatTypes.TargetKind.EMPTY_TILE:
		return false
	for e in move.effects:
		if e is ApplyTileEffect:
			return true
	return false


## Move the unit to the planned stand cell (if any), then resolve the chosen attack
## from there. The destination came from the reachable set (already validated as a
## legal stopping cell) and the move was validated to hit the target FROM it.
func _execute_plan_attack(unit: Unit, decision: Dictionary, board) -> bool:
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
		# Attacked (and possibly moved first) -- always visible.
		return true

	# The move failed to resolve after moving (rare). End the turn cleanly -- the
	# unit still spent its move if it walked. Visible only if it actually walked.
	_finish(unit, "move" if moved else "wait")
	return moved


## Move the unit its full advance toward the nearest enemy. The destination is a
## reachable cell the planner chose to minimize distance to that enemy.
func _execute_plan_advance(unit: Unit, decision: Dictionary, board) -> bool:
	var origin: Vector2i = board.cell_of(unit)
	var dest: Vector2i = decision.get("dest_cell", origin)
	if dest == origin or _is_immobilized(unit):
		_finish(unit, "wait")
		return false
	_relocate(unit, board, origin, dest)
	unit.mark_moved()
	var target = decision.get("target", null)
	var tname: String = target.get_display_name() if target != null and target.has_method("get_display_name") else "enemy"
	_finish(unit, "move")
	return true


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
		# This action used a move (an attack/cast) -- flag it so _tick dwells on it
		# long enough for the player to see the strike.
		_last_action_was_attack = true
		return true
	return false


## Log the damage a resolved move dealt (one line per damaged target), reading the
## structured events MoveExecutor returned. Silent when the move dealt no damage
## (e.g. a pure buff/move) so only real hits print.
func _log_attack_landed(unit: Unit, move, result: Dictionary) -> void:
	# Per-hit combat logging removed to keep the console quiet during play.
	pass


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
func _act_fallback(unit: Unit, board) -> bool:
	var target := _nearest_hostile(unit)
	if not target:
		_finish(unit, "wait")
		return false

	if board == null:
		# No live board -> no reliable cell math. Just apply the legacy attack so
		# AI units are not inert; movement is skipped in this degraded path.
		_fallback_attack(unit, target)
		_finish(unit, "attack")
		return true

	var ucell: Vector2i = board.cell_of(unit)
	var tcell: Vector2i = board.cell_of(target)
	var dist := _cell_manhattan(ucell, tcell)
	var atk_range: int = maxi(1, _stat(unit, "range", 1))

	if dist <= atk_range:
		_fallback_attack(unit, target)
		_finish(unit, "attack")
		return true
	else:
		var move_range: int = maxi(1, _stat(unit, "movement", 3))
		var dest := _step_toward_cell(ucell, tcell, move_range)
		_relocate(unit, board, ucell, dest)
		_finish(unit, "move")
		return true


func _fallback_attack(unit: Unit, target: Unit) -> void:
	var dmg: int = _stat(unit, "attack", 10)
	if target.has_method("take_damage"):
		target.take_damage(dmg)


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
