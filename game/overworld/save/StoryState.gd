class_name StoryState
extends RefCounted

## THE LIVE STORY SESSION -- everything a story save persists, and the one place gameplay
## state changes. Pure data + small helpers: no nodes, no disk (see [StorySnapshot] for the
## serializer and [StorySaveManager] for the slots), so every rule here is unit-testable.
##
## FLAGS are the story's single state engine: quests, opened chests, defeated trainers,
## moved guards are all flags (docs/design/OVERWORLD.md §4.2). A flag value is a bool or an
## int; [method has_flag] is the truthiness test conditions use, [method get_flag_int] the
## numeric one ("quest.blight_road >= 1").

## Facing names used by saves, entities and scripts (UnitFacing convention: +Z = south).
const FACING_NAMES: Array[String] = ["south", "north", "east", "west"]

var flags: Dictionary = {}
## Ordered: index 0 is the party LEAD (the member a duel sends first). The overworld avatar is
## the HERO (see [HeroResource]), never a party member.
var party: Array[StoryPartyMember] = []
## item_id -> count (the story bag; item DEFINITIONS are ItemLibrary's).
var bag: Dictionary = {}
var gold: int = 0
## Where the player stands: {area_id, cell: Vector3i, facing}.
var location: Dictionary = {"area_id": "", "cell": Vector3i.ZERO, "facing": "south"}
## Where a whiteout sends you: {area_id, entry}.
var respawn: Dictionary = {"area_id": "", "entry": ""}
var visited_areas: Array[String] = []
var lit_wayshrines: Array[String] = []
## Deterministic encounter stream: a per-journey seed and the step counter it is read at
## (EncounterRoller -- never randf()).
var rng_seed: int = 0
var steps: int = 0
## Steps left before the next encounter roll may fire (after a battle / area entry).
var grace_steps: int = 0
## Moved actors that PERSIST ("oakvale.guard" -> {cell, facing}); saved.
var actor_positions: Dictionary = {}
## Moved actors that do NOT persist (a trainer who walked up to you). Survive a battle round
## trip, cleared when the player changes area. Never saved.
var transient_positions: Dictionary = {}
var play_seconds: float = 0.0


# --- Flags --------------------------------------------------------------------

func set_flag(key: String, value = true) -> void:
	if key.strip_edges().is_empty():
		return
	flags[key] = _normalize_flag_value(value)


func clear_flag(key: String) -> void:
	flags.erase(key)


## The raw value, or [param default] when unset.
func get_flag(key: String, default = 0):
	return flags.get(key, default)


## Numeric view: true -> 1, false/unset -> 0, ints as-is.
func get_flag_int(key: String) -> int:
	var v = flags.get(key, 0)
	if v is bool:
		return 1 if v else 0
	if v is int or v is float:
		return int(v)
	return 0


## Truthiness: a set flag that is true or non-zero.
func has_flag(key: String) -> bool:
	return get_flag_int(key) != 0


## Add [param by] to an int flag (unset counts as 0) and return the new value.
func inc_flag(key: String, by: int = 1) -> int:
	var v: int = get_flag_int(key) + by
	set_flag(key, v)
	return v


## JSON parses every number as a float -- fold integral floats back to int so a round trip
## is lossless (quest stages compare as ints).
static func _normalize_flag_value(value):
	if value is bool or value is int:
		return value
	if value is float:
		return int(value) if is_equal_approx(value, roundf(value)) else value
	if value is String or value is StringName:
		return String(value)
	return bool(value)


# --- Party -----------------------------------------------------------------------

func member_ids() -> Array:
	var out: Array = []
	for m in party:
		out.append(m.member_id)
	return out


func member(member_id: String) -> StoryPartyMember:
	for m in party:
		if m.member_id == member_id:
			return m
	return null


func lead() -> StoryPartyMember:
	return party[0] if not party.is_empty() else null


func party_has(character_id: String) -> bool:
	for m in party:
		if m.character_id == character_id or m.line == character_id:
			return true
	return false


## Add a new individual of [param character_id] and return it; null when the party is at
## [param cap] (the Grove storage is M2) or the id is blank.
func add_member(character_id: String, nickname: String = "", cap: int = 6) -> StoryPartyMember:
	if character_id.strip_edges().is_empty():
		return null
	if cap > 0 and party.size() >= cap:
		return null
	var uid: String = StoryPartyMember.uid_for(character_id, member_ids())
	var m := StoryPartyMember.create(uid, character_id, nickname)
	party.append(m)
	return m


## Members that may be fielded, in party order.
func healthy_members() -> Array[StoryPartyMember]:
	var out: Array[StoryPartyMember] = []
	for m in party:
		if m.is_fieldable():
			out.append(m)
	return out


func heal_party() -> void:
	for m in party:
		m.heal_full()


# --- Bag / gold ------------------------------------------------------------------

func item_count(item_id: String) -> int:
	return int(bag.get(item_id, 0))


func add_item(item_id: String, count: int = 1) -> void:
	if item_id.strip_edges().is_empty() or count <= 0:
		return
	bag[item_id] = item_count(item_id) + count


## Remove [param count]; false (bag unchanged) when there are not enough.
func take_item(item_id: String, count: int = 1) -> bool:
	if item_count(item_id) < count:
		return false
	var left: int = item_count(item_id) - count
	if left <= 0:
		bag.erase(item_id)
	else:
		bag[item_id] = left
	return true


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)


## Spend [param amount]; false (gold unchanged) when short.
func take_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	return true


# --- Location ----------------------------------------------------------------------

func set_location(area_id: String, cell: Vector3i, facing: String) -> void:
	location = {"area_id": area_id, "cell": cell, "facing": facing if FACING_NAMES.has(facing) else "south"}


func location_area() -> String:
	return String(location.get("area_id", ""))


func location_cell() -> Vector3i:
	var c = location.get("cell", Vector3i.ZERO)
	return c if c is Vector3i else Cells.from_variant(c)


func location_facing() -> String:
	return String(location.get("facing", "south"))


func mark_visited(area_id: String) -> void:
	if not area_id.is_empty() and not visited_areas.has(area_id):
		visited_areas.append(area_id)


func light_wayshrine(key: String) -> void:
	if not key.is_empty() and not lit_wayshrines.has(key):
		lit_wayshrines.append(key)


# --- Moved actors -------------------------------------------------------------------

static func actor_key(area_id: String, entity_id: String) -> String:
	return "%s.%s" % [area_id, entity_id]


## The position override for an entity, persisted first then transient; {} when it stands on
## its authored cell.
func actor_override(area_id: String, entity_id: String) -> Dictionary:
	var key: String = actor_key(area_id, entity_id)
	if transient_positions.has(key):
		return transient_positions[key]
	if actor_positions.has(key):
		return actor_positions[key]
	return {}


func set_actor_position(area_id: String, entity_id: String, cell: Vector3i, facing: String, persist: bool) -> void:
	var key: String = actor_key(area_id, entity_id)
	var rec: Dictionary = {"cell": cell, "facing": facing}
	if persist:
		actor_positions[key] = rec
		transient_positions.erase(key)
	else:
		transient_positions[key] = rec


## Entering a different area forgets every non-persistent move (a trainer walks back to his
## post once you leave and come back).
func on_area_changed() -> void:
	transient_positions.clear()


# --- Views -------------------------------------------------------------------------

## The flags view EVOLUTION's StoryFlagTrigger reads (extra_ctx["story_flags"]).
func story_flags() -> Dictionary:
	return flags.duplicate(true)
