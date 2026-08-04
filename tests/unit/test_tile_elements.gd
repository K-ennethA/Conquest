extends GutTest

## ELEMENTS ON THE GROUND: the tile-effect element map, the matchup that scales damage a
## tile or a hazard deals, and the "at home" modulation of what a tile GIVES.
##
## The load-bearing properties, in the order they are pinned below:
##
##   1. THE MAP IS THE AUTHORITY. A tile effect's element is looked up by id in
##      element_chart.tres. An id nobody elemented, a null, an int, a garbage object --
##      all of them resolve to &"" and then to neutral, as a RETURNED value. Nothing here
##      may push an engine error (tests/README.md rule 1).
##   2. TILE DAMAGE IS MATCHED, through the REAL tick path (TileEffectSystem ->
##      TileEffectResource.run -> DamageEffect -> DamageMath), on the SHIPPED .tres
##      content, with the same one-round()-per-step rounding weapon damage uses.
##   3. THE MATRIX AND NOTHING ELSE. A fire unit on a fire tile takes x0.75 -- not
##      x0.75 x 1.25 x 0.9. The tile amplifier and the home benefit exist for a MOVE
##      landing on an occupant, and folding them into the tile's own burn would count
##      "you are standing in it" three times.
##   4. A HAZARD IS ELEMENTED THE SAME WAY, off the move that cast it.
##   5. AT HOME, for what a tile gives or takes -- but never for a status.
##   6. PREVIEW == REALITY. What the terrain panel prints is the tick's own arithmetic.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

const FIRE_TILE := "res://game/tiles/effects/resources/fire.tres"
const VENT_TILE := "res://game/tiles/effects/resources/scorching_vent.tres"
const GRASS_TILE := "res://game/tiles/effects/resources/tall_grass.tres"
const ICE_TILE := "res://game/tiles/effects/resources/slippery_ice.tres"
const MEADOW_TILE := "res://game/tiles/effects/resources/sacred_meadow.tres"
const RUBBLE_TILE := "res://game/tiles/effects/resources/rock_rubble.tres"
const VINE_TILE := "res://game/tiles/effects/resources/vine_trap.tres"
const WATER_TILE := "res://game/tiles/effects/resources/empowering_water.tres"
const FORTIFY_TILE := "res://game/tiles/effects/resources/fortify.tres"

## Every tile effect that ships, and the element the chart assigns it.
const ASSIGNMENTS := {
	FIRE_TILE: &"fire",
	VENT_TILE: &"fire",
	GRASS_TILE: &"nature",
	VINE_TILE: &"nature",
	ICE_TILE: &"water",
	WATER_TILE: &"water",
	FORTIFY_TILE: &"earth",
	RUBBLE_TILE: &"earth",
	# NATURE, not holy, despite the name -- an authored design call: the meadow is a living
	# place whose heal runs stronger for the nature creatures that belong in it. The .tres
	# notes carry the reasoning.
	MEADOW_TILE: &"nature",
}


## The chart is a STATIC cache, i.e. global state. Restored from after_each so a failing
## assertion cannot leak an injected chart into every later suite (tests/README.md r.3).
func after_each() -> void:
	ElementChart.reset_chart()


# --- Fixtures -----------------------------------------------------------------


func _tile(path: String) -> TileEffectResource:
	var res = load(path)
	assert_true(res is TileEffectResource, "%s is an authored tile effect" % path)
	return res


## An occupant of [param element] standing alone on [param cell] of a fresh board that
## ANSWERS tile_effects_at -- so nothing in this suite falls back to the live
## CombatServices autoload and inherits whatever the previous suite left there.
func _stand(element: StringName, effects: Array, cell: Vector2i = Vector2i(2, 2)) -> Dictionary:
	var unit := _ElementUnit.new(element, 100)
	var board := Doubles.TileEffectBoard.new()
	board.place(unit, cell)
	board.set_tile_effects(cell, effects)
	return { "unit": unit, "board": board, "cell": cell }


## HP the occupant loses to one turn-start tick of the tile it is standing on.
func _tick_loss(fixture: Dictionary) -> int:
	var unit = fixture["unit"]
	var before: int = unit.hp
	var system = autofree(TileEffectSystem.new())
	system.on_turn_start(unit, fixture["board"])
	return before - unit.hp


# ==============================================================================
# 1. THE MAP IS THE AUTHORITY
# ==============================================================================


func test_every_shipped_tile_effect_has_the_element_the_chart_assigns_it() -> void:
	for path in ASSIGNMENTS:
		var te := _tile(path)
		assert_eq(te.element(), StringName(ASSIGNMENTS[path]),
			"%s reads as %s, from element_chart.tres and nowhere else"
				% [te.id, ASSIGNMENTS[path]])


func test_a_tile_effect_carries_no_element_field_of_its_own() -> void:
	# The map is the SINGLE authority (CONQUEST.md rule 9). A field on the resource would
	# be a second one, and the first thing to disagree with it.
	var fresh := TileEffectResource.new()
	var names: Array = []
	for property in fresh.get_property_list():
		names.append(String(property.get("name", "")))
	assert_false("element" in names,
		"TileEffectResource exposes no element PROPERTY -- element() is a chart lookup")
	fresh.id = &"tall_grass"
	assert_eq(fresh.element(), &"nature",
		"so an effect built in code inherits the map's answer purely from its id")


func test_an_unassigned_id_is_elementless_rather_than_an_error() -> void:
	var orphan := TileEffectResource.new()
	orphan.id = &"quicksand"
	assert_eq(orphan.element(), &"",
		"terrain nobody has elemented is elementless, quietly")
	assert_almost_eq(ElementChart.environment_scale_for(orphan.element(),
		_ElementUnit.new(&"nature", 100)), 1.0, 0.001,
		"and an elementless tile scales its damage by exactly nothing")


func test_garbage_tile_effects_are_quiet() -> void:
	# Every one of these must RETURN &"". A push_error on any of them would fail this test
	# on the engine log alone (tests/README.md rule 1).
	for junk in [null, 42, 3.5, "tall_grass", Vector2i.ZERO, [], {}]:
		assert_eq(ElementChart.tile_element_of(junk), &"",
			"a non-tile-effect value carries no tile element, quietly")
	var no_id := TileEffectResource.new()
	assert_eq(ElementChart.tile_element_of(no_id), &"",
		"an effect with an empty id is elementless, not a lookup failure")


func test_a_cells_elements_are_read_in_effect_order_and_deduped() -> void:
	assert_eq(ElementChart.tile_elements_of([_tile(GRASS_TILE), null, _tile(VINE_TILE)]),
		[&"nature"],
		"two nature effects on one cell contribute one element; a null is skipped")
	assert_eq(ElementChart.tile_elements_of([_tile(FIRE_TILE), _tile(GRASS_TILE)]),
		[&"fire", &"nature"],
		"a mixed cell reports both, base terrain first -- the cell's own order")
	assert_eq(ElementChart.tile_elements_of("not an array"), [],
		"anything that is not a list of effects contributes nothing, quietly")


func test_the_map_is_data_and_can_be_retuned_without_code() -> void:
	var custom := ElementChartResource.new()
	custom.tile_elements = { &"tall_grass": &"dark" }
	ElementChart.set_chart(custom)
	assert_eq(_tile(GRASS_TILE).element(), &"dark",
		"swapping the resource re-elements the terrain -- nothing is hard-coded")


# ==============================================================================
# 2/3. TILE DAMAGE IS MATCHED -- through the real tick, by the matrix alone
# ==============================================================================


func test_a_fire_tile_burns_a_nature_occupant_harder() -> void:
	assert_eq(_tick_loss(_stand(&"nature", [_tile(FIRE_TILE)])), 19,
		"fire terrain into its opposite nature: 15 x 1.25 = 18.75 -> 19")


func test_a_fire_tile_barely_singes_a_fire_occupant() -> void:
	assert_eq(_tick_loss(_stand(&"fire", [_tile(FIRE_TILE)])), 11,
		"a fire unit at home in fire: 15 x 0.75 = 11.25 -> 11, the matrix ALONE")


func test_an_unmatched_occupant_takes_the_authored_number() -> void:
	assert_eq(_tick_loss(_stand(&"holy", [_tile(FIRE_TILE)])), 15,
		"fire and holy have no authored matchup, so the tile deals exactly its 15")
	assert_eq(_tick_loss(_stand(&"", [_tile(FIRE_TILE)])), 15,
		"and a unit with no element at all is neutral against every tile")


func test_the_tile_amplifier_and_home_benefit_are_not_folded_in() -> void:
	# THE anti-double-count assertion. If tile damage went through the ordinary
	# move-vs-occupant rule it would resolve 15 x 0.75 (matchup) x 1.25 (the occupant is
	# standing in fire) x 0.9 (the occupant is at home) = 12.66 -> 13. It must be 11.
	assert_eq(_tick_loss(_stand(&"fire", [_tile(FIRE_TILE)])), 11,
		"standing in it is one fact, and the matrix already prices it once")


func test_a_second_element_on_the_cell_does_not_amplify_the_first() -> void:
	# Fortified ground (earth) under a burning cell must not re-colour the FIRE tile's own
	# burn; each effect is scaled by ITS OWN element, never by the cell's.
	assert_eq(_tick_loss(_stand(&"nature", [_tile(FIRE_TILE), _tile(FORTIFY_TILE)])), 19,
		"the fire tile burns as fire regardless of what else the cell carries")


func test_tile_damage_rounds_like_the_rest_of_the_damage_math() -> void:
	var thirteen := _authored_burn(&"fire", 13)
	assert_eq(_tick_loss(_stand(&"nature", [thirteen])), 16,
		"13 x 1.25 = 16.25 rounds to 16, the same round() a weapon hit uses")
	assert_eq(_tick_loss(_stand(&"fire", [thirteen])), 10,
		"13 x 0.75 = 9.75 rounds to 10")


func test_a_resisted_tile_still_hurts() -> void:
	assert_eq(_tick_loss(_stand(&"fire", [_authored_burn(&"fire", 1)])), 1,
		"1 x 0.75 = 0.75 floors at 1 -- being at home is a discount, not immunity")


func test_the_vents_lighter_burn_is_matched_too() -> void:
	assert_eq(_tick_loss(_stand(&"nature", [_tile(VENT_TILE)])), 10,
		"the scorching vent is fire as well: 8 x 1.25 = 10")


func test_a_snare_that_damages_on_entry_is_matched_on_entry() -> void:
	# vine_trap is nature, ON_ENTER, enemies-only, and 18 MAGICAL damage.
	var fixture := _stand(&"nature", [_tile(VINE_TILE)])
	var unit = fixture["unit"]
	# The trap springs on the tile's ENEMIES; the occupant is team 1, so team 0 is the
	# perspective the faction filter resolves against.
	fixture["board"].perspective = _ElementUnit.new(&"", 100, 0)
	var system = autofree(TileEffectSystem.new())
	system.on_enter(unit, fixture["cell"], fixture["board"])
	assert_eq(100 - unit.hp, 14,
		"a nature unit resists nature brambles: 18 x 0.75 = 13.5 -> 14")


# ==============================================================================
# 4. HAZARDS
# ==============================================================================


func test_a_hazard_scales_its_band_damage_by_its_own_element() -> void:
	assert_eq(_vine_loss(&"nature", &"fire"), 25,
		"a nature vine into a fire unit is strong: 20 x 1.25 = 25")
	assert_eq(_vine_loss(&"nature", &"nature"), 15,
		"and a nature unit shrugs it off: 20 x 0.75 = 15")
	assert_eq(_vine_loss(&"nature", &"holy"), 20,
		"an unauthored pairing takes the snapshotted number unchanged")


func test_an_elementless_hazard_is_exactly_what_it_always_was() -> void:
	assert_eq(_vine_loss(&"", &"nature"), 20,
		"a vine cast by an unelemented move deals its raw damage, as before elements")


func test_a_restored_hazard_keeps_its_element_and_an_old_save_stays_neutral() -> void:
	var manager = autofree(HazardManager.new())
	var vine := TravelingHazard.new(Vector2i.ZERO, Vector2i(1, 0), 1, 2, 6, 20,
		CombatTypes.DamageCategory.TRUE, CombatTypes.TargetKind.ANY_UNIT, null)
	vine.element = &"nature"
	manager.register(vine)

	var state: Dictionary = manager.snapshot_state(func(_u): return -1)
	assert_eq(String(state["hazards"][0]["element"]), "nature",
		"the vine's element is part of the mid-battle snapshot")

	manager.restore_state(state, func(_i): return null)
	assert_eq(manager._hazards[0].element, &"nature", "and survives the resume")

	# A snapshot written before hazards carried an element has no such key.
	state["hazards"][0].erase("element")
	manager.restore_state(state, func(_i): return null)
	assert_eq(manager._hazards[0].element, &"",
		"an older save restores an ELEMENTLESS vine, i.e. the damage it was saved with")


# ==============================================================================
# 5. AT HOME -- what the tile gives, and what it takes
# ==============================================================================


func test_a_matching_occupant_reads_its_own_terrain_better() -> void:
	var fixture := _stand(&"nature", [_tile(GRASS_TILE)])
	assert_eq(TerrainStats.bonus_for(fixture["unit"], "evasion", fixture["board"]), 19,
		"a nature unit in nature tall grass: +15 x 1.25 = 18.75 -> +19 evasion")


func test_a_stranger_gets_exactly_the_authored_bonus() -> void:
	for element in [&"fire", &"", &"plasma"]:
		var fixture := _stand(element, [_tile(GRASS_TILE)])
		assert_eq(TerrainStats.bonus_for(fixture["unit"], "evasion", fixture["board"]), 15,
			"a %s unit gets tall grass's authored +15 and nothing more" % element)


func test_a_matching_occupant_shrugs_off_its_own_terrains_penalty() -> void:
	var home := _stand(&"water", [_tile(ICE_TILE)])
	assert_eq(TerrainStats.bonus_for(home["unit"], "evasion", home["board"]), -9,
		"a water unit keeps its feet on water ice: -10 x 0.9 = -9 evasion")
	var stranger := _stand(&"fire", [_tile(ICE_TILE)])
	assert_eq(TerrainStats.bonus_for(stranger["unit"], "evasion", stranger["board"]), -10,
		"and everyone else takes the full authored penalty")


func test_the_sign_of_an_effect_can_never_be_flipped() -> void:
	assert_true(ElementChart.home_effect_amount(_tile(ICE_TILE), -10,
		_ElementUnit.new(&"water", 100)) < 0,
		"a penalty stays a penalty, however generous the scale")
	assert_true(ElementChart.home_effect_amount(_tile(GRASS_TILE), 15,
		_ElementUnit.new(&"nature", 100)) > 0,
		"and a benefit stays a benefit")
	assert_eq(ElementChart.home_effect_amount(_tile(ICE_TILE), -1,
		_ElementUnit.new(&"water", 100)), -1,
		"a magnitude of 1 floors at 1 -- no scale can erase an authored effect")
	assert_eq(ElementChart.home_effect_amount(_tile(GRASS_TILE), 0,
		_ElementUnit.new(&"nature", 100)), 0,
		"and nothing is still nothing")


func test_a_heal_a_tile_grants_is_modulated_at_home() -> void:
	var home := _stand(&"nature", [_tile(MEADOW_TILE)])
	home["unit"].hp = 50
	autofree(TileEffectSystem.new()).on_turn_start(home["unit"], home["board"])
	assert_eq(home["unit"].hp, 63,
		"a NATURE unit on the nature meadow heals 10 x 1.25 = 12.5 -> 13")

	for element in [&"holy", &"dark", &""]:
		var stranger := _stand(element, [_tile(MEADOW_TILE)])
		stranger["unit"].hp = 50
		autofree(TileEffectSystem.new()).on_turn_start(stranger["unit"], stranger["board"])
		assert_eq(stranger["unit"].hp, 60,
			"a %s unit heals the authored 10 -- the meadow is not holy ground" % element)


func test_modulating_an_effect_never_mutates_the_shared_resource() -> void:
	# These resources are loaded once and handed to every cell on the map; mutating one in
	# place would retune the terrain for the whole board (CONQUEST.md rule 7).
	var meadow := _tile(MEADOW_TILE)
	var authored: int = int(meadow.effects[0].amount)
	var home := _stand(&"nature", [meadow])
	home["unit"].hp = 50
	autofree(TileEffectSystem.new()).on_turn_start(home["unit"], home["board"])
	assert_eq(int(meadow.effects[0].amount), authored,
		"the authored heal is untouched -- the modulated copy is a duplicate")


func test_the_at_home_summary_is_what_the_run_applies() -> void:
	# The panel's boost line reads this; the run scales through the same function, so the
	# number the card promises is the heal the unit is about to receive (rule 9).
	var meadow := _tile(MEADOW_TILE)
	var home := _stand(&"nature", [meadow])
	var summary: Dictionary = meadow.home_summary_for(home["unit"])
	assert_eq(int(summary["authored"]), 10, "the meadow authors a 10 HP heal")
	assert_eq(int(summary["landed"]), 13, "which lands as 13 for a nature occupant")
	assert_eq(summary["kind"], &"heal", "and it is a HEAL, not a stat change")

	home["unit"].hp = 50
	autofree(TileEffectSystem.new()).on_turn_start(home["unit"], home["board"])
	assert_eq(home["unit"].hp - 50, int(summary["landed"]),
		"the summary's number is the HP the tick actually restored")

	var stranger := _stand(&"fire", [meadow])
	var plain: Dictionary = meadow.home_summary_for(stranger["unit"])
	assert_eq(int(plain["landed"]), int(plain["authored"]),
		"for a stranger nothing changed, which is how a UI knows to say nothing")


func test_the_at_home_summary_reports_stat_tiles_and_penalties() -> void:
	var grass := _tile(GRASS_TILE)
	var in_grass := _stand(&"nature", [grass])
	var boost: Dictionary = grass.home_summary_for(in_grass["unit"])
	assert_eq(int(boost["landed"]), 19, "tall grass reads +15 -> +19 for a nature unit")
	assert_eq(boost["kind"], &"stat", "and it is a stat change, not a heal")

	var ice := _tile(ICE_TILE)
	var on_ice := _stand(&"water", [ice])
	var softened: Dictionary = ice.home_summary_for(on_ice["unit"])
	assert_eq(int(softened["landed"]), -9, "ice reads -10 -> -9 for a water unit")

	var rubble := _tile(RUBBLE_TILE)
	var summary: Dictionary = rubble.home_summary_for(_ElementUnit.new(&"earth", 100))
	assert_eq(int(summary["authored"]), 0,
		"a tile whose only payload is a STATUS reports no magnitude to scale")


func test_the_at_home_scale_is_the_authored_knob_not_a_ratio() -> void:
	assert_almost_eq(ElementChart.home_effect_scale(15), 1.25, 0.001,
		"a benefit is scaled by own_tile_effect_bonus -- 19/15 would read 1.27 and lie")
	assert_almost_eq(ElementChart.home_effect_scale(-10), 0.9, 0.001,
		"a penalty is scaled by own_tile_benefit")
	assert_almost_eq(ElementChart.home_effect_scale(0), 1.0, 0.001,
		"and nothing is scaled by nothing")


func test_a_status_a_tile_applies_is_never_modulated() -> void:
	# Rubble's slow is binary, and its only knob is a roll CHANCE. Scaling that would put
	# an RNG draw where an authored 1.0 short-circuits one, and desync every replay after
	# it -- so the at-home rule deliberately does not reach it.
	var rubble := _tile(RUBBLE_TILE)
	var apply_status = rubble.effects[0]
	var authored: float = float(apply_status.chance)
	assert_eq(rubble.element(), &"earth", "rubble is earth, so an earth unit WOULD match")
	assert_eq(ElementChart.home_effect_amount(rubble, 0, _ElementUnit.new(&"earth", 100)), 0,
		"there is no magnitude on a status for the rule to scale")
	assert_almost_eq(float(apply_status.chance), authored, 0.0001,
		"and its roll chance is exactly as authored")


func test_move_cost_is_deliberately_untouched_by_elements() -> void:
	var rubble := _tile(RUBBLE_TILE)
	assert_eq(rubble.move_cost_bonus, 2,
		"an element cannot make broken stone cheaper to walk over; move cost is geometry")


# ==============================================================================
# 6. PREVIEW == REALITY
# ==============================================================================


func test_the_panels_damage_readout_is_the_tick_itself() -> void:
	for element in [&"nature", &"fire", &"holy", &"", &"plasma"]:
		var fixture := _stand(element, [_tile(FIRE_TILE)])
		var previewed: int = _tile(FIRE_TILE).damage_preview_for(
			fixture["unit"], fixture["board"])
		assert_eq(previewed, _tick_loss(fixture),
			"what the terrain card promises a %s unit is what the tile takes off" % element)


func test_a_tile_that_deals_no_damage_previews_nothing() -> void:
	var fixture := _stand(&"nature", [_tile(GRASS_TILE)])
	assert_eq(_tile(GRASS_TILE).damage_preview_for(fixture["unit"], fixture["board"]), 0,
		"tall grass conceals; it does not burn, and the card must not claim it does")
	assert_eq(_tile(FIRE_TILE).damage_preview_for(null, null), 0,
		"and with nobody selected there is nothing to preview, quietly")


func test_the_readout_is_deterministic() -> void:
	# No RNG anywhere in the element path: identical inputs, identical answer, every time.
	var fixture := _stand(&"nature", [_tile(FIRE_TILE)])
	var first: int = _tile(FIRE_TILE).damage_preview_for(fixture["unit"], fixture["board"])
	for i in range(8):
		assert_eq(_tile(FIRE_TILE).damage_preview_for(fixture["unit"], fixture["board"]),
			first, "the element-adjusted tile damage never varies between reads")


# --- Helpers ------------------------------------------------------------------


## A turn-start burn of [param element] for a flat [param power] of TRUE damage, so the
## only arithmetic under test is the matchup.
func _authored_burn(element: StringName, power: int) -> TileEffectResource:
	var te := TileEffectResource.new()
	# The id is what the chart is keyed on -- &"fire" is the shipped fire assignment.
	te.id = element
	te.display_name = "Test Burn"
	te.trigger = TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING
	var dmg := DamageEffect.new()
	dmg.power = power
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	var fx: Array[MoveEffect] = [dmg]
	te.effects = fx
	return te


## HP a [param victim_element] unit loses to one advance of a 20-damage vine of
## [param vine_element].
func _vine_loss(vine_element: StringName, victim_element: StringName) -> int:
	var victim := _ElementUnit.new(victim_element, 100)
	var board := _VineBoard.new()
	board.place(victim, Vector2i(1, 0))
	var vine := TravelingHazard.new(Vector2i(0, 0), Vector2i(1, 0), 0, 1, 4, 20,
		CombatTypes.DamageCategory.TRUE, CombatTypes.TargetKind.ANY_UNIT, null)
	vine.element = vine_element
	vine.advance(board)
	return 100 - victim.hp


# --- Local doubles ------------------------------------------------------------
#
# `get_element` is a method the production code BRANCHES on, so it stays out of the shared
# doubles: bolting it onto one would silently reroute every suite that uses it (see the
# warning at the top of tests/helpers/test_doubles.gd).


## The smallest thing that carries an element and can be hurt. `team` is here because the
## shared boards answer are_enemies/are_allies by comparing it.
class _ElementUnit:
	var element: StringName
	var hp: int
	var team: int

	func _init(p_element: StringName, p_hp: int, p_team: int = 1) -> void:
		element = p_element
		hp = p_hp
		team = p_team

	func get_element() -> StringName:
		return element

	func get_stat(stat_name: String) -> int:
		return hp if stat_name == "health" else 0

	func get_hp() -> int:
		return hp

	func take_damage(amount: int) -> void:
		hp -= amount

	func heal(amount: int) -> void:
		hp += amount


## The minimum a [TravelingHazard] band asks of a board: who is standing where.
class _VineBoard:
	var placements: Array = []

	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out

	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)

	func are_enemies(_a, _b) -> bool:
		return true

	func are_allies(_a, _b) -> bool:
		return false
