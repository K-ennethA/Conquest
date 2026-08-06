extends GutTest

# Monster's kit, on the CLOCK -- the half of the character that is about WHEN.
#
#   * Abyssal Maw erupts at the start of the CASTER's next turn, in BOTH turn systems,
#     and NOT on the turn that happens in between.
#   * Voidwalk's immunity lasts exactly one turn and then lets go.
#   * Shadow Dash's Void Surge hands its extra action and its movement penalty back at
#     the same boundary.
#
# All three ride [method TurnSystemBase._tick_unit_turn_start] -- the ONE per-unit
# turn-start hook both turn systems drive (Speed First for the single unit whose turn
# opened, Traditional for every unit of the side that just became active). That is what
# makes "the caster's next turn" mean the same thing in either system, and it is the
# ACTIVE turn system's own signal path rather than PlayerManager's (CONQUEST.md rule 2).
#
# Real Units, real Players and real turn systems, because that machinery IS what is under
# test; the BOARD stays a mock, since none of this needs a loaded map.

# --- A board the real Units can stand on ------------------------------------

## Placement + explicit allegiance. Real Units answer get_owner_player(), but assigning
## Players to sides is beside the point here, so teams are stated directly.
class TeamBoard:
	extends RefCounted
	var placements: Array = []
	var teams: Dictionary = {}
	func place(unit, cell: Vector2i, team: int) -> void:
		placements.append({ "unit": unit, "cell": cell })
		teams[unit] = team
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
		return int(teams.get(a, -1)) != int(teams.get(b, -2))
	func are_allies(a, b) -> bool:
		return int(teams.get(a, -1)) == int(teams.get(b, -2))
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell


# --- Fixtures ---------------------------------------------------------------

## A live [Unit] with a [StatusController], built the way test_eldroot.gd builds one.
func _real_unit(display_name: String) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = display_name
	res.unit_type = "warrior"
	res.max_health = 200
	res.base_speed = 8
	res.movement_range = 3
	u.stats_resource = res
	add_child_autofree(u)
	var controller := StatusController.new()
	controller.name = "StatusController"
	controller.owner_unit = u
	u.add_child(controller)
	return u


## A player owning one real Unit, both registered with [param ts].
func _register(ts: TurnSystemBase, unit: Unit, player_id: int) -> Player:
	var player := Player.new(player_id, "Test Player %d" % player_id)
	player.add_unit(unit)
	ts.register_player(player)
	return player


## Open [param unit]'s turn exactly as a live turn system does.
##
## _tick_unit_turn_start() only runs the status tick when CombatServices.board() is
## non-null, and a headless test has no live board -- so the tick is driven here with the
## mock board instead. The ORDER under test (the turn opens, then statuses tick and
## expire) is unchanged; only where the board comes from differs. Mirrors
## test_eldroot.gd's _open_turn_for.
func _open_turn_for(ts: TurnSystemBase, unit: Unit, board) -> void:
	ts._tick_unit_turn_start(unit)
	var controller = unit.get_status_controller()
	if controller != null:
		controller.tick_all(board)


func _abyssal_maw() -> MoveResource:
	return load("res://game/combat/moves/abyssal_maw.tres") as MoveResource


func _submerged() -> StatusCondition:
	return load("res://game/combat/status/submerged.tres") as StatusCondition


func _void_surge() -> StatusCondition:
	return load("res://game/combat/status/void_surge.tres") as StatusCondition


## Cast Abyssal Maw from [param caster] at [param aim] against [param board].
func _cast_maw(caster, board, aim: Vector2i) -> void:
	var move := _abyssal_maw()
	var origin: Vector2i = board.cell_of(caster)
	var cells := move.targeting.resolve_cells(origin, aim)
	var ctx := MoveContext.new(caster, board, move, aim, cells)
	for effect in move.effects:
		effect.apply(ctx)


# ===========================================================================
# ABYSSAL MAW -- erupts at the CASTER's next turn, in both turn systems
# ===========================================================================

func test_the_maw_waits_through_the_enemy_turn_and_erupts_on_the_casters_next_turn():
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var caster := _real_unit("Monster")
	var victim := _real_unit("Target")
	_register(ts, caster, 0)
	_register(ts, victim, 1)
	var board := TeamBoard.new()
	board.place(caster, Vector2i(0, 0), 0)
	board.place(victim, Vector2i(4, 0), 1)
	ts.is_active = true
	ts.is_turn_in_progress = true

	var before: int = victim.get_hp()
	_cast_maw(caster, board, Vector2i(4, 0))
	assert_true(caster.get_status_controller().has_status(&"void_maw_fuse"),
		"the cast arms a fuse on the caster")
	assert_eq(victim.get_hp(), before, "and deals nothing on the cast turn")

	# The OTHER side's turn opens. Traditional ticks the units of the side that became
	# active -- not the caster -- so nothing about the maw moves.
	ts.current_turn += 1
	_open_turn_for(ts, victim, board)
	assert_eq(victim.get_hp(), before,
		"the maw does not go off on the enemy's turn")
	assert_true(caster.get_status_controller().has_status(&"void_maw_fuse"),
		"the fuse is still burning")

	# The caster's own next turn opens: the ground opens with it.
	ts.current_turn += 1
	_open_turn_for(ts, caster, board)
	assert_true(victim.get_hp() < before,
		"the maw erupts at the start of the CASTER's next turn")
	assert_false(caster.get_status_controller().has_status(&"void_maw_fuse"),
		"and the fuse is spent")


func test_the_maw_keeps_the_same_schedule_under_speed_first():
	# The whole reason the fuse is a status on the caster rather than a HazardManager tick:
	# a per-unit clock means the two turn systems agree without either knowing about it.
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	var caster := _real_unit("Monster")
	var victim := _real_unit("Target")
	_register(ts, caster, 0)
	_register(ts, victim, 1)
	var board := TeamBoard.new()
	board.place(caster, Vector2i(0, 0), 0)
	board.place(victim, Vector2i(4, 0), 1)
	ts.is_active = true
	ts.is_turn_in_progress = true

	var before: int = victim.get_hp()
	_cast_maw(caster, board, Vector2i(4, 0))

	# An intervening unit takes its turn.
	ts.current_turn += 1
	ts.current_acting_unit = victim
	_open_turn_for(ts, victim, board)
	assert_eq(victim.get_hp(), before, "an intervening unit's turn does not set it off")

	ts.current_turn += 1
	ts.current_acting_unit = caster
	_open_turn_for(ts, caster, board)
	assert_true(victim.get_hp() < before, "the caster's next turn does")


func test_the_maw_erupts_only_once():
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var caster := _real_unit("Monster")
	var victim := _real_unit("Target")
	_register(ts, caster, 0)
	_register(ts, victim, 1)
	var board := TeamBoard.new()
	board.place(caster, Vector2i(0, 0), 0)
	board.place(victim, Vector2i(4, 0), 1)
	ts.is_active = true
	ts.is_turn_in_progress = true

	var before: int = victim.get_hp()
	_cast_maw(caster, board, Vector2i(4, 0))

	ts.current_turn += 1
	_open_turn_for(ts, caster, board)
	var after_burst: int = victim.get_hp()
	assert_true(after_burst < before, "it went off")

	ts.current_turn += 1
	_open_turn_for(ts, caster, board)
	assert_eq(victim.get_hp(), after_burst,
		"a spent maw never bites a second time")


# ===========================================================================
# VOIDWALK -- exactly one turn of immunity
# ===========================================================================

func test_voidwalk_covers_one_turn_and_then_lets_go():
	# The anti-lockout shape every 1-turn status here follows: the tick that opens the
	# unit's next turn is what expires it, so the immunity spans exactly the round trip
	# through the opposing turn and can never become permanent.
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Monster")
	_register(ts, unit, 0)
	var board := TeamBoard.new()
	board.place(unit, Vector2i(0, 0), 0)
	ts.is_active = true
	ts.is_turn_in_progress = true

	unit.get_status_controller().add_status(_submerged())
	assert_true(unit.is_invulnerable(), "submerged: nothing can touch it")
	assert_true(DamageMath.is_invulnerable(unit),
		"and the damage layer agrees, which is what actually stops the hit")

	ts.current_turn += 1
	_open_turn_for(ts, unit, board)
	assert_false(unit.is_invulnerable(),
		"it surfaces at the start of its next turn -- one turn, not forever")


func test_voidwalk_immunity_is_read_by_the_damage_layer_not_just_the_status():
	var unit := _real_unit("Monster")
	var attacker := _real_unit("Aggressor")
	var board := TeamBoard.new()
	board.place(unit, Vector2i(0, 0), 0)
	board.place(attacker, Vector2i(1, 0), 1)

	assert_false(DamageMath.is_invulnerable(unit), "baseline: reachable")
	unit.get_status_controller().add_status(_submerged())
	assert_true(DamageMath.is_invulnerable(unit),
		"the shared invulnerability test -- what the hit, the forecast and the AI all read")
	assert_eq(DamageMath.environment_damage(unit, 99,
		CombatTypes.DamageCategory.MAGICAL, &"dark", board), 0,
		"and the environmental chain honours it too")


# ===========================================================================
# SHADOW DASH -- the Void Surge is handed back on schedule
# ===========================================================================

func test_the_void_surge_returns_the_action_budget_at_the_next_turn_start():
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Monster")
	_register(ts, unit, 0)
	var board := TeamBoard.new()
	board.place(unit, Vector2i(0, 0), 0)
	ts.is_active = true
	ts.is_turn_in_progress = true

	var base_movement: int = unit.get_stat("movement")
	unit.get_status_controller().add_status(_void_surge())

	assert_eq(unit.arena_extra_actions, 1,
		"the surge grants exactly one more action for this turn")
	assert_eq(unit.get_stat("movement"), base_movement - 2,
		"paid for with a shortened stride")

	ts.current_turn += 1
	_open_turn_for(ts, unit, board)

	assert_eq(unit.arena_extra_actions, 0, "the budget is handed back next turn")
	assert_eq(unit.get_stat("movement"), base_movement, "and the stride comes back with it")


func test_the_surge_lets_the_unit_act_a_second_time_and_no_more():
	# The action ECONOMY, through the real Unit: with the budget raised, the first
	# completed action does not latch the unit done -- the second one does.
	var unit := _real_unit("Monster")
	var board := TeamBoard.new()
	board.place(unit, Vector2i(0, 0), 0)
	unit.reset_turn_actions()
	unit.get_status_controller().add_status(_void_surge())

	unit.mark_action_completed("move")
	assert_true(unit.can_act(),
		"the dash itself is the first action, and the surge keeps the unit actable")
	assert_true(unit.can_move(), "with its movement refreshed, so it may reposition")

	unit.mark_action_completed("move")
	assert_false(unit.can_act(), "the second action closes the turn -- it is ONE extra, not many")
