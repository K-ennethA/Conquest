extends SceneTree

## Generates the STORY MODE M1 slice content (docs/design/OVERWORLD.md §5 task 8):
##
##   game/overworld/content/areas/oakvale/terrain.tres + area.tres   -- the village
##   game/overworld/content/areas/mossway/terrain.tres + area.tres   -- Route 1
##   game/overworld/content/battles/ow_mossway_clearing.tres         -- Bram's tactical board
##   game/overworld/content/hero.tres                                -- the avatar (placeholder)
##   game/overworld/content/story_ruleset.tres                       -- story tuning
##
## Run with:
##   godot --headless --path . -s res://game/overworld/build/build_story_content.gd
##
## Terrain is ordinary MapResource data (the Map Maker can open and repaint it); everything
## story -- NPCs, signs, the chest, warps, the Wayshrine, grass, dialogue -- is the
## OverworldAreaResource beside it. Nothing here lives under game/maps/resources/, so no picker
## (Skirmish, Siege, network, Map Gallery) ever lists it; every map is also status Inactive.
##
## Builder scripts are the M1 authoring path (the practice of game/maps/build_*.gd); the Map
## Maker "Story layer" is M3.

const CONTENT := "res://game/overworld/content/"
const BATTLE_MAP_PATH := CONTENT + "battles/ow_mossway_clearing.tres"

const TILE_TYPES := {
	"grass_plains": "NORMAL",
	"forest_dirt": "NORMAL",
	"flagstones": "NORMAL",
	"wooden_planks": "NORMAL",
	"tall_grass": "DIFFICULT_TERRAIN",
	"tree": "DIFFICULT_TERRAIN",
	"sacred_meadow": "SACRED_GROUND",
	"fountain": "SACRED_GROUND",
	"sacred_ground": "SACRED_GROUND",
	"stone_wall": "WALL",
	"deep_water": "WATER",
}

var _ok: bool = true


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + "areas/oakvale"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + "areas/mossway"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + "battles"))
	_build_hero()
	_build_ruleset()
	_build_battle_map()
	_build_oakvale()
	_build_mossway()
	print("[build_story_content] %s" % ("done" if _ok else "FAILED"))
	quit(0 if _ok else 1)


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("[build_story_content] could not save %s (%d)" % [path, err])
		_ok = false
	else:
		print("[build_story_content] saved %s" % path)


# =====================================================================================
#  Hero + ruleset
# =====================================================================================

func _build_hero() -> void:
	var hero := HeroResource.new()
	hero.display_name = "Warden"
	# PLACEHOLDER (DECISIONS.md owner decision 4): Vineweave's model -- the one bipedal,
	# humanoid silhouette in the roster -- stands in for the human hero until the real Blender
	# model exists. Swapping it is this block (model + yaw + scale): data, not code.
	hero.model_scene = load("res://game/characters/models/forest/vineweave.glb")
	hero.model_yaw_deg = 0.0
	hero.model_scale = 1.3
	hero.speaker_id = &"hero"
	_save(hero, CONTENT + "hero.tres")


func _build_ruleset() -> void:
	var rs := StoryRuleset.new()
	rs.start_area = &"oakvale"
	rs.start_entry = &"start"
	var party: Array[StringName] = [&"vineweave", &"blightcap"]
	rs.starting_party = party
	rs.starting_gold = 100
	_save(rs, CONTENT + "story_ruleset.tres")


# =====================================================================================
#  Map helpers
# =====================================================================================

func _new_map(map_name: String, w: int, h: int, desc: String) -> MapResource:
	var m := MapResource.new()
	m.map_name = map_name
	m.description = desc
	m.author = "System"
	m.version = "1.0"
	# NEVER in a picker: story terrain and story battle boards are Inactive drafts, and they
	# live outside game/maps/resources/ besides.
	m.status = "Inactive"
	m.width = w
	m.height = h
	m.max_players = 2
	m.recommended_players = 2
	m.difficulty = "Normal"
	m.map_type = "Story"
	m.environment_preset = "Forest"
	m.lighting_preset = "Day"
	m.background_color = Color(0.12, 0.16, 0.12, 1.0)
	var tags: Array[String] = ["story"]
	m.tags = tags
	m.creation_date = "2026-09-27T00:00:00"
	m.last_modified = "2026-09-27T00:00:00"
	return m


func _paint(m: MapResource, painter: Callable) -> void:
	m.tile_layout.clear()
	for y in range(m.height):
		for x in range(m.width):
			var id: String = String(painter.call(x, y))
			m.set_tile_at_position(Vector2i(x, y), String(TILE_TYPES.get(id, "NORMAL")), "", id)


## MapResource.validate_map wants two players with spawn entries. Story TERRAIN has no units,
## so it carries two UNASSIGNED Start slots (no character) -- MapLoader skips a slot with no
## unit reference, so they never spawn anything.
func _add_validator_anchors(m: MapResource, a: Vector2i, b: Vector2i) -> void:
	m.unit_spawns.clear()
	m.set_spawn_point_at_position(a, 0, MapResource.SPAWN_KIND_START, {})
	m.set_spawn_point_at_position(b, 1, MapResource.SPAWN_KIND_START, {})


# =====================================================================================
#  Dialogue helpers
# =====================================================================================

func _beat(speaker: StringName, speaker_name: String, text: String, side: StringName = StoryBeat.SIDE_RIGHT) -> StoryBeat:
	var b := StoryBeat.new()
	b.speaker_id = speaker
	b.speaker_name = speaker_name
	b.text = text
	b.side = side
	b.clear_portraits = false
	return b


func _narr(text: String, title: String = "") -> StoryBeat:
	var b := _beat(StoryBeat.NARRATOR, title, text, StoryBeat.SIDE_LEFT)
	b.clear_portraits = true
	return b


func _scene(id: String, beats: Array) -> StoryScene:
	var s := StoryScene.new()
	s.scene_id = StringName(id)
	var typed: Array[Resource] = []
	for b in beats:
		typed.append(b)
	s.beats = typed
	return s


func _say(beats: Array) -> SayCommand:
	var c := SayCommand.new()
	c.beats = StoryCommand.list(beats)
	return c


func _npc(id: String, cell: Vector2i, facing: String, speaker_name: String, tint: Color, dialogue: StoryScene) -> NpcEntity:
	var n := NpcEntity.new()
	n.id = StringName(id)
	n.cell = Vector3i(cell.x, cell.y, 0)
	n.facing = facing
	n.display_name = speaker_name
	n.speaker_name = speaker_name
	n.speaker_id = StringName("npc_" + id)
	n.tint = tint
	n.dialogue = dialogue
	return n


func _sign(id: String, cell: Vector2i, title: String, text: String) -> SignEntity:
	var s := SignEntity.new()
	s.id = StringName(id)
	s.cell = Vector3i(cell.x, cell.y, 0)
	s.display_name = title
	s.text = text
	s.tint = Color(0.52, 0.36, 0.2)
	return s


func _entities(list: Array) -> Array[Resource]:
	var out: Array[Resource] = []
	for e in list:
		out.append(e)
	return out


# =====================================================================================
#  Bram's battle board
# =====================================================================================

func _build_battle_map() -> void:
	var m := _new_map("Mossway Clearing", 10, 8,
		"A ferny clearing off the Mossway where Bram the Warden-apprentice tests travellers.")
	var trees := [Vector2i(0, 0), Vector2i(9, 0), Vector2i(0, 7), Vector2i(9, 7), Vector2i(4, 0), Vector2i(5, 7)]
	var grass := [Vector2i(4, 3), Vector2i(4, 4), Vector2i(5, 3), Vector2i(3, 5), Vector2i(6, 2)]
	_paint(m, func(x: int, y: int) -> String:
		var c := Vector2i(x, y)
		if c in trees:
			return "tree"
		if c in grass:
			return "tall_grass"
		if y == 4 or (x == 5 and y >= 4):
			return "forest_dirt"
		return "grass_plains")
	m.unit_spawns.clear()
	# Squad chairs: Start slots filled from the fielded party (a placeholder id is required --
	# MapLoader skips a Start slot that names no unit at all).
	for c in [Vector2i(1, 2), Vector2i(1, 4), Vector2i(1, 6)]:
		m.set_character_spawn_at_position(c, 0, "vineweave")
	m.set_character_spawn_at_position(Vector2i(8, 4), 1, "tree_grunt")
	m.set_character_spawn_at_position(Vector2i(7, 2), 1, "petalfang")
	m.set_character_spawn_at_position(Vector2i(7, 6), 1, "petalfang")
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, BATTLE_MAP_PATH)


# =====================================================================================
#  Oakvale
# =====================================================================================

const OAK_W := 22
const OAK_H := 18
## The town wall (a tree line) sits on column 19; the gate is the one gap in it.
const OAK_GATE := Vector2i(19, 9)
const OAK_FOUNTAIN := Vector2i(10, 9)
const OAK_GUARD_ASIDE := Vector2i(18, 10)


func _oak_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	# Outer border: forest.
	if y <= 1 or y >= OAK_H - 1 or x == 0:
		return "tree"
	# East: the town wall is a tree line with one gate; the road runs on to the map edge.
	if x == 19:
		return "flagstones" if c == OAK_GATE else "tree"
	if x >= 20:
		if y == OAK_GATE.y:
			return "forest_dirt"
		return "tree" if (x + y) % 3 != 0 or y < 4 or y > 14 else "grass_plains"
	# Houses: stone blocks (placeholder buildings -- real building props are M2).
	for r in _oak_houses():
		if (r as Rect2i).has_point(c):
			return "stone_wall"
	# The Wayshrine stands in the town fountain: a sacred-ground basin (the plain fountain tile
	# has no authored geometry and reads as a flat square).
	if c == OAK_FOUNTAIN:
		return "sacred_ground"
	# The plaza around the Wayshrine.
	if x >= 7 and x <= 13 and y >= 6 and y <= 12:
		return "flagstones"
	# The high road from the plaza to the gate.
	if y == OAK_GATE.y and x >= 13 and x <= 19:
		return "flagstones"
	# Lanes.
	if x == 10 and y >= 3 and y <= 16:
		return "forest_dirt"
	if y == 12 and x >= 2 and x <= 7:
		return "forest_dirt"
	# The mill yard.
	if x >= 2 and x <= 6 and y >= 13 and y <= 15:
		return "wooden_planks"
	# A meadow corner and a few garden trees.
	if x >= 14 and x <= 17 and y >= 12 and y <= 15:
		return "sacred_meadow"
	if c in [Vector2i(16, 6), Vector2i(4, 8), Vector2i(15, 16), Vector2i(8, 15), Vector2i(17, 3)]:
		return "tree"
	return "grass_plains"


func _oak_houses() -> Array:
	return [
		Rect2i(8, 2, 5, 2),    # the Elder's hall, north of the plaza
		Rect2i(2, 3, 3, 3),    # Mira's cottage
		Rect2i(13, 3, 3, 2),   # the smithy
		Rect2i(2, 13, 2, 2),   # the mill
	]


func _build_oakvale() -> void:
	var t := _new_map("Oakvale", OAK_W, OAK_H,
		"Oakvale, a village of flagstones and timber at the edge of the Forgotten Forest. Story-mode terrain.")
	_paint(t, _oak_terrain)
	_add_validator_anchors(t, Vector2i(10, 11), Vector2i(20, 9))
	_save(t, CONTENT + "areas/oakvale/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"oakvale"
	a.display_name = "Oakvale"
	a.kind = OverworldAreaResource.Kind.TOWN
	a.world_map_pos = Vector2(0.18, 0.55)
	a.terrain = load(CONTENT + "areas/oakvale/terrain.tres")
	a.entry_points = {
		"start": {"cell": [10, 11, 0], "facing": "north"},
		"wayshrine": {"cell": [10, 10, 0], "facing": "north"},
		"east_gate": {"cell": [20, 9, 0], "facing": "west"},
	}

	var ents: Array = []
	ents.append(_sign("town_sign", Vector2i(17, 8), "Oakvale",
		"OAKVALE -- where the Mossway begins.\nTravellers, mind the grass."))
	ents.append(_sign("cottage_door", Vector2i(3, 6), "Mira's Cottage",
		"The door is barred. A note is pinned to it: \"Gone to the mill.\""))
	ents.append(_sign("smithy_door", Vector2i(14, 5), "The Smithy",
		"The forge is cold. Chalked on the door: \"Closed until the road is safe.\""))

	ents.append(_npc("maren", Vector2i(6, 9), "east", "Maren", Color(0.62, 0.36, 0.3), _scene("oak_maren", [
		_beat(&"self", "", "The Elder has been pacing by the Wayshrine since dawn. Something about the road east."),
		_beat(&"self", "", "If you're hurt, touch the Wayshrine. It remembers everyone who drinks from it."),
	])))
	var tobin := _npc("tobin", Vector2i(14, 11), "west", "Tobin", Color(0.36, 0.46, 0.62), null)
	tobin.on_interact = StoryCommand.list([IfCommand.make("flag(\"quest.blight_road\") >= 1", [
		_say([_beat(&"self", "", "Bram's out on the Mossway. Thinks he's a Warden already -- he'll want to test you.")]),
	], [
		_say([_beat(&"self", "", "My brother went down the Mossway for moss-caps. Came back white as a ghost -- said the grass itself snapped at him.")]),
	])])
	ents.append(tobin)

	ents.append(_elder())
	ents.append(_guard())

	# Roofs over the placeholder stone blocks (scenery only).
	var roof_tints := [Color(0.5, 0.26, 0.18), Color(0.36, 0.42, 0.3), Color(0.44, 0.3, 0.22), Color(0.55, 0.45, 0.25)]
	var hi := 0
	for r in _oak_houses():
		var rect: Rect2i = r
		var roof := PropEntity.new()
		roof.id = StringName("house_%d" % hi)
		roof.cell = Vector3i(rect.position.x, rect.position.y, 0)
		roof.footprint = rect.size
		roof.tint = roof_tints[hi % roof_tints.size()]
		ents.append(roof)
		hi += 1

	var chest := ChestEntity.new()
	chest.id = &"mill_chest"
	chest.cell = Vector3i(5, 14, 0)
	chest.facing = "south"
	chest.display_name = "Chest"
	chest.tint = Color(0.5, 0.33, 0.18)
	var loot: Array[StringName] = [&"sagebloom_poultice"]
	chest.loot_items = loot
	chest.loot_gold = 30
	ents.append(chest)

	var shrine := WayshrineEntity.new()
	shrine.id = &"wayshrine"
	shrine.cell = Vector3i(OAK_FOUNTAIN.x, OAK_FOUNTAIN.y, 0)
	shrine.display_name = "Oakvale Wayshrine"
	shrine.respawn_entry = &"wayshrine"
	shrine.tint = Color(0.55, 0.92, 0.62)
	ents.append(shrine)

	var gate := WarpEntity.new()
	gate.id = &"east_exit"
	gate.area_rect = Rect2i(21, 9, 1, 1)
	gate.target_area = &"mossway"
	gate.target_entry = &"west"
	gate.blocking = false
	ents.append(gate)

	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/oakvale/area.tres")


func _elder() -> NpcEntity:
	var elder := _npc("elder", Vector2i(10, 5), "south", "Elder Wynn", Color(0.3, 0.48, 0.34), null)
	var ask := ChoiceCommand.new()
	ask.prompt = _beat(&"self", "", "Will you walk the Mossway for us, {hero}?")
	var yes := ChoiceOption.make("I will walk it.", [
		SetFlagCommand.make("quest.blight_road", 1),
		_say([
			_beat(&"self", "", "Then the forest has not forgotten us after all. Take this -- it kept my grandmother's roots steady."),
		]),
		_give(&"heartwood_charm"),
		_move("guard", OAK_GUARD_ASIDE, true),
		ToastCommand.make("Quest: The Blighted Road", "quest"),
		_say([_beat(&"self", "", "Hale will open the east gate. Mind Bram on the road -- the boy means well.")]),
	])
	var no := ChoiceOption.make("Not yet.", [
		_say([_beat(&"self", "", "Come back when your roots are steady. The Mossway will wait -- the rot will not.")]),
	], true)
	ask.options = StoryCommand.list([yes, no])
	elder.on_interact = StoryCommand.list([IfCommand.make("flag(\"quest.blight_road\") >= 1", [
		_say([_beat(&"self", "", "The Mossway waits east of the gate. Follow it to the Blighted Clearing, and come home whole.")]),
	], [
		_say([
			_beat(&"self", "", "Ah -- a Warden's coat. I had hoped one would come."),
			_beat(&"self", "", "The Mossway is sick. The blight walks it at night, and the grass has started to bite."),
		]),
		ask,
	])])
	return elder


func _guard() -> NpcEntity:
	var guard := _npc("guard", OAK_GATE, "west", "Gate Warden Hale", Color(0.52, 0.34, 0.24), null)
	guard.on_interact = StoryCommand.list([IfCommand.make("flag(\"quest.blight_road\") >= 1", [
		_say([_beat(&"self", "", "The Elder's given her word. Go on, then -- and mind the grass.")]),
	], [
		_say([_beat(&"self", "", "The road east is closed by the Elder's word. Speak with Elder Wynn at the hall first.")]),
	])])
	return guard


func _give(item: StringName) -> GiveItemCommand:
	var g := GiveItemCommand.new()
	g.item_id = item
	return g


func _move(actor: String, to: Vector2i, persist: bool) -> MoveActorCommand:
	var m := MoveActorCommand.new()
	m.actor = actor
	m.to = Vector3i(to.x, to.y, 0)
	m.persist = persist
	return m


# =====================================================================================
#  Route 1 -- the Mossway
# =====================================================================================

const MOSS_W := 34
const MOSS_H := 12
## Bram watches the path from the grass bank north of it (sight runs south across the road).
const BRAM_CELL := Vector2i(19, 4)


func _moss_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if y <= 1 or y >= MOSS_H - 1 or x >= MOSS_W - 1:
		return "tree"
	if x == 0:
		return "forest_dirt" if y == 6 else "tree"
	# The winding path.
	var path_y: int = 6 if x < 10 else (5 if x < 18 else 6)
	if y == path_y or (x == 10 and (y == 5 or y == 6)) or (x == 18 and (y == 5 or y == 6)):
		return "forest_dirt"
	# Tall grass (the encounter zones are the grass itself).
	if (x >= 4 and x <= 8 and y >= 2 and y <= 4) \
			or (x >= 12 and x <= 16 and y >= 7 and y <= 9) \
			or (x >= 23 and x <= 27 and y >= 7 and y <= 9) \
			or (x >= 22 and x <= 25 and y >= 2 and y <= 3):
		return "tall_grass"
	# A brook with a plank crossing.
	if x == 21 and y != 6 and y >= 2 and y <= 9:
		return "deep_water"
	if x == 21 and y == 6:
		return "wooden_planks"
	# The recruit's clearing.
	if x >= 28 and x <= 31 and y >= 2 and y <= 4:
		return "sacred_meadow"
	if c in [Vector2i(3, 3), Vector2i(11, 3), Vector2i(14, 2), Vector2i(19, 9), Vector2i(29, 8),
			Vector2i(9, 9), Vector2i(26, 5), Vector2i(31, 7), Vector2i(2, 8), Vector2i(17, 3)]:
		return "tree"
	return "grass_plains"


func _build_mossway() -> void:
	var t := _new_map("The Mossway", MOSS_W, MOSS_H,
		"Route 1: a mossy forest road east of Oakvale, grown over with biting grass. Story-mode terrain.")
	t.lighting_preset = "Day"
	_paint(t, _moss_terrain)
	_add_validator_anchors(t, Vector2i(1, 6), Vector2i(30, 6))
	_save(t, CONTENT + "areas/mossway/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"mossway"
	a.display_name = "Route 1 -- The Mossway"
	a.kind = OverworldAreaResource.Kind.ROUTE
	a.world_map_pos = Vector2(0.34, 0.5)
	a.terrain = load(CONTENT + "areas/mossway/terrain.tres")
	a.entry_points = {
		"west": {"cell": [1, 6, 0], "facing": "east"},
	}

	var ents: Array = []
	ents.append(_sign("route_sign", Vector2i(3, 5), "Route 1",
		"ROUTE 1 -- THE MOSSWAY\nWest: Oakvale.  East: the Blighted Clearing."))
	ents.append(_sign("clearing_sign", Vector2i(31, 5), "The Blighted Clearing",
		"Past this stone the road is choked with rot. (The Blighted Clearing opens in the next part of the journey.)"))

	var bram := TrainerEntity.new()
	bram.id = &"bram"
	bram.cell = Vector3i(BRAM_CELL.x, BRAM_CELL.y, 0)
	bram.facing = "south"
	bram.display_name = "Bram"
	bram.speaker_name = "Bram"
	bram.speaker_id = &"npc_bram"
	bram.tint = Color(0.3, 0.52, 0.3)
	bram.sight_range = 4
	bram.pre_scene = _scene("moss_bram_pre", [
		_beat(&"self", "", "Hold it! Elder Wynn sent you down the Mossway? Then show me you can keep a squad alive out here."),
	])
	bram.defeated_scene = _scene("moss_bram_after", [
		_beat(&"self", "", "Hah... you'll do. The Clearing's past the old stones. Watch the rot -- it watches back."),
	])
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.map_path = BATTLE_MAP_PATH
	spec.squad_size = 3
	spec.ai_difficulty = 1
	spec.opponent_name = "Bram"
	spec.opponent_speaker_id = &"npc_bram"
	var team: Array[Dictionary] = [{"character_id": "tree_grunt", "strength": 1.0},
		{"character_id": "petalfang", "strength": 1.0}]
	spec.opponent_team = team
	spec.reward_gold = 120
	spec.defeat_policy = BattleSpec.DefeatPolicy.WHITEOUT
	spec.clash_intro = true
	bram.battle = spec
	ents.append(bram)

	# A STORY RECRUIT: the lone Petalfang. Non-missable -- present until it has joined, whatever
	# happens in the duel (loss, flee, or "Not now" all leave it here).
	var recruit := NpcEntity.new()
	recruit.id = &"lone_petalfang"
	recruit.cell = Vector3i(30, 3, 0)
	recruit.facing = "west"
	recruit.display_name = "Lone Petalfang"
	recruit.visual_character = &"petalfang"
	recruit.visible_if = "not has(\"mossway.petalfang.recruited\")"
	var duel_spec := BattleSpec.new()
	duel_spec.kind = BattleSpec.Kind.DUEL
	duel_spec.encounter_id = "mossway.recruit.petalfang"
	duel_spec.opponent_name = "Lone Petalfang"
	duel_spec.opponent_speaker_id = &"petalfang"
	var foe: Array[Dictionary] = [{"character_id": "petalfang", "strength": 1.0}]
	duel_spec.opponent_team = foe
	duel_spec.can_flee = true
	duel_spec.can_befriend = true
	duel_spec.story_critical = true
	duel_spec.defeat_policy = BattleSpec.DefeatPolicy.CONTINUE
	var duel := StartDuelCommand.new()
	duel.spec = duel_spec
	duel.source = BattleRequest.SOURCE_SCRIPT
	var prompt := BefriendPromptCommand.new()
	prompt.flag_on_join = "mossway.petalfang.recruited"
	recruit.on_interact = StoryCommand.list([
		_say([_narr("A lone Petalfang watches you from the meadow, hackles raised. It will not be approached without a fight.")]),
		duel,
		IfCommand.make("outcome() == \"victory\"", [prompt], [
			_say([_narr("The Petalfang slinks back into the meadow. It is still watching you.")]),
		]),
	])
	ents.append(recruit)

	var back := WarpEntity.new()
	back.id = &"west_exit"
	back.area_rect = Rect2i(0, 6, 1, 1)
	back.target_area = &"oakvale"
	back.target_entry = &"east_gate"
	back.blocking = false
	ents.append(back)

	a.entities = _entities(ents)

	var zone := EncounterZone.new()
	var ids: Array[StringName] = [&"tall_grass"]
	zone.tile_ids = ids
	zone.rate = 0.14
	zone.grace_steps = 3
	var table: Array[Resource] = []
	for pair in [["petalfang", 3.0], ["blightcap", 2.0], ["tree_grunt", 1.0]]:
		var e := EncounterEntry.new()
		e.character_id = StringName(pair[0])
		e.weight = pair[1]
		e.kind = EncounterEntry.Kind.DUEL
		e.can_befriend = true
		table.append(e)
	zone.table = table
	var zones: Array[Resource] = [zone]
	a.encounter_zones = zones
	_save(a, CONTENT + "areas/mossway/area.tres")
