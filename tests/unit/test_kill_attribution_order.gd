extends GutTest

## Regression: ON_KILL abilities (Mortis's Reanimate) silently never fired because
## DamageEffect applied the damage BEFORE announcing it. A lethal hit resolves the death
## synchronously, and AbilitySystem attributes the kill via the damage_dealt signal -- so
## announcing afterwards meant the victim died before anyone knew who killed it.
## The damage must be ANNOUNCED before take_damage() can kill.

class MockBus:
	signal damage_dealt(attacker, defender, amount)

class MockUnit:
	var team: int
	var order: Array
	var hp: int = 100
	func _init(p_team: int, p_order: Array) -> void:
		team = p_team
		order = p_order
	func get_stat(_n: String) -> int:
		return 0
	func take_damage(n: int) -> void:
		order.append("damage")   # records WHEN the hit actually lands
		hp -= n
	func heal(_n: int) -> void:
		pass

class MockBoard:
	var placements: Array = []
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)
	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team


func test_damage_is_announced_before_the_target_can_die():
	var order: Array = []

	# A bare RefCounted is enough -- it only needs has_signal/emit_signal, not the tree.
	var bus := MockBus.new()
	bus.damage_dealt.connect(func(_a, _b, _c): order.append("announce"))

	var caster := MockUnit.new(0, order)
	var victim := MockUnit.new(1, order)
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(victim, Vector2i(0, 1))

	var move := MoveResource.new()
	move.accuracy = 1.0
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 1
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern

	var dmg := DamageEffect.new()
	dmg.power = 30
	dmg.scaling_stat = ""
	dmg.scale = 0.0
	move.effects = [dmg]

	var aim := Vector2i(0, 1)
	var ctx := MoveContext.new(caster, board, move, aim, [aim] as Array[Vector2i])
	ctx.event_bus = bus  # route the announcement through our mock bus
	dmg.apply(ctx)

	assert_eq(order, ["announce", "damage"],
		"the attacker must be announced BEFORE the hit lands, so a lethal blow can still be attributed (ON_KILL)")
