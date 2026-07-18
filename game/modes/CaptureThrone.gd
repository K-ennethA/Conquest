extends WinCondition
class_name CaptureThrone

## MET when a living unit of [member faction] occupies [member target_cell].
##
## The seize / capture-point objective. Uses the board adapter's spatial query
## when available, falling back to per-unit [code]cell_of[/code] lookups.

## The faction that must hold the cell.
@export var faction: int = 0
## The cell that must be occupied.
@export var target_cell: Vector2i = Vector2i.ZERO


func evaluate(state: Dictionary) -> int:
	var board = state.get("board")
	if board != null and board.has_method("units_at"):
		for u in board.units_at(target_cell):
			if _team_of(u) == faction and _is_alive(u):
				return Status.MET
		return Status.ONGOING

	# Fallback: scan the unit list and ask the board for each position.
	if board != null and board.has_method("cell_of"):
		for u in state.get("units", []):
			if _team_of(u) == faction and _is_alive(u) and board.cell_of(u) == target_cell:
				return Status.MET
	return Status.ONGOING


func describe() -> String:
	return "Capture the objective cell %s" % target_cell
