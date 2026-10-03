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
##   game/overworld/content/tournaments/*.tres               -- the Crown Arena's cup (DECISIONS.md #33)
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
## DUELS IN STORY (DECISIONS.md #31 / #33 -- the section at the end of this file): a duel trainer
## (Tester Fenna, the Mossway), the rival (Lark: rival.*), the barracks' sparring roster (a cooldown
## per partner: spar_ready()), the Mossway ambush (mossway.ambush.*) and the Crown Arena's tournament
## ladder + champion rematch (arena.crown_cup.*).
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
	# --- Duels in story (DECISIONS.md #33) ---
	"RIVAL": "Lark",                        # the RIVAL: a fellow tester from the first batch
	"FENNA": "Tester Fenna",                # a duel trainer on the Mossway
	"WYNN": "Corporal Wynn",                # barracks sparring partner (warm-up)
	"ALDOUS": "Lieutenant Aldous",          # barracks sparring partner (sharp)
	"BANDIT_BOSS": "Cutpurse Nell",         # the Mossway ambush
	"FOOTPAD": "Footpad",
	"ARENA": "The Crown Arena",
	"CUP": "The Crown Cup",                 # the tournament ladder
	"CUP_TITLE": "Crown Cup Champion",      # the title the first cup earns
	"ARENA_MASTER": "Arena Master Bex",
	"TAMSIN": "Tamsin",                     # the cup's entrants, weakest first
	"HARL": "Old Harl",
	"QUENBY": "Ser Quenby",
	"CHAMPION": "Champion Isolde",
	# --- The three home towns, built out (Oakvale / Crownhaven / Woodland Town) ---
	"MARRA": "Goodwife Marra",              # Oakvale: the Hearth & Hen's landlady
	"NED": "Old Ned",                       # Oakvale: a farmer
	"WICK": "Wick",                         # Oakvale: a shepherd boy
	"MARIBEL": "Innkeeper Maribel",         # Crownhaven: the Gilded Stag
	"GARRICK": "Smith Garrick",             # Crownhaven: the Aldermere Forge
	"VEYRA": "Guildmaster Veyra",           # Crownhaven: the Merchants' Guildhall
	"ODALYS": "Sister Odalys",              # Crownhaven: the Chapel of the Starfall
	"GATE_WARDEN": "Gate Warden",           # Crownhaven: the north gate
	"HALE": "Warden Hale",                  # Woodland Town: the Wardens' Lodge
	"BRYN": "Innkeeper Bryn",               # Woodland Town: the Stumped Hart
	"SEDGE": "Trader Sedge",                # Woodland Town: the Trapper's Trading Post
	"BURR": "Smith Burr",                   # Woodland Town: the smithy
	"TORVALD": "Lumberjack Torvald",        # Woodland Town: the lumber yard
	"ILSE": "Herbalist Ilse",               # Woodland Town: the herb hut
	"FERRA": "Huntress Ferra",              # Woodland Town: the archery range
	"WICKE": "Gran Wicke",                  # Woodland Town: the glade
	"FERN": "Fern",                         # Woodland Town: a child
	"STRANGER": "Cloaked Stranger",         # Woodland Town: a hint of the Thieves Guild
	"ROAD_WARDEN": "Road Warden",           # Woodland Town: the east road
	"SHOP_WOODLAND": "Sedge's Trading Post",
}

## Shop ids (the save keys of their stock -- never rename once shipped; the NAMES above are free).
const SHOP_CROWNHAVEN := "crownhaven_general"
const SHOP_PEDLAR := "mossway_pedlar"
const SHOP_WOODLAND := "woodland_trader"

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
## The example friendly SPAR (Sergeant Rowan's Geode, Crownhaven, after the opening).
const SPAR_ROWAN_ID := "crownhaven.spar.rowan"

# --- Duels in story (DECISIONS.md #33): ids are save keys, never rename once shipped ---------
## The barracks' sparring roster (rising strength: Wynn < Aldous < Rowan). Each is ready once per
## rest (StoryRuleset.spar_cooldown_rests -- spars award Growth, so this stops the farm).
const SPAR_WYNN_ID := "crownhaven.spar.wynn"
const SPAR_ALDOUS_ID := "crownhaven.spar.aldous"
## THE RIVAL: the first duel (a trigger inside Crownhaven's west gate, after the opening), then
## rematches by the arena (once per rest). Progress lives in flags so later rematches scale:
const RIVAL_DUEL_ID := "crownhaven.rival.lark"
const F_RIVAL_MET := "rival.met"
## Rival duels FOUGHT (int) -- the rematch spec scales on it (BattleSpec.scale_flag).
const F_RIVAL_STAGE := "rival.stage"
## Rival duels WON by the hero (int).
const F_RIVAL_WINS := "rival.wins"
## The first rival duel is behind you.
const F_RIVAL_DUEL1 := "rival.duel1"
## THE MOSSWAY AMBUSH (after the Act 1 hook): a trigger on the brook's plank bridge.
const F_AMBUSH_SPRUNG := "mossway.ambush.sprung"
const F_AMBUSH_FOOTPAD := "mossway.ambush.footpad_beaten"
const F_AMBUSH_CLEARED := "mossway.ambush.cleared"
## THE CROWN CUP (a TournamentResource -- its run / round / wins / title flags are "arena.crown_cup.*").
const CUP_ID := "crown_cup"
const CUP_WINS_FLAG := "arena.crown_cup.wins"
const CUP_TITLE_FLAG := "arena.crown_cup.champion"
## The champion's rematch after the cup (once per rest), scaling with every win over her.
const CHAMPION_REMATCH_ID := "arena.crown_cup.champion_rematch"
const F_CHAMPION_BEATEN := "arena.crown_cup.champion_beaten"

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
	for d in ["areas/oakvale", "areas/oakvale_ruins", "areas/mossway", "areas/crownhaven", "areas/woodland_town",
			"battles", "shops",
			"tournaments"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + d))
	_build_hero()
	_build_ruleset()
	_build_shops()
	_build_tournaments()
	_build_battle_map()
	_build_first_fight_map()
	_build_oakvale(false)
	_build_oakvale(true)
	_build_mossway()
	_build_crownhaven()
	_build_woodland_town()
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
	# Sparring partners (DECISIONS.md #33): each is ready again after one rest -- spars award Growth
	# by the ordinary story rules, and this keeps a friendly bout from being a Growth farm.
	rs.spar_cooldown_rests = 1
	rs.spar_cooldown_steps = 0
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

	# Woodland Town's trading post: a forester's stock -- cures and tonics at forest prices.
	var woodland := ShopResource.new()
	woodland.id = StringName(SHOP_WOODLAND)
	woodland.display_name = _t("{SHOP_WOODLAND}")
	woodland.greeting = _t("\"Furs, flasks and forest remedies. Everything you'd need if the trees ever start whispering back.\"")
	var ws: Array[ShopStockEntry] = [
		_stock("mossleaf_tonic"),
		_stock("bitterroot_salve"),
		_stock("heartwood_tonic", 0, 4),
		_stock("clearwater_draught", 0, 2),
		_stock("windwhisper_pendant", 0, 1),
	]
	woodland.stock = ws
	woodland.restock = ShopResource.Restock.ON_REST
	woodland.sell_ratio = -1.0
	_save(woodland, ShopResource.path_for(SHOP_WOODLAND))


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
## The Hearth & Hen (the village inn, north of the high road) and a family cottage on the west edge.
const OAK_INN := Rect2i(15, 6, 3, 2)
const OAK_COTTAGE := Rect2i(1, 9, 2, 2)
## The mill lane runs out of the village here, west, toward Farm Hamlet.
const OAK_WEST_Y := 12


## The buildings. The inn and the cottage have no ruined counterpart: the raid left only scorched
## ground there (and the ruins' node budget has no room for two more burned houses).
func _oak_buildings(ruined: bool = false) -> Array:
	var base: Array = [OAK_HOME, OAK_HALL, OAK_FARM, OAK_BAKERY, OAK_BARN, OAK_MILL]
	if not ruined:
		base.append_array([OAK_INN, OAK_COTTAGE])
	return base


func _oak_terrain(x: int, y: int, ruined: bool) -> String:
	var c := Vector2i(x, y)
	# Outer border: forest.
	if y <= 1 or y >= OAK_H - 1 or (x == 0 and not (y == OAK_WEST_Y and not ruined)):
		return "tree"
	# The west lane runs out to the Farm Hamlet track (the village as it was; the fire closed it).
	if not ruined and y == OAK_WEST_Y and x <= 1:
		return "forest_dirt"
	# East: a tree line with one gap for the road; the road runs on to the map edge.
	if x == 20:
		return "forest_dirt" if y == OAK_ROAD_Y else "tree"
	if x >= 21:
		if y == OAK_ROAD_Y:
			return "forest_dirt"
		return "tree" if (x + y) % 3 != 0 or y < 4 or y > 14 else "grass_plains"
	# Buildings: stone blocks under the house props; after the raid, smouldering embers under
	# the ruins (a vent glows and never lets a walker in). The bakery still stands.
	if _in(_oak_buildings(ruined), c):
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
	# The inn's doorstep path down to the high road.
	if not ruined and x >= 15 and x <= 17 and y == 8:
		return "forest_dirt"
	if c in [Vector2i(5, 10), Vector2i(17, 7), Vector2i(19, 4), Vector2i(13, 4), Vector2i(19, 16),
			Vector2i(1, 16), Vector2i(7, 16), Vector2i(19, 11)]:
		return "tree"
	# The village orchard behind the inn, and a windbreak along the south lane (the fire took them).
	if not ruined and c in [Vector2i(18, 5), Vector2i(19, 6), Vector2i(18, 7), Vector2i(19, 2), Vector2i(14, 5),
			Vector2i(9, 17), Vector2i(15, 17), Vector2i(2, 16)]:
		return "tree"
	if ruined:
		# Scorched earth and drifts of ash around every burned building, and scorch marks
		# across the green.
		for r in _oak_buildings(true):
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
		# The mill lane's west end: the cart track to Farm Hamlet (not part of the story yet -- the
		# warp targets the village itself and its condition never holds, so it always answers).
		ents.append(_warp("west_exit", Rect2i(0, OAK_WEST_Y, 1, 1), &"oakvale", &"start", "",
			"has(\"world.farm_hamlet_open\")", _scene("oak_hamlet_locked", [
				_beat(StoryBeat.NARRATOR, "", "The cart track west of the mill runs on through the barley toward Farm Hamlet. A hurdle gate across it is tied shut with a ribbon: \"Harvest in progress -- back soon.\""),
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
		"inn": [OAK_INN, Color(0.62, 0.3, 0.2)],
		"cottage": [OAK_COTTAGE, Color(0.5, 0.42, 0.26)],
	}
	for k in roofs:
		var r: Rect2i = roofs[k][0]
		# The bakery stands (scorched) -- everything else burned.
		var kind: String = "ruin" if ruined and k != "bakery" else "house"
		var tint: Color = roofs[k][1]
		if ruined and (k == "inn" or k == "cottage"):
			continue
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
		# Farming-village flavour: a scarecrow in the field, a second haystack, a market-day stall
		# on the plaza, lamps at its corners, a barrel by the inn door and a fence round the pond.
		out.append(_prop("scarecrow", "scarecrow", Vector2i(16, 10), Vector2i.ONE, Color(0.5, 0.36, 0.2), true))
		out.append(_prop("haystack_2", "haystack", Vector2i(19, 15), Vector2i.ONE, Color.WHITE, true))
		out.append(_prop("market_stall", "stall", Vector2i(11, 7), Vector2i(2, 1), Color(0.78, 0.6, 0.22), true))
		for lc in [Vector2i(7, 6), Vector2i(13, 6), Vector2i(7, 12), Vector2i(13, 12)]:
			out.append(_prop("lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
		out.append(_prop("inn_barrels", "barrels", Vector2i(14, 7), Vector2i.ONE, Color.WHITE, true))
		out.append(_prop("pond_fence", "fence", Vector2i(6, 5), Vector2i(2, 1), Color(0.5, 0.36, 0.22), true))
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

	# --- The farming village, filled in: the inn, the fields, the pond, the lanes ---------------
	out.append(_sign("inn_sign", Vector2i(14, 8), "The Hearth & Hen",
		"THE HEARTH & HEN\nBed, broth and a warm hearth. Muddy boots at the door, please.\nRoad north-east: Crownhaven by way of River Crossing."))
	out.append(_sign("field_sign", Vector2i(13, 10), "Barley Field",
		"\"Please keep to the lane. The barley is counting on you.\" -- Ned"))
	out.append(_sign("mill_sign", Vector2i(5, 11), "The Mill Lane",
		"WEST: the cart track to Farm Hamlet.\nMILL LANE: flour, sacks and gossip, in that order."))
	var marra := _npc("marra", Vector2i(15, 8), "south", "MARRA", Color(0.7, 0.4, 0.3), "villager")
	marra.on_interact = StoryCommand.list([_say([
		_line("marra", "MARRA", "Stew's on, and the hearth's lit. Travellers stop here before the Mossway -- it's a long road to River Crossing, and a longer one to the city."),
		_line("marra", "MARRA", "Folk say the old bridge at River Crossing is older than the kingdom. Mind the toll-keeper; he'll tell you the same story twice."),
	])])
	out.append(marra)
	var ned := _npc("ned", Vector2i(13, 8), "east", "NED", Color(0.5, 0.45, 0.3), "elder")
	ned.on_interact = StoryCommand.list([_say([
		_line("ned", "NED", "Forty harvests I've brought in off that field. A good year's barley for the bread, a bad year's for the pigs."),
		_line("ned", "NED", "This year the creatures in the hedgerow have been restless. Something stirs them. Mind yourself out there."),
	])])
	out.append(ned)
	var wick := _npc("wick", Vector2i(8, 5), "south", "WICK", Color(0.62, 0.5, 0.34), "child")
	wick.on_interact = StoryCommand.list([_say([
		_line("wick", "WICK", "I'm watching the pond for the golden frog. Nobody's seen it. That's how I know it's clever."),
	])])
	out.append(wick)
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
	# RIVER CROSSING (the world map's stop between Oakvale and the capital): the brook's plank
	# bridge, lamp-posted and signed, with a fence along the bank.
	ents.append(_sign("river_crossing_sign", Vector2i(20, 5), "River Crossing",
		"RIVER CROSSING\nThe King's bridge. Cross freely; cross carefully.\nWest: Oakvale.  East: Crownhaven."))
	ents.append(_prop("bridge_lamp_n", "lamp", Vector2i(20, 7), Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
	ents.append(_prop("bridge_lamp_s", "lamp", Vector2i(22, 5), Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
	ents.append(_prop("bank_fence", "fence", Vector2i(20, 2), Vector2i(1, 3), Color(0.5, 0.36, 0.22), true))

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

	# Duels in story (DECISIONS.md #33): a trainer who challenges you to a DUEL, and the ambush.
	ents.append(_fenna())
	ents.append_array(_ambush())

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
	Rect2i(22, 15, 3, 2)]
const CH_STALLS := [Rect2i(11, 12, 2, 1), Rect2i(18, 12, 2, 1), Rect2i(11, 16, 2, 1), Rect2i(18, 16, 2, 1)]
## The ceremony stage in front of the workshop.
const CH_RESEARCHER := Vector2i(24, 8)
const CH_PYLON := Vector2i(22, 8)
## The capital's districts, built out: the Gilded Stag inn (by the market), the Merchants' Guildhall
## (south), the Chapel of the Starfall (the east park), the Aldermere Forge (the east quarter).
const CH_INN := Rect2i(7, 11, 3, 2)
const CH_GUILD := Rect2i(14, 19, 3, 2)
const CH_CHAPEL := Rect2i(24, 10, 3, 2)
const CH_SMITHY := Rect2i(25, 15, 2, 2)
const CH_NEW_BUILDINGS := [CH_INN, CH_GUILD, CH_CHAPEL, CH_SMITHY]
## The north gate (the road to Woodland Town) and the east gate (the road to the Mountain Pass,
## closed by royal order); both are gaps in the wall ring with a road running out of them.
const CH_NORTH_GATE := Vector2i(9, 3)
const CH_EAST_GATE := Vector2i(27, 13)


func _ch_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	var inside: bool = x > CH_WALL.position.x and x < CH_WALL.end.x - 1 \
		and y > CH_WALL.position.y and y < CH_WALL.end.y - 1
	var on_wall: bool = CH_WALL.has_point(c) and not inside
	if on_wall:
		return "flagstones" if (c == CH_GATE or c == CH_NORTH_GATE or c == CH_EAST_GATE) else "stone_wall"
	if not CH_WALL.has_point(c):
		# The north road (to Woodland Town) and the east road (to the Mountain Pass).
		if x == CH_NORTH_GATE.x and y < CH_WALL.position.y:
			return "forest_dirt"
		if y == CH_EAST_GATE.y and x > CH_EAST_GATE.x:
			return "forest_dirt"
		if absi(x - CH_NORTH_GATE.x) <= 1 and y == CH_WALL.position.y - 1:
			return "grass_plains"
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
	if CH_KEEP.has_point(c) or CH_BARRACKS.has_point(c) or CH_LAB.has_point(c) or _in(CH_HOUSES, c) \
			or CH_ARENA.has_point(c) or _in(CH_NEW_BUILDINGS, c):
		return "stone_wall"
	# The north gate's avenue to the keep courtyard, and the chapel's garden path.
	if x == CH_NORTH_GATE.x and y >= 4 and y <= 8:
		return "flagstones"
	if (x == 25 and y == 12) or (x == 26 and y == 12):
		return "flagstones"
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
	if c in [Vector2i(26, 11), Vector2i(4, 21), Vector2i(26, 22), Vector2i(10, 22),
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
		"north_gate": {"cell": [CH_NORTH_GATE.x, 1, 0], "facing": "south"},
		"wayshrine": {"cell": [CH_FOUNTAIN.x, CH_FOUNTAIN.y + 1, 0], "facing": "north"},
	}

	var ents: Array = []
	ents.append_array(_ch_scenery())
	ents.append(_shrine(CH_FOUNTAIN, "Crownhaven Wayshrine"))
	ents.append_array(_ch_people())
	# Duels in story (DECISIONS.md #33): the rival, the barracks' sparring roster, the Crown Arena.
	ents.append_array(_rival())
	ents.append_array(_spar_partners())
	ents.append_array(_arena())
	ents.append(_warp("west_exit", Rect2i(0, CH_GATE.y, 1, 1), &"mossway", &"east"))
	# The wider kingdom: the north gate's road to Woodland Town (open once the opening is over --
	# the alert is lifted), and the east gate's road to the Mountain Pass (closed by royal order).
	ents.append_array(_ch_districts())
	ents.append(_warp("north_exit", Rect2i(CH_NORTH_GATE.x, 0, 1, 1), &"woodland_town", &"east_road", "",
		"has(\"%s\")" % F_COMPLETE, _scene("ch_north_locked", [
			_narr("A Gate Warden bars the way. \"The north road is closed while the alert stands. The Sergeant will pass word when it's safe to leave the city.\""),
		])))
	ents.append(_warp("east_exit", Rect2i(CH_W - 1, CH_EAST_GATE.y, 1, 1), &"crownhaven", &"west_gate", "",
		"has(\"world.mountain_road_open\")", _scene("ch_east_locked", [
			_narr("A warden shakes his head. \"The Mountain Pass road is closed by order of the crown. Landslides, they say. Soldiers, I say.\""),
		])))
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
			Vector2i(3, 18), Vector2i(3, 8), Vector2i(27, 8), Vector2i(27, 18), Vector2i(21, 3)]:
		out.append(_prop("tower_%d_%d" % [c.x, c.y], "tower", c, Vector2i.ONE, ALDERMERE_BLUE))
	out.append(_prop("west_gatehouse", "gate", Vector2i(CH_GATE.x, CH_GATE.y - 1), Vector2i(1, 3), ALDERMERE_BLUE))
	out.append(_prop("north_gatehouse", "gate", Vector2i(CH_NORTH_GATE.x - 1, CH_NORTH_GATE.y), Vector2i(3, 1), ALDERMERE_BLUE))
	out.append(_prop("east_gatehouse", "gate", Vector2i(CH_EAST_GATE.x, CH_EAST_GATE.y - 1), Vector2i(1, 3), ALDERMERE_BLUE))
	# The new districts: a gabled inn, a gold-roofed guildhall, a blue-slate chapel, a forge.
	out.append(_prop("gilded_stag", "house", CH_INN.position, CH_INN.size, Color(0.62, 0.42, 0.16)))
	out.append(_prop("guildhall", "keep", CH_GUILD.position, CH_GUILD.size, Color(0.72, 0.55, 0.15)))
	out.append(_prop("chapel", "chapel", CH_CHAPEL.position, CH_CHAPEL.size, Color(0.3, 0.38, 0.6)))
	out.append(_prop("forge", "smithy", CH_SMITHY.position, CH_SMITHY.size, Color(0.3, 0.28, 0.3)))
	out.append(_prop("forge_barrels", "barrels", Vector2i(24, 17), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("guild_banner_w", "banner", Vector2i(13, 21), Vector2i.ONE, Color(0.72, 0.55, 0.15), true))
	out.append(_prop("guild_banner_e", "banner", Vector2i(17, 21), Vector2i.ONE, Color(0.72, 0.55, 0.15), true))
	out.append(_prop("inn_barrels", "barrels", Vector2i(6, 14), Vector2i.ONE, Color.WHITE, true))
	# Street lamps: the gate street, the keep courtyard and the workshop yard.
	for lc in [Vector2i(5, 14), Vector2i(12, 10), Vector2i(18, 10), Vector2i(20, 14), Vector2i(25, 9), Vector2i(10, 5), Vector2i(26, 14)]:
		out.append(_prop("lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
	# The chapel garden: standing stones for the fallen star, and the park's trees kept as shade.
	out.append(_prop("chapel_lamp", "lamp", Vector2i(24, 12), Vector2i.ONE, Color(0.7, 0.9, 1.0), true))
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


## The capital's built-out districts: the north gate, the Gilded Stag, the Merchants' Guildhall,
## the Chapel of the Starfall and the Aldermere Forge -- signs and people, no scripts.
func _ch_districts() -> Array:
	var out: Array = []
	var raided: String = "has(\"%s\")" % F_ATTACK
	# The north gate.
	out.append(_sign("north_gate_sign", Vector2i(8, 5), "North Gate",
		"THE NORTH GATE\nWoodland Town and the Deepwood road. Wardens' tolls are paid at the Lodge."))
	var warden := _npc("gate_warden", Vector2i(10, 4), "west", "GATE_WARDEN", ALDERMERE_BLUE, "guard")
	warden.on_interact = StoryCommand.list([IfCommand.make("has(\"%s\")" % F_COMPLETE, [
		_say([_line("gate_warden", "GATE_WARDEN", "The north road is open again. Woodland Town is a day's walk under the trees -- keep to the cart ruts, and don't follow any lights.")]),
	], [
		_say([_line("gate_warden", "GATE_WARDEN", "The north gate stays barred till the alert's lifted. Nobody in, nobody out.")]),
	])])
	out.append(warden)

	# The Gilded Stag (inn).
	out.append(_sign("inn_sign", Vector2i(10, 14), "The Gilded Stag",
		"THE GILDED STAG\nFeather beds, hot baths, a locked stable. Guests of the crown drink free."))
	var maribel := _npc("maribel", Vector2i(10, 12), "west", "MARIBEL", Color(0.66, 0.42, 0.3), "villager")
	maribel.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("maribel", "MARIBEL", "Half my rooms are full of frightened scholars and the other half of soldiers. The kitchen's never been so busy -- and I've never been so worried.")]),
	], [
		_say([_line("maribel", "MARIBEL", "Welcome to the Stag! Testers from every corner of {KINGDOM} sleep under this roof the night before the ceremony. Nobody sleeps well, mind.")]),
		_say([_line("maribel", "MARIBEL", "If you're heading for the forest, the Wardens at Woodland Town keep a good table. Tell them Maribel sent you -- they'll water the soup.")]),
	])])
	out.append(maribel)

	# The Merchants' Guildhall.
	out.append(_sign("guild_sign", Vector2i(16, 21), "The Merchants' Guildhall",
		"MERCHANTS' GUILDHALL\nCharter of the Crown. Weights, measures and honest coin."))
	var veyra := _npc("veyra", Vector2i(15, 21), "south", "VEYRA", Color(0.72, 0.55, 0.15), "noble")
	veyra.dialogue = _scene("ch_veyra", [
		_line("veyra", "VEYRA", "Every road in {KINGDOM} runs through this city, and every merchant on those roads answers to this hall."),
		_line("veyra", "VEYRA", "Timber from Woodland Town, grain from Oakvale, iron from the Mountain Pass -- when the roads are open. Some are closed. I dislike closed roads."),
	])
	out.append(veyra)

	# The Chapel of the Starfall.
	out.append(_sign("chapel_sign", Vector2i(22, 12), "Chapel of the Starfall",
		"THE CHAPEL OF THE STARFALL\nWhere the old star's dust was first gathered. All are welcome; silence is kindly requested."))
	var odalys := _npc("odalys", Vector2i(26, 12), "west", "ODALYS", Color(0.78, 0.8, 0.9), "elder")
	odalys.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("odalys", "ODALYS", "I lit a candle for the Researcher. Starstone listens, they say, to anyone who's afraid enough to be honest.")]),
	], [
		_say([_line("odalys", "ODALYS", "Long ago a star fell, and the land remembers it. Every creature and every shard carries a little of that falling. Be gentle with what you bond.")]),
	])])
	out.append(odalys)

	# The Aldermere Forge.
	out.append(_sign("forge_sign", Vector2i(25, 14), "The Aldermere Forge",
		"THE ALDERMERE FORGE\nArms for the Guard. Civilians: please don't touch the anvil. It bites."))
	var garrick := _npc("garrick", Vector2i(25, 17), "north", "GARRICK", Color(0.4, 0.3, 0.26), "trainer")
	garrick.on_interact = StoryCommand.list([IfCommand.make(raided, [
		_say([_line("garrick", "GARRICK", "Spearheads. Shield rims. Every blade the Guard owns passes under my hammer this week. Whoever did this is going to regret it.")]),
	], [
		_say([_line("garrick", "GARRICK", "Forged half the spears on those walls. The other half I'm still forging. Ask the Sergeant -- the Guard never has enough spears.")]),
	])])
	out.append(garrick)

	# A courtier in the keep's shadow.
	var merrow := _npc("merrow", Vector2i(19, 10), "west", "Lady Merrow", Color(0.52, 0.3, 0.5), "noble")
	merrow.dialogue = _scene("ch_merrow", [
		_line("merrow", "Lady Merrow", "The King will not see petitioners, but the garden is lovely this time of year. Please admire it quietly."),
	])
	out.append(merrow)
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
		# Beside the player, clear of the Chapel of the Starfall's wall south of the workshop.
		_move("rowan", Vector2i(CH_RESEARCHER.x - 1, CH_RESEARCHER.y + 2)),
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
			_rowan_spar_offer(),
		]),
	], [
		_say([
			_line("rowan", "SOLDIER", "{SOLDIER_TITLE}, Crownhaven Guard. You'll be one of the Researcher's testers, then."),
			_line("rowan", "SOLDIER", "The army got a crate of her shards. Mine's bonded to a Geode that could hold a bridge by itself. Takes the recruits a month to stop flinching at it."),
		]),
	])])
	return rowan


## THE EXAMPLE SPAR (DECISIONS.md #29): a friendly bout with the Sergeant's Geode, repeatable -- once
## per rest, like every sparring partner (DECISIONS.md #33). It is tagged `spar`, so nobody falls
## for good in it, even in a Classic journey -- a knocked-out partner just gets back up
## (StoryRuleset.spar_ko_recovers). He heads the barracks' roster (the strongest of the three).
func _rowan_spar_offer() -> IfCommand:
	return _spar_partner_offer(SPAR_ROWAN_ID, "rowan", "SOLDIER", "{SOLDIER_TITLE}",
		[{"character_id": GUEST_ID, "strength": 0.8}],
		"Want to keep your partner sharp? Geode could use the exercise. A friendly bout -- nobody gets hurt for real.",
		"Ha! Geode felt that one. You're learning.",
		"On your feet. That's what spars are for -- come back when you're ready.",
		"Geode's still shaking off the last bout. Rest up at the Wayshrine, then come and find me.")


# =====================================================================================
#  DUELS IN STORY (DECISIONS.md #31 / #33): duels are not on the menu any more -- story mode
#  offers them. Trainers who challenge you to a DUEL, the RIVAL, SPARRING partners, an AMBUSH,
#  and the CROWN ARENA's tournament ladder. Opponents are duel-eligible roster creatures
#  (BattleSpec.validate checks), their strength the duel's stat scale (DuelScaling).
#  DECISION 7 (humans fight alongside creatures) is NOT built yet: the people are the trainers;
#  their creatures fight. PARTY DUELS: a duel fields your lead plus up to two bench members (the
#  duel ruleset's story format) against the opponent's TEAM -- Fenna, Lark, the Cup's later
#  rounds and the champion bring two or three; wild encounters and the ambush stay one foe.
# =====================================================================================

## A DUEL [BattleSpec]: [param team] = [{character_id, strength}], the lead first.
func _duel_spec(encounter_id: String, opponent: String, speaker: StringName, team: Array,
		spar: bool, policy: BattleSpec.DefeatPolicy, reward_gold: int = 0, items: Array = [],
		flags: Array = []) -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.DUEL
	spec.encounter_id = encounter_id
	spec.opponent_name = _t(opponent)
	spec.opponent_speaker_id = speaker
	var typed: Array[Dictionary] = []
	for t in team:
		typed.append((t as Dictionary).duplicate())
	spec.opponent_team = typed
	spec.spar = spar
	spec.defeat_policy = policy
	spec.reward_gold = reward_gold
	var ri: Array[StringName] = []
	for i in items:
		ri.append(StringName(String(i)))
	spec.reward_items = ri
	var rf: Array[String] = []
	for f in flags:
		rf.append(String(f))
	spec.reward_flags = rf
	return spec


func _duel(spec: BattleSpec) -> StartDuelCommand:
	var d := StartDuelCommand.new()
	d.spec = spec
	d.source = BattleRequest.SOURCE_SCRIPT
	return d


func _inc(key: String, by: int = 1) -> IncFlagCommand:
	var c := IncFlagCommand.new()
	c.key = key
	c.by = by
	return c


## "The duel was actually fought" (a flee / an abort -- e.g. nobody able to fight -- is neither).
const FOUGHT := "outcome() == \"victory\" or outcome() == \"defeat\""


## A SPARRING PARTNER's offer (DECISIONS.md #33): ready -> "spar?" -> a friendly duel (spar: never
## permadeath; Growth by the ordinary story rules); not ready -> the [param tired] line, until the
## journey has rested (StoryRuleset.spar_cooldown_rests, [StorySparring]).
func _spar_partner_offer(encounter_id: String, npc_id: String, name_key: String, opponent: String,
		team: Array, ask_text: String, win_text: String, lose_text: String, tired_text: String) -> IfCommand:
	var spec := _duel_spec(encounter_id, opponent, StringName("npc_" + npc_id), team, true,
		BattleSpec.DefeatPolicy.CONTINUE)
	var ask := ChoiceCommand.new()
	ask.prompt = _line(npc_id, name_key, ask_text)
	var yes := ChoiceOption.make("Let's spar.", [
		_duel(spec),
		IfCommand.make("outcome() == \"victory\"", [
			_say([_line(npc_id, name_key, win_text)]),
		], [
			IfCommand.make("outcome() == \"defeat\"", [_say([_line(npc_id, name_key, lose_text)])]),
		]),
	])
	var no := ChoiceOption.make("Not now.", [], true)
	ask.options = StoryCommand.list([yes, no])
	return IfCommand.make("spar_ready(\"%s\")" % encounter_id, [ask], [
		_say([_line(npc_id, name_key, tired_text)]),
	])


# --- The Mossway: a duel trainer, and the ambush ---------------------------------------

## TESTER FENNA: a TRAINER whose battle is a DUEL (line of sight like Bram; a real battle: a loss
## whites out, and in Classic a partner knocked out in it falls).
func _fenna() -> TrainerEntity:
	var t := TrainerEntity.new()
	t.id = &"fenna"
	t.cell = Vector3i(11, 7, 0)
	t.facing = "north"
	t.display_name = _t("{FENNA}")
	t.speaker_name = t.display_name
	t.speaker_id = &"npc_fenna"
	t.tint = Color(0.62, 0.4, 0.56)
	t.figure = "trainer"
	t.sight_range = 3
	t.visible_if = "has(\"%s\")" % F_COMPLETE
	t.pre_scene = _scene("moss_fenna_pre", [
		_beat(&"self", "", "A shard! You're a tester too? Then you know the rule -- two testers meet on the road, their partners have a word. Two of mine against yours!"),
	])
	t.defeated_scene = _scene("moss_fenna_after", [
		_beat(&"self", "", "Well fought. My Petalfang's sulking now -- that means you earned it."),
	])
	# A small TEAM (party duels: the story format fields your lead + up to 2 bench), kept weak --
	# she is the first trainer on the road.
	var spec := _duel_spec("", "{FENNA}", &"npc_fenna", [{"character_id": "petalfang", "strength": 0.85},
			{"character_id": "undead", "strength": 0.7}],
		false, BattleSpec.DefeatPolicy.WHITEOUT, 90)
	spec.clash_intro = true
	t.battle = spec
	return t


## THE AMBUSH (DECISIONS.md #7 / #33 "attacked by criminals"): once the Sergeant has signed you on
## (act1.met_rowan), bandits wait at the brook's plank bridge -- the only crossing, so the trigger
## cannot be walked round. Two self-defence duels back to back (HP carries between them), REAL
## battles: a loss whites out (the bandits wait for you again; a beaten footpad stays beaten) and a
## Classic partner knocked out in them falls. Winning pays a purse and a stolen draught.
func _ambush() -> Array:
	var out: Array = []
	var vis: String = "has(\"%s\") and not has(\"%s\")" % [F_AMBUSH_SPRUNG, F_AMBUSH_CLEARED]
	var nell := _npc("nell", Vector2i(22, 4), "south", "BANDIT_BOSS", Color(0.3, 0.26, 0.22), "raider")
	nell.visible_if = vis
	nell.dialogue = _scene("moss_nell_idle", [_line("nell", "BANDIT_BOSS", "Still here? Then your purse is still ours.")])
	out.append(nell)
	var pad := _npc("footpad", Vector2i(20, 8), "north", "FOOTPAD", Color(0.36, 0.3, 0.24), "raider")
	pad.visible_if = vis
	out.append(pad)

	var footpad_spec := _duel_spec("mossway.ambush.footpad", "{FOOTPAD}", &"npc_footpad",
		[{"character_id": "mycothrall", "strength": 0.9}], false, BattleSpec.DefeatPolicy.WHITEOUT,
		40, [], [F_AMBUSH_FOOTPAD])
	var nell_spec := _duel_spec("mossway.ambush.nell", "{BANDIT_BOSS}", &"npc_nell",
		[{"character_id": "petalfang", "strength": 1.0}], false, BattleSpec.DefeatPolicy.WHITEOUT,
		180, ["dawnpetal_draught"])
	var boss_bout: Array = [
		_say([_line("nell", "BANDIT_BOSS", "Useless! Fine -- I'll take it off you myself.")]),
		_duel(nell_spec),
		IfCommand.make("outcome() == \"victory\"", [
			_say([
				_line("nell", "BANDIT_BOSS", "Enough! Take the purse -- it wasn't ours anyway."),
				_narr("The bandits scatter into the ferns, leaving a pouch of stolen coin and a Dawnpetal Draught on the planks."),
			]),
			_flag(F_AMBUSH_CLEARED),
			_toast("The Mossway is safe again"),
			SaveGameCommand.new(),
		], [
			IfCommand.make("not (%s)" % FOUGHT, [
				_say([_line("nell", "BANDIT_BOSS", "Nothing left in you worth taking? Off with you, then.")]),
			]),
		]),
	]
	var zone := TriggerZone.new()
	zone.id = &"bandit_ambush"
	zone.area_rect = Rect2i(21, 6, 1, 1)
	zone.once = false
	zone.visible_if = "has(\"%s\") and not has(\"%s\")" % [F_ACT1_MET, F_AMBUSH_CLEARED]
	zone.on_step = StoryCommand.list([
		_flag(F_AMBUSH_SPRUNG),
		_say([_narr("Dusk is gathering over the brook. Halfway across the planks, the ferns on both banks stand up.")]),
		_emote("player", "!"),
		_move("nell", Vector2i(22, 6)),
		_move("footpad", Vector2i(20, 6)),
		_face("player", "toward:nell"),
		_say([
			_line("nell", "BANDIT_BOSS", "Evening, tester. That shard of yours, the gold in your purse -- set them on the planks and walk on."),
			_me("It isn't mine to give. And neither is the gold."),
			_line("nell", "BANDIT_BOSS", "The Guard's all ridden for the border, love. Nobody's coming. Take them!"),
		]),
		IfCommand.make("not has(\"%s\")" % F_AMBUSH_FOOTPAD, [
			_face("player", "toward:footpad"),
			_duel(footpad_spec),
			IfCommand.make("outcome() == \"victory\"", boss_bout, [
				IfCommand.make("not (%s)" % FOUGHT, [
					_say([_line("nell", "BANDIT_BOSS", "Nothing left in you worth taking? Off with you, then.")]),
				]),
			]),
		], boss_bout),
	])
	out.append(zone)
	return out


# --- Crownhaven: the rival, the barracks' sparring roster, the Crown Arena --------------

const CH_ARENA := Rect2i(22, 19, 5, 3)
const CH_ARENA_MASTER := Vector2i(22, 22)
const CH_LARK_START := Vector2i(7, 14)
const CH_LARK_ARENA := Vector2i(23, 18)
const CH_CHAMPION := Vector2i(25, 18)
## Every traveller from the west gate steps here (the gate guards flank the cell before it).
const CH_RIVAL_TRIGGER := Rect2i(5, 13, 1, 1)


## The RIVAL's duel spec: Lark's Blightcap, a FRIENDLY (DECISIONS.md #29: rival friendlies never
## cost a life), scaling +8% per rival duel fought (rival.stage, up to 6) -- the first duel is
## stage 0.
func _rival_spec() -> BattleSpec:
	var spec := _duel_spec(RIVAL_DUEL_ID, "{RIVAL}", &"npc_lark",
		[{"character_id": "blightcap", "strength": 0.9}, {"character_id": "petalfang", "strength": 0.75}],
		true, BattleSpec.DefeatPolicy.CONTINUE, 60)
	spec.clash_intro = true
	spec.scale_flag = F_RIVAL_STAGE
	spec.scale_step = 0.08
	spec.scale_max_steps = 6
	return spec


## After any rival duel that was FOUGHT: the stage counter (the next rematch is stronger), the win
## counter, and Lark's line.
func _rival_after(win: Array, lose: Array) -> Array:
	return [
		IfCommand.make(FOUGHT, [
			_inc(F_RIVAL_STAGE),
			IfCommand.make("outcome() == \"victory\"", [_inc(F_RIVAL_WINS), _say(win)], [_say(lose)]),
		]),
	]


func _rival() -> Array:
	var out: Array = []
	var lark := _npc("lark", CH_LARK_START, "west", "RIVAL", Color(0.78, 0.5, 0.2), "trainer")
	lark.visible_if = "has(\"%s\") and not has(\"%s\")" % [F_COMPLETE, F_RIVAL_DUEL1]
	lark.dialogue = _scene("ch_lark_wait", [_line("lark", "RIVAL", "Well? Come on, Oakvale -- I haven't got all day.")])
	out.append(lark)

	var first: Array = [
		_emote("lark", "!"),
		_move("lark", Vector2i(CH_RIVAL_TRIGGER.position.x + 1, CH_RIVAL_TRIGGER.position.y)),
		_face("player", "toward:lark"),
		_face("lark", "toward:player"),
		_say([
			_line("lark", "RIVAL", "So YOU'RE the one from Oakvale. The tester who rode with the Sergeant."),
			_line("lark", "RIVAL", "I'm {RIVAL}. First batch -- the Researcher picked me before she'd even heard of your village. Everyone in the barracks is talking about you, and I'm sick of it."),
			_me("My village burned, {RIVAL}. I didn't do it to be talked about."),
			_line("lark", "RIVAL", "...I know. I'm sorry about that. Truly. But a shard is a shard, and I want to see what yours can do. One bout -- a friendly. Nobody gets hurt."),
		]),
		_flag(F_RIVAL_MET),
		_duel(_rival_spec()),
	]
	first.append_array(_rival_after([
		_line("lark", "RIVAL", "...Huh. Fine. FINE. You got lucky, and Puck was still full from breakfast."),
	], [
		_line("lark", "RIVAL", "Ha! See? First batch. Don't feel bad, Oakvale -- you'll get there. Probably."),
	]))
	first.append(IfCommand.make(FOUGHT, [
		_say([
			_line("lark", "RIVAL", "I'll be at the Crown Arena. Every tester worth their shard ends up there sooner or later -- come find me when you want a rematch."),
		]),
		_flag(F_RIVAL_DUEL1),
		_toast("Rival: {RIVAL}"),
		SaveGameCommand.new(),
	], [
		_say([_line("lark", "RIVAL", "Your partner can barely stand. Rest up -- I'm not beating you like THAT.")]),
	]))
	var zone := TriggerZone.new()
	zone.id = &"rival_meet"
	zone.area_rect = CH_RIVAL_TRIGGER
	zone.once = false
	zone.visible_if = lark.visible_if
	zone.on_step = StoryCommand.list(first)
	out.append(zone)

	# By the arena after the first duel: rematches, once per rest, stronger every time.
	var lark2 := _npc("lark_arena", CH_LARK_ARENA, "south", "RIVAL", Color(0.78, 0.5, 0.2), "trainer")
	lark2.visible_if = "has(\"%s\")" % F_RIVAL_DUEL1
	var ask := ChoiceCommand.new()
	ask.prompt = _line("lark_arena", "RIVAL", "Back for more, Oakvale? Puck's been training. Rematch?")
	var yes_cmds: Array = [_duel(_rival_spec())]
	yes_cmds.append_array(_rival_after([
		_line("lark_arena", "RIVAL", "Again?! ...Alright. You're good. Don't let it go to your head."),
	], [
		_line("lark_arena", "RIVAL", "That's more like it. First batch, remember?"),
	]))
	ask.options = StoryCommand.list([ChoiceOption.make("Rematch!", yes_cmds), ChoiceOption.make("Not now.", [], true)])
	lark2.on_interact = StoryCommand.list([
		IfCommand.make("spar_ready(\"%s\")" % RIVAL_DUEL_ID, [ask], [
			_say([_line("lark_arena", "RIVAL", "Puck needs a nap after that. Go rest at the Wayshrine -- then we go again.")]),
		]),
	])
	out.append(lark2)
	return out


## The barracks' SPARRING ROSTER (rising strength): Corporal Wynn (warm-up), Lieutenant Aldous,
## and the Sergeant himself (see [method _rowan_spar_offer]). Each ready once per rest.
func _spar_partners() -> Array:
	var out: Array = []
	var after: String = "has(\"%s\")" % F_COMPLETE
	var wynn := _npc("wynn", Vector2i(4, 10), "east", "WYNN", ALDERMERE_BLUE.lightened(0.1), "guard")
	wynn.visible_if = after
	wynn.on_interact = StoryCommand.list([_spar_partner_offer(SPAR_WYNN_ID, "wynn", "WYNN", "{WYNN}",
		[{"character_id": "blightcap", "strength": 0.8}],
		"Fancy a warm-up bout? My Blightcap's the gentlest thing in the barracks. Mostly.",
		"Good form! Now go and try the Lieutenant.",
		"Don't sulk -- everyone loses to the Blightcap once. It's the spores.",
		"Blightcap's having a lie-down. Get some rest yourself and come back.")])
	out.append(wynn)
	var aldous := _npc("aldous", Vector2i(6, 7), "south", "ALDOUS", ALDERMERE_BLUE.darkened(0.1), "officer")
	aldous.visible_if = after
	aldous.on_interact = StoryCommand.list([_spar_partner_offer(SPAR_ALDOUS_ID, "aldous", "ALDOUS", "{ALDOUS}",
		[{"character_id": "petalfang", "strength": 0.95}],
		"The Sergeant says you're worth watching. Show me. A friendly bout, no quarter asked.",
		"Hm. He was right. Once more some other day.",
		"Speed. You lack it. Come back when you've found some.",
		"My Petalfang has had enough for today. Rest, and we'll go again.")])
	out.append(aldous)
	out.append(_sign("roster_sign", Vector2i(8, 7), "Sparring Roster",
		"BARRACKS SPARRING ROSTER\nCpl. Wynn -- warm-up bouts.\nLt. Aldous -- for the sharp.\nSgt. Rowan -- ask if you dare.\nOne bout each per rest. Friendly: nobody is hurt for real."))
	return out


## THE CROWN CUP (a [TournamentResource]): four spars, weakest first, back-to-back or one per visit;
## healed before every bout; 100 gold to enter; 400 gold + a Sunleaf Totem and the title the first
## time, 200 gold after. Every round scales +5% per cup already won (up to 4) -- repeat cups get
## harder.
func _build_tournaments() -> void:
	var t := TournamentResource.new()
	t.id = StringName(CUP_ID)
	t.display_name = _t("{CUP}")
	t.description = _t("Four bouts in the sand of {ARENA}, one after another. Friendly -- nobody is hurt for real -- but the crowd only cheers for winners.")
	t.host_name = _t("{ARENA_MASTER}")
	t.host_speaker_id = &"npc_arena_master"
	t.entry_fee = 100
	t.heal_between_bouts = true
	t.prize_gold = 400
	var prize: Array[StringName] = [&"sunleaf_totem"]
	t.first_prize_items = prize
	t.repeat_prize_gold = 200
	t.title = _t("{CUP_TITLE}")
	# [name, speaker, TEAM [[character_id, strength], ...]] -- the ladder grows from one partner to a
	# champion's three (party duels).
	var entrants := [
		["{TAMSIN}", "npc_tamsin", [["mycothrall", 0.9]]],
		["{HARL}", "npc_harl", [["blightcap", 0.95], ["tree_grunt", 0.8]]],
		["{QUENBY}", "npc_quenby", [["petalfang", 1.05], ["undead", 0.85]]],
		["{CHAMPION}", "npc_isolde", [["oakheart", 0.85], ["monster", 0.8], ["blightcap", 0.8]]],
	]
	var rounds: Array[BattleSpec] = []
	for i in range(entrants.size()):
		var e: Array = entrants[i]
		var team: Array = []
		for m in e[2]:
			team.append({"character_id": String(m[0]), "strength": float(m[1])})
		var spec := _duel_spec("", String(e[0]), StringName(String(e[1])), team, true,
			BattleSpec.DefeatPolicy.CONTINUE)
		spec.scale_flag = CUP_WINS_FLAG
		spec.scale_step = 0.05
		spec.scale_max_steps = 4
		rounds.append(spec)
	t.rounds = rounds
	_save(t, TournamentResource.path_for(CUP_ID))


func _arena() -> Array:
	var out: Array = []
	out.append(_prop("arena", "arena", CH_ARENA.position, CH_ARENA.size, Color(0.62, 0.18, 0.16)))
	out.append(_sign("arena_sign", Vector2i(20, 22), "The Crown Arena",
		"{ARENA}\n{CUP}: four bouts, 100 gold to enter.\nFriendly bouts only -- by order of the crown."))
	var master := _npc("arena_master", CH_ARENA_MASTER, "west", "ARENA_MASTER", Color(0.62, 0.18, 0.16), "noble")
	var run := RunTournamentCommand.new()
	run.tournament = load(TournamentResource.path_for(CUP_ID)) as TournamentResource
	master.on_interact = StoryCommand.list([IfCommand.make("has(\"%s\")" % F_COMPLETE, [
		IfCommand.make("has(\"%s\")" % CUP_TITLE_FLAG, [
			_say([_line("arena_master", "ARENA_MASTER", "The {CUP_TITLE} returns! The crowd's been asking after you. Another run?")]),
		], [
			_say([_line("arena_master", "ARENA_MASTER", "Welcome to {ARENA}! {CUP}: four bouts, the best partners in the city. Think yours is ready?")]),
		]),
		run,
	], [
		_say([_line("arena_master", "ARENA_MASTER", "{CUP} is for bonded partners, friend. Come back when you've a creature at your side.")]),
	])])
	out.append(master)

	# The reigning champion stays for REMATCHES once you've taken her title (once per rest), each
	# win over her making the next one harder (+8%, up to 6).
	var champ := _npc("isolde", CH_CHAMPION, "south", "CHAMPION", Color(0.85, 0.7, 0.3), "noble")
	champ.visible_if = "has(\"%s\")" % CUP_TITLE_FLAG
	var spec := _duel_spec(CHAMPION_REMATCH_ID, "{CHAMPION}", &"npc_isolde",
		[{"character_id": "oakheart", "strength": 0.9}, {"character_id": "monster", "strength": 0.85},
			{"character_id": "petalfang", "strength": 0.85}], true, BattleSpec.DefeatPolicy.CONTINUE, 120)
	spec.clash_intro = true
	spec.scale_flag = F_CHAMPION_BEATEN
	spec.scale_step = 0.08
	spec.scale_max_steps = 6
	var ask := ChoiceCommand.new()
	ask.prompt = _line("isolde", "CHAMPION", "You took my title fair and square. I want it back. A champion's rematch?")
	ask.options = StoryCommand.list([
		ChoiceOption.make("Rematch!", [
			_duel(spec),
			IfCommand.make("outcome() == \"victory\"", [
				_inc(F_CHAMPION_BEATEN),
				_say([_line("isolde", "CHAMPION", "Again! My Oakheart will train twice as hard. Next time.")]),
			], [
				IfCommand.make("outcome() == \"defeat\"", [
					_say([_line("isolde", "CHAMPION", "There -- the old champion still has teeth. Come back stronger.")]),
				]),
			]),
		]),
		ChoiceOption.make("Not now.", [], true),
	])
	champ.on_interact = StoryCommand.list([
		IfCommand.make("spar_ready(\"%s\")" % CHAMPION_REMATCH_ID, [ask], [
			_say([_line("isolde", "CHAMPION", "Oakheart's resting. So should you -- the Wayshrine, then back here.")]),
		]),
	])
	out.append(champ)
	return out


# =====================================================================================
#  Woodland Town -- the timber town at the edge of the Sparse Forest / Deep Woods
# =====================================================================================
#
# A rustic forest town, deliberately NOT a village or a castle: no wall, no flagstone plaza -- a
# boardwalk square, log cabins under mossy roofs, a stream with a plank bridge splitting a quiet
# WEST BANK (herbalist, archery range, the sacred glade, the trail to the Hidden Thieves Guild and
# the road on to Deepwood Village) from the busy EAST BANK (the Wardens' Lodge, the Stumped Hart
# inn, Timber Row's trading post and forge, the lumber yard and the sawmill). It sits in a
# clearing: dense woods close in on every side but the roads. Reached from Crownhaven's north gate
# (the east end, entry `east_road`); the west road and the south trail are placeholders for the
# later regions (their warps target this town and never open yet).

const WT_W := 28
const WT_H := 24
const WT_ROAD_Y := 12
const WT_STREAM_X := 7
const WT_LODGE := Rect2i(10, 6, 6, 3)
const WT_INN := Rect2i(18, 8, 4, 3)
const WT_POST := Rect2i(22, 9, 3, 2)
const WT_SMITHY := Rect2i(25, 9, 2, 2)
const WT_SAWMILL := Rect2i(23, 15, 4, 3)
const WT_HOMES := [Rect2i(10, 16, 3, 2), Rect2i(14, 16, 3, 2)]
const WT_HERB := Rect2i(3, 9, 3, 2)
const WT_HUNT := Rect2i(3, 5, 3, 2)
const WT_PLAZA := Rect2i(10, 11, 7, 4)
const WT_SHRINE := Vector2i(13, 13)
const WT_YARD := Rect2i(17, 14, 10, 7)
const WT_CAMP := Rect2i(11, 18, 5, 3)
const WT_GLADE := Rect2i(2, 17, 4, 3)
const WT_GARDEN := Rect2i(3, 14, 3, 2)
## Hand-placed trees inside the clearing (the rest is the forest around it).
const WT_TREES := [Vector2i(9, 4), Vector2i(8, 8), Vector2i(17, 5), Vector2i(9, 20), Vector2i(8, 15),
	Vector2i(9, 13), Vector2i(20, 5), Vector2i(2, 3), Vector2i(2, 7), Vector2i(21, 21), Vector2i(10, 21)]


func _wt_buildings() -> Array:
	return [WT_LODGE, WT_INN, WT_POST, WT_SMITHY, WT_SAWMILL, WT_HERB, WT_HUNT] + WT_HOMES


func _wt_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	# The roads out: east to Crownhaven, west toward Deepwood Village, and the south trail.
	if x == 0 or x == WT_W - 1:
		return "forest_dirt" if y == WT_ROAD_Y else "tree"
	if y <= 1 or y >= WT_H - 2:
		return "forest_dirt" if (x == 4 and y >= WT_H - 2) else "tree"
	if x == WT_STREAM_X and y >= 2 and y <= WT_H - 3:
		return "wooden_planks" if y == WT_ROAD_Y else "deep_water"
	if _in(_wt_buildings(), c):
		return "stone_wall"
	if c == WT_SHRINE:
		return "sacred_ground"
	# The boardwalk square and the Lodge's path onto it.
	if WT_PLAZA.has_point(c) or (x >= 12 and x <= 13 and y >= 9 and y <= 10):
		return "wooden_planks"
	if WT_GLADE.has_point(c):
		return "sacred_meadow"
	if c in WT_TREES:
		return "tree"
	# The high road (Timber Street) and the front lane of Timber Row.
	if y == WT_ROAD_Y or (y == 11 and x >= 17 and x <= WT_W - 2):
		return "forest_dirt"
	# The lumber yard, the camp, the herb garden, and the lanes.
	if WT_YARD.has_point(c) or WT_CAMP.has_point(c) or WT_GARDEN.has_point(c):
		return "forest_dirt"
	if (x == 13 and y >= 15 and y <= 18) or (x == 6 and y >= 7 and y <= 19) or (y == 7 and x >= 4 and x <= 6) \
			or (x == 4 and y == 11) or (x == 4 and y >= 20):
		return "forest_dirt"
	# The forest closes in beyond the clearing, thickest to the west (the Deep Woods).
	var dx: float = (float(x) - 14.0) / 13.0
	var dy: float = (float(y) - 12.0) / 10.0
	if dx * dx + dy * dy > 1.0:
		return "tree" if _h(x, y, 21) < (0.9 if x < 8 else 0.75) else "grass_plains"
	if _h(x, y, 22) < 0.1 and absi(y - WT_ROAD_Y) > 1 and (x < 8 or x > 20):
		return "tall_grass"
	return "grass_plains"


func _build_woodland_town() -> void:
	var t := _new_map("Woodland Town", WT_W, WT_H,
		"Woodland Town: a timber town in a clearing at the edge of the Sparse Forest -- log cabins, a lumber yard, a stream with a plank bridge. Story-mode terrain.")
	t.lighting_preset = "Dawn"
	_paint(t, _wt_terrain)
	_add_validator_anchors(t, Vector2i(26, WT_ROAD_Y), Vector2i(13, 14))
	_save(t, CONTENT + "areas/woodland_town/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"woodland_town"
	a.display_name = "Woodland Town"
	a.kind = OverworldAreaResource.Kind.TOWN
	a.world_map_pos = Vector2(0.3, 0.38)
	a.terrain = load(CONTENT + "areas/woodland_town/terrain.tres")
	a.entry_points = {
		"east_road": {"cell": [WT_W - 2, WT_ROAD_Y, 0], "facing": "west"},
		"wayshrine": {"cell": [WT_SHRINE.x, WT_SHRINE.y + 1, 0], "facing": "north"},
		"west_road": {"cell": [1, WT_ROAD_Y, 0], "facing": "east"},
	}
	var ents: Array = []
	ents.append_array(_wt_scenery())
	ents.append(_shrine(WT_SHRINE, "Woodland Wayshrine"))
	ents.append_array(_wt_people())
	# Roads: east to Crownhaven; west (Deepwood Village) and the south trail (the Hidden Thieves
	# Guild) are the next chapters -- their warps target this town and never open yet.
	ents.append(_warp("east_exit", Rect2i(WT_W - 1, WT_ROAD_Y, 1, 1), &"crownhaven", &"north_gate"))
	ents.append(_warp("west_exit", Rect2i(0, WT_ROAD_Y, 1, 1), &"woodland_town", &"west_road", "",
		"has(\"world.deepwood_open\")", _scene("wt_west_locked", [
			_narr("The road west thins to a deer track and then to nothing. Somewhere beyond the thorns lies Deepwood Village -- but the Wardens have strung a rope across the track with a painted warning: \"No travellers. Ask at the Lodge.\""),
		])))
	ents.append(_warp("south_exit", Rect2i(4, WT_H - 1, 1, 1), &"woodland_town", &"wayshrine", "",
		"has(\"world.thieves_guild_open\")", _scene("wt_south_locked", [
			_narr("A narrow trail slips south between the roots, toward a cave mouth nobody here admits to knowing. Fresh boot prints say the way is kept open from the other end. A rockfall blocks it for now."),
		])))
	a.entities = _entities(ents)
	a.on_enter = StoryCommand.list([
		IfCommand.make("not has(\"woodland.arrived\")", [
			_say([
				_narr("Woodland Town. The air smells of pine resin and woodsmoke, and somewhere a saw sings through green timber. Lanterns still burn in the cabin windows against the morning mist."),
				_narr("The Wardens' Lodge stands at the heart of the town, north of the boardwalk square. The lumber yard is east, past the inn; the old trail south runs toward the Hidden Thieves Guild."),
			]),
			_flag("woodland.arrived"),
		]),
	])
	_save(a, CONTENT + "areas/woodland_town/area.tres")


func _wt_scenery() -> Array:
	var out: Array = []
	var moss := Color(0.3, 0.42, 0.24)
	var bark := Color(0.42, 0.32, 0.2)
	out.append(_prop("wardens_lodge", "cabin", WT_LODGE.position, WT_LODGE.size, Color(0.24, 0.4, 0.26)))
	out.append(_prop("stumped_hart", "cabin", WT_INN.position, WT_INN.size, Color(0.5, 0.3, 0.2)))
	out.append(_prop("trading_post", "cabin", WT_POST.position, WT_POST.size, Color(0.36, 0.36, 0.24)))
	out.append(_prop("forge", "smithy", WT_SMITHY.position, WT_SMITHY.size, Color(0.3, 0.26, 0.24)))
	out.append(_prop("sawmill", "cabin", WT_SAWMILL.position, WT_SAWMILL.size, bark))
	out.append(_prop("herb_hut", "cabin", WT_HERB.position, WT_HERB.size, Color(0.3, 0.5, 0.3)))
	out.append(_prop("hunters_lodge", "cabin", WT_HUNT.position, WT_HUNT.size, Color(0.4, 0.34, 0.2)))
	for i in range(WT_HOMES.size()):
		var r: Rect2i = WT_HOMES[i]
		out.append(_prop("cabin_%d" % i, "cabin", r.position, r.size, [moss, Color(0.4, 0.34, 0.24)][i % 2]))
	# The lumber yard: stacked logs, a hand cart, barrels.
	out.append(_prop("logs_a", "logs", Vector2i(17, 15), Vector2i(3, 1), Color(0.62, 0.45, 0.26), true))
	out.append(_prop("logs_b", "logs", Vector2i(17, 17), Vector2i(3, 1), Color(0.56, 0.4, 0.24), true))
	out.append(_prop("logs_c", "logs", Vector2i(20, 19), Vector2i(3, 1), Color(0.66, 0.5, 0.3), true))
	out.append(_prop("logs_d", "logs", Vector2i(21, 15), Vector2i(2, 1), Color(0.6, 0.44, 0.26), true))
	out.append(_prop("timber_cart", "cart", Vector2i(21, 17), Vector2i.ONE, Color(0.55, 0.4, 0.22), true))
	out.append(_prop("yard_barrels", "barrels", Vector2i(22, 18), Vector2i.ONE, Color.WHITE, true))
	# The herb garden, the archery range, the camp fire.
	out.append(_prop("herb_garden", "crops", WT_GARDEN.position, WT_GARDEN.size, Color(0.28, 0.5, 0.34)))
	out.append(_prop("garden_fence", "fence", Vector2i(3, 16), Vector2i(3, 1), Color(0.45, 0.33, 0.2), true))
	out.append(_prop("target_a", "dummy", Vector2i(3, 8), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("target_b", "dummy", Vector2i(5, 8), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("campfire", "fire", Vector2i(13, 19), Vector2i.ONE, Color.WHITE, true))
	# The square: lamps at its corners, the Wardens' green banners at the Lodge path, a well.
	for lc in [Vector2i(10, 11), Vector2i(16, 11), Vector2i(10, 14), Vector2i(16, 14), Vector2i(8, 11), Vector2i(8, 13)]:
		out.append(_prop("lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.78, 0.4), true))
	out.append(_prop("banner_w", "banner", Vector2i(11, 9), Vector2i.ONE, Color(0.24, 0.44, 0.28), true))
	out.append(_prop("banner_e", "banner", Vector2i(14, 9), Vector2i.ONE, Color(0.24, 0.44, 0.28), true))
	out.append(_prop("well", "well", Vector2i(15, 10), Vector2i.ONE, Color(0.3, 0.38, 0.22), true))
	out.append(_prop("woodpile_inn", "logs", Vector2i(17, 8), Vector2i.ONE, Color(0.58, 0.42, 0.24), true))
	return out


func _wt_people() -> Array:
	var out: Array = []
	var cloak_green := Color(0.28, 0.44, 0.3)
	# --- Signs ---------------------------------------------------------------------------------
	out.append(_sign("town_sign", Vector2i(WT_W - 2, WT_ROAD_Y + 1), "Woodland Town",
		"WOODLAND TOWN\nTimber, tolls and tall tales. East: Crownhaven.  West: Deepwood Village (road closed)."))
	out.append(_sign("lodge_sign", Vector2i(10, 9), "The Wardens' Lodge",
		"THE WARDENS' LODGE\nTolls, maps, and the loan of a lantern. Ask for Warden Hale."))
	out.append(_sign("inn_sign", Vector2i(17, 10), "The Stumped Hart",
		"THE STUMPED HART\nA stump for a stool, a stag for a sign. Venison pie daily."))
	out.append(_sign("yard_sign", Vector2i(18, 13), "Lumber Yard",
		"HAMMOND & DAUGHTERS -- LUMBER\nCut green, sold dry.\nDo not lean on the stacks."))
	out.append(_sign("deepwood_sign", Vector2i(2, WT_ROAD_Y + 1), "To Deepwood",
		"WEST: DEEPWOOD VILLAGE\nThe road is closed by the Wardens. Ask at the Lodge."))
	out.append(_sign("trail_sign", Vector2i(5, 19), "The South Trail",
		"A hand-lettered board nailed to a root:\n\"NOT A ROAD. Not a trail. Not your business.\""))
	out.append(_sign("standing_stone", Vector2i(3, 17), "The Starfall Stone",
		"A knee-high stone, furred with moss and scored with old marks. Fresh flowers lie before it. It hums very faintly, like a held note.", "stone"))

	# --- East bank: the Lodge, the inn, Timber Row, the lumber yard --------------------------
	var hale := _npc("hale", Vector2i(12, 9), "south", "HALE", cloak_green, "officer")
	hale.on_interact = StoryCommand.list([_say([
		_line("hale", "HALE", "Welcome to Woodland Town. The Wardens keep the roads, the tolls and the peace between the town and the trees -- in about that order of difficulty."),
		_line("hale", "HALE", "Deepwood's road is shut. The wood's been restless, and a restless wood eats carts. If you want to go west, bring me a reason I can write down."),
		_line("hale", "HALE", "And if you meet a lantern in the dark that nobody's holding -- go the other way."),
	])])
	out.append(hale)
	var bryn := _npc("bryn", Vector2i(19, 11), "south", "BRYN", Color(0.6, 0.38, 0.28), "villager")
	bryn.on_interact = StoryCommand.list([_say([
		_line("bryn", "BRYN", "Venison pie, hot cider, and a room with a window onto the pines. The Stumped Hart's never let a traveller go hungry."),
		_line("bryn", "BRYN", "Odd crowd lately. Folk with no luggage and a lot of questions about the south trail. I tell them it's a trail to nowhere."),
	])])
	out.append(bryn)
	var sedge := _merchant("sedge", Vector2i(23, 11), "south", "SEDGE", Color(0.4, 0.34, 0.2), SHOP_WOODLAND)
	sedge.dialogue = _scene("wt_sedge", [_line("sedge", "SEDGE", "Furs, flasks and forest remedies, friend. Have a look.")])
	out.append(sedge)
	var burr := _npc("burr", Vector2i(26, 11), "west", "BURR", Color(0.36, 0.28, 0.24), "trainer")
	burr.on_interact = StoryCommand.list([_say([
		_line("burr", "BURR", "Axe heads, saw teeth, nails by the barrel. The Guard's smiths in the city make swords. I make the things that actually feed people."),
	])])
	out.append(burr)
	var torvald := _npc("torvald", Vector2i(19, 16), "east", "TORVALD", Color(0.5, 0.3, 0.2), "trainer")
	torvald.on_interact = StoryCommand.list([_say([
		_line("torvald", "TORVALD", "Every plank in the capital's keep started life on this yard. Mind the stacks -- they have opinions about strangers."),
		_line("torvald", "TORVALD", "We only fell what's marked. The Wardens paint a ring on the trunk, and I don't argue with a ring."),
	])])
	out.append(torvald)
	var road_warden := _npc("road_warden", Vector2i(WT_W - 3, WT_ROAD_Y + 1), "north", "ROAD_WARDEN", cloak_green, "guard")
	road_warden.dialogue = _scene("wt_road_warden", [
		_beat(&"self", "Road Warden", "East road's clear to the city. If anyone asks, I wasn't smiling."),
	])
	out.append(road_warden)
	var fern := _npc("fern", Vector2i(11, 13), "south", "FERN", Color(0.5, 0.6, 0.35), "child")
	fern.on_interact = StoryCommand.list([_say([
		_line("fern", "FERN", "I counted forty-one lanterns last night and only forty windows. Nobody believes me."),
	])])
	out.append(fern)

	# --- West bank: the herbalist, the archery range, the glade ----------------------------------
	var ilse := _npc("ilse", Vector2i(4, 11), "south", "ILSE", Color(0.34, 0.52, 0.4), "scholar")
	ilse.on_interact = StoryCommand.list([_say([
		_line("ilse", "ILSE", "Bitterroot for stings, mossleaf for scrapes, and something I'm not allowed to call a cure for anything at all. Don't tell the Wardens."),
		_line("ilse", "ILSE", "The woods are older than the kingdom, you know. Things sleep in the roots out there. Nobody here says so aloud."),
	])])
	out.append(ilse)
	var ferra := _npc("ferra", Vector2i(4, 7), "south", "FERRA", Color(0.34, 0.42, 0.26), "trainer")
	ferra.on_interact = StoryCommand.list([_say([
		_line("ferra", "FERRA", "Three arrows, three straw men, and one of them is still standing. Don't ask which. The range is open to anyone who can keep from shooting the pigeons."),
	])])
	out.append(ferra)
	var wicke := _npc("wicke", Vector2i(3, 18), "east", "WICKE", Color(0.7, 0.68, 0.74), "elder")
	wicke.on_interact = StoryCommand.list([_say([
		_line("wicke", "WICKE", "When I was a girl this stone was taller. Or I was shorter. The glade keeps its own counsel."),
		_line("wicke", "WICKE", "If you're ever lost in the woods, set your hand on a stone and listen. The star remembers the way home."),
	])])
	out.append(wicke)

	# --- The camp on the south lane ------------------------------------------------------------
	var stranger := _npc("stranger", Vector2i(12, 19), "east", "STRANGER", Color(0.2, 0.18, 0.22), "raider")
	stranger.on_interact = StoryCommand.list([_say([
		_line("stranger", "STRANGER", "Warm fire, warm night. You've the look of someone who counts doors and exits, traveller. Good habit."),
		_line("stranger", "STRANGER", "Some doors in this wood are only doors if you know the knock. I'd tell you the knock, but I don't know it. Obviously."),
	])])
	out.append(stranger)

	# --- A woodcutter's chest at the back of the yard ------------------------------------------
	var chest := ChestEntity.new()
	chest.id = &"yard_chest"
	chest.cell = Vector3i(25, 19, 0)
	chest.facing = "west"
	chest.display_name = "Chest"
	chest.tint = Color(0.46, 0.32, 0.18)
	var loot: Array[StringName] = [&"mossleaf_tonic", &"bitterroot_salve"]
	chest.loot_items = loot
	chest.loot_gold = 40
	out.append(chest)
	return out
