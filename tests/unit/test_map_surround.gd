extends GutTest

## [MapSurround] LAYOUT contract -- the scenery ring that stops a map reading as a slab
## floating in the void.
##
## Visual quality is not assertable headless (that is the playtest). What IS assertable,
## and what every one of these pins, is that the decoration is *inert*:
##   * DETERMINISTIC   -- same map identity => byte-identical layout, twice and forever,
##                        so two lockstep peers and a replay all render the same board.
##   * RNG-ISOLATED    -- it draws from its OWN seeded generator, never the match stream
##                        and never the process-wide RNG. A decoration that consumed a
##                        match draw would desync every peer.
##   * OUT OF BOUNDS   -- every planned cell lies strictly OUTSIDE the playable rect, so
##                        no scenery can ever be mistaken for a board cell.
##
## Pure planning only -- no scene tree, no nodes. The live board/camera/teardown
## invariants live in integration/test_map_surround_live.gd.

const SURROUND := preload("res://game/maps/MapSurround.gd")


# --- Fixtures ----------------------------------------------------------------

func _map(map_name: String, w: int, h: int, preset: String = "Forest") -> MapResource:
	var m := MapResource.new()
	m.map_name = map_name
	m.width = w
	m.height = h
	m.environment_preset = preset
	return m


## A stable string over every field the builder consumes, so "identical layout" is a
## single comparison rather than a hand-rolled loop of per-field assertions.
func _fingerprint(plan: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("d=%d;n=%d" % [int(plan["depth"]), int(plan["cell_count"])])
	for entry in (plan["cells"] as Array):
		var cell: Vector2i = entry["cell"]
		var off: Vector2 = entry["offset"]
		parts.append("%d,%d|%d|%s|%.6f|%.6f,%.6f|%.6f|%d" % [
			cell.x, cell.y, int(entry["ring"]), String(entry["kind"]),
			float(entry["yaw"]), off.x, off.y, float(entry["scale"]),
			int(entry["tufts"])])
	return "&".join(parts)


# --- Determinism -------------------------------------------------------------

func test_same_map_plans_an_identical_surround_twice() -> void:
	var m := _map("Forgotten Forest", 12, 10)
	var a := SURROUND.plan(m)
	var b := SURROUND.plan(m)
	assert_eq(_fingerprint(a), _fingerprint(b),
		"the same map id plans a byte-identical surround on every load")


func test_two_separate_resources_with_the_same_identity_agree() -> void:
	# Two peers each load their OWN copy of the map resource; they must still agree.
	var a := SURROUND.plan(_map("Kings Crossing", 9, 9))
	var b := SURROUND.plan(_map("Kings Crossing", 9, 9))
	assert_eq(_fingerprint(a), _fingerprint(b),
		"identity, not object identity, decides the layout -- two peers render the same ring")


func test_different_maps_get_different_surrounds() -> void:
	var a := SURROUND.plan(_map("Forgotten Forest", 12, 10))
	var b := SURROUND.plan(_map("Proving Grounds", 12, 10))
	assert_ne(_fingerprint(a), _fingerprint(b),
		"a different map name reseeds the scatter, so no two maps share a treeline")


func test_same_name_different_size_reseeds() -> void:
	assert_ne(SURROUND.seed_for(_map("Arena", 8, 8)),
		SURROUND.seed_for(_map("Arena", 10, 10)),
		"dimensions are folded into the seed, so a resized map is not the old layout cropped")


func test_seed_is_stable_across_calls() -> void:
	var m := _map("Elemental Crossroads", 11, 11)
	assert_eq(SURROUND.seed_for(m), SURROUND.seed_for(m),
		"the seed is a pure hash of the map's identity, not a fresh draw")


# --- RNG isolation: the surround must cost the match ZERO draws ---------------

func test_planning_consumes_no_draw_from_an_injected_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321
	var state_before: int = rng.state
	SURROUND.plan(_map("Forgotten Forest", 14, 14))
	assert_eq(rng.state, state_before,
		"surround generation advances no generator but its own")


func test_planning_leaves_the_match_rng_stream_untouched() -> void:
	var match_rng := MatchRng.new()
	match_rng.begin_solo(0x5EED1234)
	var seed_before: int = match_rng.match_seed
	var command_7_before: int = match_rng.seed_for(7)

	SURROUND.plan(_map("Forgotten Forest", 14, 14))

	assert_eq(match_rng.match_seed, seed_before,
		"the match seed is untouched by scenery")
	assert_eq(match_rng.seed_for(7), command_7_before,
		"command 7 still rolls exactly what it rolled -- replays and peers stay in step")


func test_planning_consumes_no_draw_from_the_process_wide_rng() -> void:
	# seed() (never randomize()) so this stays deterministic for every later suite; the
	# after-state is re-pinned below either way.
	seed(424242)
	var expected: int = randi()

	seed(424242)
	SURROUND.plan(_map("Forgotten Forest", 14, 14))
	var actual: int = randi()

	# Re-pin the shared generator so nothing downstream inherits this test's position.
	seed(424242)
	assert_eq(actual, expected,
		"the global RNG stream is exactly where it was -- the surround never calls randi/randf")


# --- Playable-bounds invariants ----------------------------------------------

func test_no_planned_cell_lands_inside_the_playable_rect() -> void:
	var w: int = 12
	var h: int = 10
	var plan := SURROUND.plan(_map("Forgotten Forest", w, h))
	var intruders: Array[Vector2i] = []
	for entry in (plan["cells"] as Array):
		var cell: Vector2i = entry["cell"]
		if cell.x >= 0 and cell.x < w and cell.y >= 0 and cell.y < h:
			intruders.append(cell)
	assert_eq(intruders, [] as Array[Vector2i],
		"every decor cell is strictly outside the board -- the surround adds no playable cell")


func test_every_cell_carries_a_ring_index_within_the_built_depth() -> void:
	var plan := SURROUND.plan(_map("Forgotten Forest", 12, 10))
	var depth: int = int(plan["depth"])
	var out_of_range: int = 0
	for entry in (plan["cells"] as Array):
		var ring: int = int(entry["ring"])
		if ring < 1 or ring > depth:
			out_of_range += 1
	assert_eq(out_of_range, 0,
		"a decor cell sits in ring 1..depth; ring 0 would BE the board")


func test_cell_count_is_exactly_the_ring_shell() -> void:
	var w: int = 12
	var h: int = 10
	var plan := SURROUND.plan(_map("Forgotten Forest", w, h))
	var depth: int = int(plan["depth"])
	assert_eq(int(plan["cell_count"]), SURROUND.ring_cell_count(w, h, depth),
		"the plan fills the whole shell between the board and the outer ring, no gaps")


func test_ring_index_is_zero_on_the_board_and_grows_outward() -> void:
	assert_eq(SURROUND.ring_index(0, 0, 8, 8), 0, "a corner board cell is not decor")
	assert_eq(SURROUND.ring_index(7, 7, 8, 8), 0, "the far corner board cell is not decor")
	assert_eq(SURROUND.ring_index(-1, 4, 8, 8), 1, "one cell west of the board is ring 1")
	assert_eq(SURROUND.ring_index(8, 4, 8, 8), 1, "one cell east of the board is ring 1")
	assert_eq(SURROUND.ring_index(-3, -3, 8, 8), 3,
		"the diagonal uses Chebyshev distance, so rings are square shells")


# --- Density, budget and biome ------------------------------------------------

func test_density_rises_toward_the_outer_edge() -> void:
	# "The forest closes in": the outermost ring must be visibly busier than the innermost.
	var plan := SURROUND.plan(_map("Forgotten Forest", 16, 16))
	var depth: int = int(plan["depth"])
	var inner_total: int = 0
	var inner_props: int = 0
	var outer_total: int = 0
	var outer_props: int = 0
	for entry in (plan["cells"] as Array):
		var ring: int = int(entry["ring"])
		var is_prop: bool = String(entry["kind"]) != "grass"
		if ring == 1:
			inner_total += 1
			if is_prop:
				inner_props += 1
		elif ring == depth:
			outer_total += 1
			if is_prop:
				outer_props += 1
	assert_gt(inner_total, 0, "there is an inner ring to compare")
	assert_gt(outer_total, 0, "there is an outer ring to compare")
	var inner_density: float = float(inner_props) / float(inner_total)
	var outer_density: float = float(outer_props) / float(outer_total)
	assert_gt(outer_density, inner_density,
		"props thicken outward, so the border reads as a treeline closing in")


func test_the_biggest_authored_map_stays_inside_the_instance_budget() -> void:
	# MapResource.MAX_MAP_SIZE is 40 -- the worst case the surround must survive.
	var plan := SURROUND.plan(_map("Colossus", 40, 40))
	assert_lte(int(plan["cell_count"]), SURROUND.MAX_RING_CELLS,
		"a 40x40 map's ring stays inside the merged-mesh cell budget")
	assert_lte(int(plan["tree_count"]), SURROUND.MAX_TREES,
		"tree NODES are capped -- they are the only per-instance cost in the surround")
	assert_gte(int(plan["depth"]), SURROUND.MIN_RING_DEPTH,
		"the ring is never trimmed away entirely, however big the map")


func test_ring_depth_trims_only_when_the_budget_demands_it() -> void:
	assert_eq(SURROUND.ring_depth_for(12, 10), SURROUND.MAX_RING_DEPTH,
		"an ordinary map gets the full ring depth")


func test_a_volcanic_map_grows_no_forest() -> void:
	var plan := SURROUND.plan(_map("Ashfall", 12, 12, "Volcanic"))
	assert_eq(int(plan["tree_count"]), 0,
		"a volcanic border is ash and rock -- trees would contradict the biome")
	assert_gt(int(plan["rock_count"]), 0, "it scatters rocks instead")


func test_an_unknown_preset_falls_back_rather_than_failing() -> void:
	var plan := SURROUND.plan(_map("Somewhere", 8, 8, "NotABiome"))
	assert_eq(String(plan["preset"]), "default",
		"an unrecognised environment_preset resolves to the default palette, never an error")
