extends GutTest

## The CONTACT OPENING of a story wild duel (rules["opening"], set when the hero touched a visible
## wild creature): "ambush" = the player acts first in round 1 whatever the speeds, "ambushed" =
## the foe does; from round 2 speed decides again. No opening = the usual speed order.


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null


## Vineweave (speed 12) for the player vs Geode (speed 8) as the foe.
func _battle(opening: String) -> DuelBattle:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight")
	req.seed = 77
	req.foe_is_ai = false
	if not opening.is_empty():
		req.rules["opening"] = opening
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(req)
	assert_true(bool(ok["success"]), str(ok.get("reason", "")))
	battle.start()
	return battle


func test_no_opening_is_speed_order() -> void:
	var b := _battle("")
	assert_eq(b.side_of(b.current_actor()), 0, "the faster Vineweave acts first")
	b.teardown()


func test_ambushed_gives_the_foe_the_first_move_in_round_one_only() -> void:
	var b := _battle(DuelRequest.OPENING_AMBUSHED)
	assert_eq(b.side_of(b.current_actor()), 1, "walked into: the slower foe strikes first")
	b.pass_turn()
	assert_eq(b.side_of(b.current_actor()), 0, "then the player")
	b.pass_turn()
	assert_eq(b.round_number(), 2, "round 2")
	assert_eq(b.side_of(b.current_actor()), 0, "speed order again from round 2")
	b.teardown()


func test_ambush_keeps_the_player_first_even_when_slower() -> void:
	var req := DuelRequest.standalone(&"gem_knight", &"vineweave")
	req.seed = 77
	req.foe_is_ai = false
	req.rules["opening"] = DuelRequest.OPENING_AMBUSH
	var b := DuelBattle.new()
	add_child_autofree(b)
	assert_true(bool(b.setup(req)["success"]))
	b.start()
	assert_eq(b.side_of(b.current_actor()), 0, "caught unaware: the slower Geode still opens")
	b.teardown()
