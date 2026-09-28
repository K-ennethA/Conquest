extends GutTest

## Solo -> Duel (docs/design/DUEL_BATTLE.md §9): the Solo picker offers a Duel card that
## goes to DuelSetup; DuelSetup lists only duel-eligible units, cycles them, and builds the
## standalone request DuelController starts.


func before_each() -> void:
	DuelController.reset()


func after_each() -> void:
	DuelController.reset()


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


func test_solo_picker_offers_the_duel_card() -> void:
	var screen := await _open("res://menus/SoloModeSelect.gd")
	var card := _find_named(screen, "DuelCard") as Button
	assert_not_null(card, "a Duel card on the Solo picker")
	var targets: Array = card.pressed.get_connections().map(func(c): return c["callable"].get_method())
	assert_true("_on_duel_chosen" in targets, "it opens DuelSetup")
	assert_eq(SoloModeSelect.DUEL_SETUP_SCENE, "res://menus/DuelSetup.tscn")
	assert_true(ResourceLoader.exists(SoloModeSelect.DUEL_SETUP_SCENE))
	assert_eq(MatchConfigPanel.MODE_DUEL, "duel")


func test_setup_lists_only_eligible_units() -> void:
	var ids := DuelSetup.eligible_ids()
	assert_false(&"bastion" in ids, "a pure self-guard kit is not offered")
	assert_true(&"vineweave" in ids and &"gem_knight" in ids)


func test_setup_defaults_to_the_slice_and_builds_a_request() -> void:
	var screen: DuelSetup = await _open("res://menus/DuelSetup.gd")
	var req := screen.build_request()
	assert_eq(req.player_party[0].character_id, &"vineweave", "the M1 slice by default")
	assert_eq(req.foe_party[0].character_id, &"gem_knight")
	assert_eq(req.ai_difficulty, DuelBrain.NORMAL)
	assert_eq(req.seed, 0, "fresh entropy at the fight")
	assert_true(bool(req.validate()["success"]))
	screen._cycle(1, 1)
	assert_ne(screen.build_request().foe_party[0].character_id, &"gem_knight", "the foe carousel cycles")
	screen._kind_opt.select(1)
	assert_true(screen.build_request().is_wild(), "a wild encounter can be picked")
	var res: Dictionary = DuelController.start(screen.build_request(), false)
	assert_true(bool(res["success"]), "and DuelController accepts what the screen builds")
	assert_not_null(_find_named(screen, "BackButton"), "Back is there")
