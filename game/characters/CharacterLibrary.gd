extends RefCounted

class_name CharacterLibrary

## Central lookup for the character roster.
##
## Loads CharacterResource .tres files from res://game/characters/roster/ on
## demand and caches them by character_id so repeated spawns (and repeated
## map loads) don't re-hit disk. Callers should treat the returned
## CharacterResource as shared/read-only - it is cached and reused across
## every unit spawned with the same id.

const ROSTER_DIR: String = "res://game/characters/roster/"

## Ids known to ship with the roster. Used as a fallback for [method all_ids]
## if the roster directory can't be scanned (e.g. exported PCK quirks), and
## as documentation of what's expected to exist.
const KNOWN_IDS: Array[StringName] = [
	&"vineweave",
	&"blightcap",
	&"petalfang",
	&"tree_grunt",
	&"mycothrall",
	&"eldroot",
]

## id (StringName) -> CharacterResource. Shared across all callers for the
## lifetime of the process.
static var _cache: Dictionary = {}

## Ids already reported as unresolvable by [method get_character], so a legacy id that is
## probed on every single spawn is mentioned once per process instead of once per unit.
static var _reported_misses: Dictionary = {}


## Loads (and caches) the CharacterResource for [param id]. [param id] may be
## a String or StringName. Returns null when [param id] is empty or doesn't resolve to a
## roster file.
##
## A MISS IS EXPECTED, not a fault: [MapLoader] deliberately PROBES this with a spawn's
## authored id and falls back to DEFAULT_CHARACTER_ID when it comes back null, so every
## legacy-id spawn used to emit a debugger warning and then work correctly. (MapResource
## even documents preferring all_ids() "rather than get_character(), which pushes a warning
## on a miss".) So the null return IS the report; the engine log is left alone, and an
## unresolvable id is printed at most once per process so real content bugs stay findable.
static func get_character(id) -> CharacterResource:
	var key: StringName = StringName(id) if id != null else &""
	if String(key).is_empty():
		return null

	if _cache.has(key):
		return _cache[key]

	var path := ROSTER_DIR + String(key) + ".tres"
	if not ResourceLoader.exists(path):
		_note_miss(key, "no roster entry (expected %s)" % path)
		return null

	var resource := load(path) as CharacterResource
	if resource == null:
		_note_miss(key, "'%s' is not a CharacterResource" % path)
		return null

	_cache[key] = resource
	return resource


## Print an unresolvable id once per process (see [method get_character]). A plain print
## never reaches the debugger's error panel, which is the point.
static func _note_miss(key: StringName, reason: String) -> void:
	if _reported_misses.has(key):
		return
	_reported_misses[key] = true
	print("[CharacterLibrary] character id '%s' did not resolve: %s" % [String(key), reason])


## All known roster character ids, as StringNames. Scans ROSTER_DIR; falls
## back to KNOWN_IDS if the directory is unavailable (e.g. running from an
## export template that doesn't expose DirAccess listing).
static func all_ids() -> Array:
	var ids: Array = []
	var dir := DirAccess.open(ROSTER_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres") and not file_name.begins_with("."):
				ids.append(StringName(file_name.get_basename()))
			file_name = dir.get_next()
		dir.list_dir_end()

	if ids.is_empty():
		for known_id in KNOWN_IDS:
			ids.append(known_id)

	return ids


## Clears the resource cache. Not needed in normal play; useful for editor
## tooling / tests that reload roster .tres files from disk.
static func clear_cache() -> void:
	_cache.clear()
