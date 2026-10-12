extends GutTest

# Units are shown at their TRUE design size (CONQUEST.md "Size"): one tile for
# everyone but the giants, overhang allowed, a tile plate to show which tile is theirs
# and a health bar that sits on the real head.

const ROSTER := "res://game/characters/roster/"

## Design heights in metres (the owner's size table), with the roster file that
## carries each. A drifted model_scale or a re-exported model shows up here.
const DESIGN_HEIGHTS := {
	"tree_grunt": 2.4384,   # Barkling, 8 ft 0 in -- wider than a tile, still one tile
	# magmoo: 8 ft (2.4384 m) since 6ba132b, ~8.4 m nose-to-tail, still ONE tile (overhangs).
	"petalfang": 1.2192,    # 4 ft 0 in
	"blightcap": 0.6096,    # 2 ft 0 in
	"firesprite": 1.3716,   # 4 ft 6 in
	"vineweave": 1.6764,    # 5 ft 6 in
	"lyra": 1.7272,         # 5 ft 8 in
	"wren": 1.795,
	"necromancer": 1.8796,  # Mortis, 6 ft 2 in
	"vampwarrior": 1.8796,
	"varden": 1.9304,       # 6 ft 4 in
	"eldroot": 4.552,       # 14 ft 11 in, the 2x2 giant
	# forge compendium placeholders (cc72d3f): ARTIST SIZES 2026-10-09.
	"bombee": 0.9144,  # about 3 ft, floats (body extent; the idle hover lifts it) (artist 2026-10-09)
	"aquaoct": 0.9144,  # around 3 ft (artist 2026-10-09)
	"canine_bat": 1.0414,  # 3 ft 5 in (artist 2026-10-09)
	"raven_rogue": 0.9144,  # 3 ft (artist 2026-10-09)
	"pangolin_knight": 0.9144,  # 3 ft (artist 2026-10-09)
	"shadow_mole": 0.762,  # sticks out of the ground ~2 ft 6 in (artist 2026-10-09)
	# forge compendium placeholders (586f2ce): ARTIST SIZES 2026-10-11 (floaters: body extent).
	"soot_puff": 0.6096,           # 2 ft, floats
	"winged_cat": 0.9144,          # 3 ft
	"phoenix_hatchling": 0.9144,   # 3 ft
	"chest_monster": 1.2192,       # 4 ft
	"petal_cobra": 1.803,          # lineup height (no artist size; kept by the artist's say-so)
	"crystal_canine": 1.524,       # 5 ft
	"leaf_bird": 0.1524,           # 6 in tall, ~1 ft long
	"eye_totem": 1.0668,           # 3 ft 6 in, floats
	"ember_eye": 1.3462,           # 4 ft 5 in, floats
	"ember_stump": 2.4384,         # 8 ft -- wider than a tile, still one tile
	"shield_rodent": 0.819,        # lineup height (no artist size; kept by the artist's say-so)
	"storm_vessel": 1.905,         # 6 ft 3 in, floats
	"volcano_turtle": 2.1336,      # 7 ft -- wider than a tile, still one tile
	"goo_shield": 1.651,           # 5 ft 5 in
	"fogeist": 1.4224,             # 4 ft 8 in (rest pose ~4% over the idle extent)
	"lava_komodo": 1.2954,         # 4 ft 3 in
	"spectormn": 1.809,            # lineup height (no artist size; kept by the artist's say-so), floats
	"halo_sentinel": 1.905,        # 6 ft 3 in, floats
	"eclipse_wolf": 1.2192,        # 4 ft
	"gemwing_dragon": 3.9624,      # 13 ft -- boss-tier mesh, still ONE tile (overhangs)
	"mystic_snow_spirit": 1.7272,  # 5 ft 8 in
	"holly_snowman": 1.524,        # 5 ft
	"vulture_creature": 1.524,     # 5 ft (artist 2026-10-12)
}

func _unit(id: String) -> Unit:
	var u := Unit.new()
	u.character_resource = load(ROSTER + id + ".tres")
	add_child_autofree(u)
	return u


func test_every_unit_stands_at_its_design_height() -> void:
	for id in DESIGN_HEIGHTS:
		var want: float = DESIGN_HEIGHTS[id]
		# The measurement is the rest-pose mesh; the size table measured an idle frame,
		# so allow a few percent for the pose difference (Petalfang rears ~12% taller
		# in its idle than in its rest pose).
		var tol: float = 0.13 if id == "petalfang" else 0.04
		assert_almost_eq(_unit(id).get_visual_height(), want, want * tol,
			"%s is %.2f m tall in game" % [id, want])


func test_only_giants_take_more_than_one_tile() -> void:
	for id in DESIGN_HEIGHTS:
		var fp: Vector2i = (load(ROSTER + id + ".tres") as CharacterResource).get_footprint()
		if id == "eldroot":
			assert_eq(fp, Vector2i(2, 2), "Eldroot is the multi-tile giant")
		else:
			assert_eq(fp, Vector2i.ONE, "%s owns ONE tile, even when it overhangs it" % id)


func test_a_model_less_unit_reads_as_human_height() -> void:
	var u := Unit.new()
	u.stats_resource = UnitStatsResource.new()
	add_child_autofree(u)
	assert_eq(u.get_visual_height(), Unit.DEFAULT_VISUAL_HEIGHT)


func _manager() -> UnitVisualManager:
	var m := UnitVisualManager.new()
	add_child_autofree(m)
	return m


func test_health_bar_sits_on_the_real_head() -> void:
	var m := _manager()
	for id in ["tree_grunt", "eldroot", "wren"]:
		var u := _unit(id)
		m.setup_unit_visuals(u, PlayerMaterials.PlayerTeam.PLAYER_1)
		var bar: Node3D = m._unit_health_bars[u]
		assert_almost_eq(bar.position.y, u.get_visual_height(), 0.001, "%s bar at its head" % id)
	# A knee-high creature's bar is held clear of the ground.
	var tiny := _unit("blightcap")
	m.setup_unit_visuals(tiny, PlayerMaterials.PlayerTeam.PLAYER_1)
	assert_almost_eq(m._unit_health_bars[tiny].position.y, m.health_bar_min_height, 0.001)


func test_tile_plate_covers_exactly_the_owned_tiles() -> void:
	var m := _manager()
	var one := _unit("tree_grunt")
	m.setup_unit_visuals(one, PlayerMaterials.PlayerTeam.PLAYER_1)
	var plate := one.get_node(UnitVisualManager.TILE_PLATE_NAME) as MeshInstance3D
	var size: Vector2 = (plate.mesh as PlaneMesh).size
	assert_lt(size.x, Unit.CELL_SIZE, "a one-tile plate stays inside its tile")
	assert_gt(size.x, Unit.CELL_SIZE * 0.8)
	assert_eq(Vector2(plate.position.x, plate.position.z), Vector2.ZERO)

	var giant := _unit("eldroot")
	m.setup_unit_visuals(giant, PlayerMaterials.PlayerTeam.PLAYER_1)
	var gp := giant.get_node(UnitVisualManager.TILE_PLATE_NAME) as MeshInstance3D
	var gs: Vector2 = (gp.mesh as PlaneMesh).size
	assert_gt(gs.x, Unit.CELL_SIZE * 1.8, "a 2x2 plate spans both tiles")
	assert_lt(gs.x, Unit.CELL_SIZE * 2.0)
	assert_eq(gp.position.x, giant.get_footprint_offset().x, "centred on the 2x2 block")
	assert_eq(gp.position.z, giant.get_footprint_offset().z)

	# Re-running setup (an ownership change) reuses the one plate.
	m.setup_unit_visuals(one, PlayerMaterials.PlayerTeam.PLAYER_2)
	var plates := one.get_children().filter(func(c): return c.name == UnitVisualManager.TILE_PLATE_NAME)
	assert_eq(plates.size(), 1)


func test_tile_plates_can_be_switched_off() -> void:
	var m := _manager()
	var u := _unit("wren")
	m.setup_unit_visuals(u, PlayerMaterials.PlayerTeam.PLAYER_1)
	m.tile_plates_enabled = false
	m.refresh_tile_plate(u)
	await get_tree().process_frame
	assert_null(u.get_node_or_null(UnitVisualManager.TILE_PLATE_NAME))
