extends GutTest

## PARTY DUELS on the stage and in the menus (headless, no window): the hot-seat DuelSetup builds a
## TEAM per player for the chosen format; the DuelHUD shows each side's team pips (fainted /
## fielded), offers the Party action (a picker; Back returns), forces a KO replacement pick (no
## way back; keys 1-6 pick), shows the team preview; and a whole hot-seat Trio duel plays through
## the real stage with switches and replacement picks at the one screen.

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
	# Rebuilt rows / pips are queue_free'd by the UI: let them go before GUT counts orphans.
	await wait_process_frames(2)


func _setup_screen() -> DuelSetup:
	var screen: DuelSetup = (load("res://menus/DuelSetup.gd") as GDScript).new()
	add_child_autofree(screen)
	await wait_process_frames(2)
	return screen


func _stage_for(req: DuelRequest) -> DuelStage:
	DuelController.start(req, false)
	var stage: DuelStage = STAGE.instantiate()
	stage.instant = true
	add_child_autofree(stage)
	await wait_process_frames(3)
	return stage


func test_hot_seat_setup_builds_a_team_per_player_for_the_format() -> void:
	var screen := await _setup_screen()
	assert_eq(screen.build_request().effective_format().team_size, 1, "Singles by default")
	screen.set_format(DuelFormat.TRIO)
	assert_eq(screen.team(0).size(), 3, "Trio: three per side")
	assert_eq(screen.team(1).size(), 3)
	screen.set_team(0, ["vineweave", "gem_knight", "petalfang"])
	screen.set_team(1, ["monster", "monster", "undead"])
	assert_eq(screen.team(1).count("monster"), 1, "the species clause drops the repeat (and refills)")
	screen.edit_slot(0, 2)
	screen._cycle(0, 1)
	assert_ne(screen.team(0)[2], "petalfang", "the carousel edits the selected team slot")
	assert_eq(screen.team(0)[0], "vineweave", "the lead is untouched")
	var slots := screen.find_child("TeamSlots0", true, false) as HBoxContainer
	assert_not_null(slots, "the team slot chips")
	assert_eq(slots.get_children().filter(func(c): return c.visible).size(), 3, "one chip per member")
	var req := screen.build_request()
	assert_eq(req.kind, DuelRequest.KIND_VERSUS)
	assert_eq(req.player_party.size(), 3, "player 1's team")
	assert_eq(req.foe_party.size(), 3, "player 2's team")
	assert_eq(req.effective_format().id, DuelFormat.TRIO)
	assert_true(bool(req.validate()["success"]), "a legal Trio request")
	screen.set_format(DuelFormat.FULL)
	assert_eq(screen.team(0).size(), 6, "Full: six per side")
	assert_eq(screen.team(0)[0], "vineweave", "the team is refitted, members kept")
	var res: Dictionary = DuelController.start(screen.build_request(), false)
	assert_true(bool(res["success"]), "the controller accepts the Full-party request")


func test_the_hud_shows_team_pips_and_the_party_picker() -> void:
	var req := DuelRequest.teams(["vineweave", "gem_knight", "petalfang"], ["gem_knight", "blightcap", "monster"],
		DuelFormat.preset(DuelFormat.TRIO))
	req.kind = DuelRequest.KIND_VERSUS
	req.player_is_ai = false
	req.foe_is_ai = false
	req.seed = 11
	var stage := await _stage_for(req)
	var hud := stage.hud
	assert_true(hud.player_card.party_strip.visible, "the player's team pips")
	assert_eq(hud.player_card.party_strip.get_child_count(), 3)
	assert_true(bool(hud.player_card.party_strip.pip_states()[0]["active"]), "the lead is ringed")
	# Team preview (both teams).
	hud.show_team_preview(["P1", "P2"])
	assert_true(hud.team_preview_visible(), "the team preview")
	var preview_text := _labels(hud).to_upper()
	assert_true(preview_text.contains("P1") and preview_text.contains("P2"), "both sides named")
	hud.hide_team_preview()
	# Wait for side A's prompt.
	var n := 0
	while not hud._accepting and n < 200:
		n += 1
		await get_tree().process_frame
	assert_true(hud._accepting, "a player is prompted")
	var party_btn := hud.find_child("PartyButton", true, false) as Button
	assert_false(party_btn.disabled, "the Party action is enabled")
	hud.open_party()
	assert_true(hud.party_open(), "the party picker is up")
	var grid := hud.find_child("PartyGrid", true, false) as GridContainer
	assert_eq(grid.get_child_count(), 3, "one row per member")
	assert_true((grid.get_child(0) as Button).disabled, "the fielded member cannot come in")
	hud.close_party()
	assert_false(hud.party_open(), "Back returns to the moves")
	assert_true(hud.find_child("MoveGrid", true, false).visible)
	var side := stage.battle.side_of(hud._actor)
	var before = stage.battle.unit_of(side)
	hud.open_party()
	hud.choose_member(2)
	await wait_process_frames(4)
	assert_ne(stage.battle.unit_of(side), before, "the switch applied")
	assert_eq(stage.battle.active_index(side), 2)
	assert_eq(int(stage.battle.result.commands[0][NetProtocol.KEY_TYPE]), NetProtocol.Action.SWITCH)
	var card := hud.card_for(side)
	assert_eq(card.unit, stage.battle.unit_of(side), "the side's card follows the newcomer")


func test_a_ko_opens_the_replacement_picker_with_no_way_back() -> void:
	var req := DuelRequest.teams(["vineweave", "gem_knight"], ["petalfang", "blightcap", "tree_grunt"],
		DuelFormat.preset(DuelFormat.TRIO))
	req.kind = DuelRequest.KIND_VERSUS
	req.player_is_ai = false
	req.foe_is_ai = false
	req.seed = 5
	req.foe_party[0].current_hp = 1
	var stage := await _stage_for(req)
	var hud := stage.hud
	var n := 0
	while not hud._accepting and n < 200:
		n += 1
		await get_tree().process_frame
	# Vineweave's sure hit KOs the 1-HP Petalfang.
	var actor = hud._actor
	var slot := -1
	for s in stage.battle.legal_slots(actor):
		var f := MoveExecutor.preview_vs(actor.get_move(s), actor, stage.battle.foe_of(actor), stage.battle.board)
		if float(f.get("hit_pct", 0.0)) >= 100.0 and int(f.get("damage", 0)) > 0:
			slot = s
			break
	hud._choose(slot)
	n = 0
	while not hud.party_open() and n < 200:
		n += 1
		await get_tree().process_frame
	assert_true(hud.party_open(), "the replacement picker opened")
	assert_eq(hud.replacement_side, 1, "for side B (Player 2)")
	assert_false((hud.find_child("PartyBack", true, false) as Button).visible, "no way back")
	hud.close_party()
	assert_true(hud.party_open(), "Back does nothing: a pick must be made")
	var caption := (hud.find_child("PartyPicker", true, false).find_child("Caption", true, false) as Label).text
	assert_true(caption.contains("PLAYER 2"), "the shared-screen prompt names the player: %s" % caption)
	assert_true((hud.find_child("PartyGrid", true, false).get_child(0) as Button).disabled, "the fainted lead is disabled")
	var key := InputEventKey.new()
	key.keycode = KEY_3
	key.pressed = true
	hud._unhandled_input(key)
	await wait_process_frames(4)
	assert_false(hud.party_open(), "key 3 picked")
	assert_eq(String(stage.battle.unit_of(1).character_resource.character_id), "tree_grunt", "Tree Grunt came in")
	assert_true(bool(hud.foe_card.party_strip.pip_states()[0]["fainted"]), "the foe's pips mark the fainted lead")


func test_a_hot_seat_trio_plays_through_with_switches_and_picks() -> void:
	var screen := await _setup_screen()
	screen.set_format(DuelFormat.TRIO)
	screen.set_team(0, ["vineweave", "gem_knight", "petalfang"])
	screen.set_team(1, ["gem_knight", "blightcap", "monster"])
	var req := screen.build_request()
	req.seed = 1234
	var stage := await _stage_for(req)
	var hud := stage.hud
	var switched := 0
	var picked := 0
	var n := 0
	while not stage.battle.is_over and n < 1500:
		n += 1
		await get_tree().process_frame
		if hud.party_open() and hud.replacement_side >= 0:
			var bench := stage.battle.usable_bench(hud.replacement_side)
			hud.choose_member(bench[0])
			picked += 1
			continue
		if not hud._accepting:
			continue
		var actor = hud._actor
		if switched < 2 and stage.battle.can_switch(actor) and n % 3 == 0:
			hud.open_party()
			hud.choose_member(stage.battle.usable_bench(stage.battle.side_of(actor))[0])
			switched += 1
			continue
		hud._choose(stage.battle.legal_slots(actor)[0])
	assert_true(stage.battle.is_over, "the Trio is decided at the one screen")
	assert_gt(switched, 0, "players switched")
	assert_gt(picked, 0, "and picked KO replacements")
	var out := stage.battle.result
	assert_true(out.winner_side == 0 or out.winner_side == 1, "somebody won")
	assert_true(stage.battle.is_side_out(1 - out.winner_side), "the loser has nobody left")


func _labels(root: Node) -> String:
	var out := ""
	if root is Label:
		out += (root as Label).text + "\n"
	for c in root.get_children():
		out += _labels(c)
	return out
