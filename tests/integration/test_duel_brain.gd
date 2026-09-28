extends GutTest

## DuelBrain on real units (docs/design/DUEL_BATTLE.md §5): it takes a lethal when one is
## there, prefers the effective move because it reads the SHARED forecast (preview_vs, rule
## 9), never re-applies a refreshing status, guards only under threat, and EASY is
## reproducible from its seeded stream.


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null


func _battle(a: StringName = &"vineweave", b: StringName = &"gem_knight") -> DuelBattle:
	var req := DuelRequest.standalone(a, b)
	req.seed = 55
	req.foe_is_ai = false
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	assert_true(bool(battle.setup(req)["success"]))
	battle.start()
	return battle


func _slot(unit, move_id: StringName) -> int:
	for i in range(unit.character_resource.move_count()):
		if unit.get_move(i).move_id == move_id:
			return i
	return -1


func test_takes_the_lethal_when_available() -> void:
	var b := _battle()
	var vw = b.unit_of(0)
	var geode = b.unit_of(1)
	geode.shield_hp = 0
	geode.set_stat("health", 6)
	var d := DuelBrain.decide(vw, geode, b.board, b.rules, DuelBrain.NORMAL)
	assert_eq(String(d["reason"]), "lethal", "a forecast KO is taken: %s" % str(d))
	var f := MoveExecutor.preview_vs(vw.get_move(int(d["slot"])), vw, geode, b.board)
	assert_true(bool(f["lethal"]), "the pick really is lethal per the shared forecast")


func test_prefers_the_effective_move_from_the_shared_forecast() -> void:
	var b := _battle()
	var vw = b.unit_of(0)
	var geode = b.unit_of(1)
	# Two otherwise-identical private moves: one earth (resisted by earth), one water (1.25).
	var base: MoveResource = vw.get_move(0)
	var dull := base.duplicate(false) as MoveResource
	dull.move_id = &"test_earth_cleave"
	dull.element = &"earth"
	var sharp := base.duplicate(false) as MoveResource
	sharp.move_id = &"test_water_cleave"
	sharp.element = &"water"
	var set: Array[MoveResource] = [dull, vw.get_move(1), sharp, vw.get_move(3)]
	vw.character_resource.moveset = set
	var mc = vw.get_moveset_controller()
	mc.cooldown_started(vw.get_move(1), 5)
	mc.cooldown_started(vw.get_move(3), 5)
	var d := DuelBrain.decide(vw, geode, b.board, b.rules, DuelBrain.NORMAL)
	assert_eq(int(d["slot"]), 2, "the water cleave (▲ effective) wins: %s" % str(d["scores"]))
	var f_sharp := MoveExecutor.preview_vs(sharp, vw, geode, b.board)
	var f_dull := MoveExecutor.preview_vs(dull, vw, geode, b.board)
	assert_gt(int(f_sharp["damage"]), int(f_dull["damage"]))
	assert_almost_eq(float(d["scores"][2]) - float(d["scores"][0]),
		DuelBrain.expected_damage(f_sharp) - DuelBrain.expected_damage(f_dull), 0.001,
		"the score gap IS the forecast gap -- no second damage formula")


func test_does_not_reapply_a_refreshing_status() -> void:
	var b := _battle()
	var geode = b.unit_of(1)
	var ensnared: StatusCondition = load("res://game/combat/status/ensnared.tres")
	var fresh := DuelBrain._status_value(geode, ensnared, b.rules)
	assert_gt(fresh, 0.0)
	geode.get_status_controller().add_status(ensnared.duplicate(true))
	assert_eq(DuelBrain._status_value(geode, ensnared, b.rules), 0.0,
		"statuses refresh, never stack: nothing to gain (rule 6)")


func test_guards_only_under_threat() -> void:
	var b := _battle()
	var vw = b.unit_of(0)
	var geode = b.unit_of(1)
	var guard := _slot(vw, &"thornward")
	vw.set_stat("health", 20)
	var threatened: float = DuelBrain.score_move(vw, geode, b.board, guard, b.rules)["score"]
	var mc = geode.get_moveset_controller()
	for i in range(geode.character_resource.move_count()):
		mc.cooldown_started(geode.get_move(i), 5)
	var safe: float = DuelBrain.score_move(vw, geode, b.board, guard, b.rules)["score"]
	assert_gt(threatened, safe, "Thornward is worth more while Geode can hurt")
	assert_lte(safe, 0.0, "and nothing (bar its cooldown cost) when it cannot")


func test_easy_is_reproducible_from_its_seed() -> void:
	var b := _battle()
	var vw = b.unit_of(0)
	var geode = b.unit_of(1)
	var picks: Array = []
	for i in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9001
		picks.append(DuelBrain.decide(vw, geode, b.board, b.rules, DuelBrain.EASY, rng)["slot"])
	assert_eq(picks[0], picks[1], "same stream -> same EASY pick")
	var seen: Dictionary = {}
	for s in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		seen[DuelBrain.decide(vw, geode, b.board, b.rules, DuelBrain.EASY, rng)["slot"]] = true
	assert_gt(seen.size(), 1, "EASY genuinely varies across seeds: %s" % str(seen.keys()))
