extends GutTest

## HUMANS ON THE TACTICAL BOARD (docs/design/HUMANS.md; DECISIONS.md #54): a human unit's action
## is its weapon attack -- slot 0, resolved through the ordinary MoveExecutor / DamageMath pipeline
## at the weapon's reach -- and the AI plans with it like any move. Mock board (no scene tree).

class MockUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var character_resource: CharacterResource
	func _init(p_team: int, p_stats: Dictionary, chr: CharacterResource = null) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))
		character_resource = chr
	func get_stat(name: String) -> int:
		return int(stats.get(name, 0))
	func get_hp() -> int:
		return hp
	func take_damage(n: int) -> void:
		hp -= n
	func get_moveset_controller():
		return null

class MockBoard:
	var placements: Array = []
	func place(unit, cell: Vector3i) -> void:
		placements.append({"unit": unit, "cell": cell})
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
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out


## A sure-hit copy of [param id] (hit 1.0, no crit) so a strike's number is exact.
func _sure(id: StringName) -> WeaponResource:
	var w := WeaponLibrary.get_weapon(id).duplicate() as WeaponResource
	w.hit = 1.0
	w.crit = 0.0
	return w


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 12345
	return r


func test_a_human_unit_exposes_its_weapon_kit() -> void:
	var unit := Unit.new()
	unit.character_resource = CharacterLibrary.get_character(&"wren")
	assert_eq(unit.get_moveset().size(), 1)
	assert_eq(unit.get_move(0).move_id, &"weapon_pitchfork")
	assert_null(unit.get_move(1))
	unit.free()


func test_equip_weapon_swaps_the_strike_on_a_private_copy() -> void:
	var unit := Unit.new()
	var roster := CharacterLibrary.get_character(&"varden")
	unit.character_resource = roster
	var r := unit.equip_weapon(WeaponLibrary.get_weapon(&"iron_lance"))
	assert_true(bool(r["success"]), str(r))
	assert_eq(unit.get_move(0).move_id, &"weapon_iron_lance")
	assert_ne(unit.character_resource, roster, "a private copy (rule 7)")
	assert_eq(roster.weapon.weapon_id, &"iron_sword", "the roster entry is untouched")
	assert_eq(String(unit.equip_weapon(WeaponLibrary.get_weapon(&"study_tome"))["reason"]), "cannot_wield")
	unit.character_resource = CharacterLibrary.get_character(&"tree_grunt")
	assert_eq(String(unit.equip_weapon(WeaponLibrary.get_weapon(&"iron_lance"))["reason"]), "not_human")
	unit.free()


func test_weapon_strike_resolves_through_the_executor() -> void:
	var hero_chr := CharacterLibrary.get_character(&"wren").with_weapon(_sure(&"iron_lance"))
	var hero := MockUnit.new(0, {"attack": 10}, hero_chr)
	var foe := MockUnit.new(1, {"health": 100, "defense": 4})
	var board := MockBoard.new()
	board.place(hero, Vector3i(0, 0, 0))
	board.place(foe, Vector3i(1, 0, 0))
	var move := hero_chr.get_move(0)
	var res := MoveExecutor.execute(move, hero, board, Vector3i(1, 0, 0), _rng())
	assert_true(bool(res["success"]), str(res))
	# might 14 + attack 10 - defense 4 (the ordinary mitigation) vs a creature: no triangle.
	var expected: int = DamageMath.mitigate(14 + 10, foe, CombatTypes.DamageCategory.PHYSICAL)
	assert_eq(100 - foe.hp, expected)
	# The forecast is the same function.
	assert_eq(int(MoveExecutor.preview_vs(move, hero, foe, board)["damage"]), expected)


func test_reach_comes_from_the_weapon() -> void:
	var archer_chr := CharacterLibrary.get_character(&"wren").with_weapon(_sure(&"short_bow"))
	var archer := MockUnit.new(0, {"attack": 10}, archer_chr)
	var near := MockUnit.new(1, {"health": 100})
	var far := MockUnit.new(1, {"health": 100})
	var board := MockBoard.new()
	board.place(archer, Vector3i(0, 0, 0))
	board.place(near, Vector3i(1, 0, 0))
	board.place(far, Vector3i(3, 0, 0))
	var bow := archer_chr.get_move(0)
	assert_eq(String(MoveExecutor.execute(bow, archer, board, Vector3i(1, 0, 0), _rng())["reason"]),
		"out_of_range", "a bow cannot shoot an adjacent foe (min range 2)")
	assert_true(bool(MoveExecutor.execute(bow, archer, board, Vector3i(3, 0, 0), _rng())["success"]))
	assert_lt(far.hp, 100)


func test_triangle_applies_between_human_wielders() -> void:
	var sword_chr := CharacterLibrary.get_character(&"varden").with_weapon(_sure(&"iron_sword"))
	var axe_chr := CharacterLibrary.get_character(&"wren").with_weapon(_sure(&"iron_axe"))
	var lance_chr := CharacterLibrary.get_character(&"wren").with_weapon(_sure(&"iron_lance"))
	var attacker := MockUnit.new(0, {"attack": 20}, sword_chr)
	var axe_man := MockUnit.new(1, {"health": 200, "defense": 0}, axe_chr)
	var lance_man := MockUnit.new(1, {"health": 200, "defense": 0}, lance_chr)
	var board := MockBoard.new()
	board.place(attacker, Vector3i(1, 0, 0))
	board.place(axe_man, Vector3i(0, 0, 0))
	board.place(lance_man, Vector3i(2, 0, 0))
	var move := sword_chr.get_move(0)
	MoveExecutor.execute(move, attacker, board, Vector3i(0, 0, 0), _rng())
	MoveExecutor.execute(move, attacker, board, Vector3i(2, 0, 0), _rng())
	var base: int = 13 + 20
	assert_eq(200 - axe_man.hp, roundi(base * 1.15), "sword beats axe")
	assert_eq(200 - lance_man.hp, roundi(base * 0.85), "lance beats sword")


## Lockstep: the same strikes from the same seed land identically (hit / crit are rolled from the
## injected RNG like any move).
func test_weapon_strikes_are_deterministic() -> void:
	var a: Array = _strike_series(777)
	var b: Array = _strike_series(777)
	assert_eq(a, b)


func _strike_series(seed_value: int) -> Array:
	var chr := CharacterLibrary.get_character(&"wren").with_weapon(WeaponLibrary.get_weapon(&"iron_axe"))
	var hero := MockUnit.new(0, {"attack": 12, "crit": 20}, chr)
	var foe := MockUnit.new(1, {"health": 500, "defense": 3})
	var board := MockBoard.new()
	board.place(hero, Vector3i(0, 0, 0))
	board.place(foe, Vector3i(1, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	for i in range(12):
		MoveExecutor.execute(chr.get_move(0), hero, board, Vector3i(1, 0, 0), rng)
		out.append(foe.hp)
	return out


func test_ai_plans_with_the_weapon_attack() -> void:
	var chr := CharacterLibrary.get_character(&"varden")
	var actor := MockUnit.new(1, {"attack": 20}, chr)
	var foe := MockUnit.new(0, {"health": 100, "defense": 0})
	var board := MockBoard.new()
	board.place(actor, Vector3i(0, 0, 0))
	board.place(foe, Vector3i(1, 0, 0))
	var bot := BotController.new()
	var d := bot.plan(actor, chr.get_moveset(), board, [])
	assert_eq(d["action"], BotController.ActionType.MOVE, "the AI strikes with the weapon")
	assert_eq((d["move"] as MoveResource).move_id, &"weapon_iron_sword")
