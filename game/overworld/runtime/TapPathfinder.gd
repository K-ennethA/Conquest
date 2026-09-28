class_name TapPathfinder
extends RefCounted

## Tap-to-walk (docs/design/OVERWORLD.md §4.3): an [AStarGrid2D] over the [OverworldGrid]'s
## walkable cells, 4-way (the overworld is grid-locked, no diagonals). Pure: grid in, path out.


## The cells to step through from [param from] to [param to] (excluding [param from]; ending on
## [param to]). Empty when [param to] is unreachable or not walkable. [param blocked_ok] lets the
## path END on an occupied cell (never used for the walker; kept for NPC tooling).
static func find_path(grid: OverworldGrid, from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if grid == null or not grid.in_bounds(from) or not grid.in_bounds(to) or from == to:
		return out
	if not grid.is_walkable(to):
		return out
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, grid.width, grid.height)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for y in range(grid.height):
		for x in range(grid.width):
			var c := Vector3i(x, y, 0)
			if c != from and not grid.is_walkable(c):
				astar.set_point_solid(Vector2i(x, y), true)
	var ids: Array[Vector2i] = astar.get_id_path(Vector2i(from.x, from.y), Vector2i(to.x, to.y))
	for i in range(1, ids.size()):
		out.append(Vector3i(ids[i].x, ids[i].y, 0))
	return out


## Path to the best walkable cell ADJACENT to [param target] (tap on an NPC / sign / chest:
## walk next to it, then face and interact). Returns {path: Array[Vector3i], stand: Vector3i}
## or {} when no side is reachable. Already adjacent -> an empty path standing where you are.
static func path_to_adjacent(grid: OverworldGrid, from: Vector3i, target: Vector3i) -> Dictionary:
	if grid == null:
		return {}
	if Cells.manhattan_2d(from, target) == 1:
		return {"path": [] as Array[Vector3i], "stand": from}
	var best: Dictionary = {}
	for d in OverworldGrid.DIRS:
		var stand := Vector3i(target.x + d.x, target.y + d.y, target.z)
		if not grid.is_walkable(stand) and stand != from:
			continue
		var p: Array[Vector3i] = find_path(grid, from, stand)
		if p.is_empty() and stand != from:
			continue
		if best.is_empty() or p.size() < (best["path"] as Array).size():
			best = {"path": p, "stand": stand}
	return best
