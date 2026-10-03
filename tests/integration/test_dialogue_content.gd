extends GutTest

## THE SHIPPED DIALOGUE BANK (game/overworld/content/dialogue.json) against the shipped story:
## it validates clean, every townsperson who talks has an entry, nobody mentions the raid before it
## happens and the towns talk about it after, story time changes what people say, the Researcher is
## the hero's longtime friend (he/him), the live overworld plays the bank -- and the Dialogue
## editor (addons/dialogue_editor) loads, edits, simulates and saves it.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const PANEL := "res://addons/dialogue_editor/dialogue_editor_panel.gd"
const TEMP_DIR := "user://test_dialogue_content/"

## Every NPC whose ambient talk moved from the builder into the bank.
const MIGRATED := {
	"oakvale": ["briony", "tobin", "hessa", "pell", "marra", "ned", "wick"],
	"oakvale_ruins": ["tobin", "hessa", "pell", "marra", "ned", "wick"],
	"mossway": ["pedlar", "nell"],
	"river_crossing": ["hobb", "nan", "joss", "rc_child"],
	"crownhaven": ["orwin", "gate_guard", "keep_guard_w", "keep_guard_e", "rowan", "lisk", "dalla", "merchant", "fenwick",
		"brisa", "biscuit", "corin", "kit", "baker", "tam", "north_guard", "gate_warden", "maribel", "veyra", "odalys",
		"garrick", "merrow", "lark"],
	"sparse_forest": ["alder"],
	"woodland_town": ["hale", "bryn", "sedge", "burr", "torvald", "road_warden", "fern", "ilse", "ferra", "wicke", "stranger"],
}
const RAID_WORDS: Array[String] = ["raid", "raider", "attack", "abduct", "kidnap", "taken"]

var _guard
var _world: Node = null
var _prev_scene: Node = null


func before_each() -> void:
	DialogueBank.set_data(null)
	QuestLog.set_definitions(null)
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	StoryController.end_session()
	StoryController.scene_changes_enabled = false


func after_each() -> void:
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	DialogueBank.set_data(null)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _phase_state(flag: String) -> StoryState:
	## The phase right after [param flag] was reached (StoryPhases, i.e. quests.json).
	for p in StoryPhases.phases():
		if String(p["flag"]) == flag:
			return StoryPhases.state_for(p)
	return StoryState.new()


func _said(area_id: String, npc_id: String, s: StoryState) -> String:
	var e: Dictionary = DialogueBank.entry(area_id, npc_id)
	var i: int = DialogueBank.pick(e, s)
	if i < 0:
		return ""
	var parts: Array[String] = []
	for l in e["variants"][i]["lines"]:
		parts.append(String(l["text"]))
	return " ".join(parts)


# --- The data ------------------------------------------------------------------------------

func test_the_shipped_bank_is_valid_and_canonical() -> void:
	var text: String = FileAccess.get_file_as_string(DialogueBank.DATA_PATH)
	var r: Dictionary = DialogueBank.parse_text(text)
	assert_true(bool(r["ok"]), "dialogue.json parses: %s" % r["error"])
	var issues: Array[String] = DialogueBank.validate(r["data"])
	assert_eq(issues, [] as Array[String], "and validates clean: %s" % "\n".join(issues))
	assert_eq(DialogueBank.to_json(r["data"]), text.replace("\r\n", "\n"),
		"it is saved in the editor's canonical form (sorted keys, tabs), so the editor's first save is no diff")


func test_every_townsperson_who_talks_has_an_entry() -> void:
	for aid in MIGRATED:
		var a := OverworldAreaResource.load_by_id(aid)
		for nid in MIGRATED[aid]:
			var e := a.entity(nid) as NpcEntity
			assert_not_null(e, "%s/%s exists" % [aid, nid])
			if e == null:
				continue
			assert_true(DialogueBank.has_entry(aid, nid), "%s/%s has a bank entry" % [aid, nid])
			assert_true(e.is_interactable_in(aid), "%s/%s can be talked to" % [aid, nid])
			assert_null(e.dialogue, "%s/%s: no stale .tres copy of its lines in the builder" % [aid, nid])


func test_nobody_mentions_the_raid_before_it_happens() -> void:
	var before: Array = []
	for p in StoryPhases.phases():
		if (p["flags"] as Array).has("opening.attack"):
			break
		before.append(StoryPhases.state_for(p))
	assert_gt(before.size(), 2, "several phases come before the raid")
	var bank: Dictionary = DialogueBank.data()
	for aid in bank["areas"]:
		for nid in bank["areas"][aid]:
			for s in before:
				var text: String = _said(aid, nid, s).to_lower()
				for w in RAID_WORDS:
					assert_false(text.contains(w), "%s/%s says '%s' before the raid: %s" % [aid, nid, w, text])


func test_after_the_raid_the_towns_talk_about_it() -> void:
	var pre: StoryState = _phase_state("opening.arrived_crownhaven")
	var post: StoryState = _phase_state("opening.complete")
	var changed: Dictionary = {}
	for aid in ["crownhaven", "river_crossing"]:
		changed[aid] = 0
		for nid in DialogueBank.data()["areas"][aid]:
			if _said(aid, nid, pre) != _said(aid, nid, post) and not _said(aid, nid, post).is_empty():
				changed[aid] += 1
	assert_gte(int(changed["crownhaven"]), 15, "most of Crownhaven talks differently after the raid")
	assert_eq(int(changed["river_crossing"]), 4, "everyone at River Crossing saw the raiders cross")
	assert_true(_said("crownhaven", "corin", post).contains("the man who makes them"), "Corin wonders about the raiders")
	# The ruins: the night of the raid, then the morning after.
	var night: StoryState = _phase_state("opening.ruins_seen")
	assert_ne(_said("oakvale_ruins", "tobin", night), _said("oakvale_ruins", "tobin", post), "Tobin, the night vs the morning after")


func test_story_time_changes_what_people_say() -> void:
	var post: StoryState = _phase_state("act1.met_rowan")
	var later: StoryState = StoryPhases.state_for(StoryPhases.phases().back(), [], [], 3, 0)
	for pair in [["crownhaven", "lisk"], ["crownhaven", "dalla"], ["crownhaven", "kit"], ["oakvale_ruins", "marra"],
			["river_crossing", "hobb"]]:
		assert_ne(_said(pair[0], pair[1], post), _said(pair[0], pair[1], later),
			"%s/%s has moved on three rests later" % pair)


func test_the_researcher_is_the_heros_longtime_friend_he_him() -> void:
	var idx := StoryContentIndex.build()
	var lines: Array[String] = []
	var bank: Dictionary = DialogueBank.data()
	for aid in bank["areas"]:
		for nid in bank["areas"][aid]:
			for v in bank["areas"][aid][nid]["variants"]:
				for l in v["lines"]:
					lines.append(String(l["text"]))
	for aid in idx.area_ids:
		for s in idx.scripts(aid):
			for l in s["lines"]:
				if not bool(l["marker"]):
					lines.append(String(l["text"]))
	var she := RegEx.create_from_string("\\b(she|her|hers|herself|woman)\\b")
	var mentions: int = 0
	for t in lines:
		if t.contains("Researcher") or t.contains("Linnea"):
			mentions += 1
			assert_null(she.search(t.to_lower()), "the Researcher is 'he': %s" % t)
	assert_gt(mentions, 10, "the Researcher is talked about")
	# Oakvale sets up the friendship before you leave; the reunion explains the invention.
	var home := _phase_state("opening.sent_off")
	var friends: int = 0
	for nid in MIGRATED["oakvale"]:
		if _said("oakvale", nid, home).contains("Linnea"):
			friends += 1
	assert_gte(friends, 3, "Oakvale talks about its boy Linnea")
	var ceremony: String = ""
	for s in idx.scripts("crownhaven"):
		if String(s["owner"]) == "linnea":
			for l in s["lines"]:
				ceremony += String(l["text"]) + "\n"
	for needle in ["invention", "Twelve years since I left Oakvale", "spark", "Which one answers you"]:
		assert_true(ceremony.contains(needle), "the reunion: '%s'" % needle)


func test_every_cutscene_line_is_indexed_with_its_gate() -> void:
	var idx := StoryContentIndex.build(["crownhaven", "oakvale_ruins"])
	var gated: bool = false
	var raid_flag: bool = false
	for s in idx.scripts("crownhaven"):
		for l in s["lines"]:
			if String(l["cond"]).contains("opening.starter_received"):
				gated = true
			if bool(l["marker"]) and String(l["text"]) == "sets opening.attack":
				raid_flag = true
	assert_true(gated, "a cutscene line knows the condition that gates it")
	assert_true(raid_flag, "and the flags the script sets are listed")
	for f in ["opening.attack", "opening.ruins_seen", "arena.crown_cup.champion", "rival.duel1", "act1.met_rowan"]:
		assert_true(idx.is_known_flag(f), "%s is a known flag" % f)
	assert_false(idx.is_known_flag("opening.attak"), "a typo is not a flag")


# --- The live overworld plays the bank -------------------------------------------------------

func _boot(area: String, cell: Vector3i, facing: String) -> OverworldController:
	var s: StoryState = StoryController.state()
	if area != s.location_area():
		s.on_area_changed()
	s.set_location(area, cell, facing)
	_teardown()
	var w: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	await get_tree().process_frame
	await get_tree().process_frame
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func _drain(ow: OverworldController) -> void:
	for i in range(600):
		await get_tree().process_frame
		var d: StoryDialogue = ow.dialogue() if is_instance_valid(ow) else null
		if d != null and d.root_control().visible:
			d.skip()
			continue
		if not StoryController.is_script_running():
			return


## Talk to the NPC the hero faces and return the first line shown.
func _talk(ow: OverworldController) -> String:
	await _drain(ow)
	assert_true(ow.interact(), "the NPC can be talked to")
	for i in range(60):
		await get_tree().process_frame
		var d: StoryDialogue = ow.dialogue()
		if d != null and d.root_control().visible and d.sequencer().current_beat() != null:
			var t: String = d.sequencer().current_beat().text
			await _drain(ow)
			return t
	return ""


func test_talking_in_the_overworld_plays_the_bank_line_for_the_moment() -> void:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	StoryFixture.sent_off(s)
	s.set_flag("opening.arrived_crownhaven", 1)
	var ow := await _boot("crownhaven", Vector3i(18, 13, 0), "east")
	var first: String = await _talk(ow)
	assert_eq(first, DialogueBank.entry("crownhaven", "corin")["variants"][1]["lines"][0]["text"], "Corin, before the raid")
	StoryFixture.past_opening(s)
	ow = await _boot("crownhaven", Vector3i(18, 13, 0), "east")
	var after: String = await _talk(ow)
	assert_true(after.contains("the man who makes them"), "Corin, after the raid: %s" % after)


# --- The Dialogue editor ----------------------------------------------------------------------

func _panel() -> Control:
	var panel: Control = load(PANEL).new()
	add_child_autofree(panel)
	return panel


func test_the_editor_loads_edits_simulates_and_saves() -> void:
	var copy: String = TEMP_DIR + "dialogue.json"
	var shipped: String = FileAccess.get_file_as_string(DialogueBank.DATA_PATH).replace("\r\n", "\n")
	var f := FileAccess.open(copy, FileAccess.WRITE)
	f.store_string(shipped)
	f.close()
	var panel: Control = _panel()
	assert_true(bool(panel.load_bank(copy)["ok"]), "the editor loads the bank")
	assert_gt(panel.entry_count(), 50, "every entry")
	assert_gt(panel.phases().size(), 8, "the story phases come from quests.json")
	# An unedited save writes the very same bytes.
	var r: Dictionary = panel.save_bank(copy)
	assert_true(bool(r["ok"]), "it saves")
	assert_eq(r["issues"], [], "and the validator runs on save")
	assert_eq(FileAccess.get_file_as_string(copy), shipped, "saving unchanged data changes nothing")
	# Edit: a new top variant for Tobin, a line, a reorder.
	panel.select_npc("oakvale", "tobin")
	var before: int = (panel.entry("oakvale", "tobin")["variants"] as Array).size()
	panel.add_variant("after('opening.sent_off') and steps_since('opening.sent_off') >= 500")
	panel.set_line_field(0, 0, "text", "Still here? The capital won't come to you!")
	panel.add_line(0, "hero", "I'm going, I'm going.")
	panel.set_variant_field(0, "label", "dawdling")
	assert_true(panel.is_dirty(), "edits mark the bank dirty")
	panel.move_variant(0, 1)
	panel.move_variant(1, -1)
	assert_true(bool(panel.save_bank(copy)["ok"]), "saved")
	var back: Dictionary = DialogueBank.parse_text(FileAccess.get_file_as_string(copy))["data"]
	var tv: Array = DialogueBank.entry("oakvale", "tobin", back)["variants"]
	assert_eq(tv.size(), before + 1, "the variant is in the file")
	assert_eq(String(tv[0]["label"]), "dawdling", "first, labelled")
	assert_eq(tv[0]["lines"][1], {"speaker": "hero", "text": "I'm going, I'm going."}, "with the hero's reply")
	# A new entry for an NPC that had no lines (the footpad), then removed again.
	panel.select_npc("mossway", "footpad")
	assert_true(panel.entry("mossway", "footpad").is_empty(), "the footpad has no entry")
	panel.add_entry()
	assert_false(panel.entry("mossway", "footpad").is_empty(), "now it has one (a TODO line)")
	assert_eq(panel.missing_report()["placeholders"].size(), 1, "and the missing view lists its TODO line")
	panel.delete_entry()
	assert_true(panel.entry("mossway", "footpad").is_empty(), "and deleted again")


func test_the_editor_simulates_a_town_and_searches_everything() -> void:
	var panel: Control = _panel()
	panel.load_bank(DialogueBank.DATA_PATH)
	var phases: Array = panel.phases()
	var attack: int = -1
	for p in phases:
		if String(p["flag"]) == "opening.attack":
			attack = int(p["index"])
	assert_gt(attack, 0, "the raid is a phase")
	panel.set_phase(attack - 1)
	var corin_before: Dictionary = {}
	for row in panel.simulate("crownhaven"):
		if row["npc"] == "corin":
			corin_before = row
	panel.set_phase(attack)
	var corin_after: Dictionary = {}
	var wynn_here: bool = true
	for row in panel.simulate("crownhaven"):
		if row["npc"] == "corin":
			corin_after = row
		if row["npc"] == "wynn":
			wynn_here = bool(row["present"])
	assert_eq(String(corin_before["source"]), "bank", "Corin talks from the bank")
	assert_ne(int(corin_before["variant"]), int(corin_after["variant"]), "and says something else once the raid happened")
	assert_false(wynn_here, "Corporal Wynn is not at the barracks yet (his visible_if: after the opening)")
	panel.set_flag_ticked("opening.complete", true)
	panel.set_flag_ticked("act1.met_rowan", true)
	panel.set_time(3, 0)
	for row in panel.simulate("crownhaven"):
		if row["npc"] == "lisk":
			assert_eq(String(row["label"]), "word from the border", "ticking a flag + 3 rests: Lisk's later line")
	var hits: Array = panel.search("scholar's coat")
	var kinds: Dictionary = {}
	for h in hits:
		kinds[String(h["kind"])] = true
	assert_true(kinds.has("bank") and kinds.has("cutscene"), "search finds bank lines and cutscene lines")
	var rep: Dictionary = panel.missing_report()
	for k in ["no_entry", "silent", "placeholders", "never"]:
		assert_true(rep.has(k), "the missing view reports %s" % k)
	assert_eq(rep["placeholders"], [], "the shipped bank has no TODO lines")
	var ids: Array = []
	for r in rep["no_entry"]:
		ids.append("%s/%s" % [r["area"], r["npc"]])
	assert_true(ids.has("crownhaven/linnea"), "scripted-only NPCs are listed as having no bank entry")
