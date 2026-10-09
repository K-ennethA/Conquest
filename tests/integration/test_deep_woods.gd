extends GutTest

## THE DEEP WOODS story slice (docs/design/DECISIONS.md #38-#41, #50, #56, #67, #71, #74, #75, #80,
## #81, #85, #88, #92-#94) against the SHIPPED content (build_story_content.gd):
##   * the places are built on the world map, in the Deep Woods band, west of Woodland Town;
##   * Warden Hale opens the west road; NYRA is a SCALED chief DUEL inside the band whose win opens
##     the trail north and makes the tree-felling field move teachable; she then TEACHES it to an
##     eligible member (#92) -- and again to another on a later visit;
##   * LYRA challenges the hero to a friendly spar, then keeps him company as a TEMPORARY member (no
##     overworld follower) until Eldroot is beaten (#94); skipping her is fine;
##   * the Depths are a MAZE (#93): look-alike rooms, the right exit marked by LIGHTS, the wrong ones
##     back to the entrance, BREAKABLE TREES blocking the right way so the move is required;
##   * ELDROOT waits in the clearing at the end: a TACTICAL legend FIXED above the band, Try Again on
##     a loss; the optional bond records the legend, never a party member;
##   * LYRA is never in two places at once.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const BAND := Vector2i(8, 15)
const DEPTHS := "depths_of_the_wood"
const HEART := "depths_of_the_wood_heart"
const VILLAGE := "deepwood_village"
## The maze, in order, and each room's right exit.
const ROOMS: Array[String] = ["depths_of_the_wood", "depths_of_the_wood_2", "depths_of_the_wood_3", "depths_of_the_wood_4"]
const EXIT_IDS: Array[String] = ["north_exit", "south_exit", "west_exit", "east_exit"]


class PickHost extends StoryScriptHost:
	var pick: int = 0
	var choices: int = 0
	var toasts: Array[String] = []
	var said: Array[String] = []

	func show_choice(_prompt: StoryBeat, _options: PackedStringArray, _cancel_index: int = -1) -> int:
		choices += 1
		return pick

	func toast(text: String, _kind: String = "") -> void:
		toasts.append(text)


## A stand-in session: every battle ends with [member outcome].
class FakeSession extends RefCounted:
	var outcome: String = BattleResult.OUTCOME_VICTORY
	var requests: Array = []

	func run_battle(request: BattleRequest) -> BattleResult:
		requests.append(request)
		var r := BattleResult.new()
		r.outcome = outcome
		return r


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


func _duel_in(area_id: String, npc: String) -> BattleSpec:
	for c in _flatten(_area(area_id).entity(npc).on_interact):
		if c is StartDuelCommand:
			return (c as StartDuelCommand).spec
	return null


func _nyra_spec() -> BattleSpec:
	return _duel_in(VILLAGE, "nyra")


func _eldroot_spec() -> BattleSpec:
	for c in _flatten(_area(HEART).entity("eldroot").on_interact):
		if c is StartBattleCommand and not (c is StartDuelCommand):
			return (c as StartBattleCommand).spec
	return null


func _party_at(top: int) -> StoryState:
	var s := _past()
	s.party.clear()
	s.add_member("tree_grunt", "", 6, top)
	return s


func _warp(area_id: String, id: String) -> WarpEntity:
	return _area(area_id).entity(id) as WarpEntity


## The exit of maze room [param i] that leads on (the next room, or the heart).
func _right_exit(i: int) -> WarpEntity:
	var next: String = ROOMS[i + 1] if i + 1 < ROOMS.size() else HEART
	for id in EXIT_IDS:
		var w := _warp(ROOMS[i], id)
		if w != null and String(w.target_area) == next:
			return w
	return null


# --- The places ------------------------------------------------------------------------------

func test_the_deep_woods_are_built_on_the_world_map() -> void:
	var atlas := WorldAtlas.load_default()
	var village := atlas.location(VILLAGE)
	assert_true(village.is_built() and village.area_ids.has(StringName(VILLAGE)), "Deepwood Village is built")
	var depths := atlas.location(DEPTHS)
	assert_true(depths.is_built(), "the Depths are built")
	var all: Array[String] = ROOMS.duplicate()
	all.append(HEART)
	for id in all:
		assert_true(depths.area_ids.has(StringName(id)), "%s is one of the Depths' areas" % id)
		assert_eq(String(atlas.location_for_area(id).id), DEPTHS, "%s sits at the Depths on the map" % id)
	for id in [VILLAGE] + all:
		var a := _area(id)
		assert_not_null(a, "%s loads" % id)
		assert_eq(a.region_id, &"woodlands", "%s is in the Deep Woods" % id)
		assert_eq(a.level_band, BAND, "%s rolls in the Deep Woods band" % id)
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
	assert_eq(north.target_area, StringName(DEPTHS), "the trail north leads into the maze's first room")
	assert_eq(north.target_entry, &"south", "at its south edge")
	assert_false(north.is_open(_past(["world.deepwood_open"])), "shut before Nyra is beaten")
	assert_not_null(north.locked_scene, "and it says why")
	var won: Array = ["world.deepwood_open"]
	won.append_array(_nyra_spec().reward_flags)
	assert_true(north.is_open(_past(won)), "open once she is (her win's reward flags) -- Lyra's challenge is not needed")


func test_winning_against_nyra_teaches_the_move() -> void:
	# The duel is fought for real (a stand-in session reports a victory and the script applies her
	# reward flags as the session would); then she teaches the move to the member the player picks.
	var s := _past(["world.deepwood_open"])
	s.add_hero("wren", "Wren", 9)
	var host := PickHost.new()
	host.pick = 1   # [Wren, Vineweave, Blightcap, Not now] -> the Vineweave
	var session := FakeSession.new()
	var nyra := _area(VILLAGE).entity("nyra")
	var teaches: int = 0
	for c in _flatten(nyra.on_interact):
		if c is TeachFieldMoveCommand:
			teaches += 1
			assert_eq(String((c as TeachFieldMoveCommand).move_id), "treefell")
		assert_false(c is JoinPartyCommand, "Lyra no longer joins on Nyra's win (she challenges you herself)")
	assert_gt(teaches, 0, "Nyra teaches the field move")
	# Her win's flags (StoryController sets them from the spec on a victory).
	for f in _nyra_spec().reward_flags:
		s.set_flag(f, 1)
	# The "already beaten" branch: talk to her -> she teaches.
	await StoryScriptRunner.run_list(nyra.on_interact, ScriptContext.new(s, host, session, VILLAGE))
	assert_true(s.member("vineweave").knows_field_move("treefell"), "the picked member learned it")
	assert_false(s.hero_member().knows_field_move("treefell"), "only that one")
	assert_true(s.has_flag("deepwood.treefell_learned"), "the quest's learned flag")
	# Later: she teaches it to another eligible member.
	host.pick = 0
	await StoryScriptRunner.run_list(nyra.on_interact, ScriptContext.new(s, host, session, VILLAGE))
	assert_true(s.hero_member().knows_field_move("treefell"), "a later visit teaches another (the hero, #71)")


func test_with_nobody_eligible_nyra_says_come_back() -> void:
	var s := _past(["world.deepwood_open", "deepwood.nyra_beaten", "fieldmove.treefell", "world.depths_of_the_wood_open"])
	s.party.clear()
	s.add_member("undead", "", 6, 9)
	var host := PickHost.new()
	await StoryScriptRunner.run_list(_area(VILLAGE).entity("nyra").on_interact, ScriptContext.new(s, host, null, VILLAGE))
	assert_false(s.party_knows_field_move("treefell"), "nobody learned it")
	assert_eq(host.choices, 0, "no question")
	s.add_member("tree_grunt", "", 6, 9)
	await StoryScriptRunner.run_list(_area(VILLAGE).entity("nyra").on_interact, ScriptContext.new(s, host, null, VILLAGE))
	assert_true(s.member("tree_grunt").knows_field_move("treefell"), "come back with one who can: it learns it")


# --- Lyra's challenge and company (#94) -----------------------------------------------------------

func test_lyra_challenges_you_to_a_friendly_spar_in_the_band() -> void:
	var spec := _duel_in(VILLAGE, "lyra")
	assert_not_null(spec, "talking to Lyra in Deepwood starts a duel")
	if spec == null:
		return
	assert_eq(spec.kind, BattleSpec.Kind.DUEL)
	assert_eq(spec.encounter_id, "deepwood.rival.lyra", "her own encounter id")
	assert_true(spec.spar, "a friendly test, never permadeath (#60)")
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.CONTINUE, "a loss costs nothing")
	assert_eq(spec.level_mode, BattleSpec.LevelMode.SCALED, "levelled with the party ...")
	assert_eq(Vector2i(spec.scale_min, spec.scale_max), BAND, "... inside the Deep Woods band")
	assert_false(spec.boss_battle, "a rival, not a chief")
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues, [] as Array[String], "validates: %s" % str(issues))


func _run_lyra(s: StoryState, outcome: String, pick: int = 0) -> void:
	var host := PickHost.new()
	host.pick = pick
	var session := FakeSession.new()
	session.outcome = outcome
	await StoryScriptRunner.run_list(_area(VILLAGE).entity("lyra").interact_script(VILLAGE, s),
		ScriptContext.new(s, host, session, VILLAGE))


func test_after_her_challenge_lyra_keeps_you_company_whatever_the_outcome() -> void:
	for outcome in [BattleResult.OUTCOME_VICTORY, BattleResult.OUTCOME_DEFEAT]:
		var s := _past(["world.deepwood_open"])
		s.add_hero("wren", "Wren", 11)
		var lyra_npc := _area(VILLAGE).entity("lyra")
		assert_true(lyra_npc.is_present(s), "she is in the village")
		await _run_lyra(s, outcome, 1)
		assert_false(s.party_has("lyra"), "Not now: nothing happens (she blocks nothing)")
		await _run_lyra(s, outcome, 0)
		assert_true(s.has_flag("deepwood.lyra_challenged"), "the bout was fought (%s)" % outcome)
		var lyra: StoryPartyMember = s.member("lyra")
		assert_not_null(lyra, "she joins (%s)" % outcome)
		if lyra == null:
			continue
		assert_true(lyra.is_temporary(), "a temporary member (#61)")
		assert_eq(lyra.guest_until, "deepwood.eldroot_beaten", "until Eldroot is beaten")
		assert_eq(lyra.level, s.party_top_level(), "at the party's level")
		assert_false(lyra_npc.is_present(s), "and she is no overworld character while she follows you")
		s.set_flag("deepwood.eldroot_beaten", 1)
		assert_false(s.party_has("lyra"), "she leaves once the legend battle is won")


func test_lyra_waits_if_the_bout_could_not_be_fought() -> void:
	var s := _past(["world.deepwood_open"])
	await _run_lyra(s, BattleResult.OUTCOME_ABORTED, 0)
	assert_false(s.has_flag("deepwood.lyra_challenged"), "an aborted bout is no challenge")
	assert_false(s.party_has("lyra"))
	assert_true(_area(VILLAGE).entity("lyra").is_present(s), "she waits in the village")


func test_eldroot_offers_lyra_only_when_she_came_along() -> void:
	var spec := _eldroot_spec()
	var with_her := _past(["world.deepwood_open", "deepwood.lyra_challenged"])
	with_her.add_hero("wren", "Wren", 12)
	with_her.join("lyra", "", 6, 12, true, "deepwood.eldroot_beaten")
	var req: BattleRequest = spec.to_request(BattleRequest.SOURCE_SCRIPT, "")
	var cands: Array[Dictionary] = SquadPick.candidates(with_her, req)
	var ids: Array = cands.map(func(c): return String(c["character_id"]))
	assert_true(ids.has("lyra"), "Lyra is selectable in the squad pick: %s" % str(ids))
	assert_eq(ids[0], "wren", "the hero first")
	var without := _past(["world.deepwood_open"])
	without.add_hero("wren", "Wren", 12)
	var cands2: Array[Dictionary] = SquadPick.candidates(without, spec.to_request(BattleRequest.SOURCE_SCRIPT, ""))
	assert_false(cands2.map(func(c): return String(c["character_id"])).has("lyra"), "skipped her challenge: not offered")
	assert_false(SquadPick.default_picks(cands2, spec.squad_size).is_empty(), "and the battle still fields a squad")
	# Her company never puts her in the party's duels.
	assert_false(with_her.duel_lineup(1, false).any(func(m): return m.character_id == "lyra"), "no duels for the guest")


# --- The maze (#93) -------------------------------------------------------------------------------

func test_the_maze_rooms_chain_and_the_wrong_ways_lead_back_to_the_entrance() -> void:
	assert_between(ROOMS.size(), 4, 6, "small enough to be fun")
	for i in range(ROOMS.size()):
		var id: String = ROOMS[i]
		var a := _area(id)
		assert_eq(a.display_name, "Depths of the Wood", "%s looks like every other room (one name)" % id)
		assert_eq(Vector2i(a.width(), a.height()), Vector2i(_area(ROOMS[0]).width(), _area(ROOMS[0]).height()), "%s: one size" % id)
		var right := _right_exit(i)
		assert_not_null(right, "%s has a way on" % id)
		var south := _warp(id, "south_exit")
		if i == 0:
			assert_eq(String(south.target_area), VILLAGE, "the entrance's south edge leads home")
		else:
			assert_eq(String(south.target_area), ROOMS[i - 1], "%s: south goes back a room" % id)
			assert_eq(south.target_entry, &"back", "arriving at that room's right exit")
		var wrong: int = 0
		for eid in EXIT_IDS:
			var w := _warp(id, eid)
			assert_not_null(w, "%s has a %s" % [id, eid])
			if w == null or w == right or w == south:
				continue
			wrong += 1
			assert_eq(String(w.target_area), ROOMS[0], "%s/%s: a wrong way leads back to the entrance" % [id, eid])
			assert_eq(w.target_entry, &"south", "to its start")
			assert_false(w.arrival_toast.is_empty(), "with a short toast")
			assert_true(w.requires.is_empty(), "never locked")
		assert_eq(wrong, 2, "%s: two wrong ways" % id)
		assert_eq(right.target_entry, &"south", "the next room starts at its south edge")
	# The heart's way back.
	assert_eq(String(_warp(HEART, "south_exit").target_area), ROOMS[ROOMS.size() - 1])


func test_lit_lanterns_mark_the_right_exit_in_every_room() -> void:
	# Every CHOICE exit (north / west / east) has a pair of lantern posts at its mouth, so the exits
	# look alike; only the RIGHT one's are lit (PropEntity.glow), the wrong ones stay dark.
	for i in range(ROOMS.size()):
		var a := _area(ROOMS[i])
		var right := _right_exit(i)
		var exit_cell: Vector3i = right.cells()[0]
		var lit: Array = []
		var dark: Array = []
		for e in a.entity_list():
			if e is PropEntity and String(e.id).begins_with("light_"):
				if (e as PropEntity).glow > 0.0:
					lit.append(e)
				else:
					dark.append(e)
		assert_eq(lit.size(), 2, "%s: a pair of LIT lanterns" % ROOMS[i])
		assert_eq(dark.size(), 4, "%s: dark pairs at the two wrong exits" % ROOMS[i])
		for l in lit:
			var d: Vector3i = (l as PropEntity).cell - exit_cell
			assert_lte(absi(d.x) + absi(d.y), 3, "%s/%s stands at the right exit's mouth" % [ROOMS[i], l.id])
		for l in dark:
			var d: Vector3i = (l as PropEntity).cell - exit_cell
			assert_gt(absi(d.x) + absi(d.y), 3, "%s/%s (dark) is not at the right exit" % [ROOMS[i], l.id])
		# ... and fireflies over the right corridor's ground (sacred meadow), never at a wrong exit.
		for eid in EXIT_IDS:
			var w := _warp(ROOMS[i], eid)
			var tid: String = String(a.terrain.get_tile_at_position(Vector2i(w.cells()[0].x, w.cells()[0].y)).get("tile_id", ""))
			if w == right:
				assert_eq(tid, "sacred_meadow", "%s: the right way glows" % ROOMS[i])
			else:
				assert_ne(tid, "sacred_meadow", "%s/%s: a wrong way does not" % [ROOMS[i], eid])


func test_a_lit_lantern_gets_a_glowing_head_and_a_light() -> void:
	var n: Node3D = OverworldProps.prop("lamp", Vector2i.ONE, Color(0.85, 1.0, 0.55), 0)
	assert_null(n.find_child("Glow", true, false), "an unlit lantern has no light")
	OverworldProps.add_glow(n, "lamp", Color(0.85, 1.0, 0.55), 2.4)
	var light := n.find_child("Glow", true, false) as OmniLight3D
	assert_not_null(light, "a lit one does")
	if light != null:
		assert_almost_eq(light.light_energy, 2.4, 0.001)
		assert_gt(light.position.y, 2.0, "at the lantern head")
	var head := n.find_child("GlowHead", true, false) as MeshInstance3D
	assert_not_null(head, "and an emissive head")
	if head != null:
		assert_true((head.material_override as StandardMaterial3D).emission_enabled)
	n.free()


func test_each_room_is_enclosed_by_forest() -> void:
	# A Lost-Woods room: walls of old trees; the walkable ground is a small share of the room, and
	# every exit is reached only along its 1-wide corridor (the cells beside it are wall or a post).
	for id in ROOMS:
		var a := _area(id)
		var g := OverworldGrid.from_map(a.terrain)
		var open: int = 0
		for y in range(a.height()):
			for x in range(a.width()):
				if g.is_terrain_passable(Vector3i(x, y, 0)):
					open += 1
		assert_lt(float(open) / float(a.width() * a.height()), 0.45, "%s: mostly forest wall (%d open cells)" % [id, open])
		var full := OverworldGrid.build(a, _past())
		for eid in EXIT_IDS:
			var c: Vector3i = _warp(id, eid).cells()[0]
			var along := Vector3i.ZERO
			if c.y == 0:
				along = Vector3i(0, 1, 0)
			elif c.y == a.height() - 1:
				along = Vector3i(0, -1, 0)
			elif c.x == 0:
				along = Vector3i(1, 0, 0)
			else:
				along = Vector3i(-1, 0, 0)
			var side := Vector3i(along.y, along.x, 0)
			for k in range(0, 3):
				var cc: Vector3i = c + along * k
				for s in [side, -side]:
					assert_false(full.is_walkable(cc + s), "%s/%s: the corridor is walled at %s" % [id, eid, str(cc + s)])


func test_breakable_trees_block_the_right_way_until_felled() -> void:
	var s := _past(["world.deepwood_open", "world.depths_of_the_wood_open", "deepwood.nyra_beaten", "fieldmove.treefell"])
	s.party[0].learn_field_move("treefell")
	var gated: int = 0
	for i in range(ROOMS.size()):
		var a := _area(ROOMS[i])
		var start: Vector3i = a.entry("south")["cell"]
		var exit_cell: Vector3i = _right_exit(i).cells()[0]
		var g := OverworldGrid.build(a, s)
		# Every exit is a real choice: the wrong ones can be walked to.
		for eid in EXIT_IDS:
			if eid == "south_exit":
				continue
			var w := _warp(ROOMS[i], eid)
			if w == _right_exit(i):
				continue
			assert_false(TapPathfinder.find_path(g, start, w.cells()[0]).is_empty(), "%s/%s can be walked to" % [ROOMS[i], eid])
		var gate := a.entity("gate_tree") as FieldObstacleEntity
		if gate == null:
			assert_false(TapPathfinder.find_path(g, start, exit_cell).is_empty(), "%s: the right way is open" % ROOMS[i])
			continue
		gated += 1
		assert_true(TapPathfinder.find_path(g, start, exit_cell).is_empty(), "%s: the gate tree cuts the right way" % ROOMS[i])
		assert_false(TapPathfinder.path_to_adjacent(g, start, gate.cell).is_empty(), "%s: the tree can be reached" % ROOMS[i])
		# Without anyone who learned it: a hint, nothing felled.
		var nobody := _past(["world.depths_of_the_wood_open", "fieldmove.treefell"])
		var hint: Array = gate.interact_script(ROOMS[i], nobody)
		assert_true(hint.size() == 1 and hint[0] is SayCommand, "%s: no learner -> one hint line" % ROOMS[i])
		var cmds: Array = gate.interact_script(ROOMS[i], s)
		assert_true(not cmds.is_empty() and cmds[0] is ChoiceCommand, "learned: Use it?")
		await StoryScriptRunner.run_list(cmds, ScriptContext.new(s, PickHost.new(), null, ROOMS[i]))
		assert_false(gate.is_present(s), "%s: Yes fells it" % ROOMS[i])
		assert_true(s.has_flag(FieldObstacleEntity.flag_for(ROOMS[i], "gate_tree")), "for good (a saved flag)")
		g.rebuild_blockers(a, s)
		assert_false(TapPathfinder.find_path(g, start, exit_cell).is_empty(), "%s: the way on is open" % ROOMS[i])
	assert_gte(gated, 2, "the skill is REQUIRED in at least two rooms")


func test_the_whole_maze_can_be_walked_to_eldroot() -> void:
	# Room by room, entrance to heart, with every gate tree felled: the right exit is reachable, and
	# it leads to the next room's south entry.
	var s := _past(["world.depths_of_the_wood_open"])
	for id in ROOMS:
		s.set_flag(FieldObstacleEntity.flag_for(id, "gate_tree"), 1)
	var at: String = ROOMS[0]
	var entry: String = "south"
	var steps: int = 0
	while at != HEART and steps < 10:
		steps += 1
		var i: int = ROOMS.find(at)
		var a := _area(at)
		var g := OverworldGrid.build(a, s)
		var w := _right_exit(i)
		assert_false(TapPathfinder.find_path(g, a.entry(entry)["cell"], w.cells()[0]).is_empty(), "%s: walk to the way on" % at)
		at = String(w.target_area)
		entry = String(w.target_entry)
	assert_eq(at, HEART, "the maze ends at the heart of the wood")
	var heart := _area(HEART)
	var eld := heart.entity("eldroot")
	assert_true(eld.is_present(s), "Eldroot waits there")
	assert_false(TapPathfinder.path_to_adjacent(OverworldGrid.build(heart, s), heart.entry("south")["cell"], eld.cell).is_empty(),
		"and can be reached")
	# Every room's back entry stands inside its right exit.
	for i in range(ROOMS.size()):
		var a := _area(ROOMS[i])
		var back: Vector3i = a.entry("back")["cell"]
		var d: Vector3i = back - _right_exit(i).cells()[0]
		assert_eq(absi(d.x) + absi(d.y), 1, "%s: arriving back puts you just inside the right exit" % ROOMS[i])


func test_the_nook_chest_appears_once_its_tree_is_felled() -> void:
	var room := "depths_of_the_wood_3"
	var a := _area(room)
	var s := _past(["world.depths_of_the_wood_open"])
	var chest := a.entity("nook_chest")
	assert_not_null(chest)
	assert_false(chest.is_present(s), "the chest is hidden behind its tree")
	var g := OverworldGrid.build(a, s)
	assert_true(TapPathfinder.path_to_adjacent(g, a.entry("south")["cell"], chest.cell).is_empty(), "walled in")
	s.set_flag(FieldObstacleEntity.flag_for(room, "nook_tree"), 1)
	assert_true(chest.is_present(s), "and found once it is felled")
	g = OverworldGrid.build(a, s)
	assert_false(TapPathfinder.path_to_adjacent(g, a.entry("south")["cell"], chest.cell).is_empty(), "reachable")


func test_the_maze_is_a_pokemon_forest_too() -> void:
	var trainers: int = 0
	var chests: int = 0
	var felled := _past()
	for id in ROOMS:
		felled.set_flag(FieldObstacleEntity.flag_for(id, "gate_tree"), 1)
	for id in ROOMS:
		var a := _area(id)
		assert_false(a.zones().is_empty(), "%s has wild grass" % id)
		for z in a.zones():
			assert_eq(z.band_in(a), BAND, "rolls in the Deep Woods band")
			for row in z.table:
				var e := row as EncounterEntry
				assert_ne(String(e.character_id), "eldroot", "the legend is never a grass encounter")
				assert_not_null(CharacterLibrary.get_character(e.character_id), "%s exists" % e.character_id)
		for e in a.entity_list():
			if e is TrainerEntity:
				trainers += 1
				var t := e as TrainerEntity
				var spec := t.battle
				assert_true(spec.enemy_level >= BAND.x and spec.enemy_level <= BAND.y, "%s fights in the band" % t.id)
				# OPTIONAL: walking the right way never crosses its sight line.
				var g := OverworldGrid.build(a, felled)
				var seen: Array[Vector3i] = TrainerSight.sight_cells(g, t.cell, OverworldEntity.facing_vector(t.facing), t.sight_range)
				var path: Array[Vector3i] = TapPathfinder.find_path(g, a.entry("south")["cell"], _right_exit(ROOMS.find(id)).cells()[0])
				assert_false(path.is_empty(), "%s: the way on" % id)
				for c in seen:
					assert_false(path.has(c), "%s: the way on does not cross %s's sight" % [id, t.id])
			if e is ChestEntity:
				chests += 1
	assert_gte(trainers, 2, "a couple of trainers")
	assert_gte(chests, 2, "an item or two")
	assert_true(_area(VILLAGE).zones().is_empty(), "a village has no wild grass")


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
	assert_eq(guests.size(), 0, "no stand-in: Lyra is deployed from the party through the squad pick")


func test_the_bond_offer_records_the_legend_and_not_a_party_member() -> void:
	var s := _past(["world.depths_of_the_wood_open", "deepwood.eldroot_beaten"])
	var size_before: int = s.party.size()
	var eldroot := _area(HEART).entity("eldroot")
	var host := PickHost.new()
	host.pick = 1
	await StoryScriptRunner.run_list(eldroot.on_interact, ScriptContext.new(s, host, null, HEART))
	assert_true(s.legends.is_empty(), "declining is allowed: catching a legend is optional (#75)")
	assert_true(eldroot.is_present(s), "and Eldroot stays, to be asked again")
	host.pick = 0
	await StoryScriptRunner.run_list(eldroot.on_interact, ScriptContext.new(s, host, null, HEART))
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
	var extra: Array[String] = ["rival.duel1", "world.deepwood_open", "deepwood.lyra_joined", "deepwood.eldroot_beaten"]
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
	e = QuestLog.tracked_entry(s)
	assert_eq(String(e["npc"]), "nyra", "then Nyra again: learn the move")
	s.set_flag("deepwood.treefell_learned", 1)
	assert_eq(String(QuestLog.tracked_entry(s).get("location", "")), DEPTHS, "then the Depths")
	s.set_flag("deepwood.eldroot_beaten", 1)
	assert_false(QuestLog.is_active(s, "deep_woods"), "done once Eldroot is beaten (bonding is optional)")
