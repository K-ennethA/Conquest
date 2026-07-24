extends AbilityCondition
class_name OnTerrainTagCondition

## Met while the unit stands on a tile carrying [member tag] in its
## [member TileResource.special_properties] — the broad, category-keyed sibling of
## [OnTerrainCondition].
##
## [OnTerrainCondition] matches ONE terrain id, so "empowered anywhere in the
## forest" would have to be authored as an [AnyCondition] over every forest tile
## id — five today (grass_plains, tall_grass, tree, sacred_meadow, forest_dirt)
## and silently wrong the moment a sixth is added. Tiles already carry the
## category as a TAG, so this condition asks the tile what it IS rather than
## enumerating what it could be: one authored `tag = &"forest"` covers the whole
## biome forever.
##
## MULTI-CELL UNITS — ANY, not ALL.
## A unit with a footprint larger than 1x1 covers several cells, so "is it on a
## forest tile" needs a rule. This condition uses ANY: the tag holds if AT LEAST
## ONE covered cell carries it. Justified two ways:
##   - Fiction/feel: a 2x2 tree boss with one root in the grove is still rooted in
##     the grove. ALL would make a large unit strictly WORSE at exploiting terrain
##     than a small one — it could never satisfy a tag on a patchy map — which
##     inverts the intent of a terrain-keyed boss power.
##   - Stability: ALL makes the passive flicker on and off every time the unit
##     straddles a biome boundary, and the player cannot see which of four cells
##     broke it. ANY is legible: "am I touching forest?"
## A future condition wanting the strict reading should be its own class rather
## than a flag here, so authored content can never silently change meaning.
##
## Terrain tags are read duck-typed, most precise source first, so this works
## against the live [BoardAdapter], a [CombatServices]-backed board, and a
## lightweight test mock alike. A board that can report no terrain at all fails
## closed (false) rather than erroring.

## Tile tag the unit must be standing on, e.g. [code]&"forest"[/code],
## [code]&"volcano"[/code], [code]&"hazard"[/code]. Matched against every entry of
## the tile's [member TileResource.special_properties] (and, as a last resort, the
## tile's canonical id, so a tag-less tile can still be named directly).
@export var tag: StringName = &""


func is_met(unit, board) -> bool:
	if unit == null or board == null or tag == &"":
		return false
	for cell in _cells_of(unit, board):
		var c: Vector2i = cell
		if _tag_at(board, c):
			return true  # ANY covered cell is enough — see the class docs.
	return false


func describe() -> String:
	return "on %s terrain" % tag


## Every cell [param unit] occupies. Prefers the board's footprint-aware accessor
## ([method BoardAdapter.cells_of]) so a 2x2 boss reports all four of its cells;
## falls back to the single anchor cell for boards (and mocks) that only know
## [code]cell_of[/code]. Empty when the board can report neither.
func _cells_of(unit, board) -> Array:
	if board.has_method("cells_of"):
		var cells = board.cells_of(unit)
		if cells is Array and not cells.is_empty():
			return cells
	if board.has_method("cell_of"):
		return [board.cell_of(unit)]
	return []


## True when the tile at [param cell] carries [member tag].
##
## Sources are tried most-precise first because the cheap accessors are LOSSY:
## [method BoardAdapter.tile_tag_at] returns only the tile's FIRST special
## property, so a volcano tile tagged ["volcano", "difficult"] would never match
## &"difficult" through it. The full-list accessors are therefore preferred, and
## the single-tag / id accessors remain as a floor so a minimal mock still works.
func _tag_at(board, cell: Vector2i) -> bool:
	# 1. Full tag list straight from the board.
	if board.has_method("tile_tags_at"):
		if _contains(board.tile_tags_at(cell)):
			return true
	# 2. The TileResource itself (board-provided, else the CombatServices registry).
	var res = null
	if board.has_method("tile_at"):
		res = board.tile_at(cell)
	elif CombatServices != null and CombatServices.has_method("tile_at"):
		res = CombatServices.tile_at(cell)
	if res != null and res is TileResource:
		if _contains(res.special_properties):
			return true
		if String(res.id) == String(tag):
			return true
	# 3. Lossy single-tag / id fallbacks for boards exposing nothing richer.
	if board.has_method("tile_tag_at") and String(board.tile_tag_at(cell)) == String(tag):
		return true
	if board.has_method("tile_id_at") and String(board.tile_id_at(cell)) == String(tag):
		return true
	return false


## True if [param values] (an Array of String/StringName tags) holds
## [member tag]. Compared as Strings so a String-typed
## [member TileResource.special_properties] entry matches a StringName tag.
func _contains(values) -> bool:
	if not (values is Array):
		return false
	var wanted := String(tag)
	for v in values:
		if String(v) == wanted:
			return true
	return false
