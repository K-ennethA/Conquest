extends GutTest

## STATUS DURATION CLOCKS (CONQUEST.md rule 6a), at the StatusController / UnitStats level.
##
## The bug: every status counted down at the afflicted unit's turn START and expired at 0,
## so a 1-turn debuff a foe inflicted on its own turn was decremented and removed by the
## very tick that opened the victim's next turn -- Ensnared never stopped a move, a 1-turn
## defense-down never covered the victim's turn. The fix gives every live instance one of
## two clocks, resolved from who inflicted it:
##
##   * AFFLICTION (hostile applier or the environment): counts at the END of each of the
##     victim's turns it was in force for; the turn it landed in never counts.
##   * PROTECTIVE (self, ally, nobody): counts at turn START, exactly as before.
##
## Turn boundaries are driven by hand here -- tick_all() = "this unit's turn opens",
## tick_turn_end() = "it closes" -- which is exactly what TurnSystemBase does per unit.
## The live-board, real-turn-system half is tests/integration/test_status_clock_live.gd.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

const ENSNARED_PATH := "res://game/combat/status/ensnared.tres"
const BRACED_PATH := "res://game/combat/status/braced.tres"
const FLINCHED_PATH := "res://game/combat/status/flinched.tres"
const FUSE_PATH := "res://game/combat/status/void_maw_fuse.tres"
const VINE_TRAP_PATH := "res://game/tiles/effects/resources/vine_trap.tres"


## A combat target that states its OWNER -- the only thing the clock rule reads -- and can
## report being mind-controlled. Local on purpose (tests/README rule 5): adding ownership to
## a shared double would change which clock every other suite's statuses resolve to.
class OwnedUnit extends Doubles.CombatUnit:
	var owner_player = null
	var controlled: bool = false
	var clocks: Dictionary = {}

	func _init(p_owner, p_team: int = 0) -> void:
		super(p_team, { "health": 100, "defense": 10 })
		owner_player = p_owner

	func get_owner_player():
		return owner_player

	func is_controlled() -> bool:
		return controlled

	func set_stat_modifier_clock(modifier_id: int, counts_own_turns: bool) -> bool:
		clocks[modifier_id] = counts_own_turns
		return true


## A plain RefCounted stands in for a Player: the rule only compares identities.
class FakeSide:
	extends RefCounted


var _side_a: FakeSide
var _side_b: FakeSide


func before_each() -> void:
	_side_a = FakeSide.new()
	_side_b = FakeSide.new()


func _controller_for(unit) -> StatusController:
	var sc: StatusController = autofree(StatusController.new())
	sc.owner_unit = unit
	return sc


func _board_with(units: Array) -> Doubles.CombatBoard:
	var board := Doubles.CombatBoard.new()
	var col := 0
	for u in units:
		board.place(u, Vector3i(col, 0, 0))
		col += 1
	return board


## A fresh copy of the authored status at [param path], stamped with [param source] the way
## ApplyStatusEffect stamps one.
func _from(path: String, source) -> StatusCondition:
	var s: StatusCondition = (load(path) as StatusCondition).duplicate(true)
	s.set_source(source)
	return s


## An N-turn TRUE-damage tick (poison-shaped, REFRESH) credited to [param source].
func _poison(turns: int, source) -> StatusCondition:
	var c := StatusCondition.new()
	c.id = &"test_poison"
	c.display_name = "Test Poison"
	c.duration_turns = turns
	var dmg := DamageEffect.new()
	dmg.power = 4
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	c.tick_effects = [dmg]
	c.set_source(source)
	return c


# ===========================================================================
# THE RULE
# ===========================================================================

func test_the_auto_rule_reads_the_applier() -> void:
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var ally := OwnedUnit.new(_side_b)
	assert_true(StatusCondition.is_affliction_from(foe, victim), "a foe's debuff is an affliction")
	assert_false(StatusCondition.is_affliction_from(victim, victim), "a self-cast is protective")
	assert_false(StatusCondition.is_affliction_from(ally, victim), "an ally's cast is protective")
	assert_false(StatusCondition.is_affliction_from(null, victim), "nobody (code-built / restored) is protective")
	assert_true(StatusCondition.is_affliction_from(null, victim, true), "the environment is an affliction")
	ally.controlled = true
	assert_true(StatusCondition.is_affliction_from(ally, victim),
		"a mind-controlled ally striking its own side is acting for the enemy")


func test_a_status_resolves_its_clock_as_it_lands() -> void:
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var sc := _controller_for(victim)
	var snare = sc.add_status(_from(ENSNARED_PATH, foe))
	var guard = sc.add_status(_from(BRACED_PATH, victim))
	assert_true(snare.counts_own_turns, "a foe's Ensnared runs on the affliction clock")
	assert_false(guard.counts_own_turns, "a self-cast Braced keeps the protective clock")


func test_an_authored_clock_beats_the_auto_rule() -> void:
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var fuse: StatusCondition = load(FUSE_PATH)
	assert_eq(fuse.clock, StatusCondition.Clock.PROTECTIVE,
		"the Abyssal Maw fuse pins the protective clock -- its contract is the caster's next turn START")
	var pinned := _from(FUSE_PATH, foe)
	assert_false(pinned.resolve_clock(victim), "so even a hostile applier cannot move it onto the turn-end clock")
	var forced := _from(BRACED_PATH, victim)
	forced.clock = StatusCondition.Clock.AFFLICTION
	assert_true(forced.resolve_clock(victim), "and an authored AFFLICTION holds even when self-cast")


# ===========================================================================
# AFFLICTIONS -- in force for the victim's next N own turns
# ===========================================================================

func test_a_foes_one_turn_immobilize_holds_through_the_victims_next_turn() -> void:
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var board := _board_with([victim, foe])
	var sc := _controller_for(victim)

	# The foe's turn: the snare lands.
	sc.add_status(_from(ENSNARED_PATH, foe))
	assert_true(sc.has_rule_flag(&"immobilized"), "snared the moment it lands")

	# The victim's turn OPENS -- the tick that used to expire it.
	sc.tick_all(board)
	assert_true(sc.has_rule_flag(&"immobilized"),
		"THE BUG: still snared for the whole of the victim's next turn")
	assert_eq(sc.get_active()[0].turns_left, 1, "and the UI reads 1 turn -- the one in progress")

	# The victim's turn CLOSES.
	sc.tick_turn_end(board)
	assert_false(sc.has_status(&"ensnared"), "gone once the turn it cost is over")

	# Its next turn is free.
	sc.tick_all(board)
	assert_false(sc.has_rule_flag(&"immobilized"), "and never comes back")


func test_an_affliction_that_lands_mid_turn_takes_the_next_turn_not_this_one() -> void:
	# A trap sprung on the victim's own move, a reactive flinch: the turn in progress is
	# not one of its N.
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var board := _board_with([victim, foe])
	var sc := _controller_for(victim)

	sc.tick_all(board)                      # the victim's turn is open
	sc.add_status(_from(ENSNARED_PATH, foe)) # ... and the snare lands during it
	sc.tick_turn_end(board)
	assert_true(sc.has_status(&"ensnared"), "the turn it landed in does not count")
	sc.tick_all(board)
	assert_true(sc.has_rule_flag(&"immobilized"), "it holds the victim's NEXT turn")
	sc.tick_turn_end(board)
	assert_false(sc.has_status(&"ensnared"), "and ends with it")


func test_a_foes_stun_is_still_on_for_the_turn_it_costs() -> void:
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var board := _board_with([victim, foe])
	var sc := _controller_for(victim)
	sc.add_status(_from(FLINCHED_PATH, foe))
	sc.tick_all(board)
	assert_true(sc.has_rule_flag(&"stunned"), "on through the skipped turn")
	sc.tick_turn_end(board)
	assert_false(sc.has_rule_flag(&"stunned"), "off once that one turn is over -- no lockout")


# ===========================================================================
# PROTECTIVE -- today's meaning, unchanged
# ===========================================================================

func test_a_self_guard_survives_its_own_turn_end_and_the_enemy_turn() -> void:
	var caster := OwnedUnit.new(_side_b)
	var board := _board_with([caster])
	var sc := _controller_for(caster)

	sc.tick_all(board)                         # the caster's turn opens
	sc.add_status(_from(BRACED_PATH, caster))  # ... and it braces
	sc.tick_turn_end(board)                    # its turn closes
	assert_true(sc.has_status(&"braced"), "a 1-turn self-guard does NOT vanish at the end of the turn it was cast")
	assert_almost_eq(sc.status_damage_taken_scale(), 0.6, 0.0001,
		"so it is still reducing damage through the enemy's following turn")
	sc.tick_all(board)                         # the caster's next turn opens
	assert_false(sc.has_status(&"braced"), "and lapses as the caster's next turn begins, as it always did")


func test_an_allys_one_turn_buff_keeps_the_protective_clock() -> void:
	var target := OwnedUnit.new(_side_b)
	var ally := OwnedUnit.new(_side_b)
	var board := _board_with([target, ally])
	var sc := _controller_for(target)
	sc.tick_all(board)
	sc.add_status(_from(BRACED_PATH, ally))
	sc.tick_turn_end(board)
	assert_true(sc.has_status(&"braced"), "an ally's ward covers the enemy's reply")
	sc.tick_all(board)
	assert_false(sc.has_status(&"braced"), "and lapses at the target's next turn start")


func test_an_unattributed_status_keeps_the_old_clock() -> void:
	# Code-built rewards, restored saves and every fixture that predates the two clocks.
	var unit := OwnedUnit.new(_side_b)
	var board := _board_with([unit])
	var sc := _controller_for(unit)
	sc.add_status(load(FLINCHED_PATH) as StatusCondition)
	sc.tick_all(board)
	assert_false(sc.has_status(&"flinched"), "no applier: expires at the opening tick exactly as before")


# ===========================================================================
# TICK COUNTS -- unchanged on both clocks
# ===========================================================================

func test_a_foes_three_turn_poison_still_ticks_exactly_three_times() -> void:
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var board := _board_with([victim, foe])
	var sc := _controller_for(victim)
	sc.add_status(_poison(3, foe))
	for turn in range(3):
		sc.tick_all(board)
		assert_eq(victim.hp, 100 - 4 * (turn + 1), "turn %d ticks once" % [turn + 1])
		assert_true(sc.has_status(&"test_poison"), "and is in force for the whole of turn %d" % [turn + 1])
		sc.tick_turn_end(board)
	assert_false(sc.has_status(&"test_poison"), "gone after the third turn it ticked on")
	sc.tick_all(board)
	assert_eq(victim.hp, 88, "three ticks, never a fourth")


func test_a_start_only_driver_still_gets_exactly_n_ticks() -> void:
	# A turn whose END never arrived is counted at the next START, so a caller that only
	# drives turn starts cannot turn a 3-turn poison into four ticks.
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var board := _board_with([victim, foe])
	var sc := _controller_for(victim)
	sc.add_status(_poison(3, foe))
	for i in range(6):
		sc.tick_all(board)
	assert_eq(victim.hp, 88, "exactly three ticks")
	assert_false(sc.has_status(&"test_poison"), "and it did expire")


func test_a_self_cast_poison_keeps_its_old_schedule() -> void:
	var unit := OwnedUnit.new(_side_b)
	var board := _board_with([unit])
	var sc := _controller_for(unit)
	sc.add_status(_poison(3, unit))
	for i in range(3):
		sc.tick_all(board)
		sc.tick_turn_end(board)
	assert_eq(unit.hp, 88, "three ticks")
	assert_false(sc.has_status(&"test_poison"), "gone at its third opening tick, as before")


# ===========================================================================
# REFRESH (rule 6) re-resolves the clock
# ===========================================================================

func test_a_refresh_restarts_the_count_and_takes_the_new_appliers_clock() -> void:
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var board := _board_with([victim, foe])
	var sc := _controller_for(victim)
	var live = sc.add_status(_from(ENSNARED_PATH, foe))
	sc.tick_all(board)                         # the victim's snared turn is open
	sc.add_status(_from(ENSNARED_PATH, foe))   # a second snare lands during it
	assert_eq(live.turns_left, 1, "refreshed to full")
	sc.tick_turn_end(board)
	assert_true(sc.has_status(&"ensnared"), "the refresh's fresh turn is the NEXT one, not the one in progress")
	sc.tick_all(board)
	sc.tick_turn_end(board)
	assert_false(sc.has_status(&"ensnared"), "which it then costs")

	var self_cast = sc.add_status(_from(ENSNARED_PATH, foe))
	sc.add_status(_from(ENSNARED_PATH, victim))
	assert_false(self_cast.counts_own_turns, "a refresh hands the clock to the NEW applier, like the credit")


# ===========================================================================
# THE ENVIRONMENT -- a trap's Ensnared is an affliction
# ===========================================================================

class SnareSink extends OwnedUnit:
	var landed: Array = []
	func add_status(condition) -> void:
		landed.append(condition)


func test_a_tile_inflicts_as_the_environment() -> void:
	var walker := SnareSink.new(_side_b)
	var board := _board_with([walker])
	var trap: TileEffectResource = load(VINE_TRAP_PATH)
	trap.run(walker, board)
	assert_eq(walker.landed.size(), 1, "the vine trap inflicts its hold")
	var hold: StatusCondition = walker.landed[0]
	assert_true(hold.inflicted_by_environment, "stamped as the environment's doing")
	assert_true(hold.resolve_clock(walker),
		"so the occupant-as-caster tile context still lands it on the affliction clock")


# ===========================================================================
# TIMED STAT MODIFIERS follow the same rule
# ===========================================================================

func _defense_down(turns: int) -> StatModifierEffect:
	var e := StatModifierEffect.new()
	e.stat_name = "defense"
	e.amount = -8
	e.duration = turns
	return e


func _enemy_ctx(caster, board, target) -> MoveContext:
	var move := MoveResource.new()
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ANY_UNIT
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	var cell: Vector3i = board.cell_of(target)
	return MoveContext.new(caster, board, move, cell, [cell] as Array[Vector3i])


func test_a_foes_timed_debuff_modifier_goes_on_the_affliction_clock() -> void:
	var victim := OwnedUnit.new(_side_b)
	var foe := OwnedUnit.new(_side_a)
	var ally := OwnedUnit.new(_side_b)
	var board := _board_with([victim, foe, ally])
	_defense_down(1).apply(_enemy_ctx(foe, board, victim))
	assert_eq(victim.clocks.values(), [true], "a foe's -defense counts the victim's own turns")
	victim.clocks.clear()
	_defense_down(1).apply(_enemy_ctx(ally, board, victim))
	assert_true(victim.clocks.is_empty(), "an ally's (or a self) modifier keeps the protective clock")


func test_unit_stats_counts_an_affliction_modifier_at_turn_end() -> void:
	var res := UnitStatsResource.new()
	res.unit_name = "Victim"
	res.base_defense = 10
	var stats := UnitStats.new()
	stats.stats_resource = res
	add_child_autofree(stats)   # _ready() seeds the current stats from the resource
	assert_eq(stats.get_stat("defense"), 10, "baseline")
	var debuff: int = stats.add_stat_modifier("defense", -8, 1)
	assert_true(stats.set_modifier_clock(debuff, true))
	var buff: int = stats.add_stat_modifier("attack", 5, 1)  # protective: self/ally

	stats.process_modifier_durations()     # the victim's turn opens
	assert_eq(stats.get_stat("defense"), 2, "the debuff holds through the victim's next turn")
	assert_false(stats.is_stat_modified("attack"), "the protective buff lapses at the opening, as before")
	stats.process_modifier_turn_end()      # ... and closes
	assert_eq(stats.get_stat("defense"), 10, "the debuff lapses as that turn ends")
	assert_false(stats.remove_stat_modifier(buff), "(the buff really was already gone)")
