class_name MapPreview
extends RefCounted

## Renders a [MapResource]'s tile_layout into a crisp top-down 2D MINIMAP texture,
## with NO SubViewport and NO 3D: it walks the tile entries, paints one flat cell of
## colour per tile straight into an [Image], overlays spawn points as small squares,
## and hands back an [ImageTexture]. Pair the result with a [TextureRect] whose
## [code]texture_filter[/code] is NEAREST (see [method make_texture_rect]) for a clean
## pixel-art look when the minimap is scaled up in a preview pane.
##
## Colour source, most trustworthy first (see [method _tile_color]):
##   1. the tile's authored [member TileResource.base_color], resolved through
##      [TileCatalog] by stable [code]tile_id[/code] then legacy path -- so the minimap
##      matches the colours a map author actually chose;
##   2. a coarse per-[code]tile_type[/code] family palette ([constant TYPE_PALETTE])
##      when the tile can't be resolved (e.g. its asset is missing);
##   3. [constant UNKNOWN_COLOR] for anything still unrecognised.
##
## Everything is static and side-effect free; callers cache the returned texture per
## map path themselves (regenerating is cheap, but the cache avoids redundant loads).

# --- Sizing -----------------------------------------------------------------
## Longest edge of the generated image, in pixels. The per-cell size is chosen so the
## bigger map dimension lands at or under this, keeping textures small and uniform.
const DEFAULT_MAX_PX := 256
## Per-cell pixel size is clamped into this range: big enough to read on small maps,
## small enough that a 40x40 map still fits under [constant DEFAULT_MAX_PX].
const MIN_CELL_PX := 4
const MAX_CELL_PX := 12

# --- Colours ----------------------------------------------------------------
## Neutral ground painted first, so cells with no tile entry (sparse maps) and the
## letterbox gaps read as empty board rather than transparent holes.
const GROUND_COLOR := Color(0.12, 0.11, 0.16, 1.0)
## Fallback when a tile resolves to neither a resource colour nor a known type.
const UNKNOWN_COLOR := Color(0.42, 0.40, 0.48, 1.0)
## Thin darkened edge blended under each cell so adjacent cells stay distinct.
const GRID_COLOR := Color(0.0, 0.0, 0.0, 0.22)

## Coarse fallback palette keyed by [enum Tile.TileType] name (see MapResource tile
## entries' "tile_type"). Only used when the real tile resource can't be resolved.
const TYPE_PALETTE := {
	"NORMAL": Color(0.40, 0.70, 0.34, 1.0),            # grass green
	"DIFFICULT_TERRAIN": Color(0.34, 0.52, 0.24, 1.0), # scrub / brush
	"WATER": Color(0.20, 0.42, 0.80, 1.0),             # water blue
	"WALL": Color(0.34, 0.34, 0.36, 1.0),              # stone grey
	"SPECIAL": Color(0.80, 0.66, 0.36, 1.0),           # marked / gold-ish
	"LAVA": Color(0.92, 0.32, 0.10, 1.0),              # molten orange
	"ICE": Color(0.68, 0.86, 0.92, 1.0),               # pale ice blue
	"SWAMP": Color(0.36, 0.42, 0.28, 1.0),             # murky green
	"SACRED_GROUND": Color(0.86, 0.82, 0.52, 1.0),     # hallowed pale gold
	"CORRUPTED": Color(0.44, 0.24, 0.46, 1.0),         # blighted purple
}

## Spawn-marker colours by player slot. Slot 0 is the player (warm gold, matching the
## menu accent); every other slot reads as a red/orange enemy family.
const PLAYER_0_COLOR := Color(0.90, 0.65, 0.29, 1.0)   # gold -- "you"
const ENEMY_COLORS := [
	Color(0.85, 0.24, 0.22, 1.0),  # crimson
	Color(0.90, 0.45, 0.18, 1.0),  # orange-red
	Color(0.80, 0.22, 0.44, 1.0),  # magenta-red
	Color(0.70, 0.20, 0.20, 1.0),  # dark red
]


## Build the minimap texture for [param map], or [code]null[/code] when there is
## nothing to draw (missing map, zero size, or an empty tile_layout). Callers show a
## neutral placeholder on null.
static func generate(map: MapResource, max_px: int = DEFAULT_MAX_PX, max_cell: int = MAX_CELL_PX) -> ImageTexture:
	if map == null:
		return null
	var cols: int = maxi(0, map.width)
	var rows: int = maxi(0, map.height)
	if cols <= 0 or rows <= 0:
		return null
	if map.tile_layout.is_empty() and map.unit_spawns.is_empty():
		return null

	var long_side: int = maxi(cols, rows)
	var cell: int = clampi(int(float(max_px) / float(long_side)), MIN_CELL_PX, maxi(MIN_CELL_PX, max_cell))

	var img_w: int = cols * cell
	var img_h: int = rows * cell
	var image := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	image.fill(GROUND_COLOR)

	# --- Terrain: one flat cell per tile entry ------------------------------
	# Memoise resolved colours per tile_id/path within this pass so a map that reuses
	# one tile hundreds of times only loads (and colour-derives) it once.
	var color_cache: Dictionary = {}
	for entry in map.tile_layout:
		if not (entry is Dictionary):
			continue
		var pos: Vector2i = entry.get("position", Vector2i(-1, -1))
		if pos.x < 0 or pos.x >= cols or pos.y < 0 or pos.y >= rows:
			continue
		var color: Color = _tile_color(entry, color_cache)
		_fill_cell(image, pos, cell, color)

	# --- Spawns: small centred marker per spawn point -----------------------
	for spawn in map.unit_spawns:
		if not (spawn is Dictionary):
			continue
		var pos: Vector2i = spawn.get("position", Vector2i(-1, -1))
		if pos.x < 0 or pos.x >= cols or pos.y < 0 or pos.y >= rows:
			continue
		var player_id: int = int(spawn.get("player_id", 0))
		_draw_spawn_marker(image, pos, cell, _player_color(player_id))

	return ImageTexture.create_from_image(image)


## Convenience: a ready-to-add [TextureRect] showing [param texture] with NEAREST
## filtering (crisp pixels) and aspect kept + centred (letterboxes non-square maps).
static func make_texture_rect(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return rect


# --- Internals --------------------------------------------------------------

## Colour for one tile entry: authored resource colour first, then type palette.
static func _tile_color(entry: Dictionary, cache: Dictionary) -> Color:
	var tile_id_str: String = str(entry.get("tile_id", ""))
	if not tile_id_str.is_empty():
		if cache.has(tile_id_str):
			return cache[tile_id_str]
		var res := TileCatalog.find_by_id(StringName(tile_id_str))
		if res != null:
			var c: Color = _opaque(res.base_color)
			cache[tile_id_str] = c
			return c

	var path_str: String = str(entry.get("tile_resource_path", ""))
	if not path_str.is_empty():
		var key := "path:" + path_str
		if cache.has(key):
			return cache[key]
		var res2 := TileCatalog.find(path_str)
		if res2 != null:
			var c2: Color = _opaque(res2.base_color)
			cache[key] = c2
			return c2

	var type_str: String = str(entry.get("tile_type", "NORMAL")).to_upper()
	return TYPE_PALETTE.get(type_str, UNKNOWN_COLOR)


## Spawn-marker colour: gold for the player (slot 0), a red family for enemies.
static func _player_color(player_id: int) -> Color:
	if player_id <= 0:
		return PLAYER_0_COLOR
	return ENEMY_COLORS[(player_id - 1) % ENEMY_COLORS.size()]


## Force full opacity: a tile's authored base_color may carry a stray alpha, but a
## minimap cell must be solid.
static func _opaque(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 1.0)


## Paint the full cell at grid [param pos], then darken its bottom/right edge so
## neighbouring cells of the same colour still separate visually.
static func _fill_cell(image: Image, pos: Vector2i, cell: int, color: Color) -> void:
	var x0: int = pos.x * cell
	var y0: int = pos.y * cell
	image.fill_rect(Rect2i(x0, y0, cell, cell), color)
	if cell >= 4:
		var edged: Color = color.blend(GRID_COLOR)
		image.fill_rect(Rect2i(x0, y0 + cell - 1, cell, 1), edged)  # bottom edge
		image.fill_rect(Rect2i(x0 + cell - 1, y0, 1, cell), edged)  # right edge


## Draw a small filled square centred in the cell at [param pos].
static func _draw_spawn_marker(image: Image, pos: Vector2i, cell: int, color: Color) -> void:
	var marker: int = maxi(2, int(round(float(cell) * 0.6)))
	marker = mini(marker, cell)
	var inset: int = (cell - marker) / 2
	var x0: int = pos.x * cell + inset
	var y0: int = pos.y * cell + inset
	image.fill_rect(Rect2i(x0, y0, marker, marker), color)
