class_name CampaignData
extends RefCounted

## Static definition of the Conquest story campaign: an ORDERED list of chapters that
## walk the player from the blighted forest edge to Eldroot, the corrupted heartwood,
## at the centre of the Forgotten Forest. Each chapter is a plain Dictionary so it can
## be read from the controller, the screen and the tests without a bespoke resource:
##
##   id            String  stable key used for progress persistence (never reorder-fragile)
##   number        int     1-based chapter number shown on the card
##   title         String  chapter name
##   blurb         String  1-2 sentences of light forest-corruption story
##   map_path      String  res:// MapResource the battle is fought on
##   ai_difficulty int     BotController.Difficulty (EASY 0 .. BRUTAL 3) -- the ramp
##   squad_size    int     how many units the player may field (Character Select cap)
##   intro_scene   String  OPTIONAL res:// StoryScene played over the loaded battle map,
##                         at boot, before the first turn (see CampaignController)
##   outro_scene   String  OPTIONAL res:// StoryScene played after a VICTORY, before the
##                         results card (a loss never plays it -- see CampaignController)
##
## The two story keys are OPTIONAL and ABSENT by default: a chapter without them plays
## exactly as it did before this system existed. Only chapter 1 is scripted today; the rest
## are deliberately left bare rather than given placeholder scripts.
##
## UNLOCK RULE (enforced by CampaignController, not stored here): chapter 0 is always
## unlocked; every later chapter unlocks once the PREVIOUS chapter is cleared. Keeping
## the rule out of the data keeps this file a pure, declarative table.
##
## The difficulty climbs Easy -> Normal -> Hard -> Brutal, and the maps grow with it
## (a small 8x8 clearing, then two mid/large skirmish maps, then the 20x20 boss arena).
## NOTE: Proving Grounds fields mycothrall, which only spawns at Hard+, so chapter 3 is
## pinned to Hard so its full enemy roster appears.


## The ordered chapter table. Returns a FRESH array on every call (callers may sort /
## annotate their own copy without mutating the shared definition).
static func chapters() -> Array:
	return [
		{
			"id": "ch1_blighted_clearing",
			"number": 1,
			"title": "The Blighted Clearing",
			"blurb": "The blight has crept to the forest's edge. Cull the first corrupted creatures before the rot spreads to the village beyond.",
			"map_path": "res://game/maps/resources/campaign_blighted_clearing.tres",
			"ai_difficulty": 0,
			"squad_size": 3,
			"intro_scene": "res://game/campaign/story/ch1_blighted_clearing_intro.tres",
			"outro_scene": "res://game/campaign/story/ch1_blighted_clearing_outro.tres",
		},
		{
			"id": "ch2_elemental_crossroads",
			"number": 2,
			"title": "The Tainted Crossroads",
			"blurb": "Where the old ley-lines cross, the corruption festers strongest. Break the blighted warband holding the elemental crossroads.",
			"map_path": "res://game/maps/resources/elemental_crossroads.tres",
			"ai_difficulty": 1,
			"squad_size": 3,
		},
		{
			"id": "ch3_proving_grounds",
			"number": 3,
			"title": "The Proving Grounds",
			"blurb": "Deeper in, the forest tests every intruder. Cut through the swarm of blight-spawn guarding the path to the heartwood.",
			"map_path": "res://game/maps/resources/proving_grounds.tres",
			"ai_difficulty": 2,
			"squad_size": 4,
		},
		{
			"id": "ch4_forgotten_forest",
			"number": 4,
			"title": "Heart of the Forgotten Forest",
			"blurb": "At the forest's rotten heart waits Eldroot, the corrupted heartwood. Fell the ancient and end the blight for good.",
			"map_path": "res://game/maps/resources/forgotten_forest.tres",
			"ai_difficulty": 3,
			"squad_size": 4,
		},
	]


## Number of chapters in the campaign.
static func count() -> int:
	return chapters().size()


## The chapter Dictionary at [param index], or {} when out of range.
static func get_chapter(index: int) -> Dictionary:
	var list: Array = chapters()
	if index < 0 or index >= list.size():
		return {}
	return list[index]


## The chapter with [param id], or {} when no chapter carries that id.
static func get_by_id(id: String) -> Dictionary:
	for c in chapters():
		if String(c.get("id", "")) == id:
			return c
	return {}


## Ordinal position of the chapter with [param id], or -1 when unknown.
static func index_of_id(id: String) -> int:
	var list: Array = chapters()
	for i in range(list.size()):
		if String(list[i].get("id", "")) == id:
			return i
	return -1


## The id of the chapter AFTER [param id] in play order, or "" when [param id] is the
## last chapter (or unknown). Used to unlock the next chapter on a clear.
static func next_id(id: String) -> String:
	var idx: int = index_of_id(id)
	if idx < 0 or idx + 1 >= count():
		return ""
	return String(get_chapter(idx + 1).get("id", ""))
