extends RefCounted
class_name TileCatalog

## Central index of every [TileResource] under game/tiles/resources/, INCLUDING
## biome subfolders (forest/, volcano/, ...). It exists for three reasons:
##
## 1. RECURSIVE DISCOVERY -- assets are grouped by theme, so anything that lists
##    tiles (the Map Creator palette, the Map Gallery) must look deeper than one
##    directory. Adding a new biome folder then needs no code change.
##
## 2. ID ADDRESSING (the preferred way to reference a tile) -- every tile declares
##    a stable [member TileResource.id] that does NOT change when the file moves or
##    is renamed. [method find_by_id] resolves that id to the live resource, so a
##    map, an effect or a hardcoded table names WHAT it wants rather than WHERE the
##    file happens to sit today. Maps are player-authored and SHARED, so this is
##    what lets someone else's map keep working after an asset reorganisation.
##
## 3. BASENAME FALLBACK (legacy) -- maps authored before ids stored their tiles as
##    PATH STRINGS (`tile_resource_path`). Moving an asset into a biome folder
##    would silently break those, so [method find] resolves the exact path first
##    and then falls back to any tile with the same file name wherever it now
##    lives. That fallback is a compatibility shim, not the intended entry point:
##    two tiles can share a file name, and it can only GUESS which was meant.
##
## The index is scanned once and cached; call [method rescan] after writing new
## tile resources (e.g. from the Tile Creator).

const ROOT := "res://game/tiles/resources/"

static var _paths: Array[String] = []
static var _by_basename: Dictionary = {}
static var _by_id: Dictionary = {}
static var _scanned: bool = false


## Every TileResource path found under ROOT, sorted for stable ordering.
static func all_paths() -> Array[String]:
	_ensure_scanned()
	return _paths.duplicate()


## Resolve a tile by its stable [member TileResource.id] -- the PREFERRED lookup.
##
## Unlike [method find] this survives the asset being moved or renamed, because it
## never touches a path. Returns null when no tile declares that id.
static func find_by_id(id: StringName) -> TileResource:
	if String(id).is_empty():
		return null
	_ensure_scanned()
	var path: String = String(_by_id.get(id, ""))
	if path.is_empty():
		return null
	var res = load(path)
	if res is TileResource:
		return res
	return null


## The stable id of the tile living at [param path], or &"" when there is none.
## Useful for MIGRATING legacy path-addressed data onto ids.
static func id_for_path(path: String) -> StringName:
	if path.is_empty():
		return &""
	var res := find(path)
	if res == null:
		return &""
	return res.get_id()


## Resolve a tile by PATH (legacy addressing -- prefer [method find_by_id]).
##
## Resolution order, most trustworthy first:
##   1. EXACT path -- the only unambiguous case.
##   2. BASENAME match elsewhere in the tree -- a compatibility fallback for maps
##      authored before the asset was reorganised into a biome folder. It guesses,
##      so it can pick the wrong tile when two files share a name.
##   3. null.
static func find(path: String) -> TileResource:
	if path.is_empty():
		return null

	# 1. Exact hit: the common case, and the only one that is ambiguity-free.
	if ResourceLoader.exists(path):
		var exact = load(path)
		if exact is TileResource:
			return exact

	# 2. Stale path -- the asset was probably reorganised into a biome folder.
	_ensure_scanned()
	var key := path.get_file()
	if _by_basename.has(key):
		var moved = load(String(_by_basename[key]))
		if moved is TileResource:
			return moved
	# 3. Nothing matched.
	return null


## Re-read the directory tree (after new tile resources are written to disk).
static func rescan() -> void:
	_scanned = false
	_ensure_scanned()


static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	_paths.clear()
	_by_basename.clear()
	_by_id.clear()
	_scan_dir(ROOT)
	_paths.sort()
	# Indexes are built from the SORTED path list, not during the directory walk,
	# so "first one wins" on a clash means the alphabetically-first path every run
	# rather than whatever order the filesystem happened to hand back.
	_build_indexes()


## Populate the basename and id indexes from the sorted [member _paths].
static func _build_indexes() -> void:
	for path in _paths:
		var res = load(path)
		if not (res is TileResource):
			continue
		var tile := res as TileResource

		var basename: String = path.get_file()
		if not _by_basename.has(basename):
			_by_basename[basename] = path

		var tile_id: StringName = tile.get_id()
		if String(tile_id).is_empty():
			continue
		if _by_id.has(tile_id):
			# Two tiles claiming one id is a content bug: every map referencing it
			# silently gets whichever we picked. Keep the first (deterministic, see
			# above) and make the duplicate loud rather than invisible.
			push_warning("TileCatalog: duplicate tile id '%s' -- keeping %s, ignoring %s. Tile ids must be unique." % [
				String(tile_id), String(_by_id[tile_id]), path])
			continue
		_by_id[tile_id] = path


## Walk [param dir] and every subdirectory, collecting .tres files that actually
## load as a TileResource (so unrelated resources living here are ignored).
## Only [member _paths] is filled here; the lookup indexes are built afterwards
## from the sorted result (see [method _build_indexes]).
static func _scan_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full)
		elif entry.ends_with(".tres") and ResourceLoader.exists(full):
			var res = load(full)
			if res is TileResource:
				_paths.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
