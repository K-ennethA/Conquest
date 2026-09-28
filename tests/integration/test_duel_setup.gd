extends GutTest

## Online > Versus > Duel > Same device (docs/design/DECISIONS.md #31/#32): the HOT-SEAT duel.
## Solo no longer offers a duel; DuelSetup lists only duel-eligible units, cycles them, and
## builds a VERSUS request with a human on both sides -- and the stage then prompts each side's
## player in turn (the move grid shows the ACTING unit's moves) and names the winner.

const STAGE := preload("res://game/duel/DuelStage.tscn")


func before_each() -> void:
	DuelController.reset()
	DuelController.record_profile = false
	CombatServices.clear()


func after_each() -> void:
	DuelController.reset()
	DuelController.record_profile = true
	CombatServices.clear()
	CombatServices.match_rng = null


func _open(script_path: String) -> Control:
	var screen: Control = (load(script_path) as GDScript).new()
	add_child_autofree(screen)
	await wait_process_frames(2)
	return screen


func _find_named(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for c in root.get_children():
		var f := _find_named(c, node_name)
		if f != null:
			return f
	return null


func _labels(root: Node) -> String:
	var out := ""
	if root is Label:
		out += (root as Label).text + "\n"
	for c in root.get_children():
		out += _labels(c)
	return out


func test_solo_no_longer_offers_a_duel() -> void:
	var screen := await _open("res://menus/SoloModeSelect.gd")
	assert_null(_find_named(screen, "DuelCard"), "no Duel card on the Solo picker (duels live in Story)")
	assert_eq(MatchConfigPanel.MODE_DUEL, "duel")
	assert_eq(DuelController.MENU_SCENE, "res://menus/MultiplayerModeSelection.tscn",
		"a standalone duel's Menu returns to Versus, its only menu route")


func test_setup_lists_only_eligible_units() -> void:
	var ids := DuelSetup.eligible_ids()
	assert_false(&"bastion" in ids, "a pure self-guard kit is not offered")
	assert_true(&"vineweave" in ids and &"gem_knight" in ids)
	assert_eq(ids, DuelNetConfig.eligible_ids(), "the same roster online duels use")


func test_setup_builds_a_hot_seat_versus_request() -> void:
	var screen: DuelSetup = await _open("res://menus/DuelSetup.gd")
	var text := _labels(screen).to_upper()
	assert_true(text.contains("PLAYER 1") and text.contains("PLAYER 2"), "two players")
	assert_null(_find_named(screen, "FoeAIOption"), "no AI to configure")
	var req := screen.build_request()
	assert_eq(req.player_party[0].character_id, &"vineweave", "the M1 slice by default")
	assert_eq(req.foe_party[0].character_id, &"gem_knight")
	assert_eq(req.kind, DuelRequest.KIND_VERSUS, "a versus duel")
	assert_false(req.player_is_ai or req.foe_is_ai, "a human on both sides")
	assert_false(req.can_flee() or req.can_befriend(), "no running, no befriend")
	assert_eq(req.seed, 0, "fresh entropy at the fight")
	assert_true(bool(req.validate()["success"]))
	screen._cycle(1, 1)
	assert_ne(screen.build_request().foe_party[0].character_id, &"gem_knight", "player 2's carousel cycles")
	var res: Dictionary = DuelController.start(screen.build_request(), false)
	assert_true(bool(res["success"]), "and DuelController accepts what the screen builds")
	assert_not_null(_find_named(screen, "BackButton"), "Back is there")
	assert_eq(DuelSetup.VERSUS_SCENE, "res://menus/MultiplayerModeSelection.tscn", "Back goes to Versus")


func test_a_hot_seat_duel_prompts_both_players_and_names_the_winner() -> void:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight")
	req.kind = DuelRequest.KIND_VERSUS
	req.player_is_ai = false
	req.foe_is_ai = false
	req.seed = 77
	DuelController.start(req, false)
	var stage: DuelStage = STAGE.instantiate()
	stage.instant = true
	add_child_autofree(stage)
	await wait_process_frames(3)
	assert_true(stage.is_hotseat(), "the stage knows it is hot-seat")
	var prompted := {}
	var n := 0
	while not stage.battle.is_over and n < 400:
		n += 1
		await get_tree().process_frame
		if not stage.hud._accepting:
			continue
		var actor = stage.hud._actor
		var side := stage.battle.side_of(actor)
		prompted[side] = true
		assert_eq(stage.hud.rows[0].move(), actor.get_move(0), "the grid shows the ACTING unit's moves (side %d)" % side)
		stage.hud._choose(stage.battle.legal_slots(actor)[0])
	assert_true(stage.battle.is_over, "the duel is decided")
	assert_eq(prompted.keys().size(), 2, "both players were prompted at the one screen")
	await wait_process_frames(4)
	assert_true(stage.hud.results_visible(), "the results card is up")
	var text := _labels(stage.hud).to_upper()
	var winner := stage.battle.result.winner_side
	if winner >= 0:
		assert_true(text.contains("PLAYER %d WINS" % (winner + 1)), "the results name the winner")
	assert_false(text.contains("DEFEAT"), "nobody at a shared screen reads Defeat")
