extends GutTest

## [RosterLedger]: the persistent roster-member store behind evolution (EVOLUTION.md §3.5,
## task 1.3). Pins growth, availability at the goal, what evolve() writes (form, history,
## unlock, the item re-key), the story-member API, corrupt-file recovery and the round trip.
##
## Every test runs against TEMP paths for BOTH stores evolve() writes -- never the player's
## user://roster.json or user://items.json (tests/README.md rule 4).

const LEDGER_PATH := "user://test_evo_roster_ledger.json"
const ITEMS_PATH := "user://test_evo_roster_items.json"
const ITEM := "ironbark_sigil"
const OTHER_ITEM := "heartwood_charm"

var _edge: EvolutionResource = null
var _goal: int = 0


func before_all() -> void:
	RosterLedger.set_save_path(LEDGER_PATH)
	ItemInventory.set_save_path(ITEMS_PATH)
	EvolutionLibrary.rescan()


func before_each() -> void:
	RosterLedger.reset()
	ItemInventory.reset()
	_edge = EvolutionLibrary.get_edge(&"tree_grunt__oakheart")
	_goal = _edge.growth_goal() if _edge != null else 3


func after_each() -> void:
	RosterLedger.reset()
	ItemInventory.reset()


func after_all() -> void:
	for path in [LEDGER_PATH, ITEMS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Back on the real paths, NOT reset(): the next read re-loads the real files lazily, and a
	# blank in-memory ledger can never be saved over the player's.
	RosterLedger.set_save_path(RosterLedger.DEFAULT_SAVE_PATH)
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)


# --- Members + growth ------------------------------------------------------------

func test_every_form_of_a_line_is_one_open_mode_member() -> void:
	assert_eq(RosterLedger.member_for_character("tree_grunt"), "tree_grunt", "a base form's member is its own id")
	assert_eq(RosterLedger.member_for_character("oakheart"), "tree_grunt", "an evolved form resolves to its line's member")
	assert_eq(RosterLedger.member_for_character("vineweave"), "vineweave", "a unit with no line is its own member")


func test_growth_accumulates_per_member() -> void:
	assert_eq(RosterLedger.growth_of("tree_grunt"), 0, "a fresh member has no growth")
	assert_false(RosterLedger.has_member("tree_grunt"), "and reading it does not create a record")
	assert_eq(RosterLedger.add_growth("tree_grunt", 1), 1, "add_growth returns the new total")
	assert_eq(RosterLedger.add_growth("tree_grunt", 2), 3, "growth is cumulative")
	RosterLedger.add_growth("tree_grunt", 0)
	RosterLedger.add_growth("tree_grunt", -4)
	assert_eq(RosterLedger.growth_of("tree_grunt"), 3, "a non-positive award is ignored")
	assert_eq(RosterLedger.form_of("tree_grunt"), &"tree_grunt", "an implicit member is its base form")


## Barkling -> Oakheart also needs 2 won battles (EVOLUTION.md §3.2a): meet that part.
func _meet_the_wins() -> void:
	RosterLedger.add_feats("tree_grunt", {"wins": 2})


func test_availability_opens_exactly_at_the_goal() -> void:
	_meet_the_wins()
	RosterLedger.add_growth("tree_grunt", _goal - 1)
	assert_eq(RosterLedger.available_evolutions("tree_grunt").size(), 0,
		"one short of the goal (%d/%d) offers nothing" % [_goal - 1, _goal])
	RosterLedger.add_growth("tree_grunt", 1)
	var offers := RosterLedger.available_evolutions("tree_grunt")
	assert_eq(offers.size(), 1, "at the goal the evolution is offered")
	assert_eq(offers[0], _edge, "and it is Barkling -> Oakheart")
	assert_eq(RosterLedger.pending_evolutions(["tree_grunt", "vineweave"]), ["tree_grunt"] as Array[String],
		"the story hook names only the members with an evolution ready")


# --- evolve() -------------------------------------------------------------------------

func test_evolve_unlocks_records_and_sets_the_form() -> void:
	assert_false(RosterLedger.is_form_unlocked("oakheart"), "Oakheart starts locked")
	assert_true(RosterLedger.is_form_unlocked("tree_grunt"), "a base form is always unlocked")
	RosterLedger.add_growth("tree_grunt", _goal)
	_meet_the_wins()
	var result := RosterLedger.evolve("tree_grunt", _edge)
	assert_true(bool(result["success"]), "evolve succeeds at the goal: %s" % str(result))
	assert_true(RosterLedger.is_form_unlocked("oakheart"), "Oakheart is now unlocked for open modes")
	assert_true(RosterLedger.is_form_unlocked("tree_grunt"), "and Barkling stays pickable")
	assert_eq(RosterLedger.form_of("tree_grunt"), &"oakheart", "the member IS Oakheart now (story semantics)")
	var history := RosterLedger.evolution_history("tree_grunt")
	assert_eq(history.size(), 1, "the step is recorded")
	assert_eq(String(history[0]["edge"]), "tree_grunt__oakheart", "with its edge id")
	assert_false(String(history[0]["at"]).is_empty(), "and a timestamp")
	assert_eq(RosterLedger.growth_of("tree_grunt"), _goal, "growth is cumulative, not reset by evolving")
	assert_eq(RosterLedger.available_evolutions("tree_grunt").size(), 0, "a final form offers nothing more")
	assert_true(FileAccess.file_exists(LEDGER_PATH), "evolve() saved the ledger")


func test_evolve_refuses_without_writing_anything() -> void:
	RosterLedger.add_growth("tree_grunt", _goal - 1)
	var early := RosterLedger.evolve("tree_grunt", _edge)
	assert_false(bool(early["success"]), "below the goal evolve is refused")
	assert_eq(String(early["reason"]), "not_available", "and says why")
	assert_eq(RosterLedger.form_of("tree_grunt"), &"tree_grunt", "the form did not change")
	assert_false(RosterLedger.is_form_unlocked("oakheart"), "nothing was unlocked")
	assert_eq(String(RosterLedger.evolve("tree_grunt", null)["reason"]), "no_edge", "a null edge is refused")
	assert_eq(String(RosterLedger.evolve("vineweave", _edge)["reason"]), "wrong_form",
		"an edge from another form is refused")


func test_evolve_carries_the_item_only_when_the_new_form_wears_none() -> void:
	ItemInventory.grant(ITEM)
	ItemInventory.equip("tree_grunt", ITEM)
	RosterLedger.add_growth("tree_grunt", _goal)
	_meet_the_wins()
	var result := RosterLedger.evolve("tree_grunt", _edge)
	assert_true(bool(result["item_moved"]), "the Ironbark Sigil moved")
	assert_eq(ItemInventory.equipped_item("oakheart"), ITEM, "Oakheart now wears it")
	assert_eq(ItemInventory.equipped_item("tree_grunt"), "", "and Barkling no longer does")


func test_evolve_never_overwrites_an_item_the_new_form_already_wears() -> void:
	ItemInventory.grant(ITEM)
	ItemInventory.grant(OTHER_ITEM)
	ItemInventory.equip("tree_grunt", ITEM)
	ItemInventory.equip("oakheart", OTHER_ITEM)
	RosterLedger.add_growth("tree_grunt", _goal)
	_meet_the_wins()
	var result := RosterLedger.evolve("tree_grunt", _edge)
	assert_true(bool(result["success"]), "the evolution itself still happens")
	assert_false(bool(result["item_moved"]), "but no item moved")
	assert_eq(ItemInventory.equipped_item("oakheart"), OTHER_ITEM, "Oakheart keeps its own item")
	assert_eq(ItemInventory.equipped_item("tree_grunt"), ITEM, "and Barkling keeps its")


func test_scripted_story_evolution_skips_triggers_but_not_the_form_check() -> void:
	var uid := RosterLedger.create_member("tree_grunt")
	assert_eq(uid, "tree_grunt#2", "a story recruit is an individual member of the line")
	assert_eq(RosterLedger.form_of(uid), &"tree_grunt", "joining as Barkling")
	assert_false(bool(RosterLedger.evolve_member(uid, &"tree_grunt__oakheart")["success"]),
		"an unscripted evolve still needs the growth")
	assert_true(bool(RosterLedger.evolve_member(uid, &"tree_grunt__oakheart", true)["success"]),
		"a scripted story beat evolves it anyway")
	assert_eq(RosterLedger.form_of(uid), &"oakheart", "the story member became Oakheart")
	assert_eq(RosterLedger.form_of("tree_grunt"), &"tree_grunt", "without touching the open-mode member")
	assert_eq(String(RosterLedger.evolve_member(uid, &"tree_grunt__oakheart", true)["reason"]), "wrong_form",
		"an Oakheart cannot take the Barkling edge again")
	assert_eq(RosterLedger.create_member("no_such_unit"), "", "an unknown character cannot join")


func test_growth_alone_no_longer_evolves_barkling() -> void:
	RosterLedger.add_growth("tree_grunt", _goal)
	assert_eq(RosterLedger.available_evolutions("tree_grunt").size(), 0, "Growth 3 with no wins is not enough")
	RosterLedger.add_feats("tree_grunt", {"wins": 1})
	assert_eq(RosterLedger.available_evolutions("tree_grunt").size(), 0, "nor with one win")
	RosterLedger.add_feats("tree_grunt", {"wins": 1})
	assert_eq(RosterLedger.available_evolutions("tree_grunt").size(), 1, "two wins complete it")


func test_the_open_mode_checklist() -> void:
	RosterLedger.add_growth("tree_grunt", _goal)
	RosterLedger.add_feats("tree_grunt", {"wins": 1})
	var lists: Array[Dictionary] = RosterLedger.checklists("tree_grunt")
	assert_eq(lists.size(), 1, "one entry per next form")
	assert_eq(lists[0]["edge"], _edge, "Barkling -> Oakheart")
	assert_false(bool(lists[0]["available"]), "not available yet")
	var rows: Array = lists[0]["rows"]
	assert_true(bool(rows[0]["met"]), "Growth met")
	assert_false(bool(rows[1]["met"]), "wins not yet")
	assert_eq(String(rows[1]["progress"]), "1/2", "1 of 2 wins")
	assert_eq(RosterLedger.checklists("vineweave").size(), 0, "a unit in no line has no checklist")


func test_hold_is_per_member_and_filters_the_automatic_question() -> void:
	RosterLedger.add_growth("tree_grunt", _goal)
	_meet_the_wins()
	assert_false(RosterLedger.is_held("tree_grunt"), "Hold starts off")
	RosterLedger.set_hold("tree_grunt", true)
	assert_true(RosterLedger.is_held("tree_grunt"), "Hold is on")
	assert_eq(RosterLedger.pending_evolutions(["tree_grunt"]), ["tree_grunt"] as Array[String],
		"the evolution is still pending (the menu offers it)")
	assert_eq(RosterLedger.pending_evolutions(["tree_grunt"], {}, true).size(), 0,
		"but the automatic question skips a held member")
	assert_eq(RosterLedger.available_evolutions("tree_grunt").size(), 1, "and EVOLVE still works")


func test_hold_and_feats_survive_the_round_trip() -> void:
	RosterLedger.set_hold("tree_grunt", true)
	RosterLedger.add_feats("tree_grunt", {"wins": 2, "kos": 3, "element_kos": {"dark": 1}})
	assert_true(RosterLedger.save(), "saves")
	RosterLedger.set_save_path(LEDGER_PATH)
	assert_true(RosterLedger.is_held("tree_grunt"), "Hold survives")
	var f: Dictionary = RosterLedger.feats_of("tree_grunt")
	assert_eq(int(f["wins"]), 2, "wins survive")
	assert_eq(int(f["kos"]), 3, "KOs survive")
	assert_eq(f["element_kos"], {"dark": 1}, "element KOs survive")


func test_an_older_file_loads_hold_off_and_zero_feats() -> void:
	var f := FileAccess.open(LEDGER_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": 1, "members": { "tree_grunt": { "line": "tree_grunt",
		"form": "tree_grunt", "growth": 3, "evolved": [], "nickname": "" } }, "unlocked_forms": [] }))
	f.close()
	RosterLedger.set_save_path(LEDGER_PATH)
	assert_false(RosterLedger.is_held("tree_grunt"), "no 'hold' = off")
	assert_eq(int(RosterLedger.feats_of("tree_grunt")["wins"]), 0, "no 'feats' = zero")
	assert_eq(RosterLedger.growth_of("tree_grunt"), 3, "the rest reads as before")


func test_open_modes_read_the_held_item_from_the_inventory() -> void:
	ItemInventory.grant(ITEM)
	ItemInventory.equip("tree_grunt", ITEM)
	assert_eq(String(RosterLedger.context_for("tree_grunt")["held_item"]), ITEM,
		"a HeldItem requirement sees the open-mode equip")
	assert_false(RosterLedger.context_for("tree_grunt").has("mode"), "and the context is not story")


# --- Persistence ----------------------------------------------------------------------

func test_round_trip_save_and_load() -> void:
	RosterLedger.add_growth("tree_grunt", _goal)
	_meet_the_wins()
	RosterLedger.evolve("tree_grunt", _edge)
	RosterLedger.add_growth("vineweave", 2)
	RosterLedger.set_nickname("vineweave", "Ivy")
	assert_true(RosterLedger.save(), "the ledger saves")
	RosterLedger.set_save_path(LEDGER_PATH)   # drops the cache: the next read is from disk
	assert_eq(RosterLedger.growth_of("tree_grunt"), _goal, "growth survives the round trip")
	assert_eq(RosterLedger.form_of("tree_grunt"), &"oakheart", "the form survives")
	assert_true(RosterLedger.is_form_unlocked("oakheart"), "the unlock survives")
	assert_eq(RosterLedger.evolution_history("tree_grunt").size(), 1, "the history survives")
	assert_eq(RosterLedger.nickname_of("vineweave"), "Ivy", "a nickname survives")


func test_a_corrupt_file_recovers_blank_without_an_engine_error() -> void:
	var f := FileAccess.open(LEDGER_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json ]")
	f.close()
	RosterLedger.set_save_path(LEDGER_PATH)
	assert_eq(RosterLedger.growth_of("tree_grunt"), 0, "a corrupt file reads as a blank ledger")
	assert_eq(RosterLedger.unlocked_forms().size(), 0, "with nothing unlocked")
	RosterLedger.add_growth("tree_grunt", 1)
	assert_true(RosterLedger.save(), "and the ledger can be written again over it")


func test_a_wrong_shaped_file_is_repaired_not_rejected() -> void:
	var f := FileAccess.open(LEDGER_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "members": { "tree_grunt": { "growth": "2" }, "bad": 5 },
		"unlocked_forms": "oops" }))
	f.close()
	RosterLedger.set_save_path(LEDGER_PATH)
	assert_eq(RosterLedger.growth_of("tree_grunt"), 2, "a readable member keeps its growth")
	assert_eq(RosterLedger.form_of("tree_grunt"), &"tree_grunt", "and gets a sane default form")
	assert_false(RosterLedger.has_member("bad"), "an unreadable member is dropped")
	assert_eq(RosterLedger.unlocked_forms().size(), 0, "a wrong-typed unlock list reads as empty")
