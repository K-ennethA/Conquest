extends RefCounted
class_name TileCatalog

## Central index of every [TileResource] under game/tiles/resources/, INCLUDING
## biome subfolders (forest/, volcano/, ...). It exists for two reasons:
##
## 1. RECURSIVE DISCOVERY -- assets are grouped by theme, so anything that lists
##    tiles (the Map Creator palette, the Map Gallery) must look deeper than one
##    directory. Adding a new biome folder then needs no code change.
##
## 2. BASENAME FALLBACK -- a saved map stores its tiles as PATH STRINGS
##    (`tile_resource_path`). Moving an asset into a biome folder would silently
##    break every map that referenced the old location, and user-authored maps get
##    shared around, so a stale path must degrade gracefully instead of vanishing.
##    [method find] resolves the exact path first, then falls back to any tile with
##    the same file name wherever it now lives.
##
## The index is scanned once and cached; call [method rescan] after writing new
## tile resources (e.g. from the Tile Creator).

const ROOT := "res://game/tiles/resources/"

static var _paths: Array[String] = []
static var _by_basename: Dictionary = {}
static var _scanned: bool = false


## Every TileResource path found under ROOT, sorted for stable ordering.
static func all_paths() -> Array[String]:
	_ensure_scanned()
	return _paths.duplicate()


## Resolve a tile by path. Falls back to matching the file name elsewhere in the
## tree, so a map authored before an asset moved still finds it. Returns null when
## nothing matches.
static func find(path: String) -> TileResource:
	if path.is_empty():
		return null

	# Exact hit: the common case, and the only one that can be ambiguous-free.
	if ResourceLoader.exists(path):
		var exact = load(path)
		if exact is TileResource:
			return exact

	# Stale path -- the asset was probably reorganised into a biome folder.
	_ensure_scanned()
	var key := path.get_file()
	if _by_basename.has(key):
		var moved = load(String(_by_basename[key]))
		if moved is TileResource:
			return moved
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
	_scan_dir(ROOT)
	_paths.sort()


## Walk [param dir] and every subdirectory, collecting .tres files that actually
## load as a TileResource (so unrelated resources living here are ignored).
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
				# First writer wins on a name clash, and _paths is sorted, so the
				# mapping stays deterministic across runs.
				if not _by_basename.has(entry):
					_by_basename[entry] = full
		entry = dir.get_next()
	dir.list_dir_end()
