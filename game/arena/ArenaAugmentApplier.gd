extends RefCounted
class_name ArenaAugmentApplier

## Re-applies a squad member's drafted build onto the LIVE Unit each round. Every
## round rebuilds fresh Unit nodes, so the accumulated augments (per-unit ones on
## ArenaUnitState.augment_ids plus run-wide ones on ArenaRun.run_augment_ids) must be
## re-stamped onto the new unit at setup. This is the generic, data-only path: it reads
## each Augment's stat_bonuses and pushes them through the unit's real stat API, then
## hands the unit to the augment's apply_to_unit() hook for any bespoke effect.
##
## The whole thing is best-effort and null-safe: a freed unit, an unknown augment id, a
## unit with no stats component, or a stat the engine does not know are all skipped
## rather than raised, so a bad draft entry can never crash round setup.

## Directory the draftable Augment .tres files live in.
const AUGMENTS_DIR := "res://game/arena/augments"

## Stats that UnitStats._set_current_stat (and, permanently, _set_base_stat) knows how to
## write. For these we go through the unit's public modify_stat() so the engine clamps
## them and raises max_health/base_attack/... alongside the current value. Anything NOT in
## this set (evasion, crit, magic, magic_defense, and any custom key) has no branch in
## _set_current_stat, so modify_stat would silently no-op -- those we write straight onto
## the component's current_<stat> field instead.
const MODIFY_STAT_KEYS := {
	"health": true,
	"attack": true,
	"defense": true,
	"speed": true,
	"movement": true,
	"range": true,
	"actions": true,
	"range_bonus": true,
}

## id -> Augment, built once by scanning AUGMENTS_DIR and cached so repeated round-setup
## calls never re-hit the disk.
static var _index: Dictionary = {}
static var _index_built: bool = false


## Re-apply every augment stacked on [param unit_state] and on the [param run] to the live
## [param unit]. Called by the round builder on each freshly-spawned squad unit.
static func apply(unit, unit_state: ArenaUnitState, run: ArenaRun) -> void:
	if not is_instance_valid(unit):
		return
	_ensure_index()

	# Gather the per-unit build plus the run-wide augments, de-duplicated (a run-wide
	# augment and a per-unit one could name the same id; apply each effect once).
	var ids: Array[String] = []
	if unit_state != null:
		for aid in unit_state.augment_ids:
			var s: String = String(aid)
			if s != "" and s not in ids:
				ids.append(s)
	if run != null:
		for aid in run.run_augment_ids:
			var s: String = String(aid)
			if s != "" and s not in ids:
				ids.append(s)

	for aid in ids:
		var augment: Augment = _index.get(aid, null)
		if augment == null:
			continue
		_apply_stat_bonuses(unit, augment.stat_bonuses)
		# Bespoke hook (move upgrades / granted passives) -- base is a no-op, so this is
		# safe for the data-only augments in the starter pool.
		augment.apply_to_unit(unit)


## Apply every run-wide augment's non-unit effect exactly once for the run (e.g. an extra
## squad slot or a currency boon). Optional companion to apply(); safe to call once at run
## or round start. Per-unit stat_bonuses are handled by apply(), not here.
static func apply_run(run: ArenaRun) -> void:
	if run == null:
		return
	_ensure_index()
	for aid in run.run_augment_ids:
		var augment: Augment = _index.get(String(aid), null)
		if augment != null:
			augment.apply_to_run(run)


## Look up a single Augment by id (null when unknown). Public so callers (e.g. the draft
## UI) can resolve an id without knowing the storage layout.
static func augment_for_id(augment_id: String) -> Augment:
	_ensure_index()
	return _index.get(augment_id, null)


# --- internals --------------------------------------------------------------

static func _apply_stat_bonuses(unit, stat_bonuses: Dictionary) -> void:
	if stat_bonuses == null or stat_bonuses.is_empty():
		return
	# The stats component, if this unit has one. Untyped on purpose: unit is untyped and
	# UnitStats' current_<stat> fields are reached via get()/set() below.
	var stats = unit.get("unit_stats")
	for raw_key in stat_bonuses.keys():
		var delta: int = int(stat_bonuses[raw_key])
		if delta == 0:
			continue
		var key: String = _canonical_stat(String(raw_key))
		if MODIFY_STAT_KEYS.has(key):
			# Permanent so max_health/base_attack/... move with the current value, and so
			# the change survives the per-turn modifier tick.
			if unit.has_method("modify_stat"):
				unit.modify_stat(key, delta, true)
		else:
			_bump_current_field(stats, key, delta)


## Directly add [param delta] to UnitStats.current_<canonical> for the stats
## (evasion/crit/magic/magic_defense) that modify_stat cannot reach. Null-safe and
## type-checked: a missing component or a field the component does not declare is skipped.
static func _bump_current_field(stats, canonical: String, delta: int) -> void:
	if stats == null:
		return
	var field: String = "current_" + canonical
	var cur = stats.get(field)
	if typeof(cur) != TYPE_INT:
		return
	stats.set(field, int(cur) + delta)


## Normalize an author-facing stat key (and its aliases) to the canonical name the engine
## uses. Unknown keys pass through lower-cased so a custom stat still round-trips.
static func _canonical_stat(stat_name: String) -> String:
	match stat_name.strip_edges().to_lower():
		"health", "hp", "max_health", "maxhp":
			return "health"
		"attack", "atk":
			return "attack"
		"defense", "def":
			return "defense"
		"speed", "spd":
			return "speed"
		"movement", "move":
			return "movement"
		"actions", "act":
			return "actions"
		"range":
			return "range"
		"range_bonus":
			return "range_bonus"
		"magic", "mag":
			return "magic"
		"magic_defense", "mdef", "resistance", "res":
			return "magic_defense"
		"evasion", "eva", "evade":
			return "evasion"
		"crit":
			return "crit"
	return stat_name.strip_edges().to_lower()


## Build the id -> Augment index once by scanning AUGMENTS_DIR for .tres files.
static func _ensure_index() -> void:
	if _index_built:
		return
	_index_built = true
	_index = {}
	var dir := DirAccess.open(AUGMENTS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_resource_file(file_name):
			# In an exported build .tres files surface as "<name>.tres.remap"; the
			# loadable path is the name with that suffix stripped back off.
			var load_name: String = file_name.trim_suffix(".remap")
			var path: String = AUGMENTS_DIR + "/" + load_name
			var res: Resource = ResourceLoader.load(path)
			if res is Augment:
				var augment: Augment = res
				var key: String = augment.id if augment.id != "" else file_name.get_basename()
				_index[key] = augment
		file_name = dir.get_next()
	dir.list_dir_end()


## True for a loadable Godot resource file, tolerating the .remap/.import suffixes an
## exported build appends to .tres names.
static func _is_resource_file(file_name: String) -> bool:
	var lower: String = file_name.to_lower()
	if lower.ends_with(".remap"):
		lower = lower.trim_suffix(".remap")
	return lower.ends_with(".tres") or lower.ends_with(".res")
