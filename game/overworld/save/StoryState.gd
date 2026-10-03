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

## Difficulty tiers, HARDEST FIRST: a journey may only move to a later entry (DECISIONS.md #29).
const TIER_CLASSIC := "classic"
const TIER_CASUAL := "casual"
const TIERS: Array[String] = [TIER_CLASSIC, TIER_CASUAL]

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
## Per-merchant stock bookkeeping ([ShopLedger]): shop_id -> {"sold": {item_id: n}, "epoch": int}.
## Saved as "shops" (an older save loads it empty: every merchant fully stocked).
var shops: Dictionary = {}
## Rests taken (Wayshrine / healer / whiteout heals): the clock an ON_REST restock reads. Saved.
var rests: int = 0
## The journey's DIFFICULTY TIER (docs/design/DECISIONS.md #29 + "Permadeath refinements"),
## chosen when the journey starts: [constant TIER_CLASSIC] (permadeath) or [constant TIER_CASUAL]
## (knocked-out members recover for gold). It may only move DOWN [constant TIERS]
## ([method lower_tier]), never back up. Saved as "tier"; a save from before tiers existed loads
## as Casual (it was played without permadeath).
var tier: String = TIER_CASUAL
## FALLEN members (Classic): out of the party for good, kept as records in the order they fell
## ([StoryPartyMember.fallen_info] says where / when). Everything that reads [member party] --
## squads, duels, healing, revives, evolution, the party cap -- never sees them. Saved as "fallen".
var fallen: Array[StoryPartyMember] = []
## What changed since the last [method drain_changes] -- the EVOLUTION auto-offer events
## (StoryController: a flag set / a member joining may have met a requirement). Never saved.
var _changed_flags: Array[String] = []
var _party_changed: bool = false


# --- Flags --------------------------------------------------------------------

func set_flag(key: String, value = true) -> void:
	if key.strip_edges().is_empty():
		return
	var v = _normalize_flag_value(value)
	if not flags.has(key) or typeof(flags[key]) != typeof(v) or flags[key] != v:
		_note_flag(key)
	flags[key] = v


func clear_flag(key: String) -> void:
	if flags.has(key):
		_note_flag(key)
	flags.erase(key)


func _note_flag(key: String) -> void:
	if not _changed_flags.has(key):
		_changed_flags.append(key)


## The changes since the last call, then forgets them: {flags: Array[String] (keys set / changed /
## cleared, in order), party: bool (a member joined)}.
func drain_changes() -> Dictionary:
	var out: Dictionary = {"flags": _changed_flags.duplicate(), "party": _party_changed}
	_changed_flags.clear()
	_party_changed = false
	return out


## True when something changed since the last [method drain_changes].
func has_changes() -> bool:
	return _party_changed or not _changed_flags.is_empty()


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
	# The RosterLedger uid scheme keys an individual by its LINE ("tree_grunt", "tree_grunt#2"),
	# so a recruit that joins as an evolved form still belongs to its line. A FALLEN member's uid
	# stays taken: its record is kept, and a new recruit must never inherit it.
	var taken: Array = member_ids()
	for f in fallen:
		taken.append(f.member_id)
	var uid: String = StoryPartyMember.uid_for(StoryPartyMember.line_of(character_id), taken)
	var m := StoryPartyMember.create(uid, character_id, nickname)
	party.append(m)
	_party_changed = true
	return m


## Members that may be fielded, in party order.
func healthy_members() -> Array[StoryPartyMember]:
	var out: Array[StoryPartyMember] = []
	for m in party:
		if m.is_fieldable():
			out.append(m)
	return out


## A full rest (a Wayshrine, a healer, waking after a whiteout): every member healed and the rest
## counter advanced (merchants that restock ON_REST read it). With [param revive_knocked_out]
## false (a Casual rest: knocked-out members recover for GOLD, [StoryPermadeath.revive_quote]) a
## knocked-out member stays down and only the living are healed. The FALLEN are never touched
## (they are not in [member party]).
func heal_party(revive_knocked_out: bool = true) -> void:
	for m in party:
		if not revive_knocked_out and ConsumableEffect.member_is_down(m):
			continue
		m.heal_full()
	rests += 1


## Party members knocked out (wounded / 0 HP) and not fallen -- what a revive is for.
func knocked_out_members() -> Array[StoryPartyMember]:
	var out: Array[StoryPartyMember] = []
	for m in party:
		if ConsumableEffect.member_is_down(m):
			out.append(m)
	return out


# --- Fallen (Classic permadeath) ------------------------------------------------------

## The fallen record of [param member_id] (null when it never fell).
func fallen_member(member_id: String) -> StoryPartyMember:
	for m in fallen:
		if m.member_id == member_id:
			return m
	return null


## Mark party member [param member_id] FALLEN with [param info] (where / when): it leaves
## [member party] for [member fallen], keeps its form, growth and nickname, and its equipped item
## goes back into the bag (the record remembers which: info.item_id). Returns the record, or null
## when there is no such party member.
func mark_fallen(member_id: String, info: Dictionary) -> StoryPartyMember:
	var m: StoryPartyMember = member(member_id)
	if m == null:
		return null
	var rec: Dictionary = StoryPartyMember.sanitize_fallen(info)
	if rec.is_empty():
		rec = StoryPartyMember.sanitize_fallen({"kind": "battle"})
	if not m.item_id.is_empty():
		add_item(m.item_id)
		rec["item_id"] = m.item_id
		m.item_id = ""
	m.fallen_info = rec
	m.wounded = true
	m.current_hp = 0
	party.erase(m)
	fallen.append(m)
	_party_changed = true
	return m


# --- Difficulty tier ---------------------------------------------------------------------

static func is_tier(t: String) -> bool:
	return TIERS.has(t)


func is_classic() -> bool:
	return tier == TIER_CLASSIC


## True when the journey may move from its tier to [param to] -- only DOWN (easier), never up.
func can_lower_tier_to(to: String) -> bool:
	return is_tier(to) and TIERS.find(to) > TIERS.find(tier)


## Move the journey DOWN to [param to] (Classic -> Casual). {ok, reason}; reasons "unknown_tier",
## "same_tier", "cannot_raise" (a journey never moves back up). Fallen members stay fallen.
func lower_tier(to: String = TIER_CASUAL) -> Dictionary:
	if not is_tier(to):
		return {"ok": false, "reason": "unknown_tier"}
	if to == tier:
		return {"ok": false, "reason": "same_tier"}
	if not can_lower_tier_to(to):
		return {"ok": false, "reason": "cannot_raise"}
	tier = to
	return {"ok": true, "reason": ""}


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


## USE a consumable from the bag on [param member_id] OUT OF BATTLE (Journey -> Bag): the rules are
## [method ConsumableEffect.check_member]; a use that helps spends ONE from the bag, a refused one
## spends nothing. {ok, reason, healed, revived, hp_before, hp_after}; reasons: "no_item",
## "not_consumable", "no_member", "fallen" or a [ConsumableEffect] refusal ("full_hp", ...).
func use_consumable(item_id: String, member_id: String) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "healed": 0, "revived": false, "hp_before": 0, "hp_after": 0}
	if item_count(item_id) <= 0:
		out["reason"] = "no_item"
		return out
	var item: ItemResource = ItemLibrary.get_item(item_id)
	if item == null or item.consumable == null:
		out["reason"] = "not_consumable"
		return out
	var m: StoryPartyMember = member(member_id)
	if m == null:
		# A FALLEN member is out of the party: nothing -- not even a revive -- brings it back.
		out["reason"] = "fallen" if fallen_member(member_id) != null else "no_member"
		return out
	var r: Dictionary = item.consumable.apply_to_member(m)
	if bool(r.get("ok", false)):
		take_item(item_id, 1)
	return r


## EQUIP a unit-scope equipment item from the bag onto [param member_id]; whatever it wore goes back
## into the bag. {ok, reason, swapped}; reasons: "no_member", "no_item", "not_equipment", "team_item"
## (shared team slots are not a per-member choice), "already".
func equip_item(member_id: String, item_id: String) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "swapped": ""}
	var m: StoryPartyMember = member(member_id)
	if m == null:
		out["reason"] = "no_member"
		return out
	var item: ItemResource = ItemLibrary.get_item(item_id)
	if item == null or item_count(item_id) <= 0:
		out["reason"] = "no_item"
		return out
	if not item.is_equipment():
		out["reason"] = "not_equipment"
		return out
	if item.is_team_item():
		out["reason"] = "team_item"
		return out
	if m.item_id == item_id:
		out["reason"] = "already"
		return out
	take_item(item_id, 1)
	if not m.item_id.is_empty():
		out["swapped"] = m.item_id
		add_item(m.item_id, 1)
	m.item_id = item_id
	out["ok"] = true
	return out


## Take the equipped item off [param member_id] and into the bag. False when nothing was worn.
func unequip_item(member_id: String) -> bool:
	var m: StoryPartyMember = member(member_id)
	if m == null or m.item_id.is_empty():
		return false
	add_item(m.item_id, 1)
	m.item_id = ""
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
