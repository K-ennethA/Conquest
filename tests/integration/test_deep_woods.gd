extends GutTest

## THE DEEP WOODS story slice (docs/design/DECISIONS.md #38-#41, #50, #56, #67, #71, #74, #75, #80,
## #81, #85, #88) against the SHIPPED content (build_story_content.gd):
##   * the places are built on the world map, in the Deep Woods band, west of Woodland Town;
##   * Warden Hale opens the west road; NYRA is a SCALED chief DUEL inside the band whose win grants
##     the tree-felling field move and opens the trail north; her final creature carries the stone
##     placeholder;
##   * ELDROOT is a TACTICAL legend FIXED above the band, Lyra fighting beside you as a guest, Try
##     Again on a loss; it waits behind a BREAKABLE TREE that blocks until felled;
##   * the optional bond records the legend, never a party member;
##   * LYRA is never in two places at once.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const BAND := Vector2i(8, 15)
const DEPTHS := "depths_of_the_wood"
const VILLAGE := "deepwood_village"


class PickHost extends StoryScriptHost:
	var pick: int = 0
	var toasts: Array[String] = []

	func show_choice(_prompt: StoryBeat, _options: PackedStringArray, _cancel_index: int = -1) -> int:
		return pick

	func toast(text: String, _kind: String = "") -> void:
		toasts.append(text)


func _area(id: String) -> OverworldAreaResource:
	return load(StoryController.area_path(id)) as OverworldAreaResource


func _flatten(commands: Array) -> Array:
	var out: Array = []
	var stack: Array = commands.duplicate()
	while not stack.is_empty():
		var c = stack.pop_front()
		if not (c is StoryCommand):
			continue
		out.append(c)
		for l in (c as StoryCommand).child_lists():
			stack.append_array(l)
	return out


func _past(flags: Array = []) -> StoryState:
	var s := StoryFixture.past_opening(StoryState.new())
	for f in flags:
		s.set_flag(String(f), 1)
	return s


func _nyra_spec() -> BattleSpec:
	for c in _flatten(_area(VILLAGE).entity("nyra").on_interact):
		if c is StartDuelCommand:
			return (c as StartDuelCommand).spec
	return null


func _eldroot_spec() -> BattleSpec:
	for c in _flatten(_area(DEPTHS).entity("eldroot").on_interact):
		if c is StartBattleCommand and not (c is StartDuelCommand):
			return (c as StartBattleCommand).spec
	return null


func _party_at(top: int) -> StoryState:
	var s := _past()
	s.party.clear()
	s.add_member("tree_grunt", "", 6, top)
	return s


# --- The places ------------------------------------------------------------------------------

func test_the_deep_woods_are_built_on_the_world_map() -> void:
	var atlas := WorldAtlas.load_default()
	for id in [VILLAGE, DEPTHS]:
		var l := atlas.location(id)
		assert_true(l.is_built(), "%s is built" % id)
		assert_true(l.area_ids.has(StringName(id)), "%s has its area" % id)
		var a := _area(id)
		assert_eq(a.region_id, &"woodlands", "%s is in the Deep Woods" % id)
		assert_eq(a.level_band, BAND, "%s rolls in the Deep Woods band" % id)
		assert_eq(a.world_map_pos, l.map_pos, "%s sits where the map puts it" % id)
	var reach: Array[String] = atlas.reachable_built("oakvale")
	assert_true(reach.has(VILLAGE) and reach.has(DEPTHS), "both are on the built road network")
	assert_true(atlas.has_road("woodland_town", VILLAGE), "the road west from Woodland Town")
	assert_true(atlas.has_road(VILLAGE, DEPTHS), "and on to the Depths")


func test_warden_hale_opens_the_west_road() -> void:
	var wt := _area("woodland_town")
	var west := wt.entity("west_exit") as WarpEntity
	assert_eq(west.target_area, StringName(VILLAGE), "the west road leads to Deepwood Village")
	assert_eq(west.target_entry, &"east_road", "onto its east road")
	var s := _past()
	assert_false(west.is_open(s), "shut until the Wardens open it")
	assert_not_null(west.locked_scene, "and it says so")
	var hale := wt.entity("hale")
	await StoryScriptRunner.run_list(hale.on_interact, ScriptContext.new(s, PickHost.new(), null, "woodland_town"))
	assert_true(s.has_flag("world.deepwood_open"), "asking Warden Hale opens it")
	assert_true(west.is_open(s), "the road is open")
	var before := StoryFixture.sent_off(StoryState.new())
	await StoryScriptRunner.run_list(hale.on_interact, ScriptContext.new(before, PickHost.new(), null, "woodland_town"))
	assert_false(before.has_flag("world.deepwood_open"), "never before the opening is over")


# --- Nyra, the Deepwood chief -------------------------------------------------------------------

func test_nyra_is_a_scaled_chief_duel_inside_the_band() -> void:
	var spec := _nyra_spec()
	assert_not_null(spec, "talking to Nyra starts a duel")
	if spec == null:
		return
	assert_eq(spec.kind, BattleSpec.Kind.DUEL, "a chief battle is a duel (#50)")
	assert_eq(spec.level_mode, BattleSpec.LevelMode.SCALED, "chiefs scale (#80)")
	assert_eq(Vector2i(spec.scale_min, spec.scale_max), BAND, "inside the Deep Woods band")
	assert_true(spec.boss_battle, "a boss battle for XP")
	assert_eq(spec.resolved_enemy_level(_party_at(3)), BAND.x, "never below the band")
	assert_eq(spec.resolved_enemy_level(_party_at(40)), BAND.y, "never above it")
	var mid: int = spec.resolved_enemy_level(_party_at(11))
	assert_true(mid >= BAND.x and mid <= BAND.y and mid >= 11, "follows the party inside it (%d)" % mid)
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues, [] as Array[String], "the spec validates (duel-eligible team): %s" % str(issues))
	assert_between(spec.opponent_team.size(), 2, 3, "two or three creatures")
	for row in spec.opponent_team:
		assert_ne(String(row["character_id"]), "eldroot", "Eldroot is the legend, never hers")
	var last: float = float(spec.opponent_team.back()["strength"])
	assert_gt(last, float(spec.opponent_team[0]["strength"]), "her FINAL creature carries the stone placeholder (#67)")
	var fm := FieldMoveResource.load_by_id("treefell")
	assert_not_null(fm, "the tree-felling field move ships")
	for f in [fm.unlock_flag, "world.depths_of_the_wood_open", "deepwood.nyra_beaten"]:
		assert_true(spec.reward_flags.has(f), "winning sets %s" % f)
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.WHITEOUT,
		"a loss wakes you at the Wayshrine and she waits (a story duel has no Try Again screen)")


func test_the_trail_north_waits_on_nyra() -> void:
	var north := _area(VILLAGE).entity("north_exit") as WarpEntity
	assert_eq(north.target_area, StringName(DEPTHS), "the trail north leads into the Depths")
	assert_false(north.is_open(_past(["world.deepwood_open"])), "shut before Nyra is beaten")
	assert_not_null(north.locked_scene, "and it says why")
	var won: Array = ["world.deepwood_open"]
	won.append_array(_nyra_spec().reward_flags)
	assert_true(north.is_open(_past(won)), "open once she is (her win's reward flags)")


# --- Eldroot, the legend ------------------------------------------------------------------------

func test_eldroot_is_a_fixed_tactical_legend_above_the_band() -> void:
	var spec := _eldroot_spec()
	assert_not_null(spec, "facing Eldroot starts a tactical battle")
	if spec == null:
		return
	var lv: int = BAND.y + ProgressionRules.current().legend_over_band
	assert_eq(spec.kind, BattleSpec.Kind.TACTICAL, "legend battles are the tactical ones (#74)")
	assert_eq(spec.level_mode, BattleSpec.LevelMode.FIXED, "legends never scale (#81)")
	assert_eq(spec.enemy_level, lv, "band max + legend_over_band")
	assert_gt(spec.enemy_level, BAND.y, "above the Deep Woods band")
	assert_eq(spec.resolved_enemy_level(_party_at(3)), lv, "whatever the party's level...")
	assert_eq(spec.resolved_enemy_level(_party_at(40)), lv, "...it never moves")
	assert_true(spec.boss_battle, "a boss battle for XP")
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.RETRY, "a loss offers Try Again")
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues, [] as Array[String], "its board validates: %s" % str(issues))
	var m := load(spec.map_path) as MapResource
	var boss: int = 0
	var guests: Array = []
	var chairs: int = 0
	for sp in m.unit_spawns:
		var pid: int = int(sp.get("player_id", -1))
		if pid == 1 and String(sp.get("character_id", "")) == "eldroot":
			boss += 1
		if pid == 0 and String(sp.get("spawn_kind", "")) == MapResource.SPAWN_KIND_REINFORCEMENT:
			guests.append(sp)
		elif pid == 0:
			chairs += 1
	assert_eq(boss, 1, "Eldroot stands on its board")
	assert_eq(chairs, spec.squad_size, "a chair per squad slot")
	assert_eq(guests.size(), 1, "Lyra fights beside you as a guest (#56 / #74)")
	if guests.size() == 1:
		assert_eq(int(guests[0].get("spawn_turn", 0)), 1, "placed at load, like the first fight's allies")
		assert_not_null(CharacterLibrary.get_character(String(guests[0].get("character_id", ""))),
			"her placeholder unit is a real roster entry")


func test_a_breakable_tree_hides_the_glade_until_it_is_felled() -> void:
	var a := _area(DEPTHS)
	var s := _past(["world.deepwood_open", "world.depths_of_the_wood_open", "fieldmove.treefell"])
	var start: Vector3i = a.entry("south")["cell"]
	var gate := a.entity("gate_tree") as FieldObstacleEntity
	assert_not_null(gate, "a breakable tree stands in the wall")
	var g := OverworldGrid.build(a, s)
	assert_false(g.is_walkable(gate.cell), "it blocks its cell")
	assert_false(TapPathfinder.path_to_adjacent(g, start, gate.cell).is_empty(), "it can be reached and checked")
	assert_true(TapPathfinder.find_path(g, start, Vector3i(12, 7, 0)).is_empty(), "the glade is cut off behind it")
	assert_false(a.entity("eldroot").is_present(s), "and Eldroot is hidden")
	var cmds: Array = gate.interact_script(DEPTHS, s)
	assert_true(not cmds.is_empty() and cmds[0] is ChoiceCommand, "the move is ready: Use it?")
	await StoryScriptRunner.run_list(cmds, ScriptContext.new(s, PickHost.new(), null, DEPTHS))
	assert_false(gate.is_present(s), "Yes fells it")
	g.rebuild_blockers(a, s)
	assert_true(g.is_walkable(gate.cell), "its cell is open ground now")
	assert_false(TapPathfinder.find_path(g, start, Vector3i(12, 7, 0)).is_empty(), "the way to the glade is open")
	assert_true(a.entity("eldroot").is_present(s), "Eldroot waits there")
	assert_false(TapPathfinder.path_to_adjacent(g, start, a.entity("eldroot").cell).is_empty(), "and can be reached")
	# Without the move: a hint, nothing felled.
	var locked := _past(["world.deepwood_open", "world.depths_of_the_wood_open"])
	var hint: Array = gate.interact_script(DEPTHS, locked)
	assert_true(hint.size() == 1 and hint[0] is SayCommand, "locked: one hint line, no question")


func test_the_nook_chest_appears_once_its_tree_is_felled() -> void:
	var a := _area(DEPTHS)
	var s := _past(["world.depths_of_the_wood_open"])
	var chest := a.entity("nook_chest")
	assert_false(chest.is_present(s), "the chest is hidden behind its tree")
	s.set_flag(FieldObstacleEntity.flag_for(DEPTHS, "nook_tree"), 1)
	assert_true(chest.is_present(s), "and found once it is felled")
	var g := OverworldGrid.build(a, s)
	assert_false(TapPathfinder.path_to_adjacent(g, a.entry("south")["cell"], chest.cell).is_empty(), "reachable")


func test_the_bond_offer_records_the_legend_and_not_a_party_member() -> void:
	var gate_flag: String = FieldObstacleEntity.flag_for(DEPTHS, "gate_tree")
	var s := _past(["world.depths_of_the_wood_open", gate_flag, "deepwood.eldroot_beaten"])
	var size_before: int = s.party.size()
	var eldroot := _area(DEPTHS).entity("eldroot")
	var host := PickHost.new()
	host.pick = 1
	await StoryScriptRunner.run_list(eldroot.on_interact, ScriptContext.new(s, host, null, DEPTHS))
	assert_true(s.legends.is_empty(), "declining is allowed: catching a legend is optional (#75)")
	assert_true(eldroot.is_present(s), "and Eldroot stays, to be asked again")
	host.pick = 0
	await StoryScriptRunner.run_list(eldroot.on_interact, ScriptContext.new(s, host, null, DEPTHS))
	assert_eq(s.legends, ["eldroot"] as Array[String], "bonding records Eldroot in the legend list")
	assert_eq(s.party.size(), size_before, "the party is unchanged (#39: legends do not accompany the hero)")
	assert_false(s.party_has("eldroot"), "Eldroot is not a party member")
	assert_false(eldroot.is_present(s), "and it leaves the glade")
	# Journey -> Party lists it, read-only, under Legends (never as a member card).
	var jm := JourneyMenu.new()
	jm.session = StoryController
	add_child_autofree(jm)
	jm.open(s)
	jm.show_party()
	await get_tree().process_frame
	assert_not_null(jm.find_child("LegendsHeading", true, false), "a Legends section")
	assert_not_null(jm.find_child("Legend_eldroot", true, false), "Eldroot is listed there")
	assert_null(jm.member_card("eldroot"), "with no party card")
	jm.close()


func test_the_deep_woods_grass_holds_the_forest_creatures_in_band() -> void:
	var a := _area(DEPTHS)
	assert_false(a.zones().is_empty(), "the Depths have wild grass")
	for z in a.zones():
		assert_eq(z.band_in(a), BAND, "rolls in the Deep Woods band")
		for row in z.table:
			var e := row as EncounterEntry
			assert_ne(String(e.character_id), "eldroot", "the legend is never a grass encounter")
			assert_not_null(CharacterLibrary.get_character(e.character_id), "%s exists" % e.character_id)
	assert_true(_area(VILLAGE).zones().is_empty(), "a village has no wild grass")


# --- Lyra -----------------------------------------------------------------------------------------

func _lyras() -> Array:
	var out: Array = []
	for id in StoryController.all_area_ids():
		var a := _area(id)
		for e in a.entity_list():
			if e is NpcEntity and (e as NpcEntity).display_name == "Lyra":
				out.append([id, e])
	return out


func test_lyra_is_never_in_two_places_at_once() -> void:
	var lyras: Array = _lyras()
	assert_gte(lyras.size(), 4, "Lyra: the workshop, the south gate, the arena, Deepwood")
	var stages: Array[StoryState] = [StoryState.new()]
	for i in range(StoryFixture.OPENING_FLAGS.size()):
		var s := StoryState.new()
		for f in StoryFixture.OPENING_FLAGS.slice(0, i + 1):
			s.set_flag(f, 1)
		stages.append(s)
	var extra: Array[String] = ["rival.duel1", "world.deepwood_open", "deepwood.nyra_beaten", "deepwood.eldroot_beaten"]
	for mask in range(1 << extra.size()):
		for base in [StoryFixture.sent_off(StoryState.new()), StoryFixture.past_opening(StoryState.new())]:
			var s: StoryState = base
			for b in range(extra.size()):
				if mask & (1 << b):
					s.set_flag(extra[b], 1)
			stages.append(s)
	for s in stages:
		var here: Array[String] = []
		for pair in lyras:
			if (pair[1] as NpcEntity).is_present(s):
				here.append("%s/%s" % [pair[0], (pair[1] as NpcEntity).id])
		assert_lte(here.size(), 1, "one Lyra at a time (flags %s): %s" % [str(s.flags.keys()), str(here)])
	# Where she is: Deepwood from the road opening until the Eldroot battle, then back in Crownhaven.
	var away := _past(["rival.duel1", "world.deepwood_open"])
	var back := _past(["rival.duel1", "world.deepwood_open", "deepwood.eldroot_beaten"])
	assert_true(_area(VILLAGE).entity("lyra").is_present(away), "she is in Deepwood Village (#88)")
	assert_false(_area("crownhaven").entity("lyra_arena").is_present(away), "not at the arena meanwhile")
	assert_false(_area(VILLAGE).entity("lyra").is_present(back), "after the legend battle she leaves Deepwood")
	assert_true(_area("crownhaven").entity("lyra_arena").is_present(back), "and is back at the arena")


# --- The quest ------------------------------------------------------------------------------------

func test_the_tracker_points_at_deepwood_then_nyra_then_the_depths() -> void:
	var s := _past(["act1.met_rowan"])
	var e: Dictionary = QuestLog.tracked_entry(s)
	assert_eq(String(e.get("id", "")), "deep_woods", "after Grow Stronger the tracker follows the Deep Woods")
	assert_eq(String(e["npc"]), "hale", "first: ask Warden Hale")
	s.set_flag("world.deepwood_open", 1)
	e = QuestLog.tracked_entry(s)
	assert_eq(String(e["location"]), VILLAGE, "then Deepwood Village")
	assert_eq(String(e["npc"]), "nyra", "and Nyra")
	s.set_flag("deepwood.nyra_beaten", 1)
	assert_eq(String(QuestLog.tracked_entry(s).get("location", "")), DEPTHS, "then the Depths")
	s.set_flag("deepwood.eldroot_beaten", 1)
	assert_false(QuestLog.is_active(s, "deep_woods"), "done once Eldroot is beaten (bonding is optional)")
