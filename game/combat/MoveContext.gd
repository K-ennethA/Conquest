extends RefCounted
class_name MoveContext

## Runtime state handed to each [MoveEffect] while a move resolves.
##
## Decouples effects from the concrete game: effects talk to [member board] and
## to units through small duck-typed interfaces, so the same effect works in the
## live game and against a mock board in tests.
##
## Expected [member board] interface (any object with these methods):
##   cell_of(unit) -> Vector2i
##   units_at(cell: Vector2i) -> Array
##   are_enemies(a, b) -> bool
##   are_allies(a, b) -> bool
##   set_tile(cell: Vector2i, tile_id) -> void
##   move_unit(unit, to_cell: Vector2i) -> void
##
## Expected unit interface: get_stat(name) -> int, take_damage(n), heal(n),
## add_stat_modifier(stat, amount, duration).

var caster                       ## the acting unit
var board                        ## board query/mutation adapter (see above)
var move: MoveResource
var aim_cell: Vector2i
var affected_cells: Array[Vector2i]
var results: Array[Dictionary] = []


func _init(p_caster, p_board, p_move: MoveResource, p_aim: Vector2i, p_cells: Array[Vector2i]) -> void:
	caster = p_caster
	board = p_board
	move = p_move
	aim_cell = p_aim
	affected_cells = p_cells


func get_caster_stat(stat_name: String) -> int:
	if caster and caster.has_method("get_stat"):
		return caster.get_stat(stat_name)
	return 0


## Units in the affected area that match the move's target kind.
func gather_targets() -> Array:
	var found: Array = []
	for cell in affected_cells:
		for unit in board.units_at(cell):
			if _matches_target_kind(unit) and unit not in found:
				found.append(unit)
	return found


func log_event(event: Dictionary) -> void:
	results.append(event)


func _matches_target_kind(unit) -> bool:
	match move.targeting.target_kind:
		CombatTypes.TargetKind.SELF:
			return unit == caster
		CombatTypes.TargetKind.ALLY:
			return unit != caster and board.are_allies(caster, unit)
		CombatTypes.TargetKind.ENEMY:
			return board.are_enemies(caster, unit)
		CombatTypes.TargetKind.ANY_UNIT:
			return true
		_:
			return false  # TILE / EMPTY_TILE effects don't gather units
