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


## Run every [enum TileEffectResource.Trigger].ON_ENTER effect on [param cell]
## that applies to [param unit]. Returns the merged event log.
func on_enter(unit, cell: Vector2i, board) -> Array:
	return _run_trigger(unit, cell, board, TileEffectResource.Trigger.ON_ENTER)


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
		if trap == null:
			continue
		if bool(trap.get("halts_movement")):
			return cell
		if i < last:
			on_pass(unit, cell, board)
	return path[last]


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


## Remove a spent runtime tile effect from the live board. Reaches the CombatServices
## autoload directly (the applied-effects owner); null-safe for headless/mocked tests
## where there is no live services node.
func _extinguish(cell: Vector2i, te) -> void:
	var svc = _combat_services()
	if svc != null and svc.has_method("remove_tile_effect"):
		svc.remove_tile_effect(cell, te)


func _combat_services():
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
