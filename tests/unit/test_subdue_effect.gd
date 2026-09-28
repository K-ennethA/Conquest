extends GutTest

## SUBDUE (DECISIONS.md, False-Swipe style): a DamageEffect with subdue = true can never
## reduce its target below 1 HP, logs "subdued" when it leaves the target on exactly 1, and
## the forecast reports the same floor (rule 9: preview and hit share the cap).

const Doubles := preload("res://tests/helpers/test_doubles.gd")


## A target that tracks live HP and a shield (the two things the cap reads).
class HpTarget:
	var team: int
	var hp: int
	var shield: int = 0
	var stats: Dictionary

	func _init(p_team: int, p_hp: int, p_defense: int = 0) -> void:
		team = p_team
		hp = p_hp
		stats = {"health": p_hp, "defense": p_defense, "attack": 40}

	func get_stat(stat_name: String) -> int:
		return hp if stat_name == "health" else int(stats.get(stat_name, 0))

	func get_hp() -> int:
		return hp

	func get_shield() -> int:
		return shield

	func take_damage(n: int) -> void:
		var soak := mini(shield, n)
		shield -= soak
		hp = maxi(0, hp - (n - soak))


func _move(subdue: bool, power: int = 60) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_swipe"
	m.accuracy = 1.0
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	m.targeting = p
	var d := DamageEffect.new()
	d.power = power
	d.scaling_stat = ""
	d.subdue = subdue
	m.effects = [d] as Array[MoveEffect]
	return m


func _cast(move: MoveResource, target: HpTarget) -> Dictionary:
	var caster := HpTarget.new(0, 100)
	var board := Doubles.MinimalBoard.new()
	board.place(caster, Vector3i(0, 0, 0))
	board.place(target, Vector3i(1, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return MoveExecutor.execute(move, caster, board, Vector3i(1, 0, 0), rng)


func _damage_event(res: Dictionary) -> Dictionary:
	for e in res["events"]:
		if String(e.get("effect", "")) == "damage":
			return e
	return {}


func test_subdue_cap_is_one_rule() -> void:
	assert_eq(DamageMath.subdue_cap(30, 0, 50), 29, "a lethal hit stops at 1 HP")
	assert_eq(DamageMath.subdue_cap(30, 0, 10), 10, "a non-lethal hit is untouched")
	assert_eq(DamageMath.subdue_cap(30, 5, 50), 34, "a shield soaks first; still 1 HP left")
	assert_eq(DamageMath.subdue_cap(1, 0, 50), 0, "a target on 1 HP takes nothing")


func test_a_subdue_hit_leaves_the_target_on_one_hp() -> void:
	var target := HpTarget.new(1, 30)
	var ev := _damage_event(_cast(_move(true), target))
	assert_eq(target.hp, 1, "subdue can never KO")
	assert_true(bool(ev.get("subdued", false)), "and the hit is logged as a subdue")
	var shielded := HpTarget.new(1, 30)
	shielded.shield = 5
	_cast(_move(true), shielded)
	assert_eq(shielded.hp, 1, "the cap counts the shield the hit burns through")


func test_a_normal_hit_still_kills_and_logs_no_subdue() -> void:
	var target := HpTarget.new(1, 30)
	var ev := _damage_event(_cast(_move(false), target))
	assert_eq(target.hp, 0)
	assert_false(ev.has("subdued"))
	var tough := HpTarget.new(1, 500)
	var ev2 := _damage_event(_cast(_move(true), tough))
	assert_false(ev2.has("subdued"), "a subdue hit that leaves plenty of HP is no subdue")


func test_forecast_reports_the_same_floor() -> void:
	var caster := HpTarget.new(0, 100)
	var target := HpTarget.new(1, 30)
	var board := Doubles.MinimalBoard.new()
	var plain := MoveExecutor.preview_vs(_move(false), caster, target, board)
	var swipe := MoveExecutor.preview_vs(_move(true), caster, target, board)
	assert_true(bool(plain["lethal"]))
	assert_false(bool(swipe["lethal"]), "the forecast never promises a subdue KO")
	assert_eq(int(swipe["remaining"]), 1)
	assert_true(bool(swipe.get("subdue", false)))
	assert_eq(int(swipe["damage"]), int(plain["damage"]), "the damage number itself is the shared chain's")
