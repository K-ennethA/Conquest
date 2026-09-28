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

static var _img: Image = null
static var _tex: ImageTexture = null
static var _w: int = 0
static var _h: int = 0


## Build + publish the mask for [param map]. Safe headless (RenderingServer calls
## are no-ops on the dummy renderer).
static func publish(map: MapResource) -> void:
	if map == null:
		return
	_w = maxi(1, int(map.width))
	_h = maxi(1, int(map.height))
	var tw := _w + MARGIN * 2
	var th := _h + MARGIN * 2
	var board: Array = []  # [x][y] -> Color
	board.resize(_w)
	for x in _w:
		var col: Array = []
		col.resize(_h)
		for y in _h:
			var entry: Dictionary = map.get_tile_at_position(Vector2i(x, y))
			col[y] = classify(MapLoader.resolve_tile_resource_for_entry(entry), entry)
		board[x] = col
	_img = Image.create(tw, th, false, Image.FORMAT_RGBA8)
	for ty in th:
		for tx in tw:
			var bx := tx - MARGIN
			var by := ty - MARGIN
			var cx := clampi(bx, 0, _w - 1)
			var cy := clampi(by, 0, _h - 1)
			var c: Color = board[cx][cy]
			var out := maxi(absi(bx - cx), absi(by - cy))
			if out > 0:
				# Corner quadrants would smear the corner cell diagonally forever:
				# only straight continuations keep their class there.
				if bx != cx and by != cy:
					c = Color(0, 0, 0, 1)
				else:
					c = _continue(c, out, bx, by)
			_img.set_pixel(tx, ty, c)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.set_image(_img)
	var rs := RenderingServer
	rs.global_shader_parameter_set(&"terrain_mask", _tex)
	rs.global_shader_parameter_set(&"terrain_mask_rect", Vector4(-MARGIN * CELL, -MARGIN * CELL, tw * CELL, th * CELL))
	rs.global_shader_parameter_set(&"terrain_mask_on", 1.0)
	rs.global_shader_parameter_set(&"board_rect", Vector4(0.0, 0.0, _w * CELL, _h * CELL))


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
	if _img == null:
		return Color(0, 0, 0, 1)
	var tx := x + MARGIN
	var ty := y + MARGIN
	if tx < 0 or ty < 0 or tx >= _img.get_width() or ty >= _img.get_height():
		return Color(0, 0, 0, 1)
	return _img.get_pixel(tx, ty)


static func board_size() -> Vector2i:
	return Vector2i(_w, _h)
