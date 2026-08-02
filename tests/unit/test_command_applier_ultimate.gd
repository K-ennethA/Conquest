extends GutTest

# APPLY-SIDE ULTIMATE CUT-IN.
#
# The rule: the full-screen cut-in belongs where a cast APPLIES, not where it is submitted.
# In a networked match every peer -- the caster's own client included -- runs the resolved
# CAST_MOVE through CommandApplier, so emitting GameEvents.ultimate_casting there is what
# makes a REMOTE opponent's ultimate flash on this client, and makes it flash exactly ONCE
# for the local caster (UnitActionsPanel's networked branch deliberately does not play it).
#
# What is pinned here:
#   1. An applied ultimate cast raises ultimate_casting, carrying the caster + its MoveResource
#      (which is what UltimateCutIn reads for the name/element).
#   2. An ordinary cast raises nothing -- ordinary casts stay silent.
#   3. A cast that cannot resolve (unknown unit) never announces a flash for a move that is
#      not happening.
#   4. A duck-typed unit with no get_move (headless mocks, the loopback suite's MockUnit)
#      degrades silently instead of erroring -- the guard that keeps the determinism suites
#      byte-for-byte unchanged.
#
# The overlay's own playback is covered by unit/test_ultimate_cutin.gd; this suite only proves
# the TRIGGER, so it never mounts one.


# --- doubles -----------------------------------------------------------------

## A unit exposing exactly the surface CommandApplier's CAST_MOVE branch touches. RefCounted:
## nothing here is a Node, so the suite cannot orphan.
class CastingUnit extends RefCounted:
	var moves: Dictionary = {}          ## slot:int -> MoveResource
	var casts: Array = []               ## slots this unit was asked to cast
	var actions_spent: Array = []

	func get_move(slot: int) -> MoveResource:
		return moves.get(slot, null)

	func perform_move(slot: int, _aim: Vector2i, _board, _rng = null) -> Dictionary:
		casts.append(slot)
		return { "success": true, "reason": "", "events": [] }

	func mark_action_completed(what: String) -> void:
		actions_spent.append(what)

	func get_display_name() -> String:
		return "Caster"

## The shape of a unit that predates the moveset accessor (and of the loopback suite's mock):
## it can cast, but cannot be asked WHICH move a slot holds.
class MoveslessUnit extends RefCounted:
	func perform_move(_slot: int, _aim: Vector2i, _board, _rng = null) -> Dictionary:
		return { "success": true, "reason": "", "events": [] }


# --- fixtures ----------------------------------------------------------------

func _move(display_name: String, ultimate: bool) -> MoveResource:
	var move := MoveResource.new()
	move.display_name = display_name
	move.is_ultimate = ultimate
	return move

## An applier holding one registered unit (net_id 1) with the given slot -> move map.
func _applier_with(unit) -> CommandApplier:
	var reg := CommandApplier.UnitRegistry.new()
	reg.register(unit, 1)
	return CommandApplier.new(reg, null)

## A resolved CAST_MOVE the way the authority stamps one before broadcasting.
func _cast(net_id: int, slot: int) -> Dictionary:
	return NetProtocol.stamp_resolution(
		NetProtocol.make_cast_move(net_id, slot, Vector2i(2, 2), 0), 1, 0)


# --- 1. An ultimate announces itself on apply --------------------------------

func test_applying_an_ultimate_cast_raises_ultimate_casting():
	var unit := CastingUnit.new()
	unit.moves = { 3: _move("Iron Meteor", false) }   # slot 3 IS the ultimate slot
	var applier := _applier_with(unit)

	watch_signals(GameEvents)
	var res: Dictionary = applier.apply_command(_cast(1, 3), null, null)

	assert_true(bool(res["ok"]), "the cast still resolves normally")
	assert_signal_emit_count(GameEvents, "ultimate_casting", 1,
		"applying an ultimate cast flashes the cut-in exactly once on this peer")
	var params: Array = get_signal_parameters(GameEvents, "ultimate_casting")
	assert_eq(params[0], unit, "the flash names the casting unit")
	assert_eq(String(params[1].display_name), "Iron Meteor", "and the move it is casting")


func test_the_is_ultimate_flag_announces_from_an_earlier_slot():
	var unit := CastingUnit.new()
	unit.moves = { 1: _move("Prism Nova", true) }
	var applier := _applier_with(unit)

	watch_signals(GameEvents)
	applier.apply_command(_cast(1, 1), null, null)

	assert_signal_emit_count(GameEvents, "ultimate_casting", 1,
		"a move flagged is_ultimate flashes from any slot, exactly as it does locally")


# --- 2. Ordinary casts stay silent -------------------------------------------

func test_an_ordinary_cast_does_not_flash():
	var unit := CastingUnit.new()
	unit.moves = { 0: _move("Jab", false) }
	var applier := _applier_with(unit)

	watch_signals(GameEvents)
	var res: Dictionary = applier.apply_command(_cast(1, 0), null, null)

	assert_true(bool(res["ok"]), "the ordinary cast resolves")
	assert_signal_emit_count(GameEvents, "ultimate_casting", 0,
		"an ordinary move never sweeps the cut-in")


func test_an_empty_slot_does_not_flash():
	var unit := CastingUnit.new()   # no moves at all
	var applier := _applier_with(unit)

	watch_signals(GameEvents)
	applier.apply_command(_cast(1, 3), null, null)

	assert_signal_emit_count(GameEvents, "ultimate_casting", 0,
		"a null move in the ultimate slot is not an ultimate")


# --- 3. A cast that cannot resolve never flashes ------------------------------

func test_an_unknown_unit_never_flashes():
	var applier := CommandApplier.new(CommandApplier.UnitRegistry.new(), null)

	watch_signals(GameEvents)
	var res: Dictionary = applier.apply_command(_cast(99, 3), null, null)

	assert_false(bool(res["ok"]), "an unregistered net_id fails the apply")
	assert_eq(String(res["reason"]), "unknown_unit", "and says why, as a returned value")
	assert_signal_emit_count(GameEvents, "ultimate_casting", 0,
		"no flash for a cast that never happened")


# --- 4. Duck-typed units without the accessor degrade silently ---------------

func test_a_unit_without_get_move_is_skipped_not_errored():
	# This is the shape the determinism/loopback suites use. It must apply exactly as before:
	# no flash, no engine error (GUT fails a test on any engine error).
	var unit := MoveslessUnit.new()
	var applier := _applier_with(unit)

	watch_signals(GameEvents)
	var res: Dictionary = applier.apply_command(_cast(1, 3), null, null)

	assert_true(bool(res["ok"]), "the cast applies unchanged for a unit with no moveset accessor")
	assert_signal_emit_count(GameEvents, "ultimate_casting", 0,
		"and it cannot be asked what the slot holds, so nothing is announced")
