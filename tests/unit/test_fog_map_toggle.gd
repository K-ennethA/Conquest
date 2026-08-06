extends GutTest

## THE FOG TOGGLE IS A PROPERTY OF THE MAP, and the SMOKE VEIL is a property of a tile effect.
## Between them they are the whole content surface of fog of war: a map author turns the
## mechanic on, and a move author places a localised patch of it. Neither needs a line of code.
##
## What this file pins:
##   * [member MapResource.fog_of_war] defaults OFF, survives a JSON round trip in both states,
##     and reads OFF on every map exported before the field existed -- the same backward
##     compatibility contract lanes and control points carry (see unit/test_map_lanes.gd);
##   * Riftwood ships with it ON and the legacy maps ship with it OFF;
##   * `smoke_veil.tres` conceals, carries its own three-round lifetime, and does nothing else;
##   * an ORDINARY [ApplyTileEffect] places it and the ORDINARY expiry sweep removes it on
##     schedule -- which is the proof that "a smaller fog of war on a move" needed no new
##     placement machinery.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

const VEIL_PATH := "res://game/tiles/effects/resources/smoke_veil.tres"
const GRASS_PATH := "res://game/tiles/effects/resources/tall_grass.tres"
const RIFTWOOD_PATH := "res://game/maps/resources/riftwood.tres"
## Two shipped maps that predate fog entirely -- the "nothing changed" fixtures.
const LEGACY_MAP_PATHS := [
	"res://game/maps/resources/kings_crossing.tres",
	"res://game/maps/resources/default_skirmish.tres",
]


func before_each() -> void:
	# CombatServices owns the APPLIED tile-effect layer this file writes into; leaving a
	# placement behind would hand it to the next suite (tests/README rule 3).
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()


# --- Fixtures ------------------------------------------------------------------

## A minimal VALID two-player map -- the shape every map authored before fog existed has.
func _plain_map() -> MapResource:
	var m := MapResource.new()
	m.map_name = "Fog Toggle Fixture"
	m.width = 10
	m.height = 10
	# Empty Start slots: legitimate (filled at match setup) and they name no catalog asset, so
	# the fixture passes the catalog-strict import gate with no painted tile layout.
	m.set_unit_spawn_at_position(Vector2i(1, 1), 0, "")
	m.set_unit_spawn_at_position(Vector2i(8, 8), 1, "")
	return m


func _round_trip(m: MapResource) -> MapResource:
	return MapResource.import_from_json(m.export_to_json(), true)


func _veil() -> TileEffectResource:
	return load(VEIL_PATH) as TileEffectResource


# --- The map toggle -------------------------------------------------------------

func test_a_map_declares_no_fog_by_default() -> void:
	assert_false(_plain_map().fog_of_war,
		"a map that says nothing about fog is fought in the open")


func test_a_fogless_map_round_trips_unchanged() -> void:
	var imported := _round_trip(_plain_map())
	assert_not_null(imported, "a map that declares no fog still imports")
	assert_false(imported.fog_of_war, "and still declares none on the way back")


func test_the_fog_flag_survives_a_json_round_trip() -> void:
	var m := _plain_map()
	m.fog_of_war = true
	var imported := _round_trip(m)
	assert_not_null(imported, "a fogged map imports")
	assert_true(imported.fog_of_war, "and is still fogged on the way back")


func test_a_payload_with_no_fog_key_imports_as_fogless() -> void:
	# Exactly what every map EXPORTED before the field existed looks like. Absent must read as
	# "no fog" rather than as a rejection, or every shared map ever made stops loading.
	var json := JSON.new()
	assert_eq(json.parse(_plain_map().export_to_json()), OK, "the fixture exports valid JSON")
	var payload: Dictionary = json.data
	(payload["gameplay"] as Dictionary).erase("fog_of_war")
	var imported := MapResource.import_from_json(JSON.stringify(payload), true)
	assert_not_null(imported, "a pre-fog payload still imports")
	assert_false(imported.fog_of_war, "and reads as fogless, which is what it means")


func test_turning_fog_on_never_invalidates_a_map() -> void:
	# A bool cannot be out of bounds or name a missing asset, so unlike a lane waypoint it
	# carries no structural check -- and must never be able to fail one.
	var m := _plain_map()
	m.fog_of_war = true
	assert_true(m.validate_map().get("valid", false),
		"a fogged map validates: %s" % "; ".join(m.validate_map().get("issues", [])))


func test_riftwood_is_the_map_that_is_fought_in_the_dark() -> void:
	var riftwood := load(RIFTWOOD_PATH) as MapResource
	assert_not_null(riftwood, "riftwood.tres loads")
	assert_true(riftwood.fog_of_war,
		"Riftwood -- lanes, jungle, tunnels, ambush cover -- ships with fog of war on")


func test_every_legacy_map_is_untouched() -> void:
	for path in LEGACY_MAP_PATHS:
		var m := load(path) as MapResource
		assert_not_null(m, "%s loads" % path)
		assert_false(m.fog_of_war, "%s predates fog and still declares none" % path)


# --- The veil resource -----------------------------------------------------------

func test_the_smoke_veil_conceals_and_does_nothing_else() -> void:
	var veil := _veil()
	assert_not_null(veil, "smoke_veil.tres loads")
	assert_eq(veil.id, &"smoke_veil", "it names itself")
	assert_true(veil.conceals_occupants, "it conceals whoever stands in it")
	assert_eq(veil.trigger, TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING,
		"as a standing state, not a per-event mutation")
	assert_eq(veil.effects.size(), 0,
		"and it carries NO payload -- no damage, no status, no stat change")
	assert_eq(veil.move_cost_bonus, 0, "walking through smoke is free")
	assert_false(veil.springs_on_pass, "it is cover, not a trap")


func test_the_veil_carries_its_own_lifetime() -> void:
	assert_eq(_veil().expiry_rounds, 3, "smoke hangs for three rounds")


func test_an_authored_lifetime_wins_over_the_modes_trap_lifetime() -> void:
	# A mode's trap lifetime is a PACING knob for the traps that have no opinion; a veil that
	# lasts three rounds is the move's DESIGN and must last three rounds in every mode.
	var veil := _veil()
	assert_eq(veil.lifetime_rounds(0), 3, "with no mode armed the authored lifetime stands")
	assert_eq(veil.lifetime_rounds(6), 3, "and it still stands when a mode declares six")


func test_an_effect_with_no_authored_lifetime_still_defers_to_the_mode() -> void:
	# The backward-compatibility half: every effect that shipped before the field existed
	# reports 0 and reaches ModeTuning exactly as it always did.
	var grass := load(GRASS_PATH) as TileEffectResource
	assert_eq(grass.expiry_rounds, 0, "tall grass declares no lifetime of its own")
	assert_eq(grass.lifetime_rounds(6), 6, "so a mode's six-round trap lifetime applies to it")
	assert_eq(grass.lifetime_rounds(0), 0, "and with no mode armed it never expires")


func test_tall_grass_does_not_conceal() -> void:
	# A DESIGN PIN. Tall grass already pays out as +15 terrain evasion; concealment on top
	# would be the same cover counted twice.
	assert_false((load(GRASS_PATH) as TileEffectResource).conceals_occupants,
		"tall grass grants evasion, not invisibility")


# --- Placing and expiring one -----------------------------------------------------

func test_an_ordinary_apply_tile_effect_places_the_veil() -> void:
	# THE REUSE CLAIM, tested: no FogVeilEffect, no bespoke placement path. The move-effect that
	# lays a vine trap lays a smoke veil.
	var caster := Doubles.CombatUnit.new(0, { "attack": 10 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_lay_veil_at(Vector2i(2, 2), caster, board)

	var placed := _placed_veil_at(Vector2i(2, 2))
	assert_not_null(placed, "the veil is on the cell")
	assert_true(placed.conceals_occupants, "and it still conceals after being placed")


func test_a_placed_veil_expires_on_schedule() -> void:
	var caster := Doubles.CombatUnit.new(0, { "attack": 10 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_lay_veil_at(Vector2i(2, 2), caster, board)

	var placed := _placed_veil_at(Vector2i(2, 2))
	assert_true(placed.expires(), "the placed copy carries a clock")
	assert_false(placed.is_expired_on(2), "it is still hanging two rounds in")
	assert_true(placed.is_expired_on(3), "and gone on the third")

	# Through the SAME sweep a spent trap takes, so an expired veil leaves the board identically.
	assert_eq(TileEffectSystem.expire_placed_effects(2).size(), 0,
		"the round-2 sweep finds nothing to take")
	assert_eq(TileEffectSystem.expire_placed_effects(3).size(), 1,
		"the round-3 sweep takes exactly the veil")
	assert_null(_placed_veil_at(Vector2i(2, 2)), "and the cell is clear again")


func test_placing_a_veil_never_stamps_the_authored_resource() -> void:
	# CONQUEST.md rule 7: the .tres is loaded once and handed to every caster, so the placement
	# record has to land on a per-cast copy or the next battle inherits this one's clock.
	var caster := Doubles.CombatUnit.new(0, { "attack": 10 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_lay_veil_at(Vector2i(2, 2), caster, board)
	assert_false(_veil().is_runtime_placement(),
		"the shared authoring resource is never stamped as a placement")


## Cast a veil-placing move at [param cell] through the ordinary effect pipeline.
func _lay_veil_at(cell: Vector2i, caster, board) -> void:
	var move := MoveResource.new()
	move.move_id = &"test_lay_veil"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.EMPTY_TILE
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	var lay := ApplyTileEffect.new()
	lay.effect = _veil()
	var ctx := MoveContext.new(caster, board, move, cell, [cell] as Array[Vector2i])
	lay.apply(ctx)


## The runtime-placed smoke veil on [param cell], or null.
func _placed_veil_at(cell: Vector2i) -> TileEffectResource:
	for te in CombatServices.applied_tile_effects_at(cell):
		if te is TileEffectResource and (te as TileEffectResource).id == &"smoke_veil":
			return te
	return null
