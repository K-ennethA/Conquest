extends GutTest

## Scree Trap's rubble must VISIBLY slow a unit that enters it, on top of the extra
## movement cost to cross it. The slow is a "Slowed" status ([StatModifierStatus]) that
## holds a -2 movement modifier for as long as it is active, so it shows up in the unit's
## active statuses (HUD / pips / hover) AND lowers get_stat("movement") -- which
## MovementResolver folds into its flood budget.
##
## CRITICAL project rule: a re-applied movement/duration debuff must REFRESH, never stack.
## These tests pin: applied once it drops movement by exactly 2; re-entering the field
## refreshes the timer without deepening the penalty (still -2, one instance); when it
## expires the modifier is taken back; and the authored rock_rubble.tres wires it up on
## ON_ENTER while keeping move_cost_bonus = 2.

# --- Mocks -----------------------------------------------------------------

## A unit that models UnitStats' modifier arithmetic: get_stat = base + sum(modifiers),
## with add/remove by id. Also exposes a StatusController so the tile pipeline can inflict.
class StatUnit:
	var base_move: int = 3
	var _mods: Dictionary = {}   # id -> { stat, amount }
	var _next_id: int = 0
	var ctrl                     # StatusController, set by the test

	func add_stat_modifier(stat: String, amount: int, _duration: int = -1) -> int:
		var id := _next_id
		_next_id += 1
		_mods[id] = { "stat": stat, "amount": amount }
		return id

	func remove_stat_modifier(id: int) -> bool:
		return _mods.erase(id)

	func get_base_stat(stat: String) -> int:
		return base_move if stat == "movement" else 0

	func get_stat(stat: String) -> int:
		var v := get_base_stat(stat)
		for m in _mods.values():
			if m["stat"] == stat:
				v += int(m["amount"])
		return v

	func get_status_controller():
		return ctrl

class TileBoard:
	var placements: Array = []
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i.ZERO
	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func in_bounds(_c: Vector2i) -> bool:
		return true


func _slow_status() -> StatModifierStatus:
	var s := StatModifierStatus.new()
	s.id = &"rubble_slowed"
	s.display_name = "Slowed"
	s.duration_turns = 2
	s.stacking = StatusCondition.Stacking.REFRESH
	s.stat_name = "movement"
	s.amount = -2
	return s


func _controller_for(unit) -> StatusController:
	var ctrl = autofree(StatusController.new())
	ctrl.owner_unit = unit
	unit.ctrl = ctrl
	return ctrl


# --- Applying the status lowers movement -----------------------------------

func test_status_applies_movement_modifier_once():
	var unit := StatUnit.new()
	var ctrl := _controller_for(unit)
	ctrl.add_status(_slow_status())
	assert_eq(unit.get_stat("movement"), 1, "movement drops from base 3 to 1 (-2)")
	assert_eq(ctrl.stack_count(&"rubble_slowed"), 1, "exactly one Slowed instance is active")


# --- Re-application REFRESHES, never STACKS ---------------------------------

func test_reentry_refreshes_not_stacks():
	var unit := StatUnit.new()
	var ctrl := _controller_for(unit)
	ctrl.add_status(_slow_status())
	# Re-enter the field: a second application of the SAME status id.
	ctrl.add_status(_slow_status())
	assert_eq(unit.get_stat("movement"), 1, "still -2 total, NOT -4 -- refresh, not stack")
	assert_eq(ctrl.stack_count(&"rubble_slowed"), 1, "still a single instance, not two")


func test_reentry_refreshes_the_timer():
	var unit := StatUnit.new()
	var ctrl := _controller_for(unit)
	var board := TileBoard.new()
	ctrl.add_status(_slow_status())      # turns_left 2
	ctrl.tick_all(board)                 # -> 1 remaining
	ctrl.add_status(_slow_status())      # REFRESH -> back to full duration
	var live: StatusCondition = ctrl.get_active()[0]
	assert_eq(live.turns_left, 2, "re-entering the rubble refreshes the remaining duration to full")


# --- Expiry takes the modifier back ----------------------------------------

func test_expiry_restores_movement():
	var unit := StatUnit.new()
	var ctrl := _controller_for(unit)
	var board := TileBoard.new()
	ctrl.add_status(_slow_status())      # turns_left 2, movement 1
	ctrl.tick_all(board)                 # 2 -> 1
	assert_eq(unit.get_stat("movement"), 1, "still slowed after the first tick")
	ctrl.tick_all(board)                 # 1 -> 0 -> expire -> modifier removed
	assert_eq(unit.get_stat("movement"), 3, "movement restored to base once Slowed expires")
	assert_eq(ctrl.stack_count(&"rubble_slowed"), 0, "the status is gone")


# --- Entering a rubble tile inflicts the visible slow (ON_ENTER pipeline) ---

func test_entering_rubble_tile_applies_slow():
	var unit := StatUnit.new()
	_controller_for(unit)
	var board := TileBoard.new()
	board.place(unit, Vector2i(0, 0))

	# A rubble-like tile effect (ALL faction so no perspective is needed) that, ON_ENTER,
	# inflicts the Slowed status -- the same wiring rock_rubble.tres carries.
	var te := TileEffectResource.new()
	te.id = &"rock_rubble"
	te.trigger = TileEffectResource.Trigger.ON_ENTER
	te.affected_factions = TileEffectResource.AffectedFactions.ALL
	te.move_cost_bonus = 2
	var apply := ApplyStatusEffect.new()
	apply.condition = _slow_status()
	apply.chance = 1.0
	te.effects = [apply]

	var sys = autofree(TileEffectSystem.new())
	sys.tile_effects[Vector2i(0, 0)] = [te]
	sys.on_enter(unit, Vector2i(0, 0), board)

	assert_eq(unit.get_stat("movement"), 1, "stepping onto rubble slows the unit to movement 1")
	var ctrl = unit.get_status_controller()
	assert_true(ctrl.has_status(&"rubble_slowed"), "the visible Slowed status is now active on the unit")


# --- Authored resource integrity -------------------------------------------

func test_rock_rubble_tres_wires_the_slow_on_enter():
	var te = load("res://game/tiles/effects/resources/rock_rubble.tres")
	assert_not_null(te, "rock_rubble.tres loads")
	assert_eq(int(te.trigger), int(TileEffectResource.Trigger.ON_ENTER), "rubble fires ON_ENTER")
	assert_eq(int(te.move_cost_bonus), 2, "rubble still costs +2 to cross")
	var found := false
	for e in te.effects:
		if e is ApplyStatusEffect and e.condition != null and StringName(e.condition.id) == &"rubble_slowed":
			found = true
			assert_eq(int(e.condition.stacking), int(StatusCondition.Stacking.REFRESH), "the slow refreshes, never stacks")
	assert_true(found, "rubble carries an ApplyStatusEffect that inflicts rubble_slowed")


func test_rubble_slowed_tres_is_a_movement_debuff():
	var s = load("res://game/combat/status/rubble_slowed.tres")
	assert_not_null(s, "rubble_slowed.tres loads")
	assert_true(s is StatModifierStatus, "it is a StatModifierStatus")
	assert_eq(s.stat_name, "movement", "it modifies movement")
	assert_eq(int(s.amount), -2, "by -2")
	assert_eq(int(s.stacking), int(StatusCondition.Stacking.REFRESH), "with refresh semantics")
