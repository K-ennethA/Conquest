extends GutTest

## FIELD MOVES (docs/design/DECISIONS.md #40 / #41 / #71 / #92) and the LEGEND list (#39 / #75), as
## pure rules on a [StoryState]:
##   * a [FieldMoveResource] is LEARNED, HM-style: it lists who CAN learn it (creature species -- a
##     form or its line -- and specific humans); a member who learns it keeps it on its record
##     (saved, format_version unchanged; an older save loads none);
##   * the move is LOCKED until its flag (teachable) while nobody knows it, then needs a FIT member
##     who has LEARNED it;
##   * [TeachFieldMoveCommand] teaches it: nobody eligible = nothing; one eligible and nobody knowing
##     it = no question; otherwise a choice (paged when long), Cancel declines;
##   * a [FieldObstacleEntity] answers a locked move / a move nobody fit knows with ONE hint line,
##     and a usable one with "Use <move>?" -- Yes fells it (its cleared flag, gone for good), No
##     leaves it standing;
##   * bonding a legend records it in [member StoryState.legends] -- never the party.


class PickHost extends StoryScriptHost:
	var pick: int = 0
	## Answers in turn (then [member pick] for the rest).
	var picks: Array = []
	var choices: int = 0
	var last_options: PackedStringArray = PackedStringArray()
	var toasts: Array[String] = []

	func show_choice(_prompt: StoryBeat, options: PackedStringArray, _cancel_index: int = -1) -> int:
		choices += 1
		last_options = options
		if not picks.is_empty():
			return int(picks.pop_front())
		return pick

	func toast(text: String, _kind: String = "") -> void:
		toasts.append(text)


func _move() -> FieldMoveResource:
	var fm := FieldMoveResource.new()
	fm.id = &"treefell"
	fm.display_name = "Treefell"
	fm.unlock_flag = "fieldmove.treefell"
	var sp: Array[StringName] = [&"tree_grunt", &"petalfang"]
	fm.species = sp
	var hu: Array[StringName] = [&"wren"]
	fm.humans = hu
	fm.locked_hint = "A gnarled tree. It could be felled -- if you knew how."
	fm.no_user_hint = "This tree could be felled with {move} -- but nobody fit in your party has learned it."
	fm.prompt_text = "Use {move}?"
	fm.used_text = "{user} used {move}!"
	return fm


func _tree() -> FieldObstacleEntity:
	var t := FieldObstacleEntity.new()
	t.id = &"gate_tree"
	t.cell = Vector3i(3, 3, 0)
	t.field_move = &"treefell"
	t.visible_if = FieldObstacleEntity.presence_condition("woods", "gate_tree")
	return t


func _state(party: Array[String], hero: bool = false) -> StoryState:
	var s := StoryState.new()
	if hero:
		s.add_hero("wren", "Wren", 5)
	for cid in party:
		s.add_member(cid)
	return s


## [param s] with the move granted and its first member of [param cid] having learned it.
func _learned(s: StoryState, cid: String) -> StoryState:
	s.set_flag("fieldmove.treefell", 1)
	for m in s.party:
		if m.character_id == cid:
			m.learn_field_move("treefell")
			break
	return s


# --- Who can learn it -------------------------------------------------------------------------

func test_listed_species_lines_and_humans_can_learn_it() -> void:
	var fm := _move()
	var s := _state(["blightcap", "petalfang"], true)
	var who: Array[String] = []
	for m in fm.teachable_members(s):
		who.append(m.character_id)
	assert_eq(who, ["wren", "petalfang"] as Array[String], "the listed human (the hero) and the listed species")
	assert_true(fm.species_can_learn("oakheart_evolved", "tree_grunt"), "an evolved form still belongs to a listed line")
	assert_false(fm.species_can_learn("blightcap", "blightcap"), "an unlisted species cannot")
	assert_true(fm.human_can_learn("wren"), "a listed human can")
	assert_false(fm.human_can_learn("lyra"), "an unlisted human cannot")
	s.join("lyra", "", 6, 5, true, "x")
	assert_false(fm.can_learn(s.member("lyra")), "Lyra is not on this move's list")
	s.member("petalfang").learn_field_move("treefell")
	assert_eq(fm.teachable_members(s).size(), 1, "a member who knows it is not offered again")


func test_the_move_is_locked_then_needs_a_fit_member_who_learned_it() -> void:
	var fm := _move()
	var s := _state(["tree_grunt"])
	assert_eq(fm.status(s), FieldMoveResource.STATUS_LOCKED, "not teachable yet, nobody knows it: locked")
	s.set_flag("fieldmove.treefell", 1)
	assert_eq(fm.status(s), FieldMoveResource.STATUS_NO_USER, "teachable -- but a Barkling that has not LEARNED it cannot use it")
	s.party[0].learn_field_move("treefell")
	assert_eq(fm.status(s), FieldMoveResource.STATUS_READY, "learned: ready")
	assert_eq(fm.user_name(s), s.party[0].display_name(), "the one who learned it uses it")
	s.party[0].wounded = true
	assert_eq(fm.status(s), FieldMoveResource.STATUS_NO_USER, "a knocked-out member cannot do the work")
	assert_eq(fm.known_by(s).size(), 1, "it still knows the move")


func test_a_learned_move_is_saved_and_an_older_save_has_none() -> void:
	var s := _learned(_state(["tree_grunt", "blightcap"], true), "tree_grunt")
	var d: Dictionary = StorySnapshot.to_dict(s)
	assert_eq(int(d["format_version"]), 2, "the format version is unchanged")
	var back: StoryState = StorySnapshot.from_dict(d)["state"]
	assert_eq(back.member("tree_grunt").field_moves, ["treefell"] as Array[String], "the member keeps what it learned")
	assert_true(back.member("blightcap").field_moves.is_empty(), "the others know nothing")
	assert_true(back.party_knows_field_move("treefell"))
	for rec in d["party"]:
		(rec as Dictionary).erase("field_moves")
	var old: StoryState = StorySnapshot.from_dict(d)["state"]
	assert_false(old.party_knows_field_move("treefell"), "an older save loads no learned moves")
	assert_eq(StoryPartyMember.sanitize_field_moves(["treefell", "", 7, "treefell", " sea "]), ["treefell", "sea"] as Array[String],
		"junk is dropped, each id once")
	assert_true(StoryPartyMember.sanitize_field_moves("treefell").is_empty(), "not an array: none")


func test_teach_checks_the_member_can_learn_it() -> void:
	var fm := _move()
	var s := _state(["blightcap", "tree_grunt"])
	assert_eq(String(s.teach_field_move("blightcap", fm)["reason"]), "cannot_learn")
	assert_true(bool(s.teach_field_move("tree_grunt", fm)["ok"]))
	assert_eq(String(s.teach_field_move("tree_grunt", fm)["reason"]), "already_known")
	assert_eq(String(s.teach_field_move("nobody", fm)["reason"]), "no_member")


# --- Teaching it (TeachFieldMoveCommand) ---------------------------------------------------------

func _teach() -> TeachFieldMoveCommand:
	var t := TeachFieldMoveCommand.new()
	t.move_id = &"treefell"   # the SHIPPED move (wren + the starter species)
	t.learned_flag = "test.treefell_learned"
	return t


func test_nobody_eligible_learns_nothing() -> void:
	var s := _state(["undead"])
	var host := PickHost.new()
	var ctx := ScriptContext.new(s, host)
	await StoryScriptRunner.run_list([_teach()], ctx)
	assert_false(bool(ctx.vars["taught"]))
	assert_eq(String(ctx.vars["teach_reason"]), "no_candidate")
	assert_eq(host.choices, 0, "no question")
	assert_false(s.has_flag("test.treefell_learned"))
	assert_false(ConditionContext.evaluate("can_learn_field_move(\"treefell\")", s), "the condition agrees")


func test_one_eligible_member_just_learns_it() -> void:
	var s := _state(["undead", "tree_grunt"])
	var host := PickHost.new()
	await StoryScriptRunner.run_list([_teach()], ScriptContext.new(s, host))
	assert_eq(host.choices, 0, "one candidate and nobody knows it yet: no question")
	assert_true(s.member("tree_grunt").knows_field_move("treefell"), "it learned it")
	assert_true(s.has_flag("test.treefell_learned"), "the learned flag is set")
	assert_eq(host.toasts.size(), 1, "a toast says so")
	assert_true(ConditionContext.evaluate("knows_field_move(\"treefell\")", s))


func test_the_player_picks_who_learns_it_or_declines() -> void:
	var s := _state(["tree_grunt", "petalfang"], true)
	var host := PickHost.new()
	host.pick = 3   # [Wren, Barkling, Petalfang, Not now]
	var ctx := ScriptContext.new(s, host)
	await StoryScriptRunner.run_list([_teach()], ctx)
	assert_eq(host.last_options.size(), 4, "three names and Not now: %s" % str(host.last_options))
	assert_eq(String(ctx.vars["teach_reason"]), "declined", "Not now declines")
	assert_false(s.party_knows_field_move("treefell"))
	host.pick = 1
	await StoryScriptRunner.run_list([_teach()], ScriptContext.new(s, host))
	assert_true(s.member("tree_grunt").knows_field_move("treefell"), "the picked member learns it")
	assert_false(s.hero_member().knows_field_move("treefell"), "nobody else")
	# A later teach: one candidate left, but somebody knows it already -> asked, not automatic.
	var s2 := _state(["tree_grunt"], true)
	s2.hero_member().learn_field_move("treefell")
	var h2 := PickHost.new()
	h2.pick = 1
	await StoryScriptRunner.run_list([_teach()], ScriptContext.new(s2, h2))
	assert_eq(h2.choices, 1, "asked")
	assert_false(s2.member("tree_grunt").knows_field_move("treefell"), "and Not now keeps it untaught")


func test_a_long_list_is_paged() -> void:
	assert_eq(TeachFieldMoveCommand.pages(3), [[0, 1, 2]], "three names fit one box")
	assert_eq(TeachFieldMoveCommand.pages(5), [[0, 1], [2, 3], [4]], "more go two to a page, with More...")
	var s := _state(["tree_grunt", "petalfang", "tree_grunt", "petalfang"], true)
	var host := PickHost.new()
	host.picks = [2, 2, 0]   # More..., More..., then the first name on page 3 (the 5th candidate)
	await StoryScriptRunner.run_list([_teach()], ScriptContext.new(s, host))
	assert_eq(host.choices, 3)
	assert_true(s.party[4].knows_field_move("treefell"), "the fifth candidate learned it")
	assert_eq(s.party.filter(func(m): return m.knows_field_move("treefell")).size(), 1)


# --- The obstacle -------------------------------------------------------------------------------

func test_a_locked_tree_gives_one_hint_line_and_no_question() -> void:
	var s := _state(["tree_grunt"])
	var cmds: Array = _tree().script_for(_move(), "woods", s)
	assert_eq(cmds.size(), 1, "one command")
	assert_true(cmds[0] is SayCommand, "a hint, not a choice")
	assert_eq((cmds[0] as SayCommand).beats.size(), 1, "one line")
	assert_true(((cmds[0] as SayCommand).beats[0] as StoryBeat).text.contains("could be felled"), "the locked hint")


func test_a_tree_nobody_has_learned_to_fell_says_so_in_one_line() -> void:
	var s := _state(["tree_grunt"])
	s.set_flag("fieldmove.treefell", 1)
	var cmds: Array = _tree().script_for(_move(), "woods", s)
	assert_eq(cmds.size(), 1, "one command")
	assert_true(cmds[0] is SayCommand, "a hint, not a choice")
	assert_true(((cmds[0] as SayCommand).beats[0] as StoryBeat).text.contains("has learned it"),
		"the no-user hint, with the move named: %s" % ((cmds[0] as SayCommand).beats[0] as StoryBeat).text)


func test_yes_fells_the_tree_for_good_and_no_leaves_it() -> void:
	var tree := _tree()
	var s := _learned(_state(["tree_grunt"]), "tree_grunt")
	assert_true(tree.is_present(s), "the tree stands")
	var cmds: Array = tree.script_for(_move(), "woods", s)
	assert_true(cmds[0] is ChoiceCommand, "a usable move asks first")
	var host := PickHost.new()
	host.pick = 1
	await StoryScriptRunner.run_list(cmds, ScriptContext.new(s, host))
	assert_eq(host.choices, 1, "the question was asked")
	assert_true(tree.is_present(s), "No leaves it standing")
	host.pick = 0
	await StoryScriptRunner.run_list(tree.script_for(_move(), "woods", s), ScriptContext.new(s, host))
	assert_true(s.has_flag("woods.gate_tree.cleared"), "Yes sets the tree's cleared flag (saved with the journey)")
	assert_false(tree.is_present(s), "and the tree is gone")
	assert_eq(host.toasts.size(), 1, "a short toast says so")
	assert_true(host.toasts[0].ends_with("used Treefell!"), "naming the move: %s" % host.toasts[0])
	assert_true(tree.script_for(_move(), "woods", s).is_empty(), "a felled tree has nothing more to say")


func test_the_party_page_lists_learned_field_moves() -> void:
	var s := _learned(_state(["tree_grunt"]), "tree_grunt")
	assert_eq(PartyDetailPage.field_moves_line(s.party[0]), "Field moves: Treefell", "the shipped move's name")


# --- The shipped move --------------------------------------------------------------------------

func test_the_shipped_move_validates_and_the_hero_can_learn_it() -> void:
	var fm := FieldMoveResource.load_by_id("treefell")
	assert_not_null(fm)
	if fm == null:
		return
	var issues: Array[String] = []
	fm.validate(issues)
	assert_eq(issues, [] as Array[String], "validates: %s" % str(issues))
	assert_true(fm.human_can_learn("wren"), "the hero (#71: 'possibly the hero as well')")
	for opt in ["tree_grunt"]:
		assert_true(fm.species_can_learn(opt), "the starter %s can learn it" % opt)


# --- Legends -------------------------------------------------------------------------------------

func test_bonding_a_legend_records_it_and_not_a_party_member() -> void:
	var s := _state(["tree_grunt"])
	var bond := BondLegendCommand.new()
	bond.character_id = &"eldroot"
	var host := PickHost.new()
	await StoryScriptRunner.run_list([bond], ScriptContext.new(s, host))
	assert_eq(s.legends, ["eldroot"] as Array[String], "the legend is in the journey's legend list")
	assert_eq(s.party.size(), 1, "the party is unchanged")
	assert_false(s.party_has("eldroot"), "a legend never joins the party")
	assert_eq(host.toasts.size(), 1, "a toast marks the bond")
	assert_false(s.add_legend("eldroot"), "a legend is unique: no second bond")
	assert_false(s.add_legend(""), "a blank id is refused")


func test_the_legend_list_is_saved_and_an_older_save_has_none() -> void:
	var s := _state(["tree_grunt"])
	s.add_legend("eldroot")
	var d: Dictionary = StorySnapshot.to_dict(s)
	assert_eq(int(d["format_version"]), 2, "the format version is unchanged")
	var back: StoryState = StorySnapshot.from_dict(d)["state"]
	assert_eq(back.legends, ["eldroot"] as Array[String], "the legend survives the round trip")
	assert_false(back.party_has("eldroot"), "still not a party member")
	d.erase("legends")
	assert_true((StorySnapshot.from_dict(d)["state"] as StoryState).legends.is_empty(), "an older save loads no legends")
	d["legends"] = ["eldroot", "no_such_legend", 7]
	assert_eq((StorySnapshot.from_dict(d)["state"] as StoryState).legends, ["eldroot"] as Array[String],
		"an id this build does not ship is skipped")
