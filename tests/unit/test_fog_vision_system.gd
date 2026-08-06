extends GutTest

## FOG OF WAR, the vision core: sight radius, team union, concealing ground, reveal-on-attack,
## the recompute wiring and determinism.
##
## THE LOAD-BEARING PROPERTY IS THE OFF SWITCH. Every map that shipped before fog existed
## reports [member MapResource.fog_of_war] false, and with it off every query in this file has
## to answer "visible" -- not "visible because the radius is large", but through a
## short-circuit, so the rest of the game runs the code it always ran. That is what the first
## block pins; everything after it is what the mechanic does once a map turns it on.
##
## Driven entirely off an INJECTED board ([method VisionSystem.set_board]) and a hand-built
## [MapResource], so there is no autoload state, no map load and no turn system anywhere in
## here -- the reveal clock is turned by hand through [method VisionSystem.note_turn_started],
## which is the same handle the live turn system pulls.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

const VEIL_PATH := "res://game/tiles/effects/resources/smoke_veil.tres"
const GRASS_PATH := "res://game/tiles/effects/resources/tall_grass.tres"

const MAP_W := 16
const MAP_H := 16


# --- Local doubles -----------------------------------------------------------
#
# The shipped doubles key allegiance on a plain `team` int and expose no owner, but vision is
# resolved per PLAYER SLOT through `get_owner_player().player_id` -- the same duck-typed hook
# BoardAdapter uses. So these two carry both: `team` keeps MinimalBoard's are_enemies/are_allies
# working unchanged, and `owner_player` is what VisionSystem reads. One-off on purpose (see
# tests/README rule 5): nothing else in the suite needs an owning side on a mock.

## A player slot, minimal enough to be the thing `get_owner_player()` returns.
class Side:
	var player_id: int

	func _init(p_player_id: int) -> void:
		player_id = p_player_id


## A unit that belongs to a SIDE and may declare its own sight radius.
class Scout:
	var team: int
	var owner_player
	var sight_range: int = 0
	var hp: int = 100
	var stats: Dictionary = { "health": 100, "attack": 20, "defense": 0 }

	func _init(p_side, p_sight: int = 0) -> void:
		owner_player = p_side
		team = p_side.player_id
		sight_range = p_sight

	func get_owner_player():
		return owner_player

	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name.to_lower(), 0))

	func take_damage(n: int) -> void:
		hp = maxi(0, hp - n)

	func get_hp() -> int:
		return hp


## A board that answers BOTH the roster query vision walks (`all_units`) and the per-cell tile
## effect lookup concealment reads (`tile_effects_at`). No shipped double combines the two.
class FogBoard extends Doubles.CombatBoard:
	var effects: Dictionary = {}

	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out

	func tile_effects_at(cell: Vector2i) -> Array:
		var arr = effects.get(cell, null)
		return arr if arr is Array else []

	func put_effect(cell: Vector2i, effect) -> void:
		effects[cell] = [effect]


## The board and the two sides are UNTYPED on purpose. GUT re-loads a suite script while
## collecting it, which mints a SECOND copy of every inner class -- so a member statically
## typed as an inner class is rejected at parse time with the famously unhelpful "value of type
## X cannot be assigned to a variable of type X". Everything that consumes them is duck-typed
## anyway, so nothing is lost by leaving the declarations open (the same yield to the analyser
## tests/README rule 3 documents for `_guard`).
var _vs: VisionSystem
var _board
var _p0
var _p1


func before_each() -> void:
	_p0 = Side.new(0)
	_p1 = Side.new(1)
	_board = FogBoard.new()
	# add_child_autofree so _ready() runs (that is what registers the live instance the static
	# seams resolve through) and so the node is freed -- and therefore DE-registered -- when the
	# test ends, whether it passed or failed.
	_vs = add_child_autofree(VisionSystem.new())
	_vs.set_board(_board)
	_vs.set_map(_map(true))


## A minimal map that does or does not ask for fog. Nothing else about it matters here except
## its dimensions, which is what bounds the lit set.
func _map(fog: bool) -> MapResource:
	var m := MapResource.new()
	m.map_name = "Fog Fixture"
	m.width = MAP_W
	m.height = MAP_H
	m.fog_of_war = fog
	return m


func _veil() -> TileEffectResource:
	return load(VEIL_PATH) as TileEffectResource


# --- The off switch -----------------------------------------------------------

func test_a_map_declares_no_fog_by_default() -> void:
	assert_false(MapResource.new().fog_of_war, "a fresh map is fought in the open")


func test_with_fog_off_every_query_answers_visible() -> void:
	_vs.set_map(_map(false))
	var hero := Scout.new(_p0)
	var enemy := Scout.new(_p1)
	_board.place(hero, Vector2i(0, 0))
	_board.place(enemy, Vector2i(15, 15))  # as far away as this map goes

	assert_false(_vs.fog_enabled(), "the map did not ask for fog")
	assert_true(_vs.is_unit_visible(0, enemy), "an enemy across the board is visible without fog")
	assert_true(_vs.is_cell_visible(0, Vector2i(15, 15)), "and so is the ground under it")
	assert_eq(_vs.visible_cells(0).size(), MAP_W * MAP_H,
		"visible_cells is the WHOLE board when there is no fog")


func test_with_fog_off_even_concealing_ground_hides_nobody() -> void:
	_vs.set_map(_map(false))
	var hero := Scout.new(_p0)
	var enemy := Scout.new(_p1)
	_board.place(hero, Vector2i(5, 5))
	_board.place(enemy, Vector2i(5, 6))
	_board.put_effect(Vector2i(5, 6), _veil())
	assert_true(_vs.is_unit_visible(0, enemy),
		"a veil is inert on a map with no fog -- there is nothing to hide behind")


# --- Sight ---------------------------------------------------------------------

func test_a_unit_lights_a_chebyshev_square_of_its_sight_radius() -> void:
	var hero := Scout.new(_p0)
	_board.place(hero, Vector2i(6, 6))
	var lit: Dictionary = _vs.visible_cells(0)

	assert_true(lit.has(Vector2i(10, 10)),
		"the far CORNER at Chebyshev 4 is lit -- sight is a square, not a diamond")
	assert_true(lit.has(Vector2i(10, 6)), "and so is the cardinal cell at 4")
	assert_false(lit.has(Vector2i(11, 6)), "one cell past the radius is dark")
	assert_false(lit.has(Vector2i(11, 11)), "and so is the corner past it")
	assert_eq(lit.size(), 81, "radius 4 lights the full 9x9 block around the unit")


func test_the_lit_set_is_clipped_to_the_board() -> void:
	var hero := Scout.new(_p0)
	_board.place(hero, Vector2i(0, 0))
	var lit: Dictionary = _vs.visible_cells(0)
	assert_false(lit.has(Vector2i(-1, 0)), "sight does not run off the edge of the map")
	assert_eq(lit.size(), 25, "a corner unit lights only the quarter of its square that exists")


func test_a_team_sees_the_union_of_its_units_sight() -> void:
	var west := Scout.new(_p0)
	var east := Scout.new(_p0)
	_board.place(west, Vector2i(2, 2))
	_board.place(east, Vector2i(13, 13))
	var lit: Dictionary = _vs.visible_cells(0)
	assert_true(lit.has(Vector2i(2, 2)), "the west scout's own cell is lit")
	assert_true(lit.has(Vector2i(13, 13)), "so is the east scout's")
	assert_false(lit.has(Vector2i(8, 8)), "the gap between them is not")


func test_a_character_sight_range_overrides_the_default() -> void:
	var myope := Scout.new(_p0, 1)
	_board.place(myope, Vector2i(6, 6))
	var lit: Dictionary = _vs.visible_cells(0)
	assert_eq(lit.size(), 9, "an authored sight of 1 lights only the 3x3 around the unit")
	assert_false(lit.has(Vector2i(8, 6)), "the default radius of 4 does not apply to it")

	var eagle := Scout.new(_p0, 6)
	_board.place(eagle, Vector2i(6, 6))
	_vs.invalidate()
	assert_true(_vs.visible_cells(0).has(Vector2i(12, 12)),
		"and an authored sight of 6 reaches further than the default")


func test_sight_range_of_falls_back_to_the_default_when_nobody_declares_one() -> void:
	assert_eq(VisionSystem.sight_range_of(Scout.new(_p0)), VisionSystem.DEFAULT_SIGHT_RANGE,
		"a character that declares no sight range sees the default distance")
	assert_eq(VisionSystem.sight_range_of(null), VisionSystem.DEFAULT_SIGHT_RANGE,
		"and so does nothing at all -- the query never faults")


func test_an_enemy_outside_every_sight_radius_is_invisible() -> void:
	var hero := Scout.new(_p0)
	var enemy := Scout.new(_p1)
	_board.place(hero, Vector2i(2, 2))
	_board.place(enemy, Vector2i(12, 12))
	assert_false(_vs.is_unit_visible(0, enemy), "an enemy nobody is looking at is hidden")
	assert_true(_vs.is_unit_visible(1, enemy), "though its own side sees it perfectly well")


func test_an_enemy_inside_the_radius_on_open_ground_is_visible() -> void:
	var hero := Scout.new(_p0)
	var enemy := Scout.new(_p1)
	_board.place(hero, Vector2i(2, 2))
	_board.place(enemy, Vector2i(5, 5))
	assert_true(_vs.is_unit_visible(0, enemy), "an enemy in the open inside sight is visible")


func test_own_units_are_always_visible_however_far_away() -> void:
	# The stray is nearly blind and stands in the far corner; the enemy is NEARER, and on ground
	# nothing player 0 owns is lighting. So the enemy is hidden and the stray -- further away
	# still -- is not, which is the point: ownership decides, not distance.
	var hero := Scout.new(_p0)
	var stray := Scout.new(_p0, 1)
	var enemy := Scout.new(_p1)
	_board.place(hero, Vector2i(0, 0))
	_board.place(stray, Vector2i(15, 15))
	_board.place(enemy, Vector2i(10, 10))
	assert_false(_vs.visible_cells(0).has(Vector2i(10, 10)),
		"nothing player 0 owns is looking at the enemy's cell")
	assert_false(_vs.is_unit_visible(0, enemy), "so the enemy standing there is hidden")
	assert_true(_vs.is_unit_visible(0, stray),
		"yet its own unit, further away again, is not -- a side never loses track of its own")


func test_a_side_with_no_units_sees_nothing() -> void:
	_board.place(Scout.new(_p1), Vector2i(5, 5))
	assert_eq(_vs.visible_cells(0).size(), 0, "no eyes on the board, no cells lit")


# --- Concealment ---------------------------------------------------------------

func test_a_smoke_veil_hides_its_occupant_from_across_the_field() -> void:
	var hero := Scout.new(_p0)
	var lurker := Scout.new(_p1)
	_board.place(hero, Vector2i(5, 5))
	_board.place(lurker, Vector2i(5, 8))  # Chebyshev 3: comfortably inside sight
	_board.put_effect(Vector2i(5, 8), _veil())

	assert_true(_vs.is_cell_visible(0, Vector2i(5, 8)),
		"the GROUND is still seen -- fog hides units, not terrain")
	assert_false(_vs.is_unit_visible(0, lurker),
		"but the unit standing in the veil is not")


func test_a_seer_beside_the_veil_sees_into_it() -> void:
	var hero := Scout.new(_p0)
	var lurker := Scout.new(_p1)
	_board.place(hero, Vector2i(5, 7))  # adjacent to the veil cell
	_board.place(lurker, Vector2i(5, 8))
	_board.put_effect(Vector2i(5, 8), _veil())
	assert_true(_vs.is_unit_visible(0, lurker),
		"you cannot see into the smoke from across the field, but you can from its edge")


func test_the_adjacency_that_reveals_a_veil_is_chebyshev() -> void:
	var hero := Scout.new(_p0)
	var lurker := Scout.new(_p1)
	_board.place(hero, Vector2i(4, 7))  # DIAGONALLY adjacent
	_board.place(lurker, Vector2i(5, 8))
	_board.put_effect(Vector2i(5, 8), _veil())
	assert_true(_vs.is_unit_visible(0, lurker),
		"a diagonal neighbour is a neighbour -- the same metric sight uses")


func test_a_veil_conceals_its_occupant_from_the_placers_side_too() -> void:
	# affected_factions = ALL and no owner is stamped on the shared authoring resource, so the
	# veil is honest cover rather than a one-way mirror. A side still sees its OWN units in it
	# (ownership short-circuits first), which is the only exemption.
	var hero := Scout.new(_p0)
	var ally_in_smoke := Scout.new(_p0)
	var enemy := Scout.new(_p1)
	_board.place(hero, Vector2i(5, 5))
	_board.place(ally_in_smoke, Vector2i(5, 6))
	_board.place(enemy, Vector2i(5, 4))
	_board.put_effect(Vector2i(5, 6), _veil())
	assert_true(_vs.is_unit_visible(0, ally_in_smoke), "my own unit in the smoke is still mine")
	assert_false(_vs.is_unit_visible(1, ally_in_smoke),
		"but the other side, standing two cells off, cannot see it")


func test_tall_grass_does_not_conceal() -> void:
	# A DESIGN PIN, not an oversight. Tall grass already pays out as +15 terrain evasion; adding
	# concealment on top would be the same cover counted twice. Concealment is authored per
	# effect, and this effect does not author it.
	var grass := load(GRASS_PATH) as TileEffectResource
	assert_not_null(grass, "tall_grass.tres loads")
	assert_false(grass.conceals_occupants, "tall grass grants evasion, not invisibility")

	var hero := Scout.new(_p0)
	var enemy := Scout.new(_p1)
	_board.place(hero, Vector2i(5, 5))
	_board.place(enemy, Vector2i(5, 7))
	_board.put_effect(Vector2i(5, 7), grass)
	assert_true(_vs.is_unit_visible(0, enemy), "so a unit standing in it is plainly visible")


func test_concealment_is_a_flag_any_effect_may_carry() -> void:
	# The "smaller fog of war on a move" hook: nothing about the vision system knows what a
	# smoke veil IS. Tick the flag on any tile effect and it conceals.
	var improvised := TileEffectResource.new()
	improvised.id = &"test_dust_cloud"
	improvised.trigger = TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING
	improvised.conceals_occupants = true

	var hero := Scout.new(_p0)
	var enemy := Scout.new(_p1)
	_board.place(hero, Vector2i(5, 5))
	_board.place(enemy, Vector2i(5, 8))
	_board.put_effect(Vector2i(5, 8), improvised)
	assert_false(_vs.is_unit_visible(0, enemy),
		"an effect nobody has ever heard of conceals, purely because it ticked the flag")


# --- Reveal on attack -----------------------------------------------------------

func test_a_hidden_attacker_gives_itself_away() -> void:
	var hero := Scout.new(_p0)
	var sniper := Scout.new(_p1)
	_board.place(hero, Vector2i(2, 2))
	_board.place(sniper, Vector2i(12, 12))  # far outside player 0's sight
	assert_false(_vs.is_unit_visible(0, sniper), "unseen before it acts")

	_vs.mark_revealed(sniper)
	assert_true(_vs.is_unit_visible(0, sniper),
		"a hidden unit that resolves a hostile move is visible to the side it hit")


func test_a_veiled_attacker_is_revealed_despite_standing_in_the_veil() -> void:
	var hero := Scout.new(_p0)
	var lurker := Scout.new(_p1)
	_board.place(hero, Vector2i(5, 5))
	_board.place(lurker, Vector2i(5, 8))
	_board.put_effect(Vector2i(5, 8), _veil())
	assert_false(_vs.is_unit_visible(0, lurker), "concealed to start with")

	_vs.mark_revealed(lurker)
	assert_true(_vs.is_unit_visible(0, lurker),
		"the veil is cover, never immunity -- attack out of it and you can be answered")


func test_a_reveal_expires_on_the_turn_boundaries() -> void:
	var hero := Scout.new(_p0)
	var sniper := Scout.new(_p1)
	_board.place(hero, Vector2i(2, 2))
	_board.place(sniper, Vector2i(12, 12))

	_vs.mark_revealed(sniper)
	for i in range(VisionSystem.REVEAL_TURNS - 1):
		_vs.note_turn_started()
		assert_true(_vs.is_unit_visible(0, sniper),
			"still revealed through the answering side's turn (boundary %d)" % (i + 1))
	_vs.note_turn_started()
	assert_false(_vs.is_unit_visible(0, sniper),
		"and back into the dark once the window has passed")


func test_a_second_attack_refreshes_the_reveal_rather_than_stacking_one() -> void:
	# CONQUEST.md rule 6: a second source of the same effect resets the timer on the one
	# instance, it never deepens or lengthens it beyond a fresh window.
	var hero := Scout.new(_p0)
	var sniper := Scout.new(_p1)
	_board.place(hero, Vector2i(2, 2))
	_board.place(sniper, Vector2i(12, 12))

	_vs.mark_revealed(sniper)
	_vs.note_turn_started()
	_vs.mark_revealed(sniper)  # attacks again: the window restarts from here
	for _i in range(VisionSystem.REVEAL_TURNS):
		_vs.note_turn_started()
	assert_false(_vs.is_unit_visible(0, sniper),
		"a refreshed reveal still runs exactly one window, not two stacked on each other")


func test_only_a_hostile_move_reveals() -> void:
	var attacker := Scout.new(_p1)
	assert_true(VisionSystem.is_hostile_move(MoveLibrary.basic_strike(), attacker),
		"a damaging move gives you away")
	assert_true(VisionSystem.is_hostile_move(MoveLibrary.expose(), attacker),
		"and so does a pure enemy-targeted debuff -- it is still an attack")
	assert_false(VisionSystem.is_hostile_move(MoveLibrary.mend(), attacker),
		"a heal does not")
	assert_false(VisionSystem.is_hostile_move(null, attacker),
		"and nothing at all does not fault")


func test_planting_a_tile_effect_does_not_reveal() -> void:
	# The one that matters most: laying the veil you are about to hide in must not be the thing
	# that lights you up.
	var place := MoveResource.new()
	place.move_id = &"test_lay_veil"
	place.display_name = "Lay Veil"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.EMPTY_TILE
	pattern.min_range = 1
	pattern.max_range = 3
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	place.targeting = pattern
	var lay := ApplyTileEffect.new()
	lay.effect = _veil()
	place.effects = [lay] as Array[MoveEffect]

	assert_false(VisionSystem.is_hostile_move(place, Scout.new(_p1)),
		"placing ground cover is not a hostile resolution")


func test_the_reveal_query_is_null_safe() -> void:
	var sniper := Scout.new(_p1)
	assert_false(_vs.is_revealed(sniper), "nothing is revealed until it acts")
	_vs.mark_revealed(sniper)
	assert_true(_vs.is_revealed(sniper), "and revealed once it has")
	assert_false(_vs.is_revealed(null), "nothing at all is never revealed, and never faults")
	_vs.mark_revealed(null)  # must not fault either
	assert_false(_vs.is_revealed(null), "marking nothing records nothing")


# --- Recompute + cache ----------------------------------------------------------

func test_vision_changed_fires_on_every_recompute() -> void:
	# GUT lambdas capture BY VALUE, so the counter has to be a reference type.
	var fired: Array = [0]
	_vs.vision_changed.connect(func() -> void: fired[0] += 1)

	_vs.invalidate()
	assert_eq(fired[0], 1, "an explicit invalidation announces once")
	_vs.note_turn_started()
	assert_eq(fired[0], 2, "a turn boundary announces (the reveal clock moved)")
	var sniper := Scout.new(_p1)
	_vs.mark_revealed(sniper)
	assert_eq(fired[0], 3, "a reveal announces -- who is visible just changed")
	_vs.set_map(_map(true))
	assert_eq(fired[0], 4, "and so does a fresh map")
	_vs.set_board(_board)
	assert_eq(fired[0], 5, "and a fresh board")


func test_setup_subscribes_to_every_signal_that_can_change_vision() -> void:
	# The wiring, asserted rather than described: a lost connection here is a lit set that
	# silently stops updating, which is invisible until somebody shoots through a wall.
	_vs.setup()
	assert_true(_connected_to(GameEvents.unit_moved), "recomputes when a unit moves")
	assert_true(_connected_to(GameEvents.unit_spawned), "and when one spawns")
	assert_true(_connected_to(GameEvents.unit_eliminated), "and when one dies")
	assert_true(_connected_to(CombatServices.tile_effects_changed),
		"and when a cell's tile effects change -- a placed or expired veil")
	assert_true(_connected_to(CombatServices.board_ready), "and when a fresh board arrives")


## True when [param sig] has a connection whose receiver is the system under test.
func _connected_to(sig: Signal) -> bool:
	for c in sig.get_connections():
		if (c["callable"] as Callable).get_object() == _vs:
			return true
	return false


func test_the_cache_is_dropped_when_the_board_changes() -> void:
	var hero := Scout.new(_p0)
	_board.place(hero, Vector2i(2, 2))
	assert_true(_vs.visible_cells(0).has(Vector2i(4, 4)), "lit from the starting cell")

	_board.move_unit(hero, Vector2i(12, 12))
	_vs.invalidate()
	var lit: Dictionary = _vs.visible_cells(0)
	assert_false(lit.has(Vector2i(4, 4)), "the old ground went dark after the move")
	assert_true(lit.has(Vector2i(12, 12)), "and the new ground is lit")


# --- Determinism ----------------------------------------------------------------

func test_two_identical_sequences_produce_identical_visible_sets() -> void:
	# Vision is a pure function of the board, so two peers that built the same board -- in a
	# DIFFERENT placement order, which is the thing that could plausibly differ between them --
	# must agree cell for cell.
	var first: Array = _run_sequence(false)
	var second: Array = _run_sequence(true)
	assert_eq(first, second,
		"the same board yields the same lit set regardless of the order it was assembled in")


## Build the same board twice, optionally placing the units in reverse order, and return the
## resulting lit set as a sorted, comparable list of cells.
func _run_sequence(reversed: bool) -> Array:
	var board := FogBoard.new()
	var a := Scout.new(_p0, 3)
	var b := Scout.new(_p0, 5)
	var c := Scout.new(_p1)
	if reversed:
		board.place(c, Vector2i(9, 1))
		board.place(b, Vector2i(4, 4))
		board.place(a, Vector2i(1, 9))
	else:
		board.place(a, Vector2i(1, 9))
		board.place(b, Vector2i(4, 4))
		board.place(c, Vector2i(9, 1))
	var vs: VisionSystem = add_child_autofree(VisionSystem.new())
	vs.set_board(board)
	vs.set_map(_map(true))
	var out: Array = vs.visible_cells(0).keys()
	out.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
		return x.x < y.x if x.x != y.x else x.y < y.y)
	return out
