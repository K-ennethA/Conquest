extends GutTest

## EVOLUTION AUTO-OFFERS, EVOLVE LATER and HOLD (docs/design/DECISIONS.md #26, #27; EVOLUTION.md
## §3.2a) against the live StoryController autoload and real Controls:
##   * the post-battle offer respects Hold (and still offers when Hold is off);
##   * "Not now" -> evolve later from Journey -> Party (the member card's checklist + EVOLVE);
##   * the Party card's Hold toggle is saved;
##   * Journey -> Bag -> Use: an evolution item offers the screen and is spent only on Evolve;
##   * a Location requirement is offered on ENTERING the area (and not re-asked every step);
##   * a flag set by the story offers a StoryFlag edge;
##   * save / reload keeps Hold and the battle-feat counters (story slot + RosterLedger);
##   * Character Select's detail block shows the checklist and the Hold toggle.
## Example edges come from tests/helpers/evolution_examples (EvolutionLibrary.add_extra_edges).
## Saves, the roster and the item store go to temp paths (tests/README.md rules 3 and 4).

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const CHARACTER_SELECT := preload("res://menus/CharacterSelect.tscn")
const SUNSTONE_EDGE := "res://tests/helpers/evolution_examples/example_sunstone.tres"
const PROMOTION_EDGE := "res://tests/helpers/evolution_examples/example_location_promotion.tres"
const TEMP_DIR := "user://test_evolution_offers/"
const TEMP_ROSTER := "user://test_evolution_offers_roster.json"
const TEMP_ITEMS := "user://test_evolution_offers_items.json"

var _guard
var _screens: Array = []


func before_all() -> void:
	RosterLedger.set_save_path(TEMP_ROSTER)
	ItemInventory.set_save_path(TEMP_ITEMS)


func after_all() -> void:
	for path in [TEMP_ROSTER, TEMP_ITEMS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	RosterLedger.set_save_path(RosterLedger.DEFAULT_SAVE_PATH)
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	for k in ["selected_map_path", "selected_squad", "game_mode", "ai_difficulty", "player_count",
			"player_names", "selected_turn_system"]:
		_guard.watch_setting(k)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	RosterLedger.reset()
	ItemInventory.reset()
	EvolutionLibrary.clear_extra_edges()
	StoryController.end_session()
	StoryController.scene_changes_enabled = false
	_screens = []
	StoryController.evolution_offered.connect(_on_offered)


func after_each() -> void:
	if StoryController.evolution_offered.is_connected(_on_offered):
		StoryController.evolution_offered.disconnect(_on_offered)
	for s in _screens:
		if is_instance_valid(s):
			s.free()
	get_tree().paused = false
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	EvolutionLibrary.clear_extra_edges()
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	RosterLedger.reset()
	ItemInventory.reset()
	GrowthTracker.begin_battle_log()
	_guard.restore()
	await get_tree().process_frame


func _on_offered(screen) -> void:
	_screens.append(screen)


func _await_until(pred: Callable, max_frames: int = 60) -> bool:
	for i in range(max_frames):
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return bool(pred.call())


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## A saved journey (slot 1) whose party is exactly [param ids], standing in [param area].
func _journey(ids: Array, area: String = "mossway") -> StoryState:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	s.party.clear()
	for id in ids:
		s.add_member(String(id))
	var a := StoryController.load_area(area)
	s.set_location(area, a.entry(a.entry_ids()[0])["cell"], "south")
	s.drain_changes()
	return s


func _menu(s: StoryState) -> JourneyMenu:
	var jm := JourneyMenu.new()
	jm.session = StoryController
	add_child_autofree(jm)
	jm.open(s)
	return jm


func _bram_request() -> BattleRequest:
	var moss := load(StoryController.area_path("mossway")) as OverworldAreaResource
	var bram := moss.entity("bram") as TrainerEntity
	return bram.battle.to_request(BattleRequest.SOURCE_TRAINER, bram.encounter_id("mossway"))


## Win Bram's battle (staged, not booted) and walk back to the overworld: the post-battle hook.
func _win_and_return() -> void:
	var req := _bram_request()
	assert_true(bool(StoryController.begin_battle(req, false)["success"]), "the battle stages")
	var r := BattleResult.make(req.encounter_id, BattleResult.OUTCOME_VICTORY)
	for p in req.party:
		r.party_after.append({"member_id": String(p["member_id"]), "current_hp": StoryPartyMember.HP_FULL,
			"wounded": false, "fought": true, "kos": 1})
	assert_true(bool(StoryController.report_battle_result(r)["success"]), "reported once")
	StoryController.on_end_action(StoryController.ACTION_CONTINUE)
	StoryController.overworld_ready(null)


func _ready_barkling(s: StoryState, hold: bool) -> StoryPartyMember:
	var bark: StoryPartyMember = s.member("tree_grunt")
	bark.add_growth(2)
	bark.add_feats({"wins": 1})
	bark.hold = hold
	return bark


# --- Post-battle offer + Hold -------------------------------------------------------------

func test_the_post_battle_offer_respects_hold() -> void:
	var s := _journey(["tree_grunt"])
	var bark := _ready_barkling(s, true)
	_win_and_return()
	await _frames(12)
	assert_eq(bark.growth_points(), 3, "the win brought Growth 3")
	assert_eq(int(bark.feats()["wins"]), 2, "and the second win")
	assert_eq(_screens.size(), 0, "Hold: no automatic Evolution screen after the battle")
	assert_eq(bark.character_id, "tree_grunt", "nothing evolved")
	assert_eq((StoryGrowth.menu_edges(bark, StoryGrowth.evolution_context(s))["edges"] as Array).size(), 1,
		"the evolution is waiting in Journey -> Party")


func test_the_post_battle_offer_appears_without_hold() -> void:
	var s := _journey(["tree_grunt"])
	var bark := _ready_barkling(s, false)
	_win_and_return()
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty()), "offered after the battle")
	if _screens.is_empty():
		return
	var evo: EvolutionScreen = _screens[0]
	assert_eq(evo.uid, "tree_grunt", "for the Barkling")
	assert_true(evo.later_hint_visible(), "the prompt says where to find it after Not now")
	evo.decline()
	await _frames(2)
	assert_eq(bark.character_id, "tree_grunt", "Not now changes nothing")


# --- Not now -> evolve later from Journey -> Party ------------------------------------------

func test_not_now_then_evolve_later_from_the_party_page() -> void:
	var s := _journey(["tree_grunt", "vineweave"])
	var bark: StoryPartyMember = s.member("tree_grunt")
	bark.add_growth(3)
	bark.add_feats({"wins": 2})
	StoryController.offer_pending_evolutions({"trigger": "after_battle"})
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty()), "offered")
	if _screens.is_empty():
		return
	(_screens[0] as EvolutionScreen).decline()
	await _frames(2)
	assert_eq(bark.character_id, "tree_grunt", "declined")

	var jm := _menu(s)
	jm.show_party()
	var card := jm.member_card("tree_grunt")
	assert_not_null(card, "the Barkling has a card")
	var rows: Array = card.find_children("Req_*", "", true, false)
	assert_eq(rows.size(), 2, "its checklist lists both requirements")
	for r in rows:
		assert_true(bool(r.get_meta(&"met")), "and both are met")
	assert_not_null(card.find_child("Ready", true, false), "marked READY")
	var vine := jm.member_card("vineweave")
	assert_null(vine.find_child("EvolveButton", true, false), "a unit in no line has no EVOLVE")
	var btn := card.find_child("EvolveButton", true, false) as Button
	assert_not_null(btn, "the pending evolution is listed with EVOLVE")
	if btn == null:
		return
	assert_eq(btn.text, "Evolve", "worded for a creature")
	btn.pressed.emit()
	assert_true(await _await_until(func() -> bool: return _screens.size() >= 2), "EVOLVE opens the screen again")
	if _screens.size() < 2:
		return
	var evo: EvolutionScreen = _screens[1]
	assert_true(bool(evo.confirm().get("success", false)), "Evolve commits")
	evo.dismiss()
	evo.dismiss()
	assert_true(await _await_until(func() -> bool: return bark.character_id == "oakheart"), "the member became Oakheart")
	await _frames(2)
	var after := jm.member_card("tree_grunt")
	assert_not_null(after, "the page was rebuilt")
	assert_not_null(after.find_child("FinalForm", true, false), "Oakheart is a final form: no checklist")
	assert_eq(String(StorySaveManager.peek(1)["party"][0]["character_id"]), "oakheart", "and the journey saved it")


func test_the_party_card_checklist_shows_progress_and_hold_saves() -> void:
	var s := _journey(["tree_grunt"])
	var bark: StoryPartyMember = s.member("tree_grunt")
	bark.add_growth(3)
	bark.add_feats({"wins": 1})
	var jm := _menu(s)
	jm.show_party()
	var card := jm.member_card("tree_grunt")
	assert_null(card.find_child("EvolveButton", true, false), "no EVOLVE while a requirement is missing")
	var rows: Array = card.find_children("Req_*", "", true, false)
	assert_true(bool(rows[0].get_meta(&"met")), "Growth 3 met")
	assert_false(bool(rows[1].get_meta(&"met")), "2 wins not yet")
	var prog := rows[1].find_child("Progress", true, false) as Label
	assert_eq(prog.text, "1/2", "with its progress")
	var hold := card.find_child("HoldToggle", true, false) as CheckButton
	assert_not_null(hold, "a Hold toggle")
	var party_row := jm.find_child("PartyRow", true, false) as Button
	var right: Node = party_row.get_node_or_null(party_row.focus_neighbor_right)
	assert_true(right != null and card.is_ancestor_of(right), "keyboard / pad: right from the Party row enters the page")
	assert_false(hold.button_pressed, "off by default")
	hold.button_pressed = true
	await _frames(2)
	assert_true(bark.hold, "the toggle holds the member")
	assert_true(bool(StorySaveManager.peek(1)["party"][0]["hold"]), "and the journey saved it")
	var again := jm.member_card("tree_grunt")
	assert_not_null(again.find_child("HoldNote", true, false), "the card says it is on hold")


# --- UseItem from the bag -----------------------------------------------------------------

func test_using_an_item_from_the_bag_offers_the_evolution_and_spends_it() -> void:
	EvolutionLibrary.add_extra_edges([load(SUNSTONE_EDGE)])
	var s := _journey(["vineweave", "tree_grunt"])
	s.add_item("sunstone", 2)
	var jm := _menu(s)
	jm.show_bag()
	var item_card: Node = jm.find_child("Item_sunstone", true, false)
	assert_not_null(item_card, "the Sunstone is in the bag")
	var on_bark := item_card.find_child("Use_tree_grunt", true, false) as Button
	var on_vine := item_card.find_child("Use_vineweave", true, false) as Button
	assert_true(on_bark != null and on_vine != null, "with a Use button per member")

	on_bark.pressed.emit()
	await _frames(2)
	assert_eq(_screens.size(), 0, "no effect on a Barkling: no screen")
	assert_eq(s.item_count("sunstone"), 2, "and the stone is kept")

	on_vine = jm.find_child("Item_sunstone", true, false).find_child("Use_vineweave", true, false) as Button
	on_vine.pressed.emit()
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty()), "using it offers the evolution")
	if _screens.is_empty():
		return
	var evo: EvolutionScreen = _screens[0]
	assert_true(evo.uses_text().contains("Sunstone"), "the prompt says it uses the Sunstone")
	evo.decline()
	await _frames(2)
	assert_eq(s.item_count("sunstone"), 2, "Not now keeps the stone")
	assert_eq(s.member("vineweave").character_id, "vineweave", "and the member")

	var r: Dictionary = await _use_and_confirm("sunstone", "vineweave")
	assert_true(bool(r.get("evolved", false)), "confirmed")
	assert_eq(s.member("vineweave").character_id, "petalfang", "the Sunstone evolved it")
	assert_eq(s.item_count("sunstone"), 1, "and one stone was spent")


func _use_and_confirm(item_id: String, member_id: String) -> Dictionary:
	var before: int = _screens.size()
	var state := {"r": {}}
	var run := func() -> void:
		state["r"] = await StoryController.use_item_on_member(item_id, member_id)
	run.call()
	await _await_until(func() -> bool: return _screens.size() > before)
	if _screens.size() > before:
		var evo: EvolutionScreen = _screens[before]
		evo.confirm()
		evo.dismiss()
		evo.dismiss()
	await _await_until(func() -> bool: return not (state["r"] as Dictionary).is_empty())
	return state["r"]


func test_the_party_evolve_button_uses_a_bag_item_when_that_completes_it() -> void:
	EvolutionLibrary.add_extra_edges([load(SUNSTONE_EDGE)])
	var s := _journey(["vineweave"])
	var jm := _menu(s)
	jm.show_party()
	assert_null(jm.member_card("vineweave").find_child("EvolveButton", true, false), "no stone: nothing due")
	s.add_item("sunstone", 1)
	jm.refresh_party()
	var card := jm.member_card("vineweave")
	var btn := card.find_child("EvolveButton", true, false) as Button
	assert_not_null(btn, "with a stone in the bag the evolution is due")
	var ready := card.find_child("Ready", true, false)
	assert_not_null(ready, "the checklist says READY WITH SUNSTONE")
	btn.pressed.emit()
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty()), "EVOLVE opens the screen")
	if _screens.is_empty():
		return
	var evo: EvolutionScreen = _screens[0]
	assert_true(bool(evo.confirm().get("success", false)), "Evolve commits with the stone")
	evo.dismiss()
	evo.dismiss()
	await _frames(2)
	assert_eq(s.member("vineweave").character_id, "petalfang", "evolved")
	assert_eq(s.item_count("sunstone"), 0, "the stone was spent")


# --- Location: offered on entering the area -------------------------------------------------

func test_a_location_promotion_is_offered_on_entering_the_area() -> void:
	EvolutionLibrary.add_extra_edges([load(PROMOTION_EDGE)])
	var s := _journey(["blightcap"])
	var cap: StoryPartyMember = s.member("blightcap")
	cap.add_growth(1)
	StoryController.offer_pending_evolutions({"trigger": "after_battle"})
	await _frames(2)
	assert_eq(_screens.size(), 0, "on the Mossway the promotion is not due")
	var crown_entry: String = StoryController.load_area("crownhaven").entry_ids()[0]
	assert_true(bool(StoryController.warp_to("crownhaven", crown_entry)["success"]), "walk into Crownhaven")
	assert_true((StoryController.pending_evolution_event().get("kinds", []) as Array).has("area"),
		"arriving is an auto-offer event")
	StoryController.flush_evolution_events()
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty()), "the promotion is offered on arrival")
	if _screens.is_empty():
		return
	var evo: EvolutionScreen = _screens[0]
	assert_eq(evo.evolve_button.text, "Promote", "worded as a promotion")
	assert_true(evo.ribbon_text().contains("is being promoted"), "the ribbon too")
	evo.decline()
	await _frames(2)

	# No nag loop: nothing new -> nothing asked; an unrelated event does not re-ask it.
	StoryController.flush_evolution_events()
	await _frames(2)
	assert_eq(_screens.size(), 1, "no event, no offer")
	s.set_flag("some.unrelated.flag", true)
	StoryController.flush_evolution_events()
	await _frames(2)
	assert_eq(_screens.size(), 1, "an unrelated flag does not re-ask a Location promotion")

	# A NEW arrival does.
	var moss_entry: String = StoryController.load_area("mossway").entry_ids()[0]
	StoryController.warp_to("mossway", moss_entry)
	StoryController.flush_evolution_events()
	await _frames(2)
	assert_eq(_screens.size(), 1, "leaving: not due there")
	StoryController.warp_to("crownhaven", crown_entry)
	StoryController.flush_evolution_events()
	assert_true(await _await_until(func() -> bool: return _screens.size() == 2), "coming back offers it again")
	if _screens.size() < 2:
		return
	(_screens[1] as EvolutionScreen).decline()
	await _frames(2)

	# Hold stops even the arrival prompt.
	cap.hold = true
	StoryController.warp_to("mossway", moss_entry)
	StoryController.warp_to("crownhaven", crown_entry)
	StoryController.flush_evolution_events()
	await _frames(3)
	assert_eq(_screens.size(), 2, "on Hold: no prompt on arrival")


func test_a_flag_set_by_the_story_offers_a_story_flag_edge() -> void:
	var trig := StoryFlagTrigger.new()
	trig.flag = "test.grove_blessing"
	trig.label = "Receive the grove's blessing"
	var edge := EvolutionResource.new()
	edge.id = &"test__petalfang_blessing"
	edge.from_id = &"petalfang"
	edge.to_id = &"monster"
	var reqs: Array[EvolutionTrigger] = [trig]
	edge.triggers = reqs
	EvolutionLibrary.add_extra_edges([edge])
	var s := _journey(["petalfang"])
	StoryController.flush_evolution_events()
	await _frames(2)
	assert_eq(_screens.size(), 0, "nothing before the flag")
	s.set_flag("test.grove_blessing", true)
	StoryController.flush_evolution_events()
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty()), "setting the flag offers it")
	if not _screens.is_empty():
		(_screens[0] as EvolutionScreen).decline()


# --- Save / reload --------------------------------------------------------------------------

func test_save_and_reload_keep_hold_and_feat_counters() -> void:
	var s := _journey(["tree_grunt"])
	var bark: StoryPartyMember = s.member("tree_grunt")
	bark.hold = true
	bark.add_feats({"wins": 3, "kos": 2, "clutch_wins": 1, "element_kos": {"dark": 2}})
	assert_true(bool(StoryController.save_game()["success"]), "saves")
	var loaded: Dictionary = StorySaveManager.load_state(1)
	assert_true(bool(loaded["success"]), "reloads")
	var back: StoryPartyMember = (loaded["state"] as StoryState).member("tree_grunt")
	assert_true(back.hold, "Hold survives")
	var f: Dictionary = back.feats()
	assert_eq(int(f["wins"]), 3, "wins survive")
	assert_eq(int(f["clutch_wins"]), 1, "clutch wins survive")
	assert_eq(f["element_kos"], {"dark": 2}, "element KOs survive")
	# The open-mode ledger keeps them too.
	RosterLedger.set_hold("vineweave", true)
	RosterLedger.add_feats("vineweave", {"kos": 4})
	assert_true(RosterLedger.save(), "the ledger saves")
	RosterLedger.set_save_path(TEMP_ROSTER)
	assert_true(RosterLedger.is_held("vineweave"), "ledger Hold survives")
	assert_eq(int(RosterLedger.feats_of("vineweave")["kos"]), 4, "ledger KOs survive")


func test_an_old_v2_save_without_hold_loads_with_hold_off() -> void:
	var s := _journey(["tree_grunt"])
	assert_true(bool(StoryController.save_game()["success"]), "saves")
	var data: Dictionary = StorySaveManager.peek(1)
	for m in data["party"]:
		(m as Dictionary).erase("hold")
		((m as Dictionary)["growth"] as Dictionary).erase("feats")
	assert_eq(int(data["format_version"]), 2, "still format v2 (no version bump)")
	var restored: Dictionary = StorySnapshot.from_dict(data)
	assert_true(bool(restored["success"]), "an older v2 save loads")
	var m: StoryPartyMember = (restored["state"] as StoryState).member("tree_grunt")
	assert_false(m.hold, "with Hold off")
	assert_eq(int(m.feats()["wins"]), 0, "and zero feats")
	assert_eq(s.member("tree_grunt").member_id, m.member_id, "the same member")


# --- Character Select (open modes) -----------------------------------------------------------

func test_character_select_shows_the_checklist_and_hold() -> void:
	RosterLedger.add_growth("tree_grunt", 3)
	RosterLedger.add_feats("tree_grunt", {"wins": 1})
	var cs = CHARACTER_SELECT.instantiate()
	add_child_autofree(cs)
	await get_tree().process_frame
	cs._show_detail("tree_grunt")
	var block := cs.find_child("EvolutionBlock", true, false) as EvolutionDetailBlock
	assert_not_null(block, "the detail pane's Growth block")
	var rows: Array = block.checklist_rows()
	assert_eq(rows.size(), 2, "the checklist lists both requirements")
	assert_true(bool(rows[0]["met"]), "Growth met")
	assert_false(bool(rows[1]["met"]), "the wins not yet")
	assert_false(block.evolve_button.visible, "no EVOLVE while a requirement is missing")
	assert_true(block.hold_toggle.visible, "a Hold toggle")
	block.hold_toggle.button_pressed = true
	assert_true(RosterLedger.is_held("tree_grunt"), "Hold writes the ledger member")
	RosterLedger.add_feats("tree_grunt", {"wins": 1})
	cs._show_detail("vineweave")
	cs._show_detail("tree_grunt")
	assert_true(block.evolve_button.visible, "both met: EVOLVE (Hold never hides the manual button)")
	assert_true(block.hold_toggle.button_pressed, "the toggle shows the saved Hold")
	for r in block.checklist_rows():
		assert_true(bool(r["met"]), "every row is met")
