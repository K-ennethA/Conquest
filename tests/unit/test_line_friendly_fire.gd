extends GutTest

## Repro for "Vineweave's piercing arrow (Splinter Volley) hit the enemy AND my own unit".
## A LINE, ENEMY-targeted move must gather ONLY enemies in its path, never allies.

class MockUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))
	func get_stat(n: String) -> int:
		return int(stats.get(n, 0))
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp += n

class MockBoard:
	var placements: Array = []
	func place(unit, cell: Vector3i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector3i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector3i(-999, -999, 0)
	func units_at(cell: Vector3i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team


func _splinter_volley() -> MoveResource:
	# Deep-dup so we can force a guaranteed hit (accuracy 1.0) without touching the .tres,
	# isolating "who gets gathered" from the accuracy roll.
	var m: MoveResource = load("res://game/combat/moves/splinter_volley.tres").duplicate(true)
	m.accuracy = 1.0
	return m


func test_line_enemy_move_hits_enemies_not_allies():
	var move := _splinter_volley()
	var caster := MockUnit.new(0, {"attack": 30, "health": 100})
	var ally := MockUnit.new(0, {"health": 100})   # same team as caster
	var enemy := MockUnit.new(1, {"health": 100})  # opposing team
	var board := MockBoard.new()
	# A straight column: caster, then ally, then enemy, then another ally beyond.
	board.place(caster, Vector3i(0, 0, 0))
	board.place(ally, Vector3i(0, 1, 0))
	board.place(enemy, Vector3i(0, 2, 0))
	var ally2 := MockUnit.new(0, {"health": 100})
	board.place(ally2, Vector3i(0, 3, 0))

	# Resolve the line from the caster toward the aim and run every effect, exactly as
	# a live cast does (MoveExecutor builds the same MoveContext).
	var aim := Vector3i(0, 2, 0)
	var cells: Array[Vector3i] = move.targeting.resolve_cells(Vector3i(0, 0, 0), aim)
	var ctx := MoveContext.new(caster, board, move, aim, cells)
	for e in move.effects:
		e.apply(ctx)

	assert_eq(ally.hp, 100, "an allied unit in the arrow's path takes NO damage")
	assert_eq(ally2.hp, 100, "an allied unit beyond the target takes NO damage")
	assert_lt(enemy.hp, 100, "the ENEMY in the line still takes damage")
