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
##   game/overworld/content/areas/depths_of_the_wood{,_2,_3,_4}/ -- the MAZE north of it (Lost Woods rooms)
##   game/overworld/content/areas/depths_of_the_wood_heart/  -- the clearing at its end: Eldroot
##   game/overworld/content/areas/beach_village/             -- THE COAST: Eloi (the sea move), Cael
##   game/overworld/content/areas/frostpeak_village/, frostpeak_dream/ (+ frostpeak_inn, frostpeak_house)
##                                                           -- THE PEAKS: the sleeping town and its dream
##   game/overworld/content/areas/rocky_badlands/, redrock_village/, red_desert/, badlands_cave/,
##     badlands_hideout{,_depths}/                           -- THE BADLANDS: the rumours, the cave, the hideout
##   game/overworld/content/battles/ow_frostpeak_dream.tres  -- the two mythical creatures (tactical)
##   game/overworld/content/battles/ow_badlands_hideout.tres -- the hideout's last fight (tactical)
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
	# Generic trainers in the Deep Woods' maze (optional duels; no named cast).
	"FORAGER": "Forager",
	"TRAPPER": "Trapper",
	# TODO(story): PLACEHOLDER name of the tree-felling field move Nyra teaches (DECISIONS.md #40/#41).
	"FIELD_MOVE_TREES": "Treefell",
	# --- The Sunlit Coast: Beach Village (DECISIONS.md #43 / #85 / #88) ---
	"ELOI": "Eloi",                         # owner: the sea chief (docs/design/characters/eloi.webp; "his people")
	# TODO(story): PLACEHOLDER name of the sea-crossing field move Eloi teaches (DECISIONS.md #41 / #43).
	"FIELD_MOVE_SEA": "Tideride",
	# Generic villagers (no named cast -- one short placeholder line each in dialogue.json).
	"BEACH_FISHER": "Fisher",
	"NET_MENDER": "Net Mender",
	"HARBOUR_HAND": "Harbour Hand",
	"BEACH_CHILD": "Beach Child",
	# --- The Snowy Peaks: Frostpeak Village (DECISIONS.md #49 / #69 / #85 / #95) ---
	"SAEVI": "Saevi",                       # owner: the winter chief (docs/design/characters/saevi.webp; "her people")
	"FROST_INNKEEPER": "Innkeeper",
	"FROST_TRAVELLER": "Traveller",
	"FROST_ELDER": "Frostpeak Elder",
	"FROST_HUNTER": "Frostpeak Hunter",
	"FROST_WATCH": "Trail Watch",
	"FROST_WOODCUTTER": "Woodcutter",
	"FROST_CHILD": "Frostpeak Child",
	"FROST_SLEEPER": "Villager",
	# --- The Rocky Badlands: Redrock Village, the Red Desert, the hideout (DECISIONS.md #46 / #57 / #73 / #96) ---
	"REDROCK_ELDER": "Redrock Elder",
	"REDROCK_MINER": "Miner",
	"REDROCK_TRADER": "Caravan Trader",
	"REDROCK_WATCH": "Mesa Watch",
	"REDROCK_CHILD": "Redrock Child",
	"BADLANDS_PROSPECTOR": "Prospector",
	# TODO(story): generic PLACEHOLDER people of the secret hideout -- who they serve is the owner's call.
	"HOODED_FIGURE": "Hooded Figure",
	"HIDEOUT_GUARD": "Hideout Guard",
	"HIDEOUT_COMMANDER": "Hideout Commander",
	# --- The post-game (DECISIONS.md #98-#100) ---
	"GRAVEKEEPER": "Gravekeeper",           # Crownhaven Graveyard (a generic placeholder; no named cast)
}

## WOMEN among the NPCs (NAMES keys, or the literal name an _npc call passes): they wear the FEMALE
## placeholder model (NpcEntity.body "female" -> StoryRuleset.npc_female_model, a clone of Lyra's;
## everyone else wears the default, a clone of Wren's -- owner, 2026-10-08). ONLY where the story
## already establishes it -- an owner fact, a gendered title, or she / her about that person; never
## guessed from a first name. Add a key here (and rebuild) when the owner says so.
const FEMALE_NPCS := {
	"MOTHER": "the hero's mother (DECISIONS.md #55)",
	"WARRIOR": "Talyn, female (owner 2026-10-04; DECISIONS.md #59)",
	"LYRA": "she / her (Lyra's scripts here; dialogue.json areas.crownhaven.lyra note)",
	"NYRA": "she is the Deepwood chief (Nyra's lodge, below)",
	"SAEVI": "'respected by her people' (docs/design/characters/saevi.webp)",
	"MARRA": "title Goodwife; 'the Hearth & Hen's landlady on her scorched plot'",
	"ODALYS": "title Sister",
	"FERRA": "title Huntress",
	"WICKE": "title Gran",
	"Lady Merrow": "title Lady",
	"MERCHANT": "Merchant Oda: 'this is her greeting' (dialogue.json areas.crownhaven.merchant note)",
	"FENNA": "'she is the first trainer on the road'; dialogue.json areas.mossway.fenna note",
	"BANDIT_BOSS": "Cutpurse Nell: 'Her idle line is in dialogue.json'",
	"CHAMPION": "Champion Isolde: 'once you've taken her title'",
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
	["depths_of_the_wood", "Depths of the Wood", "special", "woodlands", Vector2(0.114, 0.337), ["depths_of_the_wood", "depths_of_the_wood_2", "depths_of_the_wood_3", "depths_of_the_wood_4", "depths_of_the_wood_lost", "depths_of_the_wood_heart"], "world.depths_of_the_wood_open", false,
		"A maze of old forest north of Deepwood, with a glowing glade at its heart. A special encounter."],
	["frostpeak_village", "Frostpeak Village", "village", "snowy_peaks", Vector2(0.231, 0.166), ["frostpeak_village", "frostpeak_dream"], "world.frostpeak_open", false,
		"A village under the Snowy Peaks, up the north trail from Woodland Town."],
	["mountain_base", "Mountain Base", "town", "northern_mountains", Vector2(0.693, 0.188), [], "world.mountain_road_open", false,
		"The fortified town at the foot of the mountains, up the road from Crownhaven's north gate."],
	["mountain_pass", "Mountain Pass", "route", "northern_mountains", Vector2(0.668, 0.080), [], "world.mountain_pass_open", false,
		"The high pass over the mountains toward Cindral."],
	["hidden_depths", "Hidden Depths", "special", "northern_mountains", Vector2(0.850, 0.137), ["hidden_depths", "hidden_depths_2", "hidden_depths_3", "hidden_depths_heart"], "world.hidden_depths_open", false,
		"A crystal cave in the eastern mountains. A special encounter."],
	["cindral", "Cindral", "nation", "cindral", Vector2(0.761, 0.045), [], "world.cindral_open", false,
		"The Other Nation, beyond the Mountain Pass."],
	["rocky_badlands", "Rocky Badlands", "route", "rocky_badlands", Vector2(0.665, 0.398), ["rocky_badlands"], "world.badlands_open", false,
		"The Redrock road east from Crownhaven's east gate, through the red mesas."],
	["redrock_village", "Redrock Village", "village", "rocky_badlands", Vector2(0.856, 0.410), ["redrock_village"], "world.badlands_open", false,
		"A village among the red mesas, down the road from Crownhaven's east gate."],
	["red_desert", "The Red Desert", "route", "rocky_badlands", Vector2(0.800, 0.492), ["red_desert", "badlands_cave"], "world.badlands_open", false,
		"Sand and red rock south of Redrock Village, where travellers say strange people come and go."],
	["secret_hideout", "Secret Hideout", "dungeon", "rocky_badlands", Vector2(0.772, 0.532), ["badlands_hideout", "badlands_hideout_depths"], "badlands.hideout_open", true,
		"A hideout dug behind a dead-end cave in the Red Desert."],
	["stormreef_waters", "Stormreef Waters", "route", "open_ocean", Vector2(0.645, 0.800), ["stormreef_waters", "stormreef_waters_erupted", "volcano_path", "volcano_crater"], "", false,
		"The open sea south of Beach Village, off Stormreef Isle."],
	["snowy_peaks", "The Snowy Peaks", "route", "snowy_peaks", Vector2(0.262, 0.105), ["snowy_peaks"], "", false,
		"The high trail into the peaks north of Frostpeak Village."],
	["frozen_cave", "Frozen Cave", "special", "snowy_peaks", Vector2(0.300, 0.075), ["glacier_cave", "glacier_cave_2", "glacier_cave_3"], F_POSTGAME, true,
		"A cave on the Snowy Peaks, long sealed by ice. A special encounter."],
	["crownhaven_graveyard", "Crownhaven Graveyard", "route", "heartlands", Vector2(0.455, 0.372), ["crownhaven_graveyard"], "", false,
		"The graveyard on Crownhaven's outskirts, beyond the west gate."],
	["old_crypt", "The Old Crypt", "dungeon", "heartlands", Vector2(0.448, 0.352), ["old_crypt", "old_crypt_depths", "old_crypt_end"], F_FINAL_BOSS, true,
		"A crypt below Crownhaven's graveyard."],
	["beach_village", "Beach Village", "village", "sunlit_coast", Vector2(0.678, 0.685), ["beach_village"], "world.beach_road_open", false,
		"A harbour village on stilts, south-east of the capital: the port for the isles."],
	["sunrise_isle", "Sunrise Isle", "island", "open_ocean", Vector2(0.910, 0.615), [], "world.sea_routes_open", false,
		"An island to the east, a short sail from Beach Village."],
	["island_of_tides", "Island of Tides", "special", "open_ocean", Vector2(0.850, 0.810), ["island_of_tides", "tides_cave_1", "tides_pocket", "tides_cave_2", "tides_cave_3", "tides_depths"], "", false,
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
	["crownhaven", "rocky_badlands", "main"],
	["rocky_badlands", "redrock_village", "main"],
	["redrock_village", "red_desert", "secondary"],
	["red_desert", "secret_hideout", "secondary"],
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
	["beach_village", "stormreef_waters", "sea"],
	["stormreef_waters", "stormreef_isle", "sea"],
	["frostpeak_village", "snowy_peaks", "secondary"],
	["snowy_peaks", "frozen_cave", "secondary"],
	["sparse_forest", "crownhaven_graveyard", "secondary"],
	["crownhaven_graveyard", "old_crypt", "secondary"],
	["stormreef_waters", "island_of_tides", "sea"],
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
const RAIDER_UNITS: Array[String] = ["tree_grunt", "petalfang", "blightcap", "monster"]
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
	"sand": "NORMAL",
	"red_clay": "NORMAL",
	"mesa_rock": "WALL",
	"snow_field": "DIFFICULT_TERRAIN",
	"frozen_tundra": "NORMAL",
	"frozen_pine": "WALL",
	"ice_sheet": "ICE",
}

var _ok: bool = true


func _initialize() -> void:
	for d in ["areas/oakvale", "areas/oakvale_ruins", "areas/mossway", "areas/river_crossing", "areas/crownhaven",
			"areas/sparse_forest", "areas/woodland_town", "areas/deepwood_village", "areas/depths_of_the_wood",
			"areas/depths_of_the_wood_2", "areas/depths_of_the_wood_3", "areas/depths_of_the_wood_4", "areas/depths_of_the_wood_heart",
			"areas/beach_village", "areas/frostpeak_village", "areas/frostpeak_dream", "areas/rocky_badlands",
			"areas/redrock_village", "areas/red_desert", "areas/badlands_cave", "areas/badlands_hideout",
			"areas/badlands_hideout_depths", "areas/stormreef_waters", "areas/stormreef_waters_erupted", "areas/snowy_peaks",
			"areas/glacier_cave", "areas/crownhaven_graveyard", "areas/old_crypt",
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
	_build_dream_battle_map()
	_build_hideout_battle_map()
	_build_glacier_map()
	_build_crypt_map()
	_build_depths_boss_map()
	_build_tides_map()
	_build_oakvale(false)
	_build_oakvale(true)
	_build_mossway()
	_build_river_crossing()
	_build_crownhaven()
	_build_sparse_forest()
	_build_woodland_town()
	_build_deepwood_village()
	_build_depths_of_the_wood()
	_build_beach_village()
	_build_frostpeak(false)
	_build_frostpeak(true)
	_build_rocky_badlands()
	_build_redrock_village()
	_build_red_desert()
	_build_badlands_cave()
	_build_hideout()
	_build_hideout_depths()
	_build_stormreef_waters(false)
	_build_stormreef_waters(true)
	_build_snowy_peaks()
	_build_glacier_cave()
	_build_graveyard()
	_build_crypt()
	_build_volcano()
	_build_hidden_depths()
	_build_island_of_tides()
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


## A road OUT to a place that is now BUILT: a warp to [param target_area] / [param target_entry]
## held by that place's open flag (WORLD_LOCATIONS), answering with [param text] until it is set.
func _road_out(id: String, rect: Rect2i, location_id: String, target_area: StringName, target_entry: StringName,
		text: String) -> WarpEntity:
	var row: Array = _world_row(location_id)
	var flag: String = String(row[6]) if not row.is_empty() else "world.never"
	return _warp(id, rect, target_area, target_entry, "", "has(\"%s\")" % flag,
		_scene("%s_road_locked_%s" % [location_id, id], [_narr(text)]))


## The silent on_enter that opens the regions' roads ([param flags]) once [constant
## REGION_ROADS_OPEN_IF] holds -- set by the town the road leaves from, so a journey saved before
## these regions were built opens them on its next visit.
func _open_region_roads(flags: Array) -> Array:
	var out: Array = []
	for f in flags:
		out.append(IfCommand.make("(%s) and not has(\"%s\")" % [REGION_ROADS_OPEN_IF, f], [_flag(String(f))]))
	return out


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
	m.body = _body_of(name_key)
	m.shop =load(ShopResource.path_for(shop_id)) as ShopResource
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
	n.body = _body_of(name_key)
	n.dialogue = dialogue
	return n


## The placeholder body an NPC named by [param name_key] wears ([constant FEMALE_NPCS]).
static func _body_of(name_key: String) -> String:
	return NpcLooks.BODY_FEMALE if FEMALE_NPCS.has(name_key) else ""


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
	# The sleeping town (DECISIONS.md #95): the inn's beds (you must rest there) and a house of sleepers.
	"frostpeak_village": {
		"fp_inn": {"id": FP_INN_ID, "name": "Frostpeak Inn", "size": Vector2i(10, 7)},
		"fp_house": {"id": FP_HOUSE_ID, "name": "Frostpeak House", "size": Vector2i(8, 6)},
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
	a.entry_points.merge(_interior_entries(iid))
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
		FP_INN_ID:
			return _fp_inn_people(size)
		FP_HOUSE_ID:
			return _fp_house_people()
	return []


## Extra entry points of interior [param iid] (per-building override; just the door by default).
func _interior_entries(iid: String) -> Dictionary:
	match iid:
		FP_INN_ID:
			# Waking from the dream: beside the first empty bed, facing it.
			var bx: int = int(FP_INN_BEDS[0][1])
			return {"bed": {"cell": [bx, 3, 0], "facing": "north"}}
	return {}


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
	ents.append(_road_out("east_exit", Rect2i(RC_W - 1, RC_ROAD_Y, 1, 1), "beach_village", &"beach_village", &"west_road",
		"The coast road east toward Beach Village and the sea dips into a ford -- and the ford has become a lake. A Warden's rope and a painted board: \"Road closed. Ferry suspended. Ask again after the rains.\""))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	# No arrival narration (the location popup names the village); the flag is set silently -- and so is
	# the coast road's, once the opening is over.
	var on_enter: Array = [
		IfCommand.make("not has(\"river_crossing.arrived\")", [_flag("river_crossing.arrived")]),
	]
	on_enter.append_array(_open_region_roads([F_BEACH_ROAD_OPEN]))
	a.on_enter = StoryCommand.list(on_enter)
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
	# The Redrock road (the Rocky Badlands) and the coast road (Beach Village): open once the opening is
	# over ([constant REGION_ROADS_OPEN_IF]); until then the old excuses answer.
	ents.append(_road_out("east_exit", Rect2i(CH_W - 1, CH_EAST_GATE.y, 1, 1), "redrock_village", &"rocky_badlands", &"west_road",
		"The Redrock road runs east into the red mesas of the Rocky Badlands. A chain hangs across it, and a notice: \"No caravans until the Badlands road is cleared of rockfalls. By order of the Guildhall.\""))
	ents.append(_road_out("harbour_exit", Rect2i(CH_W - 1, CH_HARBOUR_GATE.y, 1, 1), "beach_village", &"beach_village", &"north_road",
		"The coast road slopes south-east toward Beach Village and the harbour. The gate warden waves you back: \"Ford's flooded below the city. Nothing's getting to the coast this week.\""))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	# No arrival narration: the location popup names the city, and nothing stops the hero's walk. The flag
	# is still set (quests and ambient talk key off "has been to Crownhaven"), silently -- as are the roads
	# out to the coast and the badlands once the opening is over.
	var on_enter: Array = [
		IfCommand.make("not has(\"%s\")" % F_ARRIVED, [_flag(F_ARRIVED)]),
	]
	on_enter.append_array(_open_region_roads([F_BEACH_ROAD_OPEN, F_BADLANDS_OPEN]))
	a.on_enter = StoryCommand.list(on_enter)
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
	# Not while he is in the Red Desert's hideout (one General at a time, #57).
	general.visible_if = "has(\"%s\") and not (%s)" % [F_COMPLETE, VARDEN_IN_HIDEOUT]
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
	t.body = _body_of("FENNA")
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
			{"character_id": "tree_grunt", "strength": 0.7}],
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
		["{QUENBY}", "npc_quenby", [["petalfang", 1.05], ["mycothrall", 0.85]]],
		["{CHAMPION}", "npc_isolde", [["vineweave", 0.85], ["monster", 0.8], ["blightcap", 0.8]]],
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
		[{"character_id": "vineweave", "strength": 0.9}, {"character_id": "monster", "strength": 0.85},
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
## The path north to Crownhaven Graveyard (off the road, just outside the city's west gate).
const SF_GRAVEYARD_X := 24


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
	# The path north to the graveyard on Crownhaven's outskirts (DECISIONS.md #100).
	if x == SF_GRAVEYARD_X and y < SF_ROAD_Y:
		return "forest_dirt"
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
		"graveyard_path": {"cell": [SF_GRAVEYARD_X, 1, 0], "facing": "south"},
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
	ents.append(_warp("graveyard_exit", Rect2i(SF_GRAVEYARD_X, 0, 1, 1), &"crownhaven_graveyard", &"south_gate"))
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
	ents.append(_road_out("north_exit", Rect2i(WT_NORTH_X, 0, 1, 1), "frostpeak_village", &"frostpeak_village", &"south_trail",
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
	# talk keys off "rests since arriving") -- as is the north trail's, once the opening is over.
	var on_enter: Array = [
		IfCommand.make("not has(\"woodland.arrived\")", [_flag("woodland.arrived")]),
	]
	on_enter.append_array(_open_region_roads([F_FROSTPEAK_OPEN]))
	a.on_enter = StoryCommand.list(on_enter)
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
#     -> LYRA CHALLENGES the hero (a friendly rival duel, #94); once it is fought, whatever the
#        outcome, she keeps the hero company: a TEMPORARY party member, no overworld follower.
#     -> beating NYRA opens the trail north (world.depths_of_the_wood_open: "to go through the forest
#        the hero must first fight Nyra") and she TEACHES the tree-felling FIELD MOVE (#40 / #92): one
#        eligible party member LEARNS it (fieldmove.treefell = teachable; the member record keeps it).
#     -> THE DEPTHS OF THE WOOD: a MAZE (#93) of look-alike rooms -- follow the deepest roots and the
#        greatest trees (#101); a wrong way leads into a thicket of tough wild creatures; the wrong ways
#        turn you back to the entrance; BREAKABLE TREES (FieldObstacleEntity) block the right way, so
#        the move is required. Tall grass, optional trainers, chests.
#     -> THE HEART OF THE WOOD: the clearing where ELDROOT waits: a TACTICAL legend battle (#74), FIXED
#        above the band (#81), Lyra deployable in its squad pick (#56 / #74 / #94). Win -> the OPTIONAL
#        bond (#75): a legend goes into the journey's legend list (StoryState.legends), never the party.
#
# All lines here are short neutral PLACEHOLDERS (TODO(story)) -- the owner's facts only.

## Flags (save keys -- never rename once shipped).
const F_DEEPWOOD_OPEN := "world.deepwood_open"
const F_DEPTHS_OPEN := "world.depths_of_the_wood_open"
const F_NYRA_BEATEN := "deepwood.nyra_beaten"
## Lyra CHALLENGES the hero in Deepwood Village (DECISIONS.md #94): set once that bout is fought,
## whatever its outcome.
const F_LYRA_CHALLENGED := "deepwood.lyra_challenged"
## ...then joins the party TEMPORARILY (#56 / #61 / #88 / #94): no overworld follower, deployable in
## the Eldroot battle's squad pick; she leaves again when Eldroot is beaten (guest_until).
const F_LYRA_JOINED := "deepwood.lyra_joined"
## The tree-felling field move is granted (FieldMoveResource.unlock_flag).
const F_TREEFELL := "fieldmove.treefell"
const F_ELDROOT_BEATEN := "deepwood.eldroot_beaten"
const F_ELDROOT_BONDED := "legend.eldroot.bonded"
## Encounter ids (save keys).
const NYRA_DUEL_ID := "deepwood.chief.nyra"
const LYRA_DEEPWOOD_DUEL_ID := "deepwood.rival.lyra"
const ELDROOT_BATTLE_ID := "deepwood.legend.eldroot"
## Lyra is IN DEEPWOOD from the moment the road opens until the Eldroot battle is won; every other
## Lyra (Crownhaven's south gate and arena) hides meanwhile -- one Lyra at a time. (The workshop's
## ceremony Lyra is gone once the opening is over, and the road only opens after it.)
const LYRA_IN_DEEPWOOD := "has(\"opening.complete\") and has(\"world.deepwood_open\") and not has(\"deepwood.eldroot_beaten\")"

## Set once a party member has LEARNED the field move from Nyra (the quest step reads it).
const F_TREEFELL_LEARNED := "deepwood.treefell_learned"

## THE FIELD MOVE (DECISIONS.md #41 / #71 / #92): id (its .tres under content/field_moves/), and who can
## LEARN it -- a member learns it from Nyra, HM-style, and only a member who knows it can fell a tree.
## KNOBS: the creature species (forms or evolution lines; the starter options are all here, so every
## journey has a learner) and the humans (character ids: the hero's unit "wren"; add "lyra" to let the
## Deepwood rival learn it too -- left out, since a guest leaves the party after the Eldroot battle).
const FIELD_MOVE_TREES_ID := "treefell"
const FIELD_MOVE_TREES_SPECIES: Array[String] = ["tree_grunt", "vineweave", "petalfang", "blightcap"]
const FIELD_MOVE_TREES_HUMANS: Array[String] = ["wren"]

## NYRA, the Deepwood chief (DECISIONS.md #85): a DUEL (#50), SCALED inside the Deep Woods band (#80)
## at this offset from the party's top level. PLACEHOLDER team (nature roster creatures; Eldroot is
## the legend, never hers) -- her FINAL creature is the one she uses the stone with (#38 / #67).
const NYRA_SCALE_OFFSET := 1
const NYRA_TEAM: Array[String] = ["petalfang", "vineweave", "blightcap"]
## TODO(bond): stone boost -- the bond / stone system is not built (#38 / #65 / #67). Until it is, her
## FINAL creature gets this small authored strength bump (the duel's stat multiplier).
const NYRA_STONE_BOOST := 1.15
const NYRA_PURSE := 400

## LYRA'S DEEPWOOD CHALLENGE (DECISIONS.md #94): a friendly spar SCALED with the party inside the Deep
## Woods band at this offset (a rival, not a chief: no boss XP). PLACEHOLDER team -- her Crownhaven
## partners (the rival duel's species).
const LYRA_DEEPWOOD_SCALE_OFFSET := 0
const LYRA_DEEPWOOD_TEAM := [{"character_id": "blightcap", "strength": 0.95}, {"character_id": "petalfang", "strength": 0.85}]
const LYRA_DEEPWOOD_PURSE := 150

## ELDROOT: the legend's TACTICAL board (a forest glade). The party fields up to ELDROOT_SQUAD_SIZE;
## Lyra fights in it as a TEMPORARY party member (joined after her Deepwood challenge; deploy her in
## the squad pick -- challenge skipped, she is simply not offered).
const ELDROOT_MAP_PATH := CONTENT + "battles/ow_deepwood_glade.tres"
const ELDROOT_SQUAD_SIZE := 4
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
	var hu: Array[StringName] = []
	for h in FIELD_MOVE_TREES_HUMANS:
		hu.append(StringName(h))
	fm.humans = hu
	# TODO(story): placeholder wording.
	fm.locked_hint = "A gnarled tree grows across the way. It could be felled -- if you knew how."
	fm.no_user_hint = "This tree could be felled with {move} -- but nobody fit in your party has learned it."
	fm.prompt_text = "This tree could be felled. Use {move}?"
	fm.used_text = "{user} used {move}!"
	fm.learned_text = "{user} learned {move}!"
	_save(fm, FieldMoveResource.path_for(FIELD_MOVE_TREES_ID))
	_build_sea_move()


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
	# Lyra (DECISIONS.md #88 / #94): met here; she challenges you, then keeps you company through the
	# Deep Woods (a temporary party member) and fights beside you against Eldroot. Her greeting is in
	# dialogue.json (areas.deepwood_village.lyra); the challenge is below.
	out.append(_lyra_deepwood())
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
## the hero must battle her to go through the forest; she then TEACHES the tree-felling move, #92).
## The duel comes first (#40); winning it makes the move teachable, and she teaches it to ONE eligible
## member the player picks ([method _nyra_teach]). Talking to her again teaches it to another.
func _nyra() -> NpcEntity:
	var nyra := _npc("nyra", DV_NYRA, "south", "NYRA", Color(0.3, 0.48, 0.3), "trainer")
	var won: Array = [
		_say([_line("nyra", "NYRA", "You've earned the way through. Now learn how we clear the old trees.")]),
	]
	won.append_array(_nyra_teach(false))
	won.append(SaveGameCommand.new())
	var ask := ChoiceCommand.new()
	ask.prompt = _line("nyra", "NYRA", "I'm {NYRA}, chief of Deepwood. To go through the forest, you battle me first. Ready?")
	ask.options = StoryCommand.list([
		ChoiceOption.make("Battle!", [_duel(_nyra_spec()), IfCommand.make("outcome() == \"victory\"", won)]),
		ChoiceOption.make("Not yet.", [], true),
	])
	var later: Array = _nyra_teach(true)
	later.append(SaveGameCommand.new())
	nyra.on_interact = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_NYRA_BEATEN, [ask], later),
	])
	return nyra


## NYRA TEACHES the field move (DECISIONS.md #92): to an eligible party member who does not know it
## yet (the player picks; one candidate and nobody knowing it = no question). Nobody eligible: she
## says to come back with one who can -- the move stays teachable. [param again] = a later visit
## (she offers it to another member, or just says her idle line). TODO(story): placeholder lines.
func _nyra_teach(again: bool) -> Array:
	return _teach_field_move("nyra", "NYRA", FIELD_MOVE_TREES_ID, F_TREEFELL_LEARNED, {
		"first": "Who will learn {move}?",
		"again": "Shall I teach {move} to another of yours?",
		# The maze's clue (#93): the lights mark the right way.
		"idle": "The deep forest turns travellers round. Follow the deepest roots and the greatest trees -- every other way leads you astray.",
		"none": "None of yours can learn {FIELD_MOVE_TREES} yet. Come back with one who can.",
	}, again)


## A CHIEF TEACHES a field move (DECISIONS.md #92; Nyra, Eloi): to an eligible party member who does
## not know it yet (the player picks; one candidate and nobody knowing it = no question). Nobody
## eligible: [param lines].none -- the move stays teachable. [param again] = a later visit (another
## member, or just [param lines].idle). [param lines]: first / again (the questions), idle, none.
func _teach_field_move(npc_id: String, name_key: String, move_id: String, learned_flag: String,
		lines: Dictionary, again: bool) -> Array:
	var cond_can: String = "can_learn_field_move(\"%s\")" % move_id
	var cond_knows: String = "knows_field_move(\"%s\")" % move_id
	var teach := TeachFieldMoveCommand.new()
	teach.move_id = StringName(move_id)
	teach.learned_flag = learned_flag
	var first_q := _line(npc_id, name_key, String(lines["first"]))
	var again_q := _line(npc_id, name_key, String(lines["again"]))
	var idle := _say([_line(npc_id, name_key, String(lines["idle"]))])
	var none := _say([_line(npc_id, name_key, String(lines["none"]))])
	if not again:
		teach.prompt = first_q
		return [IfCommand.make(cond_can, [teach, IfCommand.make(cond_knows, [idle])], [none])]
	var teach_again := teach.duplicate() as TeachFieldMoveCommand
	teach_again.prompt = again_q
	return [
		IfCommand.make(cond_can, [
			IfCommand.make(cond_knows, [teach_again], [teach]),
		], [
			IfCommand.make(cond_knows, [idle], [none]),
		]),
	]


## LYRA'S CHALLENGE (DECISIONS.md #60 / #94): a friendly rival DUEL -- a spar (never permadeath, a
## loss costs nothing: CONTINUE), SCALED with the party inside the Deep Woods band (not a boss).
## Her own encounter id; the Crownhaven rival's stage counter is not touched.
func _lyra_deepwood_spec() -> BattleSpec:
	var team: Array = []
	for row in LYRA_DEEPWOOD_TEAM:
		team.append((row as Dictionary).duplicate())
	var spec := _duel_spec(LYRA_DEEPWOOD_DUEL_ID, "{LYRA}", &"npc_lyra", team, true,
		BattleSpec.DefeatPolicy.CONTINUE, LYRA_DEEPWOOD_PURSE)
	BattleSpec.make_chief(spec, REGION_BANDS["woodlands"], LYRA_DEEPWOOD_SCALE_OFFSET)
	spec.boss_battle = false
	spec.clash_intro = true
	return spec


## Lyra in Deepwood Village (#88 / #94): talk -> she CHALLENGES you ("Not now" is fine: she blocks
## nothing -- only Nyra gates the trail). Once the bout is FOUGHT, whatever its outcome, she JOINS as
## a TEMPORARY member until Eldroot is beaten: no overworld follower (her village NPC hides while she
## is in the party), deployable in the Eldroot battle's squad pick. If the party is full she says so
## and joins when you talk to her again. TODO(story): placeholder lines.
func _lyra_deepwood() -> NpcEntity:
	var lyra := _npc("lyra", DV_LYRA, "north", "LYRA", Color(0.78, 0.5, 0.2), "trainer")
	# Here from the road opening until the Eldroot battle; hidden while she is in the party.
	lyra.visible_if = "(%s) and not has(\"%s\")" % [LYRA_IN_DEEPWOOD, F_LYRA_JOINED]
	var bout: Array = [_duel(_lyra_deepwood_spec())]
	bout.append(IfCommand.make(FOUGHT, [
		IfCommand.make("outcome() == \"victory\"", [
			_say([_line("lyra", "LYRA", "Good test. I'm coming with you into the deep forest.")]),  # TODO(story)
		], [
			_say([_line("lyra", "LYRA", "Good test. Let's go into the deep forest together.")]),  # TODO(story)
		]),
		_flag(F_LYRA_CHALLENGED),
	] + _lyra_comes_along(), [
		_say([_line("lyra", "LYRA", "Your partner can barely stand. Rest up first -- then we test each other.")]),  # TODO(story)
	]))
	var offer := ChoiceCommand.new()
	offer.prompt = _line("lyra", "LYRA", "Before the deep forest -- one bout, to test each other?")  # TODO(story)
	offer.options = StoryCommand.list([ChoiceOption.make("Let's go.", bout), ChoiceOption.make("Not now.", [], true)])
	lyra.on_interact = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_LYRA_CHALLENGED, [offer], _lyra_comes_along()),
	])
	return lyra


## Lyra JOINS: a TEMPORARY member (a human unit) at the party's level until Eldroot is beaten.
func _lyra_comes_along() -> Array:
	var j := _join(&"lyra", "", 0, F_LYRA_JOINED)
	j.temporary = true
	j.guest_until = F_ELDROOT_BEATEN
	j.match_party_level = true
	return [
		j,
		IfCommand.make("has(\"%s\")" % F_LYRA_JOINED, [SaveGameCommand.new()], [
			_say([_line("lyra", "LYRA", "Your party's full. Make room and I'll come along.")]),  # TODO(story)
		]),
	]


# --- The Depths of the Wood: THE MAZE (DECISIONS.md #93) -------------------------------
#
# Zelda's Lost Woods meets a Pokemon forest. A chain of LOOK-ALIKE forest rooms (one painter, one
# base), each ENCLOSED by walls of old trees several cells thick: the only walkable ground is a small
# central clearing, four 1-wide corridors out to the four exits, and the room's own side passages --
# tall-grass pockets and dead ends cut into the walls. You always come in from the south; of the other
# three exits ONE is RIGHT (on to the next room) and the two WRONG ones lead into THE TANGLED THICKET
# (#101: "wrong path followed equals tough battles, multiple enemy encounters"): a look-alike room
# thick with grass and strong wild creatures, every way out of which brings you back to the maze's
# entrance. The south exit goes back a room.
#
# THE CLUE (#101: "deeper roots and thicker trees indicate the correct path"; no dialogue needed): the
# RIGHT exit's mouth is flanked by two GREAT TREES and great ROOTS run along its corridor; the wrong
# exits are plain. The hunter in Deepwood Village, Nyra and a sign at the maze's entrance say "follow
# the deepest roots". (Roots and great trees are PLACEHOLDER props until the Blender models.)
#
# THE SKILL IS REQUIRED: in rooms 2 and 4 a BREAKABLE TREE stands in the right exit's mouth, between
# the lit lanterns (FieldObstacleEntity: felled for good, a saved flag). Room 3 has an optional nook
# behind another one (a chest). Tall-grass pockets (the Deep Woods' creatures, band 8-15) in every
# room, two optional trainers in side pockets, a chest at the end of a dead-end passage.
#
#   room 1 depths_of_the_wood    right: NORTH  (south: back to Deepwood Village; sign: the clue)
#   room 2 depths_of_the_wood_2  right: EAST   (gate tree; a trainer)
#   room 3 depths_of_the_wood_3  right: WEST   (a nook tree + chest; a trainer)
#   room 4 depths_of_the_wood_4  right: NORTH  (gate tree; a dead-end passage with a chest)
#   -> the HEART of the wood (depths_of_the_wood_heart): the clearing where ELDROOT waits.
#
# Deterministic: no RNG anywhere. KNOBS: DM_ROOMS (order, right exits, gates, carved side passages),
# the clearing's size, the lantern prop / tints / glow, the clue tile, the wrong-way toast.

## The maze rooms' size (all alike), and the clearing at their middle (everything else is forest
## wall unless a corridor or a room's carve opens it).
const DM_W := 19
const DM_H := 17
const DM_C := Vector2i(9, 8)
const DM_RX := 3.5
const DM_RY := 2.5
## Each exit's edge cell (the warp), keyed by its side.
const DM_EXITS := {"north": Vector2i(9, 0), "south": Vector2i(9, 16), "west": Vector2i(0, 8), "east": Vector2i(18, 8)}
## The three CHOICE exits (south is the way back).
const DM_CHOICES := ["north", "west", "east"]
## Each exit's MOUTH: the corridor cell where a gate tree stands ...
const DM_MOUTH := {"north": Vector2i(9, 2), "south": Vector2i(9, 14), "west": Vector2i(2, 8), "east": Vector2i(16, 8)}
## ... and the two cells flanking it, where the lantern posts stand (choice exits only).
const DM_FLANKS := {"north": [Vector2i(8, 2), Vector2i(10, 2)], "west": [Vector2i(2, 7), Vector2i(2, 9)],
	"east": [Vector2i(16, 7), Vector2i(16, 9)]}
## Where you stand arriving through each exit (just inside it), and the way you face.
const DM_INSIDE := {"north": [Vector2i(9, 1), "south"], "south": [Vector2i(9, 15), "north"],
	"west": [Vector2i(1, 8), "east"], "east": [Vector2i(17, 8), "west"]}
## THE MAZE, in order. "right" = the exit that advances; "gate" = a breakable tree in its mouth (the
## field move is REQUIRED); "carve" = the room's side passages cut into the walls: [Rect2i, tile]
## ("tall_grass" pockets, "forest_dirt" passages, "grass_plains" nooks), each joined to a corridor or
## the clearing.
const DM_ROOMS := [
	{"id": "depths_of_the_wood", "right": "north", "gate": false, "carve": [
		[Rect2i(2, 2, 4, 3), "tall_grass"], [Rect2i(6, 3, 3, 1), "forest_dirt"],
		[Rect2i(13, 11, 4, 3), "tall_grass"], [Rect2i(10, 12, 3, 1), "forest_dirt"]]},
	{"id": "depths_of_the_wood_2", "right": "east", "gate": true, "carve": [
		[Rect2i(2, 11, 4, 3), "tall_grass"], [Rect2i(3, 9, 1, 2), "forest_dirt"],
		[Rect2i(12, 2, 4, 3), "tall_grass"], [Rect2i(10, 3, 2, 1), "forest_dirt"]]},
	{"id": "depths_of_the_wood_3", "right": "west", "gate": false, "carve": [
		[Rect2i(10, 4, 3, 1), "forest_dirt"], [Rect2i(13, 4, 1, 1), "forest_dirt"], [Rect2i(14, 3, 3, 3), "grass_plains"],
		[Rect2i(13, 11, 4, 3), "tall_grass"], [Rect2i(14, 9, 1, 2), "forest_dirt"],
		[Rect2i(2, 2, 3, 3), "tall_grass"], [Rect2i(3, 5, 1, 3), "forest_dirt"]]},
	{"id": "depths_of_the_wood_4", "right": "north", "gate": true, "carve": [
		[Rect2i(3, 10, 4, 1), "forest_dirt"], [Rect2i(3, 11, 1, 1), "forest_dirt"], [Rect2i(2, 12, 3, 2), "grass_plains"],
		[Rect2i(12, 11, 4, 3), "tall_grass"], [Rect2i(12, 10, 1, 1), "forest_dirt"],
		[Rect2i(13, 2, 3, 3), "tall_grass"], [Rect2i(14, 5, 1, 3), "forest_dirt"]]},
]
## Room 3's nook: walled round, open only through its breakable tree; a chest at the back.
const DM_NOOK_TREE := Vector2i(13, 4)
const DM_NOOK_CHEST := Vector2i(16, 3)
## Room 4's dead-end passage chest.
const DM_POCKET_CHEST := Vector2i(2, 13)
## The entrance's signpost (room 1, in the clearing beside the path in).
const DM_SIGN := Vector2i(8, 10)
## The trainers (optional: in side pockets, looking into them, away from the paths).
const DM_FORAGER := Vector2i(5, 11)
const DM_TRAPPER := Vector2i(16, 13)
const LV_DM_FORAGER := 10
const LV_DM_TRAPPER := 12
## THE CLUE (#101): the GREAT TREES flanking the right exit's mouth and the ROOTS along its corridor
## (PLACEHOLDER props), and their tints.
const DM_CLUE_TREE_PROP := "great_tree"
const DM_CLUE_TREE_TINT := Color(0.2, 0.32, 0.17)
const DM_ROOTS_PROP := "roots"
const DM_ROOTS_TINT := Color(0.34, 0.24, 0.15)
## The right exit's corridor ground (under the roots).
const DM_CLUE_TILE := "forest_dirt"
## THE TANGLED THICKET -- where every wrong way leads (#101): its area id, the toasts going in and out
## (TODO(story): placeholder wording), and its wild creatures: frequent HIDDEN rolls, at the top of the
## Deep Woods band.
const DM_LOST_ID := "depths_of_the_wood_lost"
const DM_LOST_TOAST := "The trees close in behind you..."
const DM_FOUND_TOAST := "...and somehow you find your way back to where you began."
const DM_LOST_RATE := 0.3
const DM_LOST_BAND := Vector2i(14, 15)
const DM_LOST_TABLE := [["vineweave", 2.0], ["petalfang", 1.5], ["blightcap", 1.0]]
const DM_LOST_ROOM := {"id": DM_LOST_ID, "right": "", "gate": false, "carve": [
	[Rect2i(2, 2, 5, 5), "tall_grass"], [Rect2i(12, 2, 5, 5), "tall_grass"], [Rect2i(2, 10, 5, 5), "tall_grass"],
	[Rect2i(12, 10, 5, 5), "tall_grass"], [Rect2i(7, 5, 5, 7), "tall_grass"]]}
## The heart of the wood: the clearing at the end of the maze, where Eldroot waits.
const DM_HEART_ID := "depths_of_the_wood_heart"
const DH_W := 19
const DH_H := 14
const DH_GLADE_C := Vector2i(9, 5)
const DH_ELDROOT := Vector2i(9, 4)


## The corridor cells of exit [param side]: from its mouth out to the edge.
func _dm_right_corridor(side: String) -> Array:
	var out: Array = []
	var mouth: Vector2i = DM_MOUTH[side]
	var edge: Vector2i = DM_EXITS[side]
	var step := Vector2i(signi(edge.x - mouth.x), signi(edge.y - mouth.y))
	var c: Vector2i = mouth
	out.append(c)
	while c != edge:
		c += step
		out.append(c)
	return out


func _dm_in_clearing(x: int, y: int) -> bool:
	var dx: float = (float(x) - float(DM_C.x)) / DM_RX
	var dy: float = (float(y) - float(DM_C.y)) / DM_RY
	return dx * dx + dy * dy <= 1.0


## A room's ground: forest WALL everywhere except the clearing, the four corridors (the cross of
## paths through the middle), the lantern posts' cells and the room's carves.
func _dm_terrain(room: Dictionary, x: int, y: int) -> String:
	var c := Vector2i(x, y)
	# The right exit's corridor (mouth to edge): a path under the great roots. (The thicket has none.)
	var right: String = String(room["right"])
	if not right.is_empty() and _dm_right_corridor(right).has(c):
		return DM_CLUE_TILE
	for d in DM_EXITS:
		if c == DM_EXITS[d]:
			return "forest_dirt"
	if x == 0 or y == 0 or x == DM_W - 1 or y == DM_H - 1:
		return "tree"
	for d in DM_FLANKS:
		if (DM_FLANKS[d] as Array).has(c):
			# Under a great tree (solid) at the right exit; ordinary forest at the others.
			return "grass_plains" if d == right else "tree"
	# The cross of paths: the corridors out to the four exits, and on through the clearing.
	if x == DM_C.x or y == DM_C.y:
		return "forest_dirt"
	for cv in room["carve"]:
		if (cv[0] as Rect2i).has_point(c):
			return String(cv[1])
	if _dm_in_clearing(x, y):
		return "grass_plains"
	return "tree"

func _build_depths_of_the_wood() -> void:
	for i in range(DM_ROOMS.size()):
		_build_depths_room(i)
	_build_lost_thicket()
	_build_depths_heart()


## THE CLUE at exit [param right] (#101): two GREAT TREES flanking its mouth, great ROOTS along its corridor.
func _dm_clue(right: String) -> Array:
	var out: Array = []
	for f in DM_FLANKS[right]:
		var fc: Vector2i = f
		out.append(_prop("great_tree_%d_%d" % [fc.x, fc.y], DM_CLUE_TREE_PROP, fc, Vector2i.ONE, DM_CLUE_TREE_TINT, true))
	for c in _dm_right_corridor(right):
		var rc: Vector2i = c
		out.append(_prop("roots_%d_%d" % [rc.x, rc.y], DM_ROOTS_PROP, rc, Vector2i.ONE, DM_ROOTS_TINT))
	return out


## THE TANGLED THICKET (#101): a look-alike room choked with grass, where the wrong ways lead -- frequent
## HIDDEN encounters with the Deep Woods' strongest creatures; every way out returns you to the maze's
## entrance.
func _build_lost_thicket() -> void:
	var room: Dictionary = DM_LOST_ROOM
	var aid: String = DM_LOST_ID
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + "areas/" + aid))
	var t := _new_map("Depths of the Wood", DM_W, DM_H,
		"The Depths of the Wood: a tangled thicket where the wrong ways lead. Story-mode terrain.")
	t.lighting_preset = "Dusk"
	_paint(t, func(x: int, y: int) -> String: return _dm_terrain(room, x, y))
	_add_validator_anchors(t, DM_INSIDE["south"][0], DM_C)
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)
	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	a.display_name = "Depths of the Wood"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "depths_of_the_wood")
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	var south_in: Array = DM_INSIDE["south"]
	a.entry_points = {"south": {"cell": [south_in[0].x, south_in[0].y, 0], "facing": south_in[1]}}
	var ents: Array = []
	var entrance: StringName = StringName(String(DM_ROOMS[0]["id"]))
	for d in DM_EXITS:
		var cell: Vector2i = DM_EXITS[d]
		var out := _warp("%s_exit" % d, Rect2i(cell.x, cell.y, 1, 1), entrance, &"south")
		out.arrival_toast = DM_FOUND_TOAST
		ents.append(out)
	ents.append_array(_dm_thickets(room))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	var zone := EncounterZone.new()
	zone.mode = EncounterZone.Mode.HIDDEN
	var ids: Array[StringName] = [&"tall_grass", &"forest_dirt"]
	zone.tile_ids = ids
	zone.rate = DM_LOST_RATE
	zone.grace_steps = 1
	zone.level_band = DM_LOST_BAND
	var table: Array[Resource] = []
	for pair in DM_LOST_TABLE:
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


func _build_depths_room(i: int) -> void:
	var room: Dictionary = DM_ROOMS[i]
	var aid: String = String(room["id"])
	var right: String = String(room["right"])
	var t := _new_map("Depths of the Wood", DM_W, DM_H,
		"The Depths of the Wood (room %d of the maze): old forest north of Deepwood Village. Story-mode terrain." % (i + 1))
	t.lighting_preset = "Dusk"
	_paint(t, func(x: int, y: int) -> String: return _dm_terrain(room, x, y))
	_add_validator_anchors(t, DM_INSIDE["south"][0], DM_C)
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)

	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	# Every room has the same name: the location popup never tells you which one you are in.
	a.display_name = "Depths of the Wood"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "depths_of_the_wood")
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	var south_in: Array = DM_INSIDE["south"]
	var back_in: Array = DM_INSIDE[right]
	a.entry_points = {
		"south": {"cell": [south_in[0].x, south_in[0].y, 0], "facing": south_in[1]},
		"back": {"cell": [back_in[0].x, back_in[0].y, 0], "facing": back_in[1]},
	}
	var ents: Array = []
	var entrance: StringName = StringName(String(DM_ROOMS[0]["id"]))
	for d in DM_EXITS:
		var cell: Vector2i = DM_EXITS[d]
		var rect := Rect2i(cell.x, cell.y, 1, 1)
		if d == "south":
			if i == 0:
				ents.append(_warp("south_exit", rect, &"deepwood_village", &"north_trail"))
			else:
				ents.append(_warp("south_exit", rect, StringName(String(DM_ROOMS[i - 1]["id"])), &"back"))
		elif d == right:
			var next: String = String(DM_ROOMS[i + 1]["id"]) if i + 1 < DM_ROOMS.size() else DM_HEART_ID
			ents.append(_warp("%s_exit" % d, rect, StringName(next), &"south"))
		else:
			# A WRONG way: into the tangled thicket (tough wild creatures), then back to the entrance.
			var lost := _warp("%s_exit" % d, rect, StringName(DM_LOST_ID), &"south")
			lost.arrival_toast = DM_LOST_TOAST
			ents.append(lost)
	ents.append_array(_dm_clue(right))
	if bool(room["gate"]):
		ents.append(_breakable_tree(aid, "gate_tree", DM_MOUTH[right]))
	ents.append_array(_depths_room_extras(i, aid))
	ents.append_array(_dm_thickets(room))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	a.encounter_zones = _depths_grass_zones()
	_save(a, CONTENT + "areas/%s/area.tres" % aid)


## The forest WALL made dense: THICKET props (the tree tile's own art, extra trees per cell) laid
## over every block of the room's tree terrain -- walk-over props, the terrain blocks. The wall cells
## are cut into rectangles greedily (row by row, deterministic).
func _dm_thickets(room: Dictionary) -> Array:
	var out: Array = []
	var taken: Dictionary = {}
	# The row just SOUTH of open ground keeps its single tile tree: the camera looks from the south,
	# so a thicket there would hide the path (and the hero) behind it.
	var wall := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < DM_W and y < DM_H and not taken.has(Vector2i(x, y)) \
			and _dm_terrain(room, x, y) == "tree" and (y == 0 or _dm_terrain(room, x, y - 1) == "tree")
	for y in range(DM_H):
		for x in range(DM_W):
			if not wall.call(x, y):
				continue
			var w: int = 1
			while wall.call(x + w, y):
				w += 1
			var h: int = 1
			var grow: bool = true
			while grow:
				for xx in range(x, x + w):
					if not wall.call(xx, y + h):
						grow = false
						break
				if grow:
					h += 1
			for yy in range(y, y + h):
				for xx in range(x, x + w):
					taken[Vector2i(xx, yy)] = true
			out.append(_prop("thicket_%d_%d" % [x, y], "thicket", Vector2i(x, y), Vector2i(w, h), Color.WHITE))
	return out


## Each room's own things: the entrance sign, the trainers, the nook and the pocket chests.
## TODO(story): placeholder lines and generic placeholder trainers (no named cast).
func _depths_room_extras(i: int, aid: String) -> Array:
	var out: Array = []
	match i:
		0:
			out.append(_sign("maze_sign", DM_SIGN, "Old Signpost",
				"The deep forest turns travellers round.\nFollow the deepest roots and the greatest trees."))
		1:
			out.append(_depths_trainer("forager", DM_FORAGER, "west", "FORAGER", Color(0.46, 0.5, 0.3),
				[{"character_id": "blightcap", "strength": 0.9}, {"character_id": "petalfang", "strength": 0.8}],
				LV_DM_FORAGER, 140,
				"You're lost too? Then let's battle while we're at it!",
				"Ha. Well, at least one of us knows where they're going."))
		2:
			out.append(_depths_trainer("trapper", DM_TRAPPER, "west", "TRAPPER", Color(0.4, 0.34, 0.26),
				[{"character_id": "vineweave", "strength": 0.9}, {"character_id": "tree_grunt", "strength": 0.85}],
				LV_DM_TRAPPER, 180,
				"Quiet! You'll scare off-- oh, it's a battle you want? Fine!",
				"All right, all right. Go on, then."))
			out.append(_breakable_tree(aid, "nook_tree", DM_NOOK_TREE))
			var nook := _chest("nook_chest", DM_NOOK_CHEST, "west", [&"heartwood_tonic", &"clearwater_draught"], 60)
			# Out of reach (and out of sight) until its tree is felled.
			nook.visible_if = "has(\"%s\")" % FieldObstacleEntity.flag_for(aid, "nook_tree")
			out.append(nook)
		3:
			out.append(_chest("pocket_chest", DM_POCKET_CHEST, "east", [&"heartwood_tonic"], 40))
	return out


func _chest(id: String, cell: Vector2i, facing: String, items: Array, gold: int) -> ChestEntity:
	var chest := ChestEntity.new()
	chest.id = StringName(id)
	chest.cell = Vector3i(cell.x, cell.y, 0)
	chest.facing = facing
	chest.display_name = "Chest"
	chest.tint = Color(0.42, 0.3, 0.18)
	var loot: Array[StringName] = []
	for it in items:
		loot.append(StringName(it))
	chest.loot_items = loot
	chest.loot_gold = gold
	return chest


## An OPTIONAL trainer in the maze: a DUEL (a real battle: a loss whites out), a short sight line
## pointed AWAY from the paths, so walking the right way never forces the fight.
func _depths_trainer(id: String, cell: Vector2i, facing: String, name_key: String, tint: Color, team: Array,
		level: int, purse: int, pre: String, after: String) -> TrainerEntity:
	var t := TrainerEntity.new()
	t.id = StringName(id)
	t.cell = Vector3i(cell.x, cell.y, 0)
	t.facing = facing
	t.display_name = _t("{%s}" % name_key)
	t.speaker_name = t.display_name
	t.speaker_id = StringName("npc_" + id)
	t.tint = tint
	t.figure = "trainer"
	t.body = _body_of(name_key)
	t.sight_range = 2
	t.pre_scene = _scene("depths_%s_pre" % id, [_beat(&"self", "", pre)])
	t.defeated_scene = _scene("depths_%s_after" % id, [_beat(&"self", "", after)])
	var spec := _duel_spec("", "{%s}" % name_key, StringName("npc_" + id), team, false,
		BattleSpec.DefeatPolicy.WHITEOUT, purse)
	spec.enemy_level = level
	spec.clash_intro = true
	t.battle = spec
	return t


## The Deep Woods' wild grass (every maze room): the nature roster placeholders, in the band (8-15).
func _depths_grass_zones() -> Array[Resource]:
	var zone := EncounterZone.new()
	var ids: Array[StringName] = [&"tall_grass"]
	zone.tile_ids = ids
	zone.rate = 0.12
	zone.grace_steps = 3
	var table: Array[Resource] = []
	for pair in [["petalfang", 2.0], ["blightcap", 2.0], ["tree_grunt", 1.5], ["vineweave", 1.0]]:
		var e := EncounterEntry.new()
		e.character_id = StringName(pair[0])
		e.weight = pair[1]
		e.kind = EncounterEntry.Kind.DUEL
		e.can_befriend = true
		table.append(e)
	zone.table = table
	var zones: Array[Resource] = [zone]
	return zones


# --- The heart of the wood: the clearing where Eldroot waits ---------------------------

func _dh_terrain(x: int, y: int) -> String:
	if x == DH_GLADE_C.x and y == DH_H - 1:
		return "forest_dirt"
	if x == 0 or y == 0 or x == DH_W - 1 or y == DH_H - 1:
		return "tree"
	var gx: float = (float(x) - float(DH_GLADE_C.x)) / 6.0
	var gy: float = (float(y) - float(DH_GLADE_C.y)) / 3.6
	if gx * gx + gy * gy <= 1.0:
		return "sacred_meadow"
	# The path up from the south into the glade.
	if x == DH_GLADE_C.x and y > DH_GLADE_C.y:
		return "forest_dirt"
	var ox: float = (float(x) - float(DH_GLADE_C.x)) / 8.0
	var oy: float = (float(y) - float(DH_GLADE_C.y)) / 5.6
	if ox * ox + oy * oy <= 1.0:
		return "grass_plains"
	return "tree"


func _build_depths_heart() -> void:
	var aid: String = DM_HEART_ID
	var t := _new_map("Heart of the Wood", DH_W, DH_H,
		"The heart of the Deep Woods: the clearing at the end of the maze, where Eldroot waits. Story-mode terrain.")
	t.lighting_preset = "Dusk"
	_paint(t, _dh_terrain)
	_add_validator_anchors(t, Vector2i(DH_GLADE_C.x, DH_H - 2), Vector2i(DH_GLADE_C.x, DH_GLADE_C.y + 2))
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)

	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	a.display_name = "Heart of the Wood"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "depths_of_the_wood")
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	a.entry_points = {
		"south": {"cell": [DH_GLADE_C.x, DH_H - 2, 0], "facing": "north"},
	}
	var ents: Array = []
	# Back into the maze: the last room, just inside its right exit.
	ents.append(_warp("south_exit", Rect2i(DH_GLADE_C.x, DH_H - 1, 1, 1),
		StringName(String(DM_ROOMS[DM_ROOMS.size() - 1]["id"])), &"back"))
	ents.append(_eldroot())
	_add_doors(a, ents)
	a.entities = _entities(ents)
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


## Eldroot in the clearing at the heart of the wood (the end of the maze), until the hero bonds with
## it. Talk: face it (the legend battle) -> on a win, the OPTIONAL bond (#75). Declined: it stays, and
## talking to it again offers the bond again. TODO(story): placeholder narration.
func _eldroot() -> NpcEntity:
	var e := NpcEntity.new()
	e.id = &"eldroot"
	e.cell = Vector3i(DH_ELDROOT.x, DH_ELDROOT.y, 0)
	e.facing = "south"
	e.display_name = _species_name(&"eldroot")
	e.speaker_name = e.display_name
	e.visual_character = &"eldroot"
	e.visible_if = "not has(\"%s\")" % F_ELDROOT_BONDED
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
## two Barklings screening it; your squad chairs at the south edge (the squad pick fills them: the hero, your
## creatures and Lyra, a temporary party member).
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
	for c in [Vector2i(4, 8), Vector2i(6, 8), Vector2i(8, 8), Vector2i(5, 9)]:
		m.set_character_spawn_at_position(c, 0, String(STARTER_ID))
	m.set_character_spawn_at_position(anchor, 1, "eldroot", "BOSS")
	for c in [Vector2i(3, 3), Vector2i(8, 3)]:
		m.set_character_spawn_at_position(c, 1, "tree_grunt")
		m.unit_spawns[m.unit_spawns.size() - 1]["level"] = LV_ELDROOT_SCREEN
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, ELDROOT_MAP_PATH)


# =====================================================================================
#  THE REGIONS PAST THE HEARTLANDS: their roads (DECISIONS.md #76 -- open, never one forced path)
# =====================================================================================
#
# The coast (Crownhaven's harbour gate, River Crossing's coast road), the Snowy Peaks (Woodland
# Town's north trail) and the Rocky Badlands (Crownhaven's east gate) open together, silently, the
# first time the hero passes through the town each road leaves from after [constant
# REGION_ROADS_OPEN_IF]. The regional bands (REGION_BANDS) and the chiefs' scaling (#80) do the
# pacing; nothing forces an order.

## Flags (save keys -- never rename once shipped): the places' open flags in WORLD_LOCATIONS.
const F_BEACH_ROAD_OPEN := "world.beach_road_open"
const F_FROSTPEAK_OPEN := "world.frostpeak_open"
const F_BADLANDS_OPEN := "world.badlands_open"
## KNOB: when those roads open. The opening's end, for now.
const REGION_ROADS_OPEN_IF := "has(\"opening.complete\")"


## A DUEL TRAINER on a route or in a dungeon (optional or not, by where it stands): a real battle, a
## loss whites out. [param sight] cells of sight along its facing; [param prefix] keys its scenes.
func _duel_trainer(prefix: String, id: String, cell: Vector2i, facing: String, name_key: String, tint: Color,
		figure: String, team: Array, level: int, purse: int, pre: String, after: String, sight: int = 3) -> TrainerEntity:
	var t := TrainerEntity.new()
	t.id = StringName(id)
	t.cell = Vector3i(cell.x, cell.y, 0)
	t.facing = facing
	t.display_name = _t("{%s}" % name_key)
	t.speaker_name = t.display_name
	t.speaker_id = StringName("npc_" + id)
	t.tint = tint
	t.figure = figure
	t.body = _body_of(name_key)
	t.sight_range = sight
	t.pre_scene = _scene("%s_%s_pre" % [prefix, id], [_beat(&"self", "", pre)])
	t.defeated_scene = _scene("%s_%s_after" % [prefix, id], [_beat(&"self", "", after)])
	var spec := _duel_spec("", "{%s}" % name_key, StringName("npc_" + id), team, false,
		BattleSpec.DefeatPolicy.WHITEOUT, purse)
	spec.enemy_level = level
	spec.clash_intro = true
	t.battle = spec
	return t


## A VISIBLE wild-creature zone on [param tiles] with [param pairs] ([character id, weight]) -- the
## area's band. Befriendable, like every wild creature.
func _wild_zone(tiles: Array, pairs: Array) -> EncounterZone:
	var zone := EncounterZone.new()
	var ids: Array[StringName] = []
	for t in tiles:
		ids.append(StringName(String(t)))
	zone.tile_ids = ids
	zone.rate = 0.12
	zone.grace_steps = 3
	var table: Array[Resource] = []
	for pair in pairs:
		var e := EncounterEntry.new()
		e.character_id = StringName(pair[0])
		e.weight = pair[1]
		e.kind = EncounterEntry.Kind.DUEL
		e.can_befriend = true
		table.append(e)
	zone.table = table
	return zone


## A legend-style BOND offer for creature [param character_id] (#39 / #69 / #75): "Bond" records it
## in the journey's legend list (never the party) and sets [param flag]; "Not now" leaves it.
func _bond_offer(character_id: String, flag: String, prompt: String) -> ChoiceCommand:
	var bond_cmd := BondLegendCommand.new()
	bond_cmd.character_id = StringName(character_id)
	var bond := ChoiceCommand.new()
	bond.prompt = _narr(prompt)
	bond.options = StoryCommand.list([
		ChoiceOption.make("Bond", [bond_cmd, _flag(flag), SaveGameCommand.new()]),
		ChoiceOption.make("Not now", [], true),
	])
	return bond


# =====================================================================================
#  THE SUNLIT COAST -- Beach Village (DECISIONS.md #41, #43, #50, #67, #71, #80, #85, #88)
# =====================================================================================
#
#   Crownhaven's harbour gate (the north road) / River Crossing's coast road (the west road)
#     -> BEACH VILLAGE: huts on the sand above a boardwalk promenade, two piers out over the sea, the
#        Wayshrine. ELOI, the sea chief (#85): a SCALED chief DUEL (#50 / #80). Winning makes the sea
#        field move TEACHABLE and he TEACHES it (#41 / #43 / #92): a member that can -- a creature, the
#        owner's "traverse the water with a creature" -- LEARNS it.
#     -> THE SEA: with the move, face the water, Confirm, "Use Tideride?" -> the hero rides out on the
#        member who learned it ([RideFieldMoveCommand]); stepping onto any land ends the ride. An islet
#        off the east pier holds a chest only the sea reaches; the sea route to the isles (the south
#        edge) stays closed until the isles are built.
#     -> CAEL (#88): met here -- a friendly rival (#60), an optional spar.
#
# All lines are short neutral PLACEHOLDERS (TODO(story)) -- the owner's facts only.

const F_ELOI_BEATEN := "beach.eloi_beaten"
## The sea move is granted (FieldMoveResource.unlock_flag), and a member has learned it (the quest step).
const F_TIDERIDE := "fieldmove.tideride"
const F_TIDERIDE_LEARNED := "beach.tideride_learned"
## Cael's spar has been fought (win or lose).
const F_CAEL_SPARRED := "beach.cael_sparred"
const ELOI_DUEL_ID := "beach.chief.eloi"
const CAEL_DUEL_ID := "beach.rival.cael"

## THE SEA MOVE (#41 / #43 / #71): a TRAVEL field move -- its tiles are passable while a member who
## learned it carries the hero. Creatures only (#43: "with a creature"). KNOBS: the water creatures
## (forge imports -- PLACEHOLDERS with no battle moves yet) and the starter options, so every journey
## has a learner (as with Treefell).
const FIELD_MOVE_SEA_ID := "tideride"
const FIELD_MOVE_SEA_TILES: Array[String] = ["deep_water"]
const FIELD_MOVE_SEA_SPECIES: Array[String] = ["aquaoct", "supaoctto", "holly_snowman", "mystic_snow_spirit",
	"storm_vessel", "tree_grunt", "petalfang", "blightcap"]

## ELOI, the sea chief (#85): a DUEL (#50) SCALED inside the coast band (#80) at this offset. PLACEHOLDER
## team (battle-ready roster stand-ins: the coast's water creatures have no moves yet) -- his FINAL
## creature carries the stone placeholder (#38 / #67).
const ELOI_SCALE_OFFSET := 1
const ELOI_TEAM: Array[String] = ["mycothrall", "gem_knight", "vineweave"]
## TODO(bond): the stone boost placeholder (the duel's strength multiplier on his final creature).
const ELOI_STONE_BOOST := 1.15
const ELOI_PURSE := 500
## CAEL'S SPAR (#60 / #88): friendly, SCALED with the party inside the coast band (a rival, not a chief:
## no boss XP). PLACEHOLDER team (his ceremony creature first).
const CAEL_SCALE_OFFSET := 0
const CAEL_TEAM := [{"character_id": "mycothrall", "strength": 0.95}, {"character_id": "petalfang", "strength": 0.85}]
const CAEL_PURSE := 180

const BV_W := 28
const BV_H := 22
## The roads in: north to Crownhaven's harbour gate, west to River Crossing.
const BV_NORTH_X := 6
const BV_WEST_Y := 7
## The boardwalk promenade along the beach, and the first row of sea.
const BV_PROM_Y := 11
const BV_SEA_Y := 13
## The huts, Eloi's longhouse, the Wayshrine.
const BV_HUTS := [Rect2i(2, 4, 3, 2), Rect2i(9, 4, 3, 2), Rect2i(13, 6, 3, 2)]
const BV_ELOI_HOUSE := Rect2i(19, 3, 5, 3)
const BV_SHRINE := Vector2i(11, 9)
## The piers (planks over the water) and the islet the sea move reaches.
const BV_PIERS := [Rect2i(6, 13, 1, 6), Rect2i(17, 13, 1, 5), Rect2i(16, 18, 3, 1)]
const BV_ISLET := Rect2i(22, 16, 4, 3)
const BV_ISLET_CHEST := Vector2i(23, 17)
## The sea route to the isles (closed: the isles are not built).
const BV_SEA_ROUTE := Rect2i(10, 21, 4, 1)
const BV_ELOI := Vector2i(21, 7)
const BV_CAEL := Vector2i(7, 10)


func _build_sea_move() -> void:
	var fm := FieldMoveResource.new()
	fm.id = StringName(FIELD_MOVE_SEA_ID)
	fm.display_name = _t("{FIELD_MOVE_SEA}")
	fm.unlock_flag = F_TIDERIDE
	var sp: Array[StringName] = []
	for s in FIELD_MOVE_SEA_SPECIES:
		sp.append(StringName(s))
	fm.species = sp
	var tiles: Array[StringName] = []
	for t in FIELD_MOVE_SEA_TILES:
		tiles.append(StringName(t))
	fm.travel_tiles = tiles
	fm.travel_verb = "Ride"
	# TODO(story): placeholder wording.
	fm.locked_hint = "The sea stretches out, deep and blue. With the right partner, you could cross it."
	fm.no_user_hint = "The sea could be crossed with {move} -- but nobody fit in your party has learned it."
	fm.prompt_text = "The water is deep. Use {move}?"
	fm.used_text = "{user} used {move}!"
	fm.learned_text = "{user} learned {move}!"
	_save(fm, FieldMoveResource.path_for(FIELD_MOVE_SEA_ID))


func _bv_buildings() -> Array:
	return BV_HUTS + [BV_ELOI_HOUSE]


func _bv_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if BV_ISLET.has_point(c):
		return "sand"
	if _in(BV_PIERS, c):
		return "wooden_planks"
	if y >= BV_SEA_Y:
		return "deep_water"
	# The two roads in.
	if x == BV_NORTH_X and y <= 3:
		return "forest_dirt"
	if y == BV_WEST_Y and x <= 3:
		return "forest_dirt"
	if x == 0 or y == 0 or x == BV_W - 1:
		return "tree"
	if _in(_bv_buildings(), c):
		return "stone_wall"
	if c == BV_SHRINE:
		return "sacred_ground"
	# The boardwalk promenade above the beach.
	if y == BV_PROM_Y and x >= 2 and x <= BV_W - 3:
		return "wooden_planks"
	# The grassy bluff the roads come down from; sand below it.
	if y <= 3:
		return "tree" if _h(x, y, 71) < 0.18 and absi(x - BV_NORTH_X) > 1 else "grass_plains"
	return "sand"


func _build_beach_village() -> void:
	var t := _new_map("Beach Village", BV_W, BV_H,
		"Beach Village: a harbour village on the sand, south-east of Crownhaven. Story-mode terrain.")
	t.lighting_preset = "Day"
	_paint(t, _bv_terrain)
	_add_validator_anchors(t, Vector2i(BV_NORTH_X, 1), Vector2i(BV_SHRINE.x, BV_SHRINE.y + 1))
	_save(t, CONTENT + "areas/beach_village/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"beach_village"
	a.display_name = "Beach Village"
	a.kind = OverworldAreaResource.Kind.TOWN
	_place(a, "beach_village")
	a.terrain = load(CONTENT + "areas/beach_village/terrain.tres")
	a.entry_points = {
		"north_road": {"cell": [BV_NORTH_X, 1, 0], "facing": "south"},
		"west_road": {"cell": [1, BV_WEST_Y, 0], "facing": "east"},
		"wayshrine": {"cell": [BV_SHRINE.x, BV_SHRINE.y + 1, 0], "facing": "north"},
		# Back from the open sea, on the water (riding).
		"sea_route": {"cell": [BV_SEA_ROUTE.position.x + 1, BV_SEA_ROUTE.position.y - 1, 0], "facing": "north"},
	}
	var ents: Array = []
	ents.append_array(_bv_scenery())
	ents.append(_shrine(BV_SHRINE, "Beach Wayshrine"))
	ents.append_array(_bv_people())
	ents.append(_warp("north_exit", Rect2i(BV_NORTH_X, 0, 1, 1), &"crownhaven", &"harbour_gate"))
	ents.append(_warp("west_exit", Rect2i(0, BV_WEST_Y, 1, 1), &"river_crossing", &"east_road"))
	# The sea route south: reached only by sea, out to the waters off Stormreef Isle -- calm, or (in the
	# post-game, #98) with the new volcanic island standing in them.
	ents.append(_warp("sea_route", BV_SEA_ROUTE, &"stormreef_waters", &"north", "not (%s)" % POSTGAME))
	ents.append(_warp("sea_route_erupted", BV_SEA_ROUTE, &"stormreef_waters_erupted", &"north", POSTGAME))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	a.on_enter = StoryCommand.list([
		IfCommand.make("not has(\"beach.arrived\")", [_flag("beach.arrived")]),
	])
	_save(a, CONTENT + "areas/beach_village/area.tres")


func _bv_scenery() -> Array:
	var out: Array = []
	var driftwood := Color(0.56, 0.46, 0.34)
	var sea_blue := Color(0.24, 0.42, 0.56)
	# PLACEHOLDER huts (cabins until the Blender models arrive) and Eloi's longhouse.
	for i in range(BV_HUTS.size()):
		var r: Rect2i = BV_HUTS[i]
		out.append(_prop("hut_%d" % i, "cabin", r.position, r.size, [driftwood, sea_blue.lightened(0.2)][i % 2]))
	out.append(_prop("eloi_house", "house", BV_ELOI_HOUSE.position, BV_ELOI_HOUSE.size, sea_blue))
	out.append(_prop("banner_eloi", "banner", Vector2i(BV_ELOI_HOUSE.position.x - 1, BV_ELOI_HOUSE.end.y - 1), Vector2i.ONE, sea_blue, true))
	for pc in [Vector2i(1, 9), Vector2i(26, 8), Vector2i(18, 9), Vector2i(8, 8), Vector2i(24, 17)]:
		out.append(_prop("palm_%d_%d" % [pc.x, pc.y], "palm", pc, Vector2i.ONE, Color.WHITE, true))
	for bc in [Vector2i(3, 12), Vector2i(24, 12)]:
		out.append(_prop("boat_%d_%d" % [bc.x, bc.y], "boat", bc, Vector2i.ONE, [driftwood, sea_blue][bc.x % 2], true))
	out.append(_prop("barrels_pier", "barrels", Vector2i(8, 12), Vector2i.ONE, Color.WHITE, true))
	out.append(_prop("nets", "logs", Vector2i(15, 12), Vector2i.ONE, driftwood, true))
	for lc in [Vector2i(5, 10), Vector2i(16, 10)]:
		out.append(_prop("lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.82, 0.45), true))
	return out


func _bv_people() -> Array:
	var out: Array = []
	out.append(_sign("village_sign", Vector2i(4, BV_WEST_Y + 1), "Beach Village",
		"BEACH VILLAGE\nNorth: Crownhaven.  West: River Crossing."))
	out.append(_eloi())
	out.append(_cael())
	# Villagers: one placeholder line each in dialogue.json (areas.beach_village.<id>).
	out.append(_npc("bv_fisher", Vector2i(6, 18), "south", "BEACH_FISHER", Color(0.3, 0.46, 0.56), "villager"))
	out.append(_npc("bv_net_mender", Vector2i(14, 9), "west", "NET_MENDER", Color(0.6, 0.5, 0.36), "villager"))
	out.append(_npc("bv_harbour_hand", Vector2i(16, 18), "west", "HARBOUR_HAND", Color(0.4, 0.4, 0.46), "villager"))
	out.append(_npc("bv_child", Vector2i(4, 9), "east", "BEACH_CHILD", Color(0.86, 0.6, 0.36), "child"))
	# Only the sea reaches it.
	out.append(_chest("islet_chest", BV_ISLET_CHEST, "north", [&"dawnpetal_draught", &"clearwater_draught"], 120))
	return out


## ELOI'S CHIEF DUEL (#50 / #80): SCALED inside the coast band, a boss battle for XP. A loss whites
## out (he waits); a win grants the sea move.
func _eloi_spec() -> BattleSpec:
	var team: Array = []
	for i in range(ELOI_TEAM.size()):
		var row: Dictionary = {"character_id": ELOI_TEAM[i], "strength": 1.0}
		if i == ELOI_TEAM.size() - 1:
			# TODO(bond): stone boost -- he uses the stone with his FINAL creature (#38 / #67).
			row["strength"] = ELOI_STONE_BOOST
		team.append(row)
	var spec := _duel_spec(ELOI_DUEL_ID, "{ELOI}", &"npc_eloi", team, false, BattleSpec.DefeatPolicy.WHITEOUT,
		ELOI_PURSE, [], [F_ELOI_BEATEN, F_TIDERIDE])
	BattleSpec.make_chief(spec, REGION_BANDS["sunlit_coast"], ELOI_SCALE_OFFSET)
	spec.clash_intro = true
	return spec


## Eloi by his longhouse. TODO(story): placeholder lines -- owner facts only (the sea chief; beating
## him grants the power to traverse the sea, #43). The duel first; winning makes the move teachable
## and he teaches it to ONE eligible member the player picks; talk to him again for another.
func _eloi() -> NpcEntity:
	var eloi := _npc("eloi", BV_ELOI, "south", "ELOI", Color(0.24, 0.4, 0.56), "elder")
	var won: Array = [
		_say([_line("eloi", "ELOI", "Well fought. The sea will carry you now -- let me show one of yours how.")]),
	]
	won.append_array(_eloi_teach(false))
	won.append(SaveGameCommand.new())
	var ask := ChoiceCommand.new()
	ask.prompt = _line("eloi", "ELOI", "I'm {ELOI}, chief of this village. Show me your strength, and the sea is yours to cross. Ready?")
	ask.options = StoryCommand.list([
		ChoiceOption.make("Battle!", [_duel(_eloi_spec()), IfCommand.make("outcome() == \"victory\"", won)]),
		ChoiceOption.make("Not yet.", [], true),
	])
	var later: Array = _eloi_teach(true)
	later.append(SaveGameCommand.new())
	eloi.on_interact = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_ELOI_BEATEN, [ask], later),
	])
	return eloi


func _eloi_teach(again: bool) -> Array:
	return _teach_field_move("eloi", "ELOI", FIELD_MOVE_SEA_ID, F_TIDERIDE_LEARNED, {
		"first": "Which of yours will learn {move}?",
		"again": "Shall I teach {move} to another of yours?",
		"idle": "Face the water and call on {FIELD_MOVE_SEA}. Step onto any shore to come back to land.",
		"none": "None of yours can learn {FIELD_MOVE_SEA} yet. Come back with a creature that can.",
	}, again)


## CAEL'S SPAR (#60 / #88): a friendly rival DUEL -- never permadeath, a loss costs nothing.
func _cael_spec() -> BattleSpec:
	var team: Array = []
	for row in CAEL_TEAM:
		team.append((row as Dictionary).duplicate())
	var spec := _duel_spec(CAEL_DUEL_ID, "{CAEL}", &"npc_cael", team, true,
		BattleSpec.DefeatPolicy.CONTINUE, CAEL_PURSE)
	BattleSpec.make_chief(spec, REGION_BANDS["sunlit_coast"], CAEL_SCALE_OFFSET)
	spec.boss_battle = false
	spec.clash_intro = true
	return spec


## Cael on the promenade (#88): his greeting is in dialogue.json (areas.beach_village.cael); talk ->
## an optional friendly spar ("Not now" is fine; he blocks nothing). TODO(story): placeholder lines.
func _cael() -> NpcEntity:
	var cael := _npc("cael", BV_CAEL, "east", "CAEL", Color(0.42, 0.52, 0.66), "trainer")
	var bout: Array = [_duel(_cael_spec())]
	bout.append(IfCommand.make(FOUGHT, [
		_say([_line("cael", "CAEL", "Good bout. Let's do it again sometime.")]),  # TODO(story)
		_flag(F_CAEL_SPARRED),
		SaveGameCommand.new(),
	], [
		_say([_line("cael", "CAEL", "Your partner needs rest first. Find me after.")]),  # TODO(story)
	]))
	var offer := ChoiceCommand.new()
	offer.prompt = _line("cael", "CAEL", "Want a friendly bout, to see how far we've both come?")  # TODO(story)
	offer.options = StoryCommand.list([ChoiceOption.make("Let's go.", bout), ChoiceOption.make("Not now.", [], true)])
	cael.on_interact = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_CAEL_SPARRED, [offer]),
	])
	return cael


# =====================================================================================
#  THE SNOWY PEAKS -- Frostpeak Village (DECISIONS.md #45, #49, #50, #67, #69, #75, #80, #85, #95)
# =====================================================================================
#
#   Woodland Town's north trail
#     -> FROSTPEAK VILLAGE: a snowbound village under the peaks -- and EVERYONE IS ASLEEP (#95):
#        villagers dozing on their feet in the street, others in their beds (the inn, a house), the
#        chief SAEVI (#85) asleep by her lodge. Nobody wakes when spoken to.
#     -> THE INN: the hero must REST -- Confirm on an empty bed, "Rest?" -> the party is healed and the
#        hero falls into a DREAM (#49 / #95).
#     -> THE DREAM (frostpeak_dream): the same village in a violet half-light, empty but for SAEVI --
#        DISORIENTED, she thinks the hero did this -- and the two MYTHICAL creatures (one of nightmares,
#        one of dreams) playing and fighting by her lodge. Saevi first: a SCALED chief DUEL (#50 / #80).
#        Then, at the creatures: a TACTICAL battle against both (#49) -- Eliminate All Enemies, NO gem /
#        base to protect (#95). Win -> each may be bonded (#69 / #75, the legend list); then the hero
#        wakes in the inn, and the town is awake.
#     -> A creature the hero declined waits by the frozen pond (talk: the bond again). The dream's
#        south trail wakes the hero early (back in the inn bed), progress kept.
#
# All lines are short neutral PLACEHOLDERS (TODO(story)) -- the owner's facts only.

const F_FP_ARRIVED := "frostpeak.arrived"
## The hero rested in the inn and fell into the dream (the first time).
const F_FP_DREAMING := "frostpeak.dreaming"
const F_SAEVI_BEATEN := "frostpeak.saevi_beaten"
## The tactical battle against the two mythical creatures is won.
const F_DREAM_WON := "frostpeak.dream_won"
## The town is awake (the hero woke from the dream after the win).
const F_FP_AWAKE := "frostpeak.awake"
const SAEVI_DUEL_ID := "frostpeak.chief.saevi"
const DREAM_BATTLE_ID := "frostpeak.mythic.dream_pair"
## Frostpeak's people sleep until the town wakes.
const FP_ASLEEP := "not has(\"frostpeak.awake\")"

## SAEVI, the winter chief (#85): a DUEL (#50) SCALED inside the Snowy Peaks band (#80). PLACEHOLDER team
## (battle-ready stand-ins) -- her FINAL creature carries the stone placeholder (#38 / #67).
const SAEVI_SCALE_OFFSET := 1
const SAEVI_TEAM: Array[String] = ["monster", "mycothrall", "gem_knight"]
## TODO(bond): the stone boost placeholder.
const SAEVI_STONE_BOOST := 1.15
const SAEVI_PURSE := 650
## THE TWO MYTHICAL CREATURES (#49 / #69): one who causes NIGHTMARES, one who causes DREAMS. KNOBS:
## Eclupus (eclipse_wolf) is the owner's mythical (2026-10-12); the dreamer is still a PLACEHOLDER stand-in. Each is bonded
## like a legend (#39 / #75: the legend list, never the party) -- "both can be caught" (#69).
## [entity id, roster unit, its bonded flag]
const DREAM_PAIR := [
	["nightmare", "eclipse_wolf", "mythic.nightmare.bonded"],  # owner 2026-10-12: Fleecefang, the wolf in sheep's clothing (the only mythical made so far)
	["dreamer", "gem_knight", "mythic.dreamer.bonded"],  # PLACEHOLDER: the owner's DREAM SHEEP (brings good sleep; Lambush chases it) is not made yet
]
## Their TACTICAL board: Eliminate All Enemies, no base to protect (#95). Squad of up to this many.
const DREAM_MAP_PATH := CONTENT + "battles/ow_frostpeak_dream.tres"
const DREAM_SQUAD_SIZE := 4

const FP_W := 24
const FP_H := 20
## The trail south (to Woodland Town), the main street up to the chief's lodge, the cross street.
const FP_SOUTH_X := 11
const FP_CROSS_Y := 9
const FP_LANE_Y := 5
## The inn (enterable: the beds), Saevi's lodge, a house (enterable: sleepers in their beds), houses.
const FP_INN := Rect2i(4, 4, 4, 3)
const FP_LODGE := Rect2i(14, 2, 5, 3)
const FP_HOUSE := Rect2i(3, 12, 3, 2)
const FP_HOUSES := [Rect2i(17, 12, 3, 2), Rect2i(18, 6, 3, 2)]
const FP_SHRINE := Vector2i(8, 11)
const FP_POND := Rect2i(15, 14, 4, 3)
const FP_SAEVI := Vector2i(16, 5)
## In the dream: where the hero arrives (before the inn's door), where Saevi stands, the creatures.
const FD_START := Vector2i(5, 7)
const FD_SAEVI := Vector2i(12, 8)
const FD_PAIR_CELLS := [Vector2i(14, 6), Vector2i(17, 6)]
const FD_PAIR_FACING := ["east", "west"]
## A declined creature waits by the frozen pond in the waking village.
const FP_PAIR_CELLS := [Vector2i(14, 15), Vector2i(19, 15)]
## The inn's beds (1x2, against the north wall; the interior's floor is 10x7 -> x 1..10, y 1..7).
## [prop id, x, the sleeper lying in it ("" = an empty bed you can rest in)]
const FP_INN_BEDS := [["bed_a", 3, ""], ["bed_b", 5, "fp_traveller"], ["bed_c", 8, ""]]
const FP_INN_ID := "frostpeak_inn"
const FP_HOUSE_ID := "frostpeak_house"
## The house's beds and sleepers ([prop id, x, sleeper id, NAMES key, figure]).
const FP_HOUSE_BEDS := [["bed_a", 2, "fp_sleeper", "FROST_SLEEPER", "villager"], ["bed_b", 6, "fp_child_bed", "FROST_CHILD", "child"]]


func _fp_buildings() -> Array:
	return [FP_INN, FP_LODGE, FP_HOUSE] + FP_HOUSES


## Frostpeak's ground (the waking village and the dream share it; [param dream] scatters the dream's
## firefly-lit meadow patches over the snow).
func _fp_terrain(x: int, y: int, dream: bool) -> String:
	var c := Vector2i(x, y)
	if x == FP_SOUTH_X and (y == FP_H - 1 or y < FP_LANE_Y):
		return "frozen_tundra"
	if x == 0 or y == 0 or x == FP_W - 1 or y == FP_H - 1:
		return "frozen_pine"
	if _in(_fp_buildings(), c):
		return "stone_wall"
	if c == FP_SHRINE:
		return "sacred_ground"
	if FP_POND.has_point(c):
		return "ice_sheet"
	# The streets: up from the trail to the chief's lodge, across the village.
	if x == FP_SOUTH_X and y >= FP_LANE_Y:
		return "frozen_tundra"
	if y == FP_LANE_Y and x >= FP_SOUTH_X and x <= FP_SAEVI.x:
		return "frozen_tundra"
	if y == FP_CROSS_Y and x >= 3 and x <= FP_W - 4:
		return "frozen_tundra"
	# Pines crowd the edges (never in the village proper).
	if (x <= 1 or x >= FP_W - 2 or y <= 1) and _h(x, y, 83) < 0.5:
		return "frozen_pine"
	if dream and _h(x, y, 97) < 0.1:
		return "sacred_meadow"
	return "snow_field"


## [param dream]: false = the real village (frostpeak_village), true = the dream (frostpeak_dream).
func _build_frostpeak(dream: bool) -> void:
	var aid: String = "frostpeak_dream" if dream else "frostpeak_village"
	var t := _new_map("Frostpeak Village", FP_W, FP_H,
		("Frostpeak Village in a dream: the same streets in a violet half-light." if dream
			else "Frostpeak Village: a snowbound village under the Snowy Peaks, north of Woodland Town.") + " Story-mode terrain.")
	t.lighting_preset = "Dream" if dream else "Day"
	t.environment_preset = "Snow"
	_paint(t, func(x: int, y: int) -> String: return _fp_terrain(x, y, dream))
	_add_validator_anchors(t, Vector2i(FP_SOUTH_X, FP_H - 2), Vector2i(FP_SHRINE.x, FP_SHRINE.y + 1))
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)

	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	# The dream shares the village's name (the popup never says "dream").
	a.display_name = "Frostpeak Village"
	a.kind = OverworldAreaResource.Kind.TOWN
	_place(a, "frostpeak_village")
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	var ents: Array = []
	ents.append_array(_fp_scenery(dream))
	if dream:
		a.entry_points = {
			"dream_start": {"cell": [FD_START.x, FD_START.y, 0], "facing": "south"},
			"south_trail": {"cell": [FP_SOUTH_X, FP_H - 2, 0], "facing": "north"},
		}
		ents.append_array(_fd_people())
		# The trail out of the dream WAKES you (back in the inn's bed); what you did there is kept.
		for side in [["south_exit", FP_H - 1], ["north_exit", 0]]:
			var wake := _warp(String(side[0]), Rect2i(FP_SOUTH_X, int(side[1]), 1, 1), StringName(FP_INN_ID), &"bed")
			wake.arrival_toast = "You wake with a start."  # TODO(story)
			ents.append(wake)
		a.on_enter = StoryCommand.list([
			IfCommand.make("not has(\"%s\")" % F_FP_DREAMING, [_flag(F_FP_DREAMING)]),
		])
	else:
		a.entry_points = {
			"south_trail": {"cell": [FP_SOUTH_X, FP_H - 2, 0], "facing": "north"},
			"north_trail": {"cell": [FP_SOUTH_X, 1, 0], "facing": "south"},
			"wayshrine": {"cell": [FP_SHRINE.x, FP_SHRINE.y + 1, 0], "facing": "north"},
		}
		# The post-game's BLIZZARD over the Snowy Peaks (#99).
		a.weather_alt = "blizzard"
		a.weather_if = POSTGAME
		ents.append(_shrine(FP_SHRINE, "Frostpeak Wayshrine"))
		ents.append_array(_fp_people())
		ents.append(_warp("south_exit", Rect2i(FP_SOUTH_X, FP_H - 1, 1, 1), &"woodland_town", &"north_trail"))
		ents.append(_warp("north_exit", Rect2i(FP_SOUTH_X, 0, 1, 1), &"snowy_peaks", &"south_trail"))
		a.on_enter = StoryCommand.list([
			IfCommand.make("not has(\"%s\")" % F_FP_ARRIVED, [_flag(F_FP_ARRIVED)]),
		])
	_add_doors(a, ents)
	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/%s/area.tres" % aid)


func _fp_scenery(dream: bool) -> Array:
	var out: Array = []
	var timber := Color(0.36, 0.3, 0.34)
	var violet := Color(0.36, 0.26, 0.5)
	# PLACEHOLDER buildings (cabins / houses until the Blender models arrive); the inn and one house are
	# enterable in the waking village (INTERIORS).
	out.append(_prop("fp_inn", "house", FP_INN.position, FP_INN.size, Color(0.4, 0.34, 0.42)))
	out.append(_prop("saevi_lodge", "cabin", FP_LODGE.position, FP_LODGE.size, violet))
	out.append(_prop("fp_house", "cabin", FP_HOUSE.position, FP_HOUSE.size, timber))
	for i in range(FP_HOUSES.size()):
		var r: Rect2i = FP_HOUSES[i]
		out.append(_prop("fp_cabin_%d" % i, "cabin", r.position, r.size, [timber, Color(0.3, 0.32, 0.4)][i % 2]))
	out.append(_prop("banner_lodge", "banner", Vector2i(FP_LODGE.position.x - 1, FP_LODGE.end.y - 1), Vector2i.ONE, violet, true))
	out.append(_prop("woodpile", "logs", Vector2i(5, 17), Vector2i(2, 1), Color(0.5, 0.38, 0.26), true))
	for lc in [Vector2i(10, 12), Vector2i(12, 7)]:
		var lamp := _prop("lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(0.86, 0.8, 1.0) if dream else Color(1.0, 0.82, 0.45), true)
		lamp.glow = 2.0 if dream else 0.0
		out.append(lamp)
	if dream:
		# The dream's floating starstone-violet crystals (PLACEHOLDER look).
		for cc in [Vector2i(7, 14), Vector2i(19, 9), Vector2i(3, 7), Vector2i(14, 17)]:
			var cr := _prop("dream_crystal_%d_%d" % [cc.x, cc.y], "crystal", cc, Vector2i.ONE, Color(0.78, 0.6, 1.0), true)
			cr.glow = 3.0
			out.append(cr)
	return out


## The waking village's people: asleep until the town wakes (#95) -- dozing on their feet in the
## street; Saevi asleep by her lodge. Their lines (asleep / awake) are in dialogue.json.
func _fp_people() -> Array:
	var out: Array = []
	out.append(_sign("village_sign", Vector2i(FP_SOUTH_X + 1, FP_H - 3), "Frostpeak Village",
		"FROSTPEAK VILLAGE\nSouth: the trail down to Woodland Town."))
	var fur := Color(0.46, 0.42, 0.5)
	for row in [["fp_watch", Vector2i(12, 17), "south", "FROST_WATCH", "guard"],
			["fp_elder", Vector2i(9, 7), "east", "FROST_ELDER", "elder"],
			["fp_hunter", Vector2i(20, 10), "west", "FROST_HUNTER", "trainer"],
			["fp_woodcutter", Vector2i(6, 16), "north", "FROST_WOODCUTTER", "villager"],
			["fp_child", Vector2i(14, 12), "south", "FROST_CHILD", "child"]]:
		var n := _npc(String(row[0]), row[1], String(row[2]), String(row[3]), fur, String(row[4]))
		n.asleep_if = FP_ASLEEP
		out.append(n)
	var saevi := _npc("saevi", FP_SAEVI, "south", "SAEVI", Color(0.32, 0.24, 0.44), "elder")
	saevi.asleep_if = FP_ASLEEP
	out.append(saevi)
	# A mythical creature the hero did not bond with after the dream waits by the pond (#69 / #75).
	for i in range(DREAM_PAIR.size()):
		out.append(_dream_creature(DREAM_PAIR[i], FP_PAIR_CELLS[i], "south", false))
	return out


## The dream's people: SAEVI (disoriented: she thinks the hero did this) and the two creatures.
func _fd_people() -> Array:
	var out: Array = []
	out.append(_saevi_dream())
	for i in range(DREAM_PAIR.size()):
		out.append(_dream_creature(DREAM_PAIR[i], FD_PAIR_CELLS[i], String(FD_PAIR_FACING[i]), true))
	return out


## SAEVI'S CHIEF DUEL (#50 / #80): SCALED inside the Snowy Peaks band, a boss battle. A loss whites out
## (you wake at your Wayshrine; rest at the inn to dream again -- she waits).
func _saevi_spec() -> BattleSpec:
	var team: Array = []
	for i in range(SAEVI_TEAM.size()):
		var row: Dictionary = {"character_id": SAEVI_TEAM[i], "strength": 1.0}
		if i == SAEVI_TEAM.size() - 1:
			# TODO(bond): stone boost -- she uses the stone with her FINAL creature (#38 / #67).
			row["strength"] = SAEVI_STONE_BOOST
		team.append(row)
	var spec := _duel_spec(SAEVI_DUEL_ID, "{SAEVI}", &"npc_saevi", team, false, BattleSpec.DefeatPolicy.WHITEOUT,
		SAEVI_PURSE, [], [F_SAEVI_BEATEN])
	BattleSpec.make_chief(spec, REGION_BANDS["snowy_peaks"], SAEVI_SCALE_OFFSET)
	spec.clash_intro = true
	return spec


## Saevi in the dream (#49): DISORIENTED -- she believes the hero may have caused it -> the duel. Won:
## she sees it was the two creatures, tends your party (it is a dream) and points at them. After the
## tactical win (a journey that stopped mid-wake) she finishes the waking. TODO(story): placeholder lines.
func _saevi_dream() -> NpcEntity:
	var saevi := _npc("saevi", FD_SAEVI, "south", "SAEVI", Color(0.32, 0.24, 0.44), "elder")
	var won: Array = [
		_say([
			_line("saevi", "SAEVI", "...You're not the one. It's them -- the two who play in our sleep."),
			_line("saevi", "SAEVI", "Let me tend your partners. Then help me drive them out of our dreams."),
		]),
		HealPartyCommand.new(),
	]
	var ask := ChoiceCommand.new()
	ask.prompt = _line("saevi", "SAEVI", "Who are you? Did you do this -- put my people to sleep? Answer me!")
	ask.options = StoryCommand.list([
		ChoiceOption.make("Battle!", [_duel(_saevi_spec()), IfCommand.make("outcome() == \"victory\"", won)]),
		ChoiceOption.make("Not yet.", [], true),
	])
	saevi.on_interact = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_SAEVI_BEATEN, [ask], [
			IfCommand.make("has(\"%s\")" % F_DREAM_WON, _dream_wake(), [
				_say([_line("saevi", "SAEVI", "There -- by my lodge. Face them, and I'll be right behind you.")]),
			]),
		]),
	])
	return saevi


## THE TWO CREATURES' TACTICAL battle (#49 / #95): both on one board, Eliminate All Enemies, no base to
## protect; FIXED above the band like a legend (#81); Try Again on a loss.
func _dream_spec() -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.encounter_id = DREAM_BATTLE_ID
	spec.map_path = DREAM_MAP_PATH
	spec.squad_size = DREAM_SQUAD_SIZE
	spec.ai_difficulty = 1
	var names: Array[String] = []
	var team: Array[Dictionary] = []
	for row in DREAM_PAIR:
		names.append(_species_name(StringName(row[1])))
		team.append({"character_id": String(row[1]), "strength": 1.0})
	spec.opponent_name = " & ".join(names)
	spec.opponent_team = team
	BattleSpec.make_legend(spec, REGION_BANDS["snowy_peaks"])
	var flags: Array[String] = [F_DREAM_WON]
	spec.reward_flags = flags
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	return spec


## One of the two creatures ([param row] = DREAM_PAIR's). [param dream]: in the dream (before the win:
## lost in their game until Saevi is beaten, then the battle) or by the waking village's pond (after the
## win, until bonded: the bond again).
func _dream_creature(row: Array, cell: Vector2i, facing: String, dream: bool) -> NpcEntity:
	var e := NpcEntity.new()
	e.id = StringName(String(row[0]))
	e.cell = Vector3i(cell.x, cell.y, 0)
	e.facing = facing
	e.display_name = _species_name(StringName(row[1]))
	e.speaker_name = e.display_name
	e.visual_character = StringName(row[1])
	var bond := _bond_offer(String(row[1]), String(row[2]), "%s watches you, calm now. Bond with it?" % e.display_name)
	if not dream:
		e.visible_if = "has(\"%s\") and not has(\"%s\")" % [F_DREAM_WON, String(row[2])]
		e.on_interact = StoryCommand.list([bond])
		return e
	e.visible_if = "not has(\"%s\")" % F_DREAM_WON
	var fight := StartBattleCommand.new()
	fight.spec = _dream_spec()
	fight.source = BattleRequest.SOURCE_SCRIPT
	var face := ChoiceCommand.new()
	face.prompt = _narr("The two creatures turn on you at last -- the dream shudders. Face them?")
	face.options = StoryCommand.list([
		ChoiceOption.make("Face them", [fight, IfCommand.make("outcome() == \"victory\"", _dream_wake())]),
		ChoiceOption.make("Not yet", [], true),
	])
	e.on_interact = StoryCommand.list([
		IfCommand.make("has(\"%s\")" % F_SAEVI_BEATEN, [face], [
			_say([_narr("The two creatures circle each other, lost in their game. They do not notice you.")]),
		]),
	])
	return e


## After the creatures are beaten: the bond offers (#69 / #75), then the hero WAKES in the inn and the
## town wakes with him. TODO(story): placeholder lines.
func _dream_wake() -> Array:
	var out: Array = [
		_say([_line("saevi", "SAEVI", "They're still at last. My people will wake now -- and so will you.")]),
	]
	for row in DREAM_PAIR:
		var nm: String = _species_name(StringName(row[1]))
		out.append(IfCommand.make("not has(\"%s\")" % String(row[2]), [
			_bond_offer(String(row[1]), String(row[2]), "%s watches you, calm now. Bond with it?" % nm),
		]))
	out.append(_flag(F_FP_AWAKE))
	out.append(_say([_narr("The violet light thins, and the dream lets you go...")]))
	out.append(_warp_cmd(StringName(FP_INN_ID), &"bed"))
	return out


## The inn's people and beds: the innkeeper dozing on their feet behind the counter,
## a traveller asleep in one bed, and the EMPTY beds the hero rests in.
func _fp_inn_people(size: Vector2i) -> Array:
	var out: Array = []
	var keeper := _npc("fp_innkeeper", Vector2i(size.x - 1, 4), "south", "FROST_INNKEEPER", Color(0.5, 0.36, 0.3), "villager")
	keeper.asleep_if = FP_ASLEEP
	out.append(keeper)
	for b in FP_INN_BEDS:
		var bx: int = int(b[1])
		var bed := _prop(String(b[0]), "bed", Vector2i(bx, 1), Vector2i(1, 2), Color(0.42, 0.3, 0.52))
		if String(b[2]).is_empty():
			bed.verb = "Rest"
			bed.on_interact = StoryCommand.list(_fp_rest())
		else:
			var sleeper := _npc(String(b[2]), Vector2i(bx, 2), "south", "FROST_TRAVELLER", Color(0.44, 0.4, 0.3), "villager")
			sleeper.asleep_if = FP_ASLEEP
			sleeper.sleep_pose = "lie"
			# In bed until the town wakes; up and gone after.
			sleeper.visible_if = FP_ASLEEP
			out.append(sleeper)
		out.append(bed)
	return out


## RESTING in an inn bed (#95): while the town sleeps, the rest takes the hero into the DREAM (healed
## first); once it is awake, an ordinary rest. TODO(story): placeholder lines.
func _fp_rest() -> Array:
	var dream := ChoiceCommand.new()
	dream.prompt = _narr("Everyone in the inn is fast asleep. Lie down in the empty bed and rest?")
	dream.options = StoryCommand.list([
		ChoiceOption.make("Rest", [
			HealPartyCommand.new(),
			_say([_narr("You close your eyes... and the room tilts into a strange, violet light.")]),
			_warp_cmd(&"frostpeak_dream", &"dream_start"),
		]),
		ChoiceOption.make("Not now", [], true),
	])
	var rest := ChoiceCommand.new()
	rest.prompt = _narr("Rest a while?")
	rest.options = StoryCommand.list([
		ChoiceOption.make("Rest", [
			HealPartyCommand.new(),
			SaveGameCommand.new(),
			_say([_narr("You rest, and wake refreshed. Your party is ready to go.")]),
		]),
		ChoiceOption.make("Not now", [], true),
	])
	return [IfCommand.make(FP_ASLEEP, [dream], [rest])]


## The house: two of the village asleep in their beds (#95); up and gone once the town wakes.
func _fp_house_people() -> Array:
	var out: Array = []
	for b in FP_HOUSE_BEDS:
		var bx: int = int(b[1])
		out.append(_prop(String(b[0]), "bed", Vector2i(bx, 1), Vector2i(1, 2), Color(0.36, 0.42, 0.52)))
		var sleeper := _npc(String(b[2]), Vector2i(bx, 2), "south", String(b[3]), Color(0.44, 0.4, 0.46), String(b[4]))
		sleeper.asleep_if = FP_ASLEEP
		sleeper.sleep_pose = "lie"
		sleeper.visible_if = FP_ASLEEP
		out.append(sleeper)
	return out


## The two creatures' board: a dream-lit village square (Eliminate All Enemies, no base). Both are
## BOSS spawns at the legend level; your squad chairs to the south (the squad pick fills them).
func _build_dream_battle_map() -> void:
	var m := _new_map("Frostpeak, Dreaming", 12, 10,
		"Frostpeak's square in a dream, where the two mythical creatures play and fight.")
	m.lighting_preset = "Dream"
	m.environment_preset = "Snow"
	var pines := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(10, 0), Vector2i(11, 0), Vector2i(0, 9), Vector2i(11, 9),
		Vector2i(2, 5), Vector2i(9, 5)]
	var meadow := [Vector2i(3, 3), Vector2i(8, 3), Vector2i(5, 5), Vector2i(6, 5), Vector2i(1, 7), Vector2i(10, 7)]
	_paint(m, func(x: int, y: int) -> String:
		var c := Vector2i(x, y)
		if c in pines:
			return "frozen_pine"
		if c in meadow:
			return "sacred_meadow"
		if x == 6 and y >= 4:
			return "frozen_tundra"
		return "snow_field")
	m.unit_spawns.clear()
	for c in [Vector2i(4, 8), Vector2i(6, 8), Vector2i(8, 8), Vector2i(5, 9)]:
		m.set_character_spawn_at_position(c, 0, String(STARTER_ID))
	var boss_cells := [Vector2i(4, 2), Vector2i(7, 2)]
	for i in range(DREAM_PAIR.size()):
		m.set_character_spawn_at_position(boss_cells[i], 1, String(DREAM_PAIR[i][1]), "BOSS")
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, DREAM_MAP_PATH)


# =====================================================================================
#  THE ROCKY BADLANDS -- Redrock Village and the secret hideout (DECISIONS.md #46, #57, #73, #96)
# =====================================================================================
#
#   Crownhaven's east gate
#     -> THE ROCKY BADLANDS (route): the Redrock road through the red mesas; scrub with wild creatures,
#        a prospector who battles.
#     -> REDROCK VILLAGE: villagers TALK about strange people going out into the badlands and the desert
#        (#46 / #96, dialogue.json); one of them overheard a word (the password's middle).
#     -> THE RED DESERT (south of Redrock): a HOODED FIGURE. Get close and they hurry off -- FOLLOW them
#        (three stages, each a trigger near where they stopped); the first time they drop a crumpled
#        NOTE. At the last they slip into a cave in the cliffs.
#     -> THE CAVE: it LOOKS LIKE A DEAD END (#96). The rock at the end sounds hollow; SPEAK the PASSWORD
#        (three words, picked one at a time) and it rolls aside. THE CLUE: the note gives the first and
#        last words, the Redrock miner the middle one. A wrong answer: nothing happens (try again).
#     -> THE HIDEOUT: guards who battle in DUELS (#96 "many of the enemies in a battle style") -- three in
#        the first hall, two more in the depths, each watching the way through.
#     -> THE END OF THE HIDEOUT: General VARDEN, who has been tracking the place (#57), joins the hero
#        for the last fight: a TACTICAL battle against the hideout's commander and guards, the General a
#        GUEST on the hero's side (#96 "joined by an ally"). No base to protect.
#
# All lines are short neutral PLACEHOLDERS (TODO(story)); who runs the hideout is the owner's call.

const F_REDROCK_ARRIVED := "redrock.arrived"
## The hooded figure's flight: noticed you (1), ran again (2), slipped into the cave (entered).
const F_FIGURE_1 := "badlands.figure_fled_1"
const F_FIGURE_2 := "badlands.figure_fled_2"
const F_FIGURE_ENTERED := "badlands.figure_entered"
## The cave's rock rolled aside (the password was spoken) -- also the hideout's open flag (WORLD_LOCATIONS).
const F_HIDEOUT_OPEN := "badlands.hideout_open"
## The password picks so far (1-based word index per slot) -- set as the hero speaks.
const F_PW_SLOT := "badlands.password.%d"
## The General arrived at the end of the hideout; the last fight is won.
const F_VARDEN_ARRIVED := "badlands.varden_arrived"
const F_HIDEOUT_CLEARED := "badlands.hideout_cleared"
const HIDEOUT_BATTLE_ID := "badlands.hideout.final"
## The General is in the hideout from his arrival until the last fight is won (one General at a time).
const VARDEN_IN_HIDEOUT := "has(\"badlands.varden_arrived\") and not has(\"badlands.hideout_cleared\")"

## THE PASSWORD (#96: "a password you must find or figure out"): three words, spoken in order, each
## picked from four. KNOBS (TODO(story): placeholder words): the answer, and each slot's choices (the
## answer among them). The CLUE is split: the note names the first and last, a Redrock miner overheard
## the middle one.
const HIDEOUT_PASSWORD: Array[String] = ["Dust", "Ember", "Crown"]
const HIDEOUT_PW_CHOICES := [
	["Stone", "Dust", "Sun", "Ash"],
	["River", "Iron", "Ember", "Night"],
	["Wolf", "Gate", "Key", "Crown"],
]

## Battle levels (FIXED, inside the badlands band 22-30): the route's prospector, the hideout's guards
## (rising as you go in). The last fight SCALES inside the band like a chief's (#80 -- any order).
const LV_PROSPECTOR := 23
const LV_HIDEOUT_GUARDS: Array[int] = [23, 24, 24, 25, 26]
const HIDEOUT_SCALE_OFFSET := 1
## PLACEHOLDER teams (battle-ready roster stand-ins; #78: villains' creatures are easy to bond with).
const HIDEOUT_GUARD_TEAMS := [
	[{"character_id": "tree_grunt", "strength": 0.95}],
	[{"character_id": "blightcap", "strength": 0.95}, {"character_id": "mycothrall", "strength": 0.9}],
	[{"character_id": "monster", "strength": 0.95}],
	[{"character_id": "mycothrall", "strength": 0.95}, {"character_id": "gem_knight", "strength": 0.95}],
	[{"character_id": "monster", "strength": 1.0}, {"character_id": "blightcap", "strength": 0.95}],
]
## The last fight's board, the squad size, and its PLACEHOLDER enemy units in map-spawn order: the
## commander (the BOSS) first, then the guards and their creatures.
const HIDEOUT_MAP_PATH := CONTENT + "battles/ow_badlands_hideout.tres"
const HIDEOUT_SQUAD_SIZE := 3
const HIDEOUT_UNITS: Array[String] = ["necromancer", "monster", "petalfang", "blightcap"]
## The ally (#57: the General, or his second in command): a GUEST unit on the hero's side.
const HIDEOUT_ALLY_UNIT := GENERAL_UNIT
const HIDEOUT_PURSE := 800

const RB_W := 32
const RB_H := 14
const RB_ROAD_Y := 7
## The mesas along the road (impassable red rock) and the scrub where wild creatures roam.
const RB_MESAS := [Rect2i(4, 1, 3, 3), Rect2i(10, 9, 4, 3), Rect2i(17, 1, 3, 4), Rect2i(23, 9, 3, 3), Rect2i(27, 2, 2, 3)]
const RB_SCRUB := [Rect2i(5, 9, 3, 2), Rect2i(14, 2, 3, 2), Rect2i(24, 4, 3, 2)]
const RB_PROSPECTOR := Vector2i(21, 10)

const RV_W := 26
const RV_H := 20
const RV_WEST_Y := 9
const RV_SOUTH_X := 12
const RV_HOUSES := [Rect2i(3, 3, 3, 2), Rect2i(17, 4, 3, 2), Rect2i(4, 13, 3, 2), Rect2i(18, 13, 3, 2)]
const RV_HALL := Rect2i(9, 3, 4, 3)
const RV_SHRINE := Vector2i(14, 10)

const RD_W := 28
const RD_H := 18
const RD_NORTH_X := 12
## The cave mouth in the eastern cliffs, and where the hero stands coming back out of it.
const RD_CLIFF_X := 23
const RD_MOUTH := Vector2i(23, 9)
## The hooded figure's stops (A -> B -> C -> into the mouth), and the trigger zone around each.
const RD_FIGURE_STOPS := [Vector2i(8, 5), Vector2i(15, 12), Vector2i(20, 9)]
const RD_FIGURE_ZONES := [Rect2i(5, 2, 7, 7), Rect2i(12, 10, 7, 5), Rect2i(17, 7, 5, 5)]
const RD_MESAS := [Rect2i(3, 9, 3, 3), Rect2i(16, 3, 3, 3), Rect2i(9, 14, 3, 2), Rect2i(6, 2, 1, 1)]
const RD_SCRUB := [Rect2i(2, 13, 4, 3), Rect2i(18, 13, 3, 3), Rect2i(20, 2, 2, 3)]

## The cave: a winding passage to a dead end (the sealed rock), and a side pocket with a chest.
const BC_W := 14
const BC_H := 16
const BC_PATH := [Rect2i(6, 10, 2, 6), Rect2i(6, 10, 6, 2), Rect2i(10, 4, 2, 8), Rect2i(6, 4, 6, 2), Rect2i(6, 2, 2, 3),
	Rect2i(5, 12, 1, 1), Rect2i(2, 11, 3, 3)]
const BC_ROCK := Vector2i(7, 1)
const BC_POCKET_CHEST := Vector2i(2, 12)

## The hideout: two halls (stone floors, timber props), guards watching the way through.
const HO_W := 16
const HO_H := 14
const HO_X := 7
## [id, cell, facing] of each hall's guards (they watch ACROSS the corridor: the way through is theirs).
const HO_GUARDS := [
	["guard_1", Vector2i(5, 10), "east"], ["guard_2", Vector2i(10, 7), "west"], ["guard_3", Vector2i(5, 3), "east"],
]
const HD_GUARDS := [
	["guard_4", Vector2i(10, 9), "west"], ["guard_5", Vector2i(5, 6), "east"],
]
## The depths: the commander's chamber at the north end; the trigger in front of it; where the General
## steps in.
const HD_COMMANDER := Vector2i(7, 2)
const HD_TRIGGER := Rect2i(6, 4, 3, 1)
const HD_VARDEN := Vector2i(8, 5)


# --- The Rocky Badlands (route) -------------------------------------------------------

func _rb_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if (x == 0 or x == RB_W - 1) and y == RB_ROAD_Y:
		return "sand"
	if x == 0 or y == 0 or x == RB_W - 1 or y == RB_H - 1:
		return "mesa_rock"
	if _in(RB_MESAS, c):
		return "mesa_rock"
	if _in(RB_SCRUB, c):
		return "tall_grass"
	if y == RB_ROAD_Y:
		return "sand"
	return "red_clay"


func _build_rocky_badlands() -> void:
	var t := _new_map("Rocky Badlands", RB_W, RB_H,
		"The Rocky Badlands: the Redrock road through the red mesas, east of Crownhaven. Story-mode terrain.")
	t.lighting_preset = "Day"
	t.environment_preset = "Desert"
	_paint(t, _rb_terrain)
	_add_validator_anchors(t, Vector2i(1, RB_ROAD_Y), Vector2i(RB_W - 2, RB_ROAD_Y))
	_save(t, CONTENT + "areas/rocky_badlands/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"rocky_badlands"
	a.display_name = "Rocky Badlands"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "rocky_badlands")
	a.terrain = load(CONTENT + "areas/rocky_badlands/terrain.tres")
	a.entry_points = {
		"west_road": {"cell": [1, RB_ROAD_Y, 0], "facing": "east"},
		"east_road": {"cell": [RB_W - 2, RB_ROAD_Y, 0], "facing": "west"},
	}
	var ents: Array = []
	for i in range(RB_MESAS.size()):
		var r: Rect2i = RB_MESAS[i]
		if r.size.x * r.size.y >= 9:
			ents.append(_prop("rock_%d" % i, "boulder", Vector2i(r.position.x + r.size.x / 2, r.end.y), Vector2i.ONE,
				Color(0.58, 0.3, 0.2), true))
	ents.append(_sign("road_sign", Vector2i(2, RB_ROAD_Y - 1), "The Redrock Road",
		"EAST: REDROCK VILLAGE\nWEST: CROWNHAVEN"))
	ents.append(_duel_trainer("badlands", "prospector", RB_PROSPECTOR, "north", "BADLANDS_PROSPECTOR", Color(0.6, 0.44, 0.28),
		"villager", [{"character_id": "gem_knight", "strength": 0.95}, {"character_id": "monster", "strength": 0.9}],
		LV_PROSPECTOR, 260, "These mesas are mine to dig! Want to fight me for them?", "Fine, fine. Dig somewhere else."))
	ents.append(_warp("west_exit", Rect2i(0, RB_ROAD_Y, 1, 1), &"crownhaven", &"east_gate"))
	ents.append(_warp("east_exit", Rect2i(RB_W - 1, RB_ROAD_Y, 1, 1), &"redrock_village", &"west_road"))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	var zones: Array[Resource] = [_wild_zone(["tall_grass"], [["gem_knight", 2.0], ["monster", 1.5]])]
	a.encounter_zones = zones
	_save(a, CONTENT + "areas/rocky_badlands/area.tres")


# --- Redrock Village --------------------------------------------------------------------

func _rv_buildings() -> Array:
	return RV_HOUSES + [RV_HALL]


func _rv_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if x == 0 and y == RV_WEST_Y:
		return "sand"
	if x == RV_SOUTH_X and y == RV_H - 1:
		return "sand"
	if x == 0 or y == 0 or x == RV_W - 1 or y == RV_H - 1:
		return "mesa_rock"
	if _in(_rv_buildings(), c):
		return "stone_wall"
	if c == RV_SHRINE:
		return "sacred_ground"
	if y == RV_WEST_Y or x == RV_SOUTH_X and y >= RV_WEST_Y:
		return "sand"
	if (x <= 1 or x >= RV_W - 2) and _h(x, y, 113) < 0.45:
		return "mesa_rock"
	return "red_clay"


func _build_redrock_village() -> void:
	var t := _new_map("Redrock Village", RV_W, RV_H,
		"Redrock Village: a village among the red mesas of the Rocky Badlands. Story-mode terrain.")
	t.lighting_preset = "Day"
	t.environment_preset = "Desert"
	_paint(t, _rv_terrain)
	_add_validator_anchors(t, Vector2i(1, RV_WEST_Y), Vector2i(RV_SHRINE.x, RV_SHRINE.y + 1))
	_save(t, CONTENT + "areas/redrock_village/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"redrock_village"
	a.display_name = "Redrock Village"
	a.kind = OverworldAreaResource.Kind.TOWN
	_place(a, "redrock_village")
	a.terrain = load(CONTENT + "areas/redrock_village/terrain.tres")
	a.entry_points = {
		"west_road": {"cell": [1, RV_WEST_Y, 0], "facing": "east"},
		"south_trail": {"cell": [RV_SOUTH_X, RV_H - 2, 0], "facing": "north"},
		"wayshrine": {"cell": [RV_SHRINE.x, RV_SHRINE.y + 1, 0], "facing": "north"},
	}
	var ents: Array = []
	var adobe := Color(0.74, 0.46, 0.32)
	for i in range(RV_HOUSES.size()):
		var r: Rect2i = RV_HOUSES[i]
		ents.append(_prop("house_%d" % i, "house", r.position, r.size, [adobe, adobe.darkened(0.12)][i % 2]))
	ents.append(_prop("elder_hall", "house", RV_HALL.position, RV_HALL.size, Color(0.62, 0.32, 0.22)))
	ents.append(_prop("market_tent", "tent", Vector2i(18, 9), Vector2i(2, 1), Color(0.82, 0.62, 0.36)))
	ents.append(_prop("well", "well", Vector2i(9, 11), Vector2i.ONE, Color(0.58, 0.36, 0.24)))
	ents.append(_prop("cart", "cart", Vector2i(21, 8), Vector2i.ONE, Color(0.82, 0.62, 0.36)))
	ents.append(_shrine(RV_SHRINE, "Redrock Wayshrine"))
	ents.append(_sign("village_sign", Vector2i(2, RV_WEST_Y - 1), "Redrock Village",
		"REDROCK VILLAGE\nWest: the Redrock road to Crownhaven.  South: the Red Desert."))
	# The villagers (dialogue.json): the RUMOURS of strange people going out into the badlands and the
	# desert (#96); the miner overheard the password's middle word.
	var dust := Color(0.66, 0.46, 0.32)
	ents.append(_npc("rv_elder", Vector2i(11, 7), "south", "REDROCK_ELDER", dust.lightened(0.1), "elder"))
	ents.append(_npc("rv_miner", Vector2i(7, 11), "east", "REDROCK_MINER", Color(0.48, 0.4, 0.34), "villager"))
	ents.append(_npc("rv_trader", Vector2i(18, 10), "west", "REDROCK_TRADER", Color(0.6, 0.5, 0.3), "villager"))
	ents.append(_npc("rv_watch", Vector2i(RV_SOUTH_X + 1, RV_H - 3), "west", "REDROCK_WATCH", dust.darkened(0.15), "guard"))
	ents.append(_npc("rv_child", Vector2i(16, 15), "north", "REDROCK_CHILD", Color(0.8, 0.56, 0.4), "child"))
	ents.append(_warp("west_exit", Rect2i(0, RV_WEST_Y, 1, 1), &"rocky_badlands", &"east_road"))
	ents.append(_warp("south_exit", Rect2i(RV_SOUTH_X, RV_H - 1, 1, 1), &"red_desert", &"north_trail"))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	a.on_enter = StoryCommand.list([
		IfCommand.make("not has(\"%s\")" % F_REDROCK_ARRIVED, [_flag(F_REDROCK_ARRIVED)]),
	])
	_save(a, CONTENT + "areas/redrock_village/area.tres")


# --- The Red Desert: the hooded figure and the cave mouth --------------------------------

func _rd_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if x == RD_NORTH_X and y == 0:
		return "sand"
	if c == RD_MOUTH:
		return "red_clay"
	if x >= RD_CLIFF_X or x == 0 or y == 0 or y == RD_H - 1:
		return "mesa_rock"
	if _in(RD_MESAS, c):
		return "mesa_rock"
	if _in(RD_SCRUB, c):
		return "tall_grass"
	return "red_clay" if _h(x, y, 127) < 0.3 else "sand"


func _build_red_desert() -> void:
	var t := _new_map("The Red Desert", RD_W, RD_H,
		"The Red Desert: sand and red rock south of Redrock Village, under the eastern cliffs. Story-mode terrain.")
	t.lighting_preset = "Day"
	t.environment_preset = "Desert"
	_paint(t, _rd_terrain)
	_add_validator_anchors(t, Vector2i(RD_NORTH_X, 1), Vector2i(RD_MOUTH.x - 1, RD_MOUTH.y))
	_save(t, CONTENT + "areas/red_desert/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"red_desert"
	a.display_name = "The Red Desert"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "red_desert")
	a.terrain = load(CONTENT + "areas/red_desert/terrain.tres")
	a.entry_points = {
		"north_trail": {"cell": [RD_NORTH_X, 1, 0], "facing": "south"},
		"cave_mouth": {"cell": [RD_MOUTH.x - 1, RD_MOUTH.y, 0], "facing": "west"},
	}
	var ents: Array = []
	ents.append(_prop("cave_arch", "boulder", Vector2i(RD_MOUTH.x, RD_MOUTH.y - 1), Vector2i.ONE, Color(0.5, 0.26, 0.18), true))
	ents.append_array(_hooded_figure())
	ents.append(_warp("north_exit", Rect2i(RD_NORTH_X, 0, 1, 1), &"redrock_village", &"south_trail"))
	ents.append(_warp("cave_exit", Rect2i(RD_MOUTH.x, RD_MOUTH.y, 1, 1), &"badlands_cave", &"mouth"))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	var zones: Array[Resource] = [_wild_zone(["tall_grass"], [["monster", 2.0], ["gem_knight", 1.5], ["blightcap", 1.0]])]
	a.encounter_zones = zones
	_save(a, CONTENT + "areas/red_desert/area.tres")


## THE HOODED FIGURE (#96: "follow a person into the cave"): standing at the first stop until the hero
## comes near, then hurrying on -- three stages (a once-trigger round each stop), the last into the cave
## mouth, where they vanish for good. The first time they bolt they drop a crumpled NOTE (the clue).
## Their positions persist (a reload finds them where they stopped). TODO(story): placeholder lines.
func _hooded_figure() -> Array:
	var out: Array = []
	var fig := _npc("hooded_figure", RD_FIGURE_STOPS[0], "south", "HOODED_FIGURE", Color(0.18, 0.14, 0.16), "raider")
	fig.visible_if = "not has(\"%s\")" % F_FIGURE_ENTERED
	out.append(fig)
	var note := _sign("crumpled_note", RD_FIGURE_STOPS[0] + Vector2i(0, 1), "Crumpled Note",
		"A note, torn and dusty: \"...at the end of the cave, speak the words. First %s ... and last of all, %s.\" The middle of it is torn away." % [
			HIDEOUT_PASSWORD[0].to_upper(), HIDEOUT_PASSWORD[2].to_upper()], "note")
	note.visible_if = "has(\"%s\")" % F_FIGURE_1
	out.append(note)
	var flags: Array[String] = [F_FIGURE_1, F_FIGURE_2, F_FIGURE_ENTERED]
	for i in range(RD_FIGURE_STOPS.size()):
		var to: Vector2i = RD_FIGURE_STOPS[i + 1] if i + 1 < RD_FIGURE_STOPS.size() else RD_MOUTH
		var zone := TriggerZone.new()
		zone.id = StringName("figure_flees_%d" % (i + 1))
		zone.area_rect = RD_FIGURE_ZONES[i]
		zone.once = false
		zone.visible_if = ("not has(\"%s\")" % flags[i]) if i == 0 \
			else "has(\"%s\") and not has(\"%s\")" % [flags[i - 1], flags[i]]
		# The walk first, then the stage flag (a flag refreshes the world at once: the last one hides them).
		var steps: Array = [
			_emote("hooded_figure", "!"),
			_move("hooded_figure", to, true),
			_flag(flags[i]),
		]
		if i == 0:
			steps.append(_say([_narr("The hooded figure glances back at you -- and hurries off into the desert. Something flutters to the sand where they stood.")]))
		elif i == RD_FIGURE_STOPS.size() - 1:
			steps.append(_say([_narr("The figure slips into a cave in the cliffs.")]))
		zone.on_step = StoryCommand.list(steps)
		out.append(zone)
	return out


# --- The cave: the dead end and the password -----------------------------------------------

func _bc_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if x == BC_PATH[0].position.x and y == BC_H - 1:
		return "red_clay"
	# The sealed rock's cell (the way into the hideout once it has rolled aside).
	if c == BC_ROCK:
		return "red_clay"
	if _in(BC_PATH, c):
		return "red_clay"
	return "mesa_rock"


func _build_badlands_cave() -> void:
	var entry_x: int = (BC_PATH[0] as Rect2i).position.x
	var t := _new_map("Desert Cave", BC_W, BC_H,
		"A cave in the Red Desert's cliffs that seems to end in solid rock. Story-mode terrain.")
	t.lighting_preset = "Dusk"
	t.environment_preset = "Desert"
	_paint(t, _bc_terrain)
	_add_validator_anchors(t, Vector2i(entry_x, BC_H - 2), Vector2i(BC_ROCK.x, BC_ROCK.y + 1))
	_save(t, CONTENT + "areas/badlands_cave/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"badlands_cave"
	a.display_name = "Desert Cave"
	a.kind = OverworldAreaResource.Kind.DUNGEON
	_place(a, "red_desert")
	a.terrain = load(CONTENT + "areas/badlands_cave/terrain.tres")
	a.entry_points = {
		"mouth": {"cell": [entry_x, BC_H - 2, 0], "facing": "north"},
		"hideout": {"cell": [BC_ROCK.x, BC_ROCK.y + 1, 0], "facing": "south"},
	}
	var ents: Array = []
	ents.append(_sealed_rock())
	ents.append(_chest("pocket_chest", BC_POCKET_CHEST, "east", [&"mossleaf_tonic", &"bitterroot_salve"], 90))
	ents.append(_warp("mouth_exit", Rect2i(entry_x, BC_H - 1, 1, 1), &"red_desert", &"cave_mouth"))
	# Where the rock stood (there only once it has rolled aside): the way into the hideout.
	ents.append(_warp("hideout_door", Rect2i(BC_ROCK.x, BC_ROCK.y, 1, 1), &"badlands_hideout", &"south",
		"has(\"%s\")" % F_HIDEOUT_OPEN))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/badlands_cave/area.tres")


## THE DEAD END (#96): a boulder that sounds hollow. Speak the PASSWORD -- three words, one pick per
## slot from four -- and it rolls aside for good (F_HIDEOUT_OPEN hides it; the warp behind it opens).
## A wrong answer: nothing happens; try again. TODO(story): placeholder lines.
func _sealed_rock() -> PropEntity:
	var rock := _prop("sealed_rock", "boulder", BC_ROCK, Vector2i.ONE, Color(0.52, 0.28, 0.2), true,
		"not has(\"%s\")" % F_HIDEOUT_OPEN)
	rock.verb = "Check"
	var picks: Array = []
	var ordinals := ["first", "next", "last"]
	for slot in range(HIDEOUT_PW_CHOICES.size()):
		var words: Array = HIDEOUT_PW_CHOICES[slot]
		var pick := ChoiceCommand.new()
		pick.prompt = _narr("You speak the %s word..." % ordinals[mini(slot, ordinals.size() - 1)])
		var opts: Array = []
		for w in range(words.size()):
			opts.append(ChoiceOption.make(String(words[w]), [_flag(F_PW_SLOT % (slot + 1), w + 1)]))
		pick.options = StoryCommand.list(opts)
		picks.append(pick)
	var right: Array[String] = []
	for slot in range(HIDEOUT_PASSWORD.size()):
		var at: int = (HIDEOUT_PW_CHOICES[slot] as Array).find(HIDEOUT_PASSWORD[slot])
		if at < 0:
			push_error("[build_story_content] password word '%s' is not among slot %d's choices" % [HIDEOUT_PASSWORD[slot], slot + 1])
			_ok = false
		right.append("flag(\"%s\") == %d" % [F_PW_SLOT % (slot + 1), at + 1])
	picks.append(IfCommand.make(" and ".join(right), [
		_say([_narr("A low grinding answers you. The rock shudders -- and rolls aside, onto a passage lit by lamps.")]),
		_flag(F_HIDEOUT_OPEN),
		SaveGameCommand.new(),
	], [
		_say([_narr("Your voice echoes off the stone. Nothing happens.")]),
	]))
	var speak := ChoiceCommand.new()
	speak.prompt = _narr("A dead end. But this rock is scratched with marks, and it sounds hollow when you knock on it. Say something?")
	speak.options = StoryCommand.list([
		ChoiceOption.make("Speak", picks),
		ChoiceOption.make("Leave it", [], true),
	])
	rock.on_interact = StoryCommand.list([speak])
	return rock


# --- The hideout ----------------------------------------------------------------------------

## A hideout hall: rock walls (it is dug into the cliffs) round a broad corridor up the middle with side bays (crates, tents).
func _ho_terrain(x: int, y: int) -> String:
	if x == HO_X and (y == 0 or y == HO_H - 1):
		return "flagstones"
	if x == 0 or y == 0 or x == HO_W - 1 or y == HO_H - 1:
		return "mesa_rock"
	# Rough inner walls dividing the bays from the corridor, open in places.
	if (x == 3 or x == 12) and y % 4 == 1:
		return "mesa_rock"
	return "flagstones" if absi(x - HO_X) <= 1 else "wooden_planks"


func _hideout_area(aid: String, nm: String, entries: Dictionary) -> OverworldAreaResource:
	var t := _new_map(nm, HO_W, HO_H, "%s: the secret hideout behind the desert cave. Story-mode terrain." % nm)
	t.lighting_preset = "Dusk"
	_paint(t, _ho_terrain)
	_add_validator_anchors(t, Vector2i(HO_X, HO_H - 2), Vector2i(HO_X, 1))
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)
	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	a.display_name = nm
	a.kind = OverworldAreaResource.Kind.DUNGEON
	_place(a, "secret_hideout")
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	a.entry_points = entries
	return a


func _ho_props(prefix: String) -> Array:
	var out: Array = []
	var canvas := Color(0.42, 0.36, 0.3)
	out.append(_prop("%s_tent_w" % prefix, "tent", Vector2i(1, 6), Vector2i(2, 1), canvas))
	out.append(_prop("%s_tent_e" % prefix, "tent", Vector2i(13, 3), Vector2i(2, 1), canvas.darkened(0.1)))
	for bc in [Vector2i(1, 2), Vector2i(14, 11), Vector2i(1, 12), Vector2i(14, 7)]:
		out.append(_prop("%s_crates_%d_%d" % [prefix, bc.x, bc.y], "barrels", bc, Vector2i.ONE, Color.WHITE, true))
	for lc in [Vector2i(5, 1), Vector2i(9, 12)]:
		var lamp := _prop("%s_lamp_%d_%d" % [prefix, lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(1.0, 0.7, 0.36), true)
		lamp.glow = 2.5
		out.append(lamp)
	return out


func _hideout_guard(id: String, cell: Vector2i, facing: String, k: int) -> TrainerEntity:
	# TODO(story): placeholder lines; generic guards (no named cast).
	var pre: Array[String] = ["Nobody gets through here!", "How did you find this place?!", "Intruder! Stop right there!",
		"You won't reach the commander!", "This is as far as you go!"]
	var after: Array[String] = ["Ugh... the commander won't be happy.", "How...?", "Fine. Go on, then -- see where it gets you.",
		"You're tougher than you look.", "Go on. The commander's waiting."]
	return _duel_trainer("hideout", id, cell, facing, "HIDEOUT_GUARD", CINDRAL_RED.darkened(0.2), "raider",
		HIDEOUT_GUARD_TEAMS[k], LV_HIDEOUT_GUARDS[k], 200 + 20 * k, pre[k], after[k], 4)


func _build_hideout() -> void:
	var a := _hideout_area("badlands_hideout", "Secret Hideout", {
		"south": {"cell": [HO_X, HO_H - 2, 0], "facing": "north"},
		"north": {"cell": [HO_X, 1, 0], "facing": "south"},
	})
	var ents: Array = []
	ents.append_array(_ho_props("ho"))
	for i in range(HO_GUARDS.size()):
		var g: Array = HO_GUARDS[i]
		ents.append(_hideout_guard(String(g[0]), g[1], String(g[2]), i))
	ents.append(_warp("south_exit", Rect2i(HO_X, HO_H - 1, 1, 1), &"badlands_cave", &"hideout"))
	ents.append(_warp("north_exit", Rect2i(HO_X, 0, 1, 1), &"badlands_hideout_depths", &"south"))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/badlands_hideout/area.tres")


func _build_hideout_depths() -> void:
	var a := _hideout_area("badlands_hideout_depths", "Hideout Depths", {
		"south": {"cell": [HO_X, HO_H - 2, 0], "facing": "north"},
	})
	var ents: Array = []
	ents.append_array(_ho_props("hd"))
	for i in range(HD_GUARDS.size()):
		var g: Array = HD_GUARDS[i]
		ents.append(_hideout_guard(String(g[0]), g[1], String(g[2]), HO_GUARDS.size() + i))
	ents.append_array(_hideout_finale())
	ents.append(_warp("south_exit", Rect2i(HO_X, HO_H - 1, 1, 1), &"badlands_hideout", &"north"))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/badlands_hideout_depths/area.tres")


## THE LAST FIGHT (#96 / #57): a TACTICAL battle against the commander and the guards, General Varden a
## GUEST on the hero's side (a player-0 turn-1 Reinforcement on the board: placed at load, never replaced
## by the squad pick). SCALED inside the badlands band like a chief's (#80); Try Again on a loss.
func _hideout_spec() -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.encounter_id = HIDEOUT_BATTLE_ID
	spec.map_path = HIDEOUT_MAP_PATH
	spec.squad_size = HIDEOUT_SQUAD_SIZE
	spec.hero_deploy = BattleSpec.HeroDeploy.REQUIRED
	spec.ai_difficulty = 1
	spec.opponent_name = _t("{HIDEOUT_COMMANDER}")
	spec.opponent_speaker_id = &"npc_commander"
	var team: Array[Dictionary] = []
	for cid in HIDEOUT_UNITS:
		team.append({"character_id": cid, "strength": 1.0})
	spec.opponent_team = team
	BattleSpec.make_chief(spec, REGION_BANDS["rocky_badlands"], HIDEOUT_SCALE_OFFSET)
	spec.reward_gold = HIDEOUT_PURSE
	var flags: Array[String] = [F_HIDEOUT_CLEARED]
	spec.reward_flags = flags
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	return spec


## The commander's chamber: the commander (until the hideout is cleared) and the trigger in front of it --
## the General steps in behind the hero (#57), a few words, and the last fight. After a loss he waits
## there; talking to him (or the commander) offers the fight again. TODO(story): placeholder lines.
func _hideout_finale() -> Array:
	var out: Array = []
	var commander := _npc("commander", HD_COMMANDER, "south", "HIDEOUT_COMMANDER", CINDRAL_RED, "raider")
	commander.visible_if = "not has(\"%s\")" % F_HIDEOUT_CLEARED
	var fight := StartBattleCommand.new()
	fight.spec = _hideout_spec()
	fight.source = BattleRequest.SOURCE_SCRIPT
	var after: Array = [
		_say([
			_line("general", "GENERAL", "That's the last of them. Good work, {hero}."),
			_line("general", "GENERAL", "I'll have my soldiers go through this place. Get some rest."),
		]),
		SaveGameCommand.new(),
	]
	var offer := ChoiceCommand.new()
	offer.prompt = _line("general", "GENERAL", "Ready, {hero}? We take them together.")
	offer.options = StoryCommand.list([
		ChoiceOption.make("Fight!", [fight, IfCommand.make("outcome() == \"victory\"", after)]),
		ChoiceOption.make("Not yet.", [], true),
	])
	commander.on_interact = StoryCommand.list([IfCommand.make("has(\"%s\")" % F_VARDEN_ARRIVED, [offer])])
	out.append(commander)
	# The General: here from his arrival until the fight is won (one General at a time).
	var general := _npc("general", HD_VARDEN, "north", "GENERAL", ALDERMERE_BLUE, "officer")
	general.visual_character = VARDEN_MODEL
	general.visible_if = VARDEN_IN_HIDEOUT
	general.on_interact = StoryCommand.list([offer])
	out.append(general)
	var zone := TriggerZone.new()
	zone.id = &"commander_chamber"
	zone.area_rect = HD_TRIGGER
	zone.once = true
	zone.visible_if = "not has(\"%s\")" % F_VARDEN_ARRIVED
	zone.on_step = StoryCommand.list([
		_face("player", "north"),
		_say([_line("commander", "HIDEOUT_COMMANDER", "So you found the way in. You won't find the way out.")]),
		_flag(F_VARDEN_ARRIVED),
		_emote("player", "!"),
		_say([
			_line("general", "GENERAL", "Not alone, they won't. I've been tracking this place for weeks, {hero}."),
		]),
		_face("player", "toward:general"),
		offer,
	])
	out.append(zone)
	return out


## The last fight's board: a torch-lit hideout hall. South: your squad chairs and General Varden (a
## GUEST, player-0 turn-1 Reinforcement); north: the commander (BOSS) and the guards. Eliminate All
## Enemies -- no base to protect.
func _build_hideout_battle_map() -> void:
	var m := _new_map("Hideout Hall", 12, 9,
		"The commander's hall at the end of the secret hideout in the Red Desert.")
	m.lighting_preset = "Dusk"
	m.environment_preset = "Desert"
	var walls := [Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 8), Vector2i(11, 8), Vector2i(3, 4), Vector2i(8, 4)]
	var crates := [Vector2i(1, 2), Vector2i(10, 2), Vector2i(2, 6), Vector2i(9, 6)]
	_paint(m, func(x: int, y: int) -> String:
		var c := Vector2i(x, y)
		if c in walls:
			return "stone_wall"
		if c in crates:
			return "mesa_rock"
		if x >= 5 and x <= 6:
			return "flagstones"
		return "wooden_planks")
	m.unit_spawns.clear()
	for c in [Vector2i(4, 7), Vector2i(6, 7), Vector2i(5, 8)]:
		m.set_character_spawn_at_position(c, 0, String(STARTER_ID))
	m.set_spawn_point_at_position(Vector2i(7, 8), 0, MapResource.SPAWN_KIND_REINFORCEMENT,
		{"character_id": HIDEOUT_ALLY_UNIT, "spawn_turn": 1, "max_spawns": 1})
	var foes := [Vector2i(6, 1), Vector2i(4, 2), Vector2i(8, 2), Vector2i(6, 3)]
	for i in range(foes.size()):
		var unit: String = HIDEOUT_UNITS[i % HIDEOUT_UNITS.size()]
		if i == 0:
			m.set_character_spawn_at_position(foes[i], 1, unit, "BOSS")
		else:
			m.set_character_spawn_at_position(foes[i], 1, unit)
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, HIDEOUT_MAP_PATH)


# =====================================================================================
#  THE POST-GAME (DECISIONS.md #98-#100)
# =====================================================================================
#
# The post-game begins when the HIDDEN DEPTHS BOSS AWAKENS (#98). Then:
#   * near STORMREEF ISLE a volcano ERUPTS: a NEW ISLAND rises from the sea south of Beach Village, and a
#     new LEGEND waits on its crater (#98) -- reached riding the sea move;
#   * the SNOWY PEAKS are covered in a BLIZZARD (Frostpeak and the high trail north of it), and the storm
#     has torn away the ice that sealed a cave on the trail: a new LEGEND waits inside (#99);
#   * separately, after the FINAL BOSS is defeated, a tombstone in the GRAVEYARD on Crownhaven's outskirts
#     is found pushed aside and the tomb OPEN: it leads down to a new place, with a BOSS at its end (#100).
# Both triggers are story beats NOT BUILT YET: their flags are knobs here (the Hidden Depths and the final
# battle set them when they exist). Every line is a short neutral PLACEHOLDER (TODO(story)).

## The post-game's start: the Hidden Depths boss has awakened (TODO: set by the Hidden Depths, not built).
const F_POSTGAME := "postgame.hidden_depths_awakened"
## The final boss is defeated (TODO: set by the final battle, not built).
const F_FINAL_BOSS := "story.final_boss_beaten"
const POSTGAME := "has(\"postgame.hidden_depths_awakened\")"
const AFTER_FINAL_BOSS := "has(\"story.final_boss_beaten\")"
## The post-game's LEVEL BAND (KNOB): the new places' wild creatures, the legends (FIXED above it, #81)
## and the crypt's boss.
const POSTGAME_BAND := Vector2i(30, 40)

## The two new legends and the crypt's boss: PLACEHOLDER battle-ready roster units until they are designed
## (each legend a distinct unit -- a legend bond is one of each).
const VOLCANO_LEGEND_UNIT := "vineweave"  # PLACEHOLDER legend stand-in (battle-ready, distinct from every other legend / mythical)
const GLACIER_LEGEND_UNIT := "petalfang"  # PLACEHOLDER legend stand-in (battle-ready, distinct from every other legend / mythical)
const CRYPT_BOSS_UNIT := "necromancer"
const CRYPT_MINION_UNITS: Array[String] = ["monster", "petalfang", "blightcap"]
const LV_LEGEND_SCREEN := 38
const LV_CRYPT_BOSS := 42
const LV_CRYPT_MINIONS := 38
const F_VOLCANO_BEATEN := "postgame.volcano_legend_beaten"
const F_VOLCANO_BONDED := "legend.volcano.bonded"
const F_GLACIER_BEATEN := "postgame.glacier_legend_beaten"
const F_GLACIER_BONDED := "legend.glacier.bonded"
const F_CRYPT_BOSS_BEATEN := "postgame.crypt_boss_beaten"
const VOLCANO_BATTLE_ID := "postgame.legend.volcano"
const GLACIER_BATTLE_ID := "postgame.legend.glacier"
const CRYPT_BATTLE_ID := "postgame.crypt.boss"
const GLACIER_MAP_PATH := CONTENT + "battles/ow_glacier_cave.tres"
const CRYPT_MAP_PATH := CONTENT + "battles/ow_crypt_depths.tres"
const POSTGAME_SQUAD_SIZE := 4


## A post-game LEGEND in the overworld ([param id], roster unit [param unit]): talk -> "Face it?" -> the
## TACTICAL legend battle ([param spec]) -> on a win the OPTIONAL bond (#75), asked again on later talks.
func _postgame_legend(id: String, cell: Vector2i, unit: String, spec: BattleSpec, beaten: String, bonded: String,
		stir: String) -> NpcEntity:
	var e := NpcEntity.new()
	e.id = StringName(id)
	e.cell = Vector3i(cell.x, cell.y, 0)
	e.facing = "south"
	e.display_name = _species_name(StringName(unit))
	e.speaker_name = e.display_name
	e.visual_character = StringName(unit)
	e.visible_if = "not has(\"%s\")" % bonded
	var bond := _bond_offer(unit, bonded, "%s watches you, still. Bond with it?" % e.display_name)
	var fight := StartBattleCommand.new()
	fight.spec = spec
	fight.source = BattleRequest.SOURCE_SCRIPT
	var face := ChoiceCommand.new()
	face.prompt = _narr(stir)
	face.options = StoryCommand.list([
		ChoiceOption.make("Face it", [fight, IfCommand.make("outcome() == \"victory\"", [bond])]),
		ChoiceOption.make("Not yet", [], true),
	])
	e.on_interact = StoryCommand.list([IfCommand.make("not has(\"%s\")" % beaten, [face], [bond])])
	return e


## A post-game LEGEND's tactical spec: FIXED above the post-game band (#81), Try Again on a loss.
func _postgame_legend_spec(battle_id: String, map_path: String, unit: String, beaten: String) -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.encounter_id = battle_id
	spec.map_path = map_path
	spec.squad_size = POSTGAME_SQUAD_SIZE
	spec.ai_difficulty = 1
	spec.opponent_name = _species_name(StringName(unit))
	var team: Array[Dictionary] = [{"character_id": unit, "strength": 1.0}]
	spec.opponent_team = team
	BattleSpec.make_legend(spec, POSTGAME_BAND)
	var flags: Array[String] = [beaten]
	spec.reward_flags = flags
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	return spec


## A legend's board: the legend (BOSS) with two screens at [constant LV_LEGEND_SCREEN], your squad
## chairs to the south; [param painter] paints the ground. Eliminate All Enemies.
func _postgame_legend_map(path: String, nm: String, desc: String, lighting: String, env: String, unit: String,
		screen: String, screen_level: int, painter: Callable) -> void:
	var m := _new_map(nm, 12, 10, desc)
	m.lighting_preset = lighting
	m.environment_preset = env
	_paint(m, painter)
	m.unit_spawns.clear()
	for c in [Vector2i(4, 8), Vector2i(6, 8), Vector2i(8, 8), Vector2i(5, 9)]:
		m.set_character_spawn_at_position(c, 0, String(STARTER_ID))
	m.set_character_spawn_at_position(Vector2i(6, 2), 1, unit, "BOSS")
	for c in [Vector2i(3, 3), Vector2i(9, 3)]:
		m.set_character_spawn_at_position(c, 1, screen)
		m.unit_spawns[m.unit_spawns.size() - 1]["level"] = screen_level
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, path)


# --- The volcano near Stormreef Isle (#98) -----------------------------------------------
#
# STORMREEF WATERS: the open sea south of Beach Village (its sea route), reefs, and the shore of Stormreef
# Isle along the south edge (its landing stays closed until the isle is built). Two looks of the same
# water, swapped by the post-game flag (Beach Village's sea route leads to one or the other):
#   stormreef_waters          -- calm sea;
#   stormreef_waters_erupted  -- the VOLCANO has erupted: a NEW ISLAND stands in the water, lava in its
#                                crater, and the new LEGEND on the crater's rim.

const SW_W := 26
const SW_H := 20
const SW_NORTH := Rect2i(11, 0, 4, 1)
const SW_REEFS := [Rect2i(3, 4, 2, 2), Rect2i(21, 2, 2, 1), Rect2i(6, 13, 1, 2), Rect2i(19, 15, 2, 1)]
## The new island: its shore ring, its slopes, the crater (lava) and the rim cell where the legend waits.
const SW_ISLAND := Rect2i(13, 5, 9, 8)
const SW_CRATER := Rect2i(16, 7, 3, 3)
## The whirlpool to the Island of Tides, in the east of the water.
const SW_WHIRLPOOL := Vector2i(24, 9)
## The way up the volcano, on the island's south slope.
const SW_VOLCANO_DOOR := Vector2i(17, 11)
const SW_ISLE_SHORE_Y := 18


func _sw_terrain(x: int, y: int, erupted: bool) -> String:
	var c := Vector2i(x, y)
	if y >= SW_ISLE_SHORE_Y:
		return "sand"
	if _in(SW_REEFS, c):
		return "basalt_column"
	if erupted and SW_ISLAND.has_point(c):
		if SW_CRATER.has_point(c):
			return "molten_lava" if c == SW_CRATER.position + Vector2i(1, 1) else "magma_vent"
		# A ring of black glass round the crater, ash on the slopes, a sandy landing to the west.
		var dx: int = mini(x - SW_ISLAND.position.x, SW_ISLAND.end.x - 1 - x)
		var dy: int = mini(y - SW_ISLAND.position.y, SW_ISLAND.end.y - 1 - y)
		if dx == 0 or dy == 0:
			return "deep_water" if (dx == 0 and dy == 0) else "sand"
		if absi(x - (SW_CRATER.position.x + 1)) <= 2 and absi(y - (SW_CRATER.position.y + 1)) <= 2:
			return "obsidian"
		return "ash_field"
	return "deep_water"


func _build_stormreef_waters(erupted: bool) -> void:
	var aid: String = "stormreef_waters_erupted" if erupted else "stormreef_waters"
	var t := _new_map("Stormreef Waters", SW_W, SW_H,
		("The sea off Stormreef Isle after the eruption: a new volcanic island stands in the water." if erupted
			else "The open sea south of Beach Village, off Stormreef Isle.") + " Story-mode terrain.")
	t.lighting_preset = "Dusk" if erupted else "Day"
	_paint(t, func(x: int, y: int) -> String: return _sw_terrain(x, y, erupted))
	_add_validator_anchors(t, Vector2i(SW_NORTH.position.x, SW_ISLE_SHORE_Y), Vector2i(SW_NORTH.position.x + 2, SW_ISLE_SHORE_Y))
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)

	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	a.display_name = "Stormreef Waters"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "stormreef_waters")
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	# Arriving by sea (you are riding: a boot on the water keeps the ride), and on the isle's sand.
	a.entry_points = {
		"north": {"cell": [SW_NORTH.position.x + 1, 1, 0], "facing": "south"},
		"shore": {"cell": [SW_NORTH.position.x + 1, SW_ISLE_SHORE_Y, 0], "facing": "east"},
		# Back from the Island of Tides' currents, on the water east of the whirlpool.
		"east": {"cell": [SW_WHIRLPOOL.x - 1, SW_WHIRLPOOL.y, 0], "facing": "west"},
	}
	if erupted:
		a.entry_points["volcano_door"] = {"cell": [SW_VOLCANO_DOOR.x, SW_VOLCANO_DOOR.y + 1, 0], "facing": "west"}
	var ents: Array = []
	ents.append(_warp("north_exit", SW_NORTH, &"beach_village", &"sea_route"))
	# The whirlpool that carries you to the Island of Tides (#44 / #103).
	ents.append_array(_whirlpool("tides_whirlpool", SW_WHIRLPOOL, "island_of_tides", "whirlpool", "", TIDES_WHIRLPOOL_IF))
	ents.append(_sign("isle_sign", Vector2i(SW_NORTH.position.x + 3, SW_ISLE_SHORE_Y), "Stormreef Isle",
		"STORMREEF ISLE"))
	ents.append(_closed_road("isle_landing", Rect2i(0, SW_H - 1, SW_W, 1), "stormreef_isle", StringName(aid), &"shore",
		"Stormreef Isle's cliffs rise straight from the reef here. There is no way up -- not yet."))  # TODO(story)
	if erupted:
		ents.append_array(_volcano_scenery())
		# The way up the volcano (#105: a straightforward climb to its legend).
		ents.append(_warp("volcano_path", Rect2i(SW_VOLCANO_DOOR.x, SW_VOLCANO_DOOR.y, 1, 1), &"volcano_path", &"south"))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/%s/area.tres" % aid)


func _volcano_scenery() -> Array:
	var out: Array = []
	for fc in [Vector2i(15, 7), Vector2i(19, 9), Vector2i(16, 10), Vector2i(19, 6)]:
		out.append(_prop("lava_fire_%d_%d" % [fc.x, fc.y], "fire", fc, Vector2i.ONE, Color.WHITE, true))
	for rc in [Vector2i(14, 9), Vector2i(20, 11)]:
		out.append(_prop("lava_rock_%d_%d" % [rc.x, rc.y], "boulder", rc, Vector2i.ONE, Color(0.16, 0.13, 0.14), true))
	return out


# --- The Snowy Peaks: the blizzard and the hidden cave (#99) -----------------------------
#
# THE SNOWY PEAKS (route): the high trail north out of Frostpeak, pines and dark rock, scrub where wild
# creatures roam. In its northern cliff a cave mouth is SEALED by packed ice and fallen rock. In the
# post-game a BLIZZARD covers the region (here and Frostpeak: OverworldAreaResource.weather_if) and the
# storm has torn the ice away: the mouth is open, and the FROZEN CAVE holds the new LEGEND at its end.

const SP_W := 24
const SP_H := 22
const SP_SOUTH_X := 11
## The cliff along the north (dark rock), the sealed cave mouth in it.
const SP_CLIFF_Y := 2
const SP_MOUTH := Vector2i(17, 2)
const SP_SCRUB := [Rect2i(3, 14, 4, 3), Rect2i(15, 12, 4, 3), Rect2i(4, 5, 3, 2)]
const SP_ICE := [Rect2i(13, 6, 4, 2)]


func _sp_trail(x: int, y: int) -> bool:
	# Up from Frostpeak, a bend east, and on to the cave mouth.
	if x == SP_SOUTH_X and y >= 9:
		return true
	if y == 9 and x >= SP_SOUTH_X and x <= SP_MOUTH.x:
		return true
	return x == SP_MOUTH.x and y >= SP_CLIFF_Y and y <= 9


func _sp_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if x == SP_SOUTH_X and y == SP_H - 1:
		return "frozen_tundra"
	if c == SP_MOUTH:
		return "frozen_tundra"
	if y <= SP_CLIFF_Y:
		return "basalt_column"
	if x == 0 or x == SP_W - 1 or y == SP_H - 1:
		return "frozen_pine"
	if _sp_trail(x, y):
		return "frozen_tundra"
	if _in(SP_SCRUB, c):
		return "tall_grass"
	if _in(SP_ICE, c):
		return "ice_sheet"
	if absi(x - SP_SOUTH_X) > 1 and _h(x, y, 151) < 0.18:
		return "frozen_pine"
	return "snow_field"


func _build_snowy_peaks() -> void:
	var t := _new_map("The Snowy Peaks", SP_W, SP_H,
		"The Snowy Peaks: the high trail north of Frostpeak Village. Story-mode terrain.")
	t.lighting_preset = "Day"
	t.environment_preset = "Snow"
	_paint(t, _sp_terrain)
	_add_validator_anchors(t, Vector2i(SP_SOUTH_X, SP_H - 2), Vector2i(SP_MOUTH.x, SP_MOUTH.y + 1))
	_save(t, CONTENT + "areas/snowy_peaks/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"snowy_peaks"
	a.display_name = "The Snowy Peaks"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "snowy_peaks")
	a.terrain = load(CONTENT + "areas/snowy_peaks/terrain.tres")
	a.weather_alt = "blizzard"
	a.weather_if = POSTGAME
	a.entry_points = {
		"south_trail": {"cell": [SP_SOUTH_X, SP_H - 2, 0], "facing": "north"},
		"cave_mouth": {"cell": [SP_MOUTH.x, SP_MOUTH.y + 1, 0], "facing": "south"},
	}
	var ents: Array = []
	ents.append(_sign("trail_sign", Vector2i(SP_SOUTH_X + 1, SP_H - 3), "The Snowy Peaks",
		"THE HIGH TRAIL\nSouth: Frostpeak Village."))
	# The SEALED mouth until the post-game's blizzard tears the ice away (#99).
	var seal := _prop("ice_seal", "boulder", SP_MOUTH, Vector2i.ONE, Color(0.72, 0.82, 0.92), true, "not (%s)" % POSTGAME)
	seal.on_interact = StoryCommand.list([
		_say([_narr("A wall of packed ice and fallen rock seals what might once have been a cave. It will not budge.")]),  # TODO(story)
	])
	ents.append(seal)
	ents.append(_warp("cave_exit", Rect2i(SP_MOUTH.x, SP_MOUTH.y, 1, 1), &"glacier_cave", &"mouth", POSTGAME))
	ents.append(_warp("south_exit", Rect2i(SP_SOUTH_X, SP_H - 1, 1, 1), &"frostpeak_village", &"north_trail"))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	var zones: Array[Resource] = [_wild_zone(["tall_grass"], [["gem_knight", 1.5], ["mycothrall", 1.0], ["monster", 1.0]])]
	a.encounter_zones = zones
	_save(a, CONTENT + "areas/snowy_peaks/area.tres")


func _build_glacier_map() -> void:
	_postgame_legend_map(GLACIER_MAP_PATH, "The Frozen Cave",
		"The ice-bound chamber at the end of the cave on the Snowy Peaks.", "Dusk", "Snow",
		GLACIER_LEGEND_UNIT, "gem_knight", LV_LEGEND_SCREEN, func(x: int, y: int) -> String:
			var c := Vector2i(x, y)
			if c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(10, 0), Vector2i(11, 0), Vector2i(0, 9), Vector2i(11, 9),
					Vector2i(2, 5), Vector2i(9, 5)]:
				return "frozen_pine"
			if y <= 4 and absi(x - 6) <= 3:
				return "ice_sheet"
			return "snow_field")


# --- The graveyard on Crownhaven's outskirts and the crypt below it (#100) ----------------
#
# CROWNHAVEN GRAVEYARD: off the Sparse Forest's east end, just outside the city's west gate -- rows of
# gravestones, a gravekeeper. Once the FINAL BOSS is defeated, one headstone is found pushed aside and
# its tomb OPEN: steps down to THE OLD CRYPT (a new place), restless dead in its halls, and a BOSS at its
# end (a tactical battle).

const GY_W := 20
const GY_H := 16
const GY_SOUTH_X := 10
const GY_ROWS: Array[int] = [4, 7, 10]
const GY_COLS: Array[int] = [4, 6, 8, 12, 14, 16]
## The grave that opens (one of the rows'), and where its headstone ends up.
const GY_OPEN := Vector2i(6, 7)
const GY_MOVED := Vector2i(5, 6)
const GY_CHAPEL := Rect2i(8, 1, 4, 2)
const GY_KEEPER := Vector2i(13, 13)
## TODO(story): placeholder epitaphs (no names -- nobody buried here is anyone the owner named).
const GY_EPITAPHS: Array[String] = ["The name has worn away.", "Rest well.", "Gone on ahead.",
	"The letters are too weathered to read.", "Remembered."]



func _gy_terrain(x: int, y: int) -> String:
	var c := Vector2i(x, y)
	if x == GY_SOUTH_X and y == GY_H - 1:
		return "forest_dirt"
	if x == 0 or y == 0 or x == GY_W - 1 or y == GY_H - 1:
		return "tree"
	if GY_CHAPEL.has_point(c):
		return "stone_wall"
	if x == GY_SOUTH_X and y >= GY_CHAPEL.end.y:
		return "forest_dirt"
	if y in [5, 8, 11] and x >= 3 and x <= GY_W - 4:
		return "forest_dirt"
	return "grass_plains"


func _build_graveyard() -> void:
	var t := _new_map("Crownhaven Graveyard", GY_W, GY_H,
		"Crownhaven's graveyard, on the city's outskirts beyond the west gate. Story-mode terrain.")
	t.lighting_preset = "Dusk"
	_paint(t, _gy_terrain)
	_add_validator_anchors(t, Vector2i(GY_SOUTH_X, GY_H - 2), Vector2i(GY_SOUTH_X, GY_CHAPEL.end.y))
	_save(t, CONTENT + "areas/crownhaven_graveyard/terrain.tres")

	var a := OverworldAreaResource.new()
	a.area_id = &"crownhaven_graveyard"
	a.display_name = "Crownhaven Graveyard"
	a.kind = OverworldAreaResource.Kind.ROUTE
	_place(a, "crownhaven_graveyard")
	a.terrain = load(CONTENT + "areas/crownhaven_graveyard/terrain.tres")
	a.entry_points = {
		"south_gate": {"cell": [GY_SOUTH_X, GY_H - 2, 0], "facing": "north"},
		"tomb": {"cell": [GY_OPEN.x, GY_OPEN.y + 1, 0], "facing": "north"},
	}
	var ents: Array = []
	ents.append(_prop("gy_chapel", "chapel", GY_CHAPEL.position, GY_CHAPEL.size, Color(0.34, 0.34, 0.4)))
	ents.append(_prop("gy_fence_w", "fence", Vector2i(1, 13), Vector2i(8, 1), Color(0.2, 0.2, 0.22)))
	ents.append(_prop("gy_fence_e", "fence", Vector2i(12, 13), Vector2i(1, 1), Color(0.2, 0.2, 0.22)))
	var k: int = 0
	for y in GY_ROWS:
		for x in GY_COLS:
			var cell := Vector2i(x, y)
			var stone := _sign("grave_%d_%d" % [x, y], cell, "Gravestone", GY_EPITAPHS[k % GY_EPITAPHS.size()], "grave")
			stone.tint = Color(0.56, 0.56, 0.54).darkened(0.08 * float(k % 3))
			if cell == GY_OPEN:
				# The grave that opens after the final boss (#100).
				stone.id = &"old_grave"
				stone.text = "An old headstone, its letters worn smooth."  # TODO(story)
				stone.visible_if = "not (%s)" % AFTER_FINAL_BOSS
			ents.append(stone)
			k += 1
	var moved := _sign("old_grave_moved", GY_MOVED, "Gravestone",
		"This headstone has been dragged out of its place. The grave beside it lies open.", "grave")  # TODO(story)
	moved.visible_if = AFTER_FINAL_BOSS
	ents.append(moved)
	ents.append(_prop("open_tomb", "tomb", GY_OPEN, Vector2i.ONE, Color(0.5, 0.5, 0.48), false, AFTER_FINAL_BOSS))
	ents.append(_warp("tomb_stairs", Rect2i(GY_OPEN.x, GY_OPEN.y, 1, 1), &"old_crypt", &"stairs", AFTER_FINAL_BOSS))
	ents.append(_npc("gravekeeper", GY_KEEPER, "west", "GRAVEKEEPER", Color(0.3, 0.3, 0.34), "elder"))
	ents.append(_warp("south_exit", Rect2i(GY_SOUTH_X, GY_H - 1, 1, 1), &"sparse_forest", &"graveyard_path"))
	_add_doors(a, ents)
	a.entities = _entities(ents)
	_save(a, CONTENT + "areas/crownhaven_graveyard/area.tres")


## THE CRYPT'S BOSS (#100): at the end of the crypt -- a TACTICAL battle (its minions on the board), FIXED
## at [constant LV_CRYPT_BOSS], Try Again on a loss. Who it is is the owner's call: a PLACEHOLDER unit.
func _crypt_spec() -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.encounter_id = CRYPT_BATTLE_ID
	spec.map_path = CRYPT_MAP_PATH
	spec.squad_size = POSTGAME_SQUAD_SIZE
	spec.ai_difficulty = 1
	spec.opponent_name = _species_name(StringName(CRYPT_BOSS_UNIT))
	var team: Array[Dictionary] = [{"character_id": CRYPT_BOSS_UNIT, "strength": 1.0}]
	for u in CRYPT_MINION_UNITS:
		team.append({"character_id": u, "strength": 1.0})
	spec.opponent_team = team
	spec.enemy_level = LV_CRYPT_BOSS
	spec.boss_battle = true
	var flags: Array[String] = [F_CRYPT_BOSS_BEATEN]
	spec.reward_flags = flags
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	return spec


## The crypt boss's board: a pillared burial hall. The boss (BOSS) and its minions to the north, your
## squad chairs to the south. Eliminate All Enemies.
func _build_crypt_map() -> void:
	var m := _new_map("The Crypt's End", 12, 10, "The burial hall at the end of the Old Crypt.")
	m.lighting_preset = "Night"
	var pillars := [Vector2i(3, 2), Vector2i(8, 2), Vector2i(3, 6), Vector2i(8, 6), Vector2i(0, 0), Vector2i(11, 0)]
	_paint(m, func(x: int, y: int) -> String:
		var c := Vector2i(x, y)
		if c in pillars:
			return "basalt_column"
		if (x == 1 or x == 10) and y >= 3 and y <= 5:
			return "ash_field"
		return "flagstones")
	m.unit_spawns.clear()
	for c in [Vector2i(4, 8), Vector2i(6, 8), Vector2i(8, 8), Vector2i(5, 9)]:
		m.set_character_spawn_at_position(c, 0, String(STARTER_ID))
	m.set_character_spawn_at_position(Vector2i(6, 1), 1, CRYPT_BOSS_UNIT, "BOSS")
	var mc := [Vector2i(4, 3), Vector2i(7, 3), Vector2i(6, 4)]
	for i in range(CRYPT_MINION_UNITS.size()):
		m.set_character_spawn_at_position(mc[i], 1, CRYPT_MINION_UNITS[i])
		m.unit_spawns[m.unit_spawns.size() - 1]["level"] = LV_CRYPT_MINIONS
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, CRYPT_MAP_PATH)


# =====================================================================================
#  THE DUNGEONS -- the areas before the big battles (DECISIONS.md #101-#106)
# =====================================================================================
#
# Each floor is laid out as an ASCII map (one string per row; a char per cell): the shapes are
# readable here and every floor is checked by the tests (reachability, the ice puzzles' solutions).
#   * the ICE dungeon (the Frozen Cave, #102): two SLIDE floors (OverworldAreaResource.slide_tiles) --
#     slide until a rock stops you; a wrong slide drops you through a crack back to the floor's start;
#     the right one ends in a HOLE down to the next level -- then the legend's chamber;
#   * the SEA dungeon (the Island of Tides, #44 / #103): reached through a WHIRLPOOL off Stormreef Isle;
#     its caves go DOWN through whirlpools in small lakes and holes in the floor -- some holes lead back
#     UP (backtrack) -- to the depths, where the legend waits (a tactical battle);
#   * the UNDERWORLD (the Old Crypt, #104): fairly straightforward, tough wild creatures, two MINI
#     BOSSES (duels) barring the way, then its boss (tactical);
#   * the VOLCANO (#105): a straightforward climb up the new island's volcano; its legend is an
#     ENCOUNTER battle (a duel, no tactical);
#   * the HIDDEN DEPTHS (#106): longer and straightforward -- epic ruins hidden in a cave, many strong
#     wild creatures -- and the boss whose AWAKENING begins the post-game (#98): beating it sets
#     F_POSTGAME. Its way in (Mountain Base) is not built yet.
# All lines are short neutral PLACEHOLDERS (TODO(story)); the units are battle-ready stand-ins.

## An area's ground from ASCII [param rows] ([param tiles]: char -> tile id; anything else -> [param fallback]).
func _paint_ascii(m: MapResource, rows: Array, tiles: Dictionary, fallback: String) -> void:
	_paint(m, func(x: int, y: int) -> String: return String(tiles.get(String(rows[y])[x], fallback)))


## Every cell of [param ch] in ASCII [param rows], row by row.
static func _ascii_cells(rows: Array, ch: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rows.size()):
		var row: String = String(rows[y])
		for x in range(row.length()):
			if row[x] == ch:
				out.append(Vector2i(x, y))
	return out


## One DUNGEON FLOOR from ASCII: terrain + area (kind DUNGEON, placed at [param location], [param band]
## when not ZERO), entries {id: [Vector2i, facing]}, the entities and zones given.
func _dungeon_floor(aid: String, nm: String, location: String, rows: Array, tiles: Dictionary, fallback: String,
		lighting: String, env: String, band: Vector2i, entries: Dictionary, ents: Array, zones: Array = [],
		slide: Array = []) -> OverworldAreaResource:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT + "areas/" + aid))
	var w: int = String(rows[0]).length()
	var t := _new_map(nm, w, rows.size(), "%s: a dungeon floor. Story-mode terrain." % nm)
	t.lighting_preset = lighting
	t.environment_preset = env
	_paint_ascii(t, rows, tiles, fallback)
	var keys: Array = entries.keys()
	var e0: Vector2i = entries[keys[0]][0]
	var e1: Vector2i = entries[keys[keys.size() - 1]][0]
	if e1 == e0:
		# One entry: the second anchor on an open neighbour of it.
		for d in OverworldGrid.DIRS:
			var n: Vector2i = e0 + d
			if n.y >= 0 and n.y < rows.size() and n.x >= 0 and n.x < w \
					and String(tiles.get(String(rows[n.y])[n.x], fallback)) != fallback:
				e1 = n
				break
	_add_validator_anchors(t, e0, e1)
	_save(t, CONTENT + "areas/%s/terrain.tres" % aid)
	var a := OverworldAreaResource.new()
	a.area_id = StringName(aid)
	a.display_name = nm
	a.kind = OverworldAreaResource.Kind.DUNGEON
	_place(a, location)
	if band != Vector2i.ZERO:
		a.level_band = band
	a.terrain = load(CONTENT + "areas/%s/terrain.tres" % aid)
	var ep: Dictionary = {}
	for k in entries:
		var c: Vector2i = entries[k][0]
		ep[k] = {"cell": [c.x, c.y, 0], "facing": String(entries[k][1])}
	a.entry_points = ep
	var st: Array[StringName] = []
	for s in slide:
		st.append(StringName(String(s)))
	a.slide_tiles = st
	_add_doors(a, ents)
	a.entities = _entities(ents)
	var zs: Array[Resource] = []
	for z in zones:
		zs.append(z)
	a.encounter_zones = zs
	_save(a, CONTENT + "areas/%s/area.tres" % aid)
	return a


## A HOLE in the floor at [param c] (a "hole" prop + its warp): down (or up) to [param target] / [param entry].
func _hole(id: String, c: Vector2i, target: String, entry: String, toast: String = "", tint: Color = Color(0.5, 0.56, 0.62)) -> Array:
	var w := _warp(id, Rect2i(c.x, c.y, 1, 1), StringName(target), StringName(entry))
	w.arrival_toast = toast
	return [_prop(id + "_pit", "hole", c, Vector2i.ONE, tint), w]


## A forced-looking but optional MINI BOSS (#104): a strong creature barring the way at [param c] -- talk ->
## a DUEL at [param level] (a loss whites out: it waits); won, it is gone for good ([param flag]).
func _mini_boss(id: String, c: Vector2i, unit: String, level: int, flag: String, stir: String) -> NpcEntity:
	var e := NpcEntity.new()
	e.id = StringName(id)
	e.cell = Vector3i(c.x, c.y, 0)
	e.facing = "south"
	e.display_name = _species_name(StringName(unit))
	e.speaker_name = e.display_name
	e.visual_character = StringName(unit)
	e.visible_if = "not has(\"%s\")" % flag
	var spec := _duel_spec(id.replace("_", "."), e.display_name, StringName("npc_" + id),
		[{"character_id": unit, "strength": MINI_BOSS_STRENGTH}], false, BattleSpec.DefeatPolicy.WHITEOUT, 0, [], [flag])
	spec.enemy_level = level
	spec.boss_battle = true
	spec.clash_intro = true
	var ask := ChoiceCommand.new()
	ask.prompt = _narr(stir)
	ask.options = StoryCommand.list([ChoiceOption.make("Fight", [_duel(spec)]), ChoiceOption.make("Not yet", [], true)])
	e.on_interact = StoryCommand.list([ask])
	return e


## A legend in its lair -- talk -> "Face it?" -> the [param spec] battle (tactical or a duel) -> the
## OPTIONAL bond (#75), asked again on later talks. (The post-game's helper with its own spec.)
func _lair_legend(id: String, c: Vector2i, unit: String, spec: BattleSpec, beaten: String, bonded: String,
		stir: String) -> NpcEntity:
	return _postgame_legend(id, c, unit, spec, beaten, bonded, stir)


## The strength multiplier of a dungeon's mini bosses (KNOB).
const MINI_BOSS_STRENGTH := 1.25


# --- THE ICE DUNGEON: the Frozen Cave (#102) -------------------------------------------------
#
# Floor 1: slide from the cave mouth across the ice to the HOLE in the north wall; floor 2 (where the
# hole drops you): slide down to the hole in the south wall; floor 3: the legend's chamber. A crack
# (X) a wrong slide ends in drops you back to the floor's start. Solved by the shortest route in 10
# and 9 slides (generated, then checked by test_dungeons.gd). '.' ground, 'I' ice, 'R' rock, 'X' a
# crack, 'H' the hole down, 'S' the start, 'U' a ladder back up.

const GC_TILES := {"#": "basalt_column", ".": "frozen_tundra", "S": "frozen_tundra", "U": "frozen_tundra",
	"H": "frozen_tundra", "I": "ice_sheet", "R": "ice_sheet", "X": "ice_sheet", "M": "frozen_tundra"}
const GC_FLOOR_1 := [
	"###############",
	"###H###########",
	"#IIIIRIIRIIIII#",
	"#RIIIRIXIIIIII#",
	"#IIIIIIIIIIIII#",
	"#IXIIIRIIIIIII#",
	"#IIIIIIIIRIIII#",
	"#IRIIIIIIXIIII#",
	"#IIIIIIRIIIIRI#",
	"#XRRIIRIRIIIII#",
	"#......S......#",
	"#######M#######",
]
const GC_FLOOR_2 := [
	"#U#############",
	"#......S......#",
	"#IIIIIIIIIRIII#",
	"#IRIIIIRIRIIII#",
	"#IIIIIIIIIIIIR#",
	"#IIIIIIRIIIIIR#",
	"#IIIIIIIIIIXII#",
	"#XRIRIIRRIIIII#",
	"#IIRIIIIIIIIII#",
	"#IIIRIRIIIIIXI#",
	"##########H####",
	"###############",
]
const GC_CHAMBER := [
	"################",
	"######....######",
	"#####......#####",
	"####IIIIIIII####",
	"###.IIIIIIII.###",
	"###..IIIIII..###",
	"####........####",
	"#####..U...#####",
	"################",
]
const GC_SLIP_TOAST := "You slip into a crack in the ice and tumble back down the slope..."  # TODO(story)


## The ice floors: the rocks (boulder props on 'R'), the cracks (holes back to the start), the hole
## down, the ladder up -- built from the ASCII rows.
func _ice_floor(aid: String, rows: Array, entries: Dictionary, down: Array, up: Array, start_entry: String) -> void:
	var ents: Array = []
	for c in _ascii_cells(rows, "R"):
		ents.append(_prop("rock_%d_%d" % [c.x, c.y], "boulder", c, Vector2i.ONE, Color(0.62, 0.7, 0.78), true))
	var k: int = 0
	for c in _ascii_cells(rows, "X"):
		ents.append_array(_hole("crack_%d" % k, c, aid, start_entry, GC_SLIP_TOAST, Color(0.72, 0.84, 0.94)))
		k += 1
	if not down.is_empty():
		for c in _ascii_cells(rows, "H"):
			ents.append_array(_hole("hole_down", c, String(down[0]), String(down[1])))
	if not up.is_empty():
		for c in _ascii_cells(rows, "U"):
			ents.append(_warp("ladder_up", Rect2i(c.x, c.y, 1, 1), StringName(String(up[0])), StringName(String(up[1]))))
	for c in _ascii_cells(rows, "M"):
		ents.append(_warp("mouth_exit", Rect2i(c.x, c.y, 1, 1), &"snowy_peaks", &"cave_mouth"))
	_dungeon_floor(aid, "Frozen Cave", "frozen_cave", rows, GC_TILES, "basalt_column", "Dusk", "Snow", POSTGAME_BAND,
		entries, ents, [], ["ice_sheet"])


func _build_glacier_cave() -> void:
	_ice_floor("glacier_cave", GC_FLOOR_1, {"mouth": [Vector2i(7, 10), "north"]},
		["glacier_cave_2", "drop"], [], "mouth")
	# Floor 2: the hole drops you on the north strip; the ladder climbs back to floor 1's start.
	_ice_floor("glacier_cave_2", GC_FLOOR_2, {"drop": [Vector2i(7, 1), "south"]},
		["glacier_cave_3", "drop"], ["glacier_cave", "mouth"], "drop")
	# The legend's chamber (its ice is only ice: no slide here).
	var ents: Array = []
	ents.append(_warp("ladder_up", Rect2i(7, 7, 1, 1), &"glacier_cave", &"mouth"))
	for cc in [Vector2i(4, 4), Vector2i(11, 4)]:
		var cr := _prop("ice_crystal_%d_%d" % [cc.x, cc.y], "crystal", cc, Vector2i.ONE, Color(0.62, 0.86, 1.0), true)
		cr.glow = 2.5
		ents.append(cr)
	ents.append(_postgame_legend("glacier_legend", Vector2i(7, 1), GLACIER_LEGEND_UNIT,
		_postgame_legend_spec(GLACIER_BATTLE_ID, GLACIER_MAP_PATH, GLACIER_LEGEND_UNIT, F_GLACIER_BEATEN),
		F_GLACIER_BEATEN, F_GLACIER_BONDED,
		"Frost creeps across the floor toward you, and the ice itself seems to breathe. Face it?"))  # TODO(story)
	_dungeon_floor("glacier_cave_3", "Frozen Cave", "frozen_cave", GC_CHAMBER, GC_TILES, "basalt_column", "Dusk", "Snow",
		POSTGAME_BAND, {"drop": [Vector2i(8, 6), "north"]}, ents)


# --- THE VOLCANO (#105): a straightforward climb, an encounter battle at the top --------------

const VP_TILES := {"#": "basalt_column", ".": "ash_field", ",": "obsidian", "L": "molten_lava", "V": "magma_vent"}
const VOLCANO_PATH := [
	"######,#######",
	"######,,######",
	"####VV.,.#####",
	"###...,..LL###",
	"##..L.,...L.##",
	"##.LL.,,....##",
	"##....LL,,..##",
	"###V.LL..,.###",
	"###..L..,,..##",
	"##..,,,,,.L.##",
	"##.,,LLL...V##",
	"##.,.LLL.....#",
	"##.,,.....L..#",
	"###.,,,,..LL.#",
	"####..L,,....#",
	"###....L,,..##",
	"####.....,.###",
	"#####...,,####",
	"######.,.#####",
	"#######,######",
]
const VOLCANO_CRATER := [
	"##############",
	"#####,,,,#####",
	"####,,,,,,####",
	"###,,LLLL,,###",
	"##,,LLLLLL,,##",
	"##,,LLLLLL,,##",
	"##,,,LLLL,,,##",
	"###,,,,,,,,###",
	"####...,...###",
	"#####..,..####",
	"######.,.#####",
	"#######,######",
]
const VOLCANO_DUEL_ID := "postgame.legend.volcano"


## THE VOLCANO'S LEGEND (#105): an ENCOUNTER battle -- a DUEL, FIXED above the post-game band like a
## legend (#81). A loss whites out (it waits); won, the optional bond.
func _volcano_spec() -> BattleSpec:
	var spec := _duel_spec(VOLCANO_DUEL_ID, _species_name(StringName(VOLCANO_LEGEND_UNIT)),
		StringName("npc_volcano_legend"), [{"character_id": VOLCANO_LEGEND_UNIT, "strength": 1.0}], false,
		BattleSpec.DefeatPolicy.WHITEOUT, 0, [], [F_VOLCANO_BEATEN])
	BattleSpec.make_legend(spec, POSTGAME_BAND)
	spec.clash_intro = true
	return spec


func _build_volcano() -> void:
	var ents: Array = []
	for fc in [Vector2i(5, 2), Vector2i(10, 3), Vector2i(10, 13)]:
		ents.append(_prop("vent_fire_%d_%d" % [fc.x, fc.y], "fire", fc, Vector2i.ONE, Color.WHITE, true))
	ents.append(_warp("south_exit", Rect2i(7, 19, 1, 1), &"stormreef_waters_erupted", &"volcano_door"))
	ents.append(_warp("north_exit", Rect2i(6, 0, 1, 1), &"volcano_crater", &"south"))
	_dungeon_floor("volcano_path", "The Volcano", "stormreef_waters", VOLCANO_PATH, VP_TILES, "basalt_column", "Dusk",
		"Volcanic", POSTGAME_BAND, {"south": [Vector2i(7, 18), "north"], "north": [Vector2i(6, 1), "south"]}, ents,
		[_wild_zone(["ash_field"], [["monster", 2.0], ["blightcap", 1.0]])])
	var crater: Array = []
	for fc in [Vector2i(5, 4), Vector2i(8, 5)]:
		crater.append(_prop("rim_fire_%d_%d" % [fc.x, fc.y], "fire", fc, Vector2i.ONE, Color.WHITE, true))
	crater.append(_postgame_legend("volcano_legend", Vector2i(7, 1), VOLCANO_LEGEND_UNIT, _volcano_spec(),
		F_VOLCANO_BEATEN, F_VOLCANO_BONDED,
		"Heat rolls off the crater, and something vast stirs in the glow. Face it?"))  # TODO(story)
	crater.append(_warp("south_exit", Rect2i(7, 11, 1, 1), &"volcano_path", &"north"))
	_dungeon_floor("volcano_crater", "The Volcano's Crater", "stormreef_waters", VOLCANO_CRATER, VP_TILES, "basalt_column",
		"Dusk", "Volcanic", POSTGAME_BAND, {"south": [Vector2i(7, 10), "north"]}, crater)


# --- THE UNDERWORLD: the Old Crypt (#104) ---------------------------------------------------
#
# Two halls, fairly straightforward: restless creatures in the ash ('s'), a MINI BOSS in each hall's
# doorway north (a duel), and the boss in the chamber at the end (tactical). ':' the walkway.

const CR_TILES := {"#": "basalt_column", ".": "flagstones", ":": "flagstones", "s": "ash_field"}
const CRYPT_HALL := [
	"#########:########",
	"#########:########",
	"######.##:##.#####",
	"#..............#.#",
	"#.ss#...:...#ss..#",
	"#.ss....:....ss..#",
	"#...#...:...#....#",
	"#.......:........#",
	"#...#...:...#....#",
	"#.ss....:....ss..#",
	"#.ss#...:...#ss..#",
	"#.......:........#",
	"#...#...:...#....#",
	"#.......:........#",
	"#...#...:...#....#",
	"#.......:........#",
	"#.......:........#",
	"#########:########",
]
const CRYPT_DEPTHS := [
	"########:#########",
	"########:#########",
	"#####.##:##.######",
	"#####.......######",
	"########:#########",
	"#..ss...:...ss...#",
	"#..ss.#.:.#.ss...#",
	"#.......:........#",
	"#.#.....:.....#..#",
	"#.......:........#",
	"#####...:...######",
	"#ss.....:.....ss.#",
	"#ss.#...:...#.ss.#",
	"#.......:........#",
	"#...#...:...#....#",
	"#.......:........#",
	"#.......:........#",
	"#########:########",
]
## The burial chamber at the crypt's end (beyond the second mini boss): the boss and its reward.
const CRYPT_END := [
	"##############",
	"####......####",
	"###........###",
	"###........###",
	"####......####",
	"#####....#####",
	"######..######",
	"######::######",
]
const F_CRYPT_MINI_1 := "postgame.crypt_mini_boss_1"
const F_CRYPT_MINI_2 := "postgame.crypt_mini_boss_2"
const CRYPT_MINI_UNITS: Array[String] = ["monster", "necromancer"]
const LV_CRYPT_MINI: Array[int] = [39, 41]


func _build_crypt() -> void:
	var zone := _wild_zone(["ash_field"], [["monster", 2.0], ["blightcap", 1.0]])
	var hall: Array = []
	for lc in [Vector2i(5, 15), Vector2i(13, 15), Vector2i(2, 3), Vector2i(14, 3)]:
		var lamp := _prop("crypt_lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(0.6, 0.86, 0.7), true)
		lamp.glow = 2.5
		hall.append(lamp)
	hall.append(_mini_boss("crypt_warden_1", Vector2i(9, 2), CRYPT_MINI_UNITS[0], LV_CRYPT_MINI[0], F_CRYPT_MINI_1,
		"Something huge stirs in the doorway, barring the way deeper. Fight?"))  # TODO(story)
	hall.append(_warp("stairs_up", Rect2i(9, 17, 1, 1), &"crownhaven_graveyard", &"tomb"))
	hall.append(_warp("north_exit", Rect2i(9, 0, 1, 1), &"old_crypt_depths", &"south"))
	_dungeon_floor("old_crypt", "The Old Crypt", "old_crypt", CRYPT_HALL, CR_TILES, "basalt_column", "Night", "Default",
		POSTGAME_BAND, {"stairs": [Vector2i(9, 16), "north"], "north": [Vector2i(9, 1), "south"]}, hall, [zone])
	var deep: Array = []
	for lc in [Vector2i(5, 2), Vector2i(11, 2)]:
		var lamp := _prop("crypt_lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(0.6, 0.86, 0.7), true)
		lamp.glow = 3.0
		deep.append(lamp)
	deep.append(_mini_boss("crypt_warden_2", Vector2i(8, 2), CRYPT_MINI_UNITS[1], LV_CRYPT_MINI[1], F_CRYPT_MINI_2,
		"A cold shape rises in the last doorway. It will not let you pass. Fight?"))  # TODO(story)
	deep.append(_warp("south_exit", Rect2i(9, 17, 1, 1), &"old_crypt", &"north"))
	deep.append(_warp("north_exit", Rect2i(8, 0, 1, 1), &"old_crypt_end", &"south"))
	_dungeon_floor("old_crypt_depths", "The Old Crypt", "old_crypt", CRYPT_DEPTHS, CR_TILES, "basalt_column", "Night",
		"Default", POSTGAME_BAND, {"south": [Vector2i(9, 16), "north"], "north": [Vector2i(8, 1), "south"]}, deep, [zone])
	# The burial chamber: the boss, and the reward once it falls.
	var end: Array = []
	for lc in [Vector2i(4, 1), Vector2i(9, 1)]:
		var lamp := _prop("crypt_lamp_%d_%d" % [lc.x, lc.y], "lamp", lc, Vector2i.ONE, Color(0.6, 0.86, 0.7), true)
		lamp.glow = 3.0
		end.append(lamp)
	end.append(_crypt_boss(Vector2i(6, 1)))
	var chest := _chest("crypt_chest", Vector2i(8, 2), "south", [&"dawnpetal_draught", &"dawnpetal_draught", &"bitterroot_salve"], 600)
	chest.visible_if = "has(\"%s\")" % F_CRYPT_BOSS_BEATEN
	end.append(chest)
	end.append(_warp("south_exit", Rect2i(6, 7, 2, 1), &"old_crypt_depths", &"north"))
	_dungeon_floor("old_crypt_end", "The Old Crypt", "old_crypt", CRYPT_END, CR_TILES, "basalt_column", "Night",
		"Default", POSTGAME_BAND, {"south": [Vector2i(6, 6), "north"]}, end)


func _crypt_boss(c: Vector2i) -> NpcEntity:
	var e := NpcEntity.new()
	e.id = &"crypt_boss"
	e.cell = Vector3i(c.x, c.y, 0)
	e.facing = "south"
	e.display_name = _species_name(StringName(CRYPT_BOSS_UNIT))
	e.speaker_name = e.display_name
	e.visual_character = StringName(CRYPT_BOSS_UNIT)
	e.visible_if = "not has(\"%s\")" % F_CRYPT_BOSS_BEATEN
	var fight := StartBattleCommand.new()
	fight.spec = _crypt_spec()
	fight.source = BattleRequest.SOURCE_SCRIPT
	var face := ChoiceCommand.new()
	face.prompt = _narr("Cold light gathers in the dark at the end of the crypt -- and something rises to meet you. Fight?")  # TODO(story)
	face.options = StoryCommand.list([
		ChoiceOption.make("Fight", [fight, IfCommand.make("outcome() == \"victory\"", [
			_say([_narr("The light gutters out, and the crypt falls silent.")]),  # TODO(story)
			SaveGameCommand.new(),
		])]),
		ChoiceOption.make("Not yet", [], true),
	])
	e.on_interact = StoryCommand.list([face])
	return e


# --- THE HIDDEN DEPTHS (#106): epic ruins in a cave; the boss that begins the post-game ----------
#
# Four areas, one way through, south to north: the cave, two halls of ruins, and the heart where the
# boss sleeps. 'm' moss where strong wild creatures roam; ':' the old road through the ruins. Its way
# in from Mountain Base is not built yet (the south exit answers until it is). Beating the boss
# AWAKENS it -- the post-game begins (#98: F_POSTGAME).

const HD_TILES := {"#": "basalt_column", ".": "forest_dirt", ":": "flagstones", "m": "tall_grass"}
const HDN_CAVE := [
	"##########::########",
	"#########.:.########",
	"########..:..#######",
	"###mm....::....#####",
	"##mmm...::.....mm###",
	"##mm...::......mmm##",
	"###...::...##...mm##",
	"####..:...####...###",
	"###...::...##....###",
	"##mm...::......mm###",
	"##mmm...::....mmm###",
	"###mm....::....m####",
	"#####.....::...#####",
	"#######....::..#####",
	"#########..::#######",
	"##########::########",
]
const HDN_RUINS_1 := [
	"##########:###########",
	"#####...#.:.#...######",
	"####.mm...:...mm.#####",
	"###..mm.#.:.#.mm..####",
	"##..#...#.:.#...#..###",
	"##......#.:.#......###",
	"##mm#.........#.mm.###",
	"##mm.....:::......####",
	"###.#...#.:.#...#..###",
	"###.....#.:.#.....####",
	"####.mm...:...mm.#####",
	"#####mm.#.:.#.mm.#####",
	"######....:....#######",
	"#######...:...########",
	"########..:..#########",
	"##########:###########",
]
const HDN_RUINS_2 := [
	"###########:##########",
	"#########...:..#######",
	"#########.#:#.#.######",
	"#######.........######",
	"######mm#.#:#.#mm#####",
	"#####.mm...:...mm.####",
	"####.#.#.#.:.#.#.#.###",
	"###mm......:......mm##",
	"###mm#.#.#.:.#.#.#mm##",
	"####.......:.......###",
	"#####.#.#.#:#.#.#.####",
	"######mm...:...mm#####",
	"#######mm..:..mm######",
	"########...:...#######",
	"##########.:.#########",
	"###########:##########",
]
const HDN_HEART := [
	"##################",
	"######......######",
	"#####........#####",
	"####..........####",
	"###....::::....###",
	"###...:::::....###",
	"###....::::....###",
	"####..........####",
	"#####...::...#####",
	"######..::..######",
	"#######.::.#######",
	"########::########",
	"########::########",
	"########::########",
]
const F_DEPTHS_BOSS_BEATEN := "hidden_depths.boss_beaten"
const DEPTHS_BOSS_ID := "hidden_depths.boss"
const DEPTHS_BOSS_MAP_PATH := CONTENT + "battles/ow_hidden_depths.tres"
## PLACEHOLDER battle-ready units: the boss (the owner's to decide) and its guard.
const DEPTHS_BOSS_UNIT := "monster"
const DEPTHS_GUARD_UNITS: Array[String] = ["gem_knight", "gem_knight"]
## FIXED above the Northern Mountains band (25-35), the main game's last stretch (KNOB).
const LV_DEPTHS_BOSS := 38
const LV_DEPTHS_GUARDS := 35


func _hdn_ruin_props(prefix: String, rows: Array) -> Array:
	var out: Array = []
	# Glowing crystals along the old road, rubble in the side halls (PLACEHOLDER looks).
	var road: Array[Vector2i] = _ascii_cells(rows, ":")
	for i in range(0, road.size(), 4):
		var c: Vector2i = road[i] + Vector2i(1, 0)
		if String(rows[c.y])[c.x] == ".":
			var cr := _prop("%s_crystal_%d_%d" % [prefix, c.x, c.y], "crystal", c, Vector2i.ONE, Color(0.55, 0.9, 1.0), true)
			cr.glow = 3.0
			out.append(cr)
	return out


func _build_hidden_depths() -> void:
	var zone := _wild_zone(["tall_grass"], [["gem_knight", 2.0], ["monster", 1.5]])
	var band: Vector2i = REGION_BANDS["northern_mountains"]
	# The cave. Its way back down to Mountain Base: not built yet.
	var cave: Array = _hdn_ruin_props("hd0", HDN_CAVE)
	cave.append(_closed_road("south_exit", Rect2i(10, 15, 2, 1), "mountain_base", &"hidden_depths", &"south",
		"The path back down toward Mountain Base is buried under a fresh rockfall. Not that way -- not yet."))  # TODO(story)
	cave.append(_warp("north_exit", Rect2i(10, 0, 2, 1), &"hidden_depths_2", &"south"))
	_dungeon_floor("hidden_depths", "Hidden Depths", "hidden_depths", HDN_CAVE, HD_TILES, "basalt_column", "Dusk",
		"Default", band, {"south": [Vector2i(10, 14), "north"], "north": [Vector2i(10, 1), "south"]}, cave, [zone])
	var r1: Array = _hdn_ruin_props("hd1", HDN_RUINS_1)
	r1.append(_warp("south_exit", Rect2i(10, 15, 1, 1), &"hidden_depths", &"north"))
	r1.append(_warp("north_exit", Rect2i(10, 0, 1, 1), &"hidden_depths_3", &"south"))
	_dungeon_floor("hidden_depths_2", "Hidden Depths", "hidden_depths", HDN_RUINS_1, HD_TILES, "basalt_column", "Dusk",
		"Default", band, {"south": [Vector2i(10, 14), "north"], "north": [Vector2i(10, 1), "south"]}, r1, [zone])
	var r2: Array = _hdn_ruin_props("hd2", HDN_RUINS_2)
	r2.append(_warp("south_exit", Rect2i(11, 15, 1, 1), &"hidden_depths_2", &"north"))
	r2.append(_warp("north_exit", Rect2i(11, 0, 1, 1), &"hidden_depths_heart", &"south"))
	_dungeon_floor("hidden_depths_3", "Hidden Depths", "hidden_depths", HDN_RUINS_2, HD_TILES, "basalt_column", "Dusk",
		"Default", band, {"south": [Vector2i(11, 14), "north"], "north": [Vector2i(11, 1), "south"]}, r2, [zone])
	var heart: Array = _hdn_ruin_props("hd3", HDN_HEART)
	heart.append(_depths_boss(Vector2i(8, 2)))
	heart.append(_warp("south_exit", Rect2i(8, 13, 2, 1), &"hidden_depths_3", &"north"))
	_dungeon_floor("hidden_depths_heart", "Heart of the Depths", "hidden_depths", HDN_HEART, HD_TILES, "basalt_column",
		"Dusk", "Default", band, {"south": [Vector2i(8, 12), "north"]}, heart)


## THE HIDDEN DEPTHS' BOSS (#98 / #106): TACTICAL, FIXED; beating it AWAKENS it -- the post-game begins
## (F_POSTGAME). Try Again on a loss. TODO(story): who it is, and what its awakening means.
func _depths_boss_spec() -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.TACTICAL
	spec.encounter_id = DEPTHS_BOSS_ID
	spec.map_path = DEPTHS_BOSS_MAP_PATH
	spec.squad_size = POSTGAME_SQUAD_SIZE
	spec.ai_difficulty = 1
	spec.opponent_name = _species_name(StringName(DEPTHS_BOSS_UNIT))
	var team: Array[Dictionary] = [{"character_id": DEPTHS_BOSS_UNIT, "strength": 1.0}]
	for u in DEPTHS_GUARD_UNITS:
		team.append({"character_id": u, "strength": 1.0})
	spec.opponent_team = team
	spec.enemy_level = LV_DEPTHS_BOSS
	spec.boss_battle = true
	var flags: Array[String] = [F_DEPTHS_BOSS_BEATEN, F_POSTGAME]
	spec.reward_flags = flags
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	return spec


func _depths_boss(c: Vector2i) -> NpcEntity:
	var e := NpcEntity.new()
	e.id = &"depths_boss"
	e.cell = Vector3i(c.x, c.y, 0)
	e.facing = "south"
	e.display_name = _species_name(StringName(DEPTHS_BOSS_UNIT))
	e.speaker_name = e.display_name
	e.visual_character = StringName(DEPTHS_BOSS_UNIT)
	e.visible_if = "not has(\"%s\")" % F_DEPTHS_BOSS_BEATEN
	var fight := StartBattleCommand.new()
	fight.spec = _depths_boss_spec()
	fight.source = BattleRequest.SOURCE_SCRIPT
	var face := ChoiceCommand.new()
	face.prompt = _narr("Something vast sleeps at the heart of the ruins. As you come near, it stirs. Face it?")  # TODO(story)
	face.options = StoryCommand.list([
		ChoiceOption.make("Face it", [fight, IfCommand.make("outcome() == \"victory\"", [
			_say([_narr("The depths shudder. Far away, the ground answers.")]),  # TODO(story)
			SaveGameCommand.new(),
		])]),
		ChoiceOption.make("Not yet", [], true),
	])
	e.on_interact = StoryCommand.list([face])
	return e


func _build_depths_boss_map() -> void:
	var m := _new_map("The Heart of the Depths", 12, 10, "The ruined hall at the heart of the Hidden Depths.")
	m.lighting_preset = "Dusk"
	var pillars := [Vector2i(2, 2), Vector2i(9, 2), Vector2i(2, 6), Vector2i(9, 6), Vector2i(0, 0), Vector2i(11, 0)]
	_paint(m, func(x: int, y: int) -> String:
		var c := Vector2i(x, y)
		if c in pillars:
			return "basalt_column"
		if x >= 5 and x <= 6:
			return "flagstones"
		return "forest_dirt")
	m.unit_spawns.clear()
	for c in [Vector2i(4, 8), Vector2i(6, 8), Vector2i(8, 8), Vector2i(5, 9)]:
		m.set_character_spawn_at_position(c, 0, String(STARTER_ID))
	m.set_character_spawn_at_position(Vector2i(5, 1), 1, DEPTHS_BOSS_UNIT, "BOSS")
	var gc := [Vector2i(3, 3), Vector2i(8, 3)]
	for i in range(DEPTHS_GUARD_UNITS.size()):
		m.set_character_spawn_at_position(gc[i], 1, DEPTHS_GUARD_UNITS[i])
		m.unit_spawns[m.unit_spawns.size() - 1]["level"] = LV_DEPTHS_GUARDS
	var vc: Array[String] = ["Eliminate All Enemies"]
	m.victory_conditions = vc
	_save(m, DEPTHS_BOSS_MAP_PATH)


# --- THE SEA DUNGEON: the Island of Tides (#44 / #103) ------------------------------------------
#
# A WHIRLPOOL off Stormreef Isle carries the hero (riding the sea move) to the Island of Tides. (#44:
# "when it is RAINING and at NIGHT, going into a WHIRLPOOL brings the hero to the island" -- the in-game
# clock and rain are not built: TIDES_WHIRLPOOL_IF is the knob.) In its cave the way DOWN is through
# WHIRLPOOLS in small lakes ('W', ridden) and HOLES in the floor ('d'); some holes lead back UP ('u',
# and cave 3's 'd') -- backtracking. At the bottom, the legend (a tactical battle).
# '.' cave floor, 's' sea grass (wild creatures), '~' water, '#' rock, 'O' the cave mouth.

const TIDES_TILES := {"#": "basalt_column", ".": "sand", "s": "tall_grass", "~": "deep_water", "W": "deep_water",
	"O": "sand", "d": "sand", "u": "sand"}
## KNOB (#44): when the whirlpool off Stormreef Isle carries you to the island. Blank = always, until the
## in-game clock (night) and rain exist -- then e.g. "is_night() and weather('rain')".
const TIDES_WHIRLPOOL_IF := ""
const TIDES_ISLAND := [
	"~~~~~~~~~~~~~~~~~~",
	"~~~~~~#######~~~~~",
	"~~~~~##O....##~~~~",
	"~~~~##.......##~~~",
	"~~~##sssssssss#~~~",
	"~~~#sssssssssss~~~",
	"~~~ssssssssssss~~~",
	"~~~~ssssssssss~~~~",
	"~~~~~ssssssss~~~~~",
	"~~~~~~ssssss~~~~~~",
	"~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~",
]
const TIDES_CAVE_1 := [
	"####################",
	"#ss..##~~~~##..ss..#",
	"#ss..#~~~~~~#..ss..#",
	"#....#~~W~~~#......#",
	"#....##~~~~##..##..#",
	"#..............##..#",
	"###...........######",
	"#d#...##..##.......#",
	"#.#...#....#....ss.#",
	"#.....#....#....ss.#",
	"#.....##..##.......#",
	"#..ss..........##..#",
	"#..ss...........#..#",
	"#######......#######",
	"#########..#########",
	"#########..#########",
]
const TIDES_CAVE_2 := [
	"####################",
	"####......~~~~~....#",
	"####.ss..~~~~~~~...#",
	"####.ss.~~~W~~~~~..#",
	"####.....~~~~~~....#",
	"####......~~~~.....#",
	"#....##..........###",
	"#.ss.##...ss.....#d#",
	"#.ss......ss.....#.#",
	"#.....##.........#.#",
	"#...~~~~~.....##...#",
	"#..~~~~~~~....##...#",
	"#..~~~~~~~.........#",
	"#...~~~~~.....ss...#",
	"#..............s...#",
	"####################",
]
const TIDES_CAVE_3 := [
	"####################",
	"#..ss.....##.....ss#",
	"#..ss.~~~~##~~~..ss#",
	"#....~~~~~~~~~~~...#",
	"#...~~~~~~~~~~~~~..#",
	"#...~~~~W~~~~~~~~..#",
	"#....~~~~~~~~~~~...#",
	"#.....~~~~##~~~....#",
	"###.......##.....###",
	"#d#..ss........ss..#",
	"#.#..ss..##....ss..#",
	"#........##........#",
	"#....##.......##...#",
	"#....##.......##.u.#",
	"#..................#",
	"####################",
]
## Where cave 1's west hole drops you: a sealed hollow whose only way out is back UP (a backtrack).
const TIDES_POCKET := [
	"############",
	"#u....ss...#",
	"#.....ss...#",
	"#..........#",
	"#....##....#",
	"#..........#",
	"############",
]
const TIDES_DEPTHS := [
	"##################",
	"######......######",
	"#####........#####",
	"####..~~~~~~..####",
	"###..~~~~~~~~..###",
	"###..~~~~~~~~..###",
	"####..~~~~~~..####",
	"#####........#####",
	"######......######",
	"#######....#######",
	"########..########",
	"##################",
]
const F_TIDES_BEATEN := "tides.legend_beaten"
const F_TIDES_BONDED := "legend.tides.bonded"
const TIDES_BATTLE_ID := "tides.legend"
const TIDES_MAP_PATH := CONTENT + "battles/ow_tides_depths.tres"
## The legend's two screens on its board (inside the open-ocean band).
const LV_TIDES_SCREEN := 19
## PLACEHOLDER legend unit (a distinct battle-ready stand-in until the sea legend is designed).
const TIDES_LEGEND_UNIT := "vineweave"
const TIDES_UP_TOAST := "The hole leads back up -- you climb out where you started."  # TODO(story)
const TIDES_DOWN_TOAST := "The whirlpool drags you down into the dark..."  # TODO(story)


func _whirlpool(id: String, c: Vector2i, target: String, entry: String, toast: String, visible_if: String = "") -> Array:
	var w := _warp(id, Rect2i(c.x, c.y, 1, 1), StringName(target), StringName(entry), visible_if)
	w.arrival_toast = toast
	return [_prop(id + "_swirl", "whirlpool", c, Vector2i.ONE, Color(0.7, 0.9, 1.0), false, visible_if), w]


func _build_island_of_tides() -> void:
	var band: Vector2i = REGION_BANDS["open_ocean"]
	var sea := _wild_zone(["tall_grass"], [["mycothrall", 2.0], ["blightcap", 1.5], ["vineweave", 1.0]])
	# The island: arrive riding by the whirlpool, the cave mouth in the north, the sea back to Stormreef.
	var isl: Array = []
	isl.append(_warp("cave_mouth", Rect2i(7, 2, 1, 1), &"tides_cave_1", &"south"))
	# Back out on the open sea: the calm water, or (in the post-game) the water with the volcano in it.
	isl.append(_warp("back_to_sea", Rect2i(0, 13, 18, 1), &"stormreef_waters", &"east", "not (%s)" % POSTGAME))
	isl.append(_warp("back_to_sea_erupted", Rect2i(0, 13, 18, 1), &"stormreef_waters_erupted", &"east", POSTGAME))
	_dungeon_floor("island_of_tides", "Island of Tides", "island_of_tides", TIDES_ISLAND, TIDES_TILES, "deep_water",
		"Dusk", "Default", band, {"whirlpool": [Vector2i(9, 11), "north"], "cave": [Vector2i(8, 3), "south"]}, isl, [sea])
	# Cave 1: the whirlpool in the lake goes down; the hole in the west goes down into a pocket whose only
	# way out is back up (a backtrack).
	var c1: Array = []
	c1.append(_warp("south_exit", Rect2i(9, 15, 2, 1), &"island_of_tides", &"cave"))
	c1.append_array(_whirlpool("whirl_down", Vector2i(8, 3), "tides_cave_2", "whirl", TIDES_DOWN_TOAST))
	c1.append_array(_hole("hole_down", Vector2i(1, 7), "tides_pocket", "drop"))
	_dungeon_floor("tides_cave_1", "Cave of Tides", "island_of_tides", TIDES_CAVE_1, TIDES_TILES, "basalt_column",
		"Dusk", "Default", band, {"south": [Vector2i(9, 14), "north"], "back_up": [Vector2i(1, 9), "east"]}, c1, [sea])
	# The hollow under cave 1's west hole: its only way out is back up.
	var pocket: Array = []
	pocket.append_array(_hole("hole_up", Vector2i(1, 1), "tides_cave_1", "back_up", TIDES_UP_TOAST))
	_dungeon_floor("tides_pocket", "Cave of Tides", "island_of_tides", TIDES_POCKET, TIDES_TILES, "basalt_column",
		"Dusk", "Default", band, {"drop": [Vector2i(3, 3), "north"]}, pocket, [sea])
	# Cave 2: the lake's whirlpool and the east hole both go down.
	var c2: Array = []
	c2.append_array(_whirlpool("whirl_down", Vector2i(11, 3), "tides_cave_3", "whirl", TIDES_DOWN_TOAST))
	c2.append_array(_hole("hole_down", Vector2i(18, 7), "tides_cave_3", "east"))
	_dungeon_floor("tides_cave_2", "Cave of Tides", "island_of_tides", TIDES_CAVE_2, TIDES_TILES, "basalt_column",
		"Dusk", "Default", band, {"whirl": [Vector2i(12, 3), "south"],
			"back_up": [Vector2i(18, 9), "south"]}, c2, [sea])
	# Cave 3: the lake's whirlpool goes down to the depths; the holes lead back UP (east to cave 2, west
	# all the way to cave 1).
	var c3: Array = []
	c3.append_array(_whirlpool("whirl_down", Vector2i(8, 5), "tides_depths", "whirl", TIDES_DOWN_TOAST))
	c3.append_array(_hole("hole_up_east", Vector2i(17, 13), "tides_cave_2", "back_up", TIDES_UP_TOAST))
	c3.append_array(_hole("hole_up_west", Vector2i(1, 9), "tides_cave_1", "south", TIDES_UP_TOAST))
	_dungeon_floor("tides_cave_3", "Cave of Tides", "island_of_tides", TIDES_CAVE_3, TIDES_TILES, "basalt_column",
		"Dusk", "Default", band, {"whirl": [Vector2i(9, 5), "south"], "east": [Vector2i(16, 12), "north"]}, c3, [sea])
	# The depths: the legend over its lake; a hole back up to cave 3.
	var dp: Array = []
	dp.append_array(_hole("hole_up", Vector2i(9, 9), "tides_cave_3", "east", TIDES_UP_TOAST))
	dp.append(_postgame_legend("tides_legend", Vector2i(8, 1), TIDES_LEGEND_UNIT,
		_tides_spec(), F_TIDES_BEATEN, F_TIDES_BONDED,
		"The water of the deep lake rises and turns, and something old rises with it. Face it?"))  # TODO(story)
	_dungeon_floor("tides_depths", "Depths of the Tides", "island_of_tides", TIDES_DEPTHS, TIDES_TILES, "basalt_column",
		"Night", "Default", band, {"whirl": [Vector2i(8, 10), "north"]}, dp)


## THE ISLAND OF TIDES' LEGEND (#44 / #74): TACTICAL, FIXED above the open-ocean band (#81).
func _tides_spec() -> BattleSpec:
	var spec := _postgame_legend_spec(TIDES_BATTLE_ID, TIDES_MAP_PATH, TIDES_LEGEND_UNIT, F_TIDES_BEATEN)
	BattleSpec.make_legend(spec, REGION_BANDS["open_ocean"])
	return spec


func _build_tides_map() -> void:
	_postgame_legend_map(TIDES_MAP_PATH, "The Depths of the Tides",
		"The cave lake at the bottom of the Island of Tides.", "Night", "Default",
		TIDES_LEGEND_UNIT, "mycothrall", LV_TIDES_SCREEN, func(x: int, y: int) -> String:
			var c := Vector2i(x, y)
			if c in [Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 9), Vector2i(11, 9)]:
				return "basalt_column"
			if (x <= 1 or x >= 10) and y >= 3 and y <= 6:
				return "deep_water"
			return "sand")
