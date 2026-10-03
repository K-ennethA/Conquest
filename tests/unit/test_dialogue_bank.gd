extends GutTest

## THE DIALOGUE BANK (game/overworld/data/DialogueBank.gd): data-driven NPC talk -- ordered
## variants, the first whose condition passes plays; the bank replaces an NPC's authored .tres line
## (which stays the fallback); story TIME conditions (StoryState.flag_times: rests / steps /
## minutes since a flag was set) saved additively; stable JSON; the validator.

const AREA := "test_area"


func after_each() -> void:
	DialogueBank.set_data(null)


func _bank(npcs: Dictionary) -> Dictionary:
	return {"areas": {AREA: npcs}, "version": 1}


func _variant(cond: String, text: String, speaker: String = "self") -> Dictionary:
	return {"if": cond, "lines": [{"speaker": speaker, "text": text}]}


func _texts(cmds: Array) -> Array:
	var out: Array = []
	for c in cmds:
		if c is SayCommand:
			for b in (c as SayCommand).source_beats():
				out.append(b.text)
	return out


# --- Parsing / normalising ------------------------------------------------------------------

func test_parse_normalises_and_keeps_variant_order() -> void:
	var r: Dictionary = DialogueBank.parse_text(JSON.stringify({
		"areas": {"a": {"n": {"variants": [
			{"if": " after('x') ", "lines": [{"text": "first", "side": "right", "junk": 1}]},
			{"lines": [{"speaker": "hero", "text": "second", "side": "left"}]},
		], "junk": true}}},
	}))
	assert_true(bool(r["ok"]), "valid JSON parses")
	var e: Dictionary = DialogueBank.entry("a", "n", r["data"])
	assert_eq(e.keys(), ["variants"], "unknown keys are dropped")
	assert_eq(e["variants"][0]["if"], "after('x')", "conditions are trimmed")
	assert_eq(e["variants"][0]["lines"][0], {"speaker": "self", "text": "first"},
		"a line with no speaker is the NPC itself; its default side is not written")
	assert_eq(e["variants"][1]["lines"][0], {"speaker": "hero", "text": "second"}, "the hero's default side is left")
	assert_eq(e["variants"][1]["if"], "", "no condition = always")


func test_a_broken_file_reads_as_an_empty_bank_and_never_logs() -> void:
	for text in ["", "{not json", "[1, 2]"]:
		var r: Dictionary = DialogueBank.parse_text(text)
		assert_false(bool(r["ok"]), "'%s' is reported" % text)
		assert_eq(r["data"], DialogueBank.empty(), "and reads as an empty bank")


func test_to_json_is_stable_sorted_and_tab_indented() -> void:
	var d: Dictionary = _bank({"zed": {"variants": [_variant("", "z")]}, "abe": {"note": "n", "variants": [_variant("", "a")]}})
	var once: String = DialogueBank.to_json(d)
	var twice: String = DialogueBank.to_json(DialogueBank.parse_text(once)["data"])
	assert_eq(twice, once, "saving what was loaded writes the same bytes")
	assert_true(once.find("\"abe\"") < once.find("\"zed\""), "keys are sorted")
	assert_true(once.contains("\n\t\"areas\""), "tab-indented")
	assert_true(once.ends_with("\n"), "with a trailing newline")
	assert_true(once.find("\"if\"") < once.find("\"lines\""), "a variant's condition comes before its lines")


# --- Picking ----------------------------------------------------------------------------------

func test_the_first_matching_variant_plays() -> void:
	var e: Dictionary = {"variants": [
		_variant("after('opening.complete')", "later"),
		_variant("after('opening.attack')", "raid"),
		_variant("", "before"),
	]}
	var s := StoryState.new()
	assert_eq(DialogueBank.pick(e, s), 2, "nothing set: the fallback")
	s.set_flag("opening.attack", 1)
	assert_eq(DialogueBank.pick(e, s), 1, "after the raid")
	s.set_flag("opening.complete", 1)
	assert_eq(DialogueBank.pick(e, s), 0, "the most specific first")
	assert_eq(DialogueBank.pick({"variants": [_variant("before('x')", "only")]}, _with("x")), -1, "no match = -1")


func _with(flag: String) -> StoryState:
	var s := StoryState.new()
	s.set_flag(flag, 1)
	return s


func test_npcs_say_the_bank_line_and_fall_back_to_the_tres_scene() -> void:
	var n := NpcEntity.new()
	n.id = &"tobin"
	var scene := StoryScene.new()
	var typed: Array[Resource] = [SayCommand.beat(&"npc_tobin", "Tobin", "the .tres line")]
	scene.beats = typed
	n.dialogue = scene
	var after := SetFlagCommand.make("talked", 1)
	n.on_interact = StoryCommand.list([after])
	# No bank entry: the authored scene, then the script.
	DialogueBank.set_data(_bank({}))
	var cmds: Array = n.interact_script(AREA, StoryState.new())
	assert_eq(_texts(cmds), ["the .tres line"], "no entry: the .tres dialogue")
	assert_eq(cmds.back(), after, "on_interact still runs after it")
	# An entry: the bank replaces the scene.
	DialogueBank.set_data(_bank({"tobin": {"variants": [_variant("after('opening.attack')", "after"), _variant("", "before")]}}))
	assert_eq(_texts(n.interact_script(AREA, StoryState.new())), ["before"], "the bank's line")
	assert_eq(_texts(n.interact_script(AREA, _with("opening.attack"))), ["after"], "which changes with the story")
	# An entry with no matching variant: silence (the scene is NOT used), the script still runs.
	DialogueBank.set_data(_bank({"tobin": {"variants": [_variant("after('opening.attack')", "after")]}}))
	cmds = n.interact_script(AREA, StoryState.new())
	assert_eq(_texts(cmds), [], "nothing matches: nothing said")
	assert_eq(cmds, [after], "but the script runs")


func test_a_bank_entry_makes_a_silent_npc_talkable() -> void:
	var n := NpcEntity.new()
	n.id = &"footpad"
	DialogueBank.set_data(_bank({}))
	assert_false(n.is_interactable_in(AREA), "no lines, no script: not talkable")
	DialogueBank.set_data(_bank({"footpad": {"variants": [_variant("", "Psst.")]}}))
	assert_true(n.is_interactable_in(AREA), "a bank entry gives it a voice, no rebuild needed")
	assert_false(n.is_interactable_in("other_area"), "keyed by area id + NPC id")


func test_merchants_greet_from_the_bank_then_open_the_shop() -> void:
	var m := ShopEntity.new()
	m.id = &"oda"
	m.shop = ShopResource.new()
	DialogueBank.set_data(_bank({"oda": {"variants": [_variant("", "Welcome!")]}}))
	var cmds: Array = m.interact_script(AREA, StoryState.new())
	assert_eq(_texts(cmds), ["Welcome!"], "the greeting comes from the bank")
	assert_true(cmds.back() is OpenShopCommand, "then the shop opens")


func test_a_beaten_trainer_says_his_bank_line_else_his_defeated_scene() -> void:
	var t := TrainerEntity.new()
	t.id = &"bram"
	var scene := StoryScene.new()
	var typed: Array[Resource] = [SayCommand.beat(&"self", "", "defeated line")]
	scene.beats = typed
	t.defeated_scene = scene
	t.battle = BattleSpec.new()
	var s := _with(TrainerEntity.defeated_flag(AREA, "bram"))
	DialogueBank.set_data(_bank({}))
	assert_eq(_texts(t.interact_script(AREA, s)), ["defeated line"], "no entry: the defeated scene")
	DialogueBank.set_data(_bank({"bram": {"variants": [_variant("after('act1.met_rowan')", "signed on")]}}))
	assert_eq(_texts(t.interact_script(AREA, s)), ["defeated line"], "no matching variant: the defeated scene")
	s.set_flag("act1.met_rowan", 1)
	assert_eq(_texts(t.interact_script(AREA, s)), ["signed on"], "a matching variant: the bank")
	var fresh: Array = t.interact_script(AREA, _with("act1.met_rowan"))
	assert_true(_has_battle(fresh), "an UNBEATEN trainer still challenges you (the bank never replaces that)")


func _has_battle(cmds: Array) -> bool:
	for c in cmds:
		if c is StartBattleCommand:
			return true
	return false


func test_speakers_resolve_to_self_hero_and_narrator() -> void:
	var self_beat: StoryBeat = DialogueBank.make_beat({"speaker": "self", "text": "a"})
	assert_eq(self_beat.speaker_id, SayCommand.SELF_ID, "self -> the talking NPC (SayCommand resolves it)")
	assert_eq(self_beat.side, StoryBeat.SIDE_RIGHT, "on the right")
	var hero: StoryBeat = DialogueBank.make_beat({"speaker": "hero", "text": "b"})
	assert_eq(hero.speaker_id, SayCommand.HERO_ID, "hero -> the player's hero")
	assert_eq(hero.side, StoryBeat.SIDE_LEFT, "on the left")
	var narr: StoryBeat = DialogueBank.make_beat({"speaker": "narrator", "text": "c"})
	assert_true(narr.is_narrator() and narr.clear_portraits, "narration has no portraits")
	var other: StoryBeat = DialogueBank.make_beat({"speaker": "hessa", "text": "d", "side": "left"})
	assert_eq(other.speaker_id, &"npc_hessa", "another NPC by id")
	assert_eq(other.side, StoryBeat.SIDE_LEFT, "an explicit side wins")


# --- Story time --------------------------------------------------------------------------------

func test_flags_remember_when_they_were_set() -> void:
	var s := StoryState.new()
	assert_eq(s.rests_since("opening.complete"), -1, "unset: -1")
	s.rests = 2
	s.steps = 100
	s.play_seconds = 600.0
	s.set_flag("opening.complete", 1)
	s.rests = 5
	s.steps = 340
	s.play_seconds = 1800.0
	assert_eq(s.rests_since("opening.complete"), 3, "three rests since")
	assert_eq(s.steps_since("opening.complete"), 240, "240 steps since")
	assert_eq(s.minutes_since("opening.complete"), 20, "20 minutes since")
	s.set_flag("opening.complete", 1)
	assert_eq(s.rests_since("opening.complete"), 3, "setting it again does not restart the clock")
	s.inc_flag("rival.stage")
	s.rests = 6
	s.inc_flag("rival.stage")
	assert_eq(s.rests_since("rival.stage"), 1, "a counter's clock starts at its first set")
	s.clear_flag("opening.complete")
	assert_eq(s.rests_since("opening.complete"), -1, "cleared: unset again")
	s.set_flag("opening.complete", 1)
	assert_eq(s.rests_since("opening.complete"), 0, "set again: a fresh stamp")
	s.set_flag("opening.complete", 0)
	assert_false(s.flag_times.has("opening.complete"), "set to 0 (falsy): no stamp")


func test_conditions_read_story_time_and_the_phase_words() -> void:
	var s := StoryState.new()
	s.set_flag("opening.complete", 1)
	assert_false(ConditionContext.evaluate("rests_since('opening.complete') >= 3", s), "not yet")
	s.rests = 3
	assert_true(ConditionContext.evaluate("rests_since('opening.complete') >= 3", s), "three rests later")
	assert_true(ConditionContext.evaluate("after('opening.complete') and before('act1.met_rowan')", s), "after / before")
	assert_false(ConditionContext.evaluate("steps_since('never.set') >= 0", s), "an unset flag's time is -1")
	assert_true(ConditionContext.evaluate("rests() == 3 and steps() == 0 and play_minutes() == 0", s), "the clocks")
	for c in ["after('a')", "before('a')", "rests_since('a') > 1", "steps_since('a') < 9", "minutes_since('a') >= 2",
			"rests() > 0", "steps() > 0", "play_minutes() > 0"]:
		assert_true(bool(ConditionContext.check(c)["valid"]), "%s is valid content" % c)


func test_flag_times_save_additively_and_old_saves_still_load() -> void:
	var s := StoryState.new()
	s.rests = 4
	s.steps = 50
	s.set_flag("opening.attack", 1)
	s.rests = 9
	var d: Dictionary = StorySnapshot.to_dict(s)
	assert_eq(int(d["format_version"]), 2, "no format bump")
	assert_eq(d["flag_times"], {"opening.attack": {"step": 50, "rest": 4, "sec": 0}}, "the stamp is saved")
	var back: StoryState = StorySnapshot.from_dict(JSON.parse_string(JSON.stringify(d)))["state"]
	assert_eq(back.rests_since("opening.attack"), 5, "and read back")
	var old: Dictionary = d.duplicate(true)
	old.erase("flag_times")
	var legacy: Dictionary = StorySnapshot.from_dict(JSON.parse_string(JSON.stringify(old)))
	assert_true(bool(legacy["success"]), "a save from before stamps loads")
	assert_eq((legacy["state"] as StoryState).rests_since("opening.attack"), 9, "its flags count from the journey's start")
	var junk: Dictionary = d.duplicate(true)
	junk["flag_times"] = {"opening.attack": "nonsense", "not.set": {"rest": 1}}
	var cleaned: StoryState = StorySnapshot.from_dict(JSON.parse_string(JSON.stringify(junk)))["state"]
	assert_eq(cleaned.flag_times, {}, "malformed stamps and stamps of unset flags are dropped")


# --- Readable conditions ------------------------------------------------------------------------

func test_conditions_read_like_story_phases() -> void:
	assert_eq(DialogueBank.describe_condition(""), "always")
	assert_eq(DialogueBank.describe_condition("after('opening.attack')"), "after: opening.attack")
	assert_eq(DialogueBank.describe_condition("has(\"opening.attack\") and not has(\"opening.complete\")"),
		"after: opening.attack · before: opening.complete")
	assert_eq(DialogueBank.describe_condition("rests_since('opening.complete') >= 3"), "3+ rests since opening.complete")
	assert_eq(DialogueBank.flags_in("after('a') and rests_since(\"b\") > 1 or flag('c') >= 2 and visited('d')"),
		["a", "b", "c"] as Array[String], "the flags a condition reads (not area ids)")


# --- Validation -----------------------------------------------------------------------------------

func test_the_validator_catches_authoring_mistakes() -> void:
	var idx := StoryContentIndex.build(["oakvale"])
	var bad: Dictionary = {"areas": {
		"atlantis": {"x": {"variants": [_variant("", "hi")]}},
		"oakvale": {
			"nobody": {"variants": [_variant("", "hi")]},
			"tobin": {"variants": [
				_variant("after('opening.attak')", "typo flag"),
				_variant("has('opening.attack'", "unclosed"),
				_variant("", ""),
				{"if": "", "lines": []},
				_variant("before('opening.attack')", "shadowed"),
			]},
			"hessa": {"variants": [_variant("", "hi", "the_king")]},
			"pell": {"variants": []},
		},
	}}
	var issues: Array[String] = DialogueBank.validate(bad, idx)
	var all: String = "\n".join(issues)
	for needle in ["atlantis: unknown area", "oakvale/nobody: no NPC", "unknown flag 'opening.attak'", "malformed condition",
			"empty text", "has no lines", "never plays", "unknown speaker 'the_king'", "oakvale/pell: no variants"]:
		assert_true(all.contains(needle), "reports: %s" % needle)
	var good: Dictionary = {"areas": {"oakvale": {"tobin": {"variants": [
		_variant("after('opening.attack') and rests_since('opening.sent_off') >= 1", "fine"),
		{"if": "", "lines": [{"speaker": "hessa", "text": "a neighbour chimes in"}, {"speaker": "hero", "text": "me"}]},
	]}}}}
	assert_eq(DialogueBank.validate(good, idx), [] as Array[String], "clean content has no issues")


func test_story_phases_follow_the_main_quests() -> void:
	var defs: Array = [
		{"id": "a", "category": "main", "start_flag": "", "complete_flag": "a.done", "steps": [{"flag": "a.one", "text": "One"}, {"flag": "a.done", "text": "Done"}]},
		{"id": "side", "category": "side", "start_flag": "a.done", "complete_flag": "s.done", "steps": []},
		{"id": "b", "category": "main", "start_flag": "a.done", "complete_flag": "b.done", "steps": [{"flag": "b.one", "text": "B"}]},
	]
	var ms: Array[Dictionary] = StoryPhases.milestones(defs)
	var flags: Array = []
	for m in ms:
		flags.append(m["flag"])
	assert_eq(flags, ["a.one", "a.done", "b.one", "b.done"], "main-quest flags in order, unique, side quests left out")
	var ph: Array[Dictionary] = StoryPhases.phases(defs)
	assert_eq(ph.size(), 5, "phase 0 + one per milestone")
	assert_eq(ph[2]["flags"], ["a.one", "a.done"], "phase k = the first k milestones set")
	var e: Dictionary = {"variants": [_variant("after('b.one')", "late"), _variant("after('a.one')", "mid"), _variant("", "early")]}
	assert_eq(StoryPhases.variant_phases(e, ph), [[3, 4], [1, 2], [0]], "which phases each variant plays in")
	assert_eq(StoryPhases.compact([0, 1, 2, 4]), "P0-P2, P4")
