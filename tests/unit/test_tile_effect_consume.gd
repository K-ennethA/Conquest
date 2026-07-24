extends GutTest

## Covers the single-use tile-effect flag (consume_on_trigger) added so a Vine Trap
## springs ONCE and is extinguished, while lasting fields (tall grass, and map terrain
## like lava) persist. The live spring->remove path runs through TileEffectSystem +
## CombatServices in-game; here we lock the authored data + the regression-safe default.

func test_vine_trap_is_single_use():
	var vt: TileEffectResource = load("res://game/tiles/effects/resources/vine_trap.tres")
	assert_not_null(vt, "vine_trap.tres loads")
	if vt != null:
		assert_true(vt.consume_on_trigger, "Vine Trap is spent the moment it springs on a unit")

func test_tile_effects_persist_by_default():
	var te := TileEffectResource.new()
	assert_false(te.consume_on_trigger,
		"a fresh tile effect PERSISTS unless authored single-use (lava/burn fields stay)")

func test_tall_grass_is_a_lasting_field_not_a_one_shot():
	var tg: TileEffectResource = load("res://game/tiles/effects/resources/tall_grass.tres")
	assert_not_null(tg, "tall_grass.tres loads")
	if tg != null:
		assert_false(tg.consume_on_trigger, "tall grass keeps granting evasion, it is not consumed")
