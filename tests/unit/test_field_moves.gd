extends GutTest

## FIELD MOVES (docs/design/DECISIONS.md #40 / #41 / #71) and the LEGEND list (#39 / #75), as pure
## rules on a [StoryState]:
##   * a [FieldMoveResource] is LOCKED until its unlock flag, then needs a USER -- the hero (when he
##     can use it) or a fieldable party member of a listed species (its form or its line);
##   * a [FieldObstacleEntity] answers a locked move / a move nobody can use with ONE hint line, and a
##     usable one with "Use <move>?" -- Yes fells it (its cleared flag, so it is gone for good), No
##     leaves it standing;
##   * bonding a legend records it in [member StoryState.legends] -- never the party -- and the list
##     survives a save round trip (format_version unchanged; an older save loads none).


class PickHost extends StoryScriptHost:
	var pick: int = 0
	var choices: int = 0
	var toasts: Array[String] = []

	func show_choice(_prompt: StoryBeat, _options: PackedStringArray, _cancel_index: int = -1) -> int:
		choices += 1
		return pick

	func toast(text: String, _kind: String = "") -> void:
		toasts.append(text)


func _move(hero: bool = false) -> FieldMoveResource:
	var fm := FieldMoveResource.new()
	fm.id = &"treefell"
	fm.display_name = "Treefell"
	fm.unlock_flag = "fieldmove.treefell"
	var sp: Array[StringName] = [&"tree_grunt", &"petalfang"]
	fm.species = sp
	fm.hero_can_use = hero
	fm.locked_hint = "A gnarled tree. It could be felled -- if you knew how."
	fm.no_user_hint = "You know {move}, but nobody in your party can use it."
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


func _state(party: Array[String]) -> StoryState:
	var s := StoryState.new()
	for cid in party:
		s.add_member(cid)
	return s


# --- The move ---------------------------------------------------------------------------------

func test_a_move_is_locked_until_its_flag_then_needs_a_user() -> void:
	var fm := _move()
	var s := _state(["tree_grunt"])
	assert_eq(fm.status(s), FieldMoveResource.STATUS_LOCKED, "not granted yet: locked")
	s.set_flag("fieldmove.treefell", 1)
	assert_eq(fm.status(s), FieldMoveResource.STATUS_READY, "granted, and a Barkling can use it: ready")
	var none := _state(["blightcap"])
	none.set_flag("fieldmove.treefell", 1)
	assert_eq(fm.status(none), FieldMoveResource.STATUS_NO_USER, "granted, but nobody in the party can use it")
	assert_eq(_move(true).status(none), FieldMoveResource.STATUS_READY, "unless the hero can use it himself")


func test_only_fieldable_members_of_a_listed_species_or_line_can_use_it() -> void:
	var fm := _move()
	var s := _state(["blightcap", "petalfang"])
	var users: Array[StoryPartyMember] = fm.capable_members(s)
	assert_eq(users.size(), 1, "one member is a listed species")
	assert_eq(users[0].character_id, "petalfang", "the Petalfang")
	s.party[1].wounded = true
	assert_true(fm.capable_members(s).is_empty(), "a knocked-out member cannot do the work")
	assert_true(fm.species_can_use("oakheart_evolved", "tree_grunt"), "an evolved form still belongs to a listed line")
	assert_false(fm.species_can_use("blightcap", "blightcap"), "an unlisted species cannot")


# --- The obstacle -------------------------------------------------------------------------------

func test_a_locked_tree_gives_one_hint_line_and_no_question() -> void:
	var s := _state(["tree_grunt"])
	var cmds: Array = _tree().script_for(_move(), "woods", s)
	assert_eq(cmds.size(), 1, "one command")
	assert_true(cmds[0] is SayCommand, "a hint, not a choice")
	assert_eq((cmds[0] as SayCommand).beats.size(), 1, "one line")
	assert_true(((cmds[0] as SayCommand).beats[0] as StoryBeat).text.contains("could be felled"), "the locked hint")


func test_a_tree_nobody_can_fell_says_so_in_one_line() -> void:
	var s := _state(["blightcap"])
	s.set_flag("fieldmove.treefell", 1)
	var cmds: Array = _tree().script_for(_move(), "woods", s)
	assert_eq(cmds.size(), 1, "one command")
	assert_true(cmds[0] is SayCommand, "a hint, not a choice")
	assert_true(((cmds[0] as SayCommand).beats[0] as StoryBeat).text.contains("nobody in your party"),
		"the no-user hint, with the move named: %s" % ((cmds[0] as SayCommand).beats[0] as StoryBeat).text)


func test_yes_fells_the_tree_for_good_and_no_leaves_it() -> void:
	var tree := _tree()
	var s := _state(["tree_grunt"])
	s.set_flag("fieldmove.treefell", 1)
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
