extends GutTest

## DuelTurnSystem (docs/design/DUEL_BATTLE.md §4.1): the faster combatant acts first, the
## order is re-sorted every round by CURRENT speed (Stone Sling's slow flips it), and a speed
## tie is a seeded coin per round -- identical across runs with one seed, different across
## seeds (the name compare it replaces is unstable in a mirror match).


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null


func _battle(a: StringName, b: StringName, seed_value: int) -> DuelBattle:
	var req := DuelRequest.standalone(a, b)
	req.seed = seed_value
	req.foe_is_ai = false
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(req)
	assert_true(bool(ok["success"]), str(ok.get("reason", "")))
	battle.start()
	return battle


func _slot(unit, move_id: StringName) -> int:
	for i in range(unit.character_resource.move_count()):
		if unit.get_move(i).move_id == move_id:
			return i
	return -1


func test_faster_acts_first_whichever_side_it_is_on() -> void:
	var b1 := _battle(&"vineweave", &"gem_knight", 11)
	assert_eq(b1.current_actor(), b1.unit_of(0), "Vineweave (12) before Geode (8)")
	b1.teardown()
	var b2 := _battle(&"gem_knight", &"vineweave", 11)
	assert_eq(b2.current_actor(), b2.unit_of(1), "still Vineweave first from station B")


func test_stone_sling_flips_the_order_next_round() -> void:
	var b := _battle(&"vineweave", &"gem_knight", 12)
	var vw = b.unit_of(0)
	var geode = b.unit_of(1)
	# Lift Geode to 10 so the -4 slow (12 -> 8) is a clean flip rather than a tie.
	geode.add_stat_modifier("speed", 2, -1)
	assert_eq(b.current_actor(), vw, "round 1: Vineweave 12 > Geode 10")
	assert_true(bool(b.submit_slot(_slot(vw, &"thornward")).get("ok", false)))
	assert_eq(b.current_actor(), geode)
	var sling := b.submit_slot(_slot(geode, &"stone_sling"))
	assert_true(bool(sling.get("ok", false)), "Geode slings")
	assert_eq(b.round_number(), 2)
	assert_eq(vw.get_stat("speed"), 8, "Vineweave is slowed to 8")
	assert_eq(b.current_actor(), geode, "round 2: Geode 10 now acts first")


func _first_movers(seed_value: int, rounds: int) -> Array:
	var b := _battle(&"vineweave", &"vineweave", seed_value)
	var firsts: Array = []
	for r in rounds:
		firsts.append(b.side_of(b.current_actor()))
		b.pass_turn()
		b.pass_turn()
	b.teardown()
	return firsts


func test_mirror_tie_break_is_seeded() -> void:
	var a := _first_movers(4242, 8)
	var again := _first_movers(4242, 8)
	assert_eq(a, again, "same seed -> identical order every round: %s" % str(a))
	assert_true(0 in a and 1 in a, "the coin genuinely flips between rounds: %s" % str(a))
	var differs := false
	for s in [1, 2, 3, 5, 8]:
		if _first_movers(s, 8) != a:
			differs = true
			break
	assert_true(differs, "a different seed produces a different order")
