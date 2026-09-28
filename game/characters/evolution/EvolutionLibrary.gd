extends RefCounted
class_name EvolutionLibrary

## Central index of every shipped [EvolutionResource] under res://game/characters/evolutions/.
##
## Mirrors [ItemLibrary]: the directory is scanned ONCE (recursively, tolerant of an
## unreadable folder) and cached; content correctness is the separate [method validate] step,
## pinned by a test so a bad edit fails loudly while the game still boots. All graph queries
## delegate to one [EvolutionGraph] built from the scan.
##
## Static, content-only state: nothing here knows about the player. What the player has grown
## or unlocked lives in [RosterLedger].

const CONTENT_DIR: String = "res://game/characters/evolutions/"

static var _graph: EvolutionGraph = null
## Discovered .tres paths (sorted), for diagnostics.
static var _paths: Array[String] = []
## Test-only edges served beside the content ([method add_extra_edges]).
static var _extra_edges: Array[EvolutionResource] = []


## The graph over the shipped edges.
static func graph() -> EvolutionGraph:
	_ensure_scanned()
	return _graph


static func all() -> Array[EvolutionResource]:
	return graph().all()


static func get_edge(id) -> EvolutionResource:
	return graph().get_edge(id)


static func edges_from(char_id) -> Array[EvolutionResource]:
	return graph().edges_from(char_id)


static func edge_between(from, to) -> EvolutionResource:
	return graph().edge_between(from, to)


static func parent_of(id) -> StringName:
	return graph().parent_of(id)


static func line_root(id) -> StringName:
	return graph().line_root(id)


static func line_of(id) -> Array[StringName]:
	return graph().line_of(id)


static func stage_of(id) -> int:
	return graph().stage_of(id)


static func is_evolved_form(id) -> bool:
	return graph().is_evolved_form(id)


static func in_any_line(id) -> bool:
	return graph().in_any_line(id)


## Audit the shipped edges against the shipped roster and rules. Empty == clean.
static func validate() -> Array[String]:
	return graph().validate(
		func(cid) -> CharacterResource: return CharacterLibrary.get_character(cid),
		EvolutionRules.current().max_budget_growth)


## Re-read the content directory (tooling and tests).
static func rescan() -> void:
	_graph = null
	_ensure_scanned()


static func _ensure_scanned() -> void:
	if _graph != null:
		return
	_paths.clear()
	_scan_dir(CONTENT_DIR)
	_paths.sort()
	var edges: Array = []
	for path in _paths:
		var res: Resource = load(path)
		if res is EvolutionResource:
			edges.append(res)
	for e in _extra_edges:
		edges.append(e)
	_graph = EvolutionGraph.new(edges)


## TEST SEAM: serve [param edges] (fixture / example edges, e.g. tests/helpers/evolution_examples)
## BESIDE the shipped ones until [method clear_extra_edges]. Rebuilds the graph.
static func add_extra_edges(edges: Array) -> void:
	for e in edges:
		if e is EvolutionResource and not _extra_edges.has(e):
			_extra_edges.append(e)
	_graph = null


## Drop every [method add_extra_edges] edge (tests' after_each) and rebuild from content.
static func clear_extra_edges() -> void:
	_extra_edges.clear()
	_graph = null


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
			# Exported builds list "<name>.tres.remap"; the loadable path drops the suffix.
			var load_name: String = entry.trim_suffix(".remap")
			if load_name.ends_with(".tres") or load_name.ends_with(".res"):
				var load_path: String = dir_path.path_join(load_name)
				if ResourceLoader.exists(load_path) and not (load_path in _paths):
					_paths.append(load_path)
		entry = dir.get_next()
	dir.list_dir_end()
