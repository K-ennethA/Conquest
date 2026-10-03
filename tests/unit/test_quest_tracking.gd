extends GutTest

## QUEST TRACKING, the pure parts (docs/STORY_MODE.md "Quest tracking"): the additive QuestLog
## schema (location / area / npc / giver), the tracked quest + filters + map pins, the stable JSON
## the quest editor writes, the transition detector ([QuestTracker]), the pinned quest's save
## round trip ([StorySnapshot], no format bump) and the quest validator ([QuestValidator]).

const DEFS: Array = [
	{"id": "old", "title": "Old", "category": "side", "summary": "", "start_flag": "", "complete_flag": "",
		"steps": [{"flag": "o.1", "text": "old step"}]},
	{"id": "m", "title": "Main", "category": "main", "summary": "", "start_flag": "m.start", "complete_flag": "m.done",
		"giver": "rowan", "location": "crownhaven",
		"steps": [{"flag": "m.1", "text": "go to the ruins", "area": "oakvale_ruins", "npc": "rowan"},
			{"flag": "m.done", "text": "report back"}]},
	{"id": "s", "title": "Side", "category": "side", "summary": "", "start_flag": "", "complete_flag": "s.done",
		"steps": [{"flag": "s.1", "text": "side one", "location": "mossway"}, {"flag": "s.done", "text": "side two"}]},
]


func after_each() -> void:
	QuestLog.set_definitions(null)


# --- Schema -------------------------------------------------------------------------------

func test_old_entries_load_unchanged_and_new_pointers_resolve() -> void:
	var s := StoryState.new()
	var old: Dictionary = QuestLog.entry_for(DEFS[0], s)
	assert_eq(String(old["objective"]), "old step", "an entry without pointers still works")
	assert_eq(String(old["location"]), "", "and points nowhere")
	assert_eq(int(old["step_index"]), 0)
	s.set_flag("m.start")
	var m: Dictionary = QuestLog.entry_for(DEFS[1], s)
	assert_eq(String(m["giver"]), "rowan", "giver")
	assert_eq(String(m["area"]), "oakvale_ruins", "the step's area wins")
	assert_eq(String(m["location"]), "oakvale", "an area id resolves to its world place")
	assert_eq(String(m["npc"]), "rowan", "the step's npc")
	s.set_flag("m.1")
	m = QuestLog.entry_for(DEFS[1], s)
	assert_eq(int(m["step_index"]), 1, "the next step")
	assert_eq(String(m["location"]), "crownhaven", "a step without pointers falls back to the quest's")
	assert_eq(String(m["npc"]), "", "no npc on that step")
	s.set_flag("m.done")
	m = QuestLog.entry_for(DEFS[1], s)
	assert_eq(int(m["step_index"]), -1, "a done quest has no current step")


func test_resolve_location_takes_place_or_area_ids() -> void:
	assert_eq(QuestLog.resolve_location("crownhaven"), "crownhaven")
	assert_eq(QuestLog.resolve_location("oakvale_ruins"), "oakvale")
	assert_eq(QuestLog.resolve_location("nowhere"), "", "unknown -> nothing")
	assert_eq(QuestLog.resolve_location(""), "")


func test_tracked_entry_follows_the_pin_then_falls_back_to_main() -> void:
	var s := StoryState.new()
	assert_eq(String(QuestLog.tracked_entry(s, DEFS)["id"]), "old", "no main open: the first active quest")
	s.set_flag("m.start")
	assert_eq(String(QuestLog.tracked_entry(s, DEFS)["id"]), "m", "the main quest by default")
	s.tracked_quest = "s"
	assert_eq(String(QuestLog.tracked_entry(s, DEFS)["id"]), "s", "the pin wins")
	s.set_flag("s.done")
	assert_eq(String(QuestLog.tracked_entry(s, DEFS)["id"]), "m", "a finished pin falls back")
	s.tracked_quest = "no_such_quest"
	assert_eq(String(QuestLog.tracked_entry(s, DEFS)["id"]), "m", "an unknown pin falls back")
	assert_true(QuestLog.tracked_entry(null, DEFS).is_empty())


func test_filters_and_map_pins() -> void:
	var s := StoryState.new()
	s.set_flag("m.start")
	s.set_flag("o.1")
	var ids := func(rows: Array) -> Array:
		return rows.map(func(e: Dictionary) -> String: return String(e["id"]))
	assert_eq(ids.call(QuestLog.filtered(s, QuestLog.FILTER_MAIN, DEFS)), ["m"])
	assert_eq(ids.call(QuestLog.filtered(s, QuestLog.FILTER_SIDE, DEFS)), ["s"], "active side quests only")
	assert_eq(ids.call(QuestLog.filtered(s, QuestLog.FILTER_COMPLETED, DEFS)), ["old"])
	assert_eq(QuestLog.filtered(s, QuestLog.FILTER_ALL, DEFS).size(), 3)
	var pins: Array = QuestLog.map_pins(s, DEFS)
	assert_eq(pins.size(), 2, "the two active quests with a place")
	assert_eq(String(pins[0]["location"]), "oakvale", "main first, at its objective's place")
	assert_eq(String(pins[1]["location"]), "mossway")


func test_json_is_stable_and_round_trips() -> void:
	var text: String = QuestLog.to_json(DEFS)
	var back: Array = QuestLog.parse(text)
	assert_eq(back.size(), DEFS.size(), "round trip")
	assert_eq(QuestLog.to_json(back), text, "writing twice gives the same bytes")
	assert_false(text.contains("\"giver\": \"\""), "empty optional keys are left out")
	assert_lt(text.find("\"title\""), text.find("\"category\""), "keys in a fixed order")
	# The shipped file is already in that form, so an editor save only diffs what changed.
	var shipped: String = FileAccess.get_file_as_string(QuestLog.DATA_PATH).replace("\r\n", "\n")
	assert_eq(QuestLog.to_json(QuestLog.parse(shipped)), shipped, "quests.json is canonical")
	assert_eq(QuestLog.parse("not json").size(), 0, "malformed -> no quests")
	assert_eq(QuestLog.parse("{\"quests\": 5}").size(), 0)


func test_every_shipped_quest_points_at_a_real_place() -> void:
	var atlas := WorldAtlas.load_default()
	for d in QuestLog.definitions():
		var loc: String = String(d.get("location", ""))
		assert_ne(QuestLog.resolve_location(loc), "", "%s has a world-map location" % d["id"])
		for st in d["steps"]:
			var sl: String = String(st.get("location", ""))
			if not sl.is_empty():
				assert_not_null(atlas.location(QuestLog.resolve_location(sl)), "%s: step place %s" % [d["id"], sl])


# --- Transitions ------------------------------------------------------------------------------

func test_tracker_reports_start_advance_and_completion() -> void:
	var s := StoryState.new()
	var t := QuestTracker.new()
	t.defs = DEFS
	t.reset(s)
	assert_eq(t.poll(s), [], "nothing changed")
	s.set_flag("m.start")
	var ev: Array = t.poll(s)
	assert_eq(ev.size(), 1)
	assert_eq(String(ev[0]["kind"]), QuestTracker.STARTED)
	assert_eq(String(ev[0]["id"]), "m")
	assert_eq(String(ev[0]["objective"]), "go to the ruins")
	s.set_flag("m.1")
	ev = t.poll(s)
	assert_eq(String(ev[0]["kind"]), QuestTracker.ADVANCED, "the next objective")
	assert_eq(String(ev[0]["objective"]), "report back")
	s.set_flag("m.done")
	ev = t.poll(s)
	assert_eq(ev.size(), 1)
	assert_eq(String(ev[0]["kind"]), QuestTracker.COMPLETED)
	assert_eq(t.poll(s), [], "said once")
	assert_eq(QuestTracker.toast_text(ev[0]), "Quest complete: Main")


func test_tracker_is_quiet_on_load_and_on_going_back() -> void:
	var s := StoryState.new()
	s.set_flag("m.start")
	s.set_flag("m.1")
	var t := QuestTracker.new()
	t.defs = DEFS
	t.reset(s)
	assert_eq(t.poll(s), [], "a loaded journey's quests are not news")
	s.clear_flag("m.1")
	assert_eq(t.poll(s), [], "a cleared flag reports nothing")
	var other := StoryState.new()
	other.set_flag("s.1")
	assert_eq(t.poll(other), [], "a swapped-in state (Try Again) re-baselines silently")
	other.set_flag("s.done")
	assert_eq(String(t.poll(other)[0]["kind"]), QuestTracker.COMPLETED, "then reports as usual")


func test_a_quest_that_appears_finished_only_completes() -> void:
	var before: Dictionary = {}
	var after: Dictionary = {"q": {"status": QuestLog.STATUS_DONE, "step": -1, "title": "Q", "category": "side", "objective": ""}}
	var ev: Array = QuestTracker.diff(before, after)
	assert_eq(ev.size(), 1)
	assert_eq(String(ev[0]["kind"]), QuestTracker.COMPLETED)


# --- The pin is saved -------------------------------------------------------------------------

func test_the_pinned_quest_round_trips_without_a_format_bump() -> void:
	var s := StoryState.new()
	s.tracked_quest = "crown_cup"
	var data: Dictionary = StorySnapshot.to_dict(s)
	assert_eq(int(data["format_version"]), 2, "still format 2")
	assert_eq(String(data["tracked_quest"]), "crown_cup")
	var back: StoryState = StorySnapshot.from_dict(JSON.parse_string(JSON.stringify(data)))["state"]
	assert_eq(back.tracked_quest, "crown_cup", "restored")
	data.erase("tracked_quest")
	back = StorySnapshot.from_dict(data)["state"]
	assert_eq(back.tracked_quest, "", "an older save tracks the main quest")
	data["tracked_quest"] = 42
	back = StorySnapshot.from_dict(data)["state"]
	assert_eq(back.tracked_quest, "", "junk is dropped")


func test_flags_revision_counts_changes_only() -> void:
	var s := StoryState.new()
	var r0: int = s.flags_revision
	s.set_flag("a")
	s.set_flag("a")
	assert_eq(s.flags_revision, r0 + 1, "setting the same value again is not a change")
	s.drain_changes()
	assert_eq(s.flags_revision, r0 + 1, "draining does not reset it")
	s.clear_flag("a")
	assert_eq(s.flags_revision, r0 + 2)


# --- Validator --------------------------------------------------------------------------------

const BUILDER := "const F_A := \"story.a\"\nconst F_B := \"story.b\"\nconst F_C := \"story.c\"\nvar p := \"res://x/y.tres\"\n"
const TRES := "key = \"story.a\"\nkey = \"story.b\"\nflag_on_join = \"joined.x\"\nencounter_id = \"route.bram\"\nrewards = {\n\"flags\": [\"loot.flag\"]\n}\nvisible_if = \"has(\\\"story.c\\\")\"\nreward_flags = Array[String]([\"fight.won\"])\n"


func _scan() -> Dictionary:
	var scan: Dictionary = QuestValidator.collect_flags(BUILDER, [TRES], ["cup"])
	scan["locations"] = ["crownhaven"]
	scan["areas"] = ["oakvale"]
	return scan


func test_collect_flags_reads_constants_and_what_content_sets() -> void:
	var scan: Dictionary = _scan()
	for f in ["story.a", "story.b", "story.c", "joined.x", "route.bram.defeated", "loot.flag", "arena.cup.run", "arena.cup.champion"]:
		assert_true((scan["known"] as Array).has(f), "%s is known" % f)
	for f in ["story.a", "story.b", "joined.x", "route.bram.defeated", "loot.flag", "fight.won", "arena.cup.wins"]:
		assert_true((scan["set"] as Array).has(f), "%s is set by content" % f)
	assert_false((scan["set"] as Array).has("story.c"), "a flag only READ is not set")
	assert_false((scan["known"] as Array).has("y.tres"), "file paths are not flags")
	assert_lt(int(scan["ranks"]["story.a"]), int(scan["ranks"]["story.b"]), "ranked in builder order")


func test_validator_flags_the_classic_mistakes() -> void:
	var defs: Array = [
		{"id": "ok", "title": "Ok", "category": "main", "start_flag": "", "complete_flag": "story.b",
			"location": "crownhaven", "steps": [{"flag": "story.a", "text": "do a", "area": "oakvale"}]},
		{"id": "ok", "title": "Dup", "category": "side", "start_flag": "", "complete_flag": "",
			"steps": [{"flag": "story.a", "text": "x"}]},
		{"id": "never", "title": "Never", "category": "side", "start_flag": "story.c", "complete_flag": "",
			"steps": [{"flag": "made.up", "text": ""}]},
		{"id": "bad_place", "title": "", "category": "epic", "start_flag": "", "complete_flag": "",
			"location": "atlantis", "steps": []},
	]
	var issues: Array = QuestValidator.validate(defs, _scan())
	var text: String = "\n".join(issues.map(func(i: Dictionary) -> String: return "%s|%s|%s" % [i["severity"], i["quest"], i["message"]]))
	assert_true(text.contains("error|ok|duplicate id"), "duplicate id")
	assert_true(text.contains("error|never|unreachable: start flag 'story.c'"), "start flag nothing sets")
	assert_true(text.contains("warning|never|step 1 flag 'made.up' is unknown"), "unknown flag")
	assert_true(text.contains("error|never|step 1 has empty text"), "empty text")
	assert_true(text.contains("error|bad_place|empty title"), "empty title")
	assert_true(text.contains("warning|bad_place|category 'epic'"), "odd category")
	assert_true(text.contains("location 'atlantis' is not a world place"), "unknown place")
	assert_true(text.contains("warning|bad_place|has no steps"))
	assert_false(text.contains("|ok|start"), "the good quest has no flag problems")
	assert_eq(String(issues[0]["severity"]), QuestValidator.SEVERITY_ERROR, "errors first")


func test_story_flow_orders_by_where_start_flags_are_reached() -> void:
	var defs: Array = [
		{"id": "late", "title": "Late", "category": "side", "start_flag": "story.b", "steps": []},
		{"id": "never", "title": "Never", "category": "side", "start_flag": "story.c", "steps": []},
		{"id": "first", "title": "First", "category": "main", "start_flag": "", "complete_flag": "story.b",
			"steps": [{"flag": "story.a", "text": "a"}]},
		{"id": "mid", "title": "Mid", "category": "main", "start_flag": "story.a", "steps": []},
	]
	var flow: Array = QuestValidator.story_flow(defs, _scan())
	assert_eq(flow.map(func(r: Dictionary) -> String: return String(r["id"])), ["first", "mid", "late", "never"])
	assert_eq(String(flow[1]["after"]), "first", "opened by progress in the first quest")
	assert_false(bool(flow[3]["reachable"]), "nothing sets its start flag")


func test_the_shipped_quests_validate_clean() -> void:
	var scan: Dictionary = QuestValidator.scan_project()
	assert_gt((scan["known"] as Array).size(), 20, "the builder's flags are found")
	assert_true((scan["locations"] as Array).has("crownhaven"), "world places read from world.tres")
	assert_true((scan["areas"] as Array).has("oakvale_ruins"), "areas read from the content dir")
	var defs: Array = QuestLog.definitions()
	assert_eq(QuestValidator.validate(defs, scan), [], "quests.json validates clean (no errors, no warnings)")
	var flow: Array = QuestValidator.story_flow(defs, scan)
	assert_eq(String(flow[0]["id"]), "road_to_crownhaven", "the journey opens with the road to Crownhaven")
	assert_eq(String(flow[1]["id"]), "smoke_over_oakvale", "then the raid")
	for r in flow:
		assert_true(bool(r["reachable"]), "%s can be reached" % r["id"])
