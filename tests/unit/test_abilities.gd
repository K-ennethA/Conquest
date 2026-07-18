extends GutTest

# Tests for the data-driven abilities system built on the shared effect pipeline:
# AbilityCondition concretes (gating), AbilityResource (self-targeted effects),
# and AbilitySystem (event triggers + merged passive rule modifiers). Mock style
# mirrors test_move_system.gd / test_status_condition.gd — no scene tree required.

# --- Mocks -----------------------------------------------------------------

class MockUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var modifiers: Array = []
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = stats.get("health", 100)
	func get_stat(name: String) -> int:
		return stats.get(name, 0)
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp += n
	func add_stat_modifier(stat: String, amount: int, duration: int) -> int:
		modifiers.append({ "stat": stat, "amount": amount, "duration": duration })
		return modifiers.size()

class MockBoard:
	var placements: Array = []       # { unit, cell }
	var tiles: Dictionary = {}
	var tags: Dictionary = {}        # cell -> terrain tag (StringName)
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)
	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team
	func set_tile(cell: Vector2i, tile_id) -> void:
		tiles[cell] = tile_id
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	# Duck-typed terrain accessor read by OnTerrainCondition.
	func tag_tile(cell: Vector2i, tag: StringName) -> void:
		tags[cell] = tag
	func tile_tag_at(cell: Vector2i) -> StringName:
		return tags.get(cell, &"")

# A board exposing cell_of but no terrain accessor, to prove OnTerrainCondition
# degrades gracefully (fails closed) rather than erroring.
class _NoTerrainBoard:
	func cell_of(_unit) -> Vector2i:
		return Vector2i.ZERO

# --- Helpers ---------------------------------------------------------------

func _system_for(unit) -> AbilitySystem:
	var sys := AbilitySystem.new()
	sys.owner_unit = unit
	return autofree(sys)

# --- Conditions ------------------------------------------------------------

func test_on_terrain_met_only_on_tagged_tile():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(2, 2))
	board.tag_tile(Vector2i(2, 2), &"water")
	var cond := OnTerrainCondition.new()
	cond.terrain_id = &"water"
	assert_true(cond.is_met(unit, board), "met while standing on the water tile")
	board.move_unit(unit, Vector2i(5, 5))   # untagged tile
	assert_false(cond.is_met(unit, board), "not met once off the water tile")

func test_on_terrain_degrades_when_board_lacks_accessor():
	var unit := MockUnit.new(0, { "health": 100 })
	# A bare object with only cell_of and no terrain accessor -> fail closed.
	var stub := _NoTerrainBoard.new()
	var cond := OnTerrainCondition.new()
	cond.terrain_id = &"water"
	assert_false(cond.is_met(unit, stub), "no tile accessor -> condition fails closed, no error")

func test_health_below_gates_at_threshold():
	var board := MockBoard.new()
	var cond := HealthBelowCondition.new()
	cond.threshold = 0.3
	var wounded := MockUnit.new(0, { "health": 100 })
	wounded.hp = 25                          # 25% < 30%
	board.place(wounded, Vector2i(0, 0))
	assert_true(cond.is_met(wounded, board), "met at 25% of max health")
	var healthy := MockUnit.new(0, { "health": 100 })
	healthy.hp = 40                          # 40% not < 30%
	board.place(healthy, Vector2i(1, 0))
	assert_false(cond.is_met(healthy, board), "not met at 40% of max health")

func test_null_condition_is_always_met():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	var a := AbilityResource.new()
	a.condition = null
	assert_true(a.is_condition_met(unit, board), "a null condition never blocks the ability")

# --- Rule modifiers / passive accessors ------------------------------------

func test_blitz_reports_extra_action():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sys := _system_for(unit)
	sys.add_ability(AbilityLibrary.blitz())
	assert_eq(sys.extra_actions(unit, board), 1, "blitz grants exactly one extra action")
	assert_eq(sys.extra_movement(unit, board), 0, "blitz does not touch movement")

func test_passive_modifiers_merge_and_exclude_unmet():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(3, 3))
	board.tag_tile(Vector2i(3, 3), &"water")
	var sys := _system_for(unit)
	sys.add_ability(AbilityLibrary.blitz())       # +1 action, unconditional
	sys.add_ability(AbilityLibrary.amphibious())  # +2 movement, only on water
	# On water: both passives are in force and merge.
	var on_water := sys.passive_modifiers(unit, board)
	assert_eq(int(on_water.get("extra_actions", 0)), 1, "blitz contributes extra_actions")
	assert_eq(int(on_water.get("extra_movement", 0)), 2, "amphibious contributes extra_movement on water")
	# Off water: amphibious drops out, blitz remains.
	board.move_unit(unit, Vector2i(9, 9))
	var off_water := sys.passive_modifiers(unit, board)
	assert_eq(int(off_water.get("extra_actions", 0)), 1, "blitz still applies off water")
	assert_false(off_water.has("extra_movement"), "amphibious excluded when its condition is unmet")

func test_extra_actions_sum_across_passives():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sys := _system_for(unit)
	sys.add_ability(AbilityLibrary.blitz())
	var extra := AbilityLibrary.blitz()           # second +1 action passive
	extra.id = &"blitz_two"
	sys.add_ability(extra)
	assert_eq(sys.extra_actions(unit, board), 2, "integer rule modifiers sum across abilities")

# --- Triggered abilities ---------------------------------------------------

func test_vampiric_on_kill_heals_self():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 60
	var board := MockBoard.new()
	board.place(unit, Vector2i(4, 4))             # must be on the board so the self-effect finds it
	var sys := _system_for(unit)
	sys.add_ability(AbilityLibrary.vampiric())
	var events := sys.trigger(AbilityTrigger.Trigger.ON_KILL, unit, board)
	assert_eq(unit.hp, 75, "vampiric restores 15 health on kill")
	assert_eq(events.size(), 1, "one heal event logged")
	assert_eq(events[0].get("effect"), "heal", "the logged event is a heal")

func test_trigger_only_fires_matching_event():
	var unit := MockUnit.new(0, { "health": 100 })
	unit.hp = 60
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sys := _system_for(unit)
	sys.add_ability(AbilityLibrary.vampiric())    # ON_KILL only
	var events := sys.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(events.size(), 0, "ON_KILL ability does not fire on ON_TURN_START")
	assert_eq(unit.hp, 60, "no healing on a non-matching event")

func test_last_stand_effect_fires_only_while_wounded():
	var unit := MockUnit.new(0, { "health": 100 })
	var board := MockBoard.new()
	board.place(unit, Vector2i(2, 2))
	var sys := _system_for(unit)
	sys.add_ability(AbilityLibrary.last_stand())  # PASSIVE + HealthBelow 30%
	# Healthy: passive effect should not fire.
	unit.hp = 80
	sys.trigger(AbilityTrigger.Trigger.PASSIVE, unit, board)
	assert_eq(unit.modifiers.size(), 0, "last stand dormant while healthy")
	# Wounded: passive effect applies the defense buff.
	unit.hp = 20
	sys.trigger(AbilityTrigger.Trigger.PASSIVE, unit, board)
	assert_eq(unit.modifiers.size(), 1, "last stand buffs defense once wounded")
	assert_eq(unit.modifiers[0]["stat"], "defense", "buff targets defense")
	assert_eq(unit.modifiers[0]["amount"], 5, "buff is +5 defense")
