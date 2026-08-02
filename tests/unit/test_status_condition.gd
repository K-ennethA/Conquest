extends GutTest

# Tests for multi-turn status conditions built on the effect pipeline:
# StatusCondition (tick_effects + duration + stacking), StatusController
# (tick_all / expiry / stacking), and ApplyStatusEffect via MoveExecutor.
# Mock style mirrors test_move_system.gd.

# --- Mocks -----------------------------------------------------------------
# StatusSinkUnit answers add_status directly, which is ApplyStatusEffect's first
# branch -- so statuses land without a live StatusController Node.
const Doubles := preload("res://tests/helpers/test_doubles.gd")

# --- Fixtures --------------------------------------------------------------

func _burn(duration: int) -> StatusCondition:
	var c := StatusCondition.new()
	c.id = &"burn"
	c.display_name = "Burn"
	c.duration_turns = duration
	c.stacking = StatusCondition.Stacking.REFRESH
	var dmg := DamageEffect.new()
	dmg.power = 10
	dmg.scaling_stat = ""      # flat, no caster scaling
	dmg.category = CombatTypes.DamageCategory.TRUE  # ignore defense for clean math
	c.tick_effects = [dmg]
	return c

func _regen(duration: int) -> StatusCondition:
	var c := StatusCondition.new()
	c.id = &"regen"
	c.display_name = "Regen"
	c.duration_turns = duration
	var h := HealEffect.new()
	h.amount = 8
	h.scaling_stat = ""
	c.tick_effects = [h]
	return c

func _controller_for(unit) -> StatusController:
	# autofree: StatusController is a Node -- an untracked one is a GUT orphan.
	var sc: StatusController = autofree(StatusController.new())
	sc.owner_unit = unit
	return sc

# --- StatusCondition.tick --------------------------------------------------

func test_burn_tick_deals_damage_to_self():
	var unit := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	var board := Doubles.CombatBoard.new()
	board.place(unit, Vector2i(2, 2))
	_burn(3).tick(unit, board)
	assert_eq(unit.hp, 90, "single burn tick deals 10 true damage")

func test_regen_tick_heals_self():
	var unit := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	unit.hp = 50
	var board := Doubles.CombatBoard.new()
	board.place(unit, Vector2i(0, 0))
	_regen(2).tick(unit, board)
	assert_eq(unit.hp, 58, "single regen tick heals 8")

# --- StatusController lifecycle --------------------------------------------

func test_burn_ticks_n_turns_then_expires():
	var unit := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	var board := Doubles.CombatBoard.new()
	board.place(unit, Vector2i(1, 1))
	var sc := _controller_for(unit)
	sc.add_status(_burn(3))
	sc.tick_all(board)   # 100 -> 90, 2 turns left
	sc.tick_all(board)   # 90 -> 80, 1 turn left
	assert_eq(sc.get_active().size(), 1, "still active after 2 of 3 ticks")
	sc.tick_all(board)   # 80 -> 70, expires
	assert_eq(unit.hp, 70, "burn dealt damage across exactly 3 ticks")
	assert_eq(sc.get_active().size(), 0, "burn expired after 3 turns")
	sc.tick_all(board)   # no-op
	assert_eq(unit.hp, 70, "no damage after expiry")

func test_permanent_condition_never_expires():
	var unit := Doubles.StatusSinkUnit.new(0, { "health": 1000 })
	var board := Doubles.CombatBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sc := _controller_for(unit)
	sc.add_status(_burn(-1))
	for i in range(5):
		sc.tick_all(board)
	assert_eq(sc.get_active().size(), 1, "permanent condition still active after 5 ticks")
	assert_eq(unit.hp, 950, "permanent burn ticked all 5 turns")

func test_stacking_refresh_resets_duration():
	var unit := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	var board := Doubles.CombatBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sc := _controller_for(unit)
	sc.add_status(_burn(3))
	sc.tick_all(board)              # 2 turns left
	sc.tick_all(board)              # 1 turn left
	sc.add_status(_burn(3))         # REFRESH -> back to 3, still one instance
	assert_eq(sc.get_active().size(), 1, "refresh does not add a second instance")
	assert_eq(sc.get_active()[0].turns_left, 3, "duration reset to full")

func test_stacking_stack_adds_second_instance():
	var unit := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	var board := Doubles.CombatBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sc := _controller_for(unit)
	var a := _burn(3); a.stacking = StatusCondition.Stacking.STACK
	var b := _burn(3); b.stacking = StatusCondition.Stacking.STACK
	sc.add_status(a)
	sc.add_status(b)
	assert_eq(sc.get_active().size(), 2, "STACK adds an independent second instance")
	sc.tick_all(board)
	assert_eq(unit.hp, 80, "both stacked burns tick (10 + 10)")

func test_stacking_ignore_keeps_original():
	var unit := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	var board := Doubles.CombatBoard.new()
	board.place(unit, Vector2i(0, 0))
	var sc := _controller_for(unit)
	var a := _burn(3); a.stacking = StatusCondition.Stacking.IGNORE
	sc.add_status(a)
	sc.tick_all(board)                                # 2 turns left
	var b := _burn(3); b.stacking = StatusCondition.Stacking.IGNORE
	sc.add_status(b)                                  # ignored
	assert_eq(sc.get_active().size(), 1, "IGNORE drops the new instance")
	assert_eq(sc.get_active()[0].turns_left, 2, "existing duration untouched")

func test_added_condition_is_a_duplicate():
	var unit := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	var sc := _controller_for(unit)
	var template := _burn(3)
	sc.add_status(template)
	assert_ne(sc.get_active()[0], template, "controller stores a duplicate, not the template")
	assert_eq(template.turns_left, 0, "template instance not mutated")

# --- ApplyStatusEffect via MoveExecutor ------------------------------------

func test_apply_status_inflicts_condition_on_enemies():
	var caster := Doubles.StatusSinkUnit.new(0, {})
	var enemy := Doubles.StatusSinkUnit.new(1, { "health": 100 })
	var ally := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))
	board.place(ally, Vector2i(0, 1))

	var move := MoveResource.new()
	move.move_id = &"ignite"
	move.display_name = "Ignite"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 1
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	var apply := ApplyStatusEffect.new()
	apply.condition = _burn(3)
	move.effects = [apply]

	var result := MoveExecutor.execute(move, caster, board, Vector2i(1, 0))
	assert_true(result.success, "ignite resolves")
	assert_eq(enemy.added_statuses.size(), 1, "enemy received the burn condition")
	assert_eq(ally.added_statuses.size(), 0, "ally not affected by an ENEMY-targeted status move")
	assert_eq((enemy.added_statuses[0] as StatusCondition).id, &"burn", "correct condition id inflicted")

func test_apply_status_gives_each_target_independent_duplicate():
	var caster := Doubles.StatusSinkUnit.new(0, {})
	var enemy_a := Doubles.StatusSinkUnit.new(1, { "health": 100 })
	var enemy_b := Doubles.StatusSinkUnit.new(1, { "health": 100 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy_a, Vector2i(2, 0))
	board.place(enemy_b, Vector2i(2, 1))

	var move := MoveResource.new()
	move.move_id = &"spread_burn"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 3
	pattern.area_shape = CombatTypes.AreaShape.DIAMOND
	pattern.area_size = 1
	move.targeting = pattern
	var apply := ApplyStatusEffect.new()
	apply.condition = _burn(3)
	move.effects = [apply]

	MoveExecutor.execute(move, caster, board, Vector2i(2, 0))
	assert_eq(enemy_a.added_statuses.size(), 1, "enemy A got a condition")
	assert_eq(enemy_b.added_statuses.size(), 1, "enemy B got a condition")
	assert_ne(enemy_a.added_statuses[0], enemy_b.added_statuses[0], "each target gets its own duplicate")
