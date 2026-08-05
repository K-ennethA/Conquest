extends Node

class_name MapLoader

# MapLoader - Handles dynamic loading and creation of maps from MapResource files
# Replaces the hardcoded map structure in GameWorld.tscn

signal map_loaded(map_resource: MapResource)
signal map_load_failed(error_message: String)

var current_map: MapResource
var map_root: Node3D
var tiles_container: Node3D
var units_container: Node3D

## The map's DECORATIVE SURROUND (see [MapSurround]): rings of scenery, a dirt skirt and
## a backdrop plane that stop the board reading as a slab floating in the void. Purely
## cosmetic — it adds no board cells, registers no terrain with [CombatServices] and
## carries no collision, so pathing / picking / spawns / lockstep never see it. Freed
## with the map in [method clear_current_map].
var map_surround: Node3D = null

## Set false to load a map with NO surround. The MAP CREATOR's editing view wants the
## true grid and nothing else; tests that assert on raw board geometry can flip it too.
## Battles (including replays) leave it on, so every mode shows the same scenery.
var surround_enabled: bool = true

## model_path values already reported by [method _note_tile_model_fallback], so a bad
## path is mentioned ONCE per load instead of once per cell that uses it.
var _reported_tile_model_fallbacks: Dictionary = {}

# Tile and unit scene references
var default_tile_scene: PackedScene = preload("res://tile_objects/tiles/tile.tscn")

# Generic character-backed unit scene: instantiated for every spawn (see
# _create_unit_from_spawn). Stats and components come from the CharacterResource
# assigned to it, not from a baked-in stats_resource - see
# game/characters/CharacterUnit.tscn. The fixed-class per-type unit scenes
# have been retired; every spawn now resolves to a roster character id
# (explicit or via LEGACY_UNIT_TYPE_TO_CHARACTER_ID / DEFAULT_CHARACTER_ID).
var character_unit_scene: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

# Fallback roster id used when a spawn's character_id (explicit or aliased)
# doesn't resolve to a real CharacterResource, so map loading never fails.
const DEFAULT_CHARACTER_ID: StringName = &"vineweave"

## World Y a unit's origin sits at: the tile box top (tiles are 0.2 tall, centered on
## y=0). Models are feet-at-origin, so this rests their feet on the tile surface.
const UNIT_GROUND_Y: float = 0.1

# Legacy "unit_type" string -> roster CharacterResource id. Used to resolve
# spawns authored before the character system (no "character_id" set) to a
# fitting character so old maps keep loading with character-backed units.
const LEGACY_UNIT_TYPE_TO_CHARACTER_ID: Dictionary = {
	"WARRIOR": &"vineweave",
	"ARCHER": &"petalfang",
	"MAGE": &"mycothrall",
}

## Test/injection seam for the networked-match context [method _load_units] resolves each
## player's roster with. Empty (the default) reads the live [NetSession] autoload; a test sets
## { "networked": bool, "local_slot": int } to load a map AS a given peer without standing up
## a socket. Never set in production.
var net_context_override: Dictionary = {}

func _ready():
	pass


# --- Which squad fills a player's start slots -------------------------------
#
# Single-player and hotseat: player 0 gets the local pick (Character Select ->
# GameSettings.selected_squad); every other player_id is the map's own authored roster,
# because there is nobody else to have picked one.
#
# NETWORKED: a player_id is a ROSTER SLOT, and the same slot must field the same characters on
# BOTH machines. So exactly one participant's pick is authoritative for each slot -- OUR OWN
# for our own slot, the REPLICATED announcement for everybody else's:
#
#   * slot 0's replicated pick is the host's, carried by the game_start payload's "host_squad".
#     Before that existed a client applied its OWN selected_squad to player 0, so the client
#     fielded its picks where the host fielded the host's and the boards disagreed on frame 1.
#   * every other slot's replicated pick rides its "match_loadout" card (MatchLoadouts.squad_for),
#     which is the client -> host twin game_start never had. Before THAT, a client's own pick
#     reached nobody and player 1 fell back to the map's authored roster on both peers.

## The character ids that fill [param player_id]'s START slots on THIS peer. PURE -- every
## input is a parameter, which is what the tests drive.
##
## [param local_squad] is this peer's own Character Select pick, [param replicated_squad] the
## pick the OWNER of [param player_id] announced (empty when it announced none),
## [param local_slot] this peer's roster slot (-1 when unknown) and [param networked] whether
## this is a live networked match.
##
## Rules:
##   • not networked -> player 0 gets the local pick (unchanged for solo / hotseat / arena /
##     challenge); any other player is the map's authored roster, as it always was.
##   • networked AND this player_id IS our slot -> our own pick. That covers the host reading
##     slot 0 and the client reading its own slot alike.
##   • networked and it is SOMEBODY ELSE's slot (including when we are not yet seated, so no
##     slot is ours) -> that slot's replicated pick. Empty -- a legacy peer that announced
##     nothing -- means "the map's own authored roster for that slot", which is exactly what
##     that peer's own empty pick fields too, so the two boards still agree.
static func resolve_player_squad(player_id: int, local_squad: Array, replicated_squad: Array,
		local_slot: int, networked: bool) -> Array:
	if not networked:
		return normalise_squad_ids(local_squad) if player_id == 0 else []
	if player_id == local_slot:
		return normalise_squad_ids(local_squad)
	return normalise_squad_ids(replicated_squad)


## [method resolve_player_squad] for player 0, the shape this started as. Kept because slot 0
## is the one slot with its own replication channel (the host_squad in game_start) and callers
## / tests name it directly.
static func resolve_player0_squad(local_squad: Array, host_squad: Array, local_slot: int, networked: bool) -> Array:
	return resolve_player_squad(0, local_squad, host_squad, local_slot, networked)


## Private marker [method _load_units] stamps on a spawn whose character came from a SQUAD PICK
## rather than from the map's authoring. Read only by [method _create_unit_from_spawn] (the
## AI-difficulty gate); [method MapResource.normalize_spawn] rebuilds a fixed key set, so it
## never reaches spawn data anyone else consumes.
const SQUAD_PICK_KEY: String = "_from_squad_pick"


## The squad that fills [param player_id]'s START slots, with the replicated half looked up
## from wherever that slot announced it. Instance-level (it reads process-wide replication
## state); the DECISION itself stays pure in [method resolve_player_squad].
func _squad_for_player(player_id: int, local_squad: Array, host_squad: Array,
		local_slot: int, networked: bool) -> Array:
	return resolve_player_squad(player_id, local_squad,
		_replicated_squad_for(player_id, host_squad, networked), local_slot, networked)


## What the OWNER of [param player_id] announced it would field, from the channel that slot
## has: slot 0's rides the host's game_start payload ([param host_squad], already stored in
## GameSettings), everybody else's rides their own "match_loadout" card. Slot 0 also falls back
## to its card, so a host that announced one but sent no host_squad still lands. Empty outside
## a networked match -- nobody announced anything, so nothing is replicated.
func _replicated_squad_for(player_id: int, host_squad: Array, networked: bool) -> Array:
	if not networked:
		return []
	if player_id == 0 and not normalise_squad_ids(host_squad).is_empty():
		return host_squad
	return MatchLoadouts.squad_for(player_id)


## Drop the previous match's REPLICATION STATE at the start of a battle that is not a live
## networked match.
##
## [MatchLoadouts] is process-wide static state and [member GameSettings.host_squad] is an
## autoload field; both are set from a networked lobby and only CLEARED when the next lobby
## initialises. So going lobby -> versus match -> Main Menu -> a solo/campaign/challenge battle
## never passes through a lobby again, and that battle would read the previous opponent's slot
## card (its items and skins) and the previous host's roster. This is the other end of
## [method CollaborativeLobby.initialize]'s clear: one at the start of a networked match, one
## at the start of a battle that is not.
##
## Guarded on there being anything to forget, so the overwhelmingly common case (every solo
## battle ever launched in a process that never networked) touches nothing at all.
func _clear_stale_replication() -> void:
	if MatchLoadouts.is_active() or MatchLoadouts.peer_count() > 0:
		MatchLoadouts.clear()
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and GameSettings.has_method("get_host_squad") and GameSettings.has_method("set_host_squad") \
			and not (GameSettings.get_host_squad() as Array).is_empty():
		GameSettings.set_host_squad([])


## Coerce a squad id list into plain trimmed Strings, dropping anything that is not a scalar
## id. [member GameSettings.host_squad] arrives as an UNTRUSTED peer Dictionary value off the
## lobby channel, so a hostile or buggy host could put a Dictionary, an Array or a null in it;
## normalising at this boundary (the MatchPeerInfo pattern) means the spawn path only ever
## sees ids, and a junk entry costs that slot rather than the whole map load.
static func normalise_squad_ids(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for entry in (raw as Array):
		match typeof(entry):
			TYPE_STRING, TYPE_STRING_NAME:
				var id: String = String(entry).strip_edges()
				if not id.is_empty():
					out.append(id)
			_:
				continue
	return out


## The { networked, local_slot } context [method resolve_player0_squad] needs, from the live
## session -- or from [member net_context_override] when a test injected one. Null-safe: with
## no NetSession autoload (headless runs, bare test harnesses) this reports "not networked",
## so the local pick is used exactly as before.
func _net_squad_context() -> Dictionary:
	if not net_context_override.is_empty():
		return {
			"networked": bool(net_context_override.get("networked", false)),
			"local_slot": int(net_context_override.get("local_slot", -1)),
		}
	var net: Object = get_node_or_null("/root/NetSession")
	if net == null or not net.has_method("is_networked_match"):
		return { "networked": false, "local_slot": -1 }
	return {
		"networked": bool(net.call("is_networked_match")),
		"local_slot": int(net.call("local_slot")) if net.has_method("local_slot") else -1,
	}

func load_map(map_resource: MapResource, target_parent: Node3D) -> bool:
	"""Load a map from MapResource into the scene"""
	if not map_resource:
		_emit_load_failed("Invalid map resource")
		return false

	# Validate map
	var validation = map_resource.validate_map()
	if not validation.valid:
		var error_msg = "Map validation failed: " + str(validation.issues)
		_emit_load_failed(error_msg)
		return false
	
	# Clear existing map if any
	clear_current_map()
	# Fresh load = fresh dedupe window, so a bad model_path is reported once per map load
	# rather than once ever per process.
	_reported_tile_model_fallbacks.clear()

	# Set up map structure
	current_map = map_resource
	map_root = target_parent

	# Sync the shared board Grid to THIS map's dimensions. Grid.tres ships as a
	# stale 5x5, and the cursor clamps to grid.size -- so on a bigger map the
	# cursor would be stuck in a 5x5 corner and mouse bounds checks would fail.
	# The cursor preloads the same cached Grid.tres, so mutating it here (in
	# memory, not saved) propagates to every consumer for this map.
	_sync_grid_size(map_resource)

	# Create containers
	if not _create_map_containers():
		_emit_load_failed("Failed to create map containers")
		return false
	
	# Load tiles
	if not _load_tiles():
		_emit_load_failed("Failed to load tiles")
		return false
	
	# Load units
	if not _load_units():
		_emit_load_failed("Failed to load units")
		return false

	# Decorative scenery around the board. LAST, and never fatal: it is presentation
	# only, so nothing here can cost the player a battle.
	_build_map_surround()

	map_loaded.emit(map_resource)
	return true


## Mount the cosmetic surround for the map just built (see [member map_surround]).
##
## Deliberately parented to map_root and NOT to "Tiles": CameraController fits the
## board by scanning that container's children, so scenery placed there would inflate
## the fit rect and pull the camera back off the real board. [method MapSurround.build]
## also frees any stray surround already mounted, so a reload can never stack two.
func _build_map_surround() -> void:
	if not surround_enabled or current_map == null or map_root == null:
		return
	map_surround = MapSurround.build(current_map, map_root)

func _sync_grid_size(map_resource) -> void:
	"""Resize the shared board grid to match the loaded map (see load_map)."""
	var grid = load("res://board/Grid.tres")
	if grid == null:
		return
	var w: int = maxi(1, int(map_resource.width))
	var h: int = maxi(1, int(map_resource.height))
	grid.size = Vector3(w, 0, h)

func load_map_from_file(map_path: String, target_parent: Node3D) -> bool:
	"""Load a map from a .tres file -- or, for a .json path, through the hardened importer.

	THE ONE CONSUMPTION SEAM. A map that did not ship with the game is always inert JSON:
	the Map Creator writes it (CUSTOM_MAPS_DIR), a community download re-exports it there,
	and a map received from a networked host is materialised as one by
	MapCatalog.install_session_payload. Every one of those is addressed by PATH, and every
	caller that boots a battle (GameWorldManager._load_selected_map, the versus lobby, the
	local match setup) already hands us a path -- so routing on the extension here means
	there is exactly ONE place a shared map becomes a board, and it is the hardened one.
	A .json path NEVER reaches ResourceLoader (a shared .tres is an arbitrary-code-execution
	vector; see CONQUEST.md convention 8)."""
	if map_path.get_extension().to_lower() == "json":
		return load_map_from_json_file(map_path, target_parent)

	if not ResourceLoader.exists(map_path):
		_emit_load_failed("Map file not found: " + map_path)
		return false
	
	var map_resource = load(map_path) as MapResource
	if not map_resource:
		_emit_load_failed("Failed to load map resource: " + map_path)
		return false
	
	return load_map(map_resource, target_parent)

func clear_current_map() -> void:
	"""Clear the currently loaded map"""
	if tiles_container:
		tiles_container.queue_free()
		tiles_container = null
	
	if units_container:
		units_container.queue_free()
		units_container = null

	# The surround goes IMMEDIATELY (free, not queue_free): the very next thing a caller
	# does is load another map, and a node that is queued-but-alive would still answer to
	# get_node("MapSurround") when the new one mounts — freeing it there a second time is
	# the "freeing a freed object" bug. Immediate disposal keeps that window shut.
	if map_surround != null and is_instance_valid(map_surround):
		map_surround.free()
	map_surround = null

	current_map = null

func get_current_map() -> MapResource:
	"""Get the currently loaded map resource"""
	return current_map

func get_map_info() -> Dictionary:
	"""Get information about the currently loaded map"""
	if not current_map:
		return {}
	
	return current_map.get_display_info()

func _create_map_containers() -> bool:
	"""Create the necessary containers for tiles and units"""
	if not map_root:
		return false
	
	# Create tiles container
	tiles_container = Node3D.new()
	tiles_container.name = "Tiles"
	map_root.add_child(tiles_container)
	
	# Create player containers for units
	for player_id in range(current_map.max_players):
		var player_container = Node3D.new()
		player_container.name = "Player" + str(player_id + 1)
		map_root.add_child(player_container)
	
	return true

func _load_tiles() -> bool:
	"""Load all tiles from the map resource"""
	if not current_map or not tiles_container:
		return false
	
	var map_size = current_map.get_map_size()

	# Create tiles for each position
	for x in range(map_size.x):
		for y in range(map_size.y):
			var pos = Vector2i(x, y)
			var tile_data = current_map.get_tile_at_position(pos)
			
			if not _create_tile_at_position(pos, tile_data):
				return false

	return true

func _create_tile_at_position(grid_pos: Vector2i, tile_data: Dictionary) -> bool:
	"""Create a tile at the specified grid position"""
	var tile_resource_path = tile_data.get("tile_resource_path", "")
	var tile_type = tile_data.get("tile_type", "NORMAL")
	var tile_id = tile_data.get("tile_id", "")

	# Resolve the terrain data FIRST: the TileResource is what decides which
	# visual scene this tile gets (via its model_path), so it has to be known
	# before we choose a scene to instantiate.
	var resolved_tile_resource := _resolve_tile_resource(tile_resource_path, tile_type, tile_id)

	# Pick the scene to instantiate, most specific first:
	#  1. resolved_tile_resource.model_path -- a hand-authored geometry scene under
	#     tile_objects/tiles/scenes/ (tree, tall grass, meadow, dirt...). These are
	#     built at FULL cell size already (a 2 x 0.2 x 2 slab + collision).
	#  2. tile_resource_path when it is itself a PackedScene (legacy map data that
	#     stored a scene path in this field).
	#  3. default_tile_scene -- the plain unit-box tile.
	# Every step is guarded: a missing or non-PackedScene path just falls through
	# to the next option, so bad data can never fail map loading.
	var tile_scene: PackedScene = default_tile_scene
	var uses_authored_geometry: bool = false

	if resolved_tile_resource != null:
		var model_path: String = resolved_tile_resource.model_path
		if not model_path.is_empty():
			if ResourceLoader.exists(model_path):
				var model_scene = load(model_path) as PackedScene
				if model_scene != null:
					tile_scene = model_scene
					uses_authored_geometry = true
				else:
					_note_tile_model_fallback(model_path, "not a PackedScene")
			else:
				_note_tile_model_fallback(model_path, "not found")

	# Legacy fallback: the same field may hold a scene path instead of a TileResource.
	if not uses_authored_geometry and not tile_resource_path.is_empty() and ResourceLoader.exists(tile_resource_path):
		var custom_scene = load(tile_resource_path) as PackedScene
		if custom_scene:
			tile_scene = custom_scene

	# Instantiate tile
	var tile_instance = tile_scene.instantiate()
	if not tile_instance:
		return false
	
	# Set tile name and position
	tile_instance.name = "Tile_" + str(grid_pos.x) + "_" + str(grid_pos.y)
	
	# Calculate world position. The tile's BoxMesh (and BoxShape collision) is
	# centered on the node origin and scaled to span one 2x2 cell, so the origin
	# must sit at the CELL CENTER for the visible tile + its click/hover collider
	# to coincide with the logical cell. Grid.calculate_map_position centers cell
	# N at N*2 + 1 (half-cell), which is exactly where units spawn and where the
	# cursor snaps -- so place the tile there too. A centered 2x2 mesh at grid*2+1
	# then covers [grid*2, grid*2+2] == the logical cell, matching units, cursor,
	# and mouse picking (calculate_grid_coordinates = floor(world/2)). The old
	# origin grid*2 rendered the tile a half-cell off, which is why the mouse
	# never lined up with the tile and terrain hover resolved to the wrong cell.
	var world_pos = Vector3(grid_pos.x * 2 + 1, 0, grid_pos.y * 2 + 1)
	tile_instance.transform.origin = world_pos
	# default_tile_scene (and legacy custom scenes) use a UNIT 1x1x1 box, so they
	# are stretched to span the 2x2 cell here. Authored geometry scenes already
	# ship a 2 x 0.2 x 2 slab (see tile_objects/tiles/scenes/tree_tile.tscn and the
	# CELL = 2.0 layout in dev_scripts/grass_preview.gd), so applying the same
	# scale would double them to 4x4 and overlap their neighbours -- they stay at
	# identity. This does not change the scaling of any pre-existing path.
	if not uses_authored_geometry:
		tile_instance.transform.basis = Basis().scaled(Vector3(2, 1, 2))

	# Bind terrain data: the TileResource resolved above (explicit path, else a
	# type->resource map for the built-in families) is assigned to the live tile so
	# the board becomes terrain-aware. Assign BEFORE add_child so Tile._ready()
	# applies the resource visuals. Register the cell->TileResource mapping with
	# CombatServices so the shared BoardAdapter reads real terrain. Fall back to
	# the legacy set_tile_type() visuals when no resource resolves.
	if resolved_tile_resource != null and tile_instance.has_method("set_tile_resource"):
		tile_instance.set_tile_resource(resolved_tile_resource)
		# Guarded so headless/tool loads without the autoload don't crash.
		if CombatServices:
			CombatServices.register_tile(grid_pos, resolved_tile_resource)
	elif tile_instance.has_method("set_tile_type"):
		tile_instance.set_tile_type(tile_type)

	tiles_container.add_child(tile_instance)
	return true

## Tile.TileType enum name (plus friendly aliases) -> the STABLE
## [member TileResource.id] of the tile that represents that family. This is the
## LAST-RESORT mapping for map entries that name only a coarse type. Ids rather
## than res:// paths, so reorganising the tile assets into different biome folders
## cannot break it (see [TileCatalog]).
const TYPE_TO_TILE_ID: Dictionary = {
	"NORMAL": &"grass_plains",
	"GRASS": &"grass_plains",
	"PLAINS": &"grass_plains",
	"WATER": &"deep_water",
	"WALL": &"stone_wall",
	"LAVA": &"molten_lava",
	"SACRED_GROUND": &"sacred_ground",
}


## Report a tile falling back to the default geometry, ONCE per distinct model_path.
##
## This used to be a push_warning fired per TILE INSTANCE -- a single bad model_path in a
## map emitted one debugger warning per cell that used it, i.e. hundreds on one load.
## Falling back is the DESIGNED behaviour here (see the resolution chain in
## _create_tile_at_position: "bad data can never fail map loading"), so it is an EXPECTED
## condition and must not report through the engine log at all. It is still worth knowing
## about once, so it prints -- a plain print never reaches the debugger's error panel.
func _note_tile_model_fallback(model_path: String, reason: String) -> void:
	if _reported_tile_model_fallbacks.has(model_path):
		return
	_reported_tile_model_fallbacks[model_path] = true
	print("[MapLoader] tile model_path %s (%s); using the default tile for those cells."
		% [model_path, reason])


func _resolve_tile_resource(resource_path: String, tile_type: String, tile_id = "") -> TileResource:
	"""Resolve the TileResource for a tile from its map data.

	Resolution order, most durable reference first:
	  1. tile_id  -- the STABLE TileResource id, via TileCatalog.find_by_id(). This
	     is the reference that survives an asset being moved or renamed, which is
	     what player-authored maps shared between installs depend on.
	  2. tile_resource_path -- via TileCatalog.find(), which tries the exact path
	     and then the same file NAME elsewhere in the tree. LEGACY: this is how
	     maps authored before ids stored their tiles, and the basename fallback can
	     only guess when two files share a name.
	  3. tile_type -- the coarse built-in terrain families (grass/water/wall/lava),
	     resolved through TYPE_TO_TILE_ID and the catalog. Last resort.

	The same tile_resource_path field doubles as a custom-scene path in the caller,
	so a scene path simply won't cast to a TileResource here and is ignored.
	Returns null when nothing matches, letting the caller fall back to the legacy
	set_tile_type() path.

	[param tile_id] is an optional TRAILING parameter (String or StringName) so the
	pre-existing two-argument call signature keeps working.
	"""
	# 1. Stable id -- the durable reference.
	var by_id := TileCatalog.find_by_id(StringName(String(tile_id)))
	if by_id != null:
		return by_id

	# 2. Legacy path addressing, with TileCatalog's basename fallback.
	var found := TileCatalog.find(resource_path)
	if found != null:
		return found

	# 3. Coarse tile_type family.
	var family_id: StringName = TYPE_TO_TILE_ID.get(String(tile_type).to_upper(), &"")
	return TileCatalog.find_by_id(family_id)

func _load_units() -> bool:
	"""Load all unit spawns from the map resource"""
	if not current_map or not map_root:
		return false
	
	# The squad filling a player's spawn slots. When set, it REPLACES the character in each of
	# that player's slots, in order -- the map still decides WHERE and HOW MANY units stand,
	# the player decides WHICH. Empty = field the map's own authored roster (unchanged for maps
	# launched without a pick). Arena doesn't come through here; it seeds its squad via
	# ArenaController.start_run.
	#
	# In a NETWORKED match a player_id is a ROSTER SLOT: our own slot takes our own pick, every
	# other slot takes that participant's REPLICATED pick -- see resolve_player_squad.
	var ctx: Dictionary = _net_squad_context()
	var networked: bool = bool(ctx["networked"])
	var local_slot: int = int(ctx["local_slot"])

	# A battle that is NOT a live networked match starts from a clean replication slate -- see
	# _clear_stale_replication. Done BEFORE anything is resolved or spawned, because the reads
	# below (and ItemSystem / Unit's, on every unit this loop creates) are exactly what would
	# otherwise pick up the previous match's leftovers.
	if not networked:
		_clear_stale_replication()

	var local_squad: Array = []
	var host_squad: Array = []
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null:
		if GameSettings.has_method("get_selected_squad"):
			local_squad = GameSettings.get_selected_squad()
		if GameSettings.has_method("get_host_squad"):
			host_squad = GameSettings.get_host_squad()

	# player_id -> the resolved squad for that slot, and how many of it we have placed.
	# Resolved LAZILY (first START point a player owns), so a map with no spawns for a player
	# never asks about it.
	var squads: Dictionary = {}
	var next_slot: Dictionary = {}

	var units_created = 0
	for spawn_data in current_map.unit_spawns:
		# Spawn POINTS describe when they produce units, not just where. Only the
		# ones that seed a unit at load time are materialised here - a Reinforcement
		# scheduled for turn 5 must stay empty until the turn system activates it.
		# Maps authored before spawn_kind existed default to "Start", so they are
		# all initial and load exactly as they always did.
		if not current_map.is_initial_spawn(spawn_data):
			continue

		# An initial point with no unit reference is an UNASSIGNED SLOT, filled at
		# match setup - not an error, and specifically not a reason to conjure a
		# default WARRIOR onto the board.
		if not current_map.spawn_has_unit_reference(spawn_data):
			continue

		var sd = spawn_data
		# Override this player's slots with the squad that owns them (in slot order). If the
		# player fielded FEWER units than the map has slots for them, the extra slots stay
		# empty rather than falling back to the map's authored unit.
		#
		# START points ONLY. A "Start" point is a SQUAD SLOT -- an empty chair the
		# match-setup screen fills. A Respawn / Endless / Reinforcement point is map
		# FURNITURE: a spawn portal, a garrison, a base structure. The map decides what those
		# field, not the player, and they must never be overwritten with (nor dropped in
		# favour of) a squad pick -- a base-assault map's own base would otherwise load as
		# whichever character the player picked first.
		var spawn_player_id: int = int(sd.get("player_id", 0))
		if current_map.get_spawn_kind(spawn_data) == MapResource.SPAWN_KIND_START:
			if not squads.has(spawn_player_id):
				squads[spawn_player_id] = _squad_for_player(
					spawn_player_id, local_squad, host_squad, local_slot, networked)
				next_slot[spawn_player_id] = 0
			var squad: Array = squads[spawn_player_id]
			if not squad.is_empty():
				var pick: int = int(next_slot[spawn_player_id])
				if pick >= squad.size():
					continue
				sd = spawn_data.duplicate()
				sd["character_id"] = String(squad[pick])
				# Marks this unit as a DELIBERATE PICK, exempting it from the AI-difficulty
				# gate in _create_unit_from_spawn (see there).
				sd[SQUAD_PICK_KEY] = true
				next_slot[spawn_player_id] = pick + 1

		if _create_unit_from_spawn(sd, units_created):
			units_created += 1

	return true

## Spawn a single unit from a spawn point RIGHT NOW, returning the new unit node
## (or null on failure). This is the public entry for the runtime spawn scheduler
## (SpawnManager): _load_units() only runs at map load, but a scheduled
## Reinforcement arriving on its turn, or a Respawn/Endless point producing its
## next unit, needs to materialise one point on demand. [param count_hint] only
## feeds the generated node name — pass a running counter for uniqueness.
func spawn_unit_now(spawn_data: Dictionary, count_hint: int = 0) -> Node:
	if not current_map or not map_root:
		return null
	return _create_unit_from_spawn(spawn_data, count_hint, true)

func _create_unit_from_spawn(spawn_data: Dictionary, units_created: int, runtime: bool = false) -> Node:
	"""Create a unit from spawn data. Returns the new unit node, or null on failure."""
	var grid_pos = spawn_data.get("position", Vector2i(-1, -1))
	var player_id_raw = spawn_data.get("player_id", 0)

	# ALWAYS coerce. A .tres map carries an int here, but a JSON map (Map Creator save,
	# community download, a map a networked host shipped) carries whatever JSON.parse produced
	# -- and JSON has one number type, so "player_id": 1 comes back as the FLOAT 1.0. The old
	# String-only coercion let that float through, and str(1.0 + 1) is "2.0", so every unit on a
	# JSON map was parented to a freshly invented "Player2.0" container instead of the real
	# "Player2" -- an empty-looking board with the units hidden one node over.
	var player_id: int = int(player_id_raw)

	var unit_type = spawn_data.get("unit_type", "WARRIOR")
	var character_id_raw = spawn_data.get("character_id", "")

	if grid_pos == Vector2i(-1, -1):
		return null

	# Resolve which CharacterResource should back this unit: prefer an explicit
	# character_id on the spawn; fall back to the legacy unit_type alias table
	# so maps authored before the character system still resolve to a character;
	# finally fall back to DEFAULT_CHARACTER_ID so a missing/bad id never fails
	# to spawn a unit (the fixed-class scenes this used to fall back to are gone).
	var character_id: String = _resolve_character_id(character_id_raw, unit_type)
	if character_id.is_empty():
		character_id = String(DEFAULT_CHARACTER_ID)

	var character_resource: CharacterResource = CharacterLibrary.get_character(character_id)
	if not character_resource:
		character_id = String(DEFAULT_CHARACTER_ID)
		character_resource = CharacterLibrary.get_character(character_id)

	if not character_resource:
		return null

	# Difficulty gate: a character can require a minimum AI difficulty (e.g. a
	# parasite that only appears on Hard+). This gates ENEMY spawns -- it must NEVER drop
	# a unit the PLAYER deliberately chose. Player 0 is the local human's side (its squad
	# comes from Character Select / the map's own roster), so it is exempt; otherwise a
	# hand-picked mycothrall would silently vanish on Normal ("chose 4, only 3 showed up").
	#
	# So is ANY slot filled from a squad pick, which in a networked match includes the OPPONENT's
	# (SQUAD_PICK_KEY). ai_difficulty is a local setting: gating a human's replicated pick would
	# drop the unit on the peer set to Normal and keep it on the peer set to Hard, which is a
	# board disagreement on the first frame rather than a difficulty rule.
	if player_id != 0 and not bool(spawn_data.get(SQUAD_PICK_KEY, false)) \
			and not _difficulty_allows(character_resource):
		return null

	# Every unit is a CharacterUnit.tscn instance backed by a CharacterResource.
	var unit_instance = character_unit_scene.instantiate()
	if not unit_instance:
		return null

	# Must be assigned BEFORE add_child: Unit._ready() (tile_objects/units/unit.gd)
	# derives its UnitStats + combat components from character_resource only
	# while it's already set when the node enters the tree.
	unit_instance.character_resource = character_resource

	# Set unit name
	var name_hint = character_id if not character_id.is_empty() else unit_type
	unit_instance.name = name_hint + str(units_created + 1)

	# Calculate world position. Y sits at the TILE SURFACE (tile box top = 0.1): unit
	# models are exported feet-at-origin (see Unit._setup_character_model), so their
	# feet rest on the tile. The old Y=1.5 left every unit floating above the ground,
	# which only became visible once the camera went perspective.
	var world_pos = Vector3(grid_pos.x * 2 + 1, UNIT_GROUND_Y, grid_pos.y * 2 + 1)
	unit_instance.transform.origin = world_pos

	# Face the opposing side based on board position: a unit in the TOP (north) half faces
	# down-board toward the camera, one in the BOTTOM (south) half faces up-board (its back
	# to the camera). Set BEFORE add_child so the model is built already oriented; Unit
	# composes this ADDITIVELY with the character's authored model_yaw_deg correction.
	if "facing_yaw" in unit_instance:
		unit_instance.facing_yaw = _compute_spawn_facing(grid_pos, player_id)

	# Add to appropriate player container
	var player_container = map_root.get_node_or_null("Player" + str(player_id + 1))
	if not player_container:
		# Create player container if it doesn't exist
		player_container = Node3D.new()
		player_container.name = "Player" + str(player_id + 1)
		map_root.add_child(player_container)

	player_container.add_child(unit_instance)

	# Record the home cell and resolve AI behavior (spawn-point override -> character
	# default). The spawner is the one place that knows BOTH the cell the unit was
	# placed on AND the authored override, so it is where a placement becomes a
	# holding guardian or an anchored boss. Read every turn by Bot/BossController.
	if unit_instance.has_method("configure_ai_behavior"):
		var norm: Dictionary = current_map.normalize_spawn(spawn_data)
		# The character's OWN declared stance (raw field, "" = no preference) so a unit
		# like blightcap (explicitly "aggressive") charges even when pre-placed.
		var char_stance: String = ""
		if character_resource != null and "default_ai_stance" in character_resource:
			char_stance = String(character_resource.default_ai_stance)
		var resolved_stance: String = resolve_default_ai_stance(
			String(norm.get("spawn_kind", MapResource.SPAWN_KIND_START)),
			String(norm.get("ai_stance", "")),
			char_stance)
		unit_instance.configure_ai_behavior(
			grid_pos,
			resolved_stance,
			int(norm.get("aggro_range", -1)),
			int(norm.get("leash_radius", -1)))

	# Announce the spawn so presentation systems (camera auto-focus) can frame it.
	# runtime=false for the initial load flood; true for reinforcement/endless waves.
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null and GameEvents.has_signal(&"unit_spawned"):
		GameEvents.unit_spawned.emit(unit_instance, runtime)

	return unit_instance


## World-facing yaw (radians) a unit spawned on [param grid_pos] should take so it faces
## the OPPOSING side, per [method Unit.spawn_facing_yaw]. Enemy rows (spawns of a different
## player_id) only break a dead-center-on-the-midline tie. Null-safe: with no current_map it
## defaults to a 5-row map with no enemy hints, so a unit spawned outside a loaded map still
## gets a sane south-facing default.
func _compute_spawn_facing(grid_pos: Vector2i, player_id: int) -> float:
	var map_h: int = 5
	var enemy_rows: Array = []
	if current_map != null:
		map_h = int(current_map.height)
		for sp in current_map.unit_spawns:
			var pid: int = int(sp.get("player_id", 0))
			if pid == player_id:
				continue
			var pos = sp.get("position", Vector2i(-1, -1))
			if pos is Vector2i and pos.y >= 0:
				enemy_rows.append(pos.y)
	return Unit.spawn_facing_yaw(grid_pos.y, map_h, enemy_rows)


## Resolve the AI stance a spawned unit should hold, given its spawn KIND and the
## authored `ai_stance` override. Precedence (highest first):
##   1. An explicit authored stance ("aggressive" / "defensive") ALWAYS wins.
##   2. Otherwise the default is chosen by spawn kind:
##        - Start        -> "defensive"  (pre-placed defenders HOLD until an enemy
##                          is in aggro range of their home cell)
##        - Respawn / Endless / Reinforcement -> "aggressive"  (waves CHARGE on arrival)
## This routes through BOTH the initial map load and every SpawnManager wave, because
## both go through _create_unit_from_spawn. NOTE: this changes the default for
## pre-placed enemies on ALL maps (Start now defaults to "defensive"); that is the
## intended "defenders defend" design. Any unrecognised value falls back to Start's
## "defensive" default. Static + pure so tests can assert it directly.
static func resolve_default_ai_stance(spawn_kind: String, authored_stance: String, character_default: String = "") -> String:
	# 1. Endless/Respawn ALWAYS charge -- even over an authored stance. These reuse a
	#    single home cell every wave, so a defensive unit that sat there would choke
	#    the point; forcing aggressive keeps the spot clearing for the next spawn.
	if spawn_kind == MapResource.SPAWN_KIND_ENDLESS \
			or spawn_kind == MapResource.SPAWN_KIND_RESPAWN:
		return "aggressive"
	# 2. A per-placement author override wins next. "dormant" (a neutral camp that holds
	#    until attacked) is honored here too -- but NOT for Endless/Respawn waves above,
	#    which always charge.
	if authored_stance == "aggressive" or authored_stance == "defensive" or authored_stance == "dormant":
		return authored_stance
	# 3. The character's OWN declared stance (e.g. blightcap = always aggressive). Only
	#    an EXPLICIT value counts; "" means "no preference, use the kind default below".
	if character_default == "aggressive" or character_default == "defensive":
		return character_default
	# 4. Default by kind: reinforcements charge; pre-placed (Start) hold.
	if spawn_kind == MapResource.SPAWN_KIND_REINFORCEMENT:
		return "aggressive"
	return "defensive"

func _difficulty_allows(character_resource) -> bool:
	"""True unless [param character_resource] demands a higher AI difficulty than the
	game is currently set to. A min_difficulty of 0 (Easy / the default) always
	passes, so this is a no-op for every character that has not opted in."""
	if character_resource == null or not character_resource.has_method("get_min_difficulty"):
		return true
	var required: int = character_resource.get_min_difficulty()
	if required <= 0:
		return true
	return _current_ai_difficulty() >= required


func _current_ai_difficulty() -> int:
	"""The live GameSettings.ai_difficulty (0..3), read off the autoload defensively
	so a headless/mock context with no autoload simply defaults to Normal and never
	gates anything out spuriously."""
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		var gs = (loop as SceneTree).root.get_node_or_null("GameSettings")
		if gs != null:
			var value = gs.get("ai_difficulty")
			if value != null:
				return int(value)
	return 1


func _resolve_character_id(character_id_raw, legacy_unit_type: String) -> String:
	"""Resolve a spawn's roster character id.

	Prefers an explicit character_id (String or StringName) from the spawn data.
	Falls back to LEGACY_UNIT_TYPE_TO_CHARACTER_ID keyed by the legacy unit_type
	string ("WARRIOR"/"ARCHER"/"MAGE") for spawns authored before the character
	system. Returns "" if neither resolves to anything.
	"""
	var explicit_id := String(character_id_raw) if character_id_raw != null else ""
	if not explicit_id.is_empty():
		return explicit_id

	var alias = LEGACY_UNIT_TYPE_TO_CHARACTER_ID.get(String(legacy_unit_type).to_upper(), &"")
	return String(alias)

func _emit_load_failed(error_message: String) -> void:
	"""Emit load failed signal with error message"""
	map_load_failed.emit(error_message)

# Static helper functions for map management
static func get_available_maps(include_drafts: bool = false) -> Array[String]:
	"""Get list of available map files.

	By default this returns only maps whose status is "Active" -- work-in-progress
	drafts (status "Inactive") are saved and loadable but kept out of the
	player-facing selection screens. Pass include_drafts = true for authoring
	tools (e.g. the Map Creator's load dialog) that should see everything.
	"""
	var maps: Array[String] = []
	var dir = DirAccess.open("res://game/maps/resources/")

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			if file_name.ends_with(".tres") and not file_name.begins_with("."):
				var map_path: String = "res://game/maps/resources/" + file_name
				if include_drafts or _is_active_map(map_path):
					maps.append(map_path)
			file_name = dir.get_next()

		dir.list_dir_end()

	return maps


## Directory the in-game Map Creator writes player-authored maps to, as inert JSON
## (never .tres - a shared .tres is an arbitrary-code-execution vector).
const CUSTOM_MAPS_DIR := "user://maps/"


## Available maps as ORIGIN-TAGGED ENTRIES, so a picker can badge player-made maps.
##
## Each entry is { "path": String, "origin": String, "name": String }:
##   origin == "builtin"  -> a res:// .tres shipped with the game (the same set
##                           [method get_available_maps] returns).
##   origin == "custom"   -> a user://maps/*.json map the player authored in the
##                           Map Creator. Load these with [method load_map_from_json_file].
##
## This is ADDITIVE: [method get_available_maps] (the Array[String] of .tres paths
## every existing screen consumes) is deliberately left untouched. New UI that wants
## the custom maps + the badge reads this instead.
static func get_available_map_entries(include_drafts: bool = false) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	# Built-in .tres maps: reuse the existing discovery so the active/draft rule and
	# the res:// directory scan never drift from get_available_maps.
	for map_path in get_available_maps(include_drafts):
		entries.append({
			"path": map_path,
			"origin": "builtin",
			"name": _map_name_for_tres(map_path)
		})

	# Player-authored JSON maps under user://maps/.
	var dir = DirAccess.open(CUSTOM_MAPS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json") and not file_name.begins_with("."):
				var json_path: String = CUSTOM_MAPS_DIR + file_name
				entries.append({
					"path": json_path,
					"origin": "custom",
					"name": _map_name_for_json(json_path, file_name)
				})
			file_name = dir.get_next()
		dir.list_dir_end()

	return entries


## Best-effort display name of a .tres map (the file stem if it will not load).
static func _map_name_for_tres(map_path: String) -> String:
	if ResourceLoader.exists(map_path):
		var res = load(map_path)
		if res is MapResource and not (res as MapResource).map_name.is_empty():
			return (res as MapResource).map_name
	return map_path.get_file().get_basename()


## Best-effort display name of a custom JSON map WITHOUT running the strict import
## (listing must not reject a draft the way loading-to-play does).
static func _map_name_for_json(json_path: String, file_name: String) -> String:
	if not FileAccess.file_exists(json_path):
		return file_name.get_basename()
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return file_name.get_basename()
	var text: String = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return file_name.get_basename()
	var map_info = (json.data as Dictionary).get("map_info", {})
	if map_info is Dictionary:
		var name_value: String = str((map_info as Dictionary).get("name", ""))
		if not name_value.is_empty():
			return name_value
	return file_name.get_basename()


## Load a player-authored JSON map from [param path] into the scene.
##
## Runs the HARDENED [method MapResource.import_from_json] (which validates the map
## against the live catalog and rejects unknown / out-of-bounds / oversized data by
## returning null), then hands the resulting resource to the normal [method load_map]
## path. Returns false - via the same map_load_failed signal as every other loader -
## when the file is missing, unreadable or fails validation.
func load_map_from_json_file(map_path: String, target_parent: Node3D) -> bool:
	if not FileAccess.file_exists(map_path):
		_emit_load_failed("Custom map file not found: " + map_path)
		return false

	var file = FileAccess.open(map_path, FileAccess.READ)
	if file == null:
		_emit_load_failed("Could not open custom map: " + map_path)
		return false
	var text: String = file.get_as_text()
	file.close()

	# quiet=true: this file is UNTRUSTED, SHARED content (a player's own save, a community
	# download, a map a networked host just shipped), so a rejection is an EXPECTED outcome for
	# bad input, not an impossible state. It is reported through map_load_failed + the false
	# return -- the engine log is for bugs (CONQUEST.md convention 1), and a push_error here
	# turned every test that covers this path red.
	var map_resource = MapResource.import_from_json(text, true)
	if map_resource == null:
		_emit_load_failed("Custom map failed validation: " + map_path)
		return false

	return load_map(map_resource, target_parent)


## Load just enough of a map to decide whether it is player-facing. A file that
## fails to load is treated as inactive rather than crashing the menus.
static func _is_active_map(map_path: String) -> bool:
	if not ResourceLoader.exists(map_path):
		return false
	var res = load(map_path)
	if res is MapResource:
		return (res as MapResource).is_active()
	return false

static func create_default_map() -> MapResource:
	"""Create a default 5x5 map for testing"""
	var map_resource = MapResource.new()
	map_resource.map_name = "Default Skirmish"
	map_resource.description = "A basic 5x5 map for quick battles"
	map_resource.author = "System"
	map_resource.width = 5
	map_resource.height = 5
	map_resource.max_players = 2
	map_resource.difficulty = "Normal"
	map_resource.map_type = "Skirmish"
	
	# Create default layout
	map_resource.create_default_layout()
	
	# Add sample spawns
	map_resource.create_sample_spawns()
	
	return map_resource

static func save_map(map_resource: MapResource, file_name: String) -> bool:
	"""Save a map resource to file"""
	if not map_resource or file_name.is_empty():
		return false
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute("res://game/maps/resources/"):
		DirAccess.open("res://").make_dir_recursive("game/maps/resources")
	
	# Clean filename
	var clean_name = file_name.to_lower().replace(" ", "_")
	if not clean_name.ends_with(".tres"):
		clean_name += ".tres"
	
	var save_path = "res://game/maps/resources/" + clean_name
	
	# Update last modified
	map_resource.last_modified = Time.get_datetime_string_from_system()
	
	# Save resource
	var result = ResourceSaver.save(map_resource, save_path)
	if result == OK:
		return true
	else:
		return false