extends RefCounted
class_name TerrainMask

## Publishes a tiny per-cell TERRAIN CLASS texture of the loaded map's floor 0 as
## project-wide global shader uniforms (see tile_objects/tiles/shaders/world_lib.gdshaderinc
## and docs/WORLD_ART.md). Every stylized world shader reads it so terrain reads as
## ONE continuous landscape:
##   * water draws soft shoreline foam wherever land is near,
##   * dirt paths grow a painted grass fringe toward grass neighbours,
##   * the world skirt continues each edge biome (rivers flow off the board,
##     roads continue for a while, grass everywhere else).
##
## Channels: R = water, G = dirt / path / paving, B = lava, A = grass-ish land.
## The texture covers the board plus [constant MARGIN] cells on every side; margin
## cells copy the nearest edge cell (dirt / lava fade back to grass after a few
## cells). Linear filtering then blends classes exactly across cell borders.
##
## Purely visual and deterministic: nothing here touches the board, pathing or
## CombatServices. [method class_at] lets CPU-side builders (WorldSkirt) read the
## very same classes the shaders see.

const MARGIN := 48
const CELL := 2.0
## How many cells a dirt road / lava flow keeps going past the board edge.
const ROAD_RUN := 7
const LAVA_RUN := 3

## How many built masks [method mask_for] keeps (story areas are revisited constantly; a
## mask is ~15 k pixels, so a handful costs a few hundred KB).
const CACHE_SIZE := 8

static var _img: Image = null
static var _tex: ImageTexture = null
static var _w: int = 0
static var _h: int = 0
## content key ([method content_key]) -> built mask Image, oldest first ([constant CACHE_SIZE]).
static var _cache: Dictionary = {}


## Build + publish the mask for [param map]. Safe headless (RenderingServer calls
## are no-ops on the dummy renderer). A map whose mask was built before (a revisited story
## area, a replayed battle map) reuses it ([method mask_for]).
static func publish(map: MapResource) -> void:
	if map == null:
		return
	_w = maxi(1, int(map.width))
	_h = maxi(1, int(map.height))
	var tw := _w + MARGIN * 2
	var th := _h + MARGIN * 2
	_img = mask_for(map)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.set_image(_img)
	var rs := RenderingServer
	rs.global_shader_parameter_set(&"terrain_mask", _tex)
	rs.global_shader_parameter_set(&"terrain_mask_rect", Vector4(-MARGIN * CELL, -MARGIN * CELL, tw * CELL, th * CELL))
	rs.global_shader_parameter_set(&"terrain_mask_on", 1.0)
	rs.global_shader_parameter_set(&"board_rect", Vector4(0.0, 0.0, _w * CELL, _h * CELL))


## Identity of what the mask (and everything built from it, e.g. the [WorldSkirt]) depends on:
## the board size and its tile layout. Two loads of the same map -- or an edited copy with the
## same tiles -- share a key; any tile change makes a new one.
static func content_key(map: MapResource) -> int:
	if map == null:
		return 0
	return [int(map.width), int(map.height), map.tile_layout].hash()


## The class mask for [param map] (cached per [method content_key]). Never mutate the result.
static func mask_for(map: MapResource) -> Image:
	var key := content_key(map)
	if _cache.has(key):
		var hit: Image = _cache[key]
		_cache.erase(key)   # re-insert: most recently used last
		_cache[key] = hit
		return hit
	var img := build_image(map)
	store_mask(key, img)
	return img


## Keep a mask built elsewhere (a background prewarm) under [param key] ([method content_key]).
static func store_mask(key: int, img: Image) -> void:
	if img == null:
		return
	_cache[key] = img
	while _cache.size() > CACHE_SIZE:
		_cache.erase(_cache.keys()[0])


## Build the class mask of [param map] (board + [constant MARGIN] cells each side). Pure: reads
## only the map, touches no static state.
static func build_image(map: MapResource) -> Image:
	var w := maxi(1, int(map.width))
	var h := maxi(1, int(map.height))
	var tw := w + MARGIN * 2
	var th := h + MARGIN * 2
	var board: Array = []  # [x][y] -> Color
	board.resize(w)
	# One pass over the layout (get_tile_at_position is a linear scan per call).
	var lookup: Dictionary = map.build_tile_lookup()
	for x in w:
		var col: Array = []
		col.resize(h)
		for y in h:
			var entry: Dictionary = MapResource.tile_from_lookup(lookup, Vector2i(x, y))
			col[y] = classify(MapLoader.resolve_tile_resource_for_entry(entry), entry)
		board[x] = col
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	for ty in th:
		for tx in tw:
			var bx := tx - MARGIN
			var by := ty - MARGIN
			var cx := clampi(bx, 0, w - 1)
			var cy := clampi(by, 0, h - 1)
			var c: Color = board[cx][cy]
			var out := maxi(absi(bx - cx), absi(by - cy))
			if out > 0:
				# Corner quadrants would smear the corner cell diagonally forever:
				# only straight continuations keep their class there.
				if bx != cx and by != cy:
					c = Color(0, 0, 0, 1)
				else:
					c = _continue(c, out, bx, by)
			img.set_pixel(tx, ty, c)
	return img


## Terrain class colour for one resolved tile.
static func classify(res: TileResource, entry: Dictionary = {}) -> Color:
	var id := ""
	if res != null:
		id = String(res.get_id()).to_lower()
	else:
		id = String(entry.get("tile_id", "")).to_lower()
	var ttype := -1
	if res != null:
		ttype = int(res.tile_type)
	else:
		var tname := String(entry.get("tile_type", "NORMAL")).to_upper()
		ttype = Tile.TileType.keys().find(tname)
	if ttype == Tile.TileType.WATER or id.contains("water"):
		return Color(1, 0, 0, 0)
	if ttype == Tile.TileType.LAVA or id.contains("lava") or id.contains("magma"):
		return Color(0, 0, 1, 0)
	if id.contains("dirt") or id.contains("flagstone") or id.contains("plank") or id.contains("path"):
		return Color(0, 1, 0, 0)
	if res != null and res.material_style == TileResource.MaterialStyle.GRASS:
		return Color(0, 0, 0, 1)
	if ttype in [Tile.TileType.NORMAL, Tile.TileType.WALL, Tile.TileType.SACRED_GROUND, Tile.TileType.DIFFICULT_TERRAIN]:
		# Walls, shrines and generic ground sit in grass as far as the world cares.
		return Color(0, 0, 0, 1)
	return Color(0, 0, 0, 0)


## Class of a margin cell [param out] cells beyond the board edge.
static func _continue(c: Color, out: int, bx: int, by: int) -> Color:
	var jitter := int(ProcMesh.hash01(bx, by, 17) * 3.0)
	if c.g > 0.5 and out > ROAD_RUN + jitter:
		return Color(0, 0, 0, 1)
	if c.b > 0.5 and out > LAVA_RUN + jitter:
		return Color(0, 0, 0, 1)
	if c.r < 0.5 and c.g < 0.5 and c.b < 0.5:
		return Color(0, 0, 0, 1)
	return c


## CPU read of the published classes at board cell ([param x], [param y]) (may lie
## outside the board, within the margin). Returns grass beyond the texture.
static func class_at(x: int, y: int) -> Color:
	return class_in(_img, x, y)


## [method class_at] against a given mask [param img] (a [method mask_for] result) rather than
## the published one -- what a builder running off the main thread reads.
static func class_in(img: Image, x: int, y: int) -> Color:
	if img == null:
		return Color(0, 0, 0, 1)
	var tx := x + MARGIN
	var ty := y + MARGIN
	if tx < 0 or ty < 0 or tx >= img.get_width() or ty >= img.get_height():
		return Color(0, 0, 0, 1)
	return img.get_pixel(tx, ty)


static func board_size() -> Vector2i:
	return Vector2i(_w, _h)
