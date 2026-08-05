extends GutTest

## [TerrainVisuals] -- the shared vocabulary for what the GROUND under a unit is giving it.
##
## The rule this suite exists to hold: the chip NEVER re-derives the number. Every amount
## comes back from [method TerrainStats.bonus_for], which is the same function
## [method MoveContext.hit_chance] and [method MoveExecutor.preview_vs] read -- so what a
## nature unit's chip says (+19 in nature tall grass) and what an attacker's forecast has to
## beat are one lookup, element home-boost included. A helper that formatted an authored +15
## would be advertising a number the player does not have.
##
## The rendered proof (a real chip on a real mounted surface, and the live font actually
## being able to draw the mark) is `tests/integration/test_terrain_readout_live.gd`. This
## file is the vocabulary: numbers, wording, tint, direction and overflow.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

const GRASS_TILE := "res://game/tiles/effects/resources/tall_grass.tres"
const ICE_TILE := "res://game/tiles/effects/resources/slippery_ice.tres"
const FORTIFY_TILE := "res://game/tiles/effects/resources/fortify.tres"

const CELL := Vector2i(2, 2)


## The chart is a STATIC cache, i.e. global state (tests/README.md rule 3).
func after_each() -> void:
	ElementChart.reset_chart()


# --- Fixtures -----------------------------------------------------------------

func _tile(path: String) -> TileEffectResource:
	var res = load(path)
	assert_true(res is TileEffectResource, "%s is an authored tile effect" % path)
	return res


## An occupant of [param element] standing alone on a board that ANSWERS tile_effects_at,
## so nothing here falls back to the live CombatServices autoload and inherits whatever the
## previous suite left in it.
func _stand(element: StringName, effects: Array) -> Dictionary:
	var unit := _ElementUnit.new(element)
	var board := Doubles.TileEffectBoard.new()
	board.place(unit, CELL)
	board.set_tile_effects(CELL, effects)
	return { "unit": unit, "board": board }


func _entries(element: StringName, effects: Array) -> Array:
	var fixture: Dictionary = _stand(element, effects)
	return TerrainVisuals.bonuses_for(fixture["unit"], fixture["board"])


# ==============================================================================
# 1. The number is the one combat uses
# ==============================================================================

func test_a_stranger_in_tall_grass_wears_the_authored_bonus() -> void:
	var entries: Array = _entries(&"fire", [_tile(GRASS_TILE)])
	assert_eq(entries.size(), 1, "one stat is moving, so one chip")
	assert_eq(String(entries[0]["stat"]), "evasion", "and it is evasion")
	assert_eq(int(entries[0]["amount"]), 15, "tall grass's authored +15 for a non-nature unit")
	assert_true(bool(entries[0]["gain"]), "a bonus is a gain")


func test_a_nature_unit_wears_the_ELEMENT_BOOSTED_number_not_the_authored_one() -> void:
	# THE point of routing through TerrainStats. 15 x 1.25 = 18.75 -> 19, and that 19 is what
	# an attacker's hit chance has to beat -- so 19 is what the chip must say.
	var fixture: Dictionary = _stand(&"nature", [_tile(GRASS_TILE)])
	var entries: Array = TerrainVisuals.bonuses_for(fixture["unit"], fixture["board"])
	assert_eq(int(entries[0]["amount"]), 19,
		"a nature unit reads its own nature grass better: +15 x 1.25 = +19")
	assert_eq(int(entries[0]["amount"]),
		TerrainStats.bonus_for(fixture["unit"], "evasion", fixture["board"]),
		"and it is literally TerrainStats' own answer, not a second calculation")
	assert_eq(TerrainVisuals.chip_text(entries[0]), "±AVO+19",
		"which is the number on the chip: %s" % TerrainVisuals.chip_text(entries[0]))


func test_the_chip_number_is_what_the_hit_chance_has_to_beat() -> void:
	# Stated as the rule rather than as a coincidence of two constants: whatever the chip
	# says, a 100%-accuracy swing at this unit lands at exactly 100 minus it.
	var fixture: Dictionary = _stand(&"nature", [_tile(GRASS_TILE)])
	var entries: Array = TerrainVisuals.bonuses_for(fixture["unit"], fixture["board"])
	var move := MoveResource.new()
	move.accuracy = 1.0
	var ctx := MoveContext.new(fixture["unit"], fixture["board"], move, CELL,
		[CELL] as Array[Vector2i])
	assert_eq(ctx.hit_chance(fixture["unit"]), 100.0 - float(int(entries[0]["amount"])),
		"the forecast's avoid and the chip's avoid are the same number")


# ==============================================================================
# 2. Losses, several stats, and nothing at all
# ==============================================================================

func test_slippery_ice_reads_as_a_LOSS_and_is_tinted_for_one() -> void:
	var entries: Array = _entries(&"fire", [_tile(ICE_TILE)])
	assert_eq(int(entries[0]["amount"]), -10, "ice takes 10 evasion off a non-water unit")
	assert_false(bool(entries[0]["gain"]), "which is a loss")
	assert_eq(TerrainVisuals.chip_text(entries[0]), "±AVO-10",
		"the chip prints the sign, so it survives being read in greyscale")
	assert_eq(TerrainVisuals.color_for(entries[0]), TerrainVisuals.LOSS_COLOR,
		"and is tinted with the HUD's nerf ember rather than the terrain green")


func test_a_water_unit_keeps_its_feet_and_the_chip_says_so() -> void:
	var entries: Array = _entries(&"water", [_tile(ICE_TILE)])
	assert_eq(int(entries[0]["amount"]), -9,
		"a water unit on water ice loses 9, not 10 -- the at-home benefit")
	assert_eq(TerrainVisuals.chip_text(entries[0]), "±AVO-9", "and the chip quotes that")


func test_two_stats_on_one_cell_are_two_chips() -> void:
	var entries: Array = _entries(&"fire", [_tile(GRASS_TILE), _tile(FORTIFY_TILE)])
	assert_eq(entries.size(), 2, "tall grass over a fortified cell moves two different stats")
	assert_eq(TerrainVisuals.chip_text(entries[0]), "±AVO+15", "the evasion layer")
	assert_eq(TerrainVisuals.chip_text(entries[1]), "±DEF+3", "and the defense layer")


func test_two_layers_of_the_SAME_stat_are_one_chip_carrying_their_sum() -> void:
	# Grass (+15) and ice (-10) on one cell: the player has ONE avoid number, and it is the
	# one combat sums, not two chips to add up in their head.
	var fixture: Dictionary = _stand(&"fire", [_tile(GRASS_TILE), _tile(ICE_TILE)])
	var entries: Array = TerrainVisuals.bonuses_for(fixture["unit"], fixture["board"])
	assert_eq(entries.size(), 1, "one stat, one chip, however many layers moved it")
	assert_eq(int(entries[0]["amount"]), 5, "15 - 10 = +5, which is what TerrainStats sums")
	assert_eq(int(entries[0]["amount"]),
		TerrainStats.bonus_for(fixture["unit"], "evasion", fixture["board"]),
		"and again: the chip is quoting, never adding")


func test_layers_that_cancel_exactly_produce_no_chip_at_all() -> void:
	var cancel := StatModifierEffect.new()
	cancel.stat_name = "evasion"
	cancel.amount = -15
	var counter := TileEffectResource.new()
	counter.id = &"counterweight"
	counter.display_name = "Counterweight"
	counter.trigger = TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING
	counter.effects = [cancel]

	var fixture: Dictionary = _stand(&"fire", [_tile(GRASS_TILE), counter])
	assert_eq(TerrainStats.bonus_for(fixture["unit"], "evasion", fixture["board"]), 0,
		"the two layers really do cancel in the sum combat reads")
	assert_true(TerrainVisuals.bonuses_for(fixture["unit"], fixture["board"]).is_empty(),
		"a net zero is not news, and a '±AVO+0' chip would be furniture")


func test_plain_ground_and_broken_units_produce_nothing() -> void:
	var bare := Doubles.TileEffectBoard.new()
	var unit := _ElementUnit.new(&"nature")
	bare.place(unit, CELL)
	assert_true(TerrainVisuals.bonuses_for(unit, bare).is_empty(),
		"bare earth gives a unit nothing to wear")
	assert_true(TerrainVisuals.bonuses_for(null, bare).is_empty(),
		"and a null unit is answered with an empty list, not an error")
	assert_false(TerrainVisuals.has_bonus(unit, bare), "has_bonus agrees")


# ==============================================================================
# 3. Wording, tint and overflow
# ==============================================================================

func test_the_tooltip_names_the_terrain_the_real_number_and_the_condition() -> void:
	var entries: Array = _entries(&"nature", [_tile(GRASS_TILE)])
	var tip: String = TerrainVisuals.tooltip_for(entries[0])
	gut.p("tooltip     : %s" % tip)
	assert_true(tip.contains("Tall Grass"), "it names the tile: %s" % tip)
	assert_true(tip.contains("+19"),
		"with the number the unit ACTUALLY has, boost included: %s" % tip)
	assert_false(tip.contains("+15"),
		"and never the authored number a nature unit does not get: %s" % tip)
	assert_true(tip.contains("evasion"), "it names the stat: %s" % tip)
	assert_true(tip.contains("while standing here"),
		"and says the bonus is a consequence of POSITION, which is the whole difference "
		+ "between a terrain chip and a status chip: %s" % tip)


func test_the_roomy_label_names_the_terrain_because_the_hover_card_has_no_tooltip() -> void:
	var entries: Array = _entries(&"fire", [_tile(GRASS_TILE)])
	assert_eq(TerrainVisuals.full_chip_text(entries[0]), "±AVO+15 · Tall Grass",
		"the hover card's subtree is click-through, so its chip has to say it in the label")


func test_the_terrain_mark_collides_with_no_other_vocabulary() -> void:
	# One row on the health bar carries status badges, terrain chips and (on the HP line)
	# the shield glyph. If two vocabularies shared a mark the row would be unreadable.
	for glyph in [StatusVisuals.GLYPH_DOT, StatusVisuals.GLYPH_HOT, StatusVisuals.GLYPH_GUARD,
			StatusVisuals.GLYPH_BUFF, StatusVisuals.GLYPH_DEBUFF, StatusVisuals.GLYPH_NEUTRAL,
			ShieldVisuals.GLYPH]:
		assert_ne(TerrainVisuals.MARK, String(glyph),
			"the terrain mark is not '%s', which another vocabulary already owns" % glyph)


func test_an_unlisted_stat_is_still_named_rather_than_blank() -> void:
	assert_eq(TerrainVisuals.stat_label("evasion"), "AVO", "the authored abbreviation")
	assert_eq(TerrainVisuals.stat_label("luck"), "LUC",
		"and a stat nobody abbreviated is still legible, never an empty chip")
	assert_eq(TerrainVisuals.stat_label(""), "", "an empty stat name has no word")


func test_a_third_terrain_layer_collapses_into_the_shared_overflow_marker() -> void:
	assert_eq(TerrainVisuals.MAX_CHIPS, 2, "two terrain chips is the budget")
	assert_eq(TerrainVisuals.shown_count(2), 2, "two fit")
	assert_eq(TerrainVisuals.hidden_count(2), 0, "with nothing left over")
	assert_eq(TerrainVisuals.shown_count(4), 1,
		"past the budget the last slot becomes the marker, exactly as statuses do")
	assert_eq(TerrainVisuals.hidden_count(4), 3, "which stands for the other three")
	assert_eq(TerrainVisuals.overflow_label(3), "+3", "using the shared wording")


# --- Local doubles ------------------------------------------------------------
#
# `get_element` is a method the production code BRANCHES on, so it stays out of the shared
# doubles (tests/README.md rule 5, and the warning at the top of test_doubles.gd): bolting
# it onto one would silently reroute every suite that uses that double.

## The smallest thing that carries an element and can stand on a cell.
class _ElementUnit:
	var element: StringName
	var team: int = 1

	func _init(p_element: StringName) -> void:
		element = p_element

	func get_element() -> StringName:
		return element

	func get_stat(stat_name: String) -> int:
		return 0 if stat_name != "health" else 100

	func get_hp() -> int:
		return 100

	func take_damage(_amount: int) -> void:
		pass
