extends RefCounted
class_name ItemInventory

## The player's PERSISTENT item collection and loadout: what they own, which character wears
## which UNIT item, and what sits in the two shared TEAM slots.
##
## STATIC BY DESIGN, NOT AN AUTOLOAD. A GDScript class's static vars live for the whole
## process, exactly like an autoload's fields -- but without a project.godot entry, without a
## node in the tree, and without an initialisation order to reason about. Every caller here
## (a menu, the battle-side [ItemSystem], the Arena results flow) only ever needs pure
## reads/writes over one small Dictionary, so a node would have bought nothing.
##
## Persistence is EXPLICIT: the store lazy-loads from [constant DEFAULT_SAVE_PATH] the first
## time anything is read, and is written only when [method save] is called. Mutators
## deliberately do NOT auto-save, so a screen can stage several changes (equip, swap, fill a
## team slot) and commit them in one write -- and so a test can mutate freely without
## touching the real save file (see [method set_save_path]).
##
## EQUIPPING MOVES AN ITEM. You own COPIES, not slots: if every copy of an item is already
## in use, equipping it somewhere new TAKES IT from wherever it was. The UI says so out loud;
## [method equip] and [method set_team_item] return the place it was taken from so the caller
## can tell the player.
##
## Save schema (user://items.json), a straight JSON round-trip:
##   {
##     "owned":     { "<item_id>": <count:int>, ... },
##     "equipped":  { "<character_id>": "<item_id>", ... },   # UNIT-scope items
##     "team":      ["<item_id>", ""]                          # TEAM_SLOTS entries, "" = empty
##   }

const DEFAULT_SAVE_PATH: String = "user://items.json"

## How many shared TEAM item slots the player has. Two is deliberate: enough for a real
## build decision, few enough that the chip row stays readable on a phone.
const TEAM_SLOTS: int = 2

static var _save_path: String = DEFAULT_SAVE_PATH
static var _data: Dictionary = {}
static var _loaded: bool = false


# --- Store lifecycle --------------------------------------------------------

## Load the store from disk if it has not been read yet. Every accessor calls this, so no
## caller ever has to remember to.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data = _blank()
	if not FileAccess.file_exists(_save_path):
		return
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = _normalize(parsed)


## Write the store to disk. Returns false when the file could not be opened (a full disk or a
## read-only user dir must not crash a battle). Call once after a batch of mutations.
static func save() -> bool:
	ensure_loaded()
	var dir: String = _save_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		push_warning("ItemInventory.save: could not open '%s' for writing." % _save_path)
		return false
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	return true


## Point the store at a different file and drop the cache, so the next read loads from there.
## Exists for TESTS (a temp user:// path) and for any future profile-scoped save; normal play
## never calls it.
static func set_save_path(path: String) -> void:
	_save_path = path if not path.strip_edges().is_empty() else DEFAULT_SAVE_PATH
	_loaded = false
	_data = {}


## The file the store currently reads/writes.
static func save_path() -> String:
	return _save_path


## Wipe the in-memory store WITHOUT touching disk, and mark it loaded so nothing re-reads the
## file underneath. For tests and for a "start over" flow.
static func reset() -> void:
	_data = _blank()
	_loaded = true


# --- Ownership --------------------------------------------------------------

## Add [param count] copies of [param item_id] to the collection. Unknown ids are accepted
## (an item can be removed from content and re-added later; dropping the record silently
## would lose the player's stuff), but a non-positive count is a no-op.
static func grant(item_id, count: int = 1) -> void:
	if count <= 0:
		return
	var key: String = String(item_id)
	if key.is_empty():
		return
	ensure_loaded()
	var owned: Dictionary = _data["owned"]
	owned[key] = int(owned.get(key, 0)) + count


## How many copies of [param item_id] the player owns (0 when none).
static func owned_count(item_id) -> int:
	ensure_loaded()
	return int((_data["owned"] as Dictionary).get(String(item_id), 0))


## Every owned item id with at least one copy, sorted for stable UI ordering.
static func owned_ids() -> Array[String]:
	ensure_loaded()
	var ids: Array[String] = []
	for key in (_data["owned"] as Dictionary).keys():
		if int(_data["owned"][key]) > 0:
			ids.append(String(key))
	ids.sort()
	return ids


## Total copies across every item -- the "N items collected" headline number.
static func total_owned() -> int:
	ensure_loaded()
	var total: int = 0
	for key in (_data["owned"] as Dictionary).keys():
		total += maxi(0, int(_data["owned"][key]))
	return total


## Owned items resolved to live [ItemResource]s, filtered to [param scope]
## ([constant ItemResource.Scope.UNIT] / [code]TEAM[/code]), in library display order. Ids
## that no longer resolve are skipped -- this is the list a picker shows.
static func owned_items_with_scope(scope: int) -> Array[ItemResource]:
	var out: Array[ItemResource] = []
	for item in ItemLibrary.items_with_scope(scope):
		if owned_count(item.id) > 0:
			out.append(item)
	return out


## Copies of [param item_id] NOT currently equipped anywhere (characters + team slots).
## Negative is impossible by construction; clamped at 0 for safety.
static func free_copies(item_id) -> int:
	var key: String = String(item_id)
	if key.is_empty():
		return 0
	return maxi(0, owned_count(key) - _used_copies(key))


# --- Per-character (UNIT scope) equipment -----------------------------------

## The UNIT item [param character_id] currently wears, or "" when none.
static func equipped_item(character_id) -> String:
	ensure_loaded()
	return String((_data["equipped"] as Dictionary).get(String(character_id), ""))


## The resolved [ItemResource] on [param character_id] (null when empty or unresolvable).
static func equipped_resource(character_id) -> ItemResource:
	return ItemLibrary.get_item(equipped_item(character_id))


## Equip [param item_id] to [param character_id].
##
## Returns where the item was TAKEN FROM -- a character id, or the display-ready
## "team slot N" -- and "" when no move was needed. When at least one free copy exists nothing
## is disturbed; when every copy is in use the item is pulled off its current holder (another
## character first, then a team slot). [method set_team_item] is the mirror image. Passing an
## empty item_id is the same as [method unequip]. Does not save; the caller decides when to
## commit.
static func equip(character_id, item_id) -> String:
	var character_key: String = String(character_id)
	if character_key.is_empty():
		return ""
	var item_key: String = String(item_id)
	if item_key.is_empty():
		unequip(character_key)
		return ""

	ensure_loaded()
	if owned_count(item_key) <= 0:
		# Expected refusal (UI offers only owned items, but races/imports can desync):
		# report through the return value, never the engine log.
		return ""

	var equipped: Dictionary = _data["equipped"]
	# Already wearing it: nothing to do (and nothing to steal from ourselves).
	if String(equipped.get(character_key, "")) == item_key:
		return ""

	var taken_from: String = ""
	if free_copies(item_key) <= 0:
		# Every copy is in use, so this equip is a MOVE. Prefer taking it off another
		# character (deterministic: the first in sorted id order) and fall back to freeing a
		# team slot, so the player never ends up unable to equip something they own.
		taken_from = _take_from_character(item_key, character_key)
		if taken_from.is_empty():
			var freed_slot: int = _take_from_team(item_key)
			if freed_slot >= 0:
				# Same 1-based, display-ready wording set_team_item uses, so the UI can print
				# whichever source it gets back without a special case.
				taken_from = "team slot %d" % (freed_slot + 1)

	equipped[character_key] = item_key
	return taken_from


## Remove whatever UNIT item [param character_id] is wearing.
static func unequip(character_id) -> void:
	ensure_loaded()
	(_data["equipped"] as Dictionary).erase(String(character_id))


## The first character wearing [param item_id], or "" when nobody is. Sorted-id order, so the
## answer is stable across runs.
static func holder_of(item_id) -> String:
	ensure_loaded()
	var item_key: String = String(item_id)
	var equipped: Dictionary = _data["equipped"]
	var characters: Array = equipped.keys()
	characters.sort()
	for character_key in characters:
		if String(equipped[character_key]) == item_key:
			return String(character_key)
	return ""


## A copy of the whole character -> item map (safe for UI to iterate and mutate).
static func equipped_map() -> Dictionary:
	ensure_loaded()
	return (_data["equipped"] as Dictionary).duplicate(true)


# --- Shared TEAM slots ------------------------------------------------------

## The [constant TEAM_SLOTS] team-slot contents, "" for an empty slot. Always exactly
## TEAM_SLOTS long, so the chip row can index it without bounds checks.
static func team_items() -> Array[String]:
	ensure_loaded()
	var raw: Array = _data["team"]
	var out: Array[String] = []
	for i in range(TEAM_SLOTS):
		out.append(String(raw[i]) if i < raw.size() else "")
	return out


## The resolved [ItemResource]s in the team slots, skipping empty/unresolvable slots. This is
## the list [ItemSystem] stamps onto EVERY player unit.
static func team_resources() -> Array[ItemResource]:
	var out: Array[ItemResource] = []
	for item_id in team_items():
		var item: ItemResource = ItemLibrary.get_item(item_id)
		if item != null:
			out.append(item)
	return out


## Put [param item_id] into team slot [param slot] (0-based).
##
## Returns a short note describing where the item was taken from ("" when nothing was moved),
## using the same "you own copies, not slots" rule as [method equip]: with no free copy left
## the item is pulled off a character or out of the other team slot. An empty item_id clears
## the slot. Does not save.
static func set_team_item(slot: int, item_id) -> String:
	if slot < 0 or slot >= TEAM_SLOTS:
		return ""
	ensure_loaded()
	var item_key: String = String(item_id)
	var team: Array = _data["team"]

	if item_key.is_empty():
		team[slot] = ""
		return ""
	if owned_count(item_key) <= 0:
		# Expected refusal - return-value reporting only (see equip()).
		return ""
	if String(team[slot]) == item_key:
		return ""

	var note: String = ""
	if free_copies(item_key) <= 0:
		# Free the other slot first (a straight in-row swap reads most naturally), then fall
		# back to taking it off a character.
		var freed_slot: int = _take_from_team(item_key, slot)
		if freed_slot >= 0:
			note = "team slot %d" % (freed_slot + 1)
		else:
			var character_key: String = _take_from_character(item_key, "")
			if not character_key.is_empty():
				note = character_key

	team[slot] = item_key
	return note


## Empty team slot [param slot].
static func clear_team_item(slot: int) -> void:
	set_team_item(slot, "")


# --- internals --------------------------------------------------------------

## Total copies of [param item_id] currently spoken for: worn by a character plus sitting in
## a team slot. This is what [method free_copies] subtracts from ownership.
static func _used_copies(item_id: String) -> int:
	ensure_loaded()
	var used: int = 0
	for character_key in (_data["equipped"] as Dictionary).keys():
		if String(_data["equipped"][character_key]) == item_id:
			used += 1
	for slot_value in (_data["team"] as Array):
		if String(slot_value) == item_id:
			used += 1
	return used


## Strip [param item_id] off the first character wearing it (excluding [param except]) and
## return that character's id, or "" when nobody else had it.
static func _take_from_character(item_id: String, except: String) -> String:
	var equipped: Dictionary = _data["equipped"]
	var characters: Array = equipped.keys()
	characters.sort()
	for character_key in characters:
		var key_str: String = String(character_key)
		if key_str == except:
			continue
		if String(equipped[key_str]) == item_id:
			equipped.erase(key_str)
			return key_str
	return ""


## Clear the first team slot holding [param item_id] (excluding [param except_slot]) and
## return its index, or -1 when no slot had it.
static func _take_from_team(item_id: String, except_slot: int = -1) -> int:
	var team: Array = _data["team"]
	for i in range(team.size()):
		if i == except_slot:
			continue
		if String(team[i]) == item_id:
			team[i] = ""
			return i
	return -1


static func _blank() -> Dictionary:
	var team: Array = []
	for _i in range(TEAM_SLOTS):
		team.append("")
	return { "owned": {}, "equipped": {}, "team": team }


## Coerce a parsed save into the exact shape the accessors assume: the three sections always
## present, counts as ints, the team array exactly TEAM_SLOTS long. A save written by an older
## build (or a hand-edited one) is repaired rather than rejected, because the alternative is
## silently losing a player's collection.
static func _normalize(raw: Dictionary) -> Dictionary:
	var out: Dictionary = _blank()

	var owned_raw: Variant = raw.get("owned", {})
	if owned_raw is Dictionary:
		for key in (owned_raw as Dictionary).keys():
			var count: int = int(owned_raw[key])
			if count > 0:
				out["owned"][String(key)] = count

	var equipped_raw: Variant = raw.get("equipped", {})
	if equipped_raw is Dictionary:
		for key in (equipped_raw as Dictionary).keys():
			var value: String = String(equipped_raw[key])
			if not value.is_empty():
				out["equipped"][String(key)] = value

	var team_raw: Variant = raw.get("team", [])
	if team_raw is Array:
		for i in range(mini(TEAM_SLOTS, (team_raw as Array).size())):
			out["team"][i] = String(team_raw[i])

	return out
