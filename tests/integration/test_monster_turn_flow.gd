extends GutTest

# DUSKMAW's kit, on the CLOCK -- the half of the character that is about WHEN.
#
#   * Abyssal Maw erupts at the start of the CASTER's next turn, in BOTH turn systems,
#     and NOT on the turn that happens in between.
#   * Voidwalk's immunity lasts exactly one turn and then lets go.
#   * Shadow Dash leaves the caster under CANTO -- it has acted, but still owes ONE
#     MOVEMENT -- and BOTH turn systems must hold the turn open for that step, then
#     close it the moment the step (or a Wait) is taken.
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

const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose: a `: RefCounted` annotation makes the static analyser reject
## _guard.set_setting() as "not found in base RefCounted" (tests/README rule 3).
var _guard


func before_each() -> void:
	_guard = Guard.new()
	# Traditional's auto-end is a SETTING, and the canto tests assert both halves of it
	# (held open during the canto, fired the moment it is spent). Pin it so another suite
	# cannot decide the outcome.
	_guard.set_setting("auto_end_turn", true)


func after_each() -> void:
	_guard.restore()


## A live [Unit] with a [StatusController], built the way test_eldroot.gd builds one.
## [param speed] is a parameter because Speed First orders its queue by it and the canto
## tests need a KNOWN first actor; it must be set on the resource BEFORE the unit enters
## the tree, since that is when UnitStats reads the block.
func _real_unit(display_name: String, speed: int = 8) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = display_name
	res.unit_type = "warrior"
	res.max_health = 200
	res.base_speed = speed
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
# SHADOW DASH -- CANTO: it has acted, and still owes ONE movement
# ===========================================================================
#
# THE SHIPPED BUG THIS SECTION EXISTS FOR. The first build expressed "move again after
# dashing" as the Arena's arena_extra_actions budget, because movement-only "was not
# expressible". Two things were wrong with that, and only the second was visible:
#   * it granted a FULL action, so Duskmaw could strike twice; and
#   * NEITHER turn system understood the grant. Traditional appended the unit to
#     units_acted_this_turn the instant the dash resolved (so can_unit_act went false,
#     the movement range went dark, and the click on a reachable cell was refused --
#     the reported "could not move to a spot"), while Speed First simply advanced its
#     queue and retired the unit outright.
# Canto is therefore state the UNIT owns and BOTH turn systems ASK about.


## The live sequence a dash produces, with no board required: the move's effects resolve
## INSIDE perform_move (Void Surge lands, arming canto) and the CALLER marks the action
## complete afterwards -- exactly what UnitActionsPanel, CommandApplier and BotTurnDriver
## all do. Getting this order right is the whole reason grant_canto only ARMS.
func _resolve_dash(unit: Unit) -> void:
	unit.get_status_controller().add_status(_void_surge())
	unit.mark_action_completed("move")


func test_the_dash_leaves_the_unit_able_to_MOVE_but_never_to_act_again():
	var unit := _real_unit("Duskmaw")
	var board := TeamBoard.new()
	board.place(unit, Vector2i(0, 0), 0)
	unit.reset_turn_actions()
	unit.mark_moved()   # it walked before dashing, the ordinary FE opening

	_resolve_dash(unit)

	assert_true(unit.has_canto(), "the dash leaves it under canto")
	assert_false(unit.can_act(),
		"and it may NOT act again -- no second dash, no attack, no move at all")
	assert_true(unit.can_move(),
		"but it may still MOVE, even though it had already used its walk this turn")


func test_the_canto_movement_is_exactly_one_and_it_closes_the_turn():
	var unit := _real_unit("Duskmaw")
	unit.reset_turn_actions()
	_resolve_dash(unit)

	# GUT lambdas capture BY VALUE, so the announcement is collected through a shared Array.
	var closed: Array = []
	unit.unit_action_completed.connect(func(_u, action) -> void: closed.append(action))

	unit.mark_moved()

	assert_eq(closed, ["canto_move"],
		"taking the owed step announces the unit done -- that is what ends its turn")
	assert_false(unit.has_canto(), "the canto is spent")
	assert_false(unit.can_move(), "there is no second free step")
	assert_true(unit.has_acted_this_turn, "and the unit is latched done for the turn")


func test_waiting_instead_forfeits_the_canto_and_still_ends_the_turn():
	var unit := _real_unit("Duskmaw")
	unit.reset_turn_actions()
	_resolve_dash(unit)

	var closed: Array = []
	unit.unit_action_completed.connect(func(_u, action) -> void: closed.append(action))

	unit.finish_canto("wait")

	assert_eq(closed, ["wait"], "Wait closes the turn just as the step does")
	assert_false(unit.has_canto(), "with the owed movement given up")
	unit.finish_canto("wait")
	assert_eq(closed, ["wait"], "and finish_canto is idempotent -- never a second announcement")


func test_any_further_completed_action_forfeits_an_armed_canto():
	# The networked WAIT_UNIT command lands as a plain mark_action_completed, so this is
	# what lets a canto turn be closed from the command layer with no special case there.
	var unit := _real_unit("Duskmaw")
	unit.reset_turn_actions()
	_resolve_dash(unit)
	assert_true(unit.has_canto(), "armed by the dash")

	unit.mark_action_completed("wait")

	assert_false(unit.has_canto(), "a later completed action gives the movement up")
	assert_false(unit.can_move(), "so nothing is owed and the unit is done")


func test_the_canto_move_is_taken_on_a_stride_two_cells_shorter():
	var unit := _real_unit("Duskmaw")
	var base_movement: int = unit.get_stat("movement")
	unit.reset_turn_actions()
	_resolve_dash(unit)

	assert_eq(unit.get_stat("movement"), base_movement - 2,
		"the free step is PAID FOR: Void Surge shortens the stride by exactly 2")
	assert_true(unit.has_canto(), "and the two halves arrive together, never one without the other")


# --- Both turn systems hold the turn open for it ----------------------------

func test_traditional_holds_the_players_turn_open_for_the_canto_then_auto_ends():
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var mine := _real_unit("Duskmaw")
	var theirs := _real_unit("Target")
	var my_player := _register(ts, mine, 0)
	_register(ts, theirs, 1)
	ts.start_turn_system()
	assert_eq(ts.get_current_active_player(), my_player, "the turn opens on our side")

	_resolve_dash(mine)

	assert_true(ts.can_unit_act(mine),
		"REGRESSION: a unit that still owes its canto movement is NOT 'already acted'")
	assert_true(mine in ts.get_units_that_can_act(),
		"so it is still one of the units the player has left to command")
	await get_tree().process_frame
	assert_eq(ts.get_current_active_player(), my_player,
		"and the all-acted sweep must NOT auto-end the player turn on top of it")

	mine.mark_moved()   # the canto step

	assert_false(ts.can_unit_act(mine), "with the step taken it is genuinely done")
	await get_tree().process_frame
	assert_ne(ts.get_current_active_player(), my_player,
		"and NOW the auto-end fires, exactly once, at the right moment")


func test_speed_first_holds_the_queue_open_for_the_canto():
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	var fast := _real_unit("Duskmaw", 20)
	var slow := _real_unit("Target", 1)
	_register(ts, fast, 0)
	_register(ts, slow, 1)
	ts.start_turn_system()
	assert_eq(ts.get_current_acting_unit(), fast, "the faster unit acts first")

	_resolve_dash(fast)

	assert_eq(ts.get_current_acting_unit(), fast,
		"REGRESSION: the queue advanced the instant the dash resolved, retiring the unit " +
		"before it could take the movement it was owed")
	assert_true(ts.can_unit_act(fast), "its turn is still open")

	fast.mark_moved()   # the canto step

	assert_eq(ts.get_current_acting_unit(), slow,
		"taking the step hands the queue on, exactly as any completed action does")


func test_speed_first_hands_the_queue_on_when_the_canto_is_waited_out():
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	var fast := _real_unit("Duskmaw", 20)
	var slow := _real_unit("Target", 1)
	_register(ts, fast, 0)
	_register(ts, slow, 1)
	ts.start_turn_system()

	_resolve_dash(fast)
	fast.finish_canto("wait")

	assert_eq(ts.get_current_acting_unit(), slow,
		"a unit that gives its canto up does not hold the queue hostage")


func test_the_canto_never_survives_into_the_next_turn():
	# The anti-lockout shape every per-turn grant here follows: the flag is turn-scoped
	# state on the unit, so even a dispel, a save/load or a dropped signal cannot leak a
	# free step into a later turn.
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Duskmaw")
	_register(ts, unit, 0)
	ts.start_turn_system()

	_resolve_dash(unit)
	assert_true(unit.has_canto(), "owed this turn")

	ts.reset_all_unit_actions()   # what every turn start runs

	assert_false(unit.has_canto(), "and gone at the next turn boundary")
	assert_true(unit.can_act(), "the unit starts its next turn whole")


# --- The command seam -------------------------------------------------------

func test_the_command_layer_accepts_the_canto_move_as_an_ordinary_MOVE_UNIT():
	# Networked play and replays carry the canto step as a plain MOVE_UNIT -- there is no
	# canto command. What has to be true is that the applier's move path (which asks the
	# unit nothing about its acted state) still lands it AND still closes the turn.
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Duskmaw")
	var player := _register(ts, unit, 0)
	_register(ts, _real_unit("Target"), 1)
	ts.start_turn_system()

	var board := TeamBoard.new()
	board.place(unit, Vector2i(0, 0), 0)

	_resolve_dash(unit)
	assert_true(ts.can_unit_act(unit), "the seam is asked while the canto is still owed")

	var registry := CommandApplier.UnitRegistry.new()
	registry.register(unit, 1)
	var applier := CommandApplier.new(registry)
	var cmd: Dictionary = NetProtocol.stamp_resolution(
		NetProtocol.make_move_unit(1, Vector2i(2, 0)), 1, 0)
	var res: Dictionary = applier.apply_command(cmd, board)

	assert_true(bool(res.get("ok", false)),
		"the applier accepts the move: %s" % str(res.get("reason", "")))
	assert_eq(board.cell_of(unit), Vector2i(2, 0), "and the unit is standing on the destination")
	assert_false(unit.has_canto(), "the applier's mark_moved() spent the canto")
	assert_false(ts.can_unit_act(unit), "so the turn closed through the ordinary path")
	assert_eq(ts.get_current_active_player(), player,
		"(the deferred auto-end has not run yet -- this asserts the seam, not the advance)")


# --- The stride comes back at the next turn start ---------------------------

func test_the_void_surge_hands_the_stride_back_at_the_next_turn_start():
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Duskmaw")
	_register(ts, unit, 0)
	var board := TeamBoard.new()
	board.place(unit, Vector2i(0, 0), 0)
	ts.is_active = true
	ts.is_turn_in_progress = true

	var base_movement: int = unit.get_stat("movement")
	unit.get_status_controller().add_status(_void_surge())
	assert_eq(unit.get_stat("movement"), base_movement - 2,
		"the free step is paid for with a shortened stride")

	ts.current_turn += 1
	_open_turn_for(ts, unit, board)

	assert_false(unit.get_status_controller().has_status(&"void_surge"),
		"one turn only")
	assert_eq(unit.get_stat("movement"), base_movement, "and the stride comes back with it")
