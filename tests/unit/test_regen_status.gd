extends GutTest

## [RegenStatus] is the healing channel behind items like the Sagebloom Poultice: a
## battle-long condition that restores a flat amount at every tick.
##
## The project rule it has to honour is the same one [StatModifierStatus] does -- a
## re-applied condition REFRESHES, it never stacks -- because the alternative is a unit that
## picks up a second source of regen and quietly heals twice as fast forever. These tests are
## deliberately shaped like test_rubble_slow_status.gd: apply once and measure, re-apply and
## prove nothing deepened, then tick and prove the timer behaves.
##
## They also pin the deviation from the base class: [method RegenStatus.tick] does NOT route
## through the effect pipeline, so it heals with or without a live board. A regen that only
## worked when a board happened to be present would fail exactly where it is hardest to spot.

# --- Mocks -----------------------------------------------------------------

## A unit that models HP with a ceiling, which is what makes an overheal test meaningful.
class HealUnit:
	var max_hp: int = 30
	var hp: int = 10
	var ctrl  # StatusController, set by the test

	func heal(amount: int) -> void:
		hp = mini(max_hp, hp + amount)

	func get_stat(stat_name: String) -> int:
		return hp if stat_name == "health" else 0

	func get_base_stat(stat_name: String) -> int:
		return max_hp if stat_name == "health" else 0

	func get_status_controller():
		return ctrl


## A minimal board: RegenStatus ignores it, but tick_all still hands one down.
class TickBoard:
	func cell_of(_unit) -> Vector2i:
		return Vector2i.ZERO
	func in_bounds(_cell: Vector2i) -> bool:
		return true


func _regen_status(amount: int = 5, duration: int = -1) -> RegenStatus:
	var status := RegenStatus.new()
	status.id = &"item_regen"
	status.display_name = "Regenerating"
	status.duration_turns = duration
	status.stacking = StatusCondition.Stacking.REFRESH
	status.heal_per_turn = amount
	return status


func _controller_for(unit) -> StatusController:
	var controller = autofree(StatusController.new())
	controller.owner_unit = unit
	unit.ctrl = controller
	return controller


# --- Healing on tick --------------------------------------------------------

func test_tick_heals_the_unit():
	var unit := HealUnit.new()
	var controller := _controller_for(unit)
	var board := TickBoard.new()
	controller.add_status(_regen_status(5))

	controller.tick_all(board)

	assert_eq(unit.hp, 15, "one tick restored exactly 5 HP")


func test_it_heals_every_turn_it_is_active():
	var unit := HealUnit.new()
	var controller := _controller_for(unit)
	var board := TickBoard.new()
	controller.add_status(_regen_status(5))

	controller.tick_all(board)
	controller.tick_all(board)
	controller.tick_all(board)

	assert_eq(unit.hp, 25, "three ticks, three heals")


func test_applying_it_does_not_heal_on_its_own():
	# on_apply must be inert: the heal is a TICK, so a status applied mid-turn does not pay out
	# until the unit's next turn actually begins.
	var unit := HealUnit.new()
	var controller := _controller_for(unit)
	controller.add_status(_regen_status(5))
	assert_eq(unit.hp, 10, "applying the status alone heals nothing")


func test_it_heals_without_a_board():
	# The base StatusCondition.tick bails when board is null (it needs a MoveContext).
	# RegenStatus deliberately does not, so a mock/headless tick still heals.
	var unit := HealUnit.new()
	var status := _regen_status(5)
	status.tick(unit, null)
	assert_eq(unit.hp, 15, "healing needs no board")


func test_healing_respects_the_units_ceiling():
	var unit := HealUnit.new()
	unit.hp = 28
	var controller := _controller_for(unit)
	controller.add_status(_regen_status(5))
	controller.tick_all(TickBoard.new())
	assert_eq(unit.hp, 30, "the heal clamps at max HP rather than overfilling")


func test_a_zero_regen_is_inert():
	var unit := HealUnit.new()
	var controller := _controller_for(unit)
	controller.add_status(_regen_status(0))
	controller.tick_all(TickBoard.new())
	assert_eq(unit.hp, 10, "a 0/turn regen heals nothing")


func test_a_target_that_cannot_heal_is_survivable():
	var status := _regen_status(5)
	var events: Array[Dictionary] = status.tick(null, null)
	assert_eq(events.size(), 0, "a null target is a no-op, never a crash")


func test_the_tick_reports_what_it_healed():
	var unit := HealUnit.new()
	var status := _regen_status(5)
	var events: Array[Dictionary] = status.tick(unit, null)
	assert_eq(events.size(), 1, "one tick, one event")
	assert_eq(int(events[0].get("amount", 0)), 5, "reporting the HP actually restored")


func test_the_reported_amount_is_the_clamped_amount():
	var unit := HealUnit.new()
	unit.hp = 28
	var status := _regen_status(5)
	var events: Array[Dictionary] = status.tick(unit, null)
	assert_eq(int(events[0].get("amount", 0)), 2, "an overheal reports the 2 HP it really gave")


# --- Re-application REFRESHES, never STACKS ---------------------------------

func test_reapplying_does_not_double_the_heal():
	var unit := HealUnit.new()
	var controller := _controller_for(unit)
	var board := TickBoard.new()
	controller.add_status(_regen_status(5))
	controller.add_status(_regen_status(5))   # a second source of the SAME regen

	controller.tick_all(board)

	assert_eq(controller.stack_count(&"item_regen"), 1, "still a single instance, not two")
	assert_eq(unit.hp, 15, "still 5 per tick, NOT 10 -- refresh, not stack")


func test_reapplying_refreshes_the_timer():
	var unit := HealUnit.new()
	var controller := _controller_for(unit)
	var board := TickBoard.new()
	controller.add_status(_regen_status(5, 3))   # turns_left 3
	controller.tick_all(board)                   # -> 2 remaining
	controller.add_status(_regen_status(5, 3))   # REFRESH -> back to full
	var live: StatusCondition = controller.get_active()[0]
	assert_eq(live.turns_left, 3, "re-applying restores the full duration")


func test_a_finite_regen_expires():
	var unit := HealUnit.new()
	var controller := _controller_for(unit)
	var board := TickBoard.new()
	controller.add_status(_regen_status(5, 2))

	controller.tick_all(board)   # heals, 2 -> 1
	controller.tick_all(board)   # heals, 1 -> 0 -> expires
	controller.tick_all(board)   # gone: no third heal

	assert_eq(controller.stack_count(&"item_regen"), 0, "the status expired")
	assert_eq(unit.hp, 20, "it healed exactly twice")


func test_a_battle_long_regen_never_expires_on_its_own():
	var unit := HealUnit.new()
	var controller := _controller_for(unit)
	var board := TickBoard.new()
	controller.add_status(_regen_status(1, -1))
	for _i in range(12):
		controller.tick_all(board)
	assert_eq(controller.stack_count(&"item_regen"), 1, "a -1 duration regen ticks forever")


# --- Defaults ---------------------------------------------------------------

func test_a_fresh_regen_status_is_battle_long_and_refreshing():
	var status := RegenStatus.new()
	assert_eq(status.duration_turns, -1, "constructed at runtime it lasts the whole battle")
	assert_eq(int(status.stacking), int(StatusCondition.Stacking.REFRESH), "and refreshes")
	assert_true(status.is_permanent(), "which the engine reads as permanent")
