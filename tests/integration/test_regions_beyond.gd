extends GutTest

## THE REGIONS PAST THE HEARTLANDS against the SHIPPED content (build_story_content.gd):
##   * the roads to the coast, the peaks and the badlands open once the opening is over;
##   * BEACH VILLAGE (#43 / #85 / #88): Eloi is a SCALED chief duel whose win makes the SEA move teachable;
##     he teaches it to a creature; the sea move is a TRAVEL move -- the water is crossed riding (the islet
##     chest is reached only that way); Cael offers a friendly spar;
##   * FROSTPEAK (#49 / #69 / #95): everyone asleep; resting in an empty inn bed takes the hero into the
##     DREAM; Saevi (disoriented) is a SCALED chief duel there; then a TACTICAL battle against the two
##     mythical creatures (no base to protect); both may be bonded; the hero wakes in the inn and the
##     town with him; a declined creature waits by the pond;
##   * THE BADLANDS (#46 / #57 / #73 / #96): Redrock's villagers talk about strange people going out into
##     the desert; a hooded figure leads the hero to a cave that ends in rock; the PASSWORD (its clue split
##     between a dropped note and a villager) rolls the rock aside; the hideout's guards battle in duels;
##     at its end General Varden joins a TACTICAL battle as a guest -- and is never in two places.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const COAST := Vector2i(12, 20)
const PEAKS := Vector2i(18, 26)
const BADLANDS := Vector2i(22, 30)


## Answers each choice with the next of [member picks] (then the last one again).
class SeqHost extends StoryScriptHost:
	var picks: Array[int] = [0]
	var asked: int = 0
	var toasts: Array[String] = []

	func show_choice(_prompt: StoryBeat, _options: PackedStringArray, _cancel_index: int = -1) -> int:
		var p: int = picks[mini(asked, picks.size() - 1)]
		asked += 1
		return p

	func toast(text: String, _kind: String = "") -> void:
		toasts.append(text)


## A stand-in session: every battle ends with [member outcome], and applies its reward flags (as the
## real StoryController does on a victory); warps are recorded.
class FakeSession extends RefCounted:
	var outcome: String = BattleResult.OUTCOME_VICTORY
	var requests: Array = []
	var warps: Array = []
	var state: StoryState = null

	func run_battle(request: BattleRequest) -> BattleResult:
		requests.append(request)
		if outcome == BattleResult.OUTCOME_VICTORY and state != null:
			for f in request.rewards.get("flags", []):
				state.set_flag(f, 1)
		var r := BattleResult.new()
		r.outcome = outcome
		return r

	func warp_to(area_id: String, entry_id: String, _from: Vector3i = Cells.INVALID, _w = null) -> Dictionary:
		warps.append([area_id, entry_id])
		return {"success": true, "reason": ""}


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


func _battle_in(commands: Array, duel: bool) -> BattleSpec:
	for c in _flatten(commands):
		if c is StartDuelCommand and duel:
			return (c as StartDuelCommand).spec
		if c is StartBattleCommand and not (c is StartDuelCommand) and not duel:
			return (c as StartBattleCommand).spec
	return null


func _party_at(top: int) -> StoryState:
	var s := _past()
	s.party.clear()
	s.add_member("tree_grunt", "", 6, top)
	return s


func _run(commands: Array, s: StoryState, host: StoryScriptHost, area_id: String, session = null) -> void:
	await StoryScriptRunner.run_list(commands, ScriptContext.new(s, host, session, area_id))


## The chief checks every chief duel shares (#50 / #67 / #80).
func _assert_chief(spec: BattleSpec, band: Vector2i, who: String) -> void:
	assert_not_null(spec, "%s starts a duel" % who)
	if spec == null:
		return
	assert_eq(spec.kind, BattleSpec.Kind.DUEL, "%s: a chief battle is a duel (#50)" % who)
	assert_eq(spec.level_mode, BattleSpec.LevelMode.SCALED, "%s: chiefs scale (#80)" % who)
	assert_eq(Vector2i(spec.scale_min, spec.scale_max), band, "%s: inside the region's band" % who)
	assert_true(spec.boss_battle, "%s: a boss battle" % who)
	assert_eq(spec.resolved_enemy_level(_party_at(3)), band.x, "%s: never below the band" % who)
	assert_eq(spec.resolved_enemy_level(_party_at(45)), band.y, "%s: never above it" % who)
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues, [] as Array[String], "%s: the spec validates (duel-eligible team)" % who)
	assert_gt(float(spec.opponent_team.back()["strength"]), float(spec.opponent_team[0]["strength"]),
		"%s: the FINAL creature carries the stone placeholder (#67)" % who)
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.WHITEOUT, "%s: a loss whites out and the chief waits" % who)


# --- The places and their roads --------------------------------------------------------------

func test_the_new_places_are_built_on_the_world_map() -> void:
	var atlas := WorldAtlas.load_default()
	var bands := {"beach_village": COAST, "frostpeak_village": PEAKS, "frostpeak_dream": PEAKS,
		"rocky_badlands": BADLANDS, "redrock_village": BADLANDS, "red_desert": BADLANDS, "badlands_cave": BADLANDS,
		"badlands_hideout": BADLANDS, "badlands_hideout_depths": BADLANDS}
	for id in bands:
		var a := _area(id)
		assert_not_null(a, "%s loads" % id)
		if a == null:
			continue
		assert_eq(a.level_band, bands[id], "%s rolls in its region's band" % id)
		assert_true(atlas.location_for_area(id).is_built(), "%s's place is built" % id)
		assert_eq(a.validate(), [] as Array[String], "%s validates" % id)
	var reach: Array[String] = atlas.reachable_built("oakvale")
	for id in ["beach_village", "frostpeak_village", "rocky_badlands", "redrock_village", "red_desert"]:
		assert_true(reach.has(id), "%s is on the built road network" % id)
	assert_true(atlas.location("secret_hideout").secret, "the hideout stays off the map until found")
	assert_false(atlas.location("secret_hideout").is_known(_past()), "unknown at first")
	assert_true(atlas.location("secret_hideout").is_known(_past(["badlands.hideout_open"])), "known once the rock rolls aside")


func test_the_roads_open_once_the_opening_is_over() -> void:
	# [town, its exit, the flag its on_enter sets, the area the road leads to]
	for spec in [["crownhaven", "harbour_exit", "world.beach_road_open", &"beach_village"],
			["crownhaven", "east_exit", "world.badlands_open", &"rocky_badlands"],
			["river_crossing", "east_exit", "world.beach_road_open", &"beach_village"],
			["woodland_town", "north_exit", "world.frostpeak_open", &"frostpeak_village"]]:
		var town := _area(spec[0])
		var w := town.entity(spec[1]) as WarpEntity
		assert_eq(w.target_area, spec[3], "%s/%s leads to %s" % [spec[0], spec[1], spec[3]])
		var before := StoryFixture.sent_off(StoryState.new())
		await _run(town.on_enter, before, StoryScriptHost.new(), String(spec[0]))
		assert_false(before.has_flag(spec[2]), "%s: shut during the opening" % spec[2])
		assert_false(w.is_open(before), "%s/%s turns you back during the opening" % [spec[0], spec[1]])
		assert_not_null(w.locked_scene, "and says why")
		var after := _past()
		await _run(town.on_enter, after, StoryScriptHost.new(), String(spec[0]))
		assert_true(after.has_flag(spec[2]), "%s: set silently on the next visit after the opening" % spec[2])
		assert_true(w.is_open(after), "%s/%s is open" % [spec[0], spec[1]])


# --- Beach Village: Eloi and the sea ----------------------------------------------------------

func test_eloi_is_a_scaled_chief_duel_in_the_coast_band() -> void:
	var spec := _battle_in(_area("beach_village").entity("eloi").on_interact, true)
	_assert_chief(spec, COAST, "Eloi")
	for f in ["beach.eloi_beaten", "fieldmove.tideride"]:
		assert_true(spec.reward_flags.has(f), "winning sets %s" % f)


func test_winning_against_eloi_teaches_the_sea_move_to_a_creature() -> void:
	var s := _past()
	s.party.clear()
	s.add_hero("wren", "Wren", 14)
	s.add_member("tree_grunt", "", 6, 14)
	var session := FakeSession.new()
	session.state = s
	var host := SeqHost.new()
	host.picks = [0]
	await _run(_area("beach_village").entity("eloi").on_interact, s, host, "beach_village", session)
	assert_eq(session.requests.size(), 1, "the duel was fought")
	assert_true(s.has_flag("beach.eloi_beaten") and s.has_flag("fieldmove.tideride"), "his win's flags")
	assert_true(s.member("tree_grunt").knows_field_move("tideride"), "the creature learned it")
	assert_false(s.hero_member().knows_field_move("tideride"), "never the hero: the sea is crossed WITH a creature (#43)")
	assert_true(s.has_flag("beach.tideride_learned"), "the quest's learned flag")


func test_the_sea_move_is_a_travel_move_over_deep_water() -> void:
	var fm := FieldMoveResource.load_by_id("tideride")
	assert_not_null(fm, "the sea move ships")
	assert_true(fm.is_travel(), "a TRAVEL move")
	assert_true(fm.travel_tiles.has(&"deep_water"), "over deep water")
	assert_true(fm.humans.is_empty(), "creatures only")
	assert_eq(FieldMoveResource.travel_move_for(&"deep_water"), fm, "the water's travel move")
	assert_null(FieldMoveResource.travel_move_for(&"grass_plains"), "land has none")
	assert_false(FieldMoveResource.load_by_id("treefell").is_travel(), "the tree-felling move is an obstacle move")
	var issues: Array[String] = []
	fm.validate(issues)
	assert_eq(issues, [] as Array[String], "it validates")
	assert_eq(fm.status(_past()), FieldMoveResource.STATUS_LOCKED, "locked before Eloi")


func test_the_islet_is_reached_only_by_riding_the_sea() -> void:
	var a := _area("beach_village")
	var g := OverworldGrid.build(a, _past())
	var chest: Vector3i = a.entity("islet_chest").cell
	var reach := func(riding: bool) -> bool:
		var tiles: Array[StringName] = []
		if riding:
			tiles.append(&"deep_water")
		g.riding_tiles = tiles
		var start: Vector3i = a.entry("wayshrine")["cell"]
		var seen: Dictionary = {start: true}
		var queue: Array[Vector3i] = [start]
		while not queue.is_empty():
			var c: Vector3i = queue.pop_front()
			for n in g.walkable_neighbours(c):
				if not seen.has(n):
					seen[n] = true
					queue.append(n)
		for d in OverworldGrid.DIRS:
			if seen.has(chest + Vector3i(d.x, d.y, 0)):
				return true
		return false
	assert_false(reach.call(false), "on foot the islet is out of reach")
	assert_true(reach.call(true), "riding the sea it is not")


func test_the_shore_hints_until_someone_can_ride() -> void:
	var fm := FieldMoveResource.load_by_id("tideride")
	var water := Vector3i(5, 13, 0)
	var locked := RideFieldMoveCommand.script_for(fm, _past(), water)
	assert_true(locked.size() == 1 and locked[0] is SayCommand, "locked: one hint line")
	var nobody := RideFieldMoveCommand.script_for(fm, _past(["fieldmove.tideride"]), water)
	assert_true(nobody.size() == 1 and nobody[0] is SayCommand, "teachable but nobody fit knows it: a hint")
	var s := _past(["fieldmove.tideride"])
	s.party.clear()
	s.add_member("tree_grunt", "", 6, 14)
	s.member("tree_grunt").learn_field_move("tideride")
	var ready := RideFieldMoveCommand.script_for(fm, s, water)
	assert_true(ready.size() == 1 and ready[0] is ChoiceCommand, "ready: Use it?")
	var rides: Array = []
	for c in _flatten(ready):
		if c is RideFieldMoveCommand:
			rides.append(c)
	assert_eq(rides.size(), 1, "Yes rides out")
	assert_eq((rides[0] as RideFieldMoveCommand).to, water, "onto the faced water")


func test_cael_offers_a_friendly_spar() -> void:
	var cael := _area("beach_village").entity("cael")
	assert_not_null(cael, "Cael is met in Beach Village (#88)")
	var spec := _battle_in(cael.on_interact, true)
	assert_true(spec.spar, "a friendly spar: never permadeath")
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.CONTINUE, "a loss costs nothing")
	assert_false(spec.boss_battle, "a rival, not a chief")
	var s := _past()
	var session := FakeSession.new()
	session.state = s
	await _run(cael.on_interact, s, SeqHost.new(), "beach_village", session)
	assert_true(s.has_flag("beach.cael_sparred"), "once fought, he remembers")
	assert_true(DialogueBank.has_entry("beach_village", "cael"), "his greeting is in the bank")


# --- Frostpeak: the sleep and the dream ---------------------------------------------------------

func test_frostpeak_sleeps_until_the_dream_is_set_right() -> void:
	var asleep := _past()
	var awake := _past(["frostpeak.awake"])
	var sleepers: int = 0
	for id in ["frostpeak_village", "frostpeak_inn", "frostpeak_house"]:
		for e in _area(id).entity_list():
			if not (e is NpcEntity) or (e as NpcEntity).asleep_if.is_empty():
				continue
			sleepers += 1
			assert_true((e as NpcEntity).is_asleep(asleep), "%s/%s is asleep" % [id, e.id])
			assert_false((e as NpcEntity).is_asleep(awake), "%s/%s wakes with the town" % [id, e.id])
	assert_gte(sleepers, 8, "the whole town: in the street and in bed")
	assert_true((_area("frostpeak_village").entity("saevi") as NpcEntity).is_asleep(asleep), "the chief too")
	var in_bed: int = 0
	for id in ["frostpeak_inn", "frostpeak_house"]:
		for e in _area(id).entity_list():
			if e is NpcEntity and (e as NpcEntity).sleep_pose == "lie":
				in_bed += 1
				assert_false(e.is_present(awake), "%s is up and about once the town wakes" % e.id)
	assert_gte(in_bed, 3, "some asleep in their beds")


func test_resting_in_an_empty_inn_bed_takes_you_into_the_dream() -> void:
	var inn := _area("frostpeak_inn")
	var bed := inn.entity("bed_a") as PropEntity
	assert_not_null(bed, "an empty bed")
	assert_true(bed.is_interactable() and bed.prompt_verb() == "Rest", "Confirm on it: Rest")
	assert_false(inn.entity("bed_b").is_interactable(), "a bed with a sleeper in it is not yours")
	var s := _past()
	s.member("seedant").current_hp = 1
	var rests: int = s.rests
	var session := FakeSession.new()
	await _run(bed.on_interact, s, SeqHost.new(), "frostpeak_inn", session)
	assert_eq(session.warps, [["frostpeak_dream", "dream_start"]], "into the dream")
	assert_eq(s.rests, rests + 1, "a real rest")
	assert_true(s.member("seedant").is_full_hp(), "the party healed")
	var awake := _past(["frostpeak.awake"])
	session = FakeSession.new()
	await _run(bed.on_interact, awake, SeqHost.new(), "frostpeak_inn", session)
	assert_true(session.warps.is_empty(), "once the town is awake, just an inn rest")
	assert_false(inn.entry("bed").is_empty(), "the bed you wake up beside")


func test_in_the_dream_saevi_is_a_disoriented_chief() -> void:
	var dream := _area("frostpeak_dream")
	assert_eq(dream.lighting_preset(), "Dream", "the dream's own light")
	assert_eq(dream.display_name, "Frostpeak Village", "the same village")
	var spec := _battle_in(dream.entity("saevi").on_interact, true)
	_assert_chief(spec, PEAKS, "Saevi")
	assert_true(spec.reward_flags.has("frostpeak.saevi_beaten"), "winning sets the flag")
	var wake := dream.entity("south_exit") as WarpEntity
	assert_eq(String(wake.target_area), "frostpeak_inn", "the dream's trail wakes you in the inn")
	assert_eq(String(wake.target_entry), "bed", "beside the bed")


func test_the_two_creatures_are_a_tactical_battle_with_no_base_to_protect() -> void:
	var dream := _area("frostpeak_dream")
	var spec := _battle_in(dream.entity("nightmare").on_interact, false)
	assert_not_null(spec, "facing them starts a battle")
	assert_eq(spec.kind, BattleSpec.Kind.TACTICAL, "a TACTICAL battle (#49)")
	assert_eq(spec.opponent_team.size(), 2, "against both")
	assert_true(spec.protect.is_empty(), "nothing to protect (#95)")
	assert_eq(spec.level_mode, BattleSpec.LevelMode.FIXED, "mythical: never scaled, like a legend (#81)")
	assert_eq(spec.enemy_level, Progression.legend_level(PEAKS), "above the band")
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.RETRY, "Try Again on a loss")
	var m := load(spec.map_path) as MapResource
	assert_eq(m.victory_conditions, ["Eliminate All Enemies"] as Array[String], "eliminate all enemies -- no base")
	var bosses: int = 0
	for sp in m.unit_spawns:
		if int(sp.get("player_id", -1)) == 1:
			bosses += 1
	assert_eq(bosses, 2, "the two creatures, and nobody else")
	# Before Saevi: they are lost in their game.
	var s := _past()
	var session := FakeSession.new()
	session.state = s
	await _run(dream.entity("nightmare").on_interact, s, SeqHost.new(), "frostpeak_dream", session)
	assert_true(session.requests.is_empty(), "Saevi first")


func test_beating_them_offers_both_bonds_and_wakes_the_town() -> void:
	var s := _past(["frostpeak.dreaming", "frostpeak.saevi_beaten"])
	var session := FakeSession.new()
	session.state = s
	var host := SeqHost.new()
	host.picks = [0]  # Face them, Bond, Bond
	await _run(_area("frostpeak_dream").entity("dreamer").on_interact, s, host, "frostpeak_dream", session)
	assert_eq(session.requests.size(), 1, "the tactical battle was fought")
	assert_true(s.has_flag("frostpeak.dream_won"), "won")
	assert_eq(s.legends.size(), 2, "both bonded (#69), into the legend list -- not the party")
	assert_true(s.has_flag("mythic.nightmare.bonded") and s.has_flag("mythic.dreamer.bonded"), "their flags")
	assert_true(s.has_flag("frostpeak.awake"), "the town wakes")
	assert_eq(session.warps, [["frostpeak_inn", "bed"]], "and so does the hero, in the inn")


func test_a_declined_creature_waits_by_the_pond() -> void:
	var s := _past(["frostpeak.dreaming", "frostpeak.saevi_beaten"])
	var session := FakeSession.new()
	session.state = s
	var host := SeqHost.new()
	host.picks = [0, 1, 1]  # Face them, Not now, Not now
	await _run(_area("frostpeak_dream").entity("nightmare").on_interact, s, host, "frostpeak_dream", session)
	assert_true(s.legends.is_empty(), "declined")
	assert_true(s.has_flag("frostpeak.awake"), "the town still wakes")
	var village := _area("frostpeak_village")
	for id in ["nightmare", "dreamer"]:
		var e := village.entity(id)
		assert_true(e.is_present(s), "%s waits by the pond" % id)
		host.picks = [0]
		await _run(e.on_interact, s, host, "frostpeak_village")
		assert_false(e.is_present(s), "%s leaves once bonded" % id)
	assert_eq(s.legends.size(), 2, "both bonded in the end")


# --- The badlands: the rumours, the figure, the password, the hideout ---------------------------

func test_redrock_talks_about_strange_people_in_the_desert() -> void:
	var talk: String = ""
	for id in ["rv_elder", "rv_miner", "rv_trader", "rv_watch"]:
		assert_true(DialogueBank.has_entry("redrock_village", id), "%s talks" % id)
		var e: Dictionary = DialogueBank.entry("redrock_village", id)
		for v in e["variants"]:
			for l in v["lines"]:
				talk += String(l["text"]).to_lower() + " "
	assert_true(talk.contains("desert") and talk.contains("badlands"), "the badlands and the desert")
	assert_true(talk.contains("hooded"), "hooded strangers")
	assert_true(talk.contains("ember"), "the miner overheard the password's middle word")


func test_the_hooded_figure_leads_you_into_the_cave() -> void:
	var a := _area("red_desert")
	var fig := a.entity("hooded_figure")
	var note := a.entity("crumpled_note") as SignEntity
	var zones: Array = []
	for e in a.entity_list():
		if e is TriggerZone and String(e.id).begins_with("figure_flees_"):
			zones.append(e)
	assert_eq(zones.size(), 3, "three stages to follow")
	var s := _past()
	assert_true(fig.is_present(s), "standing in the desert")
	assert_false(note.is_present(s), "nothing dropped yet")
	var host := SeqHost.new()
	var moved: Array = []
	for z in zones:
		var live: Array = []
		for zz in zones:
			if zz.is_present(s):
				live.append(zz)
		assert_eq(live, [z], "%s is the one waiting now" % z.id)
		for c in _flatten(z.on_step):
			if c is MoveActorCommand:
				moved.append(Vector2i((c as MoveActorCommand).to.x, (c as MoveActorCommand).to.y))
		await _run(z.step_script("red_desert"), s, host, "red_desert")
		if z == zones[0]:
			assert_true(note.is_present(s), "the first time they bolt, they drop a note")
	assert_eq(moved.back(), Vector2i((a.entity("cave_exit") as WarpEntity).area_rect.position), "the last run is into the cave mouth")
	assert_false(fig.is_present(s), "gone into the cave")
	assert_true(s.has_flag("badlands.figure_entered"), "the quest step")
	assert_true(note.text.contains("DUST") and note.text.contains("CROWN"), "the note: the first and last words")
	assert_false(note.text.to_upper().contains("EMBER"), "the middle is torn away")


func _speak(picks: Array[int]) -> StoryState:
	var s := _past()
	var host := SeqHost.new()
	host.picks = picks
	await _run(_area("badlands_cave").entity("sealed_rock").on_interact, s, host, "badlands_cave")
	return s


func test_the_cave_is_a_dead_end_until_you_speak_the_password() -> void:
	var cave := _area("badlands_cave")
	var rock := cave.entity("sealed_rock") as PropEntity
	var door := cave.entity("hideout_door") as WarpEntity
	var s := _past()
	assert_true(rock.is_present(s) and rock.is_blocking() and rock.is_interactable(), "a rock you can check")
	assert_false(door.is_present(s), "no way on")
	var g := OverworldGrid.build(cave, s)
	assert_false(g.is_walkable(rock.cell), "it blocks the dead end")
	# [Speak, then the word index per slot]: Dust (1), Ember (2), Crown (3) in the shipped choices.
	var right: StoryState = await _speak([0, 1, 2, 3])
	assert_true(right.has_flag("badlands.hideout_open"), "the password rolls the rock aside")
	assert_false(rock.is_present(right), "gone")
	assert_true(door.is_present(right), "the way into the hideout")
	assert_eq(String(door.target_area), "badlands_hideout")
	for wrong in [[0, 0, 2, 3], [0, 1, 2, 0], [0, 3, 1, 2]]:
		var w: Array[int] = []
		w.assign(wrong)
		var tried: StoryState = await _speak(w)
		assert_false(tried.has_flag("badlands.hideout_open"), "a wrong word: nothing happens (%s)" % str(wrong))
	var left: StoryState = await _speak([1])
	assert_false(left.has_flag("badlands.hideout_open"), "Leave it")


func test_the_hideout_guards_battle_in_duels() -> void:
	var guards: int = 0
	for id in ["badlands_hideout", "badlands_hideout_depths"]:
		var g := OverworldGrid.build(_area(id), _past(["badlands.hideout_open"]))
		for e in _area(id).entity_list():
			if not (e is TrainerEntity):
				continue
			guards += 1
			var t := e as TrainerEntity
			assert_eq(t.battle.kind, BattleSpec.Kind.DUEL, "%s battles in a duel" % t.id)
			var issues: Array[String] = []
			t.battle.validate(issues)
			assert_eq(issues, [] as Array[String], "%s's team is duel-eligible" % t.id)
			assert_between(t.battle.enemy_level, BADLANDS.x, BADLANDS.y, "%s fights in the badlands band" % t.id)
			# Their sight crosses the corridor up the middle: the way through is theirs.
			var crosses: bool = false
			var f: Vector2i = OverworldEntity.facing_vector(t.facing)
			for k in range(1, t.sight_range + 1):
				if absi(t.cell.x + f.x * k - 7) == 0:
					crosses = true
			assert_true(crosses, "%s watches the way through" % t.id)
	assert_eq(guards, 5, "many enemies, one after another (#96)")


func test_the_last_fight_is_tactical_with_the_general_beside_you() -> void:
	var depths := _area("badlands_hideout_depths")
	var spec := _battle_in(depths.entity("general").on_interact, false)
	assert_not_null(spec, "the last fight")
	assert_eq(spec.kind, BattleSpec.Kind.TACTICAL, "a TACTICAL battle (#96)")
	assert_eq(spec.hero_deploy, BattleSpec.HeroDeploy.REQUIRED, "the hero fights in it")
	assert_eq(Vector2i(spec.scale_min, spec.scale_max), BADLANDS, "scaled inside the badlands band")
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.RETRY, "Try Again on a loss")
	assert_true(spec.protect.is_empty(), "no base to protect")
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues, [] as Array[String], "it validates")
	var m := load(spec.map_path) as MapResource
	var ally: bool = false
	for sp in m.unit_spawns:
		if int(sp.get("player_id", -1)) == 0 and String(sp.get("spawn_kind", "")) == MapResource.SPAWN_KIND_REINFORCEMENT \
				and String(sp.get("character_id", "")) == "varden":
			ally = true
	assert_true(ally, "General Varden joins as a guest on the hero's side (#57)")
	# The chamber's trigger: the General arrives, then the offer.
	var s := _past(["badlands.hideout_open"])
	var session := FakeSession.new()
	session.state = s
	var zone := depths.entity("commander_chamber") as TriggerZone
	assert_true(zone.is_present(s), "the trigger waits in front of the commander")
	await _run(zone.step_script("badlands_hideout_depths"), s, SeqHost.new(), "badlands_hideout_depths", session)
	assert_true(s.has_flag("badlands.varden_arrived"), "the General arrives")
	assert_eq(session.requests.size(), 1, "and the fight is on")
	assert_true(s.has_flag("badlands.hideout_cleared"), "won")
	assert_false(depths.entity("commander").is_present(s), "the commander is gone")


func test_the_general_is_never_in_two_places() -> void:
	var hideout := _area("badlands_hideout_depths").entity("general")
	var barracks: OverworldEntity = null
	for e in _area("crownhaven").entity_list():
		if String(e.id) == "general":
			barracks = e
	assert_not_null(barracks, "the barracks' General")
	for flags in [[], ["badlands.varden_arrived"], ["badlands.varden_arrived", "badlands.hideout_cleared"]]:
		var s := _past(flags)
		assert_false(hideout.is_present(s) and barracks.is_present(s), "one General at a time (%s)" % str(flags))
	assert_true(hideout.is_present(_past(["badlands.varden_arrived"])), "in the hideout while it matters")
