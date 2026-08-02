extends RefCounted
class_name SkinLibrary

## Central index of every [SkinResource] under game/skins/content/. Mirrors
## TileCatalog / CharacterLibrary: scan once, cache, address by stable id.
##
## Skins are grouped in one flat content/ folder (recursive scan anyway, so a
## future per-character subfolder needs no code change). Everything that lists or
## resolves skins — the Collection screen, the gacha roll, Unit's skin
## application — goes through here so there is one source of truth.
##
## The gacha math (weighted pick + duplicate refund) also lives here as PURE,
## RNG-injectable statics ([method weighted_pick], [method roll_with_rng]) so it
## is unit-testable without a scene or the PlayerProfile autoload. IMPORTANT: this
## RNG is a LOCAL, COSMETIC generator (a fresh RandomNumberGenerator the caller
## seeds however it likes) — it is emphatically NOT the deterministic match RNG,
## and must never be, since two networked peers roll skins independently.

const CONTENT_ROOT: String = "res://game/skins/content/"

## Points refunded when a gacha roll lands a skin the player already owns. No pity
## timer in v1 — a duplicate simply converts to this many points (documented in
## the Collection screen too).
const DUPLICATE_REFUND: int = 100

static var _paths: Array[String] = []
static var _by_id: Dictionary = {}          # StringName -> path
static var _scanned: bool = false


## Every SkinResource path under CONTENT_ROOT, sorted for stable ordering.
static func all_paths() -> Array[String]:
	_ensure_scanned()
	return _paths.duplicate()


## Every skin, as loaded resources, in stable id order.
static func all_skins() -> Array[SkinResource]:
	_ensure_scanned()
	var out: Array[SkinResource] = []
	for path in _paths:
		var res = load(path)
		if res is SkinResource:
			out.append(res)
	return out


## Resolve a skin by its stable [member SkinResource.id]. Returns null for an
## empty/unknown id (an unknown id therefore reads as "default look" everywhere).
static func find(skin_id) -> SkinResource:
	var key: StringName = StringName(skin_id) if skin_id != null else &""
	if String(key).is_empty():
		return null
	_ensure_scanned()
	var path: String = String(_by_id.get(key, ""))
	if path.is_empty():
		return null
	var res = load(path)
	if res is SkinResource:
		return res
	return null


## Every skin authored for [param character_id], in id order. Empty when none.
static func all_for_character(character_id) -> Array[SkinResource]:
	var wanted: StringName = StringName(character_id) if character_id != null else &""
	var out: Array[SkinResource] = []
	if String(wanted).is_empty():
		return out
	for skin in all_skins():
		if skin.character_id == wanted:
			out.append(skin)
	return out


## The full gacha pool: every skin, each carrying its rarity weight. Returns the
## SkinResources themselves (each answers rarity_weight()); [method weighted_pick]
## consumes this.
static func gacha_pool() -> Array[SkinResource]:
	return all_skins()


## Total gacha weight across the whole pool (sum of every skin's rarity_weight()).
static func total_weight() -> int:
	var total: int = 0
	for skin in gacha_pool():
		total += skin.rarity_weight()
	return total


## Weighted random pick from the gacha pool using the INJECTED [param rng]. PURE:
## no ownership, no side effects, no PlayerProfile — just "which skin did the
## wheel land on". Returns null only when the pool is empty. See the class note:
## [param rng] is a local cosmetic generator, never the match RNG.
static func weighted_pick(rng: RandomNumberGenerator) -> SkinResource:
	if rng == null:
		return null
	var pool: Array[SkinResource] = gacha_pool()
	if pool.is_empty():
		return null
	var total: int = 0
	for skin in pool:
		total += maxi(0, skin.rarity_weight())
	if total <= 0:
		return null
	var roll: int = rng.randi_range(0, total - 1)
	var cursor: int = 0
	for skin in pool:
		cursor += maxi(0, skin.rarity_weight())
		if roll < cursor:
			return skin
	return pool[pool.size() - 1]


## Resolve a whole gacha roll against the caller's [param owned_ids] (an Array of
## String/StringName the player already owns), using the injected [param rng].
## PURE and testable: it decides the OUTCOME but performs no spending or granting
## — the caller (Collection screen) applies the result against PlayerProfile.
##
## Returns a Dictionary:
##   { "skin_id": String, "rarity": int, "is_duplicate": bool, "refund": int }
## For a duplicate, refund == [constant DUPLICATE_REFUND]; otherwise refund == 0.
## An empty pool yields an empty skin_id (the caller should refund the roll cost).
static func roll_with_rng(rng: RandomNumberGenerator, owned_ids: Array = []) -> Dictionary:
	var picked: SkinResource = weighted_pick(rng)
	if picked == null:
		return { "skin_id": "", "rarity": SkinResource.Rarity.COMMON, "is_duplicate": false, "refund": 0 }

	var owned := _normalize_ids(owned_ids)
	var picked_id: String = String(picked.id)
	var is_dup: bool = picked_id in owned
	return {
		"skin_id": picked_id,
		"rarity": picked.rarity,
		"is_duplicate": is_dup,
		"refund": DUPLICATE_REFUND if is_dup else 0,
	}


## Duplicate a material and multiply its albedo by [param tint], returning a NEW
## material. PURE: never mutates [param base] (it is duplicated first), so a
## shared/base material used by several units is safe. Returns null for a null
## base. Non-standard materials are still duplicated (so callers get their own
## instance) but only Standard/ORM materials carry an albedo to tint.
static func tinted_material(base: Material, tint: Color) -> Material:
	if base == null:
		return null
	var dup: Material = base.duplicate()
	if dup is StandardMaterial3D:
		var sm := dup as StandardMaterial3D
		sm.albedo_color = sm.albedo_color * tint
	elif dup is ORMMaterial3D:
		var om := dup as ORMMaterial3D
		om.albedo_color = om.albedo_color * tint
	return dup


## Validate the whole catalog: unique ids, each character_id resolvable, each skin
## self-consistent. Returns { valid, issues }. Used by tests / content checks.
static func validate_catalog() -> Dictionary:
	_ensure_scanned()
	var issues: Array[String] = []
	var seen: Dictionary = {}
	for path in _paths:
		var res = load(path)
		if not (res is SkinResource):
			continue
		var skin := res as SkinResource
		var v: Dictionary = skin.validate()
		if not bool(v.get("valid", false)):
			for problem in v.get("issues", []):
				issues.append("%s: %s" % [path, problem])
		var key: StringName = skin.id
		if seen.has(key):
			issues.append("duplicate skin id '%s' (%s and %s)" % [String(key), String(seen[key]), path])
		else:
			seen[key] = path
	return { "valid": issues.is_empty(), "issues": issues }


## Re-read the content tree (after new skin resources are written to disk).
static func rescan() -> void:
	_scanned = false
	_ensure_scanned()


# --- internals -------------------------------------------------------------

static func _normalize_ids(ids: Array) -> Dictionary:
	## Owned ids may arrive as String or StringName; index them as Strings for a
	## uniform "in" check.
	var out: Dictionary = {}
	for entry in ids:
		out[String(entry)] = true
	return out


static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	_paths.clear()
	_by_id.clear()
	_scan_dir(CONTENT_ROOT)
	_paths.sort()
	_build_index()


static func _build_index() -> void:
	for path in _paths:
		var res = load(path)
		if not (res is SkinResource):
			continue
		var skin := res as SkinResource
		var skin_id: StringName = skin.id
		if String(skin_id).is_empty():
			continue
		if _by_id.has(skin_id):
			# Two skins claiming one id is a content bug: ownership/equip would be
			# ambiguous. Keep the alphabetically-first path (deterministic) and warn.
			push_warning("SkinLibrary: duplicate skin id '%s' -- keeping %s, ignoring %s. Skin ids must be unique." % [
				String(skin_id), String(_by_id[skin_id]), path])
			continue
		_by_id[skin_id] = path


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
			if res is SkinResource:
				_paths.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
