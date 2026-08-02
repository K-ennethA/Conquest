extends GutTest

# Tests for the data-driven tile-effects system: triggers, faction/tag filters,
# passive rule-flag merging, and the shared effect pipeline. Uses the shared
# doubles (no scene tree / live board), mirroring test_move_system.gd.

# --- Mocks -----------------------------------------------------------------
# TaggedCombatUnit carries the unit tags TileEffectResource filters on; TileEffectBoard
# adds tile_effects_at + perspective_unit. See tests/helpers/test_doubles.gd.
const Doubles := preload("res://tests/helpers/test_doubles.gd")

# --- Triggers: fire burns on turn start ------------------------------------

func test_fire_damages_occupant_on_turn_start():
	var unit := Doubles.TaggedCombatUnit.new(1, { "health": 100, "defense": 50 })
	var board := Doubles.TileEffectBoard.new()
	board.place(unit, Vector2i(2, 2))
	board.set_tile_effects(Vector2i(2, 2), [TileEffectLibrary.fire()])
	var system = autofree(TileEffectSystem.new())
	var events: Array = system.on_turn_start(unit, board)
	assert_eq(unit.hp, 85, "fire deals 15 true damage (ignores the 50 defense)")
	assert_eq(events.size(), 1, "one damage event logged")
	assert_eq(events[0]["effect"], "damage", "event is a damage event")

func test_fire_does_not_fire_on_enter():
	# fire's trigger is ON_TURN_START_WHILE_OCCUPYING, so entering must not burn.
	var unit := Doubles.TaggedCombatUnit.new(1, { "health": 100 })
	var board := Doubles.TileEffectBoard.new()
	board.place(unit, Vector2i(0, 0))
	board.set_tile_effects(Vector2i(0, 0), [TileEffectLibrary.fire()])
	var system = autofree(TileEffectSystem.new())
	var events: Array = system.on_enter(unit, Vector2i(0, 0), board)
	assert_eq(unit.hp, 100, "entering a fire tile does not burn (wrong trigger)")
	assert_eq(events.size(), 0, "no events for a non-matching trigger")

# --- Required unit tag: empowering water -----------------------------------

func test_empowering_water_affects_aquatic_unit():
	var aquatic := Doubles.TaggedCombatUnit.new(0, { "attack": 10 }, ["aquatic"])
	var board := Doubles.TileEffectBoard.new()
	board.place(aquatic, Vector2i(1, 1))
	var water := TileEffectLibrary.empowering_water()
	assert_true(water.applies_to(aquatic, board), "aquatic unit matches required tag")
	water.run(aquatic, board)
	assert_eq(aquatic.modifiers.size(), 1, "aquatic occupant receives the buff")
	assert_eq(aquatic.modifiers[0]["stat"], "attack", "buff targets attack")
	assert_eq(aquatic.modifiers[0]["amount"], 4, "buff is +4")

func test_empowering_water_ignores_non_aquatic_unit():
	var lander := Doubles.TaggedCombatUnit.new(0, { "attack": 10 }, ["infantry"])
	var board := Doubles.TileEffectBoard.new()
	board.place(lander, Vector2i(1, 1))
	var water := TileEffectLibrary.empowering_water()
	assert_false(water.applies_to(lander, board), "unit without the aquatic tag is filtered out")

func test_untagged_unit_not_empowered_via_system():
	# A unit that reports no tags at all must be unaffected by a tag-gated effect.
	var untagged := Doubles.TaggedCombatUnit.new(0, { "attack": 10 })
	var board := Doubles.TileEffectBoard.new()
	board.place(untagged, Vector2i(4, 4))
	board.set_tile_effects(Vector2i(4, 4), [TileEffectLibrary.empowering_water()])
	var system = autofree(TileEffectSystem.new())
	var untagged_flags: Dictionary = system.passive_flags(untagged, board)
	assert_true(untagged_flags.is_empty(), "no passive flags for a filtered-out unit")
	# empowering_water carries no rule_flags, but applies_to must also gate its buff:
	assert_false(TileEffectLibrary.empowering_water().applies_to(untagged, board),
		"untagged unit does not match the required tag")

# --- Passive rule flags: stealth + merge -----------------------------------

func test_stealth_reports_untargetable_flag():
	var unit := Doubles.TaggedCombatUnit.new(0, {})
	var board := Doubles.TileEffectBoard.new()
	board.place(unit, Vector2i(3, 3))
	board.set_tile_effects(Vector2i(3, 3), [TileEffectLibrary.stealth()])
	var system = autofree(TileEffectSystem.new())
	var flags: Dictionary = system.passive_flags(unit, board)
	assert_true(flags.get("untargetable", false), "stealth tile marks occupant untargetable")

func test_passive_flags_merge_across_effects():
	var unit := Doubles.TaggedCombatUnit.new(0, {})
	var board := Doubles.TileEffectBoard.new()
	board.place(unit, Vector2i(5, 5))
	board.set_tile_effects(Vector2i(5, 5), [TileEffectLibrary.stealth(), TileEffectLibrary.fortify()])
	var system = autofree(TileEffectSystem.new())
	var flags: Dictionary = system.passive_flags(unit, board)
	assert_true(flags.get("untargetable", false), "stealth flag present")
	assert_true(flags.get("fortified", false), "fortify flag merged in")
	assert_eq(flags.size(), 2, "both passive flags reported")

# --- Faction filter --------------------------------------------------------

func test_affected_factions_enemies_only():
	# A hazard that only harms occupants hostile to the tile's perspective side.
	var reference := Doubles.TaggedCombatUnit.new(0, {})   # perspective: team 0
	var enemy := Doubles.TaggedCombatUnit.new(1, { "health": 100 })
	var ally := Doubles.TaggedCombatUnit.new(0, { "health": 100 })
	var board := Doubles.TileEffectBoard.new()
	board.perspective = reference
	board.place(enemy, Vector2i(6, 0))
	board.place(ally, Vector2i(7, 0))

	var hazard := TileEffectResource.new()
	hazard.id = &"enemy_hazard"
	hazard.trigger = TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING
	hazard.affected_factions = TileEffectResource.AffectedFactions.OCCUPANT_ENEMIES
	var dmg := DamageEffect.new()
	dmg.power = 10
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	var fx: Array[MoveEffect] = [dmg]
	hazard.effects = fx

	board.set_tile_effects(Vector2i(6, 0), [hazard])
	board.set_tile_effects(Vector2i(7, 0), [hazard])
	var system = autofree(TileEffectSystem.new())

	system.on_turn_start(enemy, board)
	system.on_turn_start(ally, board)
	assert_eq(enemy.hp, 90, "enemy occupant is harmed")
	assert_eq(ally.hp, 100, "allied occupant is spared by the faction filter")

# --- Injected lookup fallback ----------------------------------------------

func test_injected_tile_effects_lookup():
	# When the board exposes no effects for a cell, the system uses its own map.
	var unit := Doubles.TaggedCombatUnit.new(1, { "health": 100 })
	var board := Doubles.TileEffectBoard.new()
	board.place(unit, Vector2i(9, 9))
	var system = autofree(TileEffectSystem.new())
	system.tile_effects[Vector2i(9, 9)] = [TileEffectLibrary.fire()]
	system.on_turn_start(unit, board)
	assert_eq(unit.hp, 85, "injected fire effect burns for 15")
