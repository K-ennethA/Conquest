extends RefCounted
class_name BattleSnapshot

## The SERIALIZER half of mid-battle save/resume: pure, engine-agnostic functions that turn a
## live [Unit] into a plain JSON-safe [Dictionary] and back again. No file I/O, no autoload
## reads, no scene -- [BattleSaveManager] owns all of that. Splitting it this way is what lets
## the round-trip be tested headlessly against a real Unit (or a double) with no map load.
##
## THE FORMAT. One versioned root dictionary; see [constant FORMAT_VERSION]. Everything is a
## JSON primitive: a [Vector2i] is stored as [code][x, y][/code] (see [method cell_to_array]),
## a [StringName] as a String, and a resource as its STABLE id (never a res:// path -- ids
## survive an asset being moved, which is the same reason [TileCatalog] / [StatusCatalog]
## exist). Anything whose id cannot be resolved on the way back in is SKIPPED rather than
## raised: a save written before a content edit must still resume, just without the one thing
## that no longer exists.
##
##     {
##       "format_version": 1,
##       "saved_at_utc_date": "2026-08-02",          # UTC date, for the challenge EOD rule
##       "saved_at_utc": "2026-08-02T14:03:11",      # full stamp, display only
##       "context": {
##         "mode": "skirmish" | "campaign" | "challenge",
##         "map_path": "res://... | user://...",
##         "map_name": "Forgotten Forest",
##         "campaign_chapter_id": "",
##         "challenge_id": "",                        # checksum
##         "challenge": { ... the full challenge dict, re-validated on resume ... },
##         "squad": ["vineweave", ...],
##         "turn_system": 0,                          # TurnSystemBase.TurnSystemType
##         "player_count": 2,
##         "difficulty": 1,                           # BotController.Difficulty
##         "challenge_turns": 0, "challenge_units_lost": 0, "campaign_turns": 0
##       },
##       "units": [ <unit entry -- see capture_unit> ],
##       "turn":  { <turn state -- written by BattleSaveManager> },
##       "board": { <applied tile effects + per-manager state> }
##     }
##
## UNITS ARE ADDRESSED BY INDEX. The "units" array order IS the identity used by every other
## section (the turn queue, the acted lists, a hazard's source). Restore re-spawns in exactly
## that order, so index N in the file is index N on the board.
##
## THE DOUBLE-APPLY RULE (why current stats are NOT stored). A unit's live stats are
## base(CharacterResource) + permanent item deltas + live status modifiers. Storing the RESULT
## and writing it back would double every one of those on resume, because a restored unit is a
## FRESH spawn whose stats are rebuilt from its CharacterResource and whose items/statuses are
## then applied again. So the snapshot stores the INPUTS -- which items are the player's
## business ([ItemInventory], durable) and which statuses are live (id + turns_left) -- and
## restore replays them in the same order the battle did:
##   1. spawn (base stats from the CharacterResource)
##   2. [method ItemSystem.apply_loadout] (permanent deltas; sets its own APPLIED_META latch,
##      so the per-turn sweep that would otherwise re-stamp them no-ops)
##   3. statuses through [method StatusController.add_status] (on_apply re-runs, which is what
##      re-installs a [StatModifierStatus]'s modifier exactly once)
##   4. current HP + shield LAST, so a step above cannot overwrite them.
## The ONE value that genuinely cannot be recomputed -- current HP -- is therefore the only
## stat in the file. Pinned by tests/integration/test_battle_save_restore.gd.

## Bump ONLY on a breaking change; [method is_supported] rejects anything else, and a
## rejected save is deleted rather than half-restored.
const FORMAT_VERSION: int = 1

## The three solo modes a battle can be saved from. Arena is deliberately absent -- a run's
## state lives in [ArenaController], not on the board, so it is excluded at the gate
## ([method BattleSaveManager.can_save_now]) rather than half-serialised here.
const MODE_SKIRMISH := "skirmish"
const MODE_CAMPAIGN := "campaign"
const MODE_CHALLENGE := "challenge"
const MODES: Array[String] = [MODE_SKIRMISH, MODE_CAMPAIGN, MODE_CHALLENGE]

## Turn-state discriminator (mirrors the two live [TurnSystemBase] subclasses).
const TURN_TRADITIONAL := "traditional"
const TURN_SPEED_FIRST := "speed_first"

## Directory scanned for [TileEffectResource]s when a runtime (applied) tile effect is
## resolved back from its id. Flat and stable; see [method tile_effect_by_id].
const TILE_EFFECT_DIR := "res://game/tiles/effects/resources/"

## Cache for [method tile_effect_by_id]: id -> TileEffectResource (built once per process).
static var _tile_effects_by_id: Dictionary = {}
static var _tile_effects_scanned: bool = false


# --- JSON-safe primitives ---------------------------------------------------

## [Vector2i] -> [code][x, y][/code]. JSON has no vector type, and storing a stringified
## "(3, 4)" would need a parser on the way back.
static func cell_to_array(cell: Vector2i) -> Array:
	return [int(cell.x), int(cell.y)]


## The inverse of [method cell_to_array]. Anything malformed reads as [param fallback], so a
## truncated file degrades to a sane cell instead of raising.
static func array_to_cell(value: Variant, fallback: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return fallback


## True when [param snapshot] is a dictionary this build knows how to restore.
static func is_supported(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return false
	if int(snapshot.get("format_version", 0)) != FORMAT_VERSION:
		return false
	if not (snapshot.get("context", null) is Dictionary):
		return false
	if not (snapshot.get("units", null) is Array):
		return false
	return not (snapshot.get("units", []) as Array).is_empty()


## Serialise to pretty JSON (tab-indented, matching the other save files in the project).
static func to_json(snapshot: Dictionary) -> String:
	return JSON.stringify(snapshot, "\t")


## Parse JSON back into a snapshot dictionary. Returns {} for anything that is not a JSON
## object, so every caller treats {} uniformly as "no usable save".
static func from_json(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {}
	# Instance parse, NOT JSON.parse_string: the static helper logs an engine error on
	# malformed input, and a corrupt/hand-edited save is an EXPECTED case here (we recover
	# with "no usable save") - convention #1, and GUT fails on engine errors.
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed if parsed is Dictionary else {}


# --- Capture ----------------------------------------------------------------

## Serialise one living [param unit] standing on [param cell].
##
## [param index] is the unit's position in the snapshot's "units" array and is the id every
## other section refers to it by. Everything is read through duck-typed accessors so a test
## double exposing only part of the [Unit] surface still round-trips.
static func capture_unit(unit, index: int, cell: Vector2i, player_id: int) -> Dictionary:
	var entry: Dictionary = {
		"index": index,
		"character_id": character_id_of(unit),
		"player_id": player_id,
		"cell": cell_to_array(cell),
		# The ONE stat stored -- everything else is recomputed on restore (see class docs).
		"hp": int(unit.get_hp()) if unit.has_method("get_hp") else 0,
		"shield": int(unit.get_shield()) if unit.has_method("get_shield") else 0,
		"facing_yaw": float(unit.facing_yaw) if "facing_yaw" in unit else 0.0,
		"has_acted": bool(unit.has_acted_this_turn) if "has_acted_this_turn" in unit else false,
		"has_moved": bool(unit.has_moved_this_turn) if "has_moved_this_turn" in unit else false,
		"provoked": bool(unit.provoked) if "provoked" in unit else false,
		"extra_actions": int(unit.arena_extra_actions) if "arena_extra_actions" in unit else 0,
		"ai_stance": String(unit.get_ai_stance()) if unit.has_method("get_ai_stance") else "",
		"home_cell": cell_to_array(unit.get_home_cell() if unit.has_method("get_home_cell") else cell),
		"aggro_range": int(unit.get_aggro_range()) if unit.has_method("get_aggro_range") else -1,
		"leash_radius": int(unit.get_leash_radius()) if unit.has_method("get_leash_radius") else -1,
		"statuses": capture_statuses(unit),
		"moves": capture_moveset(unit),
	}
	return entry


## The backing roster id for [param unit] ("" for a legacy scene-authored unit with no
## [CharacterResource] -- such a unit cannot be re-spawned and is skipped on restore).
static func character_id_of(unit) -> String:
	if unit == null:
		return ""
	if "character_resource" in unit and unit.character_resource != null:
		return String(unit.character_resource.character_id)
	return ""


## Every live status on [param unit] as [code]{id, turns_left}[/code], in application order.
##
## turns_left (not duration_turns) is what is stored: it is the remaining time, which is the
## only thing that cannot be re-derived. -1 means permanent.
static func capture_statuses(unit) -> Array:
	var out: Array = []
	var controller = unit.get_status_controller() if unit != null and unit.has_method("get_status_controller") else null
	if controller == null or not controller.has_method("get_active"):
		return out
	for condition in controller.get_active():
		if condition == null:
			continue
		var id: String = String(condition.id)
		if id.is_empty():
			continue
		out.append({ "id": id, "turns_left": int(condition.turns_left) })
	return out


## [MovesetController] state for [param unit]: remaining cooldowns and charges already spent.
static func capture_moveset(unit) -> Dictionary:
	var controller = unit.get_moveset_controller() if unit != null and unit.has_method("get_moveset_controller") else null
	if controller == null or not controller.has_method("snapshot_state"):
		return {}
	return controller.snapshot_state()


# --- Restore ----------------------------------------------------------------

## Re-apply the parts of [param entry] that do NOT depend on the item/status replay: AI
## behaviour, facing, and the per-turn action flags. Called FIRST, before items and statuses.
##
## HP and shield are deliberately NOT set here -- see [method apply_unit_vitals], which the
## caller runs LAST so nothing downstream can overwrite them.
static func apply_unit_core(unit, entry: Dictionary) -> void:
	if unit == null:
		return
	if unit.has_method("configure_ai_behavior"):
		unit.configure_ai_behavior(
			array_to_cell(entry.get("home_cell", []), Vector2i(-1, -1)),
			String(entry.get("ai_stance", "")),
			int(entry.get("aggro_range", -1)),
			int(entry.get("leash_radius", -1)))
	if "provoked" in unit:
		unit.provoked = bool(entry.get("provoked", false))
	if "arena_extra_actions" in unit:
		unit.arena_extra_actions = int(entry.get("extra_actions", 0))
	if unit.has_method("set_facing_yaw"):
		unit.set_facing_yaw(float(entry.get("facing_yaw", 0.0)))
	apply_unit_turn_flags(unit, entry)


## Re-assert the per-turn action flags. Split out from [method apply_unit_core] because BOTH
## turn systems clear them when a turn starts ([code]reset_all_unit_actions[/code] /
## [code]reset_turn_actions[/code]) -- so they have to be written again AFTER the turn state
## is restored, or a unit that had already acted would get a free second action on resume.
static func apply_unit_turn_flags(unit, entry: Dictionary) -> void:
	if unit == null:
		return
	if "has_acted_this_turn" in unit:
		unit.has_acted_this_turn = bool(entry.get("has_acted", false))
	if "has_moved_this_turn" in unit:
		unit.has_moved_this_turn = bool(entry.get("has_moved", false))


## Re-install every saved status through the REAL application path
## ([method StatusController.add_status]), so each condition's on_apply runs exactly once --
## which is what re-installs a [StatModifierStatus]'s stat modifier on a unit whose stats were
## just rebuilt from base. Returns how many were restored.
##
## The saved [code]turns_left[/code] is written onto the duplicate's
## [member StatusCondition.duration_turns] because add_status seeds
## [code]turns_left = duration_turns[/code] for a newly added instance. That override lives
## ONLY on this instance -- a later re-inflict resolves a FRESH copy from the catalog, so the
## condition's authored duration is never permanently rewritten.
##
## An id the catalog cannot resolve is SKIPPED, not raised. The item channels
## ([constant ItemSystem.REGEN_STATUS_ID] / [constant ItemSystem.WARD_STATUS_ID]) are built in
## code rather than authored as .tres, so they land here -- and that is correct: the loadout
## replay in step 2 has already re-installed them from the player's live inventory.
static func apply_unit_statuses(unit, entry: Dictionary) -> int:
	if unit == null:
		return 0
	var controller = unit.get_status_controller() if unit.has_method("get_status_controller") else null
	if controller == null or not controller.has_method("add_status"):
		return 0
	var restored: int = 0
	var raw: Variant = entry.get("statuses", [])
	if not (raw is Array):
		return 0
	for item in raw as Array:
		if not (item is Dictionary):
			continue
		var id: StringName = StringName(String((item as Dictionary).get("id", "")))
		if String(id).is_empty():
			continue
		var authored: StatusCondition = StatusCatalog.find_by_id(id)
		if authored == null:
			continue  # code-built or removed condition -- see the doc comment above
		var instance: StatusCondition = authored.duplicate(true)
		instance.duration_turns = int((item as Dictionary).get("turns_left", instance.duration_turns))
		controller.add_status(instance)
		restored += 1
	return restored


## Re-install saved move cooldowns / spent charges onto [param unit]'s [MovesetController].
static func apply_unit_moves(unit, entry: Dictionary) -> void:
	if unit == null:
		return
	var controller = unit.get_moveset_controller() if unit.has_method("get_moveset_controller") else null
	if controller == null or not controller.has_method("restore_state"):
		return
	var state: Variant = entry.get("moves", {})
	if state is Dictionary:
		controller.restore_state(state as Dictionary)


## Write current HP and shield. Called LAST in the restore order (see class docs): the item
## replay raises max health and the status replay can shift stats, and both would otherwise
## land on top of the saved value.
static func apply_unit_vitals(unit, entry: Dictionary) -> void:
	if unit == null:
		return
	var hp: int = int(entry.get("hp", 0))
	if hp > 0 and unit.has_method("set_stat"):
		unit.set_stat("health", hp)
	var shield: int = int(entry.get("shield", 0))
	if shield > 0 and unit.has_method("grant_shield"):
		unit.grant_shield(shield)


# --- Tile effect id resolution ----------------------------------------------

## Resolve a runtime (applied) tile effect back from its stable
## [member TileEffectResource.id]. Falls back to the [TileEffectLibrary] code factories for
## the built-in terrain effects, so a missing .tres still resumes. Null when unknown.
static func tile_effect_by_id(id: StringName):
	if String(id).is_empty():
		return null
	_ensure_tile_effects_scanned()
	var found = _tile_effects_by_id.get(id, null)
	if found != null:
		return found
	match id:
		&"fire":
			return TileEffectLibrary.fire()
		&"water", &"empowering_water":
			return TileEffectLibrary.empowering_water()
		&"fortify":
			return TileEffectLibrary.fortify()
		&"stealth":
			return TileEffectLibrary.stealth()
	return null


## Drop the tile-effect index (tests that write new effect resources call this).
static func rescan_tile_effects() -> void:
	_tile_effects_scanned = false
	_tile_effects_by_id.clear()


static func _ensure_tile_effects_scanned() -> void:
	if _tile_effects_scanned:
		return
	_tile_effects_scanned = true
	var dir := DirAccess.open(TILE_EFFECT_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			var path: String = TILE_EFFECT_DIR + entry
			if ResourceLoader.exists(path):
				var res = load(path)
				if res is TileEffectResource and not String((res as TileEffectResource).id).is_empty():
					_tile_effects_by_id[(res as TileEffectResource).id] = res
		entry = dir.get_next()
	dir.list_dir_end()
