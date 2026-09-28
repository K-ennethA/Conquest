class_name TrainerSight
extends RefCounted

## TRAINER LINE OF SIGHT (docs/design/OVERWORLD.md §4.5) as pure cell functions: a trainer
## sees the cells in a straight line along his facing, up to his sight range, stopping at the
## first cell that blocks sight (impassable or LOS-blocking terrain, or a blocking entity).
## Checked after each player step and on area entry.


## The cells [param trainer_cell] can see facing [param dir], nearest first, ending before the
## first blocker. The player's cell is NOT a blocker (that is what he is looking for).
static func sight_cells(grid: OverworldGrid, trainer_cell: Vector3i, dir: Vector2i,
		sight_range: int, player_cell: Vector3i = Cells.INVALID) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if grid == null or dir == Vector2i.ZERO:
		return out
	for step in range(1, sight_range + 1):
		var c := Vector3i(trainer_cell.x + dir.x * step, trainer_cell.y + dir.y * step, trainer_cell.z)
		if not grid.in_bounds(c):
			break
		if c == player_cell:
			out.append(c)
			break
		if grid.blocks_sight(c):
			break
		out.append(c)
	return out


## Does the trainer see the player?
static func spots(grid: OverworldGrid, trainer_cell: Vector3i, dir: Vector2i, sight_range: int,
		player_cell: Vector3i) -> bool:
	return sight_cells(grid, trainer_cell, dir, sight_range, player_cell).has(player_cell)


## Where a spotting trainer walks to: the cell between him and the player that is adjacent to
## the player (he walks up to face you). Equal to his own cell when already adjacent.
static func approach_cell(trainer_cell: Vector3i, dir: Vector2i, player_cell: Vector3i) -> Vector3i:
	var c := Vector3i(player_cell.x - dir.x, player_cell.y - dir.y, player_cell.z)
	if Cells.manhattan_2d(trainer_cell, player_cell) <= 1:
		return trainer_cell
	return c
