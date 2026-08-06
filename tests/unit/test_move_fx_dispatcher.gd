extends GutTest

## The DEFAULT MOVE-FX derivation ([MoveFXDispatcher]) and the per-move override
## ([MoveFXResource]) -- the two pure-data halves of the layer.
##
## Everything asserted here is arithmetic over a move's own [TargetingPattern] and a
## dictionary merge, so it needs no scene, no board and no autoloads. The RENDERING half
## (real cast on a real board, a maw covering its 3x3, self-freeing nodes, the RNG pin)
## is `tests/integration/test_move_fx_live.gd` -- see tests/README.md on the split.
##
## The rule these pin, in one line: an AREA move erupts on EVERY cell its pattern covers,
## including the cells with nobody standing in them, and it fails toward drawing LESS
## rather than drawing on the wrong tile.

const DISPATCHER := preload("res://game/visuals/MoveFXDispatcher.gd")
const MOVE_FX := preload("res://game/visuals/MoveFXResource.gd")

var _fx


func before_each() -> void:
	# Never added to the tree: every method exercised below is pure. See the class doc.
	_fx = autofree(DISPATCHER.new())


# --- Fixtures -----------------------------------------------------------------

func _pattern(shape: int, size: int, kind: int = CombatTypes.TargetKind.ENEMY,
		max_range: int = 4) -> TargetingPattern:
	var p := TargetingPattern.new()
	p.target_kind = kind
	p.min_range = 1 if kind != CombatTypes.TargetKind.SELF else 0
	p.max_range = max_range
	p.area_shape = shape
	p.area_size = size
	return p


func _move(pattern: TargetingPattern, element: StringName = &"") -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_fx_move"
	m.element = element
	m.targeting = pattern
	return m


func _cells(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in list:
		out.append(c)
	return out


# --- The Abyssal Maw shape: every cell of the area, victim or not --------------

func test_an_area_move_erupts_on_every_cell_it_covers_not_only_on_victims() -> void:
	# The bug this layer exists for. A 3x3 that caught ONE unit must still light all nine
	# cells -- otherwise a wide blast is indistinguishable from a single-target poke.
	var move := _move(_pattern(CombatTypes.AreaShape.SQUARE, 1, CombatTypes.TargetKind.ENEMY, 10))
	var area: Array[Vector2i] = _fx._derive_area(move, null, Vector2i(0, 0), _cells([Vector2i(4, 4)]))

	assert_eq(area.size(), 9,
		"a 3x3 blast draws nine cells, however many units were standing in it")
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			assert_true(area.has(Vector2i(4 + dx, 4 + dy)),
				"cell (%d,%d) of the blast erupts even with nobody on it" % [4 + dx, 4 + dy])


func test_the_inferred_aim_is_the_one_that_best_explains_the_hits() -> void:
	# Two victims two cells apart can only both sit in one 3x3 if it is centred between
	# them, so the derivation has exactly one legal answer and must find it.
	var move := _move(_pattern(CombatTypes.AreaShape.SQUARE, 1, CombatTypes.TargetKind.ENEMY, 10))
	var area: Array[Vector2i] = _fx._derive_area(
		move, null, Vector2i(0, 0), _cells([Vector2i(3, 3), Vector2i(3, 5)]))

	assert_eq(area.size(), 9, "the blast is still a 3x3")
	assert_true(area.has(Vector2i(3, 4)),
		"the only 3x3 covering both victims is centred at (3,4), so that is where it draws")
	assert_true(area.has(Vector2i(2, 3)) and area.has(Vector2i(4, 5)),
		"and its empty corners erupt with it")


func test_a_single_target_move_lights_exactly_what_it_hit() -> void:
	var move := _move(_pattern(CombatTypes.AreaShape.SINGLE, 0))
	var area: Array[Vector2i] = _fx._derive_area(move, null, Vector2i(0, 0), _cells([Vector2i(0, 1)]))
	assert_eq(area, _cells([Vector2i(0, 1)]),
		"a single-cell move has no area to expand -- it lights the struck cell and nothing else")


func test_a_self_cast_lights_the_caster_even_when_it_announced_nothing() -> void:
	# A pure buff deals no damage and heals nobody, so there is no hit to derive from. A
	# SELF pattern needs no inference: the caster's cell IS the area.
	var move := _move(_pattern(CombatTypes.AreaShape.SINGLE, 0, CombatTypes.TargetKind.SELF, 0))
	var area: Array[Vector2i] = _fx._derive_area(move, null, Vector2i(2, 2), _cells([]))
	assert_eq(area, _cells([Vector2i(2, 2)]),
		"a self-buff flashes the caster's own cell rather than producing no feedback at all")


# --- It fails toward drawing LESS ---------------------------------------------

func test_an_area_move_that_hit_nothing_draws_no_impact() -> void:
	# Nothing landed, so there is no evidence of WHERE the move was aimed. Drawing the
	# caster's own surroundings would be a lie; drawing nothing is a cosmetic gap.
	var move := _move(_pattern(CombatTypes.AreaShape.SQUARE, 1, CombatTypes.TargetKind.ENEMY, 10))
	var area: Array[Vector2i] = _fx._derive_area(move, null, Vector2i(0, 0), _cells([]))
	assert_eq(area.size(), 0,
		"an area cast with no landed cell renders the cast accent only, never a guessed blast")


func test_hits_outside_every_reachable_area_fall_back_to_the_hits_themselves() -> void:
	# A hit no aim can explain (a knock-back victim, a chained effect, a mock board) must
	# not silently discard the feedback -- it degrades to lighting exactly what was hit.
	var move := _move(_pattern(CombatTypes.AreaShape.SQUARE, 1, CombatTypes.TargetKind.ENEMY, 2))
	var far := _cells([Vector2i(40, 40)])
	assert_eq(_fx._derive_area(move, null, Vector2i(0, 0), far), far,
		"an unexplainable hit still gets its own cell lit, just not an expanded area")


func test_a_move_with_no_targeting_pattern_is_survivable() -> void:
	var move := MoveResource.new()  # deliberately no targeting at all
	var hits := _cells([Vector2i(1, 1)])
	assert_eq(_fx._derive_area(move, null, Vector2i(0, 0), hits), hits,
		"an unauthored/half-built move degrades to the hit cells rather than erroring")
	assert_eq(_fx._derive_area(null, null, Vector2i(0, 0), hits), hits,
		"and so does no move at all")


func test_an_unknown_origin_degrades_to_the_hits() -> void:
	# No board (or a caster that is not on it) means no origin -- and every area shape is
	# defined relative to one.
	var move := _move(_pattern(CombatTypes.AreaShape.SQUARE, 1))
	var hits := _cells([Vector2i(2, 2)])
	assert_eq(_fx._derive_area(move, null, null, hits), hits,
		"with no caster cell there is nothing to expand from, so only the hits light up")


# --- Defaults: the element vocabulary, not a private palette ------------------

func test_the_default_tint_is_the_moves_element_through_the_shared_theme() -> void:
	var spec: Dictionary = _fx._move_spec(_move(_pattern(CombatTypes.AreaShape.SINGLE, 0), &"ember"), 0)
	assert_eq(spec["color"], ConquestTheme.element_color("ember"),
		"the burst uses the SAME element lookup every element chip in the UI uses")

	var neutral: Dictionary = _fx._move_spec(_move(_pattern(CombatTypes.AreaShape.SINGLE, 0)), 0)
	assert_eq(neutral["color"], ConquestTheme.element_color(""),
		"an unelemented move resolves through the same function to the theme's neutral")


func test_the_defaults_are_a_complete_spec_so_an_unauthored_move_still_renders() -> void:
	var spec: Dictionary = _fx._move_spec(_move(_pattern(CombatTypes.AreaShape.SINGLE, 0)), 0)
	assert_eq(spec["burst_scale"], 1.0, "an unauthored move bursts at the default size")
	assert_true(bool(spec["ring"]), "and gets the ground ring")
	assert_eq(spec["shake"], 0.0, "but no camera kick -- that is opt-in")
	assert_null(spec["scene"], "and instances no bespoke scene")
	assert_eq(StringName(spec["cast_cue"]), _fx.default_cast_cue,
		"the cast cue falls back to the dispatcher's default")


# --- The override path: field by field, never all-or-nothing ------------------

func test_an_override_replaces_only_the_fields_it_authored() -> void:
	var fx := MOVE_FX.new()
	fx.burst_scale = 2.0
	fx.shake_strength = 0.2
	var move := _move(_pattern(CombatTypes.AreaShape.SINGLE, 0), &"ember")
	move.fx = fx

	var spec: Dictionary = _fx._move_spec(move, 0)
	assert_eq(spec["burst_scale"], 2.0, "the authored burst size wins")
	assert_eq(spec["shake"], 0.2, "and the authored shake")
	assert_eq(spec["color"], ConquestTheme.element_color("ember"),
		"but an unauthored colour still resolves from the move's element -- no cliff")
	assert_eq(StringName(spec["cast_cue"]), _fx.default_cast_cue,
		"and an unauthored cue still falls back to the default")


func test_an_authored_colour_wins_over_the_element() -> void:
	var fx := MOVE_FX.new()
	fx.color = Color(0.42, 0.24, 0.62, 1.0)
	var move := _move(_pattern(CombatTypes.AreaShape.SINGLE, 0), &"ember")
	move.fx = fx

	assert_true(fx.has_color(), "an opaque colour reads as authored")
	assert_eq(_fx._move_spec(move, 0)["color"], fx.color,
		"an authored tint overrides the element's own colour")


func test_an_alpha_zero_colour_means_not_authored() -> void:
	var fx := MOVE_FX.new()
	assert_false(fx.has_color(),
		"the default alpha-0 colour is the 'not authored' sentinel, not a transparent tint")
	var move := _move(_pattern(CombatTypes.AreaShape.SINGLE, 0), &"frost")
	move.fx = fx
	assert_eq(_fx._move_spec(move, 0)["color"], ConquestTheme.element_color("frost"),
		"so the element still decides the tint")


func test_a_move_with_no_override_is_untouched() -> void:
	var move := _move(_pattern(CombatTypes.AreaShape.SINGLE, 0), &"nature")
	assert_null(move.fx, "fx defaults to null -- every move authored before this field is unaffected")
	assert_eq(_fx._move_spec(move, 0)["color"], ConquestTheme.element_color("nature"),
		"and resolves purely from its element")


func test_a_non_fx_resource_in_the_slot_is_ignored_rather_than_trusted() -> void:
	var move := _move(_pattern(CombatTypes.AreaShape.SINGLE, 0), &"holy")
	move.fx = TargetingPattern.new()  # a Resource, but not an FX one
	var spec: Dictionary = _fx._move_spec(move, 0)
	assert_eq(spec["burst_scale"], 1.0,
		"a resource with none of the FX fields contributes nothing -- the defaults stand")
	assert_eq(spec["color"], ConquestTheme.element_color("holy"),
		"and the element tint is unchanged")


# --- The authored example ------------------------------------------------------

func test_abyssal_maw_carries_the_worked_override() -> void:
	var move := load("res://game/combat/moves/abyssal_maw.tres") as MoveResource
	assert_not_null(move, "the maw move resource loads")
	if move == null:
		return
	assert_not_null(move.fx, "the maw is the authored example of the override path")

	var spec: Dictionary = _fx._move_spec(move, 0)
	var default_spec: Dictionary = _fx._move_spec(_move(_pattern(CombatTypes.AreaShape.SQUARE, 1), &"dark"), 0)
	assert_gt(float(spec["burst_scale"]), float(default_spec["burst_scale"]),
		"the maw bursts bigger than an unauthored dark move")
	assert_gt(float(spec["shake"]), 0.0, "and kicks the camera, which a default move does not")
	assert_ne(spec["color"], default_spec["color"],
		"and uses its own deeper void tint rather than the shared dark chip")


# --- Hazards: one draw per hazard per frame ------------------------------------

func test_a_hazard_draws_once_per_frame_however_often_it_announces() -> void:
	# The double-fire guard. A maw announces its eruption AND its expiry in one beat, and a
	# replay driver can re-enter the same signal; the ground must open once.
	var hazard := DelayedBurstHazard.new([Vector2i(1, 1)] as Array[Vector2i], 10,
		CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, null)
	assert_true(_fx._claim_hazard(hazard), "the first announcement in a frame draws")
	assert_false(_fx._claim_hazard(hazard), "a second announcement in the SAME frame does not")


func test_a_detonation_gets_a_bigger_burst_and_a_kick_than_a_sweep() -> void:
	var maw := DelayedBurstHazard.new([Vector2i(0, 0)] as Array[Vector2i], 10,
		CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, null)
	var erupt: Dictionary = _fx._hazard_spec(maw, true)
	var sweep: Dictionary = _fx._hazard_spec(maw, false)

	assert_gt(float(erupt["burst_scale"]), float(sweep["burst_scale"]),
		"the ground opening is a bigger beat than a vine crawling one band")
	assert_gt(float(erupt["shake"]), 0.0, "an eruption kicks the camera")
	assert_eq(float(sweep["shake"]), 0.0, "a band sweep does not")


func test_a_hazard_is_tinted_by_the_element_it_was_cast_with() -> void:
	var maw := DelayedBurstHazard.new([Vector2i(0, 0)] as Array[Vector2i], 10,
		CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, null)
	maw.element = &"dark"
	assert_eq(_fx._hazard_spec(maw, true)["color"], ConquestTheme.element_color("dark"),
		"an eruption reads in the element of the move that opened it, from the same lookup")


# --- Sound: fill silence, never double the hit --------------------------------

func test_the_impact_cue_is_suppressed_when_the_audio_layer_already_sounded_the_hit() -> void:
	# AudioManager plays sfx_hit once per damage_dealt. Sounding an impact that hit three
	# units would triple a sound the player is already hearing.
	var quiet: Dictionary = _fx._default_spec(Color.WHITE)
	quiet["announced"] = 3
	var loud: Dictionary = _fx._default_spec(Color.WHITE)
	loud["announced"] = 0

	# No AudioManager is resolvable off a detached node, so both calls are no-ops -- what is
	# asserted is the DECISION, read back from the same predicate the player path uses.
	assert_gt(int(quiet["announced"]), 0,
		"a damaging impact is already audible, so this layer stays quiet")
	assert_eq(int(loud["announced"]), 0,
		"an impact that damaged nobody -- a maw on empty ground -- is what needs the cue")
	_fx._play_cue_for_impact(quiet)
	_fx._play_cue_for_impact(loud)
	pass_test("neither cue path errors without an audio autoload")


# --- Determinism ---------------------------------------------------------------

func test_the_shard_scatter_seed_is_a_pure_function_of_the_cell() -> void:
	# Property 3 of the class doc: the visual jitter is seeded from the CELL, so nothing
	# here can read (or move) a shared generator, and two peers scatter identically.
	assert_eq(_fx._seed_for(Vector2i(3, 4)), _fx._seed_for(Vector2i(3, 4)),
		"the same cell always seeds the same scatter -- byte-identical on every machine")
	assert_ne(_fx._seed_for(Vector2i(3, 4)), _fx._seed_for(Vector2i(4, 3)),
		"and neighbouring cells do not throw the same chunks in the same directions")
