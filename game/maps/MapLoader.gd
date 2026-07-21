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
const DEFAULT_CHARACTER_ID: StringName = &"torvald_ironhide"

# Legacy "unit_type" string -> roster CharacterResource id. Used to resolve
# spawns authored before the character system (no "character_id" set) to a
# fitting character so old maps keep loading with character-backed units.
const LEGACY_UNIT_TYPE_TO_CHARACTER_ID: Dictionary = {
	"WARRIOR": &"torvald_ironhide",
	"ARCHER": &"sable_quickarrow",
	"MAGE": &"ysolde_emberwynn",
}

func _ready():
	print("MapLoader initialized")

func load_map(map_resource: MapResource, target_parent: Node3D) -> bool:
	"""Load a map from MapResource into the scene"""
	if not map_resource:
		_emit_load_failed("Invalid map resource")
		return false
	
	print("Loading map: " + map_resource.map_name)
	
	# Validate map
	var validation = map_resource.validate_map()
	if not validation.valid:
		var error_msg = "Map validation failed: " + str(validation.issues)
		_emit_load_failed(error_msg)
		return false
	
	# Clear existing map if any
	clear_current_map()
	
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
	
	print("Map loaded successfully: " + map_resource.map_name)
	map_loaded.emit(map_resource)
	return true

func _sync_grid_size(map_resource) -> void:
	"""Resize the shared board grid to match the loaded map (see load_map)."""
	var grid = load("res://board/Grid.tres")
	if grid == null:
		return
	var w: int = maxi(1, int(map_resource.width))
	var h: int = maxi(1, int(map_resource.height))
	grid.size = Vector3(w, 0, h)
	print("[MapLoader] Grid size synced to map: %dx%d" % [w, h])

func load_map_from_file(map_path: String, target_parent: Node3D) -> bool:
	"""Load a map from a .tres file"""
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
	
	current_map = null
	print("Current map cleared")

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
	print("Loading tiles for " + str(map_size.x) + "x" + str(map_size.y) + " map")
	
	# Create tiles for each position
	for x in range(map_size.x):
		for y in range(map_size.y):
			var pos = Vector2i(x, y)
			var tile_data = current_map.get_tile_at_position(pos)
			
			if not _create_tile_at_position(pos, tile_data):
				print("Failed to create tile at position: " + str(pos))
				return false
	
	print("Loaded " + str(map_size.x * map_size.y) + " tiles")
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
					push_warning("MapLoader: model_path is not a PackedScene, using default tile: " + model_path)
			else:
				push_warning("MapLoader: model_path not found, using default tile: " + model_path)

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
	
	print("Loading unit spawns...")
	
	var units_created = 0
	for spawn_data in current_map.unit_spawns:
		# Spawn POINTS describe when they produce units, not just where. Only the
		# ones that seed a unit at load time are materialised here - a Reinforcement
		# scheduled for turn 5 must stay empty until the turn system activates it.
		# Maps authored before spawn_kind existed default to "Start", so they are
		# all initial and load exactly as they always did.
		if not current_map.is_initial_spawn(spawn_data):
			print("[MapLoader] Deferred spawn point (kind %s, turn %d) at %s - not spawned at load" % [
				current_map.get_spawn_kind(spawn_data),
				int(spawn_data.get("spawn_turn", 1)),
				str(spawn_data.get("position", Vector2i(-1, -1)))])
			continue

		# An initial point with no unit reference is an UNASSIGNED SLOT, filled at
		# match setup - not an error, and specifically not a reason to conjure a
		# default WARRIOR onto the board.
		if not current_map.spawn_has_unit_reference(spawn_data):
			print("[MapLoader] Unassigned spawn slot at %s (player %d) - left empty for match setup" % [
				str(spawn_data.get("position", Vector2i(-1, -1))),
				int(spawn_data.get("player_id", 0))])
			continue

		if _create_unit_from_spawn(spawn_data, units_created):
			units_created += 1
		else:
			print("Failed to create unit from spawn: " + str(spawn_data))

	print("Created " + str(units_created) + " units")
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
	return _create_unit_from_spawn(spawn_data, count_hint)

func _create_unit_from_spawn(spawn_data: Dictionary, units_created: int) -> Node:
	"""Create a unit from spawn data. Returns the new unit node, or null on failure."""
	print("[MapLoader] Creating unit from spawn data: " + str(spawn_data))

	var grid_pos = spawn_data.get("position", Vector2i(-1, -1))
	var player_id_raw = spawn_data.get("player_id", 0)

	print("[MapLoader] player_id_raw type: " + str(typeof(player_id_raw)) + ", value: " + str(player_id_raw))

	var player_id = int(player_id_raw) if player_id_raw is String else player_id_raw  # Ensure int

	print("[MapLoader] player_id after conversion: " + str(player_id) + " (type: " + str(typeof(player_id)) + ")")

	var unit_type = spawn_data.get("unit_type", "WARRIOR")
	var character_id_raw = spawn_data.get("character_id", "")

	if grid_pos == Vector2i(-1, -1):
		print("[MapLoader] Invalid grid position, skipping unit")
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
		print("[MapLoader] Could not resolve character '" + character_id + "', falling back to default character '" + String(DEFAULT_CHARACTER_ID) + "'")
		character_id = String(DEFAULT_CHARACTER_ID)
		character_resource = CharacterLibrary.get_character(character_id)

	if not character_resource:
		print("[MapLoader] Failed to resolve default character '" + String(DEFAULT_CHARACTER_ID) + "', skipping unit")
		return null

	# Difficulty gate: a character can require a minimum AI difficulty (e.g. a
	# parasite that only appears on Hard+). Applies to every spawn path because both
	# _load_units and SpawnManager route through here. Skips quietly below the bar.
	if not _difficulty_allows(character_resource):
		print("[MapLoader] Skipping '%s' -- min_difficulty %d exceeds current difficulty %d" % [
			character_id, character_resource.get_min_difficulty(), _current_ai_difficulty()])
		return null

	# Every unit is a CharacterUnit.tscn instance backed by a CharacterResource.
	var unit_instance = character_unit_scene.instantiate()
	if not unit_instance:
		print("[MapLoader] Failed to instantiate CharacterUnit.tscn")
		return null

	# Must be assigned BEFORE add_child: Unit._ready() (tile_objects/units/unit.gd)
	# derives its UnitStats + combat components from character_resource only
	# while it's already set when the node enters the tree.
	unit_instance.character_resource = character_resource

	# Set unit name
	var name_hint = character_id if not character_id.is_empty() else unit_type
	unit_instance.name = name_hint + str(units_created + 1)
	print("[MapLoader] Created unit: " + unit_instance.name)

	# Calculate world position (units spawn at Y=1.5 above tiles)
	var world_pos = Vector3(grid_pos.x * 2 + 1, 1.5, grid_pos.y * 2 + 1)
	unit_instance.transform.origin = world_pos

	# Add to appropriate player container
	print("[MapLoader] Looking for player container: Player" + str(player_id + 1))
	var player_container = map_root.get_node_or_null("Player" + str(player_id + 1))
	if not player_container:
		# Create player container if it doesn't exist
		print("[MapLoader] Creating player container: Player" + str(player_id + 1))
		player_container = Node3D.new()
		player_container.name = "Player" + str(player_id + 1)
		map_root.add_child(player_container)

	player_container.add_child(unit_instance)
	print("[MapLoader] Unit added to player container successfully")

	# Record the home cell and resolve AI behavior (spawn-point override -> character
	# default). The spawner is the one place that knows BOTH the cell the unit was
	# placed on AND the authored override, so it is where a placement becomes a
	# holding guardian or an anchored boss. Read every turn by Bot/BossController.
	if unit_instance.has_method("configure_ai_behavior"):
		var norm: Dictionary = current_map.normalize_spawn(spawn_data)
		unit_instance.configure_ai_behavior(
			grid_pos,
			String(norm.get("ai_stance", "")),
			int(norm.get("aggro_range", -1)),
			int(norm.get("leash_radius", -1)))

	return unit_instance

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
	print("Map load failed: " + error_message)
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
		print("Map saved: " + save_path)
		return true
	else:
		print("Failed to save map: " + str(result))
		return false