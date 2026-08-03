extends GutTest

## INDIRECT KILL CREDIT: who is credited when something OTHER than a swing removes HP.
##
## The bug this pins: a poison tick resolves with the VICTIM as its own MoveContext caster
## (that is what makes the SELF-targeted tick move gather exactly the poisoned unit), and
## [DamageEffect] announced that caster as the attacker. So the victim's own AbilitySystem
## recorded itself as the last unit to damage it, and [method AbilitySystem._on_unit_eliminated]
## early-returns when the eliminated unit IS the listener -- meaning NOBODY's ON_KILL fired
## on a damage-over-time kill. A crawling hazard was worse still: it mutated HP with no
## announcement at all.
##
## The rule now lives in exactly one place, [method DamageEffect.credited_source], and three
## indirect damage sources read it: status ticks, traveling hazards, and (for the direct case
## it never had) the AI's legacy fallback attack.
##
## The live ON_KILL wiring is proven on real Units in
## integration/test_status_tick_lifecycle.gd -- the elimination signal is typed (Unit, Unit),
## so a mock can never travel it. What is proven HERE is the attribution rule itself and the
## threading of the applier from the effect that inflicted the status onto the live instance.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

# --- Doubles ------------------------------------------------------------------

## A bus with just the one signal, so an announcement can be observed without the typed
## GameEvents autoload (which refuses non-Unit payloads by design).
class MockBus:
	extends RefCounted
	signal damage_dealt(attacker, defender, amount)


## The minimum a unit needs to take indirect damage and be judged alive-or-not.
class Prey:
	var hp: int
	var max_health: int
	func _init(p_hp: int = 100) -> void:
		hp = p_hp
		max_health = p_hp
	func get_stat(_n: String) -> int:
		return 0
	func get_base_stat(_n: String) -> int:
		return 0
	func get_hp() -> int:
		return hp
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)


## Placement-only board. `all_units` is the query [method DamageEffect._is_on_board]
## prefers, and removing a unit from `placements` is how a test takes it OFF the board.
class MockBoard:
	var placements: Array = []
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func remove(unit) -> void:
		var kept: Array = []
		for p in placements:
			if p.unit != unit:
				kept.append(p)
		placements = kept
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
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			if p.unit != null and p.unit.get_hp() > 0:
				out.append(p.unit)
		return out
	func are_enemies(_a, _b) -> bool:
		return true
	func are_allies(_a, _b) -> bool:
		return false


## A tick effect that records WHO the tick credits, so the credit wiring inside
## [method StatusCondition.tick] is observable without a live bus. Deliberately local
## (tests/README rule 5): it exists to read one production value, not to stand in for a unit.
class CreditProbe:
	extends MoveEffect
	## Untyped Array rather than a member the lambda closes over -- GUT captures by value.
	var credited: Array = []
	func apply(ctx: MoveContext) -> void:
		credited.append(ctx.damage_credit())


# --- Helpers ------------------------------------------------------------------

func _poisoned() -> StatusCondition:
	return load("res://game/combat/status/poisoned.tres") as StatusCondition


## A live status carrying [param probe] as its only tick effect, applied by [param source].
## Built by hand rather than through a controller because add_status DEEP-duplicates the
## condition, which would copy the probe and leave the test holding the wrong instance.
func _probed_status(probe: CreditProbe, source) -> StatusCondition:
	var condition := StatusCondition.new()
	condition.id = &"test_dot"
	condition.display_name = "Test DoT"
	condition.duration_turns = 3
	condition.tick_effects = [probe] as Array[MoveEffect]
	condition.set_source(source)
	condition.turns_left = 3
	return condition


func _controller_for(unit) -> StatusController:
	var sc: StatusController = autofree(StatusController.new())
	sc.owner_unit = unit
	return sc


## An ENEMY-targeted single-cell context aimed at [param target].
func _context(caster, board, target) -> MoveContext:
	var cell: Vector2i = board.cell_of(target)
	var move := MoveResource.new()
	move.move_id = &"test_apply"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 0
	pattern.max_range = 6
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	return MoveContext.new(caster, board, move, cell, [cell] as Array[Vector2i])


# ===========================================================================
# THE RULE -- DamageEffect.credited_source
# ===========================================================================

func test_a_live_applier_on_the_board_is_credited() -> void:
	var board := MockBoard.new()
	var applier := Prey.new(50)
	var victim := Prey.new(30)
	board.place(applier, Vector2i(0, 0))
	board.place(victim, Vector2i(3, 0))
	assert_eq(DamageEffect.credited_source(applier, victim, board), applier,
		"the unit that applied the status owns what it does")


func test_a_dead_applier_credits_nobody() -> void:
	var board := MockBoard.new()
	var applier := Prey.new(50)
	var victim := Prey.new(30)
	board.place(applier, Vector2i(0, 0))
	board.place(victim, Vector2i(3, 0))
	applier.hp = 0
	assert_null(DamageEffect.credited_source(applier, victim, board),
		"you cannot earn a kill after you are dead -- the poison outlives you unattributed")


func test_an_applier_no_longer_on_the_board_credits_nobody() -> void:
	var board := MockBoard.new()
	var applier := Prey.new(50)
	var victim := Prey.new(30)
	board.place(applier, Vector2i(0, 0))
	board.place(victim, Vector2i(3, 0))
	board.remove(applier)
	assert_null(DamageEffect.credited_source(applier, victim, board),
		"an applier that has left the board is absent, and absent credits nobody")


func test_self_inflicted_damage_never_credits_the_victim() -> void:
	var board := MockBoard.new()
	var victim := Prey.new(30)
	board.place(victim, Vector2i(3, 0))
	assert_null(DamageEffect.credited_source(victim, victim, board),
		"a unit must never be credited with its own death -- the whole bug in one line")


func test_no_applier_at_all_credits_nobody() -> void:
	var board := MockBoard.new()
	var victim := Prey.new(30)
	board.place(victim, Vector2i(3, 0))
	assert_null(DamageEffect.credited_source(null, victim, board),
		"a status nobody applied (a tile, a scripted debuff) is unattributed")


func test_a_freed_applier_credits_nobody_instead_of_dangling() -> void:
	var board := MockBoard.new()
	var victim := Prey.new(30)
	board.place(victim, Vector2i(3, 0))
	var ghost := Node.new()
	ghost.free()
	assert_null(DamageEffect.credited_source(ghost, victim, board),
		"a freed applier resolves to nobody rather than being touched")


# ===========================================================================
# THREADING -- who is recorded as the applier
# ===========================================================================

func test_apply_status_stamps_the_caster_on_the_condition_it_inflicts() -> void:
	# The whole production path: the effect gathers its target and hands the status to
	# ApplyStatusEffect's direct sink (tests/README rule 5's StatusSinkUnit).
	var board := MockBoard.new()
	var caster := Prey.new(50)
	var victim := Doubles.StatusSinkUnit.new(1, { "health": 100 })
	board.place(caster, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))

	var effect := ApplyStatusEffect.new()
	effect.condition = _poisoned()
	effect.apply(_context(caster, board, victim))

	assert_eq(victim.added_statuses.size(), 1, "the poison landed")
	var inflicted: StatusCondition = victim.added_statuses[0]
	assert_eq(inflicted.get_source(), caster, "stamped with the unit that inflicted it")
	assert_null(_poisoned().get_source(),
		"and the shared authoring .tres was never stamped (it is duplicated first)")


func test_a_self_buff_is_stamped_with_the_caster_too() -> void:
	# to_caster takes the other branch through _inflict; it must stamp identically, or a
	# self-applied damaging status would tick unattributed.
	var board := MockBoard.new()
	var caster := Doubles.StatusSinkUnit.new(0, { "health": 100 })
	board.place(caster, Vector2i(0, 0))

	var effect := ApplyStatusEffect.new()
	effect.condition = load("res://game/combat/status/braced.tres") as StatusCondition
	effect.to_caster = true
	effect.apply(_context(caster, board, caster))

	assert_eq(caster.added_statuses.size(), 1, "the self-buff landed")
	assert_eq(caster.added_statuses[0].get_source(), caster,
		"and names the caster as its applier -- which the tick rule then reads as SELF and credits nobody")


func test_the_source_survives_the_controllers_own_duplicate() -> void:
	# add_status stores a DUPLICATE, and duplicate() carries only exported properties --
	# so the applier has to be re-stated onto the stored copy or attribution is lost the
	# instant the status lands.
	var victim := Prey.new(100)
	var applier := Prey.new(50)
	var sc := _controller_for(victim)

	var incoming := _poisoned().duplicate(true)
	incoming.set_source(applier)
	var live: StatusCondition = sc.add_status(incoming)

	assert_ne(live, incoming, "the controller stores its own copy, never the caller's")
	assert_eq(live.get_source(), applier, "and that copy still knows who applied it")


func test_refreshing_a_status_hands_it_to_the_new_applier() -> void:
	# A deliberate half of the refresh rule: a second source may not DEEPEN the effect,
	# but it does take ownership of what the effect goes on to do. Without this, credit
	# would be frozen to whoever happened to land the first application.
	var victim := Prey.new(100)
	var first := Prey.new(50)
	var second := Prey.new(50)
	var sc := _controller_for(victim)

	var braced := load("res://game/combat/status/braced.tres") as StatusCondition
	var a := braced.duplicate(true)
	a.set_source(first)
	sc.add_status(a)
	var b := braced.duplicate(true)
	b.set_source(second)
	sc.add_status(b)

	assert_eq(sc.stack_count(&"braced"), 1, "REFRESH still keeps exactly one instance")
	assert_eq(sc.get_active()[0].get_source(), second,
		"and the most recent applier owns it from now on")


# ===========================================================================
# THE TICK -- what a status tick credits
# ===========================================================================

func test_a_tick_credits_the_unit_that_applied_the_status() -> void:
	var board := MockBoard.new()
	var applier := Prey.new(50)
	var victim := Prey.new(100)
	board.place(applier, Vector2i(0, 0))
	board.place(victim, Vector2i(4, 0))

	var probe := CreditProbe.new()
	_probed_status(probe, applier).tick(victim, board)

	assert_eq(probe.credited.size(), 1, "the tick resolved once")
	assert_eq(probe.credited[0], applier,
		"and its damage is credited to the applier, not to the unit carrying it")


func test_a_tick_from_a_dead_applier_credits_nobody() -> void:
	var board := MockBoard.new()
	var applier := Prey.new(50)
	var victim := Prey.new(100)
	board.place(applier, Vector2i(0, 0))
	board.place(victim, Vector2i(4, 0))
	applier.hp = 0

	var probe := CreditProbe.new()
	_probed_status(probe, applier).tick(victim, board)

	assert_null(probe.credited[0], "a dead applier's poison kills for nobody")


func test_a_self_applied_tick_credits_nobody() -> void:
	var board := MockBoard.new()
	var victim := Prey.new(100)
	board.place(victim, Vector2i(4, 0))

	var probe := CreditProbe.new()
	_probed_status(probe, victim).tick(victim, board)

	assert_null(probe.credited[0],
		"a unit that poisoned itself is never credited with its own kill")


func test_a_tick_leaves_the_casters_own_math_alone() -> void:
	# The credit is a SEPARATE channel from the caster on purpose: every stat lookup,
	# passive modifier and target gather in the pipeline reads ctx.caster, so swapping it
	# would silently retune what a tick DEALS. The affected unit stays the caster.
	var board := MockBoard.new()
	var applier := Prey.new(50)
	var victim := Prey.new(100)
	board.place(applier, Vector2i(0, 0))
	board.place(victim, Vector2i(4, 0))

	var before: int = victim.hp
	_probed_status(CreditProbe.new(), applier).tick(victim, board)
	assert_eq(victim.hp, before, "the probe deals nothing, so nothing moved")

	var poison := _poisoned().duplicate(true)
	poison.set_source(applier)
	poison.turns_left = 3
	poison.tick(victim, board)
	assert_eq(before - victim.hp, 4,
		"the authored poison still ticks for exactly its authored 4 -- credit moved, damage did not")


func test_an_unset_credit_still_resolves_to_the_caster() -> void:
	# Regression-safety for every ordinary cast: a context nobody spoke to credits its
	# caster, exactly as before this existed.
	var board := MockBoard.new()
	var caster := Prey.new(50)
	var target := Prey.new(100)
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))
	assert_eq(_context(caster, board, target).damage_credit(), caster,
		"no override means the caster is credited")


# ===========================================================================
# HAZARDS -- a crawling vine's kills belong to its caster
# ===========================================================================

func _hazard(source, damage: int, bus) -> TravelingHazard:
	var hazard := TravelingHazard.new(
		Vector2i(0, 0), Vector2i(1, 0), 0, 1, 4, damage,
		CombatTypes.DamageCategory.TRUE, CombatTypes.TargetKind.ENEMY, source)
	hazard.event_bus = bus
	return hazard


func test_a_hazard_hit_is_announced_and_credited_to_its_owner() -> void:
	var board := MockBoard.new()
	var eldroot := Prey.new(200)
	var victim := Prey.new(50)
	board.place(eldroot, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))

	var bus := MockBus.new()
	var seen: Array = []
	bus.damage_dealt.connect(func(a, d, n): seen.append({ "attacker": a, "defender": d, "amount": n }))

	_hazard(eldroot, 12, bus).advance(board)

	assert_eq(seen.size(), 1, "the vine announced its hit instead of mutating HP silently")
	assert_eq(seen[0]["attacker"], eldroot, "credited to the unit that cast the lane")
	assert_eq(seen[0]["defender"], victim, "against the unit it entered")
	assert_eq(victim.hp, 38, "and the damage still landed")


func test_a_hazard_announces_before_it_applies_so_a_lethal_band_is_attributable() -> void:
	var board := MockBoard.new()
	var eldroot := Prey.new(200)
	var victim := Prey.new(5)
	board.place(eldroot, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))

	var bus := MockBus.new()
	var hp_when_announced: Array = []
	bus.damage_dealt.connect(func(_a, d, _n): hp_when_announced.append(d.get_hp()))

	_hazard(eldroot, 99, bus).advance(board)

	assert_eq(hp_when_announced[0], 5,
		"the announcement arrives while the victim is still standing, exactly as a swing does")
	assert_lt(victim.hp, 1, "and only then does the vine take it down")


func test_a_hazard_whose_owner_has_died_credits_nobody() -> void:
	var board := MockBoard.new()
	var eldroot := Prey.new(200)
	var victim := Prey.new(50)
	board.place(eldroot, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	eldroot.hp = 0  # the boss fell before its vine finished crawling

	var bus := MockBus.new()
	var seen: Array = []
	bus.damage_dealt.connect(func(a, _d, _n): seen.append(a))

	_hazard(eldroot, 12, bus).advance(board)

	assert_eq(seen.size(), 1, "the hit is still announced -- the player must still see it")
	assert_null(seen[0], "but a dead caster is credited with nothing")


func test_a_hazard_that_hits_nothing_announces_nothing() -> void:
	var board := MockBoard.new()
	var eldroot := Prey.new(200)
	board.place(eldroot, Vector2i(0, 0))

	var bus := MockBus.new()
	var seen: Array = []
	bus.damage_dealt.connect(func(_a, _d, _n): seen.append(true))

	_hazard(eldroot, 12, bus).advance(board)
	assert_eq(seen.size(), 0, "an empty band is not an event")


# ===========================================================================
# THE AI'S LEGACY FALLBACK ATTACK
# ===========================================================================

## A real Unit -- this path is typed (Unit, Unit) and announces on the typed autoload
## signal, so nothing less will do.
func _real_unit(display_name: String, attack: int, health: int) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = display_name
	res.unit_type = "warrior"
	res.max_health = health
	res.base_attack = attack
	res.base_speed = 8
	res.movement_range = 3
	u.stats_resource = res
	add_child_autofree(u)
	return u


func test_the_bot_fallback_attack_announces_its_hit() -> void:
	# The legacy no-Character path mutated HP directly, so every kill it landed credited
	# nobody: no ON_KILL, no retaliation, not even a floating damage number.
	var driver: BotTurnDriver = autofree(BotTurnDriver.new())
	var attacker := _real_unit("Bot", 11, 100)
	var target := _real_unit("Target", 5, 100)

	watch_signals(GameEvents)
	driver._fallback_attack(attacker, target)

	assert_signal_emitted(GameEvents, "damage_dealt",
		"the fallback attack is announced like any other hit")
	var params: Array = get_signal_parameters(GameEvents, "damage_dealt", -1)
	assert_eq(params[0], attacker, "credited to the unit that swung")
	assert_eq(params[1], target, "against the unit it hit")
	assert_eq(int(params[2]), 11, "carrying the damage it actually dealt")
	assert_eq(target.get_hp(), 89, "and the damage still landed")
