class_name MapPreview3D
extends SubViewportContainer

## Live 3D render of a [MapResource] -- the map's real authored tile scenes (or a
## coloured box for tiles without a model) plus team-coloured spawn markers -- in
## its own SubViewport, on a slow turntable. Floor-aware: upper-floor tiles and
## spawns sit at [code]floor * Cells.FLOOR_HEIGHT[/code].
##
## Used by the Map Gallery (Compendium), the map picker's detail pane, and as the
## main menu's diorama background. Extracted from MapGallery so all three share
## one renderer and one set of caches.
##
##   var preview := MapPreview3D.new()
##   preview.custom_minimum_size = Vector2(480, 300)
##   parent.add_child(preview)
##   preview.show_map(map_res)

## tile_type -> fallback cell colour (also the legend / thumbnail palette).
const TILE_COLORS := {
	"NORMAL": Color("6f8f4e"),
	"PLAINS": Color("6f8f4e"),
	"GRASS": Color("6f8f4e"),
	"DIFFICULT_TERRAIN": Color("3f5e32"),
	"WATER": Color("3b6ea5"),
	"LAVA": Color("c0431f"),
	"WALL": Color("5a5450"),
	"ICE": Color("bcd8e6"),
	"SWAMP": Color("5b5a34"),
	"SACRED_GROUND": Color("c7a63b"),
	"CORRUPTED": Color("6b3f7a"),
}
const TILE_FALLBACK := Color("777777")
const PLAYER0_COLOR := Color("4a90d9")
const PLAYER1_COLOR := Color("d94a4a")
const PLAYER_FALLBACK := Color("e6a64b")

const TILE_STEP := 2.0
const TILE_MESH_SIZE := Vector3(1.8, 0.3, 1.8)
const SPAWN_RADIUS := 0.35
const SPAWN_Y := 0.5

enum Framing { GALLERY, DIORAMA }

## Radians per second of turntable spin (0 = still).
@export var turntable_speed: float = 0.35
## GALLERY: high 3/4 view that frames the whole map. DIORAMA: lower, closer,
## cinematic angle for a background.
@export var framing: Framing = Framing.GALLERY
## Transparent background (lets the menu backdrop show through).
@export var transparent: bool = false
@export var background_color: Color = Color(0.07, 0.08, 0.14, 1.0)
## Show spawn markers.
@export var show_spawns: bool = true
## Horizontal lens shift, in map spans (negative pushes the map to the right).
@export var lens_shift: float = 0.0
## Camera distance multiplier (1 = default framing).
@export var zoom_out: float = 1.0

var viewport: SubViewport
var map_root: Node3D
var camera: Camera3D
var current_map: MapResource

var _span: float = TILE_STEP
var _center_y: float = 0.0
var _tile_resource_cache: Dictionary = {}
var _tile_model_cache: Dictionary = {}
var _type_model_paths: Dictionary = {}
var _type_model_paths_built: bool = false


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_ensure_viewport()


func _ensure_viewport() -> void:
	if viewport != null:
		return
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.transparent_bg = transparent
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
	add_child(viewport)

	map_root = Node3D.new()
	map_root.name = "MapRoot"
	viewport.add_child(map_root)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 40.0 if framing == Framing.DIORAMA else 50.0
	viewport.add_child(camera)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR if transparent else Environment.BG_COLOR
	env.background_color = background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.55, 0.62, 1.0)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	camera.environment = env

	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.light_energy = 1.15
	light.light_color = Color(1.0, 0.94, 0.84)
	light.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	viewport.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.72, 1.0)
	fill.rotation_degrees = Vector3(-30.0, -140.0, 0.0)
	viewport.add_child(fill)
	_aim_camera()


## Render [param map_res] (null clears the preview).
func show_map(map_res: MapResource) -> void:
	_ensure_viewport()
	current_map = map_res
	for child in map_root.get_children():
		map_root.remove_child(child)
		child.queue_free()
	map_root.rotation = Vector3.ZERO
	if map_res == null:
		return

	var cols: int = maxi(map_res.width, 1)
	var rows: int = maxi(map_res.height, 1)
	var floors: int = 1
	if map_res.has_method("get_floor_count"):
		floors = maxi(map_res.get_floor_count(), 1)
	_span = maxf(float(cols), float(rows)) * TILE_STEP
	_center_y = float(floors - 1) * _floor_height() * 0.5
	_aim_camera()

	var off_x: float = float(cols - 1) * TILE_STEP * 0.5
	var off_z: float = float(rows - 1) * TILE_STEP * 0.5

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = TILE_MESH_SIZE
	var spawn_mesh := SphereMesh.new()
	spawn_mesh.radius = SPAWN_RADIUS
	spawn_mesh.height = SPAWN_RADIUS * 2.0

	# Floor 0 is implicitly full: cells with no explicit entry are default tiles.
	var explicit_ground := {}
	for entry in map_res.tile_layout:
		var pos := read_pos(entry.get("position", Vector2i.ZERO))
		var fl := int(entry.get("floor", 0))
		if pos.x < 0 or pos.x >= cols or pos.y < 0 or pos.y >= rows:
			continue
		if fl == 0:
			explicit_ground[pos] = true
		var tile_type := read_tile_type(entry)
		var visual: Node3D = _instantiate_tile_model(entry, tile_type)
		if visual == null:
			visual = _box(tile_mesh, TILE_COLORS.get(tile_type, TILE_FALLBACK))
		map_root.add_child(visual)
		visual.position = Vector3(float(pos.x) * TILE_STEP - off_x, float(fl) * _floor_height(),
			float(pos.y) * TILE_STEP - off_z)
	for x in cols:
		for y in rows:
			if explicit_ground.has(Vector2i(x, y)):
				continue
			var filler: Node3D = _instantiate_tile_model({}, "NORMAL")
			if filler == null:
				filler = _box(tile_mesh, TILE_COLORS["NORMAL"])
			map_root.add_child(filler)
			filler.position = Vector3(float(x) * TILE_STEP - off_x, 0.0, float(y) * TILE_STEP - off_z)

	if not show_spawns:
		return
	for spawn in map_res.unit_spawns:
		var pos := read_pos(spawn.get("position", Vector2i.ZERO))
		if pos.x < 0 or pos.x >= cols or pos.y < 0 or pos.y >= rows:
			continue
		var pid := int(spawn.get("player_id", -1))
		var color := PLAYER_FALLBACK
		if pid == 0:
			color = PLAYER0_COLOR
		elif pid == 1:
			color = PLAYER1_COLOR
		var marker := MeshInstance3D.new()
		marker.mesh = spawn_mesh
		marker.material_override = _material(color, true)
		marker.position = Vector3(float(pos.x) * TILE_STEP - off_x,
			SPAWN_Y + float(int(spawn.get("floor", 0))) * _floor_height(),
			float(pos.y) * TILE_STEP - off_z)
		map_root.add_child(marker)


func _process(delta: float) -> void:
	if map_root != null and turntable_speed != 0.0:
		map_root.rotate_y(turntable_speed * delta)


func _aim_camera() -> void:
	if camera == null:
		return
	var target := Vector3(0.0, _center_y, 0.0)
	var d := _span * zoom_out
	if framing == Framing.DIORAMA:
		camera.look_at_from_position(target + Vector3(0.0, d * 0.5, d * 0.95), target, Vector3.UP)
	else:
		camera.look_at_from_position(target + Vector3(0.0, d * 0.9, d * 0.7), target, Vector3.UP)
	camera.h_offset = lens_shift * _span


static func _floor_height() -> float:
	return Cells.FLOOR_HEIGHT


func _box(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color)
	return mi


static func _material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
	return mat


# --- Tile geometry (cached; a broken path falls back to the box, never retried) --

func _load_tile_resource(path: String) -> TileResource:
	if path.is_empty():
		return null
	if _tile_resource_cache.has(path):
		return _tile_resource_cache[path] as TileResource
	var res: TileResource = null
	if ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is TileResource:
			res = loaded
	_tile_resource_cache[path] = res
	return res


func _build_type_model_paths() -> void:
	if _type_model_paths_built:
		return
	_type_model_paths_built = true
	var type_names: Array = Tile.TileType.keys()
	for tile_path in TileCatalog.all_paths():
		var tr := _load_tile_resource(tile_path)
		if tr == null or tr.model_path.is_empty():
			continue
		var idx: int = int(tr.tile_type)
		if idx < 0 or idx >= type_names.size():
			continue
		var tname: String = str(type_names[idx])
		if not _type_model_paths.has(tname):
			_type_model_paths[tname] = tr.model_path


func _load_tile_model(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _tile_model_cache.has(path):
		return _tile_model_cache[path] as PackedScene
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is PackedScene:
			packed = loaded
	_tile_model_cache[path] = packed
	return packed


func _tile_model_path(entry: Dictionary, tile_type: String) -> String:
	var rp := str(entry.get("tile_resource_path", ""))
	if not rp.is_empty():
		var tr := _load_tile_resource(rp)
		if tr != null:
			return tr.model_path
	_build_type_model_paths()
	return str(_type_model_paths.get(tile_type, ""))


func _instantiate_tile_model(entry: Dictionary, tile_type: String) -> Node3D:
	var packed := _load_tile_model(_tile_model_path(entry, tile_type))
	if packed == null:
		return null
	var inst = packed.instantiate()
	if inst is Node3D:
		return inst
	if inst != null:
		inst.free()
	return null


# --- Entry readers (shared with MapThumbnail / MapGallery) ------------------------

static func read_tile_type(entry: Dictionary) -> String:
	return str(entry.get("tile_type", "NORMAL")).to_upper()


static func read_pos(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO


## Top-down 2D minimap texture (for map cards): one [param cell_px] square per
## cell coloured by tile type (the TOP floor wins, lightened), team spawn dots.
static func thumbnail(map_res: MapResource, cell_px: int = 8) -> ImageTexture:
	if map_res == null:
		return null
	var cols: int = maxi(map_res.width, 1)
	var rows: int = maxi(map_res.height, 1)
	var img := Image.create(cols * cell_px, rows * cell_px, false, Image.FORMAT_RGBA8)
	img.fill(TILE_COLORS["NORMAL"].darkened(0.1))
	var top_floor := {}
	for entry in map_res.tile_layout:
		var pos := read_pos(entry.get("position", Vector2i.ZERO))
		if pos.x < 0 or pos.x >= cols or pos.y < 0 or pos.y >= rows:
			continue
		var fl := int(entry.get("floor", 0))
		if top_floor.has(pos) and int(top_floor[pos]) > fl:
			continue
		top_floor[pos] = fl
		var c: Color = TILE_COLORS.get(read_tile_type(entry), TILE_FALLBACK)
		if fl > 0:
			c = c.lightened(0.28)
		img.fill_rect(Rect2i(pos.x * cell_px, pos.y * cell_px, cell_px, cell_px), c)
	# Grid lines for readability.
	var line := Color(0, 0, 0, 0.22)
	for x in range(1, cols):
		img.fill_rect(Rect2i(x * cell_px, 0, 1, rows * cell_px), line)
	for y in range(1, rows):
		img.fill_rect(Rect2i(0, y * cell_px, cols * cell_px, 1), line)
	for spawn in map_res.unit_spawns:
		var pos := read_pos(spawn.get("position", Vector2i.ZERO))
		if pos.x < 0 or pos.x >= cols or pos.y < 0 or pos.y >= rows:
			continue
		var pid := int(spawn.get("player_id", -1))
		var col := PLAYER0_COLOR if pid == 0 else (PLAYER1_COLOR if pid == 1 else PLAYER_FALLBACK)
		var inset: int = maxi(1, cell_px / 5)
		img.fill_rect(Rect2i(pos.x * cell_px + inset, pos.y * cell_px + inset,
			cell_px - inset * 2, cell_px - inset * 2), col.lightened(0.15))
	return ImageTexture.create_from_image(img)
