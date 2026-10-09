extends RefCounted
class_name WeaponLibrary

## Central lookup for [WeaponResource]s (the same pattern as [CharacterLibrary]): loads
## res://game/characters/weapons/library/<weapon_id>.tres on demand and caches it. Returned
## weapons are SHARED and read-only (CONQUEST.md rule 7). A miss returns null and never logs
## (rule 1): callers decide what an unknown id means.

const LIBRARY_DIR: String = "res://game/characters/weapons/library/"
## A human with no weapon (an unauthored or broken reference) still strikes with this.
const UNARMED_ID: StringName = &"unarmed"

static var _cache: Dictionary = {}


static func get_weapon(id) -> WeaponResource:
	var key: StringName = StringName(String(id)) if id != null else &""
	if String(key).is_empty():
		return null
	if _cache.has(key):
		return _cache[key]
	var path := LIBRARY_DIR + String(key) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var w := load(path) as WeaponResource
	if w == null:
		return null
	_cache[key] = w
	return w


static func has_weapon(id) -> bool:
	return get_weapon(id) != null


## The bare-handed fallback (the library's "unarmed", else a code-built one).
static func unarmed() -> WeaponResource:
	var w := get_weapon(UNARMED_ID)
	if w != null:
		return w
	if not _cache.has(&"__unarmed_builtin"):
		var b := WeaponResource.new()
		b.weapon_id = UNARMED_ID
		b.display_name = "Unarmed"
		b.weapon_type = &""
		b.might = 4
		b.hit = 0.9
		_cache[&"__unarmed_builtin"] = b
	return _cache[&"__unarmed_builtin"]


static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var dir := DirAccess.open(LIBRARY_DIR)
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".tres") and not f.begins_with("."):
				ids.append(StringName(f.get_basename()))
			f = dir.get_next()
		dir.list_dir_end()
	ids.sort()
	return ids


static func clear_cache() -> void:
	_cache.clear()
