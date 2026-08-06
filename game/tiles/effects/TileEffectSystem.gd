extends Node
class_name TileEffectSystem

## Resolves [TileEffectResource]s for units on the tactical board.
##
## The system does not own the map. It looks up the effects on a cell through a
## duck-typed board method [code]tile_effects_at(cell) -> Array[/code], falling
## back to an injected [member tile_effects] dictionary (cell -> Array). This
## keeps it testable against a mock board and lets the live board/map supply the
## real authoring source later.
##
## A turn/movement system raises the events by calling [method on_enter],
## [method on_exit] and [method on_turn_start]; the targeting system asks
## [method passive_flags] whether an occupant is currently untargetable,
## fortified, and so on. Every method resolves effects in deterministic order
## (the cell's array order, then each effect's own order).
##
## MOVEMENT arrives as [method apply_move], which is the whole terrain side of one applied
## move: the cell left, the cells CROSSED, and the cell truly landed on. Crossing matters
## because a tile effect a designer authored [member TileEffectResource.springs_on_pass] on
## is a TRAP -- it springs on a unit walking over it, and may halt that unit on it
## (CONQUEST.md rule 10). Everything else stays landing-only, exactly as it always was.

## Optional injected lookup: cell ([Vector2i]) -> [code]Array[TileEffectResource][/code].
## Used only when the board does not supply effects for that cell.
var tile_effects: Dictionary = {}

## The turn system this instance's expiry sweep is currently riding (see [method setup]).
var _expiry_turn_system = null


## Run every [enum TileEffectResource.Trigger].ON_ENTER effect on [param cell]
## that applies to [param unit], then STOMP any placement this unit's arrival destroys.
## Returns the merged event log.
##
## ORDER IS PART OF THE RULE: the ground gets its say FIRST. A unit stepping onto a cell that
## holds both an armed trap and a hostile anchor springs the trap AND breaks the anchor --
## the trap fires against a board that still contains the anchor, and the anchor then dies.
## Stomping first would let a placement disappear before an effect layered on the same cell
## had resolved against it.
func on_enter(unit, cell: Vector2i, board) -> Array:
	var events: Array = _run_trigger(unit, cell, board, TileEffectResource.Trigger.ON_ENTER)
	for te in stomp_hostile_placements(unit, cell, board):
		events.append({ "effect": "tile_effect_stomped", "cell": cell, "tile_effect": te, "unit": unit })
	return events


## Run every ON_EXIT effect on the cell the unit is leaving.
func on_exit(unit, cell: Vector2i, board) -> Array:
	return _run_trigger(unit, cell, board, TileEffectResource.Trigger.ON_EXIT)


# --- Pass-through traps -----------------------------------------------------
#
# GLOWING TILES HURT WHERE YOU STAND; TRAPS SPRING WHERE YOU STEP (CONQUEST.md rule 10).
# Everything below is the STEP half of that rule and touches nothing else: an ordinary
# ON_ENTER effect is still landing-only, because only an effect a designer authored
# springs_on_pass on is ever considered here.


## The first ARMED pass-trap among [param effects] -- the first one that would spring on
## [param unit] if it walked over the cell -- or null. First in the cell's own effect order,
## which is the same deterministic order every other query here resolves in.
static func armed_trap_in(effects: Array, unit, board):
	if unit == null:
		return null
	for te in effects:
		if te == null or not te.has_method("springs_on_pass_for"):
			continue
		if te.springs_on_pass_for(unit, board):
			return te
	return null


## The first armed pass-trap on [param cell] for [param unit], or null. Same cell lookup
## every other trigger uses (the board first, then the injected dictionary).
func armed_trap_at(unit, cell: Vector2i, board):
	return armed_trap_in(_effects_at(cell, board), unit, board)


## Spring the pass-traps on [param cell] for a unit CROSSING it -- and nothing else.
##
## Deliberately narrower than [method on_enter]: a unit that merely walks over a cell has
## not stood on it, so the cell's ordinary ON_ENTER effects (rubble's slow, a meadow's heal)
## must NOT fire. Only the authored traps do, through the very same [method
## TileEffectResource.run] pipeline -- guaranteed-hit, elemented, single-use -- so a trap
## sprung in passing is identical to one sprung by landing on it.
func on_pass(unit, cell: Vector2i, board) -> Array:
	return _run_trigger(unit, cell, board, TileEffectResource.Trigger.ON_ENTER, true)


## Walk [param path] (the traversed cells in step order, origin excluded, destination last)
## and return the cell the move actually ENDS on.
##
## The rule, in order along the path:
##   * no armed trap on a cell -> nothing happens, the unit keeps walking;
##   * an armed trap that HALTS -> the walk stops there and that cell is returned. The trap
##     itself is NOT fired here: the caller runs its ordinary ON_ENTER pass on the returned
##     cell, so the trap springs through exactly the machinery a landing would use and the
##     cell's other effects resolve too (the unit really is standing on it now);
##   * an armed trap that does NOT halt -> it springs in passing ([method on_pass]) and the
##     walk continues. Reached only mid-path: a trap on the LAST cell is a landing, and the
##     caller's ON_ENTER pass fires it, so firing it here would double-spring it.
##
## Pure board state: no RNG, no wall clock, no scene order. Given the same path and the same
## board this returns the same cell on every peer and in every replay.
## What a move from [param origin] to [param dest] would DO to [param unit], derived and
## fired nothing:
##
##   [code]path[/code] -- the cells it walks over (origin excluded, destination last),
##                        from [method MovementResolver.path_cells];
##   [code]stop[/code] -- the cell it actually ends on: [param dest], or the first armed
##                        HALTING trap on the route;
##   [code]trap[/code] -- the first armed trap on the route at all (halting or not), which
##                        is what a warning names; null when the route is clear.
##
## THE SAME DERIVATION THE MOVE ITSELF RUNS. The path preview, the AI's route check and the
## live walk in [method resolve_path] all read this one function, so the cell the ghost
## lands on is the cell the move ends on -- a preview cannot drift from the resolution
## (the terrain-side reading of CONQUEST.md rule 9).
##
## Pure: it reads the board and applies nothing. Null-safe end to end -- a unit with no
## movement profile, a board that cannot answer, or an unreachable destination all yield an
## empty path, [param dest] as the stop, and no trap.
static func preview_route(unit, origin: Vector2i, dest: Vector2i, board) -> Dictionary:
	var out: Dictionary = { "path": ([] as Array[Vector2i]), "stop": dest, "trap": null }
	if unit == null or board == null or origin == dest:
		return out
	if not unit.has_method("get_movement_profile"):
		return out
	var profile = unit.get_movement_profile()
	if profile == null:
		return out
	var path: Array[Vector2i] = MovementResolver.new().path_cells(origin, dest, profile, board, unit)
	if path.is_empty():
		return out
	out["path"] = path
	for cell in path:
		var te = trap_on_cell(unit, cell, board)
		if te == null:
			continue
		if out["trap"] == null:
			out["trap"] = te
		if bool(te.get("halts_movement")):
			out["stop"] = cell
			break
	return out


## The first armed pass-trap on [param cell] for [param unit], read straight off the board.
## The static twin of [method armed_trap_at], for the preview / AI callers that have no
## [TileEffectSystem] instance (and therefore no injected lookup) to ask.
static func trap_on_cell(unit, cell: Vector2i, board):
	if board == null or not board.has_method("tile_effects_at"):
		return null
	return armed_trap_in(board.tile_effects_at(cell), unit, board)


func resolve_path(unit, path: Array, board, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if path.is_empty():
		return fallback
	var last: int = path.size() - 1
	for i in range(path.size()):
		var cell: Vector2i = path[i]
		var trap = armed_trap_at(unit, cell, board)
		if trap != null and bool(trap.get("halts_movement")):
			# The walk ends here, so this cell is a LANDING: the caller's on_enter pass fires
			# the trap and stomps whatever the arrival breaks. Nothing more to do here.
			return cell
		if i == last:
			continue  # the destination is a landing too -- same reason.
		if trap != null:
			on_pass(unit, cell, board)
		# STOMPED IN PASSING. A hostile placement dies to a unit merely CROSSING its cell,
		# not only to one that stops on it: it is the arrival that breaks it, and a unit
		# running over an anchor has arrived on it however briefly. Deliberately AFTER the
		# trap fires, matching the landing order in on_enter.
		stomp_hostile_placements(unit, cell, board)
	return path[last]


## Destroy every placement on [param cell] that [param unit] ARRIVING there breaks -- the
## authored [member TileEffectResource.destroyed_by_hostile_entry] rule. Returns what was
## removed, so a caller can log or announce it.
##
## THE SAME REMOVAL PATH a sprung, an evicted and an expired placement all take
## ([method CombatServices.remove_tile_effect] via [method _extinguish]), so a stomped anchor
## leaves the board identically: the same state cleared, the same
## [signal CombatServices.tile_effects_changed] raised, and therefore the same marker pulled
## off the cell by the overlay. There is deliberately no second "remove a placement" path.
##
## Deterministic: the verdict is an owner comparison per effect, walked in the cell's own
## array order, with no RNG and no clock -- two lockstep peers break the same anchors.
## Removal happens AFTER the walk so the cell's effect list is never mutated mid-iteration,
## exactly as [method _run_trigger] extinguishes a spent snare.
func stomp_hostile_placements(unit, cell: Vector2i, board) -> Array:
	var broken: Array = []
	if unit == null:
		return broken
	for te in _effects_at(cell, board):
		if te == null or not te.has_method("destroyed_by"):
			continue
		if te.destroyed_by(unit, board):
			broken.append(te)
	for te in broken:
		_extinguish(cell, te)
	return broken


## THE WHOLE TERRAIN SIDE OF ONE APPLIED MOVE, in order: ON_EXIT on the cell left, the trap
## walk across the cells crossed, and ON_ENTER on the cell the move REALLY ends on. Returns
## that landing cell, which is [param to_cell] unless an armed halting trap cut the move
## short (and the unit has then been snapped back onto the trap through the board).
##
## One function because the three steps are one event: a move that halts must not run
## ON_ENTER for a destination it never reached, and must run it for the trap cell it did.
## Splitting them across callers is how those two drift apart.
##
## [param prime] is an optional per-cell hook the caller may pass to refresh whatever
## cell->effects source it owns before the walk touches a cell (GameWorldManager feeds the
## system's injected lookup through it). Never needed by a board that answers
## [code]tile_effects_at[/code] itself.
func apply_move(unit, from_cell: Vector2i, to_cell: Vector2i, board, prime: Callable = Callable()) -> Vector2i:
	if unit == null or board == null:
		return to_cell
	on_exit(unit, from_cell, board)
	var path: Array = preview_route(unit, from_cell, to_cell, board).get("path", [])
	if prime.is_valid():
		for cell in path:
			prime.call(cell)
		prime.call(to_cell)
	var land_cell: Vector2i = resolve_path(unit, path, board, to_cell)
	# Snap the unit back onto the cell the walk actually stopped on. Deliberately through
	# board.move_unit, which does NOT re-announce the move (see BoardAdapter): re-emitting
	# unit_moved for the correction would re-run this whole hook, fire ON_EXIT for a cell
	# the unit never stood on, and double-trigger every ON_MOVE ability.
	if land_cell != to_cell and board.has_method("move_unit"):
		board.move_unit(unit, land_cell)
	on_enter(unit, land_cell, board)
	return land_cell


## Run every ON_TURN_START_WHILE_OCCUPYING effect on the unit's current cell.
func on_turn_start(unit, board) -> Array:
	return _run_trigger(unit, _cell_of(unit, board), board, TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING)


## Merge the [member TileEffectResource.rule_flags] of every
## PASSIVE_WHILE_OCCUPYING effect currently affecting [param unit] on its cell.
## Later effects override earlier ones on key collisions. This is what lets the
## targeting system ask "is this unit untargetable?" without mutating anything.
func passive_flags(unit, board) -> Dictionary:
	var flags: Dictionary = {}
	if unit == null:
		return flags
	var cell := _cell_of(unit, board)
	for te in _effects_at(cell, board):
		if te == null or te.trigger != TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING:
			continue
		if not te.applies_to(unit, board):
			continue
		for key in te.rule_flags:
			flags[key] = te.rule_flags[key]
	return flags


## [param pass_traps_only] restricts the run to authored pass-through traps -- the
## crossing case (see [method on_pass]). Default false is every effect on the trigger,
## which is what landing on a cell means and is byte-for-byte the original behaviour.
func _run_trigger(unit, cell: Vector2i, board, trigger: int, pass_traps_only: bool = false) -> Array:
	var events: Array = []
	if unit == null:
		return events
	var spent: Array = []  # single-use effects that fired and must be extinguished
	for te in _effects_at(cell, board):
		if te == null or te.trigger != trigger:
			continue
		if pass_traps_only and not (te.has_method("is_pass_trap") and te.is_pass_trap()):
			continue
		if not te.applies_to(unit, board):
			continue
		for e in te.run(unit, board):
			events.append(e)
		# A single-use snare (Vine Trap) is spent the instant it springs on a unit.
		if te.get("consume_on_trigger"):
			spent.append(te)
	# Extinguish AFTER the loop so we never mutate the cell's effect list mid-iteration;
	# remove_tile_effect fires tile_effects_changed, which clears the trap's visual too.
	for te in spent:
		_extinguish(cell, te)
	return events


# --- Placed-trap expiry -------------------------------------------------------
#
# A TRAP THAT LASTS FOREVER STOPS BEING A PLAY AND BECOMES TERRAIN. A mode may declare a
# lifetime for the traps its battles plant ([member SiegeRuleset.trap_expiry_rounds], read
# through [method ModeTuning.trap_expiry_rounds]); this is the sweep that honours it.
#
# TWO THINGS IT CANNOT TOUCH, both by construction rather than by check:
#   * MAP-AUTHORED TERRAIN. The walk is over CombatServices' APPLIED layer only -- the
#     per-cast runtime placements. Base effects derived from the tile type are in a different
#     layer and are never enumerated here, so lava is not on the table at any round.
#   * A PLACEMENT WITH NO CLOCK. Only a copy that [method TileEffectResource.stamp_placement]
#     gave an expiry round is ever removed, and that is stamped only when the active mode
#     declared a lifetime AT PLACEMENT TIME. With no mode armed nothing is stamped, so a
#     skirmish trap is permanent exactly as it always was.


## Sweep every runtime-placed tile effect whose frozen expiry round has arrived on
## [param round_index]. Returns the removals as [code]{ "cell": Vector2i, "effect": ... }[/code].
##
## THE SAME REMOVAL PATH A SPRUNG TRAP TAKES -- [method CombatServices.remove_tile_effect],
## which is what [method _extinguish] calls when a single-use snare fires. So an expired trap
## and a spent one leave the board identically: the same board state cleared, the same
## [signal CombatServices.tile_effects_changed] raised, and therefore the same marker pulled
## off the cell by the overlay. There is deliberately no second "remove a trap" path.
##
## DRIVEN BY THE MODE'S ROUND CLOCK, which is itself edge-detected off the ACTIVE turn
## system's turn_started (CONQUEST.md rule 2) -- see [method SiegeController._run_round_start].
## A future mode calls this same line from its own round boundary.
##
## Deterministic: cells are walked in sorted order and the verdict is pure arithmetic on each
## placement's frozen record, so two peers sweep the same traps in the same order.
static func expire_placed_effects(round_index: int) -> Array:
	var removed: Array = []
	if round_index <= 0:
		return removed
	var svc = _combat_services()
	if svc == null or not svc.has_method("applied_effect_cells"):
		return removed
	var cells: Array = svc.applied_effect_cells()
	cells.sort_custom(_cell_before)
	for cell in cells:
		for te in svc.applied_tile_effects_at(cell):
			if te == null or not te.has_method("is_expired_on"):
				continue
			if not te.is_expired_on(round_index):
				continue
			svc.remove_tile_effect(cell, te)
			removed.append({ "cell": cell, "effect": te })
	return removed


# --- The GENERIC expiry clock -------------------------------------------------
#
# [method expire_placed_effects] is the sweep; something has to DRIVE it. [SiegeController]
# drives it from its own round boundary for the mode-declared trap lifetime, but a
# placement can also carry an expiry AUTHORED ON THE EFFECT ITSELF -- Duskmaw's void spots
# live 12 turns whatever mode is (or is not) running -- and in a plain skirmish there is no
# mode controller to turn the handle.
#
# So this node turns it too, on every turn boundary. Two things make that safe rather than a
# second, competing clock:
#   * THE VERDICT IS PURE ARITHMETIC on each placement's FROZEN record
#     ([method TileEffectResource.is_expired_on]), and both drivers read the SAME round
#     number ([method ModeTuning.current_round] resolves the active mode's counter first).
#     Sweeping twice in a round is therefore idempotent: the second pass finds nothing the
#     first did not already take, so Siege's behaviour is unchanged.
#   * IT RIDES THE ACTIVE TURN SYSTEM'S turn_started, never PlayerManager's -- those do not
#     fire on AI turns, so anything wired to them silently stops ticking the moment the
#     enemy is acting (CONQUEST.md rule 2).


## Start driving the expiry sweep off the active turn system. Called once by
## [code]GameWorldManager._setup_tile_effects[/code]; idempotent, and a no-op in a headless
## harness with no [TurnSystemManager] autoload.
func setup() -> void:
	if typeof(TurnSystemManager) != TYPE_OBJECT or TurnSystemManager == null:
		return
	if not TurnSystemManager.turn_system_activated.is_connected(_on_expiry_turn_system_activated):
		TurnSystemManager.turn_system_activated.connect(_on_expiry_turn_system_activated)
	if TurnSystemManager.has_active_turn_system():
		_on_expiry_turn_system_activated(TurnSystemManager.get_active_turn_system())


## (Re)point the sweep at whichever turn system is now active, dropping the previous one.
func _on_expiry_turn_system_activated(ts) -> void:
	if _expiry_turn_system == ts:
		return
	if _expiry_turn_system != null and is_instance_valid(_expiry_turn_system) \
			and _expiry_turn_system.turn_started.is_connected(_on_expiry_turn_started):
		_expiry_turn_system.turn_started.disconnect(_on_expiry_turn_started)
	_expiry_turn_system = ts
	if ts != null and is_instance_valid(ts) and not ts.turn_started.is_connected(_on_expiry_turn_started):
		ts.turn_started.connect(_on_expiry_turn_started)


## One turn boundary: sweep whatever the round the battle is now on has outlived.
func _on_expiry_turn_started(_player = null) -> void:
	expire_placed_effects(ModeTuning.current_round())


func _exit_tree() -> void:
	# The battle is over; stop holding the turn system's signal. Godot would drop the
	# connection when either end is freed, but a system torn down between battles while the
	# turn system survives would otherwise keep sweeping for a board it no longer serves.
	_on_expiry_turn_system_activated(null)
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null \
			and TurnSystemManager.turn_system_activated.is_connected(_on_expiry_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_expiry_turn_system_activated)


## Row-major cell order. Explicit rather than relying on [Vector2i]'s own comparison, so the
## sweep order is stated where it is depended on.
static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


## Remove a spent runtime tile effect from the live board. Reaches the CombatServices
## autoload directly (the applied-effects owner); null-safe for headless/mocked tests
## where there is no live services node.
func _extinguish(cell: Vector2i, te) -> void:
	var svc = _combat_services()
	if svc != null and svc.has_method("remove_tile_effect"):
		svc.remove_tile_effect(cell, te)


static func _combat_services():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("CombatServices")
	return null


## Prefer the board's own authoring source; fall back to the injected dictionary.
func _effects_at(cell: Vector2i, board) -> Array:
	if board and board.has_method("tile_effects_at"):
		var arr = board.tile_effects_at(cell)
		if arr is Array and not arr.is_empty():
			return arr
	if tile_effects.has(cell):
		var injected = tile_effects[cell]
		if injected is Array:
			return injected
	return []


static func _cell_of(unit, board) -> Vector2i:
	if board and board.has_method("cell_of"):
		return board.cell_of(unit)
	return Vector2i.ZERO
