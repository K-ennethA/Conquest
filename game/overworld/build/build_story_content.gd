extends SceneTree

## Generates the STORY MODE content -- the story OPENING (docs/design/DECISIONS.md #12-#21) and
## the Mossway route that joins its two towns:
##
##   game/overworld/content/areas/oakvale/         -- the hero's HOME village, before the raid
##   game/overworld/content/areas/oakvale_ruins/   -- the same village after the raid (burned)
##   game/overworld/content/areas/mossway/         -- Route 1, Oakvale <-> River Crossing
##   game/overworld/content/areas/river_crossing/  -- the Old Bridge's toll village, north to the capital
##   game/overworld/content/areas/crownhaven/      -- the walled river city (the shard ceremony)
##   game/overworld/content/areas/sparse_forest/   -- the road west from Crownhaven to Woodland Town
##   game/overworld/content/areas/woodland_town/   -- the timber town at the edge of the Deep Woods
##   game/overworld/content/areas/deepwood_village/    -- THE DEEP WOODS: Nyra's clan village
##   game/overworld/content/areas/depths_of_the_wood/  -- the forest north of it and Eldroot's glade
##   game/overworld/content/world.tres                       -- the WORLD MAP registry (WorldAtlas)
##   game/overworld/content/battles/ow_oakvale_ashes.tres    -- the FIRST FIGHT (tactical)
##   game/overworld/content/battles/ow_deepwood_glade.tres   -- Eldroot's legend battle (tactical)
##   game/overworld/content/field_moves/*.tres               -- FIELD MOVES (DECISIONS.md #41 / #71)
##   game/overworld/content/battles/ow_mossway_clearing.tres -- Bram's board (post-opening)
##   game/overworld/content/hero.tres                        -- the avatar (placeholder model)
##   game/overworld/content/story_ruleset.tres               -- story tuning
##   game/overworld/content/shops/*.tres                     -- the merchants' shops (DECISIONS.md #28)
##   game/overworld/content/tournaments/*.tres               -- the Crown Arena's cup (DECISIONS.md #33)
##
## Run with (the runner loads this file once the autoloads exist -- run directly with -s, its typed
## dependencies reach autoload names the analyzer does not know yet and it fails to compile):
##   godot --headless --path . -s res://game/overworld/build/run_builder.gd
##
## Terrain is ordinary MapResource data (the Map Maker can open and repaint it); everything
## story -- NPCs, signs, props, warps, the Wayshrines, dialogue, the opening's scripts -- is the
## OverworldAreaResource beside it. Nothing here lives under game/maps/resources/, so no picker
## (Skirmish, Siege, network, Map Gallery) ever lists it; every map is also status Inactive.
##
## AMBIENT NPC TALK IS NOT HERE: what townsfolk say (and how it changes with the story and with
## time) lives in game/overworld/content/dialogue.json -- the DialogueBank, edited with the
## Dialogue editor (addons/dialogue_editor) and read at runtime, so editing it needs no rebuild.
## An NPC here is just its place, look and SCRIPTED behaviour (cutscenes, offers, shops, battles);
## a bank entry keyed by the area id + the NPC id gives it its lines.
##
## THE OPENING, as built here (flags in the F_* constants):
##   1. Oakvale (home): a new journey starts at your door; your mother sends you to Crownhaven,
##      where Professor Elias -- the Royal Researcher, an old friend of your mother's -- has asked
##      to see you ......................................................... opening.sent_off
##   2. The Mossway (east) and River Crossing (north over the Old Bridge): wild creatures leave a
##      traveller with no partner alone (no encounters, trainers let you pass -- OverworldController);
##      Bram and the Lone Petalfang only appear once the opening is over .... (opening.complete)
##   3. Crownhaven (in by the south gate): Professor Elias waits INSIDE the Royal Workshop (an
##      interior, see INTERIORS); he explains his new invention (the stones let a person bond with
##      a creature), the stone is yours and you CHOOSE a starter from STARTER_OPTIONS (placeholders)
##      ......................... opening.starter_received, opening.starter_pick, key.bonding_shard
##   4. The kidnapping (INSIDE the Royal Workshop, right after the starter is chosen): placeholder
##      enemy soldiers appear in the room and take Elias; enemies are attacking the city at the same
##      time as a distraction, and the raiders run to escape (and burn Oakvale). The hero is then
##      free -- nothing warps him anywhere; the Mossway's west end leads to the burned village
##      ............................. opening.attack, opening.researcher_taken, opening.raiders_fled, opening.chase
##   5. Oakvale in ashes (a second area, swapped in by the Mossway's flag-gated west warps): the
##      General and the Warrior (PLACEHOLDERS) say what happened and ask you to fight; "Not yet."
##      lets you explore first ...................................... opening.allies_met, opening.ruins_seen
##   6. The FIRST FIGHT: a tactical battle on ow_oakvale_ashes vs enemy soldiers and their creatures,
##      the General and the Warrior fighting beside your starter as guests ... opening.first_fight_won
##   7. Aftermath: they task you with getting stronger, while they prepare for war; then the whole
##      region is open ............................ opening.complete (+ legacy act1.find_rowan)
##
## NO INTERRUPTIONS: arriving somewhere never plays a scene -- the HUD's location popup
## (PlaceAnnouncer) names a new place and the hero keeps walking; ambient NPC talk speaks only when
## spoken to; the rival is an opt-in bout. Cutscenes are kept to the lines needed to follow them.
##
## DUELS IN STORY (DECISIONS.md #31 / #33 -- the section at the end of this file): a duel trainer
## (Tester Fenna, the Mossway), the friendly rival (Lyra: rival.*), the barracks' sparring roster (a cooldown
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
	# PROFESSOR ELIAS (owner): the Royal Researcher (magic / history / science), 60+, he/him, wise,
	# calm, intelligent, wears glasses; a longtime friend of the hero's MOTHER and a family friend.
	# Reference sheet: docs/design/characters/professor_elias.webp. Anything else about him is TBD.
	"RESEARCHER": "Elias",
	"RESEARCHER_TITLE": "Professor Elias",
	"ASSISTANT": "Tam",
	# TODO(story): PLACEHOLDER allies who meet the hero in burned Oakvale and fight beside the hero in the
	# first fight (owner: "the general and another warrior"). Names, looks and roles are TBD -- rename
	# them here, in one place. Owner, 2026-10-04: the General is "General Varden" (placeholder name;
	# he is also the barracks' sparring partner -- there is no separate Sergeant Rowan any more) and
	# the Warrior is "Talyn", female (she/her), also a placeholder name.
	"GENERAL": "General Varden",
	"WARRIOR": "Talyn",
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
	# DECISIONS.md #51/#52/#60/#61: the two fellow shard TESTERS at the ceremony -- the main friendly
	# rivals and allies (temporary joins; they join for the final battles).
	"LYRA": "Lyra",                         # owner: rival + ally, Professor Elias' student (docs/design/characters/lyra.webp)
	"CAEL": "Cael",                         # owner: friend + ally, Professor Elias' student (docs/design/characters/cael.webp)
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
	# --- The world map's roads (River Crossing, the Sparse Forest) ---
	"TOLLKEEPER": "Toll-keeper Hobb",       # River Crossing: the Old Bridge's keeper
	"FISHER": "Fisher Nan",                 # River Crossing: the south bank
	"CARTER": "Carter Joss",                # River Crossing: stuck on the coast road
	"WOODSMAN": "Woodsman Alder",           # the Sparse Forest
	# --- The Deep Woods (DECISIONS.md #40 / #85 / #88) ---
	"NYRA": "Nyra",                         # owner: the Deepwood chief (docs/design/characters/nyra.webp)
	# Generic villagers (no named cast -- one short placeholder line each in dialogue.json).
	"DEEPWOOD_ELDER": "Deepwood Elder",
	"DEEPWOOD_HUNTER": "Deepwood Hunter",
	"DEEPWOOD_CHILD": "Deepwood Child",
	# TODO(story): PLACEHOLDER name of the tree-felling field move Nyra teaches (DECISIONS.md #40/#41).
	"FIELD_MOVE_TREES": "Treefell",
}

# =====================================================================================
#  THE WORLD MAP (the owner's map: docs/design/world_map/world_map.webp) -- the ONE place for geography
# =====================================================================================
#
# Every named place, built or not. Positions are normalised (x right, y down) on the map image;
# each built area's OverworldAreaResource.world_map_pos / region_id come from here. A CLOSED place
# has no area yet: the road toward it is a flag-gated warp that answers with a short scene, and
# `open` names the flag a later chapter sets. Generated into content/world.tres (WorldAtlas).

const WORLD_NAME := "Aldermere and its neighbours"
const WORLD_REGIONS := {
	"heartlands": "The Heartlands",
	"woodlands": "The Deep Woods",
	"snowy_peaks": "The Snowy Peaks",
	"northern_mountains": "The Northern Mountains",
	"rocky_badlands": "The Rocky Badlands",
	"sunlit_coast": "The Sunlit Coast",
	"open_ocean": "The Open Ocean",
	"cindral": "Cindral",
}
## [id, display name, kind, region, map_pos, area ids (built) | [], open flag (closed), secret, description]
const WORLD_LOCATIONS := [
	["oakvale", "Oakvale", "village", "heartlands", Vector2(0.426, 0.630), ["oakvale", "oakvale_ruins"], "", false,
		"The Starting Village: farmland above the southern coast. The hero's home."],
	["farm_hamlet", "Farm Hamlet", "village", "heartlands", Vector2(0.300, 0.674), [], "world.farm_hamlet_open", false,
		"A barley hamlet west of Oakvale, down the mill lane."],
	["mossway", "The Mossway", "route", "heartlands", Vector2(0.485, 0.645), ["mossway"], "", false,
		"Route 1: the mossy road east from Oakvale to River Crossing."],
	["river_crossing", "River Crossing", "village", "heartlands", Vector2(0.544, 0.655), ["river_crossing"], "", false,
		"A toll village at the Old Bridge, where the road north to the capital crosses the river."],
	["crownhaven", "Crownhaven", "city", "heartlands", Vector2(0.498, 0.410), ["crownhaven"], "", false,
		"The Central Kingdom's walled river city, royal seat of Aldermere."],
	["sparse_forest", "The Sparse Forest", "route", "woodlands", Vector2(0.400, 0.400), ["sparse_forest"], "", false,
		"Open woodland between Crownhaven's west gate and Woodland Town."],
	["woodland_town", "Woodland Town", "town", "woodlands", Vector2(0.301, 0.384), ["woodland_town"], "", false,
		"A timber town in a forest clearing at the edge of the Deep Woods."],
	["thieves_guild", "Hidden Thieves Guild", "dungeon", "woodlands", Vector2(0.275, 0.478), [], "world.thieves_guild_open", true,
		"A cave below Woodland Town that nobody admits to knowing."],
	["deepwood_village", "Deepwood Village", "village", "woodlands", Vector2(0.098, 0.474), ["deepwood_village"], "world.deepwood_open", false,
		"A village deep in the old forest, west of Woodland Town."],
	["depths_of_the_wood", "Depths of the Wood", "special", "woodlands", Vector2(0.114, 0.337), ["depths_of_the_wood"], "world.depths_of_the_wood_open", false,
		"A glowing glade at the forest's heart. A special encounter."],
	["frostpeak_village", "Frostpeak Village", "village", "snowy_peaks", Vector2(0.231, 0.166), [], "world.frostpeak_open", false,
		"A village under the Snowy Peaks, up the north trail from Woodland Town."],
	["mountain_base", "Mountain Base", "town", "northern_mountains", Vector2(0.693, 0.188), [], "world.mountain_road_open", false,
		"The fortified town at the foot of the mountains, up the road from Crownhaven's north gate."],
	["mountain_pass", "Mountain Pass", "route", "northern_mountains", Vector2(0.668, 0.080), [], "world.mountain_pass_open", false,
		"The high pass over the mountains toward Cindral."],
	["hidden_depths", "Hidden Depths", "special", "northern_mountains", Vector2(0.850, 0.137), [], "world.hidden_depths_open", false,
		"A crystal cave in the eastern mountains. A special encounter."],
	["cindral", "Cindral", "nation", "cindral", Vector2(0.761, 0.045), [], "world.cindral_open", false,
		"The Other Nation, beyond the Mountain Pass."],
	["redrock_village", "Redrock Village", "village", "rocky_badlands", Vector2(0.856, 0.410), [], "world.badlands_open", false,
		"A village among the red mesas, down the road from Crownhaven's east gate."],
	["beach_village", "Beach Village", "village", "sunlit_coast", Vector2(0.678, 0.685), [], "world.beach_road_open", false,
		"A harbour village on stilts, south-east of the capital: the port for the isles."],
	["sunrise_isle", "Sunrise Isle", "island", "open_ocean", Vector2(0.910, 0.615), [], "world.sea_routes_open", false,
		"An island to the east, a short sail from Beach Village."],
	["island_of_tides", "Island of Tides", "special", "open_ocean", Vector2(0.850, 0.810), [], "world.sea_routes_open", false,
		"A storm-wrapped island far out to sea. A special encounter."],
	["stormreef_isle", "Stormreef Isle", "island", "open_ocean", Vector2(0.608, 0.915), [], "world.sea_routes_open", false,
		"A reef island south of Beach Village."],
]
## [a, b, kind] -- the map's roads ("main" gold road, "secondary" dashed track, "sea" route).
const WORLD_ROADS := [
	["oakvale", "mossway", "main"],
	["mossway", "river_crossing", "main"],
	["river_crossing", "crownhaven", "main"],
	["crownhaven", "sparse_forest", "main"],
	["sparse_forest", "woodland_town", "main"],
	["crownhaven", "mountain_base", "main"],
	["mountain_base", "mountain_pass", "main"],
	["mountain_pass", "cindral", "main"],
	["crownhaven", "redrock_village", "main"],
	["crownhaven", "beach_village", "main"],
	["river_crossing", "beach_village", "main"],
	["oakvale", "farm_hamlet", "secondary"],
	["woodland_town", "deepwood_village", "secondary"],
	["woodland_town", "thieves_guild", "secondary"],
	["woodland_town", "frostpeak_village", "secondary"],
	["deepwood_village", "depths_of_the_wood", "secondary"],
	["mountain_base", "hidden_depths", "secondary"],
	["beach_village", "sunrise_isle", "sea"],
	["beach_village", "island_of_tides", "sea"],
	["beach_village", "stormreef_isle", "sea"],
]

## Shop ids (the save keys of their stock -- never rename once shipped; the NAMES above are free).
const SHOP_CROWNHAVEN := "crownhaven_general"
const SHOP_PEDLAR := "mossway_pedlar"
const SHOP_WOODLAND := "woodland_trader"

## The STARTER creature (a CharacterLibrary id): the DEFAULT of the ceremony's choice -- the first
## option, the one tests and a no-host run pick -- and the placeholder in the first fight's squad
## chairs. Keep it equal to STARTER_OPTIONS[0].character_id.
const STARTER_ID := &"tree_grunt"
const STARTER_NICKNAME := ""
## THE STARTER CHOICE (owner: the hero chooses a starter; the roster is TBD). ONE list of N options,
## each {character_id, label}; the ceremony offers whatever is here (1 option = no question asked,
## 2+ = a choice, the first being the default). The pick is recorded as the int flag F_STARTER_PICK
## (1-based index into this list). Edit the list and rebuild.
## PLACEHOLDERS: existing roster units standing in until the real starters are decided.
const STARTER_OPTIONS: Array[Dictionary] = [
	{"character_id": STARTER_ID, "label": "Barkling", "placeholder": true},
	{"character_id": &"petalfang", "label": "Petalfang", "placeholder": true},
	{"character_id": &"blightcap", "label": "Blightcap", "placeholder": true},
]
## The General and the Warrior in the first fight: guests beside the hero and your starter as
## player-0 turn-1 Reinforcements. General Varden is a HUMAN battle unit (docs/design/HUMANS.md) and
## fights as HIMSELF; TODO(story): Talyn (the Warrior) has no model / roster entry yet -- the
## "warrior grown rather than armed" stands in for her.
## The owner's character MODELS for people (roster entries also used for their look on the overworld):
## General Varden and Professor Elias.
const VARDEN_MODEL := &"varden"
const ELIAS_MODEL := &"elias"
const GENERAL_UNIT := "varden"
const WARRIOR_UNIT := "vineweave"
## PLACEHOLDER enemy units for the first fight (existing roster units): the soldiers first, then
## their creatures. In map-spawn order (see [method _build_first_fight_map]).
const RAIDER_UNITS: Array[String] = ["undead", "undead", "blightcap", "monster"]
## PLACEHOLDER creatures beside the fellow testers at the ceremony (DECISIONS.md #52): existing
## roster units, purely visual. [tester entity id, cell, its creature's entity id, cell, character_id]
const CEREMONY_TESTERS: Array = [
	["lyra", Vector2i(2, 4), "lyra_creature", Vector2i(3, 4), "gem_knight"],
	["cael", Vector2i(2, 5), "cael_creature", Vector2i(3, 5), "mycothrall"],
]
## The hero's placeholder overworld model (DECISIONS.md #4): swap the model here.
const HERO_MODEL := "res://game/characters/models/forest/wren_forge.glb"

# --- Story levels (docs/design/PROGRESSION.md §3; DECISIONS.md #76, #80, #81) ------------
## REGIONAL LEVEL BANDS: every area of a region gets its region's band ([method _place]); wild
## creatures roll inside it (a zone may narrow it), a SCALED chief clamps into it, a LEGEND is authored
## above it. Regions not listed have no band yet (no area built there).
const REGION_BANDS := {
	"heartlands": Vector2i(2, 8),
	"woodlands": Vector2i(8, 15),
	"sunlit_coast": Vector2i(12, 20),
	"open_ocean": Vector2i(12, 20),
	"snowy_peaks": Vector2i(18, 26),
	"rocky_badlands": Vector2i(22, 30),
	"northern_mountains": Vector2i(25, 35),
}
## The Mossway's grass is the first route: its creatures stay at the bottom of the Heartlands band.
const BAND_MOSSWAY_GRASS := Vector2i(2, 5)
## AUTHORED BATTLE LEVELS (FIXED). The starter joins at ProgressionRules.starter_level (5).
const LV_FIRST_FIGHT := 4
const LV_LONE_PETALFANG := 4
const LV_BRAM := 5
const LV_FENNA := 6
const LV_FOOTPAD := 7
const LV_BANDIT_BOSS := 8
const LV_RIVAL := 7
const LV_SPAR_WYNN := 5
const LV_SPAR_ALDOUS := 7
const LV_SPAR_GENERAL := 10
## The Crown Cup ladder, round by round (rising), and the champion's rematch.
const LV_CUP_ROUNDS: Array[int] = [6, 7, 8, 10]
const LV_CHAMPION_REMATCH := 12

## Tints (the raiders' Cindral colours, the kingdom's blue).
const CINDRAL_RED := Color(0.62, 0.16, 0.12)
const ALDERMERE_BLUE := Color(0.2, 0.28, 0.5)

# --- Story flags ------------------------------------------------------------------
const F_SENT_OFF := "opening.sent_off"
const F_ARRIVED := "opening.arrived_crownhaven"
const F_CEREMONY := "opening.ceremony"
const F_STARTER := "opening.starter_received"
## WHICH starter you chose (1-based index into STARTER_OPTIONS).
const F_STARTER_PICK := "opening.starter_pick"
const F_SHARD := "key.bonding_shard"
const F_ATTACK := "opening.attack"
const F_TAKEN := "opening.researcher_taken"
const F_FLED := "opening.raiders_fled"
const F_CHASE := "opening.chase"
## The General and the Warrior have been met in the ruins (the arrival scene ran).
const F_ALLIES_MET := "opening.allies_met"
const F_RUINS_SEEN := "opening.ruins_seen"
const F_FIGHT_WON := "opening.first_fight_won"
const F_COMPLETE := "opening.complete"
## LEGACY KEYS: "rowan" is a former character name (merged into General Varden). The flag and spar
## ids below are persisted in saves and replays, so they keep their old spelling -- never rename.
const F_ACT1 := "act1.find_rowan"
## The hero has talked to the General at the Crownhaven barracks after the opening (legacy key).
const F_ACT1_MET := "act1.met_rowan"
const FIRST_FIGHT_ID := "story.opening.first_fight"
## The example friendly SPAR (the General's Geode, Crownhaven, after the opening). Legacy id.
const SPAR_GENERAL_ID := "crownhaven.spar.rowan"

# --- Duels in story (DECISIONS.md #33): ids are save keys, never rename once shipped ---------
## The barracks' sparring roster (rising strength: Wynn < Aldous < the General). Each is ready once per
## rest (StoryRuleset.spar_cooldown_rests -- spars award Growth, so this stops the farm).
const SPAR_WYNN_ID := "crownhaven.spar.wynn"
const SPAR_ALDOUS_ID := "crownhaven.spar.aldous"
## THE FRIENDLY RIVAL (Lyra): the first duel (a trigger inside Crownhaven's south gate, after the opening), then
## rematches by the arena (once per rest). Progress lives in flags so later rematches scale:
## LEGACY KEYS (the owner merged the old rival "Lark" into Lyra, 2026-10-05): the encounter id below and the
## rival.* flags keep their old spelling so saves and the sparred.<id>.* cooldown flags stay valid.
const RIVAL_DUEL_ID := "crownhaven.rival.lark"  # legacy id (Lark -> Lyra)
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
	for d in ["areas/oakvale", "areas/oakvale_ruins", "areas/mossway", "areas/river_crossing", "areas/crownhaven",
			"areas/sparse_forest", "areas/woodland_town", "areas/deepwood_village", "areas/depths_of_the_wood",
			"battles", "shops", "tournaments", "field_moves"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + d))
	_build_world()
	_build_hero()
	_build_ruleset()
	_build_shops()
	_build_tournaments()
	_build_field_moves()
	_build_battle_map()
	_build_first_fight_map()
	_build_eldroot_map()
	_build_oakvale(false)
	_build_oakvale(true)
	_build_mossway()
	_build_river_crossing()
	_build_crownhaven()
	_build_sparse_forest()
	_build_woodland_town()
	_build_deepwood_village()
	_build_depths_of_the_wood()
	print("[build_story_content] %s" % ("done" if _ok else "FAILED"))
	quit(0 if _ok else 1)


# =====================================================================================
#  The world map registry (content/world.tres)
# =====================================================================================

func _build_world() -> void:
	var w := WorldAtlas.new()
	w.world_name = WORLD_NAME
	w.regions = WORLD_REGIONS.duplicate()
	var locs: Array[WorldLocation] = []
	for row in WORLD_LOCATIONS:
		var l := WorldLocation.new()
		l.id = StringName(row[0])
		l.display_name = String(row[1])
		l.kind = String(row[2])
		l.region_id = StringName(row[3])
		l.map_pos = row[4]
		var areas: Array[StringName] = []
		for aid in row[5]:
			areas.append(StringName(aid))
		# A town's building interiors are part of its place (not places of their own).
		for aid in row[5]:
			for iid in _interior_ids(String(aid)):
				areas.append(StringName(iid))
		l.area_ids = areas
		l.status = WorldLocation.Status.BUILT if not areas.is_empty() else WorldLocation.Status.CLOSED
		l.open_flag = String(row[6])
		l.secret = bool(row[7])
		l.description = String(row[8])
		locs.append(l)
	w.locations = locs
	var roads: Array[Dictionary] = []
	for r in WORLD_ROADS:
		roads.append({"a": StringName(r[0]), "b": StringName(r[1]), "kind": String(r[2])})
	w.roads = roads
	var issues: Array[String] = w.validate()
	if not issues.is_empty():
		push_error("[build_story_content] world map: %s" % str(issues))
		_ok = false
	_save(w, WorldAtlas.PATH)


func _world_row(location_id: String) -> Array:
	for row in WORLD_LOCATIONS:
		if String(row[0]) == location_id:
			return row
	push_error("[build_story_content] no world location '%s'" % location_id)
	_ok = false
	return []


## Place an area on the world map: its position and region come from [constant WORLD_LOCATIONS].
func _place(a: OverworldAreaResource, location_id: String) -> void:
	var row: Array = _world_row(location_id)
	if row.is_empty():
		return
	a.world_map_pos = row[4]
	a.region_id = StringName(row[3])
	a.level_band = REGION_BANDS.get(String(row[3]), Vector2i.ZERO)


## The closed road toward [param location_id]: a warp held by that place's open flag, answering
## with [param text] (it targets [param back_area] / [param back_entry] -- the place has no area yet).
func _closed_road(id: String, rect: Rect2i, location_id: String, back_area: StringName, back_entry: StringName,
		text: String) -> WarpEntity:
	var row: Array = _world_row(location_id)
	var flag: String = String(row[6]) if not row.is_empty() else "world.never"
	return _warp(id, rect, back_area, back_entry, "", "has(\"%s\")" % flag,
		_scene("%s_road_locked_%s" % [location_id, id], [_narr(text)]))


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


## The default starter's species name.
func _starter_name() -> String:
	return _species_name(STARTER_ID)


## A species name, read straight from its roster .tres TEXT (CharacterLibrary needs the autoloads,
## which a -s builder run does not have).
func _species_name(character_id: StringName) -> String:
	var roster: String = "res://game/characters/roster/"
	var dir := DirAccess.open(roster)
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var text: String = FileAccess.get_file_as_string(roster + f)
			if not text.contains("character_id = &\"%s\"" % character_id):
				continue
			var re := RegEx.create_from_string("display_name = \"([^\"]*)\"")
			var m := re.search(text)
			if m != null:
				return m.get_string(1)
	return String(character_id).capitalize()


# =====================================================================================
#  Hero + ruleset
# =====================================================================================

func _build_hero() -> void:
	var hero := HeroResource.new()
	hero.display_name = String(NAMES["HERO"])
	# DECISIONS.md owner decision 4: the Wren forge model (HERO_MODEL; it replaced the Vineweave
	# placeholder in 7f8ac62 -- kept here so a rebuild no longer reverts it). Swapping it is this
	# block (model + yaw + scale): data, not code. The hero is also a BATTLE unit
	# (docs/design/HUMANS.md): the "wren" roster entry, his party record flagged hero.
	hero.battle_character_id = &"wren"
	hero.model_scene = load(HERO_MODEL)
	hero.model_yaw_deg = 0.0
	hero.model_scale = 1.0
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
	# Solidity is per KIND (PropEntity.SOLID_KINDS); an explicit `true` on a walk-over kind makes it solid.
	if blocking and not PropEntity.SOLID_KINDS.has(kind):
		p.collision = "solid"
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
#  INTERIORS -- enterable buildings (docs/STORY_MODE.md "Interiors")
# =====================================================================================

## The Royal Workshop's prop id in Crownhaven. Its door's town entry ("door_workshop", the cell in
## front of the door) is where the ceremony's alarm brings the hero out, into the raid.
const CH_WORKSHOP_PROP := "workshop"
## The workshop interior's east-most floor column (it is 10 wide): where the kidnapping raiders come and go.
const WORKSHOP_EAST_X := 10

## OPT-IN, per building: town area id -> {building prop id -> spec}. A building NOT listed here
## stays a plain solid block: no door, no marker, no room. Listed: the places the story uses now
## (the Royal Workshop, the hero's home) and the community buildings the towns already had (inns,
## the village hall, shops, the barracks, the guildhall, the chapel, the forges, the Wardens' Lodge,
## the toll house). Spec keys:
##   "id"     the interior's area id (a SAVE KEY -- never rename once shipped)
##   "name"   its display name (the area ribbon)
##   "size"   the FLOOR in cells (8x6 .. 12x8); walls go round three sides, the south is the open
##            cut-away with the exit mat at its middle
##   "door"   optional: the door's offset in the prop footprint (default: the bottom row's middle,
##            else the nearest bottom-row cell whose front cell is open ground nobody stands on)
##   "floor"  optional: the floor tile id (default wooden_planks)
## Who stands inside: [method _interior_people] (nobody, by default -- no new NPCs).
const INTERIORS := {
	"oakvale": {
		"house_home": {"id": "oakvale_home", "name": "Home", "size": Vector2i(8, 6)},
		"house_inn": {"id": "oakvale_inn", "name": "The Hearth & Hen", "size": Vector2i(10, 7)},
		"house_hall": {"id": "oakvale_hall", "name": "Village Hall", "size": Vector2i(10, 6)},
		"house_bakery": {"id": "oakvale_bakery", "name": "Oakvale Bakery", "size": Vector2i(8, 6)},
	},
	"river_crossing": {
		"toll_house": {"id": "river_crossing_toll_house", "name": "Toll House", "size": Vector2i(8, 6)},
	},
	"crownhaven": {
		"workshop": {"id": "crownhaven_workshop", "name": "The Royal Workshop", "size": Vector2i(10, 7), "door": Vector2i(2, 2)},
		"barracks": {"id": "crownhaven_barracks", "name": "The Barracks", "size": Vector2i(10, 7)},
		"gilded_stag": {"id": "crownhaven_inn", "name": "The Gilded Stag", "size": Vector2i(10, 7)},
		"guildhall": {"id": "crownhaven_guildhall", "name": "The Merchants' Guildhall", "size": Vector2i(12, 8), "floor": "flagstones"},
		"chapel": {"id": "crownhaven_chapel", "name": "Chapel of the Starfall", "size": Vector2i(8, 8), "floor": "flagstones"},
		"forge": {"id": "crownhaven_forge", "name": "The Aldermere Forge", "size": Vector2i(8, 6), "floor": "flagstones"},
	},
	"woodland_town": {
		"wardens_lodge": {"id": "woodland_lodge", "name": "The Wardens' Lodge", "size": Vector2i(12, 7)},
		"stumped_hart": {"id": "woodland_inn", "name": "The Stumped Hart", "size": Vector2i(10, 7)},
		"trading_post": {"id": "woodland_trading_post", "name": "Sedge's Trading Post", "size": Vector2i(8, 6)},
		"forge": {"id": "woodland_forge", "name": "Woodland Smithy", "size": Vector2i(8, 6), "floor": "flagstones"},
		"herb_hut": {"id": "woodland_herb_hut", "name": "The Herb Hut", "size": Vector2i(8, 6)},
	},
}


## Every interior area id of town [param town_id] (the world map lists them under its place).
static func _interior_ids(town_id: String) -> Array[String]:
	var out: Array[String] = []
	var specs: Dictionary = INTERIORS.get(town_id, {})
	for k in specs:
		out.append(String(specs[k]["id"]))
	return out


## Give the enterable buildings of [param a] (INTERIORS) their doors: mark the prop enterable,
## put a [DoorEntity] on its facade, add the town entry the interior's exit mat returns to (the
## front cell, facing away from the building), and build the interior. Called by every town
## builder just before its entity list is stored; a town with no INTERIORS row is untouched.
func _add_doors(a: OverworldAreaResource, ents: Array) -> void:
	var specs: Dictionary = INTERIORS.get(String(a.area_id), {})
	if specs.is_empty():
		return
	var g := OverworldGrid.from_map(a.terrain)
	# Cells something stands on (NPCs, signs, chests, props): a door never opens onto one.
	var taken: Dictionary = {}
	for e in ents:
		var oe := e as OverworldEntity
		if oe == null or oe is WarpEntity or oe is TriggerZone:
			continue
		for c in oe.cells():
			taken[c] = String(oe.id)
	for e in ents.duplicate():
		var p := e as PropEntity
		if p == null or not specs.has(String(p.id)):
			continue
		var spec: Dictionary = specs[String(p.id)]
		p.enterable = true
		p.door_offset = spec["door"] if spec.has("door") else _pick_door(p, g, taken)
		var d := DoorEntity.new()
		d.id = StringName("door_" + String(p.id))
		d.building = p.id
		d.cell = p.door_cell()
		d.area_rect = Rect2i(d.cell.x, d.cell.y, 1, 1)
		d.blocking = false
		d.facing = "south"
		d.tint = p.tint
		d.display_name = String(spec["name"])
		d.target_area = StringName(spec["id"])
		d.target_entry = &"door"
		var front: Vector3i = d.front_cell()
		if not g.is_terrain_passable(front) or taken.has(front):
			push_error("[build_story_content] %s/%s: the door's front cell %s is not open ground (%s)" % [
				a.area_id, p.id, str(front), String(taken.get(front, g.tile_id_at(front)))])
			_ok = false
		a.entry_points[DoorEntity.entry_id_for(String(p.id))] = {"cell": [front.x, front.y, 0], "facing": d.exit_facing()}
		ents.append(d)
		_build_interior(a, p, spec)


## The door offset for [param p]: the bottom row's middle, else the nearest bottom-row cell whose
## front cell (and, preferably, the cell beyond it) is open, unoccupied ground.
func _pick_door(p: PropEntity, g: OverworldGrid, taken: Dictionary) -> Vector2i:
	var fp := Vector2i(maxi(1, p.footprint.x), maxi(1, p.footprint.y))
	var mid: int = (fp.x - 1) / 2
	var order: Array[int] = [mid]
	for k in range(1, fp.x):
		for x in [mid + k, mid - k]:
			if x >= 0 and x < fp.x and not order.has(x):
				order.append(x)
	# Best: the front cell AND the one beyond it are open (you come out facing open ground); else
	# just the front cell.
	for need_beyond in [true, false]:
		for x in order:
			var front := Vector3i(p.cell.x + x, p.cell.y + fp.y, 0)
			var beyond := Vector3i(front.x, front.y + 1, 0)
			if not g.is_terrain_passable(front) or taken.has(front):
				continue
			if need_beyond and (not g.is_terrain_passable(beyond) or taken.has(beyond)):
				continue
			return Vector2i(x, fp.y - 1)
	return Vector2i(mid, fp.y - 1)


## THE INTERIOR TEMPLATE -- one function for every enterable building: a floor of
## spec.size cells walled on three sides (the south is the cut-away the camera looks in through),
## the EXIT MAT at the bottom-centre (a warp back to the town's "door_<building>" entry), the
## arrival cell just above it (entry "door", facing in), two placeholder barrel stacks in the back
## corners, and [method _interior_people] (nobody by default). No encounter zones: no wild
## creatures inside. On the world map an interior is part of its town's place (WORLD_LOCATIONS
## lists it there), so "You are here" stays the town.
func _build_interior(town: OverworldAreaResource, p: PropEntity, spec: Dictionary) -> void:
	var iid: String = String(spec["id"])
	var nm: String = String(spec["name"])
	var floor_size: Vector2i = spec.get("size", Vector2i(8, 6))
	var w: int = floor_size.x + 2
	var h: int = floor_size.y + 1
	var door_x: int = w / 2
	var floor_tile: String = String(spec.get("floor", "wooden_planks"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + "areas/" + iid))
	var t := _new_map(nm, w, h, "%s, inside (%s). Story-mode interior." % [nm, town.display_name])
	t.lighting_preset = "Day"
	_paint(t, func(x: int, y: int) -> String:
		if y == 0 or x == 0 or x == w - 1:
			return "stone_wall"
		return floor_tile)
	_add_validator_anchors(t, Vector2i(1, 1), Vector2i(w - 2, h - 1))
	_save(t, CONTENT + "areas/%s/terrain.tres" % iid)

	var a := OverworldAreaResource.new()
	a.area_id = StringName(iid)
	a.display_name = nm
	a.kind = OverworldAreaResource.Kind.INTERIOR
	a.parent_area = town.area_id
	a.world_map_pos = town.world_map_pos
	a.region_id = town.region_id
	a.level_band = town.level_band
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % iid)
	a.entry_points = {"door": {"cell": [door_x, h - 2, 0], "facing": "north"}}
	var ents: Array = []
	ents.append(_prop("exit_mat", "mat", Vector2i(door_x, h - 1), Vector2i.ONE, Color(0.62, 0.22, 0.18)))
	ents.append(_warp("exit", Rect2i(door_x, h - 1, 1, 1), town.area_id, StringName(DoorEntity.entry_id_for(String(p.id)))))
	# PLACEHOLDER furniture (procedural; the real interiors come from Blender).
	ents.append(_prop("barrels_w", "barrels", Vector2i(1, 1), Vector2i.ONE, Color.WHITE, true))
	ents.append(_prop("barrels_e", "barrels", Vector2i(w - 2, 1), Vector2i.ONE, Color.WHITE, true))
	ents.append_array(_interior_people(iid, floor_size, door_x))
	a.entities = _entities(ents)
	a.on_enter = StoryCommand.list(_interior_on_enter(iid))
	_save(a, CONTENT + "areas/%s/area.tres" % iid)


## Who stands inside interior [param iid] (per-building override; empty rooms by default).
func _interior_people(iid: String, size: Vector2i, door_x: int) -> Array:
	match iid:
		"crownhaven_workshop":
			return _workshop_people(size, door_x)
	return []


## Scripts run when interior [param iid] loads (per-building override).
func _interior_on_enter(iid: String) -> Array:
	match iid:
		"crownhaven_workshop":
			# A journey that stopped between the ceremony and the end of the kidnapping resumes it here,
			# in the room where it happens.
			return [IfCommand.make("has(\"%s\") and not has(\"%s\")" % [F_STARTER, F_CHASE], _raid())]
	return []


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
## West: your squad chairs + the General and the Warrior as GUESTS (player-0 Reinforcements due on
## turn 1 = placed at load, never replaced by the squad pick). East: the enemy soldiers and their
## creatures (PLACEHOLDER roster units -- RAIDER_UNITS).
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
	# The General and the Warrior (PLACEHOLDER roster units): guest allies, placed at load.
	m.set_spawn_point_at_position(Vector2i(2, 2), 0, MapResource.SPAWN_KIND_REINFORCEMENT,
		{"character_id": GENERAL_UNIT, "spawn_turn": 1, "max_spawns": 1})
	m.set_spawn_point_at_position(Vector2i(2, 6), 0, MapResource.SPAWN_KIND_REINFORCEMENT,
		{"character_id": WARRIOR_UNIT, "spawn_turn": 1, "max_spawns": 1})
	var foes := [Vector2i(9, 2), Vector2i(9, 6), Vector2i(10, 3), Vector2i(10, 5)]
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
	# The hero fights in it himself, beside his starter (docs/design/HUMANS.md).
	spec.hero_deploy = BattleSpec.HeroDeploy.REQUIRED
	spec.ai_difficulty = 0
	spec.opponent_name = "Enemy Soldiers"  # TODO(story): placeholder
	spec.opponent_speaker_id = &"npc_raider_captain"
	var team: Array[Dictionary] = []
	for cid in RAIDER_UNITS:
		team.append({"character_id": cid, "strength": 1.0})
	spec.opponent_team = team
	spec.enemy_level = LV_FIRST_FIGHT
	var flags: Array[String] = [F_FIGHT_WON]
	spec.reward_flags = flags
	# The story cannot go on without this win: a loss offers Try Again / the Wayshrine, and the
	# General waits in the ruins to offer the fight again.
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	return spec


# =====================================================================================
#  Oakvale -- the hero's home village (before) and its ruins (after)
# =====================================================================================

const OAK_W := 24
## 18 rows of village and farmland, then the southern coast: a broken hedge (row 17), the shore
## (row 18) and the sea (rows 19-20) -- the world map puts Oakvale just above the coast.
const OAK_H := 21
const OAK_SHORE_Y := 18
const OAK_SEA_Y := 19
const OAK_TERRACOTTA := Color(0.72, 0.34, 0.2)
## The well on the village green (beside the Wayshrine's basin).
const OAK_WELL := Vector2i(12, 10)
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
## Where the General and the Warrior wait in the burned village (the road from the east gate leads
## to them; beside it, so neither stands in the one-cell gap of the tree line).
const RUINS_GENERAL := Vector2i(18, 9)
const RUINS_WARRIOR := Vector2i(18, 10)


## The buildings. The inn and the cottage have no ruined counterpart: the raid left only scorched
## ground there (and the ruins' node budget has no room for two more burned houses).
func _oak_buildings(ruined: bool = false) -> Array:
	var base: Array = [OAK_HOME, OAK_HALL, OAK_FARM, OAK_BAKERY, OAK_BARN, OAK_MILL]
	if not ruined:
		base.append_array([OAK_INN, OAK_COTTAGE])
	return base


func _oak_terrain(x: int, y: int, ruined: bool) -> String:
	var c := Vector2i(x, y)
	# The coast: the sea, a jetty off the south lane, the shore, and a broken hedge above it.
	if y >= OAK_SEA_Y:
		return "wooden_planks" if (x == 10 and y == OAK_SEA_Y) else "deep_water"
	if y == OAK_SHORE_Y:
		return "forest_dirt" if x > 0 and x < OAK_W - 1 else "tree"
	if y == OAK_SHORE_Y - 1:
		return "forest_dirt" if x == 10 else ("tree" if x % 3 == 0 or x == 0 or x >= OAK_W - 2 else "grass_plains")
	# Outer border: forest (north, the west edge), broken by the mill lane.
	if y <= 1 or (x == 0 and y != OAK_WEST_Y):
		return "tree"
	# The west lane runs out to the Farm Hamlet track.
	if y == OAK_WEST_Y and x <= 1:
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
	# The village green: a beaten-earth ring and crossroads round the grass (no paving -- this is
	# a farming village, not the city).
	if x >= 7 and x <= 13 and y >= 6 and y <= 12:
		if x == 7 or x == 13 or y == 6 or y == 12 or x == 10 or y == OAK_ROAD_Y:
			return "forest_dirt"
		return "grass_plains"
	# The high road (a cart track) from the green to the edge.
	if y == OAK_ROAD_Y and x >= 13:
		return "forest_dirt" if not ruined or _h(x, y, 1) > 0.3 else "ash_field"
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
			if ruined else "Oakvale, the hero's home: a farming village of barley fields above the southern coast.")
		+ " Story-mode terrain.")
	t.lighting_preset = "Night" if ruined else "Day"
	_paint(t, _oak_terrain.bind(ruined))
	_add_validator_anchors(t, Vector2i(10, 11), Vector2i(21, OAK_ROAD_Y))
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)

	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	a.display_name = "Ruined Oakvale" if ruined else "Oakvale"
	a.kind = OverworldAreaResource.Kind.TOWN
	_place(a, "oakvale")
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	var ents: Array = _oak_scenery(ruined)
	ents.append(_shrine(OAK_FOUNTAIN, "Oakvale Wayshrine"))
	if ruined:
		a.entry_points = {
			"east_road": {"cell": [21, OAK_ROAD_Y, 0], "facing": "west"},
			"east_gate": {"cell": [22, OAK_ROAD_Y, 0], "facing": "west"},
			"wayshrine": {"cell": [10, 10, 0], "facing": "north"},
			"west_lane": {"cell": [1, OAK_WEST_Y, 0], "facing": "east"},
		}
		ents.append_array(_oak_ruins_people())
		# The east road is open: the hero may leave to explore ("Not yet.") and come back -- the
		# General and the Warrior wait.
		ents.append(_warp("east_exit", Rect2i(23, OAK_ROAD_Y, 1, 1), &"mossway", &"west"))
		# The mill lane survived the fire: the cart track west to Farm Hamlet (its chapter is not
		# built yet -- the warp answers until world.farm_hamlet_open).
		ents.append(_closed_road("west_exit", Rect2i(0, OAK_WEST_Y, 1, 1), "farm_hamlet", &"oakvale_ruins", &"west_lane",
			"The cart track west of the burned mill runs on through trampled barley toward Farm Hamlet. A hurdle gate is dragged across it, and a note is pinned to the rail: \"Hamlet folk -- we are taking in Oakvale's families. Road shut till the harvest's in.\""))
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
			"west_lane": {"cell": [1, OAK_WEST_Y, 0], "facing": "east"},
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
		# warp answers until world.farm_hamlet_open; it targets the lane's own end meanwhile).
		ents.append(_closed_road("west_exit", Rect2i(0, OAK_WEST_Y, 1, 1), "farm_hamlet", &"oakvale", &"west_lane",
			"The cart track west of the mill runs on through the barley toward Farm Hamlet. A hurdle gate across it is tied shut with a ribbon: \"Harvest in progress -- back soon.\""))
		a.on_enter = StoryCommand.list([
			IfCommand.make("not has(\"%s\")" % F_SENT_OFF, _send_off()),
		])
	_add_doors(a, ents)
	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/%s/area.tres" % aid)


## Houses / ruins, the windmill, the farm clutter -- shared layout, the raid's damage on top.
func _oak_scenery(ruined: bool) -> Array:
	var out: Array = []
	# One village, one clay pit: every Oakvale roof is the same terracotta (a shade apart), the
	# barn barn-red -- Crownhaven's slate blues and Woodland Town's moss never appear here.
	var roofs := {
		"home": [OAK_HOME, OAK_TERRACOTTA],
		"hall": [OAK_HALL, OAK_TERRACOTTA.darkened(0.08)],
		"farm": [OAK_FARM, OAK_TERRACOTTA.lightened(0.05)],
		"bakery": [OAK_BAKERY, OAK_TERRACOTTA],
		"barn": [OAK_BARN, Color(0.6, 0.18, 0.14)],
		"inn": [OAK_INN, OAK_TERRACOTTA.darkened(0.04)],
		"cottage": [OAK_COTTAGE, OAK_TERRACOTTA.lightened(0.03)],
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
	out.append(_prop("well", "well", OAK_WELL, Vector2i.ONE, Color(0.5, 0.3, 0.2), true))
	if ruined:
		# The fires burn through the night of the raid; once the opening is over they are out.
		var burning: String = "not has(\"%s\")" % F_COMPLETE
		for f in [Vector2i(15, 10), Vector2i(17, 11), Vector2i(8, 15), Vector2i(19, 13), Vector2i(12, 3),
				Vector2i(16, 16), Vector2i(21, OAK_ROAD_Y + 2)]:
			if _oak_terrain(f.x, f.y, true) == "tree":
				continue
			out.append(_prop("fire_%d_%d" % [f.x, f.y], "fire", f, Vector2i.ONE, Color.WHITE, false, burning))
		for r in [Vector2i(14, 12), Vector2i(8, 14), Vector2i(18, 8), Vector2i(6, 11)]:
			out.append(_prop("rubble_%d_%d" % [r.x, r.y], "rubble", r, Vector2i.ONE, Color.WHITE))
		out.append(_prop("cart", "rubble", Vector2i(19, 12), Vector2i.ONE, Color.WHITE))
		# Rebuilding, after the opening: new timber stacked on the Hearth & Hen's scorched plot.
		var after: String = "has(\"%s\")" % F_COMPLETE
		out.append(_prop("rebuild_logs", "logs", Vector2i(OAK_INN.position.x, OAK_INN.position.y), Vector2i(2, 1),
			Color(0.66, 0.5, 0.3), true, after))
		out.append(_prop("rebuild_cart", "cart", Vector2i(OAK_INN.position.x + 2, OAK_INN.position.y - 1), Vector2i.ONE,
			Color(0.86, 0.72, 0.38), true, after))
	else:
		out.append(_prop("field", "crops", OAK_FIELD.position, OAK_FIELD.size, Color(0.4, 0.6, 0.26)))
		out.append(_prop("garden", "crops", OAK_GARDEN.position, OAK_GARDEN.size, Color(0.3, 0.55, 0.3)))
		out.append(_prop("field_fence", "fence", Vector2i(14, 12), Vector2i(5, 1), Color(0.5, 0.36, 0.22), true))
		out.append(_prop("haystack", "haystack", Vector2i(19, 13), Vector2i.ONE, Color.WHITE, true))
		out.append(_prop("cart", "cart", Vector2i(19, 12), Vector2i.ONE, Color(0.86, 0.72, 0.38), true))
		out.append(_prop("barrels", "barrels", Vector2i(7, 14), Vector2i.ONE, Color.WHITE, true))
		# Farming-village flavour: a scarecrow in the field, a second haystack, a market-day stall
		# on the plaza, lamps at its corners, a barrel by the inn door and a fence round the pond.
		out.append(_prop("scarecrow", "scarecrow", Vector2i(16, 10), Vector2i.ONE, Color(0.5, 0.36, 0.2), true))
		out.append(_prop("haystack_2", "haystack", Vector2i(19, 14), Vector2i.ONE, Color.WHITE, true))
		out.append(_prop("market_stall", "stall", Vector2i(11, 7), Vector2i(2, 1), Color(0.78, 0.6, 0.22), true))
		for lc in [Vector2i(7, 6), Vector2i(14, 6), Vector2i(7, 12), Vector2i(13, 12)]:
			out.append(_prop("lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
		out.append(_prop("inn_barrels", "barrels", Vector2i(14, 7), Vector2i.ONE, Color.WHITE, true))
		out.append(_prop("pond_fence", "fence", Vector2i(6, 5), Vector2i(2, 1), Color(0.5, 0.36, 0.22), true))
	return out


func _oak_people() -> Array:
	var out: Array = []
	out.append(_sign("town_sign", Vector2i(19, 8), "Oakvale",
		"OAKVALE\nEast: the Mossway to River Crossing, then north over the Old Bridge to Crownhaven.\nWest: Farm Hamlet.  South: the sea.\nTravellers, mind the grass."))
	out.append(_sign("strand_sign", Vector2i(11, OAK_SHORE_Y), "The Strand",
		"THE STRAND\nOakvale's shingle beach and the fishing jetty. The tide comes in faster than you think."))
	out.append(_sign("hall_sign", Vector2i(13, 5), "Village Hall",
		"A notice is nailed to the door:\n\"By order of {KINGDOM}'s crown: shards of {STONE} will be granted to chosen testers at Crownhaven. One tester is called from Oakvale, at the Royal Researcher's own request: {hero}.\""))

	# The villagers' talk is in dialogue.json (DialogueBank): areas.oakvale.<id>.
	out.append(_npc("briony", Vector2i(OAK_START.x + 1, OAK_START.y), "west", "MOTHER", Color(0.62, 0.36, 0.3)))
	out.append(_npc("tobin", Vector2i(13, 11), "east", "TOBIN", Color(0.36, 0.46, 0.62)))
	out.append(_npc("hessa", Vector2i(11, 15), "east", "HESSA", Color(0.6, 0.5, 0.3), "villager"))
	out.append(_npc("pell", Vector2i(8, 7), "south", "PELL", Color(0.4, 0.6, 0.5), "child"))

	# --- The farming village, filled in: the inn, the fields, the pond, the lanes ---------------
	out.append(_sign("inn_sign", Vector2i(14, 8), "The Hearth & Hen",
		"THE HEARTH & HEN\nBed, broth and a warm hearth. Muddy boots at the door, please.\nRoad north-east: Crownhaven by way of River Crossing."))
	out.append(_sign("field_sign", Vector2i(13, 10), "Barley Field",
		"\"Please keep to the lane. The barley is counting on you.\" -- Ned"))
	out.append(_sign("mill_sign", Vector2i(5, 11), "The Mill Lane",
		"WEST: the cart track to Farm Hamlet.\nMILL LANE: flour, sacks and gossip, in that order."))
	out.append(_npc("marra", Vector2i(15, 8), "south", "MARRA", Color(0.7, 0.4, 0.3), "villager"))
	out.append(_npc("ned", Vector2i(13, 8), "east", "NED", Color(0.5, 0.45, 0.3), "elder"))
	out.append(_npc("wick", Vector2i(8, 5), "south", "WICK", Color(0.62, 0.5, 0.34), "child"))
	return out


## The send-off: the first scene of a new journey (Oakvale on_enter, until opening.sent_off).
func _send_off() -> Array:
	return [
		_say([
			_narr("Long ago, a star fell on this world. Its dust sank into the stone and the soil, and ever since, humans and creatures alike have called on the elements.", "Conquest"),
		]),
		_face("player", "toward:briony"),
		_say([
			# TODO(story): placeholder send-off, cut to the bone. Owner facts only: Professor Elias is an
			# old friend of the hero's mother (a family friend) and has asked to see the hero.
			_line("briony", "MOTHER", "There you are, {hero}! {RESEARCHER_TITLE} is expecting you at his workshop in Crownhaven -- an old friend of the family."),
			_line("briony", "MOTHER", "Follow the Mossway east, then the road north over the bridge. Go on -- I love you."),
		]),
		_flag(F_SENT_OFF),
	]


func _oak_ruins_people() -> Array:
	var out: Array = []
	# The survivors' talk is in dialogue.json (DialogueBank): areas.oakvale_ruins.<id>.
	out.append(_npc("tobin", Vector2i(11, 11), "north", "TOBIN", Color(0.3, 0.36, 0.44)))
	out.append(_npc("hessa", Vector2i(4, 9), "west", "HESSA", Color(0.45, 0.38, 0.26), "villager"))
	out.append(_npc("pell", Vector2i(6, 10), "north", "PELL", Color(0.3, 0.45, 0.4), "child"))
	out.append_array(_ruins_allies())
	var cairn := _sign("cairn", Vector2i(OAK_GARDEN.position.x + 1, OAK_GARDEN.position.y), "A cairn",
		"Stones piled with care beside a burned house, and wildflowers laid across them.\n\"{MOTHER} of Oakvale, who went back for the others.\"", "stone")
	cairn.visible_if = "has(\"%s\")" % F_COMPLETE
	out.append(cairn)
	# After the opening the rest of the village comes back out to rebuild: the Hearth & Hen's
	# landlady on her scorched plot, Old Ned at his ash field, Wick at the pond.
	var after: String = "has(\"%s\")" % F_COMPLETE
	var marra := _npc("marra", Vector2i(OAK_INN.position.x, OAK_INN.end.y), "south", "MARRA", Color(0.6, 0.34, 0.26), "villager")
	marra.visible_if = after
	out.append(marra)
	var ned := _npc("ned", Vector2i(13, 12), "east", "NED", Color(0.45, 0.4, 0.28), "elder")
	ned.visible_if = after
	out.append(ned)
	var wick := _npc("wick", Vector2i(8, 5), "south", "WICK", Color(0.52, 0.42, 0.3), "child")
	wick.visible_if = after
	out.append(wick)
	return out


## The General and the Warrior, waiting in the burned village from the moment the hero arrives until
## the fight is won. TODO(story): PLACEHOLDER allies (NAMES: GENERAL / WARRIOR) -- who they are is
## the owner's to decide.
func _ruins_allies() -> Array:
	var vis: String = "has(\"%s\") and not has(\"%s\")" % [F_CHASE, F_COMPLETE]
	var out: Array = []
	var general := _npc("general", RUINS_GENERAL, "east", "GENERAL", ALDERMERE_BLUE, "officer")
	general.visual_character = VARDEN_MODEL
	var warrior := _npc("warrior", RUINS_WARRIOR, "east", "WARRIOR", Color(0.5, 0.3, 0.2), "guard")
	for ally in [general, warrior]:
		ally.visible_if = vis
		ally.on_interact = StoryCommand.list([_allies_offer()])
		out.append(ally)
	return out


## Arriving in the burned village: Hessa tells you your mother is dead (owner: a FORCED story beat),
## then the General and the Warrior say what happened, then the offer to join the fight.
## TODO(story): neutral placeholder wording -- only the facts the owner gave.
func _ruins_arrival() -> Array:
	return [
		_move("player", Vector2i(RUINS_GENERAL.x + 1, OAK_ROAD_Y)),
		_emote("hessa", "!"),
		_move("hessa", Vector2i(RUINS_GENERAL.x + 1, OAK_ROAD_Y + 1)),
		_face("player", "toward:hessa"),
		_say([
			_line("hessa", "HESSA", "{hero}... I'm so sorry. Your mother got the little ones down into the mill cellar, then went back for {MAUD}."),
			_line("hessa", "HESSA", "The roof came down. She didn't come out."),
		]),
		_face("player", "toward:general"),
		_say([
			_line("general", "GENERAL", "Enemy soldiers took the Professor, and they burned Oakvale as a distraction while they got away."),
			_line("warrior", "WARRIOR", "Their rear guard is holding the road past the mill. We're going in."),
		]),
		_flag(F_ALLIES_MET),
		_flag(F_RUINS_SEEN),
		_allies_offer(),
	]


## The offer (on arrival, and whenever you talk to either of them until the fight is won). "Not yet."
## leaves the village to explore first -- they wait.
func _allies_offer() -> ChoiceCommand:
	var ask := ChoiceCommand.new()
	ask.prompt = _line("general", "GENERAL", "Will you fight with us, {hero}?")
	var fight := StartBattleCommand.new()
	fight.spec = _first_fight_spec()
	fight.source = BattleRequest.SOURCE_SCRIPT
	var yes := ChoiceOption.make(_t("I'll fight."), [
		_say([_line("general", "GENERAL", "Stay close to your {lead}.")]),
		# A loss sends you to this Wayshrine (the fight waits here with the General).
		_respawn(&"oakvale_ruins", &"wayshrine"),
		fight,
		IfCommand.make("outcome() == \"victory\"", _aftermath()),
	])
	var no := ChoiceOption.make("Not yet.", [
		_say([_line("general", "GENERAL", "We'll wait here.")]),
	], true)
	ask.options = StoryCommand.list([yes, no])
	return ask


## After the first fight is won: the General and the Warrior task you with getting stronger (to avenge
## your mother) while they prepare for war -- and then you are free to explore the whole region.
## TODO(story): neutral placeholder wording -- only the facts the owner gave.
func _aftermath() -> Array:
	return [
		_say([
			_narr("The last enemy falls."),
			_line("general", "GENERAL", "Get stronger, {hero}. Avenge your mother."),
			_line("warrior", "WARRIOR", "We'll be preparing for war."),
			_narr("That evening, the village raises a cairn for {MOTHER} beside the house she built."),
		]),
		_flag(F_COMPLETE),
		# Legacy hook flag (kept for saves and ambient-talk gates); nothing sends the hero anywhere now.
		_flag(F_ACT1),
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
	# Both ends open onto the road: west to Oakvale, east to River Crossing.
	if x == 0 or x >= MOSS_W - 1:
		return "forest_dirt" if y == 6 else "tree"
	# The Mossbrook runs bank to bank (tree line to tree line): its plank bridge is the ONLY way
	# over -- the ambush on it cannot be walked round.
	if x == 21:
		return "wooden_planks" if y == 6 else "deep_water"
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
	# The recruit's clearing.
	if x >= 28 and x <= 31 and y >= 2 and y <= 4:
		return "sacred_meadow"
	if c in [Vector2i(3, 3), Vector2i(11, 3), Vector2i(14, 2), Vector2i(19, 9), Vector2i(29, 8),
			Vector2i(9, 9), Vector2i(26, 5), Vector2i(31, 7), Vector2i(2, 8), Vector2i(17, 3)]:
		return "tree"
	return "grass_plains"


func _build_mossway() -> void:
	var t := _new_map("The Mossway", MOSS_W, MOSS_H,
		"Route 1: a mossy forest road east from Oakvale to River Crossing, grown over with biting grass. Story-mode terrain.")
	t.lighting_preset = "Day"
	_paint(t, _moss_terrain)
	_add_validator_anchors(t, Vector2i(1, 6), Vector2i(30, 6))
	_save(t, CONTENT + "areas/mossway/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"mossway"
	a.display_name = "Route 1 -- The Mossway"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "mossway")
	a.terrain = load(CONTENT + "areas/mossway/terrain.tres")
	a.entry_points = {
		"west": {"cell": [1, 6, 0], "facing": "east"},
		"east": {"cell": [MOSS_W - 2, 6, 0], "facing": "west"},
	}

	var after_opening: String = "has(\"%s\")" % F_COMPLETE
	var ents: Array = []
	ents.append(_sign("route_sign", Vector2i(3, 5), "Route 1",
		"ROUTE 1 -- THE MOSSWAY\nWest: Oakvale.  East: River Crossing."))
	ents.append(_sign("crownhaven_sign", Vector2i(31, 5), "River Crossing",
		"EAST: RIVER CROSSING\nThe Old Bridge, and the King's road north to Crownhaven."))
	# The MOSSBROOK's plank bridge (the river proper -- and its stone bridge -- is River Crossing,
	# the next area east): lamp-posted and signed, with a fence along the bank.
	ents.append(_sign("brook_sign", Vector2i(20, 5), "The Mossbrook",
		"THE MOSSBROOK\nPlanks laid by the Wardens. Cross carefully -- the brook is deeper than it looks.\nWest: Oakvale.  East: River Crossing."))
	ents.append(_prop("bridge_lamp_n", "lamp", Vector2i(20, 7), Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
	ents.append(_prop("bridge_lamp_s", "lamp", Vector2i(22, 5), Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
	ents.append(_prop("bank_fence", "fence", Vector2i(20, 2), Vector2i(1, 3), Color(0.5, 0.36, 0.22), true))

	# (Before you have a partner the wild creatures leave you alone -- silently: no hint scene on the road.)

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
		_beat(&"self", "", "Hold it! You're the one from Oakvale. Show me you can keep a squad alive out here."),
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
	spec.enemy_level = LV_BRAM
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
	duel_spec.enemy_level = LV_LONE_PETALFANG
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
	# His greeting is in dialogue.json (areas.mossway.pedlar).
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
	ents.append(_warp("east_exit", Rect2i(MOSS_W - 1, 6, 1, 1), &"river_crossing", &"west"))

	_add_doors(a, ents)
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
	zone.level_band = BAND_MOSSWAY_GRASS
	var zones: Array[Resource] = [zone]
	a.encounter_zones = zones
	_save(a, CONTENT + "areas/mossway/area.tres")


# =====================================================================================
#  River Crossing -- the toll village at the Old Bridge
# =====================================================================================
#
# The world map's stop east of Oakvale: the river that comes down from the capital's walls runs
# east-west across the whole area (three rows of deep water, edge to edge -- there is no walking
# round it) and the OLD BRIDGE, a two-wide stone span, is the only way over. The village is on the
# south bank: the toll-house at the bridge foot, slate-roofed cottages, a fisher's jetty and the
# Wayshrine. The Mossway comes in from the west, the King's road leaves north for Crownhaven's
# south gate, and the coast road east to Beach Village is washed out (closed).

const RC_W := 24
const RC_H := 20
## The river's rows (north bank above, the village below) and the bridge's columns.
const RC_RIVER_Y0 := 7
const RC_RIVER_Y1 := 9
const RC_BRIDGE_X0 := 11
const RC_BRIDGE_X1 := 12
const RC_ROAD_Y := 14
const RC_TOLL := Rect2i(13, 11, 2, 2)
const RC_HOMES := [Rect2i(3, 11, 3, 2), Rect2i(5, 16, 3, 2), Rect2i(16, 16, 3, 2)]
const RC_HUT := Rect2i(19, 11, 2, 2)
const RC_SHRINE := Vector2i(8, 13)
const RC_JETTY := Vector2i(17, RC_RIVER_Y1)
const RC_SLATE := Color(0.36, 0.42, 0.5)
const RC_TREES := [Vector2i(2, 2), Vector2i(4, 4), Vector2i(7, 1), Vector2i(8, 5), Vector2i(3, 6), Vector2i(6, 6),
	Vector2i(15, 3), Vector2i(17, 1), Vector2i(19, 4), Vector2i(21, 2), Vector2i(16, 6), Vector2i(20, 6),
	Vector2i(1, 16), Vector2i(2, 18), Vector2i(10, 17), Vector2i(13, 17), Vector2i(20, 18), Vector2i(22, 16),
	Vector2i(1, 11), Vector2i(22, 11)]


func _rc_buildings() -> Array:
	return [RC_TOLL, RC_HUT] + RC_HOMES


func _rc_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	var on_bridge: bool = x >= RC_BRIDGE_X0 and x <= RC_BRIDGE_X1
	# The river, bank to bank across the whole map; the Old Bridge's stone deck over it.
	if y >= RC_RIVER_Y0 and y <= RC_RIVER_Y1:
		if on_bridge:
			return "flagstones"
		return "wooden_planks" if c == RC_JETTY else "deep_water"
	# The King's road north (to Crownhaven) runs off the top edge.
	if on_bridge and y < RC_RIVER_Y0:
		return "flagstones"
	if y == 0 or y == RC_H - 1:
		return "tree"
	# The Mossway (west) and the coast road (east) leave by the side edges.
	if x == 0 or x == RC_W - 1:
		return "forest_dirt" if y == RC_ROAD_Y else "tree"
	if _in(_rc_buildings(), c):
		return "stone_wall"
	if c == RC_SHRINE:
		return "sacred_ground"
	# The bridge road down to the crossroads, the Mossway road and the coast road.
	if on_bridge and y > RC_RIVER_Y1 and y <= RC_ROAD_Y:
		return "flagstones"
	if y == RC_ROAD_Y:
		return "forest_dirt"
	# Lanes to the cottages, a riverside path along the south bank.
	if (x == 6 and y >= 15 and y <= 15) or (x == 17 and y == 15) or (y == RC_RIVER_Y1 + 1 and x >= 13 and x <= 20):
		return "forest_dirt"
	# Willows along the banks, a few trees in the meadows (hand-placed: nothing walls a lane off).
	if c in RC_TREES:
		return "tree"
	return "grass_plains"


func _build_river_crossing() -> void:
	var t := _new_map("River Crossing", RC_W, RC_H,
		"River Crossing: a toll village at the Old Bridge, where the King's road crosses the river north to Crownhaven. Story-mode terrain.")
	t.lighting_preset = "Day"
	_paint(t, _rc_terrain)
	_add_validator_anchors(t, Vector2i(1, RC_ROAD_Y), Vector2i(RC_BRIDGE_X0, 2))
	_save(t, CONTENT + "areas/river_crossing/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"river_crossing"
	a.display_name = "River Crossing"
	a.kind = OverworldAreaResource.Kind.TOWN
	_place(a, "river_crossing")
	a.terrain = load(CONTENT + "areas/river_crossing/terrain.tres")
	a.entry_points = {
		"west": {"cell": [1, RC_ROAD_Y, 0], "facing": "east"},
		"north": {"cell": [RC_BRIDGE_X0, 1, 0], "facing": "south"},
		"east_road": {"cell": [RC_W - 2, RC_ROAD_Y, 0], "facing": "west"},
		"wayshrine": {"cell": [RC_SHRINE.x, RC_SHRINE.y + 1, 0], "facing": "north"},
	}
	var ents: Array = []
	# The toll-house and cottages (slate roofs -- a river village, not Oakvale's terracotta).
	ents.append(_prop("toll_house", "house", RC_TOLL.position, RC_TOLL.size, RC_SLATE.darkened(0.1)))
	ents.append(_prop("fisher_hut", "cabin", RC_HUT.position, RC_HUT.size, Color(0.4, 0.36, 0.3)))
	for i in range(RC_HOMES.size()):
		var r: Rect2i = RC_HOMES[i]
		ents.append(_prop("cottage_%d" % i, "house", r.position, r.size, RC_SLATE.lightened(0.04 * i)))
	# Lamps at the four corners of the Old Bridge, a fence along the west bank, barrels by the toll.
	for lc in [Vector2i(RC_BRIDGE_X0 - 1, RC_RIVER_Y0 - 1), Vector2i(RC_BRIDGE_X1 + 1, RC_RIVER_Y0 - 1),
			Vector2i(RC_BRIDGE_X0 - 1, RC_RIVER_Y1 + 1)]:
		ents.append(_prop("bridge_lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
	ents.append(_prop("bank_fence", "fence", Vector2i(3, RC_RIVER_Y1 + 1), Vector2i(6, 1), Color(0.5, 0.36, 0.22), true))
	ents.append(_prop("toll_barrels", "barrels", Vector2i(RC_TOLL.end.x, RC_TOLL.position.y + 1), Vector2i.ONE, Color.WHITE, true))
	ents.append(_prop("coast_cart", "cart", Vector2i(21, RC_ROAD_Y - 1), Vector2i.ONE, Color(0.7, 0.58, 0.34), true))
	ents.append(_shrine(RC_SHRINE, "River Crossing Wayshrine"))

	ents.append(_sign("bridge_sign", Vector2i(RC_BRIDGE_X0 - 1, RC_RIVER_Y1 + 2), "The Old Bridge",
		"THE OLD BRIDGE\nOlder than the kingdom; kept by the crown.\nNorth: Crownhaven.  West: the Mossway to Oakvale.\nEast: the coast road to Beach Village (closed)."))
	ents.append(_sign("milestone", Vector2i(RC_BRIDGE_X1 + 1, 2), "Milestone",
		"A worn milestone: \"CROWNHAVEN -- THE SOUTH GATE\". Someone has carved a little crown under the letters.", "stone"))
	ents.append(_sign("coast_sign", Vector2i(RC_W - 3, RC_ROAD_Y + 1), "The Coast Road",
		"EAST: BEACH VILLAGE\nRoad closed -- washed out at the ford. By order of the Wardens."))

	# The villagers' talk is in dialogue.json (DialogueBank): areas.river_crossing.<id>.
	ents.append(_npc("hobb", Vector2i(RC_BRIDGE_X1 + 1, RC_RIVER_Y1 + 1), "west", "TOLLKEEPER", Color(0.4, 0.4, 0.5), "elder"))
	ents.append(_npc("nan", RC_JETTY, "north", "FISHER", Color(0.36, 0.5, 0.56), "villager"))
	ents.append(_npc("joss", Vector2i(20, RC_ROAD_Y - 1), "east", "CARTER", Color(0.55, 0.42, 0.26), "villager"))
	ents.append(_npc("rc_child", Vector2i(7, 15), "north", "Pip", Color(0.6, 0.5, 0.36), "child"))

	ents.append(_warp("west_exit", Rect2i(0, RC_ROAD_Y, 1, 1), &"mossway", &"east"))
	ents.append(_warp("north_exit", Rect2i(RC_BRIDGE_X0, 0, 2, 1), &"crownhaven", &"south_gate"))
	ents.append(_closed_road("east_exit", Rect2i(RC_W - 1, RC_ROAD_Y, 1, 1), "beach_village", &"river_crossing", &"east_road",
		"The coast road east toward Beach Village and the sea dips into a ford -- and the ford has become a lake. A Warden's rope and a painted board: \"Road closed. Ferry suspended. Ask again after the rains.\""))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	# No arrival narration (the location popup names the village); the flag is set silently.
	a.on_enter = StoryCommand.list([
		IfCommand.make("not has(\"river_crossing.arrived\")", [_flag("river_crossing.arrived")]),
	])
	_save(a, CONTENT + "areas/river_crossing/area.tres")


# =====================================================================================
#  Crownhaven -- the walled castle town
# =====================================================================================

const CH_W := 30
## 24 rows of walled city, then the river along its south side (bank, two rows of water, the far
## bank) and the King's road south to River Crossing.
const CH_H := 29
## The town wall ring (stone_wall on its edge cells) and its FIVE gates, following the world map:
##   south (CH_SOUTH_GATE)   -- the King's road over the river to River Crossing, Oakvale (open)
##   west (CH_GATE)          -- the Sparse Forest road to Woodland Town (after the opening)
##   north (CH_NORTH_GATE)   -- the Mountain Road to Mountain Base and the Pass (closed)
##   east (CH_EAST_GATE)     -- the Redrock road into the Rocky Badlands (closed)
##   harbour (CH_HARBOUR_GATE, the south-east) -- the coast road to Beach Village (closed)
const CH_WALL := Rect2i(3, 3, 25, 21)
const CH_GATE := Vector2i(3, 13)
const CH_SOUTH_GATE := Vector2i(15, 23)
const CH_NORTH_GATE := Vector2i(9, 3)
const CH_EAST_GATE := Vector2i(27, 13)
const CH_HARBOUR_GATE := Vector2i(27, 17)
## The river south of the walls (fed by the moat down the west side) and the stone bridge over it.
const CH_RIVER_Y0 := 25
const CH_RIVER_Y1 := 26
const CH_BRIDGE_X0 := 14
const CH_BRIDGE_X1 := 16
const CH_KEEP := Rect2i(11, 4, 8, 4)
const CH_BARRACKS := Rect2i(4, 4, 4, 3)
const CH_LAB := Rect2i(22, 4, 4, 3)
const CH_MARKET := Rect2i(10, 11, 11, 7)
const CH_FOUNTAIN := Vector2i(15, 14)
const CH_HOUSES := [Rect2i(5, 15, 3, 2), Rect2i(5, 19, 3, 2), Rect2i(17, 19, 3, 2), Rect2i(22, 15, 3, 2)]
const CH_STALLS := [Rect2i(11, 12, 2, 1), Rect2i(18, 12, 2, 1), Rect2i(11, 16, 2, 1), Rect2i(18, 16, 2, 1)]
const CH_PYLON := Vector2i(22, 8)
## The capital's districts, built out: the Gilded Stag inn (by the market), the Merchants' Guildhall
## (the south quarter, west of the gate avenue), the Chapel of the Starfall (the east park), the
## Aldermere Forge (the east quarter, on Harbour Lane).
const CH_INN := Rect2i(7, 11, 3, 2)
const CH_GUILD := Rect2i(11, 19, 3, 2)
const CH_CHAPEL := Rect2i(24, 10, 3, 2)
const CH_SMITHY := Rect2i(25, 15, 2, 2)
const CH_NEW_BUILDINGS := [CH_INN, CH_GUILD, CH_CHAPEL, CH_SMITHY]


func _ch_gate(c: Vector2i) -> bool:
	return c == CH_GATE or c == CH_NORTH_GATE or c == CH_EAST_GATE or c == CH_SOUTH_GATE or c == CH_HARBOUR_GATE


func _ch_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	var inside: bool = x > CH_WALL.position.x and x < CH_WALL.end.x - 1 \
		and y > CH_WALL.position.y and y < CH_WALL.end.y - 1
	var on_wall: bool = CH_WALL.has_point(c) and not inside
	var on_bridge: bool = x >= CH_BRIDGE_X0 and x <= CH_BRIDGE_X1
	if on_wall:
		return "flagstones" if _ch_gate(c) else "stone_wall"
	if not CH_WALL.has_point(c):
		# The river along the south side, edge to edge, and the stone bridge over it; the King's
		# road on south to River Crossing.
		if y >= CH_RIVER_Y0 and y <= CH_RIVER_Y1:
			return "flagstones" if on_bridge else "deep_water"
		if on_bridge and y > CH_WALL.end.y - 1:
			return "flagstones" if y < CH_H - 1 else "forest_dirt"
		# The north road (Mountain Base), the east road (Redrock), the harbour road (Beach Village).
		if x == CH_NORTH_GATE.x and y < CH_WALL.position.y:
			return "forest_dirt"
		if (y == CH_EAST_GATE.y or y == CH_HARBOUR_GATE.y) and x > CH_EAST_GATE.x:
			return "forest_dirt"
		if absi(x - CH_NORTH_GATE.x) <= 1 and y == CH_WALL.position.y - 1:
			return "grass_plains"
		# The west road (the Sparse Forest) over the moat that feeds the river.
		if y == CH_GATE.y and x < CH_GATE.x:
			return "wooden_planks" if x == 2 else "forest_dirt"
		if x == 2 and y >= 4 and y < CH_RIVER_Y0:
			return "deep_water"
		if y <= 1 or y >= CH_H - 1 or x == 0 or x == CH_W - 1:
			return "tree"
		# Open verges beside the roads (the gate signs stand there), the forest edge beyond.
		if absi(y - CH_GATE.y) <= 2 and x < CH_GATE.x:
			return "grass_plains"
		if x > CH_EAST_GATE.x and (absi(y - CH_EAST_GATE.y) <= 1 or absi(y - CH_HARBOUR_GATE.y) <= 1):
			return "grass_plains"
		if absi(x - CH_SOUTH_GATE.x) <= 3 and (y == CH_WALL.end.y or y == CH_RIVER_Y1 + 1):
			return "grass_plains"
		if _h(x, y, 11) < 0.25:
			return "tree"
		return "grass_plains"
	# Inside the walls.
	if CH_KEEP.has_point(c) or CH_BARRACKS.has_point(c) or CH_LAB.has_point(c) or _in(CH_HOUSES, c) \
			or CH_ARENA.has_point(c) or _in(CH_NEW_BUILDINGS, c):
		return "stone_wall"
	# The north gate's avenue to the keep courtyard, the south gate's avenue to the market street,
	# Harbour Lane out of the south-east gate, and the chapel's garden path.
	if x == CH_NORTH_GATE.x and y >= 4 and y <= 8:
		return "flagstones"
	if x == CH_SOUTH_GATE.x and y >= 18 and y < CH_SOUTH_GATE.y:
		return "flagstones"
	if y == CH_HARBOUR_GATE.y and x >= 22 and x < CH_HARBOUR_GATE.x:
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
	# Streets: the main street from the west gate, the north street, the east street, the lab lane,
	# the south street between the house rows.
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
		"Crownhaven, the walled river city and royal seat of Aldermere: the keep, the market, the barracks, the Researcher's workshop and five gates. Story-mode terrain.")
	t.lighting_preset = "Day"
	_paint(t, _ch_terrain)
	_add_validator_anchors(t, Vector2i(CH_SOUTH_GATE.x, CH_H - 2), Vector2i(15, 15))
	_save(t, CONTENT + "areas/crownhaven/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"crownhaven"
	a.display_name = "Crownhaven"
	a.kind = OverworldAreaResource.Kind.TOWN
	_place(a, "crownhaven")
	a.terrain = load(CONTENT + "areas/crownhaven/terrain.tres")
	a.entry_points = {
		"south_gate": {"cell": [CH_SOUTH_GATE.x, CH_H - 2, 0], "facing": "north"},
		"west_gate": {"cell": [1, CH_GATE.y, 0], "facing": "east"},
		"north_gate": {"cell": [CH_NORTH_GATE.x, 1, 0], "facing": "south"},
		"east_gate": {"cell": [CH_W - 2, CH_EAST_GATE.y, 0], "facing": "west"},
		"harbour_gate": {"cell": [CH_W - 2, CH_HARBOUR_GATE.y, 0], "facing": "west"},
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
	ents.append_array(_ch_districts())
	# The south gate: over the river to River Crossing (and on to the Mossway and Oakvale).
	ents.append(_warp("south_exit", Rect2i(CH_BRIDGE_X0, CH_H - 1, CH_BRIDGE_X1 - CH_BRIDGE_X0 + 1, 1),
		&"river_crossing", &"north"))
	# The west gate: the Sparse Forest road to Woodland Town (open once the opening is over).
	ents.append(_warp("west_exit", Rect2i(0, CH_GATE.y, 1, 1), &"sparse_forest", &"east", "",
		"has(\"%s\")" % F_COMPLETE, _scene("ch_west_locked", [
			_narr("A Gate Warden bars the way. \"West road's closed for now.\""),
		])))
	# The roads the map shows but the story has not built yet: closed, each with its own excuse.
	ents.append(_closed_road("north_exit", Rect2i(CH_NORTH_GATE.x, 0, 1, 1), "mountain_base", &"crownhaven", &"north_gate",
		"The Mountain Road climbs north toward Mountain Base and the Pass beyond. A Royal Guard shakes his head. \"Closed by order of the crown. Landslides, they say. Soldiers, I say.\""))
	ents.append(_closed_road("east_exit", Rect2i(CH_W - 1, CH_EAST_GATE.y, 1, 1), "redrock_village", &"crownhaven", &"east_gate",
		"The Redrock road runs east into the red mesas of the Rocky Badlands. A chain hangs across it, and a notice: \"No caravans until the Badlands road is cleared of rockfalls. By order of the Guildhall.\""))
	ents.append(_closed_road("harbour_exit", Rect2i(CH_W - 1, CH_HARBOUR_GATE.y, 1, 1), "beach_village", &"crownhaven", &"harbour_gate",
		"The coast road slopes south-east toward Beach Village and the harbour. The gate warden waves you back: \"Ford's flooded below the city. Nothing's getting to the coast this week.\""))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	# No arrival narration: the location popup names the city, and nothing stops the hero's walk. The flag
	# is still set (quests and ambient talk key off "has been to Crownhaven"), silently.
	a.on_enter = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_ARRIVED, [_flag(F_ARRIVED)]),
	])
	_save(a, CONTENT + "areas/crownhaven/area.tres")


func _ch_scenery() -> Array:
	var out: Array = []
	out.append(_prop("keep", "keep", CH_KEEP.position, CH_KEEP.size, ALDERMERE_BLUE))
	out.append(_prop("barracks", "house", CH_BARRACKS.position, CH_BARRACKS.size, Color(0.55, 0.2, 0.16)))
	out.append(_prop("workshop", "house", CH_LAB.position, CH_LAB.size, Color(0.3, 0.38, 0.52)))
	# City roofs are slate -- blue-greys a shade apart (Oakvale is terracotta, Woodland Town moss).
	var roof_tints := [Color(0.3, 0.36, 0.48), Color(0.36, 0.4, 0.46), Color(0.28, 0.33, 0.42),
		Color(0.34, 0.38, 0.5), Color(0.4, 0.42, 0.48), Color(0.32, 0.35, 0.44)]
	for i in range(CH_HOUSES.size()):
		var r: Rect2i = CH_HOUSES[i]
		out.append(_prop("house_%d" % i, "house", r.position, r.size, roof_tints[i % roof_tints.size()]))
	# The walls' towers and the five gatehouses.
	for c in [Vector2i(3, 3), Vector2i(27, 3), Vector2i(3, 23), Vector2i(27, 23), Vector2i(10, 23), Vector2i(20, 23),
			Vector2i(3, 18), Vector2i(3, 8), Vector2i(27, 8), Vector2i(27, 20), Vector2i(21, 3)]:
		out.append(_prop("tower_%d_%d" % [c.x, c.y], "tower", c, Vector2i.ONE, ALDERMERE_BLUE))
	out.append(_prop("west_gatehouse", "gate", Vector2i(CH_GATE.x, CH_GATE.y - 1), Vector2i(1, 3), ALDERMERE_BLUE))
	out.append(_prop("north_gatehouse", "gate", Vector2i(CH_NORTH_GATE.x - 1, CH_NORTH_GATE.y), Vector2i(3, 1), ALDERMERE_BLUE))
	out.append(_prop("east_gatehouse", "gate", Vector2i(CH_EAST_GATE.x, CH_EAST_GATE.y - 1), Vector2i(1, 3), ALDERMERE_BLUE))
	out.append(_prop("south_gatehouse", "gate", Vector2i(CH_SOUTH_GATE.x - 1, CH_SOUTH_GATE.y), Vector2i(3, 1), ALDERMERE_BLUE))
	out.append(_prop("harbour_gatehouse", "gate", Vector2i(CH_HARBOUR_GATE.x, CH_HARBOUR_GATE.y - 1), Vector2i(1, 3), ALDERMERE_BLUE))
	# Lamps at the four corners of the river bridge's deck. (They stood on the banks, one cell off the bridge ends --
	# but lamps are solid and each bank is a one-cell strip, so a lamp there cut the strip in two and walled the south
	# gate's sign into its nook. On the deck's edge the middle lane stays open.)
	for lc in [Vector2i(CH_BRIDGE_X0, CH_RIVER_Y0), Vector2i(CH_BRIDGE_X1, CH_RIVER_Y0),
			Vector2i(CH_BRIDGE_X0, CH_RIVER_Y1), Vector2i(CH_BRIDGE_X1, CH_RIVER_Y1)]:
		out.append(_prop("bridge_lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
	# The new districts: a gabled inn, a gold-roofed guildhall, a blue-slate chapel, a forge.
	out.append(_prop("gilded_stag", "house", CH_INN.position, CH_INN.size, Color(0.62, 0.42, 0.16)))
	out.append(_prop("guildhall", "keep", CH_GUILD.position, CH_GUILD.size, Color(0.72, 0.55, 0.15)))
	out.append(_prop("chapel", "chapel", CH_CHAPEL.position, CH_CHAPEL.size, Color(0.3, 0.38, 0.6)))
	out.append(_prop("forge", "smithy", CH_SMITHY.position, CH_SMITHY.size, Color(0.3, 0.28, 0.3)))
	# The forge's barrels stand off Harbour Lane (they once sealed the arena corner off the street).
	out.append(_prop("forge_barrels", "barrels", Vector2i(22, 14), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("guild_banner_w", "banner", Vector2i(CH_GUILD.position.x, CH_GUILD.end.y), Vector2i.ONE, Color(0.72, 0.55, 0.15), true))
	out.append(_prop("guild_banner_e", "banner", Vector2i(CH_GUILD.end.x, CH_GUILD.end.y - 1), Vector2i.ONE, Color(0.72, 0.55, 0.15), true))
	out.append(_prop("inn_barrels", "barrels", Vector2i(6, 14), Vector2i.ONE, Color.WHITE, true))
	# Street lamps: the gate street, the keep courtyard and the workshop yard.
	# (The north-gate lamp stands in the barracks-side column at (8, 6), not mid-corridor at (10, 5): lamps are
	# solid, and with the two signs there it left no way from the gate to the town.)
	for lc in [Vector2i(5, 14), Vector2i(12, 10), Vector2i(18, 10), Vector2i(20, 14), Vector2i(26, 10), Vector2i(8, 6)]:
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
	out.append(_prop("dummy_a", "dummy", Vector2i(4, 7), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("dummy_b", "dummy", Vector2i(8, 8), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("barracks_barrels", "barrels", Vector2i(8, 10), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("pylon", "crystal", CH_PYLON, Vector2i.ONE, Color(0.5, 0.92, 1.0), true))
	out.append(_prop("market_barrels", "barrels", Vector2i(20, 15), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("market_cart", "cart", Vector2i(10, 15), Vector2i.ONE, Color(0.6, 0.75, 0.4), true))
	out.append(_prop("well", "well", Vector2i(21, 12), Vector2i.ONE, Color(0.36, 0.3, 0.26), true))
	return out


func _ch_people() -> Array:
	var out: Array = []
	out.append(_sign("town_sign", Vector2i(1, CH_GATE.y - 1), "Crownhaven",
		"CROWNHAVEN -- THE WEST GATE\nRoyal city of {KINGDOM}. Keep the peace.\nWest: the Sparse Forest and Woodland Town."))
	out.append(_sign("south_sign", Vector2i(CH_BRIDGE_X0 - 2, CH_RIVER_Y1 + 1), "Crownhaven",
		"CROWNHAVEN -- THE SOUTH GATE\nRoyal city of {KINGDOM}. Keep the peace.\nSouth: River Crossing, the Mossway and Oakvale."))
	out.append(_sign("east_gate_sign", Vector2i(CH_W - 2, CH_EAST_GATE.y - 1), "The Redrock Road",
		"EAST: THE ROCKY BADLANDS\nRedrock Village. Road closed to caravans."))
	out.append(_sign("harbour_gate_sign", Vector2i(CH_W - 2, CH_HARBOUR_GATE.y + 1), "The Coast Road",
		"SOUTH-EAST: BEACH VILLAGE\nThe harbour and the isles. Road closed -- the ford is flooded."))
	out.append(_sign("workshop_sign", Vector2i(21, 9), "The Royal Workshop",
		"THE ROYAL WORKSHOP\n{RESEARCHER_TITLE}. Knock loudly -- he will not hear you otherwise."))
	out.append(_sign("barracks_sign", Vector2i(9, 6), "The Barracks",
		"CROWNHAVEN GUARD -- BARRACKS\nRecruits drill at dawn."))
	out.append(_sign("notice_board", Vector2i(10, 11), "Notice Board",
		"By order of the crown: shards of bonding {STONE} are issued to chosen testers only. The sale, theft or copying of shards is forbidden.\nBelow, in smaller hand: \"Lost: one Petalfang. Answers to Biscuit.\""))

	# EVERY townsperson's talk is in dialogue.json (DialogueBank): areas.crownhaven.<id> -- the
	# entities here are their places and looks (and, for the General, his barracks line + spar).
	# The south gate's guards (the gate travellers from Oakvale use), flanking the avenue inside it.
	out.append(_npc("orwin", Vector2i(CH_SOUTH_GATE.x - 1, CH_SOUTH_GATE.y - 1), "east", "ORWIN", ALDERMERE_BLUE, "guard"))
	var gate2 := _npc("gate_guard", Vector2i(CH_SOUTH_GATE.x + 1, CH_SOUTH_GATE.y - 1), "west", "KEEP_GUARD", ALDERMERE_BLUE, "guard")
	gate2.display_name = "Gate Guard"
	gate2.speaker_name = "Gate Guard"
	out.append(gate2)

	# The keep's guards.
	for spec in [["keep_guard_w", Vector2i(13, 8)], ["keep_guard_e", Vector2i(16, 8)]]:
		out.append(_npc(spec[0], spec[1], "south", "KEEP_GUARD", Color(0.45, 0.4, 0.6), "guard"))

	# The barracks: the General (only once the opening is over) and a recruit.
	out.append(_general_in_crownhaven())
	out.append(_npc("lisk", Vector2i(5, 9), "east", "LISK", ALDERMERE_BLUE.lightened(0.15), "guard"))

	# The market.
	out.append(_npc("dalla", Vector2i(12, 11), "south", "DALLA", Color(0.7, 0.45, 0.3)))
	# THE MERCHANT (DECISIONS.md #28): at the end of the green-awning stall, between it and the well.
	out.append(_merchant("merchant", Vector2i(20, 12), "south", "MERCHANT", Color(0.3, 0.5, 0.36), SHOP_CROWNHAVEN))
	out.append(_npc("fenwick", Vector2i(17, 14), "west", "FENWICK", Color(0.4, 0.42, 0.48), "elder"))
	out.append(_npc("brisa", Vector2i(13, 15), "east", "BRISA", Color(0.45, 0.62, 0.4), "trainer"))
	var biscuit := NpcEntity.new()
	biscuit.id = &"biscuit"
	biscuit.cell = Vector3i(12, 15, 0)
	biscuit.facing = "east"
	biscuit.display_name = "Biscuit"
	biscuit.speaker_name = "Biscuit"
	biscuit.speaker_id = &"npc_biscuit"
	biscuit.visual_character = &"petalfang"
	out.append(biscuit)
	out.append(_npc("corin", Vector2i(19, 13), "west", "CORIN", Color(0.55, 0.5, 0.4)))
	out.append(_npc("kit", Vector2i(16, 16), "north", "KIT", Color(0.7, 0.55, 0.3), "child"))
	out.append(_npc("baker", Vector2i(14, 12), "south", "BAKER", Color(0.75, 0.62, 0.45)))

	# The workshop yard: the assistant. Professor Elias waits INSIDE the workshop (INTERIORS:
	# crownhaven_workshop, _workshop_people), where the ceremony and the kidnapping both happen.
	out.append(_npc("tam", Vector2i(26, 8), "west", "ASSISTANT", Color(0.5, 0.42, 0.6), "scholar"))
	return out


## The capital's built-out districts: the north gate, the Gilded Stag, the Merchants' Guildhall,
## the Chapel of the Starfall and the Aldermere Forge -- signs and people (their talk is in
## dialogue.json), no scripts.
func _ch_districts() -> Array:
	var out: Array = []
	# The north gate: the Mountain Road (closed).
	out.append(_sign("north_gate_sign", Vector2i(8, 5), "North Gate",
		"THE NORTH GATE\nThe Mountain Road: Mountain Base, and the Pass beyond it.\nClosed by order of the crown."))
	out.append(_npc("north_guard", Vector2i(10, 4), "west", "KEEP_GUARD", ALDERMERE_BLUE, "guard"))
	# The west gate: the Sparse Forest road to Woodland Town (barred until the opening is over).
	out.append(_npc("gate_warden", Vector2i(CH_GATE.x + 1, CH_GATE.y - 1), "south", "GATE_WARDEN", ALDERMERE_BLUE, "guard"))

	# The Gilded Stag (inn).
	out.append(_sign("inn_sign", Vector2i(10, 14), "The Gilded Stag",
		"THE GILDED STAG\nFeather beds, hot baths, a locked stable. Guests of the crown drink free."))
	out.append(_npc("maribel", Vector2i(10, 12), "west", "MARIBEL", Color(0.66, 0.42, 0.3), "villager"))

	# The Merchants' Guildhall.
	out.append(_sign("guild_sign", Vector2i(CH_GUILD.position.x - 1, CH_GUILD.end.y), "The Merchants' Guildhall",
		"MERCHANTS' GUILDHALL\nCharter of the Crown. Weights, measures and honest coin."))
	out.append(_npc("veyra", Vector2i(CH_GUILD.position.x + 1, CH_GUILD.end.y), "north", "VEYRA", Color(0.72, 0.55, 0.15), "noble"))

	# The Chapel of the Starfall.
	out.append(_sign("chapel_sign", Vector2i(22, 12), "Chapel of the Starfall",
		"THE CHAPEL OF THE STARFALL\nWhere the old star's dust was first gathered. All are welcome; silence is kindly requested."))
	out.append(_npc("odalys", Vector2i(26, 12), "west", "ODALYS", Color(0.78, 0.8, 0.9), "elder"))

	# The Aldermere Forge.
	out.append(_sign("forge_sign", Vector2i(25, 14), "The Aldermere Forge",
		"THE ALDERMERE FORGE\nArms for the Guard. Civilians: please don't touch the anvil. It bites."))
	# At his forge's door, on the east street (Harbour Lane past the forge stays clear to the gate).
	out.append(_npc("garrick", Vector2i(CH_SMITHY.end.x - 1, CH_SMITHY.position.y - 1), "north", "GARRICK", Color(0.4, 0.3, 0.26), "trainer"))

	# A courtier in the keep's shadow.
	out.append(_npc("merrow", Vector2i(19, 10), "west", "Lady Merrow", Color(0.52, 0.3, 0.5), "noble"))
	return out


## Professor Elias's look (a procedural figure until the Blender model lands).
const ELIAS_TINT := Color(0.28, 0.42, 0.55)


## The people inside the Royal Workshop (an interior): Elias waits there until the ceremony,
## with the starter options beside him during it.
func _workshop_people(size: Vector2i, door_x: int) -> Array:
	var out: Array = []
	var elias_cell := Vector2i(door_x, 2)
	var r := _npc("elias", elias_cell, "south", "RESEARCHER_TITLE", ELIAS_TINT, "elder")
	r.visual_character = ELIAS_MODEL
	# He is here until the raiders take him (the kidnapping plays in this room, right after the ceremony).
	r.visible_if = "not has(\"%s\")" % F_TAKEN
	r.on_interact = StoryCommand.list([IfCommand.make("not has(\"%s\")" % F_STARTER, _ceremony())])
	out.append(r)
	# The raiders (only during the kidnapping): PLACEHOLDER figures in Cindral red, who come in from the
	# room's east side (see [method _raid]).
	var raid_vis: String = "has(\"%s\") and not has(\"%s\")" % [F_ATTACK, F_FLED]
	for spec in [["raider_captain", Vector2i(WORKSHOP_EAST_X, 3)], ["raider_a", Vector2i(WORKSHOP_EAST_X, 4)],
			["raider_b", Vector2i(WORKSHOP_EAST_X, 5)]]:
		var raider := _npc(spec[0], spec[1], "west", "RAIDER_CAPTAIN" if spec[0] == "raider_captain" else "Raider",
			CINDRAL_RED, "raider")
		raider.visible_if = raid_vis
		out.append(raider)
	# Fellow shard testers (DECISIONS.md #51/#52), each with the creature they bonded: here for the
	# ceremony, still here after the kidnapping, gone once the opening is over. PLACEHOLDERS.
	var testers_vis: String = "not has(\"%s\")" % F_COMPLETE
	for t in CEREMONY_TESTERS:
		var key: String = String(t[0]).to_upper()
		var tester := _npc(t[0], t[1], "east", key, Color(0.42, 0.46, 0.36), "villager")
		tester.visible_if = testers_vis
		# TODO(story): a neutral placeholder line (owner: the professor hands shards out as tests).
		tester.on_interact = StoryCommand.list([_say([_line(t[0], key,
			"{RESEARCHER_TITLE} has been handing out shards to a few of us, to see how people bond.")])])
		out.append(tester)
		var partner := NpcEntity.new()
		partner.id = StringName(t[2])
		partner.cell = Vector3i(t[3].x, t[3].y, 0)
		partner.facing = "east"
		partner.display_name = _species_name(StringName(t[4]))
		partner.visual_character = StringName(t[4])
		partner.visible_if = testers_vis
		out.append(partner)
	# The starter options stand in a row either side of him (only during the ceremony).
	for i in range(STARTER_OPTIONS.size()):
		var k: int = i / 2 + 2
		var x: int = door_x - k if i % 2 == 0 else door_x + k
		x = clampi(x, 1, size.x)
		var cid: StringName = StringName(STARTER_OPTIONS[i]["character_id"])
		var starter := NpcEntity.new()
		starter.id = _starter_entity_id(i)
		starter.cell = Vector3i(x, 2 + (i / 6), 0)
		starter.facing = "south"
		starter.display_name = _starter_label(i)
		starter.visual_character = cid
		starter.visible_if = "has(\"%s\") and not has(\"%s\")" % [F_CEREMONY, F_STARTER]
		out.append(starter)
	return out


## The display label of starter option [param i] (its "label", else the species name).
func _starter_label(i: int) -> String:
	var label: String = String(STARTER_OPTIONS[i].get("label", ""))
	return label if not label.is_empty() else _species_name(StringName(STARTER_OPTIONS[i]["character_id"]))


## The ceremony's creature entity ids: "starter" (the default, STARTER_ID), then "starter_2", ...
static func _starter_entity_id(i: int) -> StringName:
	return &"starter" if i == 0 else StringName("starter_%d" % (i + 1))


## THE CEREMONY (the owner's opening), INSIDE the Royal Workshop: Professor Elias explains his new
## invention -- the stones that let a person bond with a creature -- the stone is yours, and you
## CHOOSE a starter from STARTER_OPTIONS (the first is the default; one option = no question).
## Then THE KIDNAPPING plays in the same room ([method _raid]) and the hero is handed the controls.
## TODO(story): every line here is a short neutral PLACEHOLDER -- the lore of the stones, the
## starters and the ceremony is not decided yet.
func _ceremony() -> Array:
	var out: Array = [
		_say([
			_line("elias", "RESEARCHER_TITLE", "Ah, {hero}. This is my new invention: the bonding shards -- stones that let a person bond with a creature."),
		]),
		_flag(F_CEREMONY),
	]
	for i in range(STARTER_OPTIONS.size()):
		out.append(_emote(String(_starter_entity_id(i)), "?"))
	out.append(_say([
		_line("elias", "RESEARCHER_TITLE", "This shard is yours now. Choose a partner."),
	]))
	out.append(_flag(F_SHARD))
	out.append(_toast("Received: Bonding Shard", "item"))
	# THE CHOICE: whatever STARTER_OPTIONS holds. The first option is the default -- what a test
	# or a no-host run picks. A single option needs no question.
	var picks: Array = []
	for i in range(STARTER_OPTIONS.size()):
		picks.append([
			_say([_narr("The %s steps to your side." % _starter_label(i))]),
			_flag(F_STARTER_PICK, i + 1),
			_join(StringName(STARTER_OPTIONS[i]["character_id"]), STARTER_NICKNAME, 0, F_STARTER),
		])
	if picks.size() == 1:
		out.append_array(picks[0])
	elif picks.size() > 1:
		var ask := ChoiceCommand.new()
		ask.prompt = _line("elias", "RESEARCHER_TITLE", "Which one will you choose?")
		var opts: Array = []
		for i in range(picks.size()):
			opts.append(ChoiceOption.make(_starter_label(i), picks[i]))
		ask.options = StoryCommand.list(opts)
		out.append(ask)
	out.append_array(_raid())
	return out


## THE KIDNAPPING (the owner's rework), in the Royal Workshop right after the ceremony: placeholder
## enemy soldiers appear IN THE ROOM and take Professor Elias; at the same moment enemies are
## attacking the city as a distraction, and the raiders then run to escape (to burn Oakvale, which
## the ruins show). Short on purpose -- a couple of moves, an emote, two lines and one narration --
## and then the hero has the controls: nothing forces him anywhere. The way to Oakvale is the open
## road (the Mossway's west end leads to the burned village once `opening.attack` is set).
## Also what the workshop's on_enter resumes for a journey saved between the ceremony and the end.
## TODO(story): the lines are neutral PLACEHOLDERS.
func _raid() -> Array:
	return [
		# The raiders (visible_if on this flag) are in the room, at its east side.
		_flag(F_ATTACK),
		_emote("elias", "!"),
		_emote("player", "!"),
		_move("raider_captain", Vector2i(7, 3)),
		_move("raider_a", Vector2i(5, 3)),
		_move("raider_b", Vector2i(5, 4)),
		_face("elias", "toward:raider_captain"),
		_face("player", "toward:raider_captain"),
		_say([
			_line("raider_captain", "RAIDER_CAPTAIN", "{RESEARCHER_TITLE}. You're coming with us."),
			_line("elias", "RESEARCHER_TITLE", "{hero} -- keep that shard safe!"),
		]),
		# Elias is gone (his entity is hidden by this flag), and the raiders run for it.
		_flag(F_TAKEN),
		_move("raider_captain", Vector2i(WORKSHOP_EAST_X, 3)),
		_flag(F_FLED),
		_flag("act1.researcher_abducted"),
		_say([_narr("Bells are ringing across Crownhaven: enemy soldiers are attacking the city -- a distraction, so the raiders can slip away.")]),
		_flag(F_CHASE),
		# Whiteouts from here wake you in the ruins (the first fight waits there).
		_respawn(&"oakvale_ruins", &"wayshrine"),
		SaveGameCommand.new(),
	]


## General Varden at the barracks -- only once the opening is over (the hero first meets him in
## burned Oakvale, so he is not standing here before that). His script: a short line (the first talk
## also sets the legacy F_ACT1_MET flag), then the sparring offer.
## TODO(story): placeholder wording -- only the owner's facts (preparing for war; get stronger).
func _general_in_crownhaven() -> NpcEntity:
	var general := _npc("general", Vector2i(7, 9), "south", "GENERAL", ALDERMERE_BLUE, "officer")
	general.visual_character = VARDEN_MODEL
	general.visible_if = "has(\"%s\")" % F_COMPLETE
	general.on_interact = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_ACT1_MET, [
			_say([
				_line("general", "GENERAL", "We're preparing for war, {hero}."),
				_line("general", "GENERAL", "Get stronger. Talk to me again if you want a sparring bout."),
			]),
			_flag(F_ACT1_MET),
		], [
			_say([_line("general", "GENERAL", "Keep getting stronger.")]),
			_general_spar_offer(),
		]),
	])
	return general


## THE EXAMPLE SPAR (DECISIONS.md #29): a friendly bout with the General's Geode, repeatable -- once
## per rest, like every sparring partner (DECISIONS.md #33). It is tagged `spar`, so nobody falls
## for good in it, even in a Classic journey -- a knocked-out partner just gets back up
## (StoryRuleset.spar_ko_recovers). He heads the barracks' roster (the strongest of the three).
func _general_spar_offer() -> IfCommand:
	return _spar_partner_offer(SPAR_GENERAL_ID, "general", "GENERAL", "{GENERAL}",
		[{"character_id": GENERAL_UNIT, "strength": 0.8, "level": LV_SPAR_GENERAL}],
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
#  duel ruleset's story format) against the opponent's TEAM -- Fenna, Lyra, the Cup's later
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
	spec.enemy_level = LV_FENNA
	spec.clash_intro = true
	t.battle = spec
	return t


## THE AMBUSH (DECISIONS.md #7 / #33 "attacked by criminals"): once you have spoken to the General at
## the barracks (F_ACT1_MET, legacy key act1.met_rowan), bandits wait at the brook's plank bridge -- the only crossing, so the trigger
## cannot be walked round. Two self-defence duels back to back (HP carries between them), REAL
## battles: a loss whites out (the bandits wait for you again; a beaten footpad stays beaten) and a
## Classic partner knocked out in them falls. Winning pays a purse and a stolen draught.
func _ambush() -> Array:
	var out: Array = []
	var vis: String = "has(\"%s\") and not has(\"%s\")" % [F_AMBUSH_SPRUNG, F_AMBUSH_CLEARED]
	var nell := _npc("nell", Vector2i(22, 4), "south", "BANDIT_BOSS", Color(0.3, 0.26, 0.22), "raider")
	nell.visible_if = vis
	# Her idle line is in dialogue.json (areas.mossway.nell).
	out.append(nell)
	var pad := _npc("footpad", Vector2i(20, 8), "north", "FOOTPAD", Color(0.36, 0.3, 0.24), "raider")
	pad.visible_if = vis
	out.append(pad)

	var footpad_spec := _duel_spec("mossway.ambush.footpad", "{FOOTPAD}", &"npc_footpad",
		[{"character_id": "mycothrall", "strength": 0.9}], false, BattleSpec.DefeatPolicy.WHITEOUT,
		40, [], [F_AMBUSH_FOOTPAD])
	footpad_spec.enemy_level = LV_FOOTPAD
	var nell_spec := _duel_spec("mossway.ambush.nell", "{BANDIT_BOSS}", &"npc_nell",
		[{"character_id": "petalfang", "strength": 1.0}], false, BattleSpec.DefeatPolicy.WHITEOUT,
		180, ["dawnpetal_draught"])
	nell_spec.enemy_level = LV_BANDIT_BOSS
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
## Lyra waits beside the south gate's avenue (the road home to Oakvale comes in there now).
const CH_LYRA_START := Vector2i(CH_SOUTH_GATE.x + 2, CH_SOUTH_GATE.y - 2)
## By the arena: on the market street, reached from Harbour Lane behind them as well as the street.
const CH_LYRA_ARENA := Vector2i(23, 18)
const CH_CHAMPION := Vector2i(25, 18)


## The friendly RIVAL's duel spec: Lyra's Blightcap, a FRIENDLY (DECISIONS.md #29: rival friendlies never
## cost a life), scaling +8% per rival duel fought (rival.stage, up to 6) -- the first duel is
## stage 0.
func _rival_spec() -> BattleSpec:
	var spec := _duel_spec(RIVAL_DUEL_ID, "{LYRA}", &"npc_lyra",
		[{"character_id": "blightcap", "strength": 0.9}, {"character_id": "petalfang", "strength": 0.75}],
		true, BattleSpec.DefeatPolicy.CONTINUE, 60)
	spec.enemy_level = LV_RIVAL
	spec.clash_intro = true
	spec.scale_flag = F_RIVAL_STAGE
	spec.scale_step = 0.08
	spec.scale_max_steps = 6
	return spec


## After any rival duel that was FOUGHT: the stage counter (the next rematch is stronger), the win
## counter, and Lyra's line.
func _rival_after(win: Array, lose: Array) -> Array:
	return [
		IfCommand.make(FOUGHT, [
			_inc(F_RIVAL_STAGE),
			IfCommand.make("outcome() == \"victory\"", [_inc(F_RIVAL_WINS), _say(win)], [_say(lose)]),
		]),
	]


func _rival() -> Array:
	var out: Array = []
	var lyra := _npc("lyra", CH_LYRA_START, "west", "LYRA", Color(0.78, 0.5, 0.2), "trainer")
	# Never while she is away in Deepwood Village (LYRA_IN_DEEPWOOD: one Lyra at a time).
	lyra.visible_if = "has(\"%s\") and not has(\"%s\") and not (%s)" % [F_COMPLETE, F_RIVAL_DUEL1, LYRA_IN_DEEPWOOD]
	# Her waiting line is in dialogue.json (areas.crownhaven.lyra).
	out.append(lyra)

	# OPT-IN, not an ambush: Lyra waits by the gate and the bout starts only when you talk to her (her
	# waiting line is the bank's, then this offer). The old meeting speeches are cut.
	var first: Array = [
		_flag(F_RIVAL_MET),
		_duel(_rival_spec()),
	]
	first.append_array(_rival_after([
		_line("lyra", "LYRA", "...Huh. You got me. That was a good test."),  # TODO(story)
	], [
		_line("lyra", "LYRA", "That was a good test. We'll both be better for it."),  # TODO(story)
	]))
	first.append(IfCommand.make(FOUGHT, [
		_say([
			_line("lyra", "LYRA", "I'll be at the Crown Arena. Come find me when you want to test each other again."),  # TODO(story)
		]),
		_flag(F_RIVAL_DUEL1),
		_toast("Rival: {LYRA}"),
		SaveGameCommand.new(),
	], [
		# TODO(story)
		_say([_line("lyra", "LYRA", "Your partner can barely stand. Rest up first -- we'll test each other after.")]),
	]))
	var offer := ChoiceCommand.new()
	offer.prompt = _line("lyra", "LYRA", "I'm {LYRA}. One friendly bout, to test each other -- ready?")  # TODO(story)
	offer.options = StoryCommand.list([ChoiceOption.make("Let's go.", first), ChoiceOption.make("Not now.", [], true)])
	lyra.on_interact = StoryCommand.list([offer])

	# By the arena after the first duel: rematches, once per rest, stronger every time.
	var lyra2 := _npc("lyra_arena", CH_LYRA_ARENA, "south", "LYRA", Color(0.78, 0.5, 0.2), "trainer")
	lyra2.visible_if = "has(\"%s\") and has(\"%s\") and not (%s)" % [F_COMPLETE, F_RIVAL_DUEL1, LYRA_IN_DEEPWOOD]
	var ask := ChoiceCommand.new()
	ask.prompt = _line("lyra_arena", "LYRA", "Ready to test each other again? Rematch?")  # TODO(story)
	var yes_cmds: Array = [_duel(_rival_spec())]
	yes_cmds.append_array(_rival_after([
		_line("lyra_arena", "LYRA", "Good bout. You're getting strong."),  # TODO(story)
	], [
		_line("lyra_arena", "LYRA", "Good bout. We both learned something."),  # TODO(story)
	]))
	ask.options = StoryCommand.list([ChoiceOption.make("Rematch!", yes_cmds), ChoiceOption.make("Not now.", [], true)])
	lyra2.on_interact = StoryCommand.list([
		IfCommand.make("spar_ready(\"%s\")" % RIVAL_DUEL_ID, [ask], [
			# TODO(story)
			_say([_line("lyra_arena", "LYRA", "My partner needs a rest. Go to the Wayshrine -- then we go again.")]),
		]),
	])
	out.append(lyra2)
	return out


## The barracks' SPARRING ROSTER (rising strength): Corporal Wynn (warm-up), Lieutenant Aldous,
## and the General himself (see [method _general_spar_offer]). Each ready once per rest.
func _spar_partners() -> Array:
	var out: Array = []
	var after: String = "has(\"%s\")" % F_COMPLETE
	var wynn := _npc("wynn", Vector2i(4, 10), "east", "WYNN", ALDERMERE_BLUE.lightened(0.1), "guard")
	wynn.visible_if = after
	wynn.on_interact = StoryCommand.list([_spar_partner_offer(SPAR_WYNN_ID, "wynn", "WYNN", "{WYNN}",
		[{"character_id": "blightcap", "strength": 0.8, "level": LV_SPAR_WYNN}],
		"Fancy a warm-up bout? My Blightcap's the gentlest thing in the barracks. Mostly.",
		"Good form! Now go and try the Lieutenant.",
		"Don't sulk -- everyone loses to the Blightcap once. It's the spores.",
		"Blightcap's having a lie-down. Get some rest yourself and come back.")])
	out.append(wynn)
	var aldous := _npc("aldous", Vector2i(6, 7), "south", "ALDOUS", ALDERMERE_BLUE.darkened(0.1), "officer")
	aldous.visible_if = after
	aldous.on_interact = StoryCommand.list([_spar_partner_offer(SPAR_ALDOUS_ID, "aldous", "ALDOUS", "{ALDOUS}",
		[{"character_id": "petalfang", "strength": 0.95, "level": LV_SPAR_ALDOUS}],
		"The General says you're worth watching. Show me. A friendly bout, no quarter asked.",
		"Hm. He was right. Once more some other day.",
		"Speed. You lack it. Come back when you've found some.",
		"My Petalfang has had enough for today. Rest, and we'll go again.")])
	out.append(aldous)
	out.append(_sign("roster_sign", Vector2i(8, 7), "Sparring Roster",
		"BARRACKS SPARRING ROSTER\nCpl. Wynn -- warm-up bouts.\nLt. Aldous -- for the sharp.\nGen. Varden -- ask if you dare.\nOne bout each per rest. Friendly: nobody is hurt for real."))
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
		spec.enemy_level = LV_CUP_ROUNDS[mini(i, LV_CUP_ROUNDS.size() - 1)]
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
	spec.enemy_level = LV_CHAMPION_REMATCH
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
#  The Sparse Forest -- the road west from Crownhaven to Woodland Town
# =====================================================================================
#
# A short ROUTE (the world map's Sparse Forest lies between the capital and Woodland Town): open
# woodland, a winding cart track, wild grass (its own encounter table -- the forest's creatures),
# a woodsman's clearing. Its east end opens on Crownhaven's west gate, its west end on Woodland
# Town's east road. Only reachable once the opening is over (the west gate is barred until then).

const SF_W := 28
const SF_H := 12
const SF_ROAD_Y := 6
const SF_GRASS := [Rect2i(3, 2, 4, 3), Rect2i(10, 7, 5, 3), Rect2i(17, 2, 5, 3), Rect2i(22, 8, 4, 2)]
## Kept clear of the scatter trees (the signs, the woodsman, his logs and the ground around them).
const SF_CLEAR := [Rect2i(1, 4, 3, 3), Rect2i(23, 4, 4, 3), Rect2i(13, 2, 4, 3)]


func _sf_path_y(x: int) -> int:
	if x < 8:
		return SF_ROAD_Y
	if x < 16:
		return SF_ROAD_Y - 1
	if x < 22:
		return SF_ROAD_Y + 1
	return SF_ROAD_Y


func _sf_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if y <= 1 or y >= SF_H - 1:
		return "tree"
	if x == 0 or x == SF_W - 1:
		return "forest_dirt" if y == SF_ROAD_Y else "tree"
	# The cart track, with its kinks where it bends round the thickets.
	var py: int = _sf_path_y(x)
	var prev: int = _sf_path_y(x - 1)
	if y >= mini(py, prev) and y <= maxi(py, prev):
		return "forest_dirt"
	if _in(SF_GRASS, c):
		return "tall_grass"
	if _in(SF_CLEAR, c):
		return "grass_plains"
	# Sparse woodland: trees here and there, never on the track's verge.
	if absi(y - py) > 1 and _h(x, y, 41) < 0.22:
		return "tree"
	return "grass_plains"


func _build_sparse_forest() -> void:
	var t := _new_map("The Sparse Forest", SF_W, SF_H,
		"The Sparse Forest: open woodland on the road west from Crownhaven to Woodland Town. Story-mode terrain.")
	t.lighting_preset = "Day"
	_paint(t, _sf_terrain)
	_add_validator_anchors(t, Vector2i(1, SF_ROAD_Y), Vector2i(SF_W - 2, SF_ROAD_Y))
	_save(t, CONTENT + "areas/sparse_forest/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"sparse_forest"
	a.display_name = "The Sparse Forest"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "sparse_forest")
	a.terrain = load(CONTENT + "areas/sparse_forest/terrain.tres")
	a.entry_points = {
		"west": {"cell": [1, SF_ROAD_Y, 0], "facing": "east"},
		"east": {"cell": [SF_W - 2, SF_ROAD_Y, 0], "facing": "west"},
	}
	var ents: Array = []
	ents.append(_sign("west_sign", Vector2i(2, SF_ROAD_Y - 1), "The Sparse Forest",
		"THE SPARSE FOREST\nWest: Woodland Town.  East: Crownhaven."))
	ents.append(_sign("east_sign", Vector2i(SF_W - 3, SF_ROAD_Y - 1), "The Sparse Forest",
		"THE SPARSE FOREST\nWest: Woodland Town, a morning's walk.  East: Crownhaven's west gate.\nMind the grass -- the forest's creatures are bolder than the Mossway's."))
	ents.append(_prop("woodpile", "logs", Vector2i(13, 3), Vector2i(2, 1), Color(0.6, 0.44, 0.26), true))
	# The woodsman's talk is in dialogue.json (areas.sparse_forest.alder).
	ents.append(_npc("alder", Vector2i(15, 3), "south", "WOODSMAN", Color(0.4, 0.46, 0.28), "villager"))
	ents.append(_warp("west_exit", Rect2i(0, SF_ROAD_Y, 1, 1), &"woodland_town", &"east_road"))
	ents.append(_warp("east_exit", Rect2i(SF_W - 1, SF_ROAD_Y, 1, 1), &"crownhaven", &"west_gate"))
	_add_doors(a, ents)
	a.entities = _entities(ents)

	var zone := EncounterZone.new()
	var ids: Array[StringName] = [&"tall_grass"]
	zone.tile_ids = ids
	zone.rate = 0.12
	zone.grace_steps = 3
	var table: Array[Resource] = []
	for pair in [["petalfang", 2.0], ["blightcap", 2.0], ["mycothrall", 1.5], ["tree_grunt", 1.0]]:
		var e := EncounterEntry.new()
		e.character_id = StringName(pair[0])
		e.weight = pair[1]
		e.kind = EncounterEntry.Kind.DUEL
		e.can_befriend = true
		table.append(e)
	zone.table = table
	var zones: Array[Resource] = [zone]
	a.encounter_zones = zones
	_save(a, CONTENT + "areas/sparse_forest/area.tres")


# =====================================================================================
#  Woodland Town -- the timber town at the edge of the Sparse Forest / Deep Woods
# =====================================================================================
#
# A rustic forest town, deliberately NOT a village or a castle: no wall, no flagstone plaza -- a
# boardwalk square, log cabins under mossy roofs, a stream with a plank bridge splitting a quiet
# WEST BANK (herbalist, archery range, the sacred glade, an unmarked trail south and the road on to
# Deepwood Village) from the busy EAST BANK (the Wardens' Lodge, the Stumped Hart inn, Timber Row's
# trading post and forge, the lumber yard and the sawmill). It sits in a clearing: dense woods close
# in on every side but the roads. Reached from the Sparse Forest (the east end, entry `east_road`);
# the west road leads to Deepwood Village (THE DEEP WOODS, below -- held until Warden Hale opens it);
# the north trail (Frostpeak Village, under the Snowy Peaks) and the south trail (the Hidden Thieves
# Guild -- never named in town) are placeholders for the later regions (their warps target this town
# and never open yet).

const WT_W := 28
const WT_H := 24
const WT_ROAD_Y := 12
const WT_STREAM_X := 7
## The north trail climbs out of town between the Lodge and the inn, toward the snowline.
const WT_NORTH_X := 17
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
const WT_TREES := [Vector2i(9, 4), Vector2i(8, 8), Vector2i(19, 4), Vector2i(9, 20), Vector2i(8, 15),
	Vector2i(9, 13), Vector2i(20, 5), Vector2i(2, 3), Vector2i(2, 7), Vector2i(21, 21), Vector2i(10, 21)]


func _wt_buildings() -> Array:
	return [WT_LODGE, WT_INN, WT_POST, WT_SMITHY, WT_SAWMILL, WT_HERB, WT_HUNT] + WT_HOMES


func _wt_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	# The roads out: east to the Sparse Forest, west toward Deepwood Village, the north trail up to
	# Frostpeak, and the south trail.
	if x == 0 or x == WT_W - 1:
		return "forest_dirt" if y == WT_ROAD_Y else "tree"
	if x == WT_NORTH_X and y <= WT_ROAD_Y - 2:
		return "forest_dirt"
	if absi(x - WT_NORTH_X) == 1 and y >= 1 and y <= 3:
		return "grass_plains"
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
	# (No tall grass in town: a town has no wild encounters, so grass that never rustles would lie.)
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
	_place(a, "woodland_town")
	a.terrain = load(CONTENT + "areas/woodland_town/terrain.tres")
	a.entry_points = {
		"east_road": {"cell": [WT_W - 2, WT_ROAD_Y, 0], "facing": "west"},
		"wayshrine": {"cell": [WT_SHRINE.x, WT_SHRINE.y + 1, 0], "facing": "north"},
		"west_road": {"cell": [1, WT_ROAD_Y, 0], "facing": "east"},
		"north_trail": {"cell": [WT_NORTH_X, 1, 0], "facing": "south"},
	}
	var ents: Array = []
	ents.append_array(_wt_scenery())
	ents.append(_shrine(WT_SHRINE, "Woodland Wayshrine"))
	ents.append_array(_wt_people())
	# Roads: east through the Sparse Forest to Crownhaven; west to Deepwood Village (below); the north
	# trail (Frostpeak Village) and the south trail (the Hidden Thieves Guild) are the next chapters --
	# their warps target this town and never open yet.
	ents.append(_warp("east_exit", Rect2i(WT_W - 1, WT_ROAD_Y, 1, 1), &"sparse_forest", &"west"))
	ents.append(_closed_road("north_exit", Rect2i(WT_NORTH_X, 0, 1, 1), "frostpeak_village", &"woodland_town", &"north_trail",
		"The trail north climbs out of the pines toward the snowline, where Frostpeak Village sits under the Snowy Peaks. A Warden's chain is drawn across it, hung with a frosted board: \"High trail closed -- snow. Open at the thaw.\""))
	# The west road to Deepwood Village (the Deep Woods, built below): held by the Wardens' rope until
	# Warden Hale opens it ([method _wt_people]: talk to him at the Lodge).
	ents.append(_warp("west_exit", Rect2i(0, WT_ROAD_Y, 1, 1), &"deepwood_village", &"east_road", "",
		"has(\"%s\")" % F_DEEPWOOD_OPEN, _scene("wt_west_locked", [
			_narr("The road west thins to a deer track and then to nothing. Somewhere beyond the thorns lies Deepwood Village -- but the Wardens have strung a rope across the track with a painted warning: \"No travellers. Ask at the Lodge.\""),
		])))
	ents.append(_warp("south_exit", Rect2i(4, WT_H - 1, 1, 1), &"woodland_town", &"wayshrine", "",
		"has(\"world.thieves_guild_open\")", _scene("wt_south_locked", [
			_narr("A narrow trail slips south between the roots, toward a cave mouth nobody here admits to knowing. Fresh boot prints say the way is kept open from the other end. A rockfall blocks it for now."),
		])))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	# No arrival narration (the location popup names the town); the flag is set silently (ambient
	# talk keys off "rests since arriving").
	a.on_enter = StoryCommand.list([
		IfCommand.make("not has(\"woodland.arrived\")", [_flag("woodland.arrived")]),
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
	out.append(_prop("logs_b", "logs", Vector2i(18, 17), Vector2i(3, 1), Color(0.56, 0.4, 0.24), true))
	out.append(_prop("logs_c", "logs", Vector2i(20, 19), Vector2i(3, 1), Color(0.66, 0.5, 0.3), true))
	out.append(_prop("logs_d", "logs", Vector2i(21, 15), Vector2i(2, 1), Color(0.6, 0.44, 0.26), true))
	out.append(_prop("timber_cart", "cart", Vector2i(21, 17), Vector2i.ONE, Color(0.55, 0.4, 0.22), true))
	out.append(_prop("yard_barrels", "barrels", Vector2i(22, 18), Vector2i.ONE, Color.WHITE, true))
	# The herb garden, the archery range, the camp fire.
	out.append(_prop("herb_garden", "crops", WT_GARDEN.position, WT_GARDEN.size, Color(0.28, 0.5, 0.34)))
	out.append(_prop("garden_fence", "fence", Vector2i(3, 16), Vector2i(3, 1), Color(0.45, 0.33, 0.2), true))
	# (The two targets stand one row up, either side of the archer at (4, 7): dummies are solid, and at (3, 8) / (5, 8)
	# they sealed the cell in front of the archer -- the range itself -- off on all four sides.)
	out.append(_prop("target_a", "dummy", Vector2i(3, 7), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("target_b", "dummy", Vector2i(5, 7), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("campfire", "fire", Vector2i(13, 19), Vector2i.ONE, Color.WHITE, true))
	# The square: lamps at its corners, the Wardens' green banners at the Lodge path, a well.
	for lc in [Vector2i(10, 11), Vector2i(16, 11), Vector2i(10, 14), Vector2i(16, 14), Vector2i(8, 11), Vector2i(8, 13)]:
		out.append(_prop("lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.78, 0.4), true))
	out.append(_prop("banner_w", "banner", Vector2i(11, 9), Vector2i.ONE, Color(0.24, 0.44, 0.28), true))
	out.append(_prop("banner_e", "banner", Vector2i(14, 9), Vector2i.ONE, Color(0.24, 0.44, 0.28), true))
	out.append(_prop("well", "well", Vector2i(15, 10), Vector2i.ONE, Color(0.3, 0.38, 0.22), true))
	out.append(_prop("woodpile_inn", "logs", Vector2i(16, 8), Vector2i.ONE, Color(0.58, 0.42, 0.24), true))
	return out


func _wt_people() -> Array:
	var out: Array = []
	var cloak_green := Color(0.28, 0.44, 0.3)
	# --- Signs ---------------------------------------------------------------------------------
	out.append(_sign("town_sign", Vector2i(WT_W - 2, WT_ROAD_Y + 1), "Woodland Town",
		"WOODLAND TOWN\nTimber, tolls and tall tales.\nEast: the Sparse Forest and Crownhaven.  West: Deepwood Village (road closed).\nNorth: Frostpeak Village (trail closed)."))
	out.append(_sign("north_trail_sign", Vector2i(WT_NORTH_X - 1, 2), "The High Trail",
		"NORTH: FROSTPEAK VILLAGE\nThe high trail, under the Snowy Peaks. Closed till the thaw -- by order of the Wardens."))
	out.append(_sign("lodge_sign", Vector2i(10, 9), "The Wardens' Lodge",
		"THE WARDENS' LODGE\nTolls, maps, and the loan of a lantern. Ask for Warden Hale."))
	out.append(_sign("inn_sign", Vector2i(18, 11), "The Stumped Hart",
		"THE STUMPED HART\nA stump for a stool, a stag for a sign. Venison pie daily."))
	out.append(_sign("yard_sign", Vector2i(18, 13), "Lumber Yard",
		"HAMMOND & DAUGHTERS -- LUMBER\nCut green, sold dry.\nDo not lean on the stacks."))
	out.append(_sign("deepwood_sign", Vector2i(2, WT_ROAD_Y + 1), "To Deepwood",
		"WEST: DEEPWOOD VILLAGE\nThe road is closed by the Wardens. Ask at the Lodge."))
	out.append(_sign("trail_sign", Vector2i(5, 19), "The South Trail",
		"A hand-lettered board nailed to a root:\n\"NOT A ROAD. Not a trail. Not your business.\""))
	out.append(_sign("standing_stone", Vector2i(3, 17), "The Starfall Stone",
		"A knee-high stone, furred with moss and scored with old marks. Fresh flowers lie before it. It hums very faintly, like a held note.", "stone"))

	# EVERY townsperson's talk is in dialogue.json (DialogueBank): areas.woodland_town.<id>.
	# --- East bank: the Lodge, the inn, Timber Row, the lumber yard --------------------------
	var hale := _npc("hale", Vector2i(12, 9), "south", "HALE", cloak_green, "officer")
	# The Deepwood road (DECISIONS.md #40): the sign says "Ask at the Lodge" -- asking him (after the
	# opening) opens it. His talk is the bank's; this runs after it.
	# TODO(story): placeholder narration -- the owner has not said why the road opens.
	hale.on_interact = StoryCommand.list([
		IfCommand.make("has(\"%s\") and not has(\"%s\")" % [F_COMPLETE, F_DEEPWOOD_OPEN], [
			_say([_narr("{HALE} writes your name in the Lodge's ledger and sends a Warden to take down the rope across the west road.")]),
			_flag(F_DEEPWOOD_OPEN),
			_toast("The road to Deepwood Village is open"),
		]),
	])
	out.append(hale)
	out.append(_npc("bryn", Vector2i(19, 11), "south", "BRYN", Color(0.6, 0.38, 0.28), "villager"))
	out.append(_merchant("sedge", Vector2i(23, 11), "south", "SEDGE", Color(0.4, 0.34, 0.2), SHOP_WOODLAND))
	out.append(_npc("burr", Vector2i(26, 11), "west", "BURR", Color(0.36, 0.28, 0.24), "trainer"))
	out.append(_npc("torvald", Vector2i(19, 16), "east", "TORVALD", Color(0.5, 0.3, 0.2), "trainer"))
	out.append(_npc("road_warden", Vector2i(WT_W - 3, WT_ROAD_Y + 1), "north", "ROAD_WARDEN", cloak_green, "guard"))
	out.append(_npc("fern", Vector2i(11, 13), "south", "FERN", Color(0.5, 0.6, 0.35), "child"))

	# --- West bank: the herbalist, the archery range, the glade ----------------------------------
	out.append(_npc("ilse", Vector2i(4, 11), "south", "ILSE", Color(0.34, 0.52, 0.4), "scholar"))
	out.append(_npc("ferra", Vector2i(4, 7), "south", "FERRA", Color(0.34, 0.42, 0.26), "trainer"))
	out.append(_npc("wicke", Vector2i(3, 18), "east", "WICKE", Color(0.7, 0.68, 0.74), "elder"))

	# --- The camp on the south lane ------------------------------------------------------------
	out.append(_npc("stranger", Vector2i(12, 19), "east", "STRANGER", Color(0.2, 0.18, 0.22), "raider"))

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


# =====================================================================================
#  THE DEEP WOODS (DECISIONS.md #38-#41, #50, #56, #67, #71, #74, #75, #80, #81, #85, #88)
# =====================================================================================
#
#   Woodland Town's west road (opened by Warden Hale at the Lodge: world.deepwood_open)
#     -> DEEPWOOD VILLAGE: Nyra's tree-house clan village (#85) -- a Wayshrine, Nyra (the Deepwood
#        CHIEF: a scaled DUEL, #50 / #80), a few villagers (one bank line each), and Lyra (#88), here
#        from the moment the road opens until the Eldroot battle is won.
#     -> beating NYRA grants the tree-felling FIELD MOVE (#40 / #41: fieldmove.treefell) and opens
#        the trail north (world.depths_of_the_wood_open: "to go through the forest the hero must first
#        fight Nyra").
#     -> THE DEPTHS OF THE WOOD: forest, tall grass (the Deep Woods' creatures), and BREAKABLE TREES
#        (FieldObstacleEntity) -- one hides the way to the glade at the forest's heart, where ELDROOT
#        waits: a TACTICAL legend battle (#74), FIXED above the band (#81), with Lyra fighting beside
#        you as a guest (#56 / #74). Win -> the OPTIONAL bond (#75): a legend goes into the journey's
#        legend list (StoryState.legends), never the party (#39).
#
# All lines here are short neutral PLACEHOLDERS (TODO(story)) -- the owner's facts only.

## Flags (save keys -- never rename once shipped).
const F_DEEPWOOD_OPEN := "world.deepwood_open"
const F_DEPTHS_OPEN := "world.depths_of_the_wood_open"
const F_NYRA_BEATEN := "deepwood.nyra_beaten"
## The tree-felling field move is granted (FieldMoveResource.unlock_flag).
const F_TREEFELL := "fieldmove.treefell"
const F_ELDROOT_BEATEN := "deepwood.eldroot_beaten"
const F_ELDROOT_BONDED := "legend.eldroot.bonded"
## Encounter ids (save keys).
const NYRA_DUEL_ID := "deepwood.chief.nyra"
const ELDROOT_BATTLE_ID := "deepwood.legend.eldroot"
## Lyra is IN DEEPWOOD from the moment the road opens until the Eldroot battle is won; every other
## Lyra (Crownhaven's south gate and arena) hides meanwhile -- one Lyra at a time. (The workshop's
## ceremony Lyra is gone once the opening is over, and the road only opens after it.)
const LYRA_IN_DEEPWOOD := "has(\"opening.complete\") and has(\"world.deepwood_open\") and not has(\"deepwood.eldroot_beaten\")"

## THE FIELD MOVE (DECISIONS.md #41 / #71): id (its .tres under content/field_moves/), and who can use
## it. KNOBS: the species list (forms or evolution lines; the starter options are all here, so every
## journey has a user) and whether the hero can use it himself (#71: "possibly").
const FIELD_MOVE_TREES_ID := "treefell"
const FIELD_MOVE_TREES_SPECIES: Array[String] = ["tree_grunt", "oakheart", "vineweave", "petalfang", "blightcap"]
const FIELD_MOVE_TREES_HERO := false

## NYRA, the Deepwood chief (DECISIONS.md #85): a DUEL (#50), SCALED inside the Deep Woods band (#80)
## at this offset from the party's top level. PLACEHOLDER team (nature roster creatures; Eldroot is
## the legend, never hers) -- her FINAL creature is the one she uses the stone with (#38 / #67).
const NYRA_SCALE_OFFSET := 1
const NYRA_TEAM: Array[String] = ["petalfang", "vineweave", "oakheart"]
## TODO(bond): stone boost -- the bond / stone system is not built (#38 / #65 / #67). Until it is, her
## FINAL creature gets this small authored strength bump (the duel's stat multiplier).
const NYRA_STONE_BOOST := 1.15
const NYRA_PURSE := 400

## ELDROOT: the legend's TACTICAL board (a forest glade). The party fields up to ELDROOT_SQUAD_SIZE;
## Lyra joins as a GUEST (a player-0 turn-1 Reinforcement, like the first fight's allies).
const ELDROOT_MAP_PATH := CONTENT + "battles/ow_deepwood_glade.tres"
const ELDROOT_SQUAD_SIZE := 3
## TODO(humans): swap to "lyra" + deploy picker -- Lyra as a real battle unit and a deployable squad
## pick (#56 / #74) come with the humans-as-units work. Until then an existing roster unit stands in
## (the same placeholder as her ceremony partner); not a catchable species, so the squad hand-off
## can never mistake her for a party member.
const LYRA_UNIT := "gem_knight"
## The two Barklings screening Eldroot fight at this level (map-spawn "level"); Eldroot itself is
## the legend level (BattleSpec.make_legend: band max + legend_over_band).
const LV_ELDROOT_SCREEN := 13


# --- The field move ------------------------------------------------------------------

func _build_field_moves() -> void:
	var fm := FieldMoveResource.new()
	fm.id = StringName(FIELD_MOVE_TREES_ID)
	fm.display_name = _t("{FIELD_MOVE_TREES}")
	fm.unlock_flag = F_TREEFELL
	var sp: Array[StringName] = []
	for s in FIELD_MOVE_TREES_SPECIES:
		sp.append(StringName(s))
	fm.species = sp
	fm.hero_can_use = FIELD_MOVE_TREES_HERO
	# TODO(story): placeholder wording.
	fm.locked_hint = "A gnarled tree grows across the way. It could be felled -- if you knew how."
	fm.no_user_hint = "You know {move}, but nobody in your party can use it."
	fm.prompt_text = "This tree could be felled. Use {move}?"
	fm.used_text = "{user} used {move}!"
	_save(fm, FieldMoveResource.path_for(FIELD_MOVE_TREES_ID))


## A BREAKABLE TREE at [param cell] of area [param area_id] (DECISIONS.md #40): gone for good once felled.
func _breakable_tree(area_id: String, id: String, cell: Vector2i) -> FieldObstacleEntity:
	var t := FieldObstacleEntity.new()
	t.id = StringName(id)
	t.cell = Vector3i(cell.x, cell.y, 0)
	t.display_name = "Gnarled Tree"
	t.field_move = StringName(FIELD_MOVE_TREES_ID)
	t.look = "tree"
	t.tint = Color(0.3, 0.4, 0.2)
	t.visible_if = FieldObstacleEntity.presence_condition(area_id, id)
	return t


# --- Deepwood Village ------------------------------------------------------------------
#
# A small clan village in a clearing of the old forest (Nyra's sheet: a tree-house village). The
# tree-houses are PLACEHOLDER cabin props (the real models come from Blender). East: the road back
# to Woodland Town. North: the trail into the deep forest, held until Nyra is beaten.

const DV_W := 26
const DV_H := 20
const DV_ROAD_Y := 11
const DV_NORTH_X := 12
## Nyra's lodge (the chief's tree-house) and the clan's houses.
const DV_LODGE := Rect2i(15, 3, 4, 3)
const DV_HOUSES := [Rect2i(4, 5, 3, 2), Rect2i(5, 14, 3, 2), Rect2i(18, 14, 3, 2)]
const DV_SHRINE := Vector2i(10, 9)
const DV_NYRA := Vector2i(16, 6)
const DV_LYRA := Vector2i(14, 12)


func _dv_buildings() -> Array:
	return [DV_LODGE] + DV_HOUSES


func _dv_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	# The two ways out: the road east (Woodland Town) and the trail north (the Depths).
	if x == DV_W - 1 and y == DV_ROAD_Y:
		return "forest_dirt"
	if x == DV_NORTH_X and y <= DV_ROAD_Y:
		return "forest_dirt"
	if x == 0 or y == 0 or x == DV_W - 1 or y == DV_H - 1:
		return "tree"
	# The trail's mouth: a little open ground either side of it at the forest edge.
	if absi(x - DV_NORTH_X) == 1 and y <= 3:
		return "grass_plains"
	if _in(_dv_buildings(), c):
		return "stone_wall"
	if c == DV_SHRINE:
		return "sacred_ground"
	# The road in from the east, and the lane down from the chief's lodge.
	if y == DV_ROAD_Y and x >= 8:
		return "forest_dirt"
	if x == DV_LODGE.position.x + 2 and y >= DV_LODGE.end.y and y < DV_ROAD_Y:
		return "forest_dirt"
	# The clearing; the old forest closes in all round it.
	var dx: float = (float(x) - 13.0) / 11.5
	var dy: float = (float(y) - 10.0) / 8.0
	if dx * dx + dy * dy > 1.0:
		return "tree" if _h(x, y, 61) < 0.85 else "grass_plains"
	return "grass_plains"


func _build_deepwood_village() -> void:
	var t := _new_map("Deepwood Village", DV_W, DV_H,
		"Deepwood Village: a clan village in a clearing of the old forest, west of Woodland Town. Story-mode terrain.")
	t.lighting_preset = "Day"
	_paint(t, _dv_terrain)
	_add_validator_anchors(t, Vector2i(DV_W - 2, DV_ROAD_Y), Vector2i(DV_SHRINE.x, DV_SHRINE.y + 1))
	_save(t, CONTENT + "areas/deepwood_village/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"deepwood_village"
	a.display_name = "Deepwood Village"
	a.kind = OverworldAreaResource.Kind.TOWN
	_place(a, "deepwood_village")
	a.terrain = load(CONTENT + "areas/deepwood_village/terrain.tres")
	a.entry_points = {
		"east_road": {"cell": [DV_W - 2, DV_ROAD_Y, 0], "facing": "west"},
		"north_trail": {"cell": [DV_NORTH_X, 1, 0], "facing": "south"},
		"wayshrine": {"cell": [DV_SHRINE.x, DV_SHRINE.y + 1, 0], "facing": "north"},
	}
	var ents: Array = []
	ents.append_array(_dv_scenery())
	ents.append(_shrine(DV_SHRINE, "Deepwood Wayshrine"))
	ents.append_array(_dv_people())
	ents.append(_warp("east_exit", Rect2i(DV_W - 1, DV_ROAD_Y, 1, 1), &"woodland_town", &"west_road"))
	# DECISIONS.md #40: to go through the forest the hero must first fight Nyra.
	ents.append(_warp("north_exit", Rect2i(DV_NORTH_X, 0, 1, 1), &"depths_of_the_wood", &"south", "",
		"has(\"%s\")" % F_DEPTHS_OPEN, _scene("dv_north_locked", [
			# TODO(story): placeholder wording.
			_narr("The trail north leads into the deep forest. To go on, you must first battle {NYRA}, the chief of Deepwood."),
		])))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	# No arrival scene (the location popup names the village); the flag is set silently.
	a.on_enter = StoryCommand.list([
		IfCommand.make("not has(\"deepwood.arrived\")", [_flag("deepwood.arrived")]),
	])
	_save(a, CONTENT + "areas/deepwood_village/area.tres")


func _dv_scenery() -> Array:
	var out: Array = []
	var moss := Color(0.26, 0.4, 0.22)
	# PLACEHOLDER tree-houses (cabins until the Blender models arrive).
	out.append(_prop("nyra_lodge", "cabin", DV_LODGE.position, DV_LODGE.size, Color(0.22, 0.36, 0.2)))
	for i in range(DV_HOUSES.size()):
		var r: Rect2i = DV_HOUSES[i]
		out.append(_prop("treehouse_%d" % i, "cabin", r.position, r.size, [moss, Color(0.36, 0.3, 0.2)][i % 2]))
	out.append(_prop("campfire", "fire", Vector2i(13, 15), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("woodpile", "logs", Vector2i(9, 16), Vector2i(2, 1), Color(0.58, 0.42, 0.24), true))
	out.append(_prop("banner_lodge", "banner", Vector2i(DV_LODGE.position.x - 1, DV_LODGE.end.y), Vector2i.ONE,
		Color(0.24, 0.42, 0.26), true))
	for lc in [Vector2i(9, 8), Vector2i(11, 8)]:
		out.append(_prop("lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.78, 0.4), true))
	return out


func _dv_people() -> Array:
	var out: Array = []
	out.append(_sign("village_sign", Vector2i(DV_W - 3, DV_ROAD_Y + 1), "Deepwood Village",
		"DEEPWOOD VILLAGE\nEast: Woodland Town.  North: the deep forest."))
	out.append(_sign("trail_sign", Vector2i(DV_NORTH_X + 1, 3), "The North Trail",
		"NORTH: THE DEEP FOREST"))
	out.append(_nyra())
	# Lyra (DECISIONS.md #88): met here; she fights beside you against Eldroot (the guest on its board).
	# Her line is in dialogue.json (areas.deepwood_village.lyra).
	var lyra := _npc("lyra", DV_LYRA, "north", "LYRA", Color(0.78, 0.5, 0.2), "trainer")
	lyra.visible_if = LYRA_IN_DEEPWOOD
	out.append(lyra)
	# Villagers: one placeholder line each in dialogue.json (areas.deepwood_village.<id>).
	var cloak := Color(0.3, 0.42, 0.28)
	out.append(_npc("dv_elder", Vector2i(6, 8), "south", "DEEPWOOD_ELDER", cloak.lightened(0.15), "elder"))
	out.append(_npc("dv_hunter", Vector2i(21, 9), "west", "DEEPWOOD_HUNTER", cloak, "trainer"))
	out.append(_npc("dv_child", Vector2i(9, 13), "east", "DEEPWOOD_CHILD", Color(0.5, 0.6, 0.35), "child"))
	return out


## NYRA'S CHIEF DUEL (DECISIONS.md #50 / #80): SCALED inside the Deep Woods band, a boss battle for XP.
## A loss WHITES OUT (a story duel concludes at once -- the Try Again screen is the tactical board's):
## you wake at the Wayshrine and she waits, so it is never missable. Winning grants the field move
## and opens the trail north.
func _nyra_spec() -> BattleSpec:
	var team: Array = []
	for i in range(NYRA_TEAM.size()):
		var row: Dictionary = {"character_id": NYRA_TEAM[i], "strength": 1.0}
		if i == NYRA_TEAM.size() - 1:
			# TODO(bond): stone boost -- she uses the stone with her FINAL creature (#38 / #67).
			row["strength"] = NYRA_STONE_BOOST
		team.append(row)
	var spec := _duel_spec(NYRA_DUEL_ID, "{NYRA}", &"npc_nyra", team, false, BattleSpec.DefeatPolicy.WHITEOUT,
		NYRA_PURSE, [], [F_NYRA_BEATEN, F_TREEFELL, F_DEPTHS_OPEN])
	BattleSpec.make_chief(spec, REGION_BANDS["woodlands"], NYRA_SCALE_OFFSET)
	spec.clash_intro = true
	return spec


## Nyra at her lodge. TODO(story): placeholder lines -- owner facts only (she is the Deepwood chief;
## the hero must battle her to go through the forest; she teaches the tree-felling move).
func _nyra() -> NpcEntity:
	var nyra := _npc("nyra", DV_NYRA, "south", "NYRA", Color(0.3, 0.48, 0.3), "trainer")
	var won: Array = [
		_say([_line("nyra", "NYRA", "You've earned the way through. Take this with you -- it will clear the trees.")]),
		_toast("New field move: {FIELD_MOVE_TREES}"),
		SaveGameCommand.new(),
	]
	var ask := ChoiceCommand.new()
	ask.prompt = _line("nyra", "NYRA", "I'm {NYRA}, chief of Deepwood. To go through the forest, you battle me first. Ready?")
	ask.options = StoryCommand.list([
		ChoiceOption.make("Battle!", [_duel(_nyra_spec()), IfCommand.make("outcome() == \"victory\"", won)]),
		ChoiceOption.make("Not yet.", [], true),
	])
	nyra.on_interact = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_NYRA_BEATEN, [ask], [
			_say([_line("nyra", "NYRA", "The deep forest is open to you. Mind the trees.")]),
		]),
	])
	return nyra


# --- The Depths of the Wood ------------------------------------------------------------
#
# The forest north of the village: a winding track through tall grass (the Deep Woods' creatures,
# in the region band), and BREAKABLE TREES. One closes the only gap in a wall of old trees -- the way
# to the glade at the forest's heart, where Eldroot waits; another hides a nook with a chest; a third
# is a shortcut. South: the trail back to Deepwood Village.

const DW_W := 24
const DW_H := 30
const DW_ENTRY_X := 12
## The wall of old trees across the forest, and its one gap (the gate tree).
const DW_WALL_Y := 10
const DW_GATE := Vector2i(12, DW_WALL_Y)
## The glade at the forest's heart (north of the wall) and Eldroot in it.
const DW_GLADE_C := Vector2i(12, 5)
const DW_ELDROOT := Vector2i(12, 4)
## The nook (a pocket behind a breakable tree) and its chest.
const DW_NOOK := Rect2i(19, 15, 3, 3)
const DW_NOOK_TREE := Vector2i(18, 16)
const DW_NOOK_CHEST := Vector2i(21, 16)
## The shortcut: a line of trees across the east side with one breakable tree in it.
const DW_THICKET_Y := 21
const DW_THICKET_TREE := Vector2i(16, DW_THICKET_Y)
const DW_GRASS := [Rect2i(13, 23, 5, 4), Rect2i(3, 16, 3, 5), Rect2i(9, 16, 4, 4), Rect2i(14, 11, 4, 3)]


## The winding track (the cells the scatter keeps off).
func _dw_on_track(x: int, y: int) -> bool:
	if x == DW_ENTRY_X and y >= 22:
		return true
	if y == 22 and x >= 7 and x <= DW_ENTRY_X:
		return true
	if x == 7 and y >= 14 and y <= 22:
		return true
	if y == 14 and x >= 7 and x <= DW_ENTRY_X:
		return true
	return x == DW_ENTRY_X and y > DW_WALL_Y and y <= 14


func _dw_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if x == DW_ENTRY_X and y == DW_H - 1:
		return "forest_dirt"
	if x == 0 or y == 0 or x == DW_W - 1 or y == DW_H - 1:
		return "tree"
	# North of the wall: the glade (sacred meadow), its path up from the gate, old forest round it.
	if y < DW_WALL_Y:
		if x == DW_ENTRY_X and y > DW_GLADE_C.y:
			return "forest_dirt"
		var gx: float = (float(x) - float(DW_GLADE_C.x)) / 6.0
		var gy: float = (float(y) - float(DW_GLADE_C.y)) / 3.6
		if gx * gx + gy * gy <= 1.0:
			return "sacred_meadow"
		return "tree"
	# The wall of old trees and its one gap (the gate tree stands in it).
	if y == DW_WALL_Y:
		return "forest_dirt" if c == DW_GATE else "tree"
	# The nook: walled round, open only through its tree.
	if c == DW_NOOK_TREE:
		return "forest_dirt"
	if DW_NOOK.grow(1).has_point(c) and not DW_NOOK.has_point(c):
		return "tree"
	if DW_NOOK.has_point(c):
		return "grass_plains"
	# The shortcut's thicket line (east of the track), broken only by its tree.
	if y == DW_THICKET_Y and x >= 13 and x <= DW_W - 2:
		return "forest_dirt" if c == DW_THICKET_TREE else "tree"
	if _dw_on_track(x, y):
		return "forest_dirt"
	if _in(DW_GRASS, c):
		return "tall_grass"
	# Old forest: scattered trees, never beside the track or the trees you can fell.
	var near: bool = false
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = c + d
		if _dw_on_track(n.x, n.y) or n == DW_NOOK_TREE or n == DW_THICKET_TREE or n == DW_GATE:
			near = true
	if not near and _h(x, y, 71) < 0.16:
		return "tree"
	return "grass_plains"


func _build_depths_of_the_wood() -> void:
	var aid := "depths_of_the_wood"
	var t := _new_map("Depths of the Wood", DW_W, DW_H,
		"The Depths of the Wood: the old forest north of Deepwood Village, and the glade at its heart. Story-mode terrain.")
	t.lighting_preset = "Dusk"
	_paint(t, _dw_terrain)
	_add_validator_anchors(t, Vector2i(DW_ENTRY_X, DW_H - 2), Vector2i(DW_ENTRY_X, DW_WALL_Y + 2))
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)

	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	a.display_name = "Depths of the Wood"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, aid)
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	a.entry_points = {
		"south": {"cell": [DW_ENTRY_X, DW_H - 2, 0], "facing": "north"},
	}
	var ents: Array = []
	ents.append(_warp("south_exit", Rect2i(DW_ENTRY_X, DW_H - 1, 1, 1), &"deepwood_village", &"north_trail"))
	ents.append(_breakable_tree(aid, "gate_tree", DW_GATE))
	ents.append(_breakable_tree(aid, "nook_tree", DW_NOOK_TREE))
	ents.append(_breakable_tree(aid, "thicket_tree", DW_THICKET_TREE))
	var chest := ChestEntity.new()
	chest.id = &"nook_chest"
	chest.cell = Vector3i(DW_NOOK_CHEST.x, DW_NOOK_CHEST.y, 0)
	chest.facing = "west"
	chest.display_name = "Chest"
	chest.tint = Color(0.42, 0.3, 0.18)
	var loot: Array[StringName] = [&"heartwood_tonic", &"clearwater_draught"]
	chest.loot_items = loot
	chest.loot_gold = 60
	# Out of reach (and out of sight) until its tree is felled.
	chest.visible_if = "has(\"%s\")" % FieldObstacleEntity.flag_for(aid, "nook_tree")
	ents.append(chest)
	ents.append(_eldroot(aid))
	_add_doors(a, ents)
	a.entities = _entities(ents)

	var zone := EncounterZone.new()
	var ids: Array[StringName] = [&"tall_grass"]
	zone.tile_ids = ids
	zone.rate = 0.12
	zone.grace_steps = 3
	var table: Array[Resource] = []
	# The Deep Woods' creatures (nature roster placeholders), rolling in the region band (8-15).
	for pair in [["petalfang", 2.0], ["blightcap", 2.0], ["tree_grunt", 1.5], ["vineweave", 1.0], ["oakheart", 0.5]]:
		var e := EncounterEntry.new()
		e.character_id = StringName(pair[0])
		e.weight = pair[1]
		e.kind = EncounterEntry.Kind.DUEL
		e.can_befriend = true
		table.append(e)
	zone.table = table
	var zones: Array[Resource] = [zone]
	a.encounter_zones = zones
	_save(a, CONTENT + "areas/%s/area.tres" % aid)


## ELDROOT'S LEGEND BATTLE (DECISIONS.md #39 / #74 / #81): TACTICAL, FIXED at the band max +
## legend_over_band (never scaled), Lyra on your side as a guest; a loss offers Try Again.
func _eldroot_spec() -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.encounter_id = ELDROOT_BATTLE_ID
	spec.map_path = ELDROOT_MAP_PATH
	spec.squad_size = ELDROOT_SQUAD_SIZE
	spec.ai_difficulty = 1
	spec.opponent_name = _species_name(&"eldroot")
	var team: Array[Dictionary] = [{"character_id": "eldroot", "strength": 1.0}]
	spec.opponent_team = team
	BattleSpec.make_legend(spec, REGION_BANDS["woodlands"])
	var flags: Array[String] = [F_ELDROOT_BEATEN]
	spec.reward_flags = flags
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	return spec


## Eldroot in the glade: there once the gate tree is felled, until the hero bonds with it. Talk: face
## it (the legend battle) -> on a win, the OPTIONAL bond (#75). Declined: it stays, and talking to it
## again offers the bond again. TODO(story): placeholder narration.
func _eldroot(aid: String) -> NpcEntity:
	var e := NpcEntity.new()
	e.id = &"eldroot"
	e.cell = Vector3i(DW_ELDROOT.x, DW_ELDROOT.y, 0)
	e.facing = "south"
	e.display_name = _species_name(&"eldroot")
	e.speaker_name = e.display_name
	e.visual_character = &"eldroot"
	e.visible_if = "has(\"%s\") and not has(\"%s\")" % [FieldObstacleEntity.flag_for(aid, "gate_tree"), F_ELDROOT_BONDED]
	var bond_cmd := BondLegendCommand.new()
	bond_cmd.character_id = &"eldroot"
	var bond := ChoiceCommand.new()
	bond.prompt = _narr("%s watches you, still. Bond with it?" % e.display_name)
	bond.options = StoryCommand.list([
		ChoiceOption.make("Bond", [bond_cmd, _flag(F_ELDROOT_BONDED), SaveGameCommand.new()]),
		ChoiceOption.make("Not now", [], true),
	])
	var fight := StartBattleCommand.new()
	fight.spec = _eldroot_spec()
	fight.source = BattleRequest.SOURCE_SCRIPT
	var face := ChoiceCommand.new()
	face.prompt = _narr("Something ancient stirs among the roots of the glade. Face it?")
	face.options = StoryCommand.list([
		ChoiceOption.make("Face it", [fight, IfCommand.make("outcome() == \"victory\"", [bond])]),
		ChoiceOption.make("Not yet", [], true),
	])
	e.on_interact = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_ELDROOT_BEATEN, [face], [bond]),
	])
	return e


## The legend's board: a forest glade, Eldroot (2x2, the boss) on the sacred ground at its heart with
## two Barklings screening it; your squad chairs at the south edge and Lyra (the GUEST, LYRA_UNIT)
## beside them.
func _build_eldroot_map() -> void:
	var m := _new_map("Heart of the Wood", 12, 10,
		"The glade at the heart of the Deep Woods, where Eldroot waits.")
	m.lighting_preset = "Dusk"
	var anchor := Vector2i(5, 1)
	var trees := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(10, 0), Vector2i(11, 0), Vector2i(0, 1), Vector2i(11, 1),
		Vector2i(0, 9), Vector2i(11, 9), Vector2i(2, 5), Vector2i(9, 5)]
	var grass := [Vector2i(3, 6), Vector2i(4, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(2, 3), Vector2i(9, 3)]
	_paint(m, func(x: int, y: int) -> String:
		var c := Vector2i(x, y)
		if c in trees:
			return "tree"
		if x >= anchor.x and x <= anchor.x + 1 and y >= anchor.y and y <= anchor.y + 1:
			return "sacred_meadow"
		if c in grass:
			return "tall_grass"
		if x == 6 and y >= 3:
			return "forest_dirt"
		return "grass_plains")
	m.unit_spawns.clear()
	# Squad chairs (filled from the fielded party; a placeholder id is required).
	for c in [Vector2i(4, 8), Vector2i(6, 8), Vector2i(8, 8)]:
		m.set_character_spawn_at_position(c, 0, String(STARTER_ID))
	# Lyra: a guest ally, placed at load (never replaced by the squad pick).
	# TODO(humans): swap to "lyra" + deploy picker
	m.set_spawn_point_at_position(Vector2i(5, 9), 0, MapResource.SPAWN_KIND_REINFORCEMENT,
		{"character_id": LYRA_UNIT, "spawn_turn": 1, "max_spawns": 1})
	m.set_character_spawn_at_position(anchor, 1, "eldroot", "BOSS")
	for c in [Vector2i(3, 3), Vector2i(8, 3)]:
		m.set_character_spawn_at_position(c, 1, "tree_grunt")
		m.unit_spawns[m.unit_spawns.size() - 1]["level"] = LV_ELDROOT_SCREEN
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, ELDROOT_MAP_PATH)
