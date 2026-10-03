extends GutTest

## The story JOURNEY pages added around Party / Bag: the flag-derived QuestLog (+ its shipped data),
## member equip / unequip, the party detail page, and the Quests / Map / Settings / Load rows of
## [JourneyMenu] (session-less: the menu falls back to writing straight onto the state).

const DEFS: Array = [
	{"id": "a", "title": "A", "category": "side", "summary": "", "start_flag": "", "complete_flag": "a.done",
		"steps": [{"flag": "a.1", "text": "do one"}, {"flag": "a.2", "text": "do two"}]},
	{"id": "m", "title": "M", "category": "main", "summary": "", "start_flag": "m.start", "complete_flag": "",
		"steps": [{"flag": "m.1", "text": "main step"}]},
]


func after_each() -> void:
	QuestLog.set_definitions(null)


func test_quest_hidden_until_started_and_current_step_advances() -> void:
	var s := StoryState.new()
	var rows: Array = QuestLog.entries(s, DEFS)
	assert_eq(rows.size(), 1, "the gated main quest is not listed yet")
	assert_eq(String(rows[0]["objective"]), "do one", "first undone step is the objective")
	s.set_flag("a.1")
	assert_eq(QuestLog.current_objective(s, DEFS), "do two", "advances with the flag")
	s.set_flag("m.start")
	rows = QuestLog.entries(s, DEFS)
	assert_eq(rows.size(), 2, "the main quest is listed once started")
	assert_eq(String(rows[0]["id"]), "m", "main sorts before side")
	assert_eq(QuestLog.current_objective(s, DEFS), "main step", "main objective wins")


func test_done_quests_sort_last_and_clear_objective() -> void:
	var s := StoryState.new()
	s.set_flag("m.start")
	s.set_flag("m.1")
	s.set_flag("a.done")
	var rows: Array = QuestLog.entries(s, DEFS)
	assert_eq(String(rows[0]["status"]), QuestLog.STATUS_DONE, "both done")
	assert_eq(String(rows[1]["objective"]), "", "a done quest has no objective")
	assert_eq(QuestLog.current_objective(s, DEFS), "", "nothing open")


func test_shipped_quests_reference_known_shapes() -> void:
	var defs: Array = QuestLog.definitions()
	assert_gt(defs.size(), 0, "quests.json loads")
	var ids: Dictionary = {}
	for d in defs:
		assert_false(ids.has(d["id"]), "unique id " + String(d["id"]))
		ids[d["id"]] = true
		assert_gt((d["steps"] as Array).size(), 0, "%s has steps" % d["id"])
	var fresh := StoryState.new()
	assert_ne(QuestLog.current_objective(fresh), "", "a new journey has an objective")


func test_equip_swaps_through_the_bag() -> void:
	var s := StoryState.new()
	var m: StoryPartyMember = s.add_member("vineweave")
	var items: Array = _equipment_ids()
	if items.size() < 2:
		pending("needs two unit equipment items")
		return
	s.add_item(items[0])
	s.add_item(items[1])
	var r: Dictionary = s.equip_item(m.member_id, items[0])
	assert_true(bool(r["ok"]), "equips")
	assert_eq(m.item_id, items[0])
	assert_eq(s.item_count(items[0]), 0, "taken from the bag")
	r = s.equip_item(m.member_id, items[1])
	assert_eq(String(r["swapped"]), items[0], "the old item swaps back")
	assert_eq(s.item_count(items[0]), 1)
	assert_true(s.unequip_item(m.member_id), "unequips")
	assert_eq(s.item_count(items[1]), 1)
	assert_false(s.unequip_item(m.member_id), "nothing left to take off")
	assert_eq(String(s.equip_item(m.member_id, "no_such_item")["reason"]), "no_item")


func test_party_detail_page_builds() -> void:
	var s := StoryState.new()
	var m: StoryPartyMember = s.add_member("vineweave")
	var page := PartyDetailPage.build(m, s, true, Callable(), Callable(), Callable())
	add_child_autofree(page)
	assert_not_null(page.find_child("StatTable", true, false), "stat table")
	assert_not_null(page.find_child("Equipment", true, false), "equipment block")
	assert_not_null(page.find_child("GrowthLine", true, false), "growth line")
	assert_ne(PartyDetailPage.role_of(m.character()), "", "a role label")


func test_journey_menu_pages() -> void:
	var s := StoryState.new()
	s.add_member("vineweave")
	s.set_location("oakvale", Vector3i.ZERO, "south")
	s.mark_visited("oakvale")
	var jm := JourneyMenu.new()
	add_child_autofree(jm)
	jm.open(s)
	await get_tree().process_frame
	jm.show_quests()
	assert_true(jm.is_quests_open(), "Quests page")
	assert_not_null(jm.find_child("Quest_road_to_crownhaven", true, false), "the opening quest is listed")
	jm.show_map()
	assert_true(jm.is_map_open() and not jm.is_quests_open(), "pages are exclusive")
	assert_not_null(jm.find_child("Place_oakvale", true, false), "the visited area is listed")
	jm.show_party()
	jm.show_member_detail("vineweave")
	assert_eq(jm.detail_member_id(), "vineweave")
	assert_not_null(jm.find_child("PartyDetail", true, false), "detail page replaces the list")
	jm.show_member_detail("")
	assert_not_null(jm.member_card("vineweave"), "back to the list")
	assert_false(jm.can_load(), "no session, nothing to load")
	assert_not_null(jm.find_child("JourneySettingsPanel", true, false), "settings mounted")


func _equipment_ids() -> Array:
	var out: Array = []
	for item in ItemLibrary.all_items():
		if item.is_equipment() and not item.is_team_item():
			out.append(String(item.id))
		if out.size() >= 2:
			break
	return out
