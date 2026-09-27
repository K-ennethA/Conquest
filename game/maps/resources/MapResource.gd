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
#   position           Vector2i  the (col, row) column this entry occupies
#   floor              int       the floor it sits on (default 0 = ground). The KEY
#                                of an entry is (position, floor): a bridge deck is a
#                                floor-1 entry above the floor-0 river/road entry.
#                                Floor 0 is implicitly FULL (a missing floor-0 entry
#                                is a default tile); floors > 0 only exist where an
#                                entry is placed -- a gap is air (broken bridge).
#   stairs             String    OPTIONAL "north"/"south"/"east"/"west": this tile is
#                                a stair climbing that way -- it auto-generates a link
#                                from (position, floor) to the neighbouring column in
#                                that direction on floor + 1 (see get_links()).
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
#   position           Vector2i  the (col, row) column this point occupies
#   floor              int       the floor it stands on (default 0). A floor > 0
#                                point must sit on a floor-N tile entry.
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

@export var links: Array[Dictionary] = []  # Explicit cross-floor LINKS - see below
# A links entry joins two cells (possibly on different floors) that units may step
# between directly -- stairs, ladders, ramps, rope bridges between towers:
#
#   from           Vector3i  (col, row, floor) of one end
#   to             Vector3i  (col, row, floor) of the other end
#   cost           int       movement cost of the step (default 1)
#   kind           String    "stairs" / "ladder" / "ramp" / ... (flavour + UI hint)
#   bidirectional  bool      default true; false = one-way (a drop-down ledge)
#
# get_links() returns these PLUS the ones generated from "stairs" tile entries, all
# normalized. Maps authored before links existed have none (and are all floor 0).

## Direction names accepted by a tile entry's "stairs" key -> (dx, dy) column step.
const STAIR_DIRECTIONS := {
	"north": Vector2i(0, -1), "south": Vector2i(0, 1),
	"east": Vector2i(1, 0), "west": Vector2i(-1, 0),
}

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

# Weather (see docs/WEATHER.md). Ids name game/weather/resources/<id>.tres.
#   fixed    -- [member weather] all battle.
#   schedule -- [member weather_schedule] entries {"weather": id, "rounds": n}, looping.
#   dynamic  -- starts as [member weather]; every [member weather_change_every] rounds
#               re-rolls from [member weather_pool] {id: weight}, seeded per match
#               (deterministic + network-safe, see WeatherState.base_id_for_round).
@export_enum("fixed", "schedule", "dynamic") var weather_mode: String = "fixed"
@export var weather: String = "clear"
@export var weather_schedule: Array[Dictionary] = []
@export var weather_pool: Dictionary = {}
@export var weather_change_every: int = 3

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

# --- Entry key helpers (robust to JSON-imported / legacy entries) --------------

## The (col, row) position of a tile or spawn entry, whatever form it was stored in.
static func entry_position(entry: Dictionary) -> Vector2i:
	return Cells.pos2_from_variant(entry.get("position", Vector2i(-1, -1)))


## The floor of a tile or spawn entry (0 when absent -- every legacy entry).
static func entry_floor(entry: Dictionary) -> int:
	return int(entry.get("floor", 0))


## The board cell (col, row, floor) of a tile or spawn entry.
static func entry_cell(entry: Dictionary) -> Vector3i:
	return Cells.lift(entry_position(entry), entry_floor(entry))


func get_tile_at_position(pos: Vector2i, floor_index: int = 0) -> Dictionary:
	"""Get tile data at a position on a floor (default: the ground floor).

	Floor 0 is implicitly full: a position with no entry returns a default NORMAL
	tile. On an upper floor a missing entry means AIR and returns {}.
	"""
	for tile_data in tile_layout:
		if entry_position(tile_data) == pos and entry_floor(tile_data) == floor_index:
			return tile_data

	if floor_index != 0:
		return {}
	# Return default tile if not found
	return {
		"position": pos,
		"tile_type": "NORMAL",
		"tile_resource_path": "",
		"tile_id": ""
	}

func set_tile_at_position(pos: Vector2i, tile_type: String, tile_resource_path: String = "", tile_id = "", floor_index: int = 0) -> void:
	"""Set tile data at specific position.

	[param tile_id] is the STABLE [member TileResource.id] and is what makes the
	entry survive the asset being moved or renamed - always pass it when the tile
	is known. It is an optional TRAILING parameter so every existing two- and
	three-argument caller keeps working unchanged; those entries simply store an
	empty tile_id and resolve through the legacy path (see the schema block above).
	Accepts a String or a StringName.

	[param floor_index] (trailing, default 0) places the tile on an upper floor; the
	"floor" key is only written for floors > 0 so ground entries stay byte-identical
	to the pre-multi-floor schema.
	"""
	remove_tile_at_position(pos, floor_index)

	# Add new tile data
	var entry := {
		"position": pos,
		"tile_type": tile_type,
		"tile_resource_path": tile_resource_path,
		"tile_id": String(tile_id)
	}
	if floor_index != 0:
		entry["floor"] = floor_index
	tile_layout.append(entry)


func remove_tile_at_position(pos: Vector2i, floor_index: int = 0) -> void:
	"""Remove the tile entry at (pos, floor). On floor 0 the cell then reverts to the
	default tile; on an upper floor it becomes air."""
	for i in range(tile_layout.size() - 1, -1, -1):
		if entry_position(tile_layout[i]) == pos and entry_floor(tile_layout[i]) == floor_index:
			tile_layout.remove_at(i)


func has_tile_at(pos: Vector2i, floor_index: int = 0) -> bool:
	"""True when (pos, floor) has a tile: any in-bounds floor-0 cell, or an upper-
	floor cell with an entry."""
	if pos.x < 0 or pos.y < 0 or pos.x >= width or pos.y >= height or floor_index < 0:
		return false
	if floor_index == 0:
		return true
	return not get_tile_at_position(pos, floor_index).is_empty()


func set_stairs_at_position(pos: Vector2i, direction: String, floor_index: int = 0) -> void:
	"""Mark the tile at (pos, floor) as a stair climbing toward [param direction]
	("north"/"south"/"east"/"west", "" to clear). Creates a default tile entry first
	if the cell has none."""
	var entry: Dictionary = {}
	for e in tile_layout:
		if entry_position(e) == pos and entry_floor(e) == floor_index:
			entry = e
			break
	if entry.is_empty():
		set_tile_at_position(pos, "NORMAL", "", "", floor_index)
		entry = tile_layout[tile_layout.size() - 1]
	if direction.is_empty():
		entry.erase("stairs")
	else:
		entry["stairs"] = direction.to_lower()


# --- Floors & links -------------------------------------------------------------

func get_floor_count() -> int:
	"""Number of floors (1 for a classic flat map): highest floor used by any tile,
	spawn or link endpoint, plus one."""
	var top := 0
	for e in tile_layout:
		top = maxi(top, entry_floor(e))
	for s in unit_spawns:
		top = maxi(top, entry_floor(s))
	for l in get_links():
		top = maxi(top, maxi(l["from"].z, l["to"].z))
	return top + 1


func get_floors_at(pos: Vector2i) -> Array[int]:
	"""Every floor with a tile in column [param pos], ascending (0 first)."""
	var out: Array[int] = []
	if pos.x < 0 or pos.y < 0 or pos.x >= width or pos.y >= height:
		return out
	out.append(0)
	for e in tile_layout:
		var f := entry_floor(e)
		if f > 0 and entry_position(e) == pos and not out.has(f):
			out.append(f)
	out.sort()
	return out


func get_tiles_on_floor(floor_index: int) -> Array[Dictionary]:
	"""The tile entries on one floor (floor 0: only EXPLICIT entries)."""
	var out: Array[Dictionary] = []
	for e in tile_layout:
		if entry_floor(e) == floor_index:
			out.append(e)
	return out


func add_link(from: Vector3i, to: Vector3i, cost: int = 1, kind: String = "stairs", bidirectional: bool = true) -> void:
	"""Add an explicit link between two cells (replacing one with the same ends)."""
	remove_link(from, to)
	links.append({
		"from": from,
		"to": to,
		"cost": maxi(1, cost),
		"kind": kind,
		"bidirectional": bidirectional,
	})


func remove_link(a: Vector3i, b: Vector3i) -> void:
	"""Remove any explicit link joining [param a] and [param b] (either direction)."""
	for i in range(links.size() - 1, -1, -1):
		var f := Cells.from_variant(links[i].get("from", null))
		var t := Cells.from_variant(links[i].get("to", null))
		if (f == a and t == b) or (f == b and t == a):
			links.remove_at(i)


static func normalize_link(raw: Dictionary) -> Dictionary:
	"""Canonical link dict (Vector3i ends, int cost, String kind, bool
	bidirectional), or {} when an end is unreadable."""
	var a := Cells.from_variant(raw.get("from", null))
	var b := Cells.from_variant(raw.get("to", null))
	if a == Cells.INVALID or b == Cells.INVALID or a == b:
		return {}
	return {
		"from": a,
		"to": b,
		"cost": maxi(1, int(raw.get("cost", 1))),
		"kind": str(raw.get("kind", "stairs")),
		"bidirectional": bool(raw.get("bidirectional", true)),
	}


func get_links() -> Array[Dictionary]:
	"""Every link of the map, normalized: the explicit [member links] plus one per
	"stairs" tile entry (from the stair tile up to the next floor's neighbouring
	column). This is what MapLoader registers with the board."""
	var out: Array[Dictionary] = []
	for raw in links:
		var l := normalize_link(raw)
		if not l.is_empty():
			out.append(l)
	for e in tile_layout:
		var dir_name := str(e.get("stairs", "")).to_lower()
		if dir_name.is_empty() or not STAIR_DIRECTIONS.has(dir_name):
			continue
		var from := entry_cell(e)
		var step: Vector2i = STAIR_DIRECTIONS[dir_name]
		out.append({
			"from": from,
			"to": Vector3i(from.x + step.x, from.y + step.y, from.z + 1),
			"cost": maxi(1, int(e.get("stairs_cost", 1))),
			"kind": "stairs",
			"bidirectional": true,
		})
	return out

func get_unit_spawn_at_position(pos: Vector2i, floor_index: int = 0) -> Dictionary:
	"""Get the RAW spawn point entry at a position, or {} when there is none.

	Deliberately raw (not normalized): callers rely on the empty dictionary meaning
	"no spawn here". Pass the result through [method normalize_spawn] when you need
	the optional keys filled in.
	"""
	for spawn_data in unit_spawns:
		if entry_position(spawn_data) == pos and entry_floor(spawn_data) == floor_index:
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
		"position": entry_position(spawn_data),
		"floor": entry_floor(spawn_data),
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
	anything omitted falls back to the schema defaults. [code]opts.floor[/code] puts
	the point on an upper floor (written only when > 0).
	"""
	var floor_index: int = int(opts.get("floor", 0))
	# Remove existing spawn at position
	remove_unit_spawn_at_position(pos, floor_index)

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
	if floor_index != 0:
		unit_spawns[unit_spawns.size() - 1]["floor"] = floor_index

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

func remove_unit_spawn_at_position(pos: Vector2i, floor_index: int = 0) -> void:
	"""Remove unit spawn at specific position (on a floor, default ground)"""
	for i in range(unit_spawns.size() - 1, -1, -1):
		if entry_position(unit_spawns[i]) == pos and entry_floor(unit_spawns[i]) == floor_index:
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
		positions.append(entry_position(spawn_data))
	return positions

func get_player_spawn_cells(player_id: int, spawn_kind: String = "") -> Array[Vector3i]:
	"""Like [method get_player_spawn_positions] but as board cells (col, row, floor)."""
	var cells: Array[Vector3i] = []
	for spawn_data in unit_spawns:
		if spawn_data.get("player_id", -1) != player_id:
			continue
		if not spawn_kind.is_empty() and get_spawn_kind(spawn_data) != spawn_kind:
			continue
		cells.append(entry_cell(spawn_data))
	return cells

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

func validate_map() -> Dictionary:
	"""Validate map configuration"""
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
		var pos := entry_position(tile_data)
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			issues.append("Tile position out of bounds: " + str(pos))
		if entry_floor(tile_data) < 0:
			issues.append("Tile at %s has a negative floor" % str(pos))

	for spawn_data in unit_spawns:
		var pos := entry_position(spawn_data)
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			issues.append("Unit spawn position out of bounds: " + str(pos))
		elif not has_tile_at(pos, entry_floor(spawn_data)):
			issues.append("Unit spawn at %s floor %d has no tile to stand on" % [str(pos), entry_floor(spawn_data)])

	# Links must join two cells that exist.
	for raw in links:
		var l := normalize_link(raw)
		if l.is_empty():
			issues.append("Link has an unreadable endpoint: " + str(raw))
			continue
		for endpoint in [l["from"], l["to"]]:
			if not has_tile_at(Cells.flat(endpoint), endpoint.z):
				issues.append("Link endpoint %s has no tile" % str(endpoint))
	for e in tile_layout:
		var dir_name := str(e.get("stairs", "")).to_lower()
		if not dir_name.is_empty() and not STAIR_DIRECTIONS.has(dir_name):
			warnings.append("Tile at %s has an unknown stairs direction '%s'" % [str(entry_position(e)), dir_name])

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

	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"warnings": warnings
	}

## True when this map should be offered to players. Inactive maps are drafts:
## they save and load normally but are filtered out of map-selection lists.
func is_active() -> bool:
	return status != "Inactive"


## The map's weather settings as the plain dictionary [WeatherState] consumes
## ({mode, weather, schedule, pool, change_every}).
func get_weather_settings() -> Dictionary:
	return {
		"mode": weather_mode,
		"weather": weather,
		"schedule": weather_schedule.duplicate(true),
		"pool": weather_pool.duplicate(true),
		"change_every": weather_change_every,
	}


## Short label for map lists ("Rain", "Dynamic weather", "Changing weather"); ""
## for a permanently Clear map.
func weather_summary() -> String:
	match weather_mode:
		"dynamic":
			return "Dynamic weather"
		"schedule":
			return "Changing weather"
	if weather == "" or weather == "clear":
		return ""
	return Weather.get_weather(weather).display_name


## Apply a settings dictionary (the inverse of [method get_weather_settings]).
func set_weather_settings(settings: Dictionary) -> void:
	var n := WeatherState.normalize_settings(settings)
	weather_mode = String(n["mode"])
	weather = String(n["weather"])
	var sched: Array[Dictionary] = []
	for e in n["schedule"]:
		sched.append({ "weather": String(e["weather"]), "rounds": int(e["rounds"]) })
	weather_schedule = sched
	var pool: Dictionary = {}
	for k in n["pool"]:
		pool[String(k)] = float(n["pool"][k])
	weather_pool = pool
	weather_change_every = int(n["change_every"])


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
		"weather": get_weather_settings(),
		"layout": {
			# Positions are written as [col, row] arrays and link ends as
			# [col, row, floor] -- raw Vector2i/Vector3i would be stringified by JSON.
			"tiles": _entries_to_json(tile_layout),
			"unit_spawns": _entries_to_json(unit_spawns),
			"links": _links_to_json()
		},
		"metadata": {
			"tags": tags,
			"preview_image_path": preview_image_path
		}
	}
	
	return JSON.stringify(data, "\t")

static func _entries_to_json(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		var d: Dictionary = (e as Dictionary).duplicate()
		var p := entry_position(d)
		d["position"] = [p.x, p.y]
		out.append(d)
	return out


func _links_to_json() -> Array:
	var out: Array = []
	for raw in links:
		var l := normalize_link(raw)
		if l.is_empty():
			continue
		l["from"] = Cells.to_array(l["from"])
		l["to"] = Cells.to_array(l["to"])
		out.append(l)
	return out


static func import_from_json(json_string: String) -> MapResource:
	"""Import map data from JSON format"""
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Failed to parse JSON: " + json.get_error_message())
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
	resource.width = int(dimensions.get("width", 5))
	resource.height = int(dimensions.get("height", 5))
	
	# Gameplay
	var gameplay = data.get("gameplay", {})
	resource.max_players = int(gameplay.get("max_players", 2))
	resource.recommended_players = int(gameplay.get("recommended_players", 2))
	resource.difficulty = gameplay.get("difficulty", "Normal")
	resource.map_type = gameplay.get("map_type", "Skirmish")
	resource.turn_limit = int(gameplay.get("turn_limit", 0))
	# JSON arrays come back untyped; the exported properties are Array[String] /
	# Array[Dictionary], which reject a plain Array -- rebuild them typed.
	resource.victory_conditions = _json_string_array(gameplay.get("victory_conditions", ["Eliminate All Enemies"]))
	resource.special_rules = _json_string_array(gameplay.get("special_rules", []))
	
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
	
	# Weather (absent in older exports -> fixed Clear)
	var weather_data = data.get("weather", {})
	if weather_data is Dictionary:
		resource.set_weather_settings(weather_data)

	# Layout (positions parsed back from arrays -- or legacy "(x, y)" strings)
	var layout = data.get("layout", {})
	resource.tile_layout = _json_entry_array(layout.get("tiles", []))
	resource.unit_spawns = _json_entry_array(layout.get("unit_spawns", []))
	var parsed_links: Array[Dictionary] = []
	for raw in layout.get("links", []):
		if raw is Dictionary:
			var l := normalize_link(raw)
			if not l.is_empty():
				parsed_links.append(l)
	resource.links = parsed_links
	
	# Metadata
	var metadata = data.get("metadata", {})
	resource.tags = _json_string_array(metadata.get("tags", []))
	resource.preview_image_path = metadata.get("preview_image_path", "")
	
	return resource

# --- JSON -> typed value helpers (import_from_json) ---------------------------
# JSON has no Vector2i and no int: JSON.stringify writes a Vector2i as the string
# "(x, y)" and every number comes back as a float. These restore the typed values
# the rest of the game expects (MapLoader / MapMakerModel read "position" as
# Vector2i and ids/counts as int).

static func _json_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(String(v) if v is String or v is StringName else str(v))
	return out

static func _json_entry_array(value) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for entry in value:
			if entry is Dictionary:
				out.append(_json_entry(entry))
	return out

## One tile / spawn entry: "position" back to a Vector2i, integral floats to int.
static func _json_entry(entry: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in entry.keys():
		var v = entry[key]
		if key == "position":
			v = json_to_vector(v)
		elif v is float and is_equal_approx(v, roundf(v)):
			v = int(roundf(v))
		out[key] = v
	return out

## Parse a JSON-encoded grid position back to a Vector2i (or a Vector3i when it has
## three components). Accepts the "(x, y)" string JSON.stringify writes, an [x, y]
## array, or an {"x":..,"y":..} object; passes an already-typed vector through.
## Unparseable input yields Vector2i(-1, -1) (out of bounds, so loaders skip it).
static func json_to_vector(v):
	if v is Vector2i or v is Vector3i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	var parts: Array = []
	if v is String:
		for p in (v as String).strip_edges().trim_prefix("(").trim_suffix(")").split(","):
			parts.append(p.strip_edges())
	elif v is Array:
		parts = v
	elif v is Dictionary:
		parts = [v.get("x", -1), v.get("y", -1)]
		if v.has("z"):
			parts.append(v["z"])
	if parts.size() == 3:
		return Vector3i(int(float(parts[0])), int(float(parts[1])), int(float(parts[2])))
	if parts.size() == 2:
		return Vector2i(int(float(parts[0])), int(float(parts[1])))
	return Vector2i(-1, -1)