@tool
extends Resource

class_name MapResource

# Resource for storing map configurations and layouts
# Used by the Map Creator tool and map loading system

@export var map_name: String = ""
@export var description: String = ""
@export var author: String = ""
@export var version: String = "1.0"

## Publication state. "Active" maps are offered to players in the map-selection
## screens; "Inactive" ones are work-in-progress drafts that save freely but stay
## out of the player-facing lists (see [method MapLoader.get_available_maps]).
## Defaults to "Active" so maps authored before this field existed keep showing up.
@export_enum("Active", "Inactive") var status: String = "Active"

# Map Dimensions
@export var width: int = 5
@export var height: int = 5

# Map Layout Data
@export var tile_layout: Array[Dictionary] = []  # Array of TILE ENTRIES - see the schema block below
# A tile_layout entry names which terrain occupies one cell. Every key past
# "position" is optional and read through .get(), so maps authored before a key
# existed keep loading unchanged:
#
#   position           Vector2i  the cell this entry occupies
#   tile_id            String    STABLE TileResource id (see TileResource.id) --
#                                the PREFERRED reference and the durable one
#   tile_resource_path String    res:// path to the .tres, LEGACY/fallback
#   tile_type          String    Tile.TileType enum name, coarse last-resort hint
#
# NOTE on "tile_id" vs "tile_resource_path": a path breaks the moment the asset is
# moved or renamed, and maps are authored by PLAYERS and SHARED, so a map must keep
# resolving on an install where the tiles were reorganised. The id never changes,
# so it is what MapLoader tries first (see MapLoader._resolve_tile_resource).
# "tile_resource_path" is still written by the authoring tools for back-compat with
# anything that reads it, and is still honoured when a map carries no tile_id.
@export var unit_spawns: Array[Dictionary] = []  # Array of SPAWN POINTS - see the schema block below
# A unit_spawns entry is a SPAWN POINT: a position, the player slot that owns it,
# and what kind of spawning it does. Full schema (every key past "position" and
# "player_id" is optional and read through .get(), so maps authored before a key
# existed keep loading unchanged - see [method normalize_spawn]):
#
#   position           Vector2i  the cell this point occupies
#   player_id          int       owning player slot (0-based)
#   spawn_kind         String    "Start" / "Respawn" / "Endless" / "Reinforcement"
#                                (default "Start" - i.e. exactly the old behaviour)
#   unit_type          String    legacy class hint, OPTIONAL
#   character_id       String    roster CharacterResource id, OPTIONAL
#   unit_resource_path String    explicit resource override, OPTIONAL
#   max_spawns         int       units this point may ever produce, -1 = unlimited
#                                (default 1, or -1 for "Endless")
#   respawn_interval   int       turns between spawns for Respawn/Endless (default 1)
#   spawn_turn         int       turn a Reinforcement point activates (default 1)
#   ai_stance          String    "" (inherit character default) / "aggressive" /
#                                "defensive". Aggressive units chase the nearest
#                                enemy; defensive units hold and only engage once a
#                                hostile enters aggro_range of their home cell.
#   aggro_range        int       defensive wake distance (Manhattan) from the home
#                                cell, or -1 to inherit the character default
#   leash_radius       int       max cells the spawned unit will ever move from its
#                                home cell (caps pursuit / anchors a boss), or -1 to
#                                inherit the character default. A RESOLVED value < 0
#                                means untethered (see Unit.configure_ai_behavior).
#
# NOTE on "character_id": preferred over "unit_type" when set - it names a
# CharacterResource id under res://game/characters/roster/ (see CharacterLibrary).
# "unit_type" is kept for back-compat with maps authored before the character system
# (MapLoader maps legacy WARRIOR/ARCHER/MAGE strings to a roster id).
# The unit reference is OPTIONAL: a "Start" point with none is an EMPTY SLOT to be
# filled at match setup; the spawner kinds use it to say WHAT they spawn.

# --- Push-mode geometry: lanes + bases ----------------------------------------
# Both are OPTIONAL and EMPTY BY DEFAULT, so every map authored before they existed
# stays valid and round-trips byte for byte. Only a map that actually declares them
# pays for them, and only a map that declares them BADLY is rejected.

## LANE ROUTES -- the ordered paths a push mode's waves walk between the two bases.
##
## Each entry is ONE lane: an [code]Array[/code] of [Vector2i] WAYPOINTS ordered from
## PLAYER 0's SIDE TOWARD PLAYER 1's. That direction is the whole contract: a consumer
## reads the FIRST waypoint as player 0's lane head and the LAST as player 1's, and
## walks the list forwards for player 0's wave and backwards for player 1's -- so a lane
## is authored ONCE and both sides read the same cells. See [method get_lane] and
## [method lane_head].
##
## Deliberately an untyped [Array]: Godot 4 cannot express an exported
## [code]Array[Array[Vector2i]][/code], and a JSON-parsed plain Array could not be
## assigned to one anyway (CONQUEST.md rule 3). Read a lane through [method get_lane],
## which coerces element-wise, rather than indexing [member lanes] raw.
@export var lanes: Array = []

## BASE CELLS -- player slot ([int]) -> the cell ([Vector2i]) that player's base stands on.
##
## The map's own statement of "this is where player N's base is", independent of which
## unit happens to be spawned there, so a mode can reason about bases (distance to,
## proximity auras, wave targets) without pattern-matching spawn entries. Authoring it
## does NOT place anything: a map that wants a destructible base still spawns the
## structure, and the two should agree.
##
## Keys are player slots that must actually EXIST on this map (own at least one spawn
## point); values must be in-bounds cells. Empty = the map declares no bases, which is
## every map that is not a base-assault / push map.
@export var base_cells: Dictionary = {}

## CONTROL POINTS -- the cells a mode may let a side CLAIM and hold (a captured midpoint
## that spawns grunts, heals, or pays a timed augment).
##
## An [code]Array[/code] of [Vector2i]. Deliberately UNOWNED and UNORDERED: the map states
## only WHERE the contested cells are, exactly as [member base_cells] states where the bases
## are. Who holds one, what holding it grants, and how long it takes to flip are the MODE's
## business (CONQUEST.md rule 11 -- a mode's tuning lives on that mode's ruleset resource),
## so a map does not have to be re-authored when a mode retunes its objective.
##
## Deliberately an untyped [Array] for the same reason [member lanes] is: a JSON-parsed plain
## Array cannot be assigned to a typed one (CONQUEST.md rule 3). Read it through
## [method get_control_points], which coerces element-wise.
##
## OPTIONAL and EMPTY BY DEFAULT, so every map authored before this field existed stays valid
## and round-trips unchanged. A declared point must be an in-bounds cell (structural) and, at
## catalog-strict validation, must stand on WALKABLE ground -- a point inside a wall could
## never be captured.
@export var control_points: Array = []


# --- Spawn kinds --------------------------------------------------------------
const SPAWN_KIND_START := "Start"                  # places one unit at map load
const SPAWN_KIND_RESPAWN := "Respawn"              # replaces its unit every N turns
const SPAWN_KIND_ENDLESS := "Endless"              # respawns forever (max_spawns -1)
const SPAWN_KIND_REINFORCEMENT := "Reinforcement"  # activates on spawn_turn

const SPAWN_KINDS: Array[String] = [
	SPAWN_KIND_START, SPAWN_KIND_RESPAWN, SPAWN_KIND_ENDLESS, SPAWN_KIND_REINFORCEMENT
]

# Size guardrails for shareable, player-authored maps. Kept as constants so the
# Map Creator's SpinBoxes and validate_map() can never drift apart.
const MIN_MAP_SIZE := 3
## Soft ceiling on a map's width/height. Raise it here (the single source) to allow
## larger maps -- the Map Creator's SpinBoxes and validate_map() both read this, so
## they can never drift apart. Larger values grow the editor grid (WxH buttons +
## tile meshes) so keep it within what the creator dock stays responsive at.
const MAX_MAP_SIZE := 40

# Map Properties
@export var max_players: int = 2
@export var recommended_players: int = 2
@export var difficulty: String = "Normal"  # Easy, Normal, Hard, Expert
@export var map_type: String = "Skirmish"  # Skirmish, Campaign, Custom

# Visual Properties
@export var environment_preset: String = "Default"  # Default, Desert, Forest, Snow, Volcanic
@export var lighting_preset: String = "Day"  # Day, Night, Dawn, Dusk
@export var background_color: Color = Color(0.2, 0.2, 0.3, 1.0)

# Gameplay Properties
@export var turn_limit: int = 0  # 0 = no limit
@export var victory_conditions: Array[String] = ["Eliminate All Enemies"]
@export var special_rules: Array[String] = []

# Metadata
@export var creation_date: String = ""
@export var last_modified: String = ""
@export var tags: Array[String] = []
@export var preview_image_path: String = ""

func _init():
	resource_name = "MapResource"
	creation_date = Time.get_datetime_string_from_system()
	last_modified = creation_date

func get_map_size() -> Vector2i:
	"""Get map dimensions as Vector2i"""
	return Vector2i(width, height)

func get_tile_at_position(pos: Vector2i) -> Dictionary:
	"""Get tile data at specific position"""
	for tile_data in tile_layout:
		if tile_data.get("position", Vector2i(-1, -1)) == pos:
			return tile_data
	
	# Return default tile if not found
	return {
		"position": pos,
		"tile_type": "NORMAL",
		"tile_resource_path": "",
		"tile_id": ""
	}

func set_tile_at_position(pos: Vector2i, tile_type: String, tile_resource_path: String = "", tile_id = "") -> void:
	"""Set tile data at specific position.

	[param tile_id] is the STABLE [member TileResource.id] and is what makes the
	entry survive the asset being moved or renamed - always pass it when the tile
	is known. It is an optional TRAILING parameter so every existing two- and
	three-argument caller keeps working unchanged; those entries simply store an
	empty tile_id and resolve through the legacy path (see the schema block above).
	Accepts a String or a StringName.
	"""
	# Remove existing tile at position
	for i in range(tile_layout.size() - 1, -1, -1):
		if tile_layout[i].get("position", Vector2i(-1, -1)) == pos:
			tile_layout.remove_at(i)
	
	# Add new tile data
	tile_layout.append({
		"position": pos,
		"tile_type": tile_type,
		"tile_resource_path": tile_resource_path,
		"tile_id": String(tile_id)
	})

func get_unit_spawn_at_position(pos: Vector2i) -> Dictionary:
	"""Get the RAW spawn point entry at a position, or {} when there is none.

	Deliberately raw (not normalized): callers rely on the empty dictionary meaning
	"no spawn here". Pass the result through [method normalize_spawn] when you need
	the optional keys filled in.
	"""
	for spawn_data in unit_spawns:
		if spawn_data.get("position", Vector2i(-1, -1)) == pos:
			return spawn_data

	return {}

func get_spawn_kind(spawn_data: Dictionary) -> String:
	"""Spawn kind of an entry, defaulting to "Start" for maps authored before the
	key existed (and for any unrecognised value)."""
	var kind: String = str(spawn_data.get("spawn_kind", SPAWN_KIND_START))
	if not SPAWN_KINDS.has(kind):
		return SPAWN_KIND_START
	return kind

func get_default_max_spawns(spawn_kind: String) -> int:
	"""Default [code]max_spawns[/code] for a kind: unlimited for Endless, one otherwise."""
	return -1 if spawn_kind == SPAWN_KIND_ENDLESS else 1

func normalize_spawn(spawn_data: Dictionary) -> Dictionary:
	"""Return a copy of a spawn point entry with every optional key filled in.

	This is the ONE place spawn defaults live, so old maps (which carry none of the
	newer keys) and freshly authored ones are read through identical rules.
	"""
	var kind: String = get_spawn_kind(spawn_data)
	var normalized: Dictionary = {
		"position": spawn_data.get("position", Vector2i(-1, -1)),
		"player_id": int(spawn_data.get("player_id", 0)),
		"unit_type": str(spawn_data.get("unit_type", "")),
		"unit_resource_path": str(spawn_data.get("unit_resource_path", "")),
		"character_id": str(spawn_data.get("character_id", "")),
		"spawn_kind": kind,
		"max_spawns": int(spawn_data.get("max_spawns", get_default_max_spawns(kind))),
		"respawn_interval": int(spawn_data.get("respawn_interval", 1)),
		"spawn_turn": int(spawn_data.get("spawn_turn", 1)),
		"ai_stance": str(spawn_data.get("ai_stance", "")),
		"aggro_range": int(spawn_data.get("aggro_range", -1)),
		"leash_radius": int(spawn_data.get("leash_radius", -1))
	}
	return normalized

func spawn_has_unit_reference(spawn_data: Dictionary) -> bool:
	"""True when an entry names WHAT to spawn (character id, legacy type or path).

	False means an unassigned slot - legitimate for a "Start" point (filled at match
	setup), but broken for a spawner kind, which has nothing to produce.
	"""
	var normalized: Dictionary = normalize_spawn(spawn_data)
	return not (String(normalized["character_id"]).is_empty()
		and String(normalized["unit_type"]).is_empty()
		and String(normalized["unit_resource_path"]).is_empty())

func is_initial_spawn(spawn_data: Dictionary) -> bool:
	"""True when this point places a unit at MAP LOAD time.

	Start points obviously do; Respawn/Endless points seed their first unit up front
	too. Only a Reinforcement scheduled past turn 1 stays empty until its turn comes.
	"""
	if get_spawn_kind(spawn_data) != SPAWN_KIND_REINFORCEMENT:
		return true
	return int(spawn_data.get("spawn_turn", 1)) <= 1

func set_spawn_point_at_position(pos: Vector2i, player_id: int, spawn_kind: String, opts: Dictionary = {}) -> void:
	"""Write a spawn POINT at a position - the primary authoring entry point.

	A point is a position + owning player slot + kind. [param opts] optionally carries
	[code]unit_type[/code], [code]character_id[/code], [code]unit_resource_path[/code],
	[code]max_spawns[/code], [code]respawn_interval[/code] and [code]spawn_turn[/code];
	anything omitted falls back to the schema defaults.
	"""
	# Remove existing spawn at position
	for i in range(unit_spawns.size() - 1, -1, -1):
		if unit_spawns[i].get("position", Vector2i(-1, -1)) == pos:
			unit_spawns.remove_at(i)

	var kind: String = spawn_kind
	if not SPAWN_KINDS.has(kind):
		kind = SPAWN_KIND_START

	# Add new spawn data
	unit_spawns.append({
		"position": pos,
		"player_id": player_id,
		"unit_type": str(opts.get("unit_type", "")),
		"unit_resource_path": str(opts.get("unit_resource_path", "")),
		"character_id": str(opts.get("character_id", "")),
		"spawn_kind": kind,
		"max_spawns": int(opts.get("max_spawns", get_default_max_spawns(kind))),
		"respawn_interval": maxi(1, int(opts.get("respawn_interval", 1))),
		"spawn_turn": maxi(1, int(opts.get("spawn_turn", 1))),
		"ai_stance": str(opts.get("ai_stance", "")),
		"aggro_range": int(opts.get("aggro_range", -1)),
		"leash_radius": int(opts.get("leash_radius", -1))
	})

func set_unit_spawn_at_position(pos: Vector2i, player_id: int, unit_type: String, unit_resource_path: String = "", character_id: String = "") -> void:
	"""Set a plain "Start" spawn point at a position.

	Kept for the many existing callers; delegates to [method set_spawn_point_at_position].
	[param character_id] names a CharacterResource id (see CharacterLibrary) and takes
	priority over [param unit_type] when loading. [param unit_type] is kept for
	back-compat with legacy (pre-character) maps and as a display/authoring hint.
	"""
	set_spawn_point_at_position(pos, player_id, SPAWN_KIND_START, {
		"unit_type": unit_type,
		"unit_resource_path": unit_resource_path,
		"character_id": character_id
	})


func set_character_spawn_at_position(pos: Vector2i, player_id: int, character_id: String, unit_type: String = "") -> void:
	"""Convenience wrapper for authoring character-backed spawns directly.

	Equivalent to [method set_unit_spawn_at_position] with the [param character_id]
	and [param unit_type] arguments swapped to the front, since character-backed
	spawns are the primary authoring path going forward.
	"""
	set_unit_spawn_at_position(pos, player_id, unit_type, "", character_id)


func get_character_id_at_position(pos: Vector2i) -> String:
	"""Get the character_id (if any) of the spawn at a specific position"""
	return get_unit_spawn_at_position(pos).get("character_id", "")

func remove_unit_spawn_at_position(pos: Vector2i) -> void:
	"""Remove unit spawn at specific position"""
	for i in range(unit_spawns.size() - 1, -1, -1):
		if unit_spawns[i].get("position", Vector2i(-1, -1)) == pos:
			unit_spawns.remove_at(i)

func get_player_spawn_positions(player_id: int, spawn_kind: String = "") -> Array[Vector2i]:
	"""Get all spawn positions for a specific player.

	Pass [param spawn_kind] to keep only points of that kind (e.g. "Start" for the
	slots a match-setup screen should offer); the default "" returns every point.
	"""
	var positions: Array[Vector2i] = []
	for spawn_data in unit_spawns:
		if spawn_data.get("player_id", -1) != player_id:
			continue
		if not spawn_kind.is_empty() and get_spawn_kind(spawn_data) != spawn_kind:
			continue
		positions.append(spawn_data.get("position", Vector2i(-1, -1)))
	return positions

func get_spawn_kind_counts() -> Dictionary:
	"""How many points of each kind this map defines, e.g. {"Start": 6, "Endless": 1}.

	Every kind is present (zeroed) so UIs can lay out a fixed set of rows.
	"""
	var counts: Dictionary = {}
	for kind in SPAWN_KINDS:
		counts[kind] = 0
	for spawn_data in unit_spawns:
		var kind_name: String = get_spawn_kind(spawn_data)
		counts[kind_name] = int(counts.get(kind_name, 0)) + 1
	return counts

func get_total_units_for_player(player_id: int) -> int:
	"""Get total number of units for a specific player"""
	var count = 0
	for spawn_data in unit_spawns:
		if spawn_data.get("player_id", -1) == player_id:
			count += 1
	return count

# --- Lanes + bases: reading ---------------------------------------------------

## How many lanes this map declares (0 for every map that declares none).
func lane_count() -> int:
	return lanes.size()


## Lane [param index] as a typed [code]Array[Vector2i][/code] of waypoints, ordered from
## player 0's side toward player 1's. Out-of-range index (or a lane that is not a list)
## returns an empty array rather than erroring -- reading a lane a map does not have is
## an ordinary "no lane here" answer, not a fault.
##
## THIS is the accessor to use, never [code]lanes[index][/code] raw: a lane that came
## back from JSON is a plain Array of decoded cells, and assigning that to a typed local
## is a runtime error (CONQUEST.md rule 3). The coercion lives here, once.
func get_lane(index: int) -> Array[Vector2i]:
	if index < 0 or index >= lanes.size():
		return [] as Array[Vector2i]
	return _to_cell_array(lanes[index])


## The end of lane [param index] that belongs to [param player_id]: the FIRST waypoint
## for player 0, the LAST for anybody else (see [member lanes] for why that is the whole
## contract). [code]Vector2i(-1, -1)[/code] when there is no such lane.
func lane_head(index: int, player_id: int) -> Vector2i:
	var lane: Array[Vector2i] = get_lane(index)
	if lane.is_empty():
		return Vector2i(-1, -1)
	return lane[0] if player_id == 0 else lane[lane.size() - 1]


## Append a lane, coerced to a typed waypoint list. The primary authoring entry point.
func add_lane(waypoints: Array) -> void:
	lanes.append(_to_cell_array(waypoints))


## [param player_id]'s base cell, or [code]Vector2i(-1, -1)[/code] when the map declares none.
func get_base_cell(player_id: int) -> Vector2i:
	if not base_cells.has(player_id):
		return Vector2i(-1, -1)
	var value = base_cells[player_id]
	return value if value is Vector2i else Vector2i(-1, -1)


## Record [param player_id]'s base cell. The primary authoring entry point.
func set_base_cell(player_id: int, cell: Vector2i) -> void:
	base_cells[player_id] = cell


# --- Control points: reading + authoring --------------------------------------

## How many control points this map declares (0 for every map that declares none).
func control_point_count() -> int:
	return control_points.size()


## Every declared control point as a typed [code]Array[Vector2i][/code]. THIS is the accessor
## to use, never [member control_points] raw: a list that came back from JSON is a plain Array
## of decoded cells, and assigning that to a typed local is a runtime error (CONQUEST.md
## rule 3). The coercion lives here, once.
func get_control_points() -> Array[Vector2i]:
	return _to_cell_array(control_points)


## Control point [param index], or [code]Vector2i(-1, -1)[/code] when there is no such point --
## reading a point a map does not have is an ordinary answer, not a fault (matches
## [method get_lane] / [method get_base_cell]).
func get_control_point(index: int) -> Vector2i:
	if index < 0 or index >= control_points.size():
		return Vector2i(-1, -1)
	return _decode_position(control_points[index])


## Append a control point. The primary authoring entry point.
func add_control_point(cell: Vector2i) -> void:
	control_points.append(cell)


## True when [param cell] is one of this map's declared control points.
func has_control_point(cell: Vector2i) -> bool:
	for point in get_control_points():
		if point == cell:
			return true
	return false


## Every player slot that owns at least one spawn point on this map -- the set a base
## cell (and any other per-player declaration) has to name.
func spawn_player_ids() -> Array[int]:
	var seen: Dictionary = {}
	var out: Array[int] = []
	for spawn_data in unit_spawns:
		if not (spawn_data is Dictionary):
			continue
		var player_id: int = int((spawn_data as Dictionary).get("player_id", -1))
		if player_id < 0 or seen.has(player_id):
			continue
		seen[player_id] = true
		out.append(player_id)
	out.sort()
	return out


## Convert any waypoint list -- authored [Vector2i]s, or the plain dictionaries/arrays a
## JSON round-trip produces -- into the typed [code]Array[Vector2i][/code] callers need.
## Mirrors [method _to_string_array]: a plain Array cannot be assigned to a typed one, so
## the conversion is element-wise (CONQUEST.md rule 3). Junk decodes to
## [code]Vector2i(-1, -1)[/code], which validation then rejects as out of bounds rather
## than silently dropping it.
static func _to_cell_array(raw) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if raw is Array:
		for v in raw:
			out.append(_decode_position(v))
	return out


func validate_map(strict_catalog: bool = false) -> Dictionary:
	"""Validate map configuration.

	This is the ONE authoritative validator for a map. [param strict_catalog]
	additionally resolves every tile_id / character_id the map references against
	the live [TileCatalog] / [CharacterLibrary], so a SHARED map that names an asset
	this install does not have fails loudly instead of silently substituting a
	default. Left [code]false[/code] for the many in-editor / in-game callers that
	only want the structural + playability checks, so their behaviour is unchanged.
	"""
	var issues: Array[String] = []
	var warnings: Array[String] = []

	# Check required fields
	if map_name.is_empty():
		issues.append("Map name is required")
	
	# Check dimensions
	if width < MIN_MAP_SIZE or width > MAX_MAP_SIZE:
		issues.append("Map width should be between %d and %d" % [MIN_MAP_SIZE, MAX_MAP_SIZE])

	if height < MIN_MAP_SIZE or height > MAX_MAP_SIZE:
		issues.append("Map height should be between %d and %d" % [MIN_MAP_SIZE, MAX_MAP_SIZE])

	# Check player spawns
	var player_counts = {}
	for spawn_data in unit_spawns:
		var player_id = spawn_data.get("player_id", -1)
		if player_id >= 0:
			player_counts[player_id] = player_counts.get(player_id, 0) + 1
	
	if player_counts.size() < 2:
		issues.append("Map needs at least 2 players with unit spawns")
	
	# Check for balanced spawns
	var spawn_counts = player_counts.values()
	if spawn_counts.size() > 1:
		var min_spawns = spawn_counts.min()
		var max_spawns = spawn_counts.max()
		if max_spawns - min_spawns > 2:
			warnings.append("Unbalanced unit spawns between players")
	
	# Check for valid positions
	for tile_data in tile_layout:
		var pos = tile_data.get("position", Vector2i(-1, -1))
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			issues.append("Tile position out of bounds: " + str(pos))
	
	for spawn_data in unit_spawns:
		var pos = spawn_data.get("position", Vector2i(-1, -1))
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			issues.append("Unit spawn position out of bounds: " + str(pos))

	# Spawn point sanity. Only genuinely broken configurations are issues: a bare
	# "Start" point is FINE (it is an empty slot filled at match setup), but a
	# respawning point with nothing to spawn can never do its job.
	for spawn_data in unit_spawns:
		var normalized: Dictionary = normalize_spawn(spawn_data)
		var kind: String = String(normalized["spawn_kind"])
		var spawn_pos = normalized["position"]

		var is_spawner: bool = kind == SPAWN_KIND_RESPAWN or kind == SPAWN_KIND_ENDLESS
		if is_spawner and not spawn_has_unit_reference(spawn_data):
			issues.append("Spawn point at %s is a %s point - a respawning point must specify which unit it spawns" % [str(spawn_pos), kind])

		if int(normalized["respawn_interval"]) < 1:
			issues.append("Spawn point at %s has a respawn interval below 1 turn" % str(spawn_pos))

	# Lanes + base cells + control points. STRUCTURAL (not strict-only), for the same reason
	# the out-of-bounds checks above are: a waypoint outside the board is broken on every
	# install, not just on one that is missing an asset. Costs nothing for the maps that
	# declare none -- every loop runs zero times.
	_append_lane_and_base_issues(issues)
	_append_control_point_issues(issues)

	# Optional catalog resolution pass. Only NON-EMPTY references are checked: an
	# empty tile_id / character_id is a legitimate "resolve me by type / legacy
	# alias" and is handled by MapLoader, so it is never an issue here.
	if strict_catalog:
		_append_catalog_issues(issues)
		_append_terrain_placement_issues(issues)

	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"warnings": warnings
	}


func _append_lane_and_base_issues(issues: Array[String]) -> void:
	"""Flag every structurally broken [member lanes] / [member base_cells] declaration.

	The rules, and why each one is a HARD issue rather than a warning: a consumer walks a
	lane cell by cell and indexes a base cell straight into the board, so anything that is
	not an in-bounds cell would fault at the first step. A map is player-authored and
	SHARED, so the failure has to happen at the gate (import returns null, quietly) rather
	than mid-match.

	  * a lane that is not a list of waypoints -- nothing to walk;
	  * a lane with NO waypoints -- declaring a lane and giving it no route is the one
	    case that reads as an authoring slip rather than "this map has no lanes"
	    (which is the empty [member lanes] array, and is always fine);
	  * a waypoint that is not an in-bounds cell;
	  * a base cell keyed on anything but a player slot that EXISTS on this map (owns at
	    least one spawn point) -- a base for nobody has no owner to win or lose it;
	  * a base cell that is not an in-bounds cell.

	Every map that declares neither costs two zero-iteration loops, so nothing that shipped
	before these fields existed can change verdict.
	"""
	for i in range(lanes.size()):
		var raw = lanes[i]
		if not (raw is Array):
			issues.append("Lane %d is not a list of waypoints" % i)
			continue
		var lane: Array = raw
		if lane.is_empty():
			issues.append("Lane %d has no waypoints" % i)
			continue
		for waypoint in lane:
			if not (waypoint is Vector2i):
				issues.append("Lane %d waypoint is not a cell: %s" % [i, str(waypoint)])
				continue
			var cell: Vector2i = waypoint
			if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= height:
				issues.append("Lane %d waypoint out of bounds: %s" % [i, str(cell)])

	if base_cells.is_empty():
		return
	var known: Array[int] = spawn_player_ids()
	for key in base_cells.keys():
		if typeof(key) != TYPE_INT:
			issues.append("Base cell is keyed on '%s', which is not a player slot" % str(key))
			continue
		var player_id: int = int(key)
		if not known.has(player_id):
			issues.append("Base cell names player %d, who has no spawns on this map" % player_id)
			continue
		var value = base_cells[key]
		if not (value is Vector2i):
			issues.append("Base cell for player %d is not a cell: %s" % [player_id, str(value)])
			continue
		var base_cell: Vector2i = value
		if base_cell.x < 0 or base_cell.x >= width or base_cell.y < 0 or base_cell.y >= height:
			issues.append("Base cell for player %d out of bounds: %s" % [player_id, str(base_cell)])


func _append_control_point_issues(issues: Array[String]) -> void:
	"""Flag every structurally broken [member control_points] declaration.

	The rules, and why each one is a HARD issue:

	  * a point that is not a cell, or not an IN-BOUNDS cell -- a mode indexes it straight
	    into the board to ask who is standing on it, so anything else faults at the first tick;
	  * the SAME cell declared twice -- a duplicate is scored, contested and rewarded twice
	    over from one square of ground, which reads as an authoring slip rather than an
	    intention. There is no legitimate map that wants it.

	The WALKABLE check deliberately is NOT here: it needs the tile layout resolved through the
	live [TileCatalog], so it rides with the other placement checks in
	[method _append_terrain_placement_issues] (catalog-strict only), exactly as the "a spawn
	must not sit in a wall" backstop does.

	Empty [member control_points] -- every map authored before the field existed -- runs this
	loop zero times and cannot change verdict.
	"""
	if control_points.is_empty():
		return
	var seen: Dictionary = {}
	for i in range(control_points.size()):
		var raw = control_points[i]
		if not (raw is Vector2i):
			issues.append("Control point %d is not a cell: %s" % [i, str(raw)])
			continue
		var cell: Vector2i = raw
		if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= height:
			issues.append("Control point %d out of bounds: %s" % [i, str(cell)])
			continue
		if seen.has(cell):
			issues.append("Control point %s is declared twice" % str(cell))
			continue
		seen[cell] = true


func _append_terrain_placement_issues(issues: Array[String]) -> void:
	"""Flag any unit spawn or objective/throne marker sitting on impassable terrain (a
	wall, a tree, ...). This is the BACKSTOP for the live Map Creator's placement guard
	(MapMakerScene refuses these at paint/place time) -- a hand-edited or shared JSON map
	can still smuggle an invalid placement past the creator, so strict import rejects it
	too. Shares [method MapMakerModel.tile_dict_is_passable] (a static, resolver-free call
	here -- it resolves through the real TileCatalog) rather than re-deriving the
	wall/impassable rule a second time, so the two checks can never drift apart.

	Strict-mode only (see [method validate_map]): the many in-editor / in-game callers
	that only want structural checks stay exactly as fast and permissive as before.
	Position sanity is left to the out-of-bounds checks above this call -- a bad position
	is reported once, there, not duplicated here.
	"""
	for spawn_data in unit_spawns:
		var pos = spawn_data.get("position", Vector2i(-1, -1))
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			continue
		if not MapMakerModel.tile_dict_is_passable(get_tile_at_position(pos)):
			issues.append("Unit spawn at %s sits on impassable terrain" % str(pos))

	for rule in special_rules:
		var decoded: Dictionary = MapMakerModel.decode_objective_rule(rule)
		if decoded.is_empty():
			continue
		var pos = decoded["position"]
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			continue
		if not MapMakerModel.tile_dict_is_passable(get_tile_at_position(pos)):
			issues.append("Objective marker at %s sits on impassable terrain" % str(pos))

	# A control point nobody can stand on can never be claimed. Same backstop, same shared
	# passability rule (see [method _append_control_point_issues] for why it lives here).
	for point in get_control_points():
		if point.x < 0 or point.x >= width or point.y < 0 or point.y >= height:
			continue
		if not MapMakerModel.tile_dict_is_passable(get_tile_at_position(point)):
			issues.append("Control point at %s sits on impassable terrain" % str(point))


func _append_catalog_issues(issues: Array[String]) -> void:
	"""Append an issue for every tile_id / character_id that does not resolve.

	Kept out of [method validate_map]'s body so the structural checks read clean;
	invoked only when validation is asked to be catalog-strict (map import).
	"""
	for tile_data in tile_layout:
		var tile_id: String = str(tile_data.get("tile_id", ""))
		if tile_id.is_empty():
			continue
		if TileCatalog.find_by_id(StringName(tile_id)) == null:
			var pos = tile_data.get("position", Vector2i(-1, -1))
			issues.append("Unknown tile_id '%s' at %s" % [tile_id, str(pos)])

	# CharacterLibrary.all_ids() is used (rather than get_character(), which pushes a
	# warning on a miss) so an unknown id is reported once, here, without console noise.
	var known_ids: Dictionary = {}
	for known in CharacterLibrary.all_ids():
		known_ids[String(known)] = true
	for spawn_data in unit_spawns:
		var character_id: String = str(spawn_data.get("character_id", ""))
		if character_id.is_empty():
			continue
		if not known_ids.has(character_id):
			var spawn_pos = spawn_data.get("position", Vector2i(-1, -1))
			issues.append("Unknown character_id '%s' at %s" % [character_id, str(spawn_pos)])

## True when this map should be offered to players. Inactive maps are drafts:
## they save and load normally but are filtered out of map-selection lists.
func is_active() -> bool:
	return status != "Inactive"


func get_display_info() -> Dictionary:
	"""Get formatted info for UI display"""
	var player_counts = {}
	for spawn_data in unit_spawns:
		var player_id = spawn_data.get("player_id", -1)
		if player_id >= 0:
			player_counts[player_id] = player_counts.get(player_id, 0) + 1
	
	return {
		"name": map_name,
		"description": description,
		"author": author,
		"size": str(width) + "x" + str(height),
		"players": player_counts.size(),
		"max_players": max_players,
		"difficulty": difficulty,
		"map_type": map_type,
		"total_tiles": tile_layout.size(),
		"total_spawns": unit_spawns.size(),
		"spawn_kinds": get_spawn_kind_counts(),
		"creation_date": creation_date,
		"tags": tags
	}

func create_default_layout() -> void:
	"""Create a default tile layout for the map"""
	tile_layout.clear()
	
	# Fill with normal tiles
	for x in range(width):
		for y in range(height):
			set_tile_at_position(Vector2i(x, y), "NORMAL", "")

func create_sample_spawns() -> void:
	"""Create sample unit spawns for testing"""
	unit_spawns.clear()
	
	# Player 1 spawns (bottom)
	if height >= 2:
		for x in range(min(3, width)):
			set_unit_spawn_at_position(Vector2i(x, 0), 0, "WARRIOR", "")
	
	# Player 2 spawns (top)
	if height >= 2:
		for x in range(min(3, width)):
			set_unit_spawn_at_position(Vector2i(x, height - 1), 1, "WARRIOR", "")

func export_to_json() -> String:
	"""Export map data to JSON format"""
	var data = {
		"map_info": {
			"name": map_name,
			"description": description,
			"author": author,
			"version": version,
			"creation_date": creation_date,
			"last_modified": last_modified
		},
		"dimensions": {
			"width": width,
			"height": height
		},
		"gameplay": {
			"max_players": max_players,
			"recommended_players": recommended_players,
			"difficulty": difficulty,
			"map_type": map_type,
			"turn_limit": turn_limit,
			"victory_conditions": victory_conditions,
			"special_rules": special_rules
		},
		"visual": {
			"environment_preset": environment_preset,
			"lighting_preset": lighting_preset,
			"background_color": {
				"r": background_color.r,
				"g": background_color.g,
				"b": background_color.b,
				"a": background_color.a
			}
		},
		"layout": {
			"tiles": _entries_with_encoded_positions(tile_layout),
			"unit_spawns": _entries_with_encoded_positions(unit_spawns),
			# Written unconditionally (as [] / {} for the maps that declare neither) so the
			# payload shape is the same for every map and the importer never has to guess
			# whether a missing key means "no lanes" or "an older export".
			"lanes": _encoded_lanes(),
			"base_cells": _encoded_base_cells(),
			"control_points": _encoded_control_points()
		},
		"metadata": {
			"tags": tags,
			"preview_image_path": preview_image_path
		}
	}
	
	return JSON.stringify(data, "\t")

## Convert a JSON-parsed plain Array into the typed Array[String] our @export
## properties require (a direct plain->typed assignment is a runtime error).
## Non-string elements are stringified rather than dropped, matching JSON's
## loose typing.
static func _to_string_array(raw) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for v in raw:
			out.append(String(v))
	return out


static func import_from_json(json_string: String, quiet: bool = false) -> MapResource:
	"""Import map data from JSON format. Pass quiet=true from validation-only callers
	(e.g. ChallengeCodec.validate probing untrusted codes) so an EXPECTED rejection
	reports through the null return alone instead of push_error - the loud default
	stays for real load paths, where a rejected map is a genuine error."""
	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		if not quiet:
			push_error("MapResource: Failed to parse JSON: " + json.get_error_message())
		return null
	
	var data = json.data
	var resource = MapResource.new()
	
	# Map info
	var map_info = data.get("map_info", {})
	resource.map_name = map_info.get("name", "")
	resource.description = map_info.get("description", "")
	resource.author = map_info.get("author", "")
	resource.version = map_info.get("version", "1.0")
	resource.creation_date = map_info.get("creation_date", "")
	resource.last_modified = map_info.get("last_modified", "")
	
	# Dimensions
	var dimensions = data.get("dimensions", {})
	resource.width = dimensions.get("width", 5)
	resource.height = dimensions.get("height", 5)
	
	# Gameplay
	var gameplay = data.get("gameplay", {})
	resource.max_players = gameplay.get("max_players", 2)
	resource.recommended_players = gameplay.get("recommended_players", 2)
	resource.difficulty = gameplay.get("difficulty", "Normal")
	resource.map_type = gameplay.get("map_type", "Skirmish")
	resource.turn_limit = gameplay.get("turn_limit", 0)
	# JSON.parse gives plain Arrays; these properties are typed Array[String], and Godot
	# rejects a direct plain->typed assignment. Convert element-wise.
	resource.victory_conditions = _to_string_array(gameplay.get("victory_conditions", ["Eliminate All Enemies"]))
	resource.special_rules = _to_string_array(gameplay.get("special_rules", []))
	
	# Visual
	var visual = data.get("visual", {})
	resource.environment_preset = visual.get("environment_preset", "Default")
	resource.lighting_preset = visual.get("lighting_preset", "Day")
	var bg_color = visual.get("background_color", {"r": 0.2, "g": 0.2, "b": 0.3, "a": 1.0})
	resource.background_color = Color(
		bg_color.get("r", 0.2),
		bg_color.get("g", 0.2),
		bg_color.get("b", 0.3),
		bg_color.get("a", 1.0)
	)
	
	# Layout. Positions are decoded back into Vector2i (JSON has no native vector type,
	# so export writes them as {"x","y"} - see _entries_with_encoded_positions), and the
	# legacy "(x, y)" string form is still accepted so older hand-written files load.
	var layout = data.get("layout", {})
	resource.tile_layout = _decode_layout_entries(layout.get("tiles", []))
	resource.unit_spawns = _decode_layout_entries(layout.get("unit_spawns", []))
	# Absent on every map exported before these fields existed -- the defaults are the
	# "declares neither" answer, which is exactly what those maps mean.
	resource.lanes = _decode_lanes(layout.get("lanes", []))
	resource.base_cells = _decode_base_cells(layout.get("base_cells", {}))
	resource.control_points = _decode_control_points(layout.get("control_points", []))

	# Metadata
	var metadata = data.get("metadata", {})
	resource.tags = _to_string_array(metadata.get("tags", []))
	resource.preview_image_path = metadata.get("preview_image_path", "")

	# A map with no victory condition can never be won - default it rather than reject.
	if resource.victory_conditions.is_empty():
		resource.victory_conditions = ["Eliminate All Enemies"]

	# HARDENING: a JSON map is authored by a PLAYER and SHARED, so it is untrusted
	# input. Validate it (catalog-strict) before handing it back: unknown tile / character
	# references, out-of-bounds positions and a size outside MIN..MAX are all hard
	# failures. Returning null (not a broken resource) keeps callers on their existing
	# "load failed" path instead of quietly loading a corrupt map.
	var validation: Dictionary = resource.validate_map(true)
	if not validation.get("valid", false):
		if not quiet:
			push_error("MapResource.import_from_json: rejected invalid map '%s' - %s" % [
				resource.map_name, "; ".join(validation.get("issues", []))])
		return null

	return resource


# --- JSON position (de)serialization -----------------------------------------
# JSON has no native vector type. Tile / spawn entries key their cell on a Vector2i
# "position", which JSON.stringify would otherwise flatten to the lossy string
# "(x, y)". These helpers write it as {"x","y"} on export and rebuild the Vector2i
# on import, so a save/load round-trip is exact.

func _entries_with_encoded_positions(entries: Array) -> Array:
	"""Deep-copy layout entries, replacing each Vector2i position with {"x","y"}."""
	var out: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		var pos_value: Variant = copy.get("position", null)
		if pos_value is Vector2i:
			var pos: Vector2i = pos_value
			copy["position"] = {"x": pos.x, "y": pos.y}
		out.append(copy)
	return out


static func _decode_layout_entries(entries: Array) -> Array[Dictionary]:
	"""Rebuild layout entries from JSON, restoring position to a Vector2i."""
	var out: Array[Dictionary] = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy["position"] = _decode_position(copy.get("position", null))
		out.append(copy)
	return out


## [member lanes] with every waypoint written as {"x","y"} -- the same encoding tile and
## spawn positions use, and for the same reason (JSON has no vector type).
func _encoded_lanes() -> Array:
	var out: Array = []
	for raw in lanes:
		if not (raw is Array):
			continue
		var encoded: Array = []
		for waypoint in (raw as Array):
			if waypoint is Vector2i:
				var cell: Vector2i = waypoint
				encoded.append({"x": cell.x, "y": cell.y})
		out.append(encoded)
	return out


## [member base_cells] as JSON: a player slot is written as its DECIMAL STRING, because a
## JSON object key can only ever be a string. [method _decode_base_cells] turns it back
## into the int the rest of the game keys on.
func _encoded_base_cells() -> Dictionary:
	var out: Dictionary = {}
	for key in base_cells.keys():
		var value = base_cells[key]
		if typeof(key) != TYPE_INT or not (value is Vector2i):
			continue
		var cell: Vector2i = value
		out[str(int(key))] = {"x": cell.x, "y": cell.y}
	return out


## [member control_points] with every cell written as {"x","y"} -- the same encoding tile,
## spawn and lane positions use, and for the same reason (JSON has no vector type).
func _encoded_control_points() -> Array:
	var out: Array = []
	for raw in control_points:
		if not (raw is Vector2i):
			continue
		var cell: Vector2i = raw
		out.append({"x": cell.x, "y": cell.y})
	return out


## Rebuild [member control_points] from JSON. Junk decodes to [code]Vector2i(-1, -1)[/code]
## rather than being dropped, so [method _append_control_point_issues] rejects it as out of
## bounds -- a silently discarded point would let a broken map import as a valid one with
## fewer objectives. A payload whose "control_points" is not a list at all reads as "declares
## none", which is what every map exported before this field existed means.
static func _decode_control_points(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for entry in (raw as Array):
		out.append(_decode_position(entry))
	return out


## Rebuild [member lanes] from JSON. Anything that IS a list becomes a typed waypoint
## list; anything that is not is carried through UNTOUCHED rather than dropped, so
## [method _append_lane_and_base_issues] gets to reject it (a silently discarded lane
## would let a broken map import as a valid one with fewer lanes).
static func _decode_lanes(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for entry in (raw as Array):
		if entry is Array:
			out.append(_to_cell_array(entry))
		else:
			out.append(entry)
	return out


## Rebuild [member base_cells] from JSON, turning each decimal-string key back into an int.
## A key that is NOT a valid integer is kept verbatim so validation rejects the map --
## coercing it (String.to_int() answers 0 for "abc") would silently hand player 0 a base.
static func _decode_base_cells(raw) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for key in (raw as Dictionary).keys():
		var value: Variant = (raw as Dictionary)[key]
		if typeof(key) == TYPE_INT:
			out[int(key)] = _decode_position(value)
		elif str(key).is_valid_int():
			out[str(key).to_int()] = _decode_position(value)
		else:
			out[key] = _decode_position(value)
	return out


static func _decode_position(value) -> Vector2i:
	"""Best-effort parse of a position from any form a JSON file might carry it in."""
	if value is Vector2i:
		return value
	if value is Dictionary:
		var d: Dictionary = value
		return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	if value is Array and (value as Array).size() >= 2:
		var a: Array = value
		return Vector2i(int(a[0]), int(a[1]))
	if value is String:
		var stripped: String = (value as String).replace("(", "").replace(")", "").replace(" ", "")
		var parts: PackedStringArray = stripped.split(",")
		if parts.size() >= 2:
			return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(-1, -1)