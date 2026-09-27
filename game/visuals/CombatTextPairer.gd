extends RefCounted
class_name CombatTextPairer

## Pure pairing logic behind [FloatingCombatText] (no nodes, so it is unit-tested
## headless).
##
## Sources call [method annotate] just BEFORE they change a unit's HP (see
## [CombatText]); the unit's [signal UnitStats.health_changed] then arrives
## synchronously and [method on_health_changed] claims the oldest matching
## annotation (damage for a loss, heal for a gain) to build one display ENTRY. An
## HP change nobody annotated becomes a plain entry. At the end of the frame
## [method flush] turns every unclaimed annotation that still means something into an
## entry of its own: a MISS, an IMMUNE (invulnerable), or a "Blocked N" when a shield
## soaked the whole hit. Unclaimed heals (the unit was already full) show nothing.
##
## Entry keys: unit, kind (damage / heal / miss / immune / blocked), amount, crit,
## effectiveness, source, source_kind, source_id, weather, weather_fx, color,
## blocked (HP a shield soaked), plain (true when unannotated).

const ENTRY_DAMAGE := &"damage"
const ENTRY_HEAL := &"heal"
const ENTRY_MISS := &"miss"
const ENTRY_IMMUNE := &"immune"
const ENTRY_BLOCKED := &"blocked"

## unit -> Array[Dictionary] of pending annotations (oldest first).
var _pending: Dictionary = {}


## Queue [param info] for [param unit]. [param shield_before] is the unit's shield at
## annotation time, so a later claim can report how much the shield soaked.
func annotate(unit, info: Dictionary, shield_before: int = 0) -> void:
	if unit == null:
		return
	var a := info.duplicate()
	a["shield_before"] = shield_before
	if not _pending.has(unit):
		_pending[unit] = []
	(_pending[unit] as Array).append(a)


## True while any annotation is waiting for its HP change / the end of the frame.
func has_pending() -> bool:
	return not _pending.is_empty()


## Pair one HP change with the oldest matching annotation. Returns the entry, or an
## empty dictionary when HP did not change.
func on_health_changed(unit, old_hp: int, new_hp: int, shield_now: int = 0) -> Dictionary:
	var delta := new_hp - old_hp
	if delta == 0 or unit == null:
		return {}
	var want: StringName = CombatText.KIND_DAMAGE if delta < 0 else CombatText.KIND_HEAL
	var a := _claim(unit, want)
	var entry := {
		"unit": unit,
		"kind": ENTRY_DAMAGE if delta < 0 else ENTRY_HEAL,
		"amount": absi(delta),
		"plain": a.is_empty(),
	}
	if not a.is_empty():
		_copy_context(a, entry)
		if delta < 0:
			var blocked := maxi(0, int(a.get("shield_before", 0)) - shield_now)
			if blocked > 0:
				entry["blocked"] = blocked
	return entry


## End of frame: entries for the unclaimed annotations that still mean something, in
## arrival order. [param shield_of] maps a unit to its CURRENT shield (for the
## "Blocked" case); omit it when shields are irrelevant. Clears every pending item.
func flush(shield_of: Callable = Callable()) -> Array:
	var out: Array = []
	for unit in _pending.keys():
		var shield_now := 0
		if shield_of.is_valid() and is_instance_valid_or_plain(unit):
			shield_now = int(shield_of.call(unit))
		for a in _pending[unit]:
			var kind: StringName = StringName(a.get("kind", &""))
			var entry := { "unit": unit, "amount": 0, "plain": false }
			match kind:
				CombatText.KIND_MISS:
					entry["kind"] = ENTRY_MISS
				CombatText.KIND_NEGATED:
					entry["kind"] = ENTRY_IMMUNE
				CombatText.KIND_DAMAGE:
					# Never reached HP: if the shield went down since, it soaked it all.
					if int(a.get("shield_before", 0)) <= shield_now or int(a.get("amount", 0)) <= 0:
						continue
					entry["kind"] = ENTRY_BLOCKED
					entry["blocked"] = mini(int(a.get("amount", 0)), int(a.get("shield_before", 0)))
				_:
					continue  # an unclaimed heal = already at full health: show nothing
			_copy_context(a, entry)
			out.append(entry)
	_pending.clear()
	return out


func clear() -> void:
	_pending.clear()


func _claim(unit, kind: StringName) -> Dictionary:
	if not _pending.has(unit):
		return {}
	var list: Array = _pending[unit]
	for i in list.size():
		if StringName(list[i].get("kind", &"")) == kind:
			var a: Dictionary = list[i]
			list.remove_at(i)
			if list.is_empty():
				_pending.erase(unit)
			return a
	return {}


static func _copy_context(a: Dictionary, entry: Dictionary) -> void:
	for k in ["crit", "effectiveness", "source", "source_kind", "source_id",
			"weather", "weather_fx", "color", "attacker"]:
		if a.has(k):
			entry[k] = a[k]


static func is_instance_valid_or_plain(o) -> bool:
	if o is Object:
		return is_instance_valid(o)
	return o != null
