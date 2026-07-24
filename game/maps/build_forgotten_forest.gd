extends SceneTree

## Populates the player-authored "Forgotten Forest" draft (T62) with the Eldroot
## boss encounter, IN PLACE -- it enriches the existing map rather than creating a
## duplicate.
##
## Run with:
##   godot --headless --path . -s res://game/maps/build_forgotten_forest.gd
##
## The draft (game/maps/resources/forgotten_forest.tres, 20x20, author "Kenneth")
## was painted with the OLD type-only tiles: every cell carries a tile_type but an
## empty tile_id, so it renders as generic terrain instead of the real forest tiles
## we built (which heal / give evasion / wall). This script:
##   1. UPGRADES each tile to its real forest id by type, preserving the author's
##      exact spatial layout: NORMAL -> grass_plains, SACRED_GROUND -> sacred_meadow
##      (heals each turn), DIFFICULT_TERRAIN -> tall_grass (evasion). Trees (walls)
##      are NOT auto-placed -- the old data can't tell a wall from cover, so the
##      author paints those in with the new tile picker where they want them.
##   2. Anchors Eldroot (2x2) on the heart of the author's sacred grove.
##   3. Screens it with grunts, seeds Mycothrall (Hard+ only, via min_difficulty),
##      and drops a placeholder hero squad on the far edge so the map is testable.
## Identity (name / author / description / Inactive draft status / size) is preserved.

const MAP_PATH := "res://game/maps/resources/forgotten_forest.tres"

# type name -> real forest tile id. The author's layout is kept cell-for-cell; only
# the tile IDENTITY is upgraded so the terrain gains its authored mechanics.
#
# DIFFICULT_TERRAIN -> tree: the old tile system had NO separate tree type -- trees
# and cover both lived under DIFFICULT_TERRAIN -- so the author's forest was painted
# as difficult terrain. Restoring it as TREE (an impassable wall) brings the forest
# back. Any cell that should be tall-grass cover instead can be repainted in the
# Map Creator now that it loads again.
const TYPE_TO_FOREST_ID := {
	"NORMAL": "grass_plains",
	"SACRED_GROUND": "sacred_meadow",
	"DIFFICULT_TERRAIN": "tree",
}
const DEFAULT_FOREST_ID := "grass_plains"
# Impassable tile ids a unit must never be spawned on.
const BLOCKING_TILE_IDS := ["tree"]


func _initialize() -> void:
	var res := load(MAP_PATH) as MapResource
	if res == null:
		push_error("[build_forbidden_forest] Could not load %s -- expected the author's draft to exist" % MAP_PATH)
		quit(1)
		return

	# Name correction: the draft was authored "Forbidden Forest" by mistake.
	res.map_name = "Forgotten Forest"
	# This is a boss encounter: you win by defeating Eldroot, not by clearing every
	# spawn (the Hard+ parasites would otherwise make elimination the wrong goal).
	res.victory_conditions = ["Defeat Boss"]

	var sacred_cells: Array[Vector2i] = _upgrade_tiles(res)
	if sacred_cells.is_empty():
		push_error("[build_forbidden_forest] No SACRED_GROUND cells found -- cannot place the boss grove")
		quit(1)
		return

	var anchor := _boss_anchor(res, sacred_cells)
	_place_encounter(res, anchor)

	res.last_modified = Time.get_datetime_string_from_system()
	if ResourceSaver.save(res, MAP_PATH) != OK:
		push_error("[build_forbidden_forest] Failed to save %s" % MAP_PATH)
		quit(1)
		return
	print("[build_forbidden_forest] Enriched and saved %s" % MAP_PATH)

	quit(0 if _validate(anchor) else 1)


## Rewrites every tile's id from its type, in place, and returns the sacred cells.
func _upgrade_tiles(res: MapResource) -> Array[Vector2i]:
	var sacred: Array[Vector2i] = []
	for tile in res.tile_layout:
		var type_name: String = str(tile.get("tile_type", "NORMAL"))
		var forest_id: String = str(TYPE_TO_FOREST_ID.get(type_name, DEFAULT_FOREST_ID))
		tile["tile_id"] = forest_id
		tile["tile_resource_path"] = ""
		if type_name == "SACRED_GROUND":
			sacred.append(tile.get("position", Vector2i(-1, -1)))
	return sacred


## The 2x2 boss anchor: the sacred region's centroid, clamped so the footprint fits.
## The four anchor cells are forced to sacred_meadow so the boss always stands on
## healing forest ground even if the centroid grazed the grove's edge.
func _boss_anchor(res: MapResource, sacred_cells: Array[Vector2i]) -> Vector2i:
	var sum := Vector2i.ZERO
	for c in sacred_cells:
		sum += c
	var count: int = sacred_cells.size()
	var centre := Vector2i(int(round(float(sum.x) / count)), int(round(float(sum.y) / count)))
	var ax: int = clampi(centre.x, 0, res.width - 2)
	var ay: int = clampi(centre.y, 0, res.height - 2)
	var anchor := Vector2i(ax, ay)
	for d in _footprint_cells(anchor):
		res.set_tile_at_position(d, "SACRED_GROUND", "", "sacred_meadow")
	return anchor


func _footprint_cells(anchor: Vector2i) -> Array[Vector2i]:
	return [anchor, anchor + Vector2i(1, 0), anchor + Vector2i(0, 1), anchor + Vector2i(1, 1)]


## Places the boss, its grunt screen, the Hard+ parasites, and the placeholder
## player squad, using free-cell search so nothing overlaps.
func _place_encounter(res: MapResource, anchor: Vector2i) -> void:
	res.unit_spawns.clear()
	var occupied := {}
	for d in _footprint_cells(anchor):
		occupied[d] = true

	# Boss (player 1) on the sacred heart.
	res.set_character_spawn_at_position(anchor, 1, "eldroot", "BOSS")

	# Grunt screen ringing the grove.
	var grunts := [
		{"id": "tree_grunt", "pref": anchor + Vector2i(-3, -1)},
		{"id": "tree_grunt", "pref": anchor + Vector2i(4, -1)},
		{"id": "petalfang", "pref": anchor + Vector2i(-3, 3)},
		{"id": "blightcap", "pref": anchor + Vector2i(4, 3)},
	]
	for g in grunts:
		_add_spawn(res, 1, String(g["id"]), g["pref"], occupied)

	# Mycothrall: Hard+ only (min_difficulty gate). Seeded just outside the grove
	# on the approach, so on Hard the player wades through infestation to reach the boss.
	_add_spawn(res, 1, "mycothrall", anchor + Vector2i(-1, 5), occupied)
	_add_spawn(res, 1, "mycothrall", anchor + Vector2i(2, 5), occupied)

	# Player placeholder squad on the edge FARTHEST from the grove, spread across it.
	var far_y: int = res.height - 1 if anchor.y <= res.height / 2 else 0
	var squad := ["vineweave", "tree_grunt", "petalfang", "blightcap"]
	var xs := [int(res.width * 0.2), int(res.width * 0.4), int(res.width * 0.6), int(res.width * 0.8)]
	for i in range(squad.size()):
		_add_spawn(res, 0, squad[i], Vector2i(xs[i], far_y), occupied)


## Places one character spawn at the first free cell at/near [param pref].
func _add_spawn(res: MapResource, player_id: int, character_id: String, pref: Vector2i, occupied: Dictionary) -> void:
	var cell := _free_cell_near(res, pref, occupied)
	occupied[cell] = true
	res.set_character_spawn_at_position(cell, player_id, character_id, "")


## First in-bounds, unoccupied, PASSABLE cell spiralling out from [param pref].
## Skips trees so a unit is never stranded on an impassable tile.
func _free_cell_near(res: MapResource, pref: Vector2i, occupied: Dictionary) -> Vector2i:
	for radius in range(0, maxi(res.width, res.height)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cell := pref + Vector2i(dx, dy)
				if cell.x < 0 or cell.x >= res.width or cell.y < 0 or cell.y >= res.height:
					continue
				if occupied.has(cell):
					continue
				if _tile_id_at(res, cell) in BLOCKING_TILE_IDS:
					continue
				return cell
	return pref  # fallback: map is full (won't happen at these sizes)


func _tile_id_at(res: MapResource, cell: Vector2i) -> String:
	for tile in res.tile_layout:
		if tile.get("position", Vector2i(-1, -1)) == cell:
			return str(tile.get("tile_id", ""))
	return ""


func _validate(anchor: Vector2i) -> bool:
	print("\n==== VALIDATION ====")
	var ok := true
	var res := load(MAP_PATH) as MapResource
	if res == null:
		push_error("[validate] reload failed")
		return false

	print("Name: %s | status=%s | %dx%d | boss_anchor=%s" % [res.map_name, res.status, res.width, res.height, str(anchor)])

	# Every tile id resolves (no typo / stale id).
	var ids := {}
	for tile in res.tile_layout:
		var tid: String = str(tile.get("tile_id", ""))
		ids[tid] = int(ids.get(tid, 0)) + 1
		if not tid.is_empty() and TileCatalog.find_by_id(StringName(tid)) == null:
			push_error("[validate] tile_id '%s' does not resolve" % tid)
			ok = false
	print("Tile ids: %s" % str(ids))

	# Boss present + on the sacred anchor.
	var boss_ok := false
	for s in res.unit_spawns:
		if str(s.get("character_id", "")) == "eldroot" and s.get("position", Vector2i(-1, -1)) == anchor:
			boss_ok = true
	if not boss_ok:
		push_error("[validate] Eldroot not found at the sacred anchor %s" % str(anchor))
		ok = false

	var report: Dictionary = res.validate_map()
	print("validate_map(): valid=%s issues=%s" % [str(report.get("valid", false)), str(report.get("issues", []))])
	if not report.get("valid", false):
		ok = false

	# Spawn character ids all resolve, and the two sides are populated.
	var p0 := 0
	var p1 := 0
	for s in res.unit_spawns:
		var cid: String = str(s.get("character_id", ""))
		if cid.is_empty():
			continue
		if CharacterLibrary.get_character(cid) == null:
			push_error("[validate] character_id '%s' does not resolve" % cid)
			ok = false
		if int(s.get("player_id", -1)) == 0:
			p0 += 1
		else:
			p1 += 1
	print("Spawns: player0=%d player1=%d (Mycothrall gated by min_difficulty at play time)" % [p0, p1])
	if p0 < 1 or p1 < 1:
		push_error("[validate] both sides must have spawns")
		ok = false

	# NOTE: the live MapLoader build is verified separately (tests/unit/test_forgotten_forest.gd
	# + the game boot), not here -- MapLoader depends on the GameEvents / CombatServices
	# autoloads, which are not registered when this runs as a bare `-s` script.

	print("==== RESULT: %s ====" % ("PASS" if ok else "FAIL"))
	return ok
