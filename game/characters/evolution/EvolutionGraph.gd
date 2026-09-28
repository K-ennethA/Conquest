extends RefCounted
class_name EvolutionGraph

## The evolution graph over a SET of [EvolutionResource] edges: lookups, line walks and the
## content validator.
##
## An instance, not statics, so the same queries run over the shipped content (held by
## [EvolutionLibrary]) and over fixture edges a test builds in code -- the validator's failure
## cases (a missing id, a second parent, a cycle, a budget out of bounds) are proven without
## a single broken file on disk.
##
## Every query is tolerant: an unknown id is simply "not in any line" (its own root, stage 1,
## no edges). Correctness is the separate, explicit [method validate] step.

var _edges: Array[EvolutionResource] = []
## id -> edge (first wins on a duplicate id; validate() reports the clash).
var _by_id: Dictionary = {}
## from_id -> Array[EvolutionResource], sorted by edge id.
var _from: Dictionary = {}
## to_id -> from_id (first parent wins; validate() reports a second one).
var _parent: Dictionary = {}


func _init(edges: Array = []) -> void:
	for e in edges:
		if e is EvolutionResource:
			_edges.append(e)
	_edges.sort_custom(func(a: EvolutionResource, b: EvolutionResource) -> bool:
		return String(a.id) < String(b.id))
	for edge in _edges:
		if not String(edge.id).is_empty() and not _by_id.has(edge.id):
			_by_id[edge.id] = edge
		if String(edge.from_id).is_empty() or String(edge.to_id).is_empty():
			continue
		if not _from.has(edge.from_id):
			_from[edge.from_id] = []
		(_from[edge.from_id] as Array).append(edge)
		if not _parent.has(edge.to_id):
			_parent[edge.to_id] = edge.from_id


## Every edge, sorted by id.
func all() -> Array[EvolutionResource]:
	return _edges.duplicate()


## The edge with [param id], or null.
func get_edge(id) -> EvolutionResource:
	if id == null:
		return null
	return _by_id.get(StringName(id), null)


## Every edge leaving [param char_id] (its possible evolutions), sorted by edge id.
func edges_from(char_id) -> Array[EvolutionResource]:
	var out: Array[EvolutionResource] = []
	for e in _from.get(StringName(char_id), []):
		out.append(e)
	return out


## The edge [param from] -> [param to], or null.
func edge_between(from, to) -> EvolutionResource:
	for e in edges_from(from):
		if e.to_id == StringName(to):
			return e
	return null


## The form [param id] evolves from, or &"" for a base form / unknown id.
func parent_of(id) -> StringName:
	return _parent.get(StringName(id), &"")


## The base form of [param id]'s line (itself when it has no parent). Cycle-safe.
func line_root(id) -> StringName:
	var current: StringName = StringName(id)
	var seen: Dictionary = {}
	while _parent.has(current) and not seen.has(current):
		seen[current] = true
		current = _parent[current]
	return current


## The whole line of [param id]: its root plus every descendant, breadth-first.
func line_of(id) -> Array[StringName]:
	var root: StringName = line_root(id)
	var out: Array[StringName] = [root]
	var i: int = 0
	while i < out.size():
		for e in edges_from(out[i]):
			if not out.has(e.to_id):
				out.append(e.to_id)
		i += 1
	return out


## 1 for a base form, 2 for its evolution, and so on.
func stage_of(id) -> int:
	var stage: int = 1
	var current: StringName = StringName(id)
	var seen: Dictionary = {}
	while _parent.has(current) and not seen.has(current):
		seen[current] = true
		current = _parent[current]
		stage += 1
	return stage


## True when [param id] is reached by some edge (it has a parent).
func is_evolved_form(id) -> bool:
	return _parent.has(StringName(id))


## True when [param id] takes part in any edge, as a parent or a child.
func in_any_line(id) -> bool:
	var key: StringName = StringName(id)
	return _parent.has(key) or _from.has(key)


## Audit the edges; returns human-readable problems (empty == clean).
##
## [param lookup] resolves a character id to its [CharacterResource] (null when unknown) --
## [code]CharacterLibrary.get_character[/code] for shipped content, a Dictionary lookup in
## tests. [param max_budget_growth] is [member EvolutionRules.max_budget_growth].
func validate(lookup: Callable, max_budget_growth: float) -> Array[String]:
	var problems: Array[String] = []
	var seen_ids: Dictionary = {}
	var parents: Dictionary = {}
	for e in _edges:
		var eid: String = String(e.id)
		if eid.is_empty():
			problems.append("an edge %s -> %s has an empty id." % [String(e.from_id), String(e.to_id)])
		elif seen_ids.has(eid):
			problems.append("duplicate edge id '%s'." % eid)
		seen_ids[eid] = true

		var from_c: CharacterResource = lookup.call(e.from_id) if not String(e.from_id).is_empty() else null
		var to_c: CharacterResource = lookup.call(e.to_id) if not String(e.to_id).is_empty() else null
		if from_c == null:
			problems.append("edge '%s': from_id '%s' is not a roster character." % [eid, String(e.from_id)])
		if to_c == null:
			problems.append("edge '%s': to_id '%s' is not a roster character." % [eid, String(e.to_id)])
		if e.from_id == e.to_id and not String(e.from_id).is_empty():
			problems.append("edge '%s' evolves a form into itself." % eid)

		if not String(e.to_id).is_empty():
			if parents.has(e.to_id) and parents[e.to_id] != e.from_id:
				problems.append("form '%s' has a second parent ('%s' and '%s'); a form may evolve from one form only." % [
					String(e.to_id), String(parents[e.to_id]), String(e.from_id)])
			elif parents.has(e.to_id):
				problems.append("form '%s' is reached by two edges from '%s'." % [String(e.to_id), String(e.from_id)])
			else:
				parents[e.to_id] = e.from_id

		for t in e.triggers:
			if t == null:
				problems.append("edge '%s' has an empty trigger slot." % eid)

		if from_c == null or to_c == null:
			continue
		# Bosses are never a player's evolution, except as an in-battle boss phase change.
		if (from_c.is_boss or to_c.is_boss) and not (e.allowed_in_battle and to_c.is_boss):
			problems.append("edge '%s' involves a boss; only an in-battle edge INTO a boss form (a phase change) may." % eid)
		if e.allowed_in_battle and from_c.get_footprint() != to_c.get_footprint():
			problems.append("edge '%s' is allowed in battle but changes the footprint (%s -> %s)." % [
				eid, str(from_c.get_footprint()), str(to_c.get_footprint())])
		var from_budget: int = from_c.power_budget()
		var to_budget: int = to_c.power_budget()
		if to_budget < from_budget:
			problems.append("edge '%s': '%s' (budget %d) is weaker than '%s' (budget %d)." % [
				eid, String(e.to_id), to_budget, String(e.from_id), from_budget])
		elif float(to_budget) > float(from_budget) * max_budget_growth + 0.0001:
			problems.append("edge '%s': budget grows %d -> %d, over the x%.2f ceiling." % [
				eid, from_budget, to_budget, max_budget_growth])

	# Cycles: walking parents from any form must terminate at a root.
	var reported: Dictionary = {}
	for start in parents.keys():
		var current: StringName = start
		var seen: Dictionary = {}
		while parents.has(current):
			if seen.has(current):
				if not reported.has(current):
					reported[current] = true
					problems.append("the evolution graph has a cycle through '%s'." % String(current))
				break
			seen[current] = true
			current = parents[current]
	return problems
