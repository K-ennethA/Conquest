extends SceneTree

## Generates the STORY MODE content -- the story OPENING (docs/design/DECISIONS.md #12-#21) and
## the Mossway route that joins its two towns:
##
##   game/overworld/content/areas/oakvale/         -- the hero's HOME village, before the raid
##   game/overworld/content/areas/oakvale_ruins/   -- the same village after the raid (burned)
##   game/overworld/content/areas/mossway/         -- Route 1, Oakvale <-> Crownhaven
##   game/overworld/content/areas/crownhaven/      -- the walled castle town (the shard ceremony)
##   game/overworld/content/battles/ow_oakvale_ashes.tres    -- the FIRST FIGHT (tactical)
##   game/overworld/content/battles/ow_mossway_clearing.tres -- Bram's board (post-opening)
##   game/overworld/content/hero.tres                        -- the avatar (placeholder model)
##   game/overworld/content/story_ruleset.tres               -- story tuning
##   game/overworld/content/shops/*.tres                     -- the merchants' shops (DECISIONS.md #28)
##
## Run with:
##   godot --headless --path . -s res://game/overworld/build/build_story_content.gd
##
## Terrain is ordinary MapResource data (the Map Maker can open and repaint it); everything
## story -- NPCs, signs, props, warps, the Wayshrines, dialogue, the opening's scripts -- is the
## OverworldAreaResource beside it. Nothing here lives under game/maps/resources/, so no picker
## (Skirmish, Siege, network, Map Gallery) ever lists it; every map is also status Inactive.
##
## THE OPENING, as built here (flags in the F_* constants):
##   1. Oakvale (home): a new journey starts at your door; your mother sends you to Crownhaven
##      to receive your first creature and a bonding shard ............... opening.sent_off
##   2. The Mossway: wild creatures leave a traveller with no partner alone (no encounters,
##      trainers let you pass -- OverworldController); Bram and the Lone Petalfang only appear
##      once the opening is over ............................................ (opening.complete)
##   3. Crownhaven: the Researcher's ceremony -- the STARTER joins, the shard is yours
##      ........................................ opening.starter_received, key.bonding_shard
##   4. The raid: Cindral raiders vault the east wall, seize the Researcher and flee west down
##      the Mossway; the Sergeant runs up; you give chase (a scripted warp) ... opening.attack,
##      opening.researcher_taken, opening.raiders_fled, opening.chase
##   5. Oakvale in ashes (a second area, swapped in by the Mossway's flag-gated west warps):
##      your mother's fate, and the Sergeant's offer to fight ...... opening.ruins_seen
##   6. The FIRST FIGHT: a tactical battle on ow_oakvale_ashes vs the raiders' rear guard, the
##      Sergeant's Geode fighting beside your starter as a guest .... opening.first_fight_won
##   7. Aftermath: the Sergeant's hook into Act 1 ............... opening.complete, act1.find_rowan
##
## NAMES live in ONE place ([constant NAMES]) -- rename a character there and rebuild. Text uses
## {TOKEN} placeholders filled at build time; lower-case {hero} / {lead} / {gold} are filled at
## RUNTIME by the script context (the hero's name comes from HeroResource).

const CONTENT := "res://game/overworld/content/"
const BATTLE_MAP_PATH := CONTENT + "battles/ow_mossway_clearing.tres"
const FIRST_FIGHT_MAP_PATH := CONTENT + "battles/ow_oakvale_ashes.tres"

# =====================================================================================
#  THE ONE PLACE for names, the starter and the placeholders
# =====================================================================================

const NAMES := {
	"HERO": "Wren",                         # default hero name (player naming is planned)
	"MOTHER": "Briony",
	"RESEARCHER": "Linnea",
	"RESEARCHER_TITLE": "Researcher Linnea",
	"ASSISTANT": "Tam",
	"SOLDIER": "Rowan",                     # becomes the recurring general (DECISIONS.md #21)
	"SOLDIER_TITLE": "Sergeant Rowan",
	"RAIDER_CAPTAIN": "Raider Captain",
	"KINGDOM": "Aldermere",
	"NATION": "Cindral",                    # the enemy nation (framed; the Gloam stays secret)
	"STONE": "starstone",                   # what the shards are cut from
	"TOBIN": "Tobin",
	"HESSA": "Hessa",
	"PELL": "Pell",
	"ORWIN": "Guard Orwin",
	"DALLA": "Dalla",
	"FENWICK": "Old Fenwick",
	"BRISA": "Brisa",
	"CORIN": "Corin",
	"LISK": "Private Lisk",
	"KEEP_GUARD": "Royal Guard",
	"KIT": "Kit",
	"BAKER": "Baker Gilly",
	"MAUD": "old Maud",
	"MERCHANT": "Merchant Oda",             # Crownhaven's general-goods stall
	"SHOP_CROWNHAVEN": "Oda's General Goods",
	"PEDLAR": "Pedlar Jory",                # the travelling merchant on the Mossway (after the opening)
	"SHOP_PEDLAR": "Jory's Travelling Cart",
}

## Shop ids (the save keys of their stock -- never rename once shipped; the NAMES above are free).
const SHOP_CROWNHAVEN := "crownhaven_general"
const SHOP_PEDLAR := "mossway_pedlar"

## The STARTER creature the ceremony gives (a CharacterLibrary id) -- change it here and rebuild.
const STARTER_ID := &"tree_grunt"
const STARTER_NICKNAME := ""
## The Sergeant's army-issued creature, fighting as a GUEST in the first fight (a player-0 turn-1
## Reinforcement slot on the battle map: placed at load, never replaced by the squad pick).
const GUEST_ID := "gem_knight"
## PLACEHOLDER raider units (existing Dark roster creatures) until Cindral's own units exist.
const RAIDER_UNITS: Array[String] = ["undead", "undead", "monster"]
## The hero's placeholder overworld model (DECISIONS.md #4): swap the model here.
const HERO_MODEL := "res://game/characters/models/forest/vineweave.glb"

## Tints (the raiders' Cindral colours, the kingdom's blue).
const CINDRAL_RED := Color(0.62, 0.16, 0.12)
const ALDERMERE_BLUE := Color(0.2, 0.28, 0.5)

# --- Story flags ------------------------------------------------------------------
const F_SENT_OFF := "opening.sent_off"
const F_ARRIVED := "opening.arrived_crownhaven"
const F_CEREMONY := "opening.ceremony"
const F_STARTER := "opening.starter_received"
const F_SHARD := "key.bonding_shard"
const F_ATTACK := "opening.attack"
const F_TAKEN := "opening.researcher_taken"
const F_FLED := "opening.raiders_fled"
const F_CHASE := "opening.chase"
const F_ROWAN_ARRIVED := "opening.rowan_arrived"
const F_RUINS_SEEN := "opening.ruins_seen"
const F_FIGHT_WON := "opening.first_fight_won"
const F_COMPLETE := "opening.complete"
const F_ACT1 := "act1.find_rowan"
const F_ACT1_MET := "act1.met_rowan"
const FIRST_FIGHT_ID := "story.opening.first_fight"

const TILE_TYPES := {
	"grass_plains": "NORMAL",
	"forest_dirt": "NORMAL",
	"flagstones": "NORMAL",
	"wooden_planks": "NORMAL",
	"ash_field": "DIFFICULT_TERRAIN",
	"magma_vent": "LAVA",
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
	for d in ["areas/oakvale", "areas/oakvale_ruins", "areas/mossway", "areas/crownhaven", "battles", "shops"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + d))
	_build_hero()
	_build_ruleset()
	_build_shops()
	_build_battle_map()
	_build_first_fight_map()
	_build_oakvale(false)
	_build_oakvale(true)
	_build_mossway()
	_build_crownhaven()
	print("[build_story_content] %s" % ("done" if _ok else "FAILED"))
	quit(0 if _ok else 1)


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("[build_story_content] could not save %s (%d)" % [path, err])
		_ok = false
	else:
		print("[build_story_content] saved %s" % path)


## Fill the build-time {TOKENS} (names, the starter's species).
func _t(text: String) -> String:
	if not text.contains("{"):
		return text
	var out: String = text
	for k in NAMES:
		out = out.replace("{%s}" % k, String(NAMES[k]))
	out = out.replace("{STARTER}", _starter_name())
	return out


## The starter's species name, read straight from its roster .tres TEXT (CharacterLibrary needs
## the autoloads, which a -s builder run does not have).
func _starter_name() -> String:
	var roster: String = "res://game/characters/roster/"
	var dir := DirAccess.open(roster)
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var text: String = FileAccess.get_file_as_string(roster + f)
			if not text.contains("character_id = &\"%s\"" % STARTER_ID):
				continue
			var re := RegEx.create_from_string("display_name = \"([^\"]*)\"")
			var m := re.search(text)
			if m != null:
				return m.get_string(1)
	return String(STARTER_ID).capitalize()


# =====================================================================================
#  Hero + ruleset
# =====================================================================================

func _build_hero() -> void:
	var hero := HeroResource.new()
	hero.display_name = String(NAMES["HERO"])
	# PLACEHOLDER (DECISIONS.md owner decision 4): Vineweave's model -- the one bipedal,
	# humanoid silhouette in the roster -- stands in for the human hero until the real Blender
	# model exists. Swapping it is this block (model + yaw + scale): data, not code. The human
	# hero as a BATTLE unit does not exist yet (planned): the party fights, the hero does not.
	hero.model_scene = load(HERO_MODEL)
	hero.model_yaw_deg = 0.0
	hero.model_scale = 1.3
	hero.speaker_id = &"hero"
	_save(hero, CONTENT + "hero.tres")


func _build_ruleset() -> void:
	var rs := StoryRuleset.new()
	rs.start_area = &"oakvale"
	rs.start_entry = &"start"
	# The hero is a villager with no creature: the starter comes from the Crownhaven ceremony.
	var party: Array[StringName] = []
	rs.starting_party = party
	rs.starting_gold = 100
	# The economy (DECISIONS.md #28): wild wins pay per foe, trainers pay their authored purse,
	# merchants buy back at half price, a bag stack holds 99.
	rs.wild_gold_per_foe = 15
	rs.battle_gold_per_foe = 0
	rs.sell_ratio = 0.5
	rs.bag_stack_cap = 99
	_save(rs, CONTENT + "story_ruleset.tres")


# =====================================================================================
#  Shops (DECISIONS.md #28 + revision: healing, cures, revives and existing equipment only --
#  no bonding shards or evolution items yet; those are later stock lines gated by flags)
# =====================================================================================

func _stock(item_id: String, price: int = 0, limit: int = -1, condition: String = "") -> ShopStockEntry:
	return ShopStockEntry.make(StringName(item_id), price, limit, condition)


func _build_shops() -> void:
	var after_opening: String = "has(\"%s\")" % F_COMPLETE
	var general := ShopResource.new()
	general.id = StringName(SHOP_CROWNHAVEN)
	general.display_name = _t("{SHOP_CROWNHAVEN}")
	general.greeting = _t("\"Tonics, salves, a charm or two -- everything a tester needs on the road. Take your time, love.\"")
	var gs: Array[ShopStockEntry] = [
		_stock("mossleaf_tonic"),
		_stock("heartwood_tonic", 0, 5),
		_stock("bitterroot_salve"),
		_stock("clearwater_draught", 0, 3),
		_stock("dawnpetal_draught", 0, 2),
		_stock("heartwood_charm", 0, 1),
		_stock("ironbark_sigil", 0, 1),
		# The better gear once the opening is over (a story-flag gate).
		_stock("swiftspore_boots", 0, 1, after_opening),
		_stock("sagebloom_poultice", 0, 1, after_opening),
	]
	general.stock = gs
	general.restock = ShopResource.Restock.ON_REST
	general.sell_ratio = -1.0
	_save(general, ShopResource.path_for(SHOP_CROWNHAVEN))

	var pedlar := ShopResource.new()
	pedlar.id = StringName(SHOP_PEDLAR)
	pedlar.display_name = _t("{SHOP_PEDLAR}")
	pedlar.greeting = _t("\"Road prices, friend -- dearer than the city, but the city's a long walk with a limping partner.\"")
	var ps: Array[ShopStockEntry] = [
		_stock("mossleaf_tonic", 45),
		_stock("bitterroot_salve", 35),
		_stock("dawnpetal_draught", 275, 1),
		_stock("windwhisper_pendant", 0, 1),
	]
	pedlar.stock = ps
	pedlar.restock = ShopResource.Restock.EVERY_N_STEPS
	pedlar.restock_steps = 150
	pedlar.sell_ratio = 0.4
	_save(pedlar, ShopResource.path_for(SHOP_PEDLAR))


## A merchant NPC standing at [param cell] selling [param shop_id].
func _merchant(id: String, cell: Vector2i, facing: String, name_key: String, tint: Color, shop_id: String,
		figure: String = "villager") -> ShopEntity:
	var m := ShopEntity.new()
	m.id = StringName(id)
	m.cell = Vector3i(cell.x, cell.y, 0)
	m.facing = facing
	var nm: String = _t(String(NAMES.get(name_key, name_key)))
	m.display_name = nm
	m.speaker_name = nm
	m.speaker_id = StringName("npc_" + id)
	m.tint = tint
	m.figure = figure
	m.shop = load(ShopResource.path_for(shop_id)) as ShopResource
	return m


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
	m.last_modified = "2026-09-28T00:00:00"
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


func _in(rects: Array, c: Vector2i) -> bool:
	for r in rects:
		if (r as Rect2i).has_point(c):
			return true
	return false


## Deterministic 0..1 per cell (scatter, ash patches).
static func _h(x: int, y: int, salt: int = 0) -> float:
	return ProcMesh.hash01(x, y, salt)


# =====================================================================================
#  Dialogue + entity helpers
# =====================================================================================

func _beat(speaker: StringName, speaker_name: String, text: String, side: StringName = StoryBeat.SIDE_RIGHT) -> StoryBeat:
	var b := StoryBeat.new()
	b.speaker_id = speaker
	b.speaker_name = _t(speaker_name)
	b.text = _t(text)
	b.side = side
	b.clear_portraits = false
	return b


## A line spoken by the NPC entity [param npc_id] (its speaker id / name).
func _line(npc_id: String, name_key: String, text: String) -> StoryBeat:
	return _beat(StringName("npc_" + npc_id), String(NAMES.get(name_key, name_key)), text)


## A line spoken by the hero ({hero}; SayCommand resolves the "hero" speaker).
func _me(text: String) -> StoryBeat:
	return _beat(SayCommand.HERO_ID, "", text, StoryBeat.SIDE_LEFT)


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


func _npc(id: String, cell: Vector2i, facing: String, name_key: String, tint: Color,
		figure: String = "", dialogue: StoryScene = null) -> NpcEntity:
	var n := NpcEntity.new()
	n.id = StringName(id)
	n.cell = Vector3i(cell.x, cell.y, 0)
	n.facing = facing
	var nm: String = _t(String(NAMES.get(name_key, name_key)))
	n.display_name = nm
	n.speaker_name = nm
	n.speaker_id = StringName("npc_" + id)
	n.tint = tint
	n.figure = figure
	n.dialogue = dialogue
	return n


func _sign(id: String, cell: Vector2i, title: String, text: String, look: String = "post") -> SignEntity:
	var s := SignEntity.new()
	s.id = StringName(id)
	s.cell = Vector3i(cell.x, cell.y, 0)
	s.display_name = _t(title)
	s.text = _t(text)
	s.look = look
	s.tint = Color(0.52, 0.36, 0.2) if look == "post" else Color(0.55, 0.9, 0.6)
	return s


func _prop(id: String, kind: String, cell: Vector2i, footprint: Vector2i, tint: Color,
		blocking: bool = false, visible_if: String = "") -> PropEntity:
	var p := PropEntity.new()
	p.id = StringName(id)
	p.prop = kind
	p.cell = Vector3i(cell.x, cell.y, 0)
	p.footprint = footprint
	p.tint = tint
	p.blocking = blocking
	p.visible_if = visible_if
	return p


func _warp(id: String, rect: Rect2i, target_area: StringName, target_entry: StringName,
		visible_if: String = "", requires: String = "", locked: StoryScene = null) -> WarpEntity:
	var w := WarpEntity.new()
	w.id = StringName(id)
	w.area_rect = rect
	w.target_area = target_area
	w.target_entry = target_entry
	w.blocking = false
	w.visible_if = visible_if
	w.requires = requires
	w.locked_scene = locked
	return w


func _shrine(cell: Vector2i, name: String) -> WayshrineEntity:
	var shrine := WayshrineEntity.new()
	shrine.id = &"wayshrine"
	shrine.cell = Vector3i(cell.x, cell.y, 0)
	shrine.display_name = name
	shrine.respawn_entry = &"wayshrine"
	shrine.tint = Color(0.55, 0.92, 0.62)
	return shrine


func _entities(list: Array) -> Array[Resource]:
	var out: Array[Resource] = []
	for e in list:
		out.append(e)
	return out


func _join(character_id: StringName, nickname: String, growth: int, flag: String = "") -> JoinPartyCommand:
	var j := JoinPartyCommand.new()
	j.character_id = character_id
	j.nickname = nickname
	j.growth = growth
	j.flag_on_join = flag
	return j


func _move(actor: String, to: Vector2i, persist: bool = false) -> MoveActorCommand:
	var m := MoveActorCommand.new()
	m.actor = actor
	m.to = Vector3i(to.x, to.y, 0)
	m.persist = persist
	return m


func _face(actor: String, facing: String) -> FaceActorCommand:
	var f := FaceActorCommand.new()
	f.actor = actor
	f.facing = facing
	return f


func _emote(actor: String, glyph: String) -> EmoteCommand:
	var e := EmoteCommand.new()
	e.actor = actor
	e.glyph = glyph
	return e


func _wait(seconds: float) -> WaitCommand:
	var w := WaitCommand.new()
	w.seconds = seconds
	return w


func _flag(key: String, value: int = 1) -> SetFlagCommand:
	return SetFlagCommand.make(key, value)


func _toast(text: String, kind: String = "quest") -> ToastCommand:
	return ToastCommand.make(_t(text), kind)


func _respawn(area_id: StringName, entry: StringName) -> SetRespawnCommand:
	var r := SetRespawnCommand.new()
	r.area_id = area_id
	r.entry = entry
	return r


func _warp_cmd(area_id: StringName, entry: StringName) -> WarpCommand:
	var w := WarpCommand.new()
	w.area_id = area_id
	w.entry = entry
	return w


# =====================================================================================
#  Battle boards
# =====================================================================================

## Bram's board (the Mossway trainer -- after the opening).
func _build_battle_map() -> void:
	var m := _new_map("Mossway Clearing", 10, 8,
		"A ferny clearing off the Mossway where Bram tests travellers.")
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


## THE FIRST FIGHT: the village road past the burned mill, where the raiders' rear guard holds.
## West: your squad chairs + the Sergeant's GUEST creature (a player-0 Reinforcement due on
## turn 1 = placed at load and never replaced by the squad pick). East: the raiders' chained
## creatures (PLACEHOLDER Dark roster units -- RAIDER_UNITS).
func _build_first_fight_map() -> void:
	var m := _new_map("Oakvale Mill Road", 12, 8,
		"The road past Oakvale's burned mill, where the raiders' rear guard holds the way to the border.")
	m.lighting_preset = "Dusk"
	var walls := [Vector2i(5, 1), Vector2i(5, 2), Vector2i(6, 6), Vector2i(7, 6), Vector2i(3, 6)]
	var trees := [Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 7), Vector2i(11, 7), Vector2i(1, 0), Vector2i(10, 7)]
	_paint(m, func(x: int, y: int) -> String:
		var c := Vector2i(x, y)
		if c in trees:
			return "tree"
		if c in walls:
			return "stone_wall"
		if y == 4 or (y == 3 and x >= 8):
			return "forest_dirt"
		if x >= 8 and x <= 9 and y >= 1 and y <= 2:
			return "wooden_planks"
		if _h(x, y, 5) < 0.3 or (x >= 4 and x <= 7 and y >= 3 and y <= 5 and _h(x, y, 6) < 0.6):
			return "ash_field"
		return "grass_plains")
	m.unit_spawns.clear()
	for c in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5)]:
		m.set_character_spawn_at_position(c, 0, String(STARTER_ID))
	m.set_spawn_point_at_position(Vector2i(2, 2), 0, MapResource.SPAWN_KIND_REINFORCEMENT,
		{"character_id": GUEST_ID, "spawn_turn": 1, "max_spawns": 1})
	var foes := [Vector2i(9, 2), Vector2i(9, 6), Vector2i(10, 4)]
	for i in range(foes.size()):
		m.set_character_spawn_at_position(foes[i], 1, RAIDER_UNITS[i % RAIDER_UNITS.size()])
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, FIRST_FIGHT_MAP_PATH)


func _first_fight_spec() -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.encounter_id = FIRST_FIGHT_ID
	spec.map_path = FIRST_FIGHT_MAP_PATH
	spec.squad_size = 3
	spec.ai_difficulty = 0
	spec.opponent_name = _t("{NATION} Raiders")
	spec.opponent_speaker_id = &"npc_raider_captain"
	var team: Array[Dictionary] = []
	for cid in RAIDER_UNITS:
		team.append({"character_id": cid, "strength": 1.0})
	spec.opponent_team = team
	var flags: Array[String] = [F_FIGHT_WON]
	spec.reward_flags = flags
	# The story cannot go on without this win: a loss offers Try Again / the Wayshrine, and the
	# Sergeant waits in the ruins to offer the fight again.
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	return spec


# =====================================================================================
#  Oakvale -- the hero's home village (before) and its ruins (after)
# =====================================================================================

const OAK_W := 24
const OAK_H := 18
const OAK_FOUNTAIN := Vector2i(10, 9)
## The village's east edge (a tree line) is broken by the road on this row.
const OAK_ROAD_Y := 9
const OAK_HOME := Rect2i(2, 3, 3, 3)
const OAK_HALL := Rect2i(8, 2, 5, 2)
const OAK_FARM := Rect2i(15, 3, 3, 2)
const OAK_BAKERY := Rect2i(12, 14, 3, 2)
const OAK_BARN := Rect2i(16, 13, 3, 2)
const OAK_MILL := Rect2i(2, 13, 2, 2)
const OAK_FIELD := Rect2i(14, 10, 5, 2)
const OAK_GARDEN := Rect2i(5, 7, 2, 2)
const OAK_POND := Rect2i(6, 3, 2, 2)
## Where a new journey starts: your own doorstep.
const OAK_START := Vector2i(3, 6)


func _oak_buildings() -> Array:
	return [OAK_HOME, OAK_HALL, OAK_FARM, OAK_BAKERY, OAK_BARN, OAK_MILL]


func _oak_terrain(x: int, y: int, ruined: bool) -> String:
	var c := Vector2i(x, y)
	# Outer border: forest.
	if y <= 1 or y >= OAK_H - 1 or x == 0:
		return "tree"
	# East: a tree line with one gap for the road; the road runs on to the map edge.
	if x == 20:
		return "forest_dirt" if y == OAK_ROAD_Y else "tree"
	if x >= 21:
		if y == OAK_ROAD_Y:
			return "forest_dirt"
		return "tree" if (x + y) % 3 != 0 or y < 4 or y > 14 else "grass_plains"
	# Buildings: stone blocks under the house props; after the raid, smouldering embers under
	# the ruins (a vent glows and never lets a walker in). The bakery still stands.
	if _in(_oak_buildings(), c):
		return "magma_vent" if ruined and not OAK_BAKERY.has_point(c) else "stone_wall"
	if OAK_POND.has_point(c):
		return "deep_water"
	# The Wayshrine in the fountain basin (sacred ground reads as a basin; it survives the fire).
	if c == OAK_FOUNTAIN:
		return "sacred_ground"
	# The plaza.
	if x >= 7 and x <= 13 and y >= 6 and y <= 12:
		return "flagstones"
	# The high road from the plaza to the edge.
	if y == OAK_ROAD_Y and x >= 13:
		return "flagstones" if not ruined or _h(x, y, 1) > 0.3 else "ash_field"
	# The fields and the home garden (burned to ash after the raid).
	if OAK_FIELD.has_point(c) or OAK_GARDEN.has_point(c):
		return "ash_field" if ruined else "forest_dirt"
	# Lanes: home -> road, the north-south lane, the mill lane, the bakery lane.
	if (x == 3 and y >= 6 and y <= 9) or (y == OAK_ROAD_Y and x >= 3 and x <= 6) \
			or (x == 10 and y >= 3 and y <= 16) or (y == 12 and x >= 2 and x <= 6) \
			or (y == 16 and x >= 11 and x <= 18):
		return "forest_dirt"
	# The mill yard.
	if x >= 4 and x <= 6 and y >= 13 and y <= 15:
		return "wooden_planks"
	if c in [Vector2i(5, 10), Vector2i(17, 7), Vector2i(19, 4), Vector2i(13, 4), Vector2i(19, 16),
			Vector2i(1, 16), Vector2i(7, 16), Vector2i(19, 11)]:
		return "tree"
	if ruined:
		# Scorched earth and drifts of ash around every burned building, and scorch marks
		# across the green.
		for r in _oak_buildings():
			if (r as Rect2i).grow(1).has_point(c):
				return "ash_field" if _h(x, y, 3) < 0.35 else "forest_dirt"
		if _h(x, y, 2) < 0.14:
			return "forest_dirt"
	return "grass_plains"


func _build_oakvale(ruined: bool) -> void:
	var aid: String = "oakvale_ruins" if ruined else "oakvale"
	var t := _new_map("Oakvale" + (" (Ruins)" if ruined else ""), OAK_W, OAK_H,
		("Oakvale after the Cindral raid: ash, embers and a Wayshrine still glowing in the square."
			if ruined else "Oakvale, the hero's home: a farming village at the edge of the Forgotten Forest.")
		+ " Story-mode terrain.")
	t.lighting_preset = "Night" if ruined else "Day"
	_paint(t, _oak_terrain.bind(ruined))
	_add_validator_anchors(t, Vector2i(10, 11), Vector2i(21, OAK_ROAD_Y))
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)

	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	a.display_name = "Ruined Oakvale" if ruined else "Oakvale"
	a.kind = OverworldAreaResource.Kind.TOWN
	a.world_map_pos = Vector2(0.18, 0.55)
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	var ents: Array = _oak_scenery(ruined)
	ents.append(_shrine(OAK_FOUNTAIN, "Oakvale Wayshrine"))
	if ruined:
		a.entry_points = {
			"east_road": {"cell": [21, OAK_ROAD_Y, 0], "facing": "west"},
			"east_gate": {"cell": [22, OAK_ROAD_Y, 0], "facing": "west"},
			"wayshrine": {"cell": [10, 10, 0], "facing": "north"},
		}
		ents.append_array(_oak_ruins_people())
		ents.append(_warp("east_exit", Rect2i(23, OAK_ROAD_Y, 1, 1), &"mossway", &"west", "",
			"has(\"%s\")" % F_COMPLETE, _scene("oak_ruins_locked", [
				_line("rowan", "SOLDIER", "Not that way -- the rear guard is dug in past the mill. Talk to me when you're ready."),
			])))
		a.on_enter = StoryCommand.list([
			IfCommand.make("has(\"%s\") and not has(\"%s\")" % [F_CHASE, F_RUINS_SEEN], _ruins_arrival(), [
				IfCommand.make("has(\"%s\") and not has(\"%s\")" % [F_FIGHT_WON, F_COMPLETE], _aftermath()),
			]),
		])
	else:
		a.entry_points = {
			"start": {"cell": [OAK_START.x, OAK_START.y, 0], "facing": "east"},
			"wayshrine": {"cell": [10, 10, 0], "facing": "north"},
			"east_gate": {"cell": [22, OAK_ROAD_Y, 0], "facing": "west"},
		}
		ents.append_array(_oak_people())
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
		ents.append(_warp("east_exit", Rect2i(23, OAK_ROAD_Y, 1, 1), &"mossway", &"west", "",
			"has(\"%s\")" % F_SENT_OFF, _scene("oak_locked", [
				_line("briony", "MOTHER", "{hero}! Not without saying goodbye, you don't."),
			])))
		a.on_enter = StoryCommand.list([
			IfCommand.make("not has(\"%s\")" % F_SENT_OFF, _send_off()),
		])
	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/%s/area.tres" % aid)


## Houses / ruins, the windmill, the farm clutter -- shared layout, the raid's damage on top.
func _oak_scenery(ruined: bool) -> Array:
	var out: Array = []
	var roofs := {
		"home": [OAK_HOME, Color(0.44, 0.52, 0.34)],
		"hall": [OAK_HALL, Color(0.5, 0.26, 0.18)],
		"farm": [OAK_FARM, Color(0.55, 0.45, 0.25)],
		"bakery": [OAK_BAKERY, Color(0.6, 0.36, 0.22)],
		"barn": [OAK_BARN, Color(0.58, 0.2, 0.16)],
	}
	for k in roofs:
		var r: Rect2i = roofs[k][0]
		# The bakery stands (scorched) -- everything else burned.
		var kind: String = "ruin" if ruined and k != "bakery" else "house"
		var tint: Color = roofs[k][1]
		if ruined and k == "bakery":
			tint = tint.darkened(0.45)
		out.append(_prop("house_" + k, kind, r.position, r.size, tint))
	out.append(_prop("mill", "ruin" if ruined else "windmill", OAK_MILL.position, OAK_MILL.size, Color(0.5, 0.3, 0.2)))
	if ruined:
		for f in [Vector2i(15, 10), Vector2i(17, 11), Vector2i(8, 15), Vector2i(19, 13), Vector2i(12, 3),
				Vector2i(16, 16), Vector2i(21, OAK_ROAD_Y + 2)]:
			if _oak_terrain(f.x, f.y, true) == "tree":
				continue
			out.append(_prop("fire_%d_%d" % [f.x, f.y], "fire", f, Vector2i.ONE, Color.WHITE))
		for r in [Vector2i(14, 12), Vector2i(8, 14), Vector2i(18, 8), Vector2i(6, 11)]:
			out.append(_prop("rubble_%d_%d" % [r.x, r.y], "rubble", r, Vector2i.ONE, Color.WHITE))
		out.append(_prop("cart", "rubble", Vector2i(19, 12), Vector2i.ONE, Color.WHITE))
	else:
		out.append(_prop("field", "crops", OAK_FIELD.position, OAK_FIELD.size, Color(0.4, 0.6, 0.26)))
		out.append(_prop("garden", "crops", OAK_GARDEN.position, OAK_GARDEN.size, Color(0.3, 0.55, 0.3)))
		out.append(_prop("field_fence", "fence", Vector2i(14, 12), Vector2i(5, 1), Color(0.5, 0.36, 0.22), true))
		out.append(_prop("haystack", "haystack", Vector2i(19, 14), Vector2i.ONE, Color.WHITE, true))
		out.append(_prop("cart", "cart", Vector2i(19, 12), Vector2i.ONE, Color(0.86, 0.72, 0.38), true))
		out.append(_prop("well", "well", Vector2i(8, 13), Vector2i.ONE, Color(0.5, 0.3, 0.2), true))
		out.append(_prop("barrels", "barrels", Vector2i(7, 14), Vector2i.ONE, Color.WHITE, true))
	return out


func _oak_people() -> Array:
	var out: Array = []
	out.append(_sign("town_sign", Vector2i(19, 8), "Oakvale",
		"OAKVALE\nEast: the Mossway, and Crownhaven beyond it.\nTravellers, mind the grass."))
	out.append(_sign("hall_sign", Vector2i(13, 5), "Village Hall",
		"A notice is nailed to the door:\n\"By order of {KINGDOM}'s crown: shards of {STONE} will be granted to chosen testers at Crownhaven. Oakvale's name was drawn.\""))

	var mom := _npc("briony", Vector2i(OAK_START.x + 1, OAK_START.y), "west", "MOTHER", Color(0.62, 0.36, 0.3))
	mom.on_interact = StoryCommand.list([_say([
		_line("briony", "MOTHER", "Crownhaven is east, along the Mossway. Go on -- the Researcher won't wait all day, and neither will I!"),
	])])
	out.append(mom)

	var tobin := _npc("tobin", Vector2i(13, 11), "east", "TOBIN", Color(0.36, 0.46, 0.62))
	tobin.on_interact = StoryCommand.list([_say([
		_line("tobin", "TOBIN", "Off to get your shard, then? Pa says in his day you befriended a creature by sharing your bread with it for a year."),
		_line("tobin", "TOBIN", "Less bread this way, I suppose."),
	])])
	out.append(tobin)

	var hessa := _npc("hessa", Vector2i(11, 15), "east", "HESSA", Color(0.6, 0.5, 0.3), "villager")
	hessa.on_interact = StoryCommand.list([_say([
		_line("hessa", "HESSA", "Soldiers went down the Mossway at dawn, riding for the border. Nobody would say why."),
		_line("hessa", "HESSA", "There's talk of {NATION} again. There's always talk of {NATION}."),
	])])
	out.append(hessa)

	var pell := _npc("pell", Vector2i(8, 7), "south", "PELL", Color(0.4, 0.6, 0.5), "child")
	pell.on_interact = StoryCommand.list([_say([
		_line("pell", "PELL", "Will your creature be big? Will it breathe fire? Can I hold the shard? Just once?"),
	])])
	out.append(pell)
	return out


## The send-off: the first scene of a new journey (Oakvale on_enter, until opening.sent_off).
func _send_off() -> Array:
	return [
		_say([
			_narr("Long ago, a star fell on this world. Its dust sank into the stone and the soil, and ever since, humans and creatures alike have called on the elements.", "Conquest"),
			_narr("Few people ever bond with a creature. It takes years of patient trust -- or chains. But in the royal city, a researcher has cut a shard of {STONE} that makes the bond easy and safe."),
		]),
		_face("player", "toward:briony"),
		_say([
			_line("briony", "MOTHER", "There you are! Today's the day, {hero}. The letter says noon -- you'll be late if you dawdle."),
			_line("briony", "MOTHER", "One of {RESEARCHER_TITLE}'s chosen testers. A shard of your own, and a creature to go with it. Your father would have been so proud."),
			_me("I'll be home before dark, Mother. I promise."),
			_line("briony", "MOTHER", "Follow the Mossway east to Crownhaven. The wild ones in the grass leave a traveller alone -- until you walk with a partner of your own. Then mind yourself."),
			_line("briony", "MOTHER", "Go on, then. And {hero} -- I love you. Bring your new friend home for supper."),
		]),
		_flag(F_SENT_OFF),
		_toast("Quest: The Shard Ceremony"),
	]


func _oak_ruins_people() -> Array:
	var out: Array = []
	var tobin := _npc("tobin", Vector2i(11, 11), "north", "TOBIN", Color(0.3, 0.36, 0.44))
	tobin.on_interact = StoryCommand.list([IfCommand.make("has(\"%s\")" % F_COMPLETE, [
		_say([_line("tobin", "TOBIN", "We'll rebuild. Oakvale always does. Go and find the ones who did this, {hero}.")]),
	], [
		_say([_line("tobin", "TOBIN", "They went past the mill toward the border. The Sergeant's waiting on you.")]),
	])])
	out.append(tobin)
	var hessa := _npc("hessa", Vector2i(4, 9), "west", "HESSA", Color(0.45, 0.38, 0.26), "villager")
	hessa.on_interact = StoryCommand.list([_say([
		_line("hessa", "HESSA", "The little ones are safe in the mill cellar, thanks to her. Every one of them."),
	])])
	out.append(hessa)
	var pell := _npc("pell", Vector2i(6, 10), "north", "PELL", Color(0.3, 0.45, 0.4), "child")
	pell.dialogue = _scene("ruins_pell", [
		_line("pell", "PELL", "...She told us to count to a thousand in the dark and not come out. I only got to four hundred."),
	])
	out.append(pell)
	out.append(_rowan_in_ruins())
	var cairn := _sign("cairn", Vector2i(OAK_GARDEN.position.x + 1, OAK_GARDEN.position.y), "A cairn",
		"Stones piled with care beside a burned house, and wildflowers laid across them.\n\"{MOTHER} of Oakvale, who went back for the others.\"", "stone")
	cairn.visible_if = "has(\"%s\")" % F_COMPLETE
	out.append(cairn)
	return out


func _rowan_in_ruins() -> NpcEntity:
	var rowan := _npc("rowan", Vector2i(13, OAK_ROAD_Y), "west", "SOLDIER", ALDERMERE_BLUE, "officer")
	rowan.visible_if = "has(\"%s\") and not has(\"%s\")" % [F_ROWAN_ARRIVED, F_COMPLETE]
	rowan.on_interact = StoryCommand.list([
		_say([_line("rowan", "SOLDIER", "The rear guard's still holding the mill road. Are you ready?")]),
		_rowan_offer(),
	])
	return rowan


## Arriving in the burned village: the survivors, your mother's fate, the Sergeant's offer.
func _ruins_arrival() -> Array:
	return [
		_say([
			_narr("Smoke hangs low over Oakvale. The raiders came through on their way to the border -- and did not slow down."),
		]),
		_move("player", Vector2i(14, OAK_ROAD_Y)),
		_emote("tobin", "!"),
		_move("tobin", Vector2i(13, OAK_ROAD_Y)),
		_face("player", "toward:tobin"),
		_say([
			_line("tobin", "TOBIN", "{hero}! Thank the stars you weren't here."),
			_line("tobin", "TOBIN", "They came out of the Mossway at a run -- a dozen of them in {NATION} red, dragging a woman in a scholar's coat. Anyone in their way, they just... went through."),
			_me("Where's my mother? Tobin -- where is she?"),
			_line("tobin", "TOBIN", "...Hessa's with her. Come."),
		]),
		_move("tobin", Vector2i(11, 11)),
		_move("player", Vector2i(3, OAK_ROAD_Y - 1)),
		_face("player", "toward:hessa"),
		_face("hessa", "toward:player"),
		_say([
			_line("hessa", "HESSA", "{hero}... I'm so sorry."),
			_line("hessa", "HESSA", "When the fires started, your mother got Pell and the little ones down into the mill cellar. Then she went back for {MAUD}, who can't walk."),
			_line("hessa", "HESSA", "The roof came down. She didn't come out."),
			_narr("For a long moment, there is nothing to say at all."),
			_me("She sent me to Crownhaven this morning. She told me to mind myself."),
		]),
		_flag(F_ROWAN_ARRIVED),
		_move("rowan", Vector2i(4, OAK_ROAD_Y - 1)),
		_face("player", "toward:rowan"),
		_say([
			_line("rowan", "SOLDIER", "{SOLDIER_TITLE}, Crownhaven Guard. We rode in on the raiders' heels. I heard -- I'm sorry. Truly."),
			_line("rowan", "SOLDIER", "Your village wasn't their target. It was only in their way. To them, that's all this was."),
			_line("rowan", "SOLDIER", "Their rear guard has dug in past the mill with chained beasts -- black chains, {STONE} links -- holding the road so the rest can get the Researcher over the border."),
			_line("rowan", "SOLDIER", "I can't give her back to you. Nobody can. But my Geode and I are going in, and I won't pretend you haven't earned the right to stand with us. Will you fight?"),
		]),
		_flag(F_RUINS_SEEN),
		_rowan_offer(),
	]


## The Sergeant's offer (on arrival, and whenever you talk to him until the fight is won).
func _rowan_offer() -> ChoiceCommand:
	var ask := ChoiceCommand.new()
	ask.prompt = _line("rowan", "SOLDIER", "Well, {hero}?")
	var fight := StartBattleCommand.new()
	fight.spec = _first_fight_spec()
	fight.source = BattleRequest.SOURCE_SCRIPT
	var yes := ChoiceOption.make(_t("I'll fight."), [
		_say([_line("rowan", "SOLDIER", "Then keep your {STARTER} close, and stay on my shield side.")]),
		# A loss sends you to this Wayshrine (the fight waits here with the Sergeant).
		_respawn(&"oakvale_ruins", &"wayshrine"),
		fight,
		IfCommand.make("outcome() == \"victory\"", _aftermath()),
	])
	var no := ChoiceOption.make("Not yet.", [
		_say([_line("rowan", "SOLDIER", "Take the moment you need. I'll hold here -- come and find me when you're ready.")]),
	], true)
	ask.options = StoryCommand.list([yes, no])
	return ask


## After the first fight is won: the Sergeant's hook into Act 1.
func _aftermath() -> Array:
	return [
		_say([
			_narr("The last chained beast falls. Beyond the mill, hoofbeats fade toward the border."),
			_line("rowan", "SOLDIER", "That's the rear guard broken. The rest got away with the Researcher -- over the border by nightfall, I'd wager."),
			_line("rowan", "SOLDIER", "You fought like you had something to fight for. Your mother would have been proud of you -- and furious with me for letting you."),
			_line("rowan", "SOLDIER", "The King will call this an act of war. {NATION} will swear it never sent a soul. And something about this whole raid stinks."),
			_line("rowan", "SOLDIER", "Bury your mother, {hero}. Then come and find me at the barracks in Crownhaven. I could use someone with a shard -- and a reason."),
			_narr("{SOLDIER_TITLE} mounts up and rides east. That evening, the village raises a cairn for {MOTHER} beside the house she built."),
		]),
		_flag(F_COMPLETE),
		_flag(F_ACT1),
		_toast("Quest: Answers in Crownhaven"),
		SaveGameCommand.new(),
	]


# =====================================================================================
#  Route 1 -- the Mossway
# =====================================================================================

const MOSS_W := 34
const MOSS_H := 12
## Bram watches the path from the grass bank north of it (sight runs south across the road).
const BRAM_CELL := Vector2i(19, 4)


func _moss_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if y <= 1 or y >= MOSS_H - 1:
		return "tree"
	# Both ends open onto the road: west to Oakvale, east to Crownhaven.
	if x == 0 or x >= MOSS_W - 1:
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
		"Route 1: a mossy forest road between Oakvale and Crownhaven, grown over with biting grass. Story-mode terrain.")
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
		"east": {"cell": [MOSS_W - 2, 6, 0], "facing": "west"},
	}

	var after_opening: String = "has(\"%s\")" % F_COMPLETE
	var ents: Array = []
	ents.append(_sign("route_sign", Vector2i(3, 5), "Route 1",
		"ROUTE 1 -- THE MOSSWAY\nWest: Oakvale.  East: Crownhaven."))
	ents.append(_sign("crownhaven_sign", Vector2i(31, 5), "Crownhaven",
		"EAST: CROWNHAVEN\nRoyal city of {KINGDOM}."))

	# Before you have a partner, the grass rustles -- and lets you pass.
	var hint := TriggerZone.new()
	hint.id = &"grass_hint"
	hint.area_rect = Rect2i(4, 6, 1, 1)
	hint.once = true
	hint.visible_if = "not has(\"%s\")" % F_STARTER
	hint.on_step = StoryCommand.list([_say([
		_narr("Something rustles in the tall grass and goes still. Wild creatures keep their distance from a traveller with no partner of their own."),
	])])
	ents.append(hint)

	var bram := TrainerEntity.new()
	bram.id = &"bram"
	bram.cell = Vector3i(BRAM_CELL.x, BRAM_CELL.y, 0)
	bram.facing = "south"
	bram.display_name = "Bram"
	bram.speaker_name = "Bram"
	bram.speaker_id = &"npc_bram"
	bram.tint = Color(0.3, 0.52, 0.3)
	bram.sight_range = 4
	# The Mossway's trainer only takes the road once the opening is over.
	bram.visible_if = after_opening
	bram.pre_scene = _scene("moss_bram_pre", [
		_beat(&"self", "", "Hold it! You're the one from Oakvale -- the one who stood with the Sergeant. Show me you can keep a squad alive out here."),
	])
	bram.defeated_scene = _scene("moss_bram_after", [
		_beat(&"self", "", "Hah... you'll do. Whatever you're chasing, I hope you catch it."),
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

	# A STORY RECRUIT: the lone Petalfang. Non-missable -- present (after the opening) until it
	# has joined, whatever happens in the duel (loss, flee, or "Not now" all leave it here).
	var recruit := NpcEntity.new()
	recruit.id = &"lone_petalfang"
	recruit.cell = Vector3i(30, 3, 0)
	recruit.facing = "west"
	recruit.display_name = "Lone Petalfang"
	recruit.visual_character = &"petalfang"
	recruit.visible_if = "%s and not has(\"mossway.petalfang.recruited\")" % after_opening
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

	# A TRAVELLING MERCHANT camps by the road once the opening is over (his cart beside him).
	var pedlar := _merchant("pedlar", Vector2i(13, 4), "south", "PEDLAR", Color(0.55, 0.42, 0.25), SHOP_PEDLAR)
	pedlar.visible_if = after_opening
	pedlar.dialogue = _scene("moss_pedlar", [_line("pedlar", "PEDLAR", "Mind the grass, traveller. Need anything for the road?")])
	ents.append(pedlar)
	ents.append(_prop("pedlar_cart", "cart", Vector2i(12, 4), Vector2i.ONE, Color(0.55, 0.42, 0.25), true, after_opening))

	# The west edge leads home -- to Oakvale as it was, or (once the raid began) to its ruins.
	ents.append(_warp("west_exit", Rect2i(0, 6, 1, 1), &"oakvale", &"east_gate",
		"not has(\"%s\")" % F_ATTACK))
	ents.append(_warp("west_exit_ruins", Rect2i(0, 6, 1, 1), &"oakvale_ruins", &"east_gate",
		"has(\"%s\")" % F_ATTACK))
	ents.append(_warp("east_exit", Rect2i(MOSS_W - 1, 6, 1, 1), &"crownhaven", &"west_gate"))

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


# =====================================================================================
#  Crownhaven -- the walled castle town
# =====================================================================================

const CH_W := 30
const CH_H := 26
## The town wall ring (stone_wall on its edge cells) and the west gate in it.
const CH_WALL := Rect2i(3, 3, 25, 21)
const CH_GATE := Vector2i(3, 13)
const CH_KEEP := Rect2i(11, 4, 8, 4)
const CH_BARRACKS := Rect2i(4, 4, 4, 3)
const CH_LAB := Rect2i(22, 4, 4, 3)
const CH_MARKET := Rect2i(10, 11, 11, 7)
const CH_FOUNTAIN := Vector2i(15, 14)
const CH_HOUSES := [Rect2i(5, 15, 3, 2), Rect2i(5, 19, 3, 2), Rect2i(11, 19, 3, 2), Rect2i(17, 19, 3, 2),
	Rect2i(22, 15, 3, 2), Rect2i(22, 19, 4, 2)]
const CH_STALLS := [Rect2i(11, 12, 2, 1), Rect2i(18, 12, 2, 1), Rect2i(11, 16, 2, 1), Rect2i(18, 16, 2, 1)]
## The ceremony stage in front of the workshop.
const CH_RESEARCHER := Vector2i(24, 8)
const CH_PYLON := Vector2i(22, 8)


func _ch_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	var inside: bool = x > CH_WALL.position.x and x < CH_WALL.end.x - 1 \
		and y > CH_WALL.position.y and y < CH_WALL.end.y - 1
	var on_wall: bool = CH_WALL.has_point(c) and not inside
	if on_wall:
		return "flagstones" if c == CH_GATE else "stone_wall"
	if not CH_WALL.has_point(c):
		# Outside the walls: the road in from the Mossway, a moat, the forest edge.
		if y == CH_GATE.y and x < CH_GATE.x:
			return "wooden_planks" if x == 2 else "forest_dirt"
		if x == 2 and y >= 4 and y <= 22:
			return "deep_water"
		if y <= 1 or y >= CH_H - 1 or x == 0 or x == CH_W - 1:
			return "tree"
		if absi(y - CH_GATE.y) <= 2 and x < CH_GATE.x:
			return "grass_plains"
		if _h(x, y, 11) < 0.25:
			return "tree"
		return "grass_plains"
	# Inside the walls.
	if CH_KEEP.has_point(c) or CH_BARRACKS.has_point(c) or CH_LAB.has_point(c) or _in(CH_HOUSES, c):
		return "stone_wall"
	if c == CH_FOUNTAIN:
		return "sacred_ground"
	# Shade trees in the market's south corners.
	if c == Vector2i(CH_MARKET.position.x, CH_MARKET.end.y - 1) or c == Vector2i(CH_MARKET.end.x - 1, CH_MARKET.end.y - 1):
		return "tree"
	# The keep courtyard, the lab courtyard, the market.
	if x >= 9 and x <= 20 and y >= 8 and y <= 9:
		return "flagstones"
	if x >= 21 and x <= 26 and y >= 7 and y <= 9:
		return "flagstones"
	if CH_MARKET.has_point(c):
		return "flagstones"
	# Streets: the main street from the gate, the north street, the east street, the lab lane,
	# the south lane between the house rows.
	if y == CH_GATE.y and x > CH_GATE.x:
		return "flagstones"
	if x >= 14 and x <= 16 and y >= 10 and y <= 10:
		return "flagstones"
	if x == 23 and y >= 10 and y <= 12:
		return "flagstones"
	if y == 18 and x >= 4 and x <= 26:
		return "flagstones"
	if (x == 9 or x == 21) and y >= 14 and y <= 22:
		return "flagstones"
	# The barracks' training yard.
	if x >= 4 and x <= 8 and y >= 7 and y <= 10:
		return "forest_dirt"
	if x == 6 and y >= 11 and y <= 12:
		return "forest_dirt"
	# A little park in the east.
	if x >= 24 and x <= 26 and y >= 10 and y <= 12:
		return "sacred_meadow"
	if c in [Vector2i(26, 11), Vector2i(4, 21), Vector2i(15, 21), Vector2i(26, 22), Vector2i(10, 22),
			Vector2i(20, 21), Vector2i(8, 4), Vector2i(20, 5)]:
		return "tree"
	return "grass_plains"


func _build_crownhaven() -> void:
	var t := _new_map("Crownhaven", CH_W, CH_H,
		"Crownhaven, the walled royal city of Aldermere: the keep, the market, the barracks and the Researcher's workshop. Story-mode terrain.")
	t.lighting_preset = "Day"
	_paint(t, _ch_terrain)
	_add_validator_anchors(t, Vector2i(1, CH_GATE.y), Vector2i(15, 15))
	_save(t, CONTENT + "areas/crownhaven/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"crownhaven"
	a.display_name = "Crownhaven"
	a.kind = OverworldAreaResource.Kind.TOWN
	a.world_map_pos = Vector2(0.52, 0.45)
	a.terrain = load(CONTENT + "areas/crownhaven/terrain.tres")
	a.entry_points = {
		"west_gate": {"cell": [1, CH_GATE.y, 0], "facing": "east"},
		"wayshrine": {"cell": [CH_FOUNTAIN.x, CH_FOUNTAIN.y + 1, 0], "facing": "north"},
	}

	var ents: Array = []
	ents.append_array(_ch_scenery())
	ents.append(_shrine(CH_FOUNTAIN, "Crownhaven Wayshrine"))
	ents.append_array(_ch_people())
	ents.append(_warp("west_exit", Rect2i(0, CH_GATE.y, 1, 1), &"mossway", &"east"))
	a.entities = _entities(ents)
	a.on_enter = StoryCommand.list([
		# Resume the raid if the journey was saved in the middle of it (a closed window).
		IfCommand.make("has(\"%s\") and not has(\"%s\")" % [F_STARTER, F_CHASE], _raid(), [
			IfCommand.make("not has(\"%s\")" % F_ARRIVED, [
				_say([
					_narr("Crownhaven, royal seat of {KINGDOM}. Banners snap on the walls, and the market is loud with every accent in the kingdom."),
					_narr("{RESEARCHER_TITLE}'s workshop stands in the upper town, east of the keep."),
				]),
				_flag(F_ARRIVED),
			]),
		]),
	])
	_save(a, CONTENT + "areas/crownhaven/area.tres")


func _ch_scenery() -> Array:
	var out: Array = []
	out.append(_prop("keep", "keep", CH_KEEP.position, CH_KEEP.size, ALDERMERE_BLUE))
	out.append(_prop("barracks", "house", CH_BARRACKS.position, CH_BARRACKS.size, Color(0.55, 0.2, 0.16)))
	out.append(_prop("workshop", "house", CH_LAB.position, CH_LAB.size, Color(0.3, 0.38, 0.52)))
	var roof_tints := [Color(0.5, 0.26, 0.18), Color(0.36, 0.42, 0.3), Color(0.44, 0.3, 0.22),
		Color(0.55, 0.45, 0.25), Color(0.48, 0.32, 0.36), Color(0.4, 0.36, 0.3)]
	for i in range(CH_HOUSES.size()):
		var r: Rect2i = CH_HOUSES[i]
		out.append(_prop("house_%d" % i, "house", r.position, r.size, roof_tints[i % roof_tints.size()]))
	# The walls' towers and the west gatehouse.
	for c in [Vector2i(3, 3), Vector2i(27, 3), Vector2i(3, 23), Vector2i(27, 23), Vector2i(15, 23),
			Vector2i(27, 13), Vector2i(3, 18), Vector2i(3, 8)]:
		out.append(_prop("tower_%d_%d" % [c.x, c.y], "tower", c, Vector2i.ONE, ALDERMERE_BLUE))
	out.append(_prop("west_gatehouse", "gate", Vector2i(CH_GATE.x, CH_GATE.y - 1), Vector2i(1, 3), ALDERMERE_BLUE))
	# The market's stalls (blocking), banners down the main street, the training yard, the pylon.
	var awnings := [Color(0.7, 0.25, 0.2), Color(0.25, 0.45, 0.3), Color(0.8, 0.6, 0.2), Color(0.35, 0.3, 0.6)]
	for i in range(CH_STALLS.size()):
		var s: Rect2i = CH_STALLS[i]
		out.append(_prop("stall_%d" % i, "stall", s.position, s.size, awnings[i], true))
	for c in [Vector2i(5, 12), Vector2i(8, 14), Vector2i(10, 10), Vector2i(20, 10)]:
		out.append(_prop("banner_%d_%d" % [c.x, c.y], "banner", c, Vector2i.ONE, ALDERMERE_BLUE, true))
	out.append(_prop("dummy_a", "dummy", Vector2i(4, 8), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("dummy_b", "dummy", Vector2i(8, 8), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("barracks_barrels", "barrels", Vector2i(8, 10), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("pylon", "crystal", CH_PYLON, Vector2i.ONE, Color(0.5, 0.92, 1.0), true))
	out.append(_prop("market_barrels", "barrels", Vector2i(20, 15), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("market_cart", "cart", Vector2i(10, 15), Vector2i.ONE, Color(0.6, 0.75, 0.4), true))
	out.append(_prop("well", "well", Vector2i(21, 12), Vector2i.ONE, Color(0.36, 0.3, 0.26), true))
	return out


func _ch_people() -> Array:
	var out: Array = []
	var raided: String = "has(\"%s\")" % F_ATTACK
	out.append(_sign("town_sign", Vector2i(1, CH_GATE.y - 1), "Crownhaven",
		"CROWNHAVEN\nRoyal city of {KINGDOM}. Keep the peace."))
	out.append(_sign("workshop_sign", Vector2i(21, 9), "The Royal Workshop",
		"THE ROYAL WORKSHOP\n{RESEARCHER_TITLE}. Knock loudly -- she will not hear you otherwise."))
	out.append(_sign("barracks_sign", Vector2i(9, 6), "The Barracks",
		"CROWNHAVEN GUARD -- BARRACKS\nRecruits drill at dawn."))
	out.append(_sign("notice_board", Vector2i(10, 11), "Notice Board",
		"By order of the crown: shards of bonding {STONE} are issued to chosen testers only. The sale, theft or copying of shards is forbidden.\nBelow, in smaller hand: \"Lost: one Petalfang. Answers to Biscuit.\""))

	# The gate guards.
	var orwin := _npc("orwin", Vector2i(4, CH_GATE.y - 1), "south", "ORWIN", ALDERMERE_BLUE, "guard")
	orwin.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("orwin", "ORWIN", "They came over the EAST wall, and out through my gate before I'd got my spear up. I'll not forget it.")]),
	], [
		_say([_line("orwin", "ORWIN", "A shard tester, from Oakvale? The Researcher's workshop is in the upper town -- east of the keep. Mind the market crowd.")]),
	])])
	out.append(orwin)
	var gate2 := _npc("gate_guard", Vector2i(4, CH_GATE.y + 1), "north", "KEEP_GUARD", ALDERMERE_BLUE, "guard")
	gate2.display_name = "Gate Guard"
	gate2.speaker_name = "Gate Guard"
	gate2.dialogue = _scene("ch_gate_guard", [_beat(&"self", "Gate Guard", "Crownhaven's gates are open from dawn to dusk. Keep the peace inside them.")])
	out.append(gate2)

	# The keep's guards.
	for spec in [["keep_guard_w", Vector2i(13, 8)], ["keep_guard_e", Vector2i(16, 8)]]:
		var g := _npc(spec[0], spec[1], "south", "KEEP_GUARD", Color(0.45, 0.4, 0.6), "guard")
		g.dialogue = _scene("ch_" + String(spec[0]), [_beat(&"self", "", "The King is in council. No petitions today.")])
		out.append(g)

	# The barracks: the Sergeant and a recruit.
	out.append(_rowan_in_crownhaven())
	var lisk := _npc("lisk", Vector2i(5, 9), "east", "LISK", ALDERMERE_BLUE.lightened(0.15), "guard")
	lisk.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("lisk", "LISK", "The Sergeant says we're on alert till the King decides what this raid means. I think it means war.")]),
	], [
		_say([_line("lisk", "LISK", "The army got a crate of the Researcher's shards last month. Only the officers carry them. The Sergeant's Geode could flatten this dummy with one arm.")]),
	])])
	out.append(lisk)

	# The market.
	var dalla := _npc("dalla", Vector2i(12, 11), "south", "DALLA", Color(0.7, 0.45, 0.3))
	dalla.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("dalla", "DALLA", "Raiders, in the royal city! In broad daylight! What's next -- dragons in the fish stall?")]),
	], [
		_say([_line("dalla", "DALLA", "Everyone wants to talk shards today. Nobody wants to buy turnips. You'd think a bit of glowing rock was worth more than supper.")]),
	])])
	out.append(dalla)
	# THE MERCHANT (DECISIONS.md #28): at the end of the green-awning stall, between it and the well.
	var oda := _merchant("merchant", Vector2i(20, 12), "south", "MERCHANT", Color(0.3, 0.5, 0.36), SHOP_CROWNHAVEN)
	oda.dialogue = _scene("ch_merchant", [_line("merchant", "MERCHANT", "Welcome to the market! Tonics for the road, salves for the stings -- have a look.")])
	out.append(oda)
	var fenwick := _npc("fenwick", Vector2i(17, 14), "west", "FENWICK", Color(0.4, 0.42, 0.48), "elder")
	fenwick.dialogue = _scene("ch_fenwick", [
		_line("fenwick", "FENWICK", "In my father's day, the lords bound their creatures in chains -- {STONE} chains, forged hot. The beasts obeyed. They never loved anyone for it."),
		_line("fenwick", "FENWICK", "Good folk did it the slow way: years of trust, trial and error, bread and patience. Those bonds need no shard at all."),
		_line("fenwick", "FENWICK", "Now the Researcher says almost anyone can do it with a sliver of the same stone. Hm. Stone is stone. It's the hand that holds it."),
	])
	out.append(fenwick)
	var brisa := _npc("brisa", Vector2i(13, 15), "east", "BRISA", Color(0.45, 0.62, 0.4), "trainer")
	brisa.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("brisa", "BRISA", "If they took the Researcher for her shards... then everyone who carries one is a target now. Keep yours hidden, {hero}.")]),
	], [
		_say([_line("brisa", "BRISA", "I was in the first batch of testers! Biscuit here trusted me the moment the shard warmed. You'll see -- it feels like a second heartbeat.")]),
	])])
	out.append(brisa)
	var biscuit := NpcEntity.new()
	biscuit.id = &"biscuit"
	biscuit.cell = Vector3i(12, 15, 0)
	biscuit.facing = "east"
	biscuit.display_name = "Biscuit"
	biscuit.visual_character = &"petalfang"
	biscuit.dialogue = _scene("ch_biscuit", [_narr("The Petalfang sniffs your hand and wags its whole back half.")])
	out.append(biscuit)
	var corin := _npc("corin", Vector2i(19, 13), "west", "CORIN", Color(0.55, 0.5, 0.4))
	corin.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("corin", "CORIN", "{NATION} raiders, they're saying. Funny -- {NATION} has no shards of its own. So why come all this way for the woman who makes them?")]),
	], [
		_say([_line("corin", "CORIN", "A select few testers, and a crate for the army. Everyone else keeps waiting. That's how it always goes, isn't it?")]),
	])])
	out.append(corin)

	var kit := _npc("kit", Vector2i(16, 16), "north", "KIT", Color(0.7, 0.55, 0.3), "child")
	kit.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("kit", "KIT", "Mum says I'm not allowed past the fountain till the soldiers catch them.")]),
	], [
		_say([_line("kit", "KIT", "I saw the Sergeant's Geode this morning! It was THIS big. Bigger! When I'm a tester I'm getting two.")]),
	])])
	out.append(kit)
	var baker := _npc("baker", Vector2i(14, 12), "south", "BAKER", Color(0.75, 0.62, 0.45))
	baker.dialogue = _scene("ch_baker", [
		_line("baker", "BAKER", "Starstone buns! Get your starstone buns! ...No, there's no starstone in them. There's currants. Glowing currants would be a health hazard."),
	])
	out.append(baker)

	# The workshop: the Researcher, her assistant, and the starter (only during the ceremony).
	out.append(_researcher())
	var tam := _npc("tam", Vector2i(26, 8), "west", "ASSISTANT", Color(0.5, 0.42, 0.6), "scholar")
	tam.on_interact = StoryCommand.list([IfCommand.make("has(\"%s\")" % F_TAKEN, [
		_say([_line("tam", "ASSISTANT", "They knew exactly where she'd be, and exactly when. They didn't touch a single note -- they only wanted HER.")]),
	], [
		_say([_line("tam", "ASSISTANT", "Don't touch the pylon, please. The last tester who touched the pylon could hear colours for a week.")]),
	])])
	out.append(tam)
	var starter := NpcEntity.new()
	starter.id = &"starter"
	starter.cell = Vector3i(CH_RESEARCHER.x + 1, CH_RESEARCHER.y, 0)
	starter.facing = "south"
	starter.display_name = _starter_name()
	starter.visual_character = STARTER_ID
	starter.visible_if = "has(\"%s\") and not has(\"%s\")" % [F_CEREMONY, F_STARTER]
	out.append(starter)

	# The raiders (only during the raid). PLACEHOLDER figures in Cindral red.
	var raid_vis: String = "has(\"%s\") and not has(\"%s\")" % [F_ATTACK, F_FLED]
	for spec in [["raider_captain", Vector2i(26, 6)], ["raider_a", Vector2i(26, 5)], ["raider_b", Vector2i(26, 4)]]:
		var r := _npc(spec[0], spec[1], "west", "RAIDER_CAPTAIN" if spec[0] == "raider_captain" else "Raider",
			CINDRAL_RED, "raider")
		r.visible_if = raid_vis
		out.append(r)
	return out


func _researcher() -> NpcEntity:
	var r := _npc("linnea", CH_RESEARCHER, "south", "RESEARCHER_TITLE", Color(0.28, 0.42, 0.55), "scholar")
	r.visible_if = "not has(\"%s\")" % F_TAKEN
	r.on_interact = StoryCommand.list([IfCommand.make("not has(\"%s\")" % F_STARTER, _ceremony())])
	return r


## THE SHARD CEREMONY: the starter joins, the shard is yours -- and then the raid.
func _ceremony() -> Array:
	var out: Array = [
		_say([
			_line("linnea", "RESEARCHER_TITLE", "Ah -- the tester from Oakvale! {hero}, isn't it? Come in, come in. Mind the cables."),
			_line("linnea", "RESEARCHER_TITLE", "You know the old ways. Chains of {STONE}, forged hot, for those who wanted obedience. Years of patience for those who wanted a friend."),
			_line("linnea", "RESEARCHER_TITLE", "This shard is cut from the same {STONE} -- but tuned to listen, not to bind. Almost anyone can forge a true bond with it. Only a handful of testers have one yet, and the army a few crates."),
			_line("linnea", "RESEARCHER_TITLE", "Which is why I am told to hand them out slowly, and never to say where they're kept. Now -- someone has been waiting to meet you."),
		]),
		_flag(F_CEREMONY),
		_emote("starter", "?"),
		_say([
			_narr("A small {STARTER} peers out from behind the pylon, bark-skin rustling."),
			_line("linnea", "RESEARCHER_TITLE", "Hold the shard out. Don't grab -- offer. Let it feel what you mean."),
			_narr("The shard warms in your palm like a second heartbeat. A thread of green light runs from the stone to the {STARTER}, and it steps to your side as if it has always stood there."),
		]),
		_flag(F_SHARD),
		_toast("Received: Bonding Shard", "item"),
		_join(STARTER_ID, STARTER_NICKNAME, 0, F_STARTER),
		_say([
			_line("linnea", "RESEARCHER_TITLE", "There. Bonded. Look after each other -- that is the whole of the science, really."),
		]),
	]
	out.append_array(_raid())
	return out


## THE RAID: raiders vault the wall, seize the Researcher and flee west; the Sergeant runs up;
## you give chase toward Oakvale (a scripted warp -- the script ends here).
func _raid() -> Array:
	return [
		_flag(F_ATTACK),
		_say([_narr("A horn blares from the east wall. Then another -- cut short.")]),
		_emote("linnea", "!"),
		_emote("player", "!"),
		_move("raider_captain", Vector2i(CH_RESEARCHER.x + 1, CH_RESEARCHER.y)),
		_move("raider_a", Vector2i(CH_RESEARCHER.x - 1, CH_RESEARCHER.y - 1)),
		_move("raider_b", Vector2i(26, 7)),
		_face("linnea", "toward:raider_captain"),
		_face("player", "toward:raider_captain"),
		_say([
			_line("raider_captain", "RAIDER_CAPTAIN", "{RESEARCHER_TITLE}. You will come with us. Your shards belong to {NATION} now."),
			_line("linnea", "RESEARCHER_TITLE", "{hero} -- keep that shard hidden. Whatever happens, don't let them have it!"),
			_narr("Behind the raiders, a hulking creature strains at black chains -- {STONE} links, glowing dully where they bite."),
		]),
		_flag(F_TAKEN),
		_say([_narr("They seize the Researcher and drag her toward the lower town, scattering townsfolk as they run for the west gate.")]),
		_move("raider_captain", Vector2i(23, 11)),
		_flag(F_FLED),
		_flag("act1.researcher_abducted"),
		_emote("rowan", "!"),
		_move("rowan", Vector2i(CH_RESEARCHER.x, CH_RESEARCHER.y + 2)),
		_face("player", "toward:rowan"),
		_say([
			_line("rowan", "SOLDIER", "Which way did they go?"),
			_line("tam", "ASSISTANT", "West! Out the west gate -- toward the Mossway!"),
			_line("rowan", "SOLDIER", "The Mossway. It runs to Oakvale, and on to the border. They'll cut straight through the village."),
			_me("Oakvale? My mother is in Oakvale!"),
			_line("rowan", "SOLDIER", "Then we don't stand here talking. My riders are saddling now. Run, and don't stop until you're home."),
		]),
		_flag(F_CHASE),
		_toast("Quest: The Burning Road"),
		_say([_narr("You run the Mossway as fast as your legs will carry you, the {STARTER} crashing through the ferns at your side. Long before you reach home, you see the smoke.")]),
		# Whiteouts from here wake you in the ruins (the first fight waits there).
		_respawn(&"oakvale_ruins", &"wayshrine"),
		_warp_cmd(&"oakvale_ruins", &"east_road"),
	]


func _rowan_in_crownhaven() -> NpcEntity:
	var rowan := _npc("rowan", Vector2i(7, 9), "south", "SOLDIER", ALDERMERE_BLUE, "officer")
	rowan.on_interact = StoryCommand.list([IfCommand.make("has(\"%s\")" % F_COMPLETE, [
		IfCommand.make("not has(\"%s\")" % F_ACT1_MET, [
			_say([
				_line("rowan", "SOLDIER", "You came. Good. I'm sorry about Oakvale -- I mean that."),
				_line("rowan", "SOLDIER", "The council's been shouting since dawn. {NATION}'s envoy swears his people never sent a raider across the border. Half the lords want to march tomorrow."),
				_line("rowan", "SOLDIER", "But those chains, {hero}. {NATION} doesn't forge {STONE}. Someone armed those raiders -- and I mean to find out who before this turns into a war."),
				_line("rowan", "SOLDIER", "I've asked for you on my detail. Rest up at the Wayshrine. When you're ready, we ride."),
			]),
			_flag(F_ACT1_MET),
			_toast("Act 1: The Borderlands (coming soon)", "quest"),
		], [
			_say([_line("rowan", "SOLDIER", "Rest while you can. We ride when the council stops shouting.")]),
		]),
	], [
		_say([
			_line("rowan", "SOLDIER", "{SOLDIER_TITLE}, Crownhaven Guard. You'll be one of the Researcher's testers, then."),
			_line("rowan", "SOLDIER", "The army got a crate of her shards. Mine's bonded to a Geode that could hold a bridge by itself. Takes the recruits a month to stop flinching at it."),
		]),
	])])
	return rowan
