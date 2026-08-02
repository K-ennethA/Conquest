extends RefCounted
class_name ItemLibrary

## Central index of every [ItemResource] under game/items/content/.
##
## Mirrors [TileCatalog]'s contract, for the same reasons: the directory is scanned ONCE and
## cached (so repeated battle setups, drop rolls and menu opens never re-hit disk), and every
## lookup goes through the item's stable [member ItemResource.id] rather than its path. Save
## files store ids, so an item must stay resolvable after its .tres is renamed or moved into
## a sub-folder -- which is also why the scan recurses.
##
## Scanning is deliberately tolerant (an unreadable directory yields an empty library rather
## than an error) and content correctness is a SEPARATE, explicit step: [method validate]
## reports duplicate ids, empty ids, and stat keys [UnitStats] does not know. That split is
## what lets the game boot on a bad content edit while a test still fails loudly on it.

const CONTENT_DIR: String = "res://game/items/content/"

## id (StringName) -> ItemResource, in sorted-path order so a duplicate-id clash always
## resolves the same way across runs.
static var _by_id: Dictionary = {}
## Discovered .tres paths, sorted. Kept so [method validate] can name the offending file.
static var _paths: Array[String] = []
## id -> path, for diagnostics.
static var _path_by_id: Dictionary = {}
static var _scanned: bool = false


## Every item, ordered by rarity then display name (the order UI lists want). Returns a
## fresh Array each call; the ItemResources themselves are shared and read-only.
static func all_items() -> Array[ItemResource]:
	_ensure_scanned()
	var items: Array[ItemResource] = []
	for key in _by_id.keys():
		items.append(_by_id[key])
	# Rarity DESCENDING (epics lead, the way a collection screen wants to open), then name.
	# An inline lambda rather than a named static helper: a bare method reference inside a
	# static function has no instance to bind to.
	items.sort_custom(func(a: ItemResource, b: ItemResource) -> bool:
		if int(a.rarity) != int(b.rarity):
			return int(a.rarity) > int(b.rarity)
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return items


## Every known item id, sorted alphabetically (stable across runs).
static func all_ids() -> Array[StringName]:
	_ensure_scanned()
	var ids: Array[StringName] = []
	for key in _by_id.keys():
		ids.append(key)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## Resolve an item by its stable id (String or StringName). Null when unknown -- callers
## must handle that, because a save file can reference an item removed from the content
## folder and the game must not crash on it.
static func get_item(id) -> ItemResource:
	if id == null:
		return null
	var key: StringName = StringName(id)
	if String(key).is_empty():
		return null
	_ensure_scanned()
	return _by_id.get(key, null)


## True when [param id] resolves to a shipped item.
static func has_item(id) -> bool:
	return get_item(id) != null


## Every item whose [member ItemResource.scope] is [param scope], in display order.
static func items_with_scope(scope: int) -> Array[ItemResource]:
	var out: Array[ItemResource] = []
	for item in all_items():
		if int(item.scope) == scope:
			out.append(item)
	return out


## Every item of [param rarity], in display order. This is the pool a drop roll draws from
## once the rarity tier has been decided.
static func items_of_rarity(rarity: int) -> Array[ItemResource]:
	var out: Array[ItemResource] = []
	for item in all_items():
		if int(item.rarity) == rarity:
			out.append(item)
	return out


## The content-source path an id was loaded from ("" when unknown). Diagnostics only.
static func path_for_id(id) -> String:
	_ensure_scanned()
	return String(_path_by_id.get(StringName(id), ""))


## Audit the shipped content and return a list of human-readable problems (empty == clean).
##
## Checks, in order: an item with no id (unreferenceable, so unequippable and unsaveable);
## two items claiming the same id (every save referencing it silently gets whichever the
## scan happened to keep); and a [member ItemResource.stat_modifiers] key that is not a stat
## [UnitStats] can carry (a typo like "hp" or "max_health" would apply nothing at all).
## Called by the item tests; safe to call at runtime.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for path in _sorted_paths():
		var res: Resource = load(path)
		if not (res is ItemResource):
			continue
		var item: ItemResource = res
		var key: StringName = item.id
		if String(key).is_empty():
			problems.append("%s has an empty id (items must declare a stable id)." % path)
			continue
		if seen.has(key):
			problems.append("duplicate item id '%s': %s and %s." % [String(key), String(seen[key]), path])
		else:
			seen[key] = path
		for raw_stat in item.stat_modifiers.keys():
			var stat_name: String = String(raw_stat)
			if stat_name not in ItemResource.VALID_STATS:
				problems.append("item '%s' (%s) modifies unknown stat '%s'." % [String(key), path, stat_name])
	return problems


## Re-read the content directory. Only needed after writing new item .tres files (tooling
## and tests); normal play scans once lazily.
static func rescan() -> void:
	_scanned = false
	_ensure_scanned()


# --- internals --------------------------------------------------------------

static func _sorted_paths() -> Array[String]:
	_ensure_scanned()
	return _paths.duplicate()


static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	_by_id.clear()
	_paths.clear()
	_path_by_id.clear()
	_scan_dir(CONTENT_DIR)
	# Index from the SORTED path list rather than during the walk, so "first one wins" on an
	# id clash means the alphabetically-first file every run rather than whatever order the
	# filesystem handed back (same rule TileCatalog uses).
	_paths.sort()
	for path in _paths:
		var res: Resource = load(path)
		if not (res is ItemResource):
			continue
		var item: ItemResource = res
		if String(item.id).is_empty():
			continue
		if _by_id.has(item.id):
			# A content bug, not a crash: keep the first and make the clash loud.
			# ItemLibrary.validate() reports it as a hard failure for the tests.
			push_warning("ItemLibrary: duplicate item id '%s' -- keeping %s, ignoring %s." % [
				String(item.id), String(_path_by_id[item.id]), path])
			continue
		_by_id[item.id] = item
		_path_by_id[item.id] = path


## Walk [param dir_path] and every subdirectory, collecting .tres files that really load as
## an [ItemResource] (so an unrelated resource parked here is simply ignored).
static func _scan_dir(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full)
		else:
			# An exported build surfaces .tres as "<name>.tres.remap"; the loadable path is
			# the name with that suffix stripped back off.
			var load_name: String = entry.trim_suffix(".remap")
			if load_name.ends_with(".tres") or load_name.ends_with(".res"):
				var load_path: String = dir_path.path_join(load_name)
				if ResourceLoader.exists(load_path):
					var res: Resource = load(load_path)
					if res is ItemResource and not (load_path in _paths):
						_paths.append(load_path)
		entry = dir.get_next()
	dir.list_dir_end()
