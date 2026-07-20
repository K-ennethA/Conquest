extends RefCounted
class_name StatusCatalog

## Central index of every [StatusCondition] resource in the project, modelled on
## [TileCatalog]. It exists for the same two reasons:
##
## 1. RECURSIVE DISCOVERY -- status .tres files are authored as content and get
##    regrouped (by element, by source, by expansion) as the set grows. Anything
##    that LISTS statuses (the Compendium) must therefore look deeper than one
##    directory, and adding a new subfolder must need no code change.
##
##    Discovery deliberately walks SEVERAL candidate roots (see [constant ROOTS])
##    rather than one hardcoded folder: status authoring is in flight, so the
##    folder that ends up holding them is not settled. Every root is optional --
##    a missing directory is skipped silently, not an error -- and only files
##    that actually LOAD as a StatusCondition are kept, so unrelated resources
##    sharing a folder are ignored rather than mistaken for statuses.
##
## 2. ID ADDRESSING -- every condition declares a stable
##    [member StatusCondition.id] that survives the file being moved or renamed.
##    [method find_by_id] resolves that id to the live resource, so a move's
##    ApplyStatusEffect, a tile, or an ability can name WHAT it inflicts rather
##    than WHERE the file happens to sit today.
##
## The index is scanned once and cached; call [method rescan] after new status
## resources are written to disk.

## Directories searched, each recursively. Missing roots are skipped. The first
## entry is the expected home; the rest are tolerated alternatives so the catalog
## keeps working if statuses are filed elsewhere.
const ROOTS: Array[String] = [
	"res://game/combat/status/",
	"res://game/combat/statuses/",
	"res://game/combat/resources/statuses/",
	"res://game/statuses/",
]

static var _paths: Array[String] = []
static var _by_id: Dictionary = {}
static var _scanned: bool = false


## Every StatusCondition path found under [constant ROOTS], sorted for stable
## ordering.
static func all_paths() -> Array[String]:
	_ensure_scanned()
	return _paths.duplicate()


## Every StatusCondition resource, in the same order as [method all_paths].
## Entries that fail to load are dropped, so the result never contains nulls.
static func all_statuses() -> Array[StatusCondition]:
	_ensure_scanned()
	var out: Array[StatusCondition] = []
	for path in _paths:
		var res = load(path)
		if res is StatusCondition:
			out.append(res as StatusCondition)
	return out


## Resolve a condition by its stable [member StatusCondition.id] -- the PREFERRED
## lookup, since it never touches a path. Returns null when nothing declares it.
static func find_by_id(id: StringName) -> StatusCondition:
	if String(id).is_empty():
		return null
	_ensure_scanned()
	var path: String = String(_by_id.get(id, ""))
	if path.is_empty():
		return null
	var res = load(path)
	if res is StatusCondition:
		return res as StatusCondition
	return null


## Re-read the directory trees (after new status resources are written to disk).
static func rescan() -> void:
	_scanned = false
	_ensure_scanned()


static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	_paths.clear()
	_by_id.clear()
	for root in ROOTS:
		_scan_dir(root)
	_paths.sort()
	# The id index is built from the SORTED path list rather than during the
	# directory walk, so "first one wins" on a clash resolves to the
	# alphabetically-first path every run instead of filesystem order.
	_build_index()


## Populate the id index from the sorted [member _paths].
static func _build_index() -> void:
	for path in _paths:
		var res = load(path)
		if not (res is StatusCondition):
			continue
		var status := res as StatusCondition
		var status_id: StringName = status.id
		if String(status_id).is_empty():
			continue
		if _by_id.has(status_id):
			# Two conditions claiming one id is a content bug: whatever inflicts
			# it silently gets whichever we picked. Keep the first
			# (deterministic, see above) and make the duplicate loud.
			push_warning("StatusCatalog: duplicate status id '%s' -- keeping %s, ignoring %s. Status ids must be unique." % [
				String(status_id), String(_by_id[status_id]), path])
			continue
		_by_id[status_id] = path


## Walk [param dir_path] and every subdirectory, collecting .tres files that
## actually load as a StatusCondition (so the StatusCondition.gd script itself,
## and any unrelated resource living alongside, are ignored). Only
## [member _paths] is filled here; the id index is built afterwards from the
## sorted result (see [method _build_index]).
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
			if res is StatusCondition and not _paths.has(full):
				_paths.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
