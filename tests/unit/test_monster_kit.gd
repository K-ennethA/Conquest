extends GutTest

# DUSKMAW's kit -- the long-range dark attacker.
#
#   DREAD BRAND (ON_ATTACK passive)  -- damage it deals BRANDS the victim; the next
#                                       damage instance from ANY source is x1.3, then
#                                       the brand is spent.
#   ABYSSAL MAW  (move 1)            -- a delayed 3x3 eruption at long range.
#   UMBRAL CLAW  (move 2)            -- a 3-cell piercing line.
#   VOIDWALK     (move 3)            -- one turn of taking no damage at all.
#   SHADOW DASH  (move 4)            -- charge through up to 3 enemies, land beyond,
#                                       then MOVE again (CANTO) on a shortened leash --
#                                       movement only, never a second strike.
#
# Everything here is pure mocks + resources: no scene tree, no autoloads, no disk. The
# turn-flow half of the kit (WHEN the maw erupts, WHEN Voidwalk and the Void Surge run
# out) needs real turn systems and lives in
# tests/integration/test_monster_turn_flow.gd instead.
#
# Mock style follows test_eldroot.gd / test_bot_controller.gd. The event BUS is a bare
# RefCounted carrying an untyped `damage_dealt`, exactly as test_kill_attribution_order.gd
# uses one: the real GameEvents signal is typed (Unit, Unit, int) and rejects mocks, so
# every damage announcement in this suite is routed through the injected bus instead.

# --- Mocks -----------------------------------------------------------------

## Stand-in for the GameEvents autoload, injected via MoveContext.event_bus. Records
## every announcement so attribution can be asserted, and is the bus a BrandStatus binds
## to -- which is what lets the whole consume rule be driven without autoloads.
class MockBus:
	extends RefCounted
	signal damage_dealt(attacker, defender, amount)
	signal hazard_advanced(hazard, cells, next_cells, damage)
	signal hazard_expired(hazard)
	var damage_calls: Array = []
	var advanced_calls: Array = []
	var expired_calls: Array = []
	func _init() -> void:
		damage_dealt.connect(_on_damage)
		hazard_advanced.connect(_on_advanced)
		hazard_expired.connect(_on_expired)
	func _on_damage(attacker, defender, amount) -> void:
		damage_calls.append({ "attacker": attacker, "defender": defender, "amount": amount })
	func _on_advanced(hazard, cells, next_cells, damage) -> void:
		advanced_calls.append({
			"hazard": hazard, "cells": cells, "next_cells": next_cells, "damage": damage })
	func _on_expired(hazard) -> void:
		expired_calls.append(hazard)


## A duck-typed unit with a real [StatusController] hanging off it -- the shape the
## defender-side rules actually read (DamageMath asks get_status_controller() for the
## damage_taken_scale and for the "invulnerable" rule flag).
##
## The controller is a Node, so it is NOT created here: tests/README.md rule 2 warns that
## a RefCounted double constructing a Node in _init leaks it past every autofree. It is
## built in the test body with autofree() and handed in.
class StatusUnit:
	extends RefCounted
	var team: int
	var stats: Dictionary
	var hp: int
	## How many times CantoStatus armed the movement-only grant on this unit. A COUNT,
	## not a bool, so "refresh never grants twice" is provable.
	var canto_grants: int = 0
	## The Arena's full-extra-action budget, present so a test can prove the canto path
	## no longer touches it (the arena machinery is untouched, and unused here).
	var arena_extra_actions: int = 0
	var modifiers: Array = []
	var controller = null
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))
	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name, 0))
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp += n
	func get_status_controller():
		return controller
	func add_stat_modifier(stat: String, amount: int, duration: int) -> int:
		modifiers.append({ "stat": stat, "amount": amount, "duration": duration })
		return modifiers.size()
	func remove_stat_modifier(id: int) -> void:
		if id >= 1 and id <= modifiers.size():
			modifiers[id - 1]["removed"] = true
	func grant_canto() -> void:
		canto_grants += 1


## The board every test here uses: placement, allegiance, and the two mutators the dash
## needs (move_unit) plus a blocked-terrain set so the "nowhere to land" edge case can be
## built without a live map.
class MockBoard:
	extends RefCounted
	var placements: Array = []
	var blocked: Dictionary = {}
	var bounds: Rect2i = Rect2i(-20, -20, 40, 40)
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func block(cell: Vector2i) -> void:
		blocked[cell] = true
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
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	func in_bounds(cell: Vector2i) -> bool:
		return bounds.has_point(cell)
	func is_blocked(cell: Vector2i) -> bool:
		return blocked.has(cell)


# --- Content loaders -------------------------------------------------------

func _branded() -> StatusCondition:
	return load("res://game/combat/status/branded.tres") as StatusCondition

func _submerged() -> StatusCondition:
	return load("res://game/combat/status/submerged.tres") as StatusCondition

func _void_surge() -> StatusCondition:
	return load("res://game/combat/status/void_surge.tres") as StatusCondition

func _dread_brand() -> AbilityResource:
	return load("res://game/abilities/dread_brand.tres") as AbilityResource

func _abyssal_maw() -> MoveResource:
	return load("res://game/combat/moves/abyssal_maw.tres") as MoveResource

func _umbral_claw() -> MoveResource:
	return load("res://game/combat/moves/umbral_claw.tres") as MoveResource

func _voidwalk() -> MoveResource:
	return load("res://game/combat/moves/voidwalk.tres") as MoveResource

func _shadow_dash() -> MoveResource:
	return load("res://game/combat/moves/shadow_dash.tres") as MoveResource


# --- Helpers ---------------------------------------------------------------

## A controller wired to [param unit], registered for automatic freeing.
func _controller_for(unit) -> StatusController:
	var controller: StatusController = autofree(StatusController.new())
	controller.owner_unit = unit
	unit.controller = controller
	return controller


## A flat, always-landing magical hit: no stat scaling and no crit, so the number under
## test is exactly `power` after mitigation and the post-mitigation chain.
func _flat_move(power: int) -> MoveResource:
	var move := MoveResource.new()
	move.move_id = &"test_flat"
	move.accuracy = 1.0
	move.crit_chance = 0.0
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 6
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	var dmg := DamageEffect.new()
	dmg.power = power
	dmg.scaling_stat = ""
	dmg.scale = 0.0
	dmg.category = CombatTypes.DamageCategory.MAGICAL
	move.effects = [dmg]
	return move


## Resolve [param move] from [param attacker] at [param victim]'s cell, announcing on
## [param bus]. Returns the context so a test can read the event log.
func _strike(attacker, victim, board, move: MoveResource, bus) -> MoveContext:
	var aim: Vector2i = board.cell_of(victim)
	var ctx := MoveContext.new(attacker, board, move, aim, [aim] as Array[Vector2i])
	ctx.event_bus = bus
	for effect in move.effects:
		effect.apply(ctx)
	return ctx


## Plant Dread Brand's payload on [param victim], announcing on [param bus] -- i.e. what
## the ON_ATTACK ability does once AbilitySystem has routed the trigger to it.
func _plant_brand(brander, victim, board, bus) -> void:
	var effect := DreadBrandEffect.new()
	effect.brand = _branded()
	var aim: Vector2i = board.cell_of(victim)
	var move := MoveResource.new()
	move.move_id = &"dread_brand"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ANY_UNIT
	pattern.min_range = 0
	pattern.max_range = 9
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	move.targeting = pattern
	var ctx := MoveContext.new(brander, board, move, aim, [aim] as Array[Vector2i])
	ctx.event_bus = bus
	effect.apply(ctx)


# ===========================================================================
# DREAD BRAND -- the mark
# ===========================================================================

func test_dread_brand_is_authored_as_an_on_attack_passive_aimed_at_the_victim():
	var ability := _dread_brand()
	assert_not_null(ability, "dread_brand.tres loads")
	assert_eq(ability.trigger, AbilityTrigger.Trigger.ON_ATTACK,
		"the brand is planted the moment the unit resolves an attack")
	assert_true(ability.targets_triggering_unit,
		"and it lands on the unit that was hit, not on Monster itself")
	assert_eq(ability.cooldown, 0, "every strike brands -- there is no cooldown")
	assert_eq(ability.max_activations, -1, "and no per-battle limit")


func test_the_brand_lands_on_a_unit_this_one_damages():
	var brander := StatusUnit.new(0, { "magic": 20 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(brander, Vector2i(0, 0))
	board.place(victim, Vector2i(2, 0))
	_controller_for(victim)
	var bus := MockBus.new()

	_plant_brand(brander, victim, board, bus)

	assert_true(victim.controller.has_status(&"branded"),
		"damaging a unit brands it")
	assert_eq(victim.controller.stack_count(&"branded"), 1,
		"exactly one brand instance")


func test_the_ability_resource_plants_the_brand_through_its_own_pipeline():
	# The authored wiring, end to end: AbilityResource.run_effects with the victim as the
	# triggering unit is precisely what AbilitySystem calls on ON_ATTACK.
	var brander := StatusUnit.new(0, { "magic": 20 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(brander, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	var controller := _controller_for(victim)

	_dread_brand().run_effects(brander, board, victim)

	assert_true(controller.has_status(&"branded"),
		"the authored ability's own effect list plants the brand on the triggering unit")
	# Bound to the GameEvents autoload here (run_effects injects no bus); take it back off
	# so no live subscription outlives this test.
	controller.remove_status(&"branded")


func test_a_branded_target_takes_amplified_damage():
	var attacker := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	var controller := _controller_for(victim)
	var bus := MockBus.new()

	# Baseline: an unbranded 20 lands as 20.
	_strike(attacker, victim, board, _flat_move(20), bus)
	assert_eq(victim.hp, 80, "baseline: a flat 20 removes 20")

	_plant_brand(attacker, victim, board, bus)
	_strike(attacker, victim, board, _flat_move(20), bus)
	assert_eq(victim.hp, 80 - 26, "the branded hit is amplified x1.3 (20 -> 26)")
	assert_false(controller.has_status(&"branded"),
		"and the brand is spent on that one instance")


func test_the_brand_amplifies_a_DIFFERENT_attacker_too():
	# "the NEXT damage the victim takes (from ANYONE)". The brand belongs to the victim,
	# not to a matchup.
	var brander := StatusUnit.new(0, { "magic": 0 })
	var other := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(brander, Vector2i(0, 0))
	board.place(other, Vector2i(0, 1))
	board.place(victim, Vector2i(1, 0))
	var controller := _controller_for(victim)
	var bus := MockBus.new()

	_plant_brand(brander, victim, board, bus)
	_strike(other, victim, board, _flat_move(20), bus)

	assert_eq(victim.hp, 74, "a second attacker collects the amplified 26")
	assert_false(controller.has_status(&"branded"), "and spends the brand doing it")


func test_the_brand_amplifies_exactly_one_instance_and_no_more():
	var attacker := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 200 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	_controller_for(victim)
	var bus := MockBus.new()

	_plant_brand(attacker, victim, board, bus)
	_strike(attacker, victim, board, _flat_move(20), bus)
	assert_eq(victim.hp, 174, "first hit after the brand: 26")

	_strike(attacker, victim, board, _flat_move(20), bus)
	assert_eq(victim.hp, 154, "the SECOND hit is a plain 20 -- the brand is gone")


func test_hazard_damage_also_takes_the_amplification_and_spends_the_brand():
	# The environmental chain (DamageMath.environment_damage) reads the SAME
	# damage_taken_scale, and a hazard announces on the same bus -- so a vine both eats
	# the brand and is deepened by it, with no hazard-specific code.
	var brander := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(brander, Vector2i(0, 0))
	board.place(victim, Vector2i(3, 0))
	var controller := _controller_for(victim)
	var bus := MockBus.new()

	_plant_brand(brander, victim, board, bus)

	var hazard := TravelingHazard.new(
		Vector2i(0, 0), Vector2i(1, 0), 0, 3, 6, 20,
		CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, brander)
	hazard.event_bus = bus
	hazard.advance(board)

	assert_eq(victim.hp, 74, "the vine's 20 lands as 26 on a branded unit")
	assert_false(controller.has_status(&"branded"), "and the vine spends the brand")


func test_rebranding_refreshes_and_never_stacks():
	# CONQUEST.md rule 6. Two brands must never compound into x1.69.
	var brander := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(brander, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	var controller := _controller_for(victim)
	var bus := MockBus.new()

	_plant_brand(brander, victim, board, bus)
	_plant_brand(brander, victim, board, bus)
	_plant_brand(brander, victim, board, bus)

	assert_eq(controller.stack_count(&"branded"), 1,
		"three brands leave exactly one instance on the victim")
	assert_eq(controller.status_damage_taken_scale(), 1.3,
		"and one amplification, not 1.3 cubed")

	_strike(brander, victim, board, _flat_move(20), bus)
	assert_eq(victim.hp, 74, "so the next hit is 26, never 44")


func test_the_hit_that_plants_the_brand_is_not_itself_amplified():
	# The brand is planted FROM the damage announcement (ON_ATTACK), i.e. after the blow's
	# scales were read and before its HP is applied. Neither the number nor the brand may
	# move as a result: the branding hit deals plain damage and leaves the brand STANDING
	# for whatever comes next.
	var brander := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(brander, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	var controller := _controller_for(victim)
	var bus := MockBus.new()

	# Stand in for AbilitySystem: the brand is planted the instant the hit is announced.
	bus.damage_dealt.connect(func(_a, defender, _amount) -> void:
		if defender == victim and not controller.has_status(&"branded"):
			_plant_brand(brander, victim, board, bus))

	_strike(brander, victim, board, _flat_move(20), bus)

	assert_eq(victim.hp, 80, "the branding blow itself deals a plain 20")
	assert_true(controller.has_status(&"branded"),
		"and the brand it planted survives that same blow")


func test_a_negated_hit_does_not_spend_the_brand():
	# An invulnerable defender is announced with a literal 0. Nothing was taken, so the
	# brand is still owed its one amplification.
	var attacker := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	var controller := _controller_for(victim)
	var bus := MockBus.new()

	_plant_brand(attacker, victim, board, bus)
	controller.add_status(_submerged())
	_strike(attacker, victim, board, _flat_move(20), bus)

	assert_eq(victim.hp, 100, "the submerged victim took nothing")
	assert_true(controller.has_status(&"branded"),
		"so the brand is still owed its amplification")


func test_the_forecast_shows_the_amplified_number_without_spending_it():
	# CONQUEST.md rule 9: the panel and the blow share DamageMath, so the brand shows up
	# in the forecast for free -- and a forecast must never mutate anything.
	var attacker := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	var controller := _controller_for(victim)
	var bus := MockBus.new()
	var move := _flat_move(20)

	var clean: Dictionary = MoveExecutor.preview_vs(move, attacker, victim, board)
	assert_eq(int(clean["damage"]), 20, "unbranded forecast: 20")

	_plant_brand(attacker, victim, board, bus)

	var branded_forecast: Dictionary = MoveExecutor.preview_vs(move, attacker, victim, board)
	assert_eq(int(branded_forecast["damage"]), 26,
		"the forecast reports the amplified 26 against a branded target")
	assert_true(controller.has_status(&"branded"),
		"and previewing does not consume the brand")
	assert_eq(victim.hp, 100, "nor touch its HP")

	# ...and the number the forecast promised is the number the board applies.
	_strike(attacker, victim, board, move, bus)
	assert_eq(victim.hp, 74, "the resolved hit matches the forecast exactly")


func test_a_reduction_and_a_brand_land_on_opposite_sides_of_neutral():
	# The status aggregate takes the strongest of EACH side and multiplies the two -- a
	# reduction and a vulnerability are opposing sources, so neither may erase the other.
	var victim := StatusUnit.new(1, { "health": 100 })
	var controller := _controller_for(victim)

	var braced := StatusCondition.new()
	braced.id = &"test_braced"
	braced.duration_turns = 2
	braced.damage_taken_scale = 0.5
	controller.add_status(braced)
	assert_eq(controller.status_damage_taken_scale(), 0.5,
		"a lone reduction still reads as the minimum, exactly as before brands existed")

	controller.add_status(_branded())
	assert_almost_eq(controller.status_damage_taken_scale(), 0.65, 0.0001,
		"braced AND branded resolves to 0.5 x 1.3, not to one of them alone")


# ===========================================================================
# ABYSSAL MAW -- the delayed eruption
# ===========================================================================

## Cast Abyssal Maw from [param caster] at [param aim], returning the context.
func _cast_maw(caster, board, aim: Vector2i, bus) -> MoveContext:
	var move := _abyssal_maw()
	var origin: Vector2i = board.cell_of(caster)
	var cells := move.targeting.resolve_cells(origin, aim)
	var ctx := MoveContext.new(caster, board, move, aim, cells)
	ctx.event_bus = bus
	for effect in move.effects:
		effect.apply(ctx)
	return ctx


func test_the_maw_is_a_long_range_three_by_three_ground_mark():
	var move := _abyssal_maw()
	assert_not_null(move, "abyssal_maw.tres loads")
	assert_eq(move.targeting.min_range, 2, "it cannot be dropped on your own doorstep")
	assert_eq(move.targeting.max_range, 5, "and reaches five cells out")
	assert_eq(move.targeting.area_shape, CombatTypes.AreaShape.SQUARE,
		"the patch is a filled block")
	assert_eq(move.targeting.area_size, 1, "of Chebyshev radius 1 -- a 3x3")
	assert_eq(move.cooldown, 3, "and it is a 3-turn cooldown")
	assert_eq(move.element, &"dark", "dark, like the rest of the kit")


func test_casting_the_maw_telegraphs_the_patch_and_damages_nothing_yet():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(victim, Vector2i(4, 0))
	_controller_for(caster)
	var bus := MockBus.new()

	_cast_maw(caster, board, Vector2i(4, 0), bus)

	assert_eq(victim.hp, 100, "the cast turn deals no damage at all -- the maw is only armed")
	assert_eq(bus.advanced_calls.size(), 1, "one telegraph was announced")
	var telegraph: Dictionary = bus.advanced_calls[0]
	assert_eq((telegraph["cells"] as Array).size(), 0,
		"nothing is erupting yet, so the CURRENT band is empty")
	assert_eq((telegraph["next_cells"] as Array).size(), 9,
		"and the 3x3 patch is telegraphed as the band that erupts next")
	assert_true(Vector2i(4, 0) in (telegraph["next_cells"] as Array),
		"the aimed cell is in the marked patch")
	assert_true(caster.controller.has_status(&"void_maw_fuse"),
		"the caster carries the fuse that will set it off")


func test_the_fuse_expiring_erupts_the_maw_on_whoever_is_standing_in_it():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var inside := StatusUnit.new(1, { "health": 100 })
	var outside := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(inside, Vector2i(4, 0))
	board.place(outside, Vector2i(7, 0))
	var controller := _controller_for(caster)
	var bus := MockBus.new()

	_cast_maw(caster, board, Vector2i(4, 0), bus)
	# One tick of the caster's own turn-start status pass is the whole fuse.
	controller.tick_all(board)

	# power 24 + magic 10 = 34 raw, mitigated by 0 magic defense.
	assert_eq(inside.hp, 66, "a unit standing in the patch is bitten for 34")
	assert_eq(outside.hp, 100, "a unit outside it is untouched")
	assert_false(controller.has_status(&"void_maw_fuse"), "and the fuse is spent")
	assert_eq(bus.expired_calls.size(), 1, "the maw announces that it is finished")


func test_the_maw_credits_its_caster_and_spares_its_own_side():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var ally := StatusUnit.new(0, { "health": 100 })
	var enemy := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(ally, Vector2i(4, 1))
	board.place(enemy, Vector2i(4, 0))
	var controller := _controller_for(caster)
	var bus := MockBus.new()

	_cast_maw(caster, board, Vector2i(4, 0), bus)
	controller.tick_all(board)

	assert_eq(ally.hp, 100, "the maw is ENEMY-affiliated: it never bites its caster's side")
	assert_eq(enemy.hp, 66, "only the foe is bitten")
	assert_eq(bus.damage_calls.size(), 1, "one hit was announced")
	assert_eq(bus.damage_calls[0]["attacker"], caster,
		"credited to the caster, so a maw kill fires its ON_KILL")


func test_the_maw_bites_a_unit_that_walked_into_the_patch_after_the_cast():
	# The cells are frozen at cast; the occupants are read at detonation. Stepping in is a
	# mistake the player is allowed to make, and stepping out is the counterplay.
	var caster := StatusUnit.new(0, { "magic": 10 })
	var wanderer := StatusUnit.new(1, { "health": 100 })
	var bolter := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(wanderer, Vector2i(8, 8))   # far outside at cast time
	board.place(bolter, Vector2i(4, 0))     # inside at cast time
	var controller := _controller_for(caster)
	var bus := MockBus.new()

	_cast_maw(caster, board, Vector2i(4, 0), bus)
	board.move_unit(wanderer, Vector2i(3, 0))  # walks in
	board.move_unit(bolter, Vector2i(9, 9))    # walks out
	controller.tick_all(board)

	assert_eq(wanderer.hp, 66, "whoever is standing in it when it opens gets bitten")
	assert_eq(bolter.hp, 100, "and whoever stepped out is spared")


func test_the_maw_number_is_frozen_at_cast_time():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(victim, Vector2i(4, 0))
	var controller := _controller_for(caster)
	var bus := MockBus.new()

	_cast_maw(caster, board, Vector2i(4, 0), bus)
	caster.stats["magic"] = 100  # a buff lands while the fuse burns
	controller.tick_all(board)

	assert_eq(victim.hp, 66,
		"the eruption deals the 34 snapshotted at cast, not a number retuned mid-fuse")


func test_the_maw_erupts_identically_when_the_whole_cast_is_replayed():
	# Determinism pin: nothing in the arm/telegraph/erupt path touches a generator, so two
	# identical runs must be byte-identical.
	var runs: Array = []
	for _i in range(2):
		var caster := StatusUnit.new(0, { "magic": 10 })
		var a := StatusUnit.new(1, { "health": 100 })
		var b := StatusUnit.new(1, { "health": 100, "magic_defense": 9 })
		var board := MockBoard.new()
		board.place(caster, Vector2i(0, 0))
		board.place(a, Vector2i(4, 0))
		board.place(b, Vector2i(5, 1))
		var controller := _controller_for(caster)
		var bus := MockBus.new()
		_cast_maw(caster, board, Vector2i(4, 0), bus)
		controller.tick_all(board)
		runs.append([a.hp, b.hp, bus.damage_calls.size(), bus.expired_calls.size()])
	assert_eq(runs[0], runs[1],
		"the same cast replayed erupts for the same numbers on the same victims")


# ===========================================================================
# UMBRAL CLAW -- the piercing line
# ===========================================================================

func test_umbral_claw_is_a_three_cell_line():
	var move := _umbral_claw()
	assert_not_null(move, "umbral_claw.tres loads")
	assert_eq(move.targeting.area_shape, CombatTypes.AreaShape.LINE, "a straight run")
	assert_eq(move.targeting.area_size, 3, "three cells long")
	assert_eq(move.targeting.max_range, 1,
		"aimed at an adjacent cell, so the run covers exactly distance 1-3")
	assert_eq(move.cooldown, 1, "a 1-turn cooldown")
	assert_eq(move.element, &"dark", "dark")


func test_umbral_claw_covers_exactly_the_three_cells_ahead():
	var move := _umbral_claw()
	var cells := move.targeting.resolve_cells(Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(cells, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i],
		"the swipe runs three cells straight out from the caster")


func test_umbral_claw_hits_every_enemy_in_the_line_and_nothing_beside_it():
	var caster := StatusUnit.new(0, { "magic": 32 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	var in_line: Array = []
	for x in [1, 2, 3]:
		var e := StatusUnit.new(1, { "health": 100 })
		board.place(e, Vector2i(x, 0))
		in_line.append(e)
	var flank := StatusUnit.new(1, { "health": 100 })
	board.place(flank, Vector2i(2, 1))

	var move := _umbral_claw()
	var aim := Vector2i(1, 0)
	var ctx := MoveContext.new(caster, board, move, aim,
		move.targeting.resolve_cells(Vector2i(0, 0), aim))
	var gathered: Array = ctx.gather_targets()

	assert_eq(gathered.size(), 3, "all three enemies in the line are gathered")
	for e in in_line:
		assert_true(e in gathered, "each enemy standing in the swipe is hit")
	assert_false(flank in gathered, "a unit one cell off the line is not")


func test_umbral_claw_caps_at_three_enemies():
	# The cap is the GEOMETRY: the line is three cells, so a fourth enemy behind them is
	# simply out of the swipe.
	var caster := StatusUnit.new(0, { "magic": 32 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	var fourth: StatusUnit = null
	for x in [1, 2, 3, 4]:
		var e := StatusUnit.new(1, { "health": 100 })
		board.place(e, Vector2i(x, 0))
		if x == 4:
			fourth = e

	var move := _umbral_claw()
	var aim := Vector2i(1, 0)
	var ctx := MoveContext.new(caster, board, move, aim,
		move.targeting.resolve_cells(Vector2i(0, 0), aim))
	var gathered: Array = ctx.gather_targets()

	assert_eq(gathered.size(), 3, "never more than three")
	assert_false(fourth in gathered, "the fourth enemy in the row is out of reach")


func test_umbral_claw_spares_allies_standing_in_the_line():
	var caster := StatusUnit.new(0, { "magic": 32 })
	var ally := StatusUnit.new(0, { "health": 100 })
	var enemy := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(ally, Vector2i(1, 0))
	board.place(enemy, Vector2i(2, 0))

	var move := _umbral_claw()
	var aim := Vector2i(1, 0)
	var ctx := MoveContext.new(caster, board, move, aim,
		move.targeting.resolve_cells(Vector2i(0, 0), aim))
	var gathered: Array = ctx.gather_targets()

	assert_eq(gathered, [enemy], "an ENEMY-keyed line cuts past its own side")


# ===========================================================================
# VOIDWALK -- one turn of nothing touching it
# ===========================================================================

func test_voidwalk_applies_the_submerged_status_to_the_caster():
	var caster := StatusUnit.new(0, { "magic": 32 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	var controller := _controller_for(caster)

	var move := _voidwalk()
	var ctx := MoveContext.new(caster, board, move, Vector2i(0, 0),
		[Vector2i(0, 0)] as Array[Vector2i])
	for effect in move.effects:
		effect.apply(ctx)

	assert_true(controller.has_status(&"submerged"), "Voidwalk submerges its caster")
	assert_eq(move.cooldown, 4, "on a 4-turn cooldown")
	assert_true(controller.has_rule_flag(&"invulnerable"),
		"and the status carries the invulnerability flag the damage layer reads")


func test_a_submerged_unit_takes_nothing_from_an_attack():
	var attacker := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	_controller_for(victim).add_status(_submerged())
	var bus := MockBus.new()

	var ctx := _strike(attacker, victim, board, _flat_move(40), bus)

	assert_eq(victim.hp, 100, "a swing takes nothing off a submerged unit")
	var negated := false
	for e in ctx.results:
		if e.get("effect") == "damage" and bool(e.get("negated", false)):
			negated = true
	assert_true(negated, "and the log says the hit was NEGATED rather than reporting a bare 0")


func test_a_submerged_unit_takes_nothing_from_tile_or_hazard_damage():
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(victim, Vector2i(1, 0))
	_controller_for(victim).add_status(_submerged())

	# The environmental chain -- what a burning tile and a crawling vine both resolve
	# through -- short-circuits ahead of mitigation.
	assert_eq(DamageMath.environment_damage(victim, 40,
		CombatTypes.DamageCategory.MAGICAL, &"dark", board), 0,
		"environmental damage is a hard 0 against a submerged unit")

	# ...and the maw's own eruption is that same chain.
	var attacker := StatusUnit.new(0, { "magic": 0 })
	board.place(attacker, Vector2i(0, 0))
	var maw := DelayedBurstHazard.new([Vector2i(1, 0)] as Array[Vector2i], 40,
		CombatTypes.DamageCategory.MAGICAL, CombatTypes.TargetKind.ENEMY, attacker)
	maw.event_bus = MockBus.new()
	maw.detonate(board)
	assert_eq(victim.hp, 100, "an erupting maw cannot touch it either")


func test_the_forecast_reports_zero_against_a_submerged_unit():
	var attacker := StatusUnit.new(0, { "magic": 0 })
	var victim := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))
	_controller_for(victim).add_status(_submerged())

	var forecast: Dictionary = MoveExecutor.preview_vs(_flat_move(40), attacker, victim, board)
	assert_eq(int(forecast["damage"]), 0,
		"showing a mitigated number against a target that will take 0 would be a lie")


func test_the_bot_never_spends_its_turn_swinging_at_a_submerged_unit():
	# The AI skip. Targeting exclusion is deliberately NOT done in the shared gather path
	# (that would also make a submerged unit unhealable by its own side, and would silently
	# change what Guarded does), so the bot is stopped one layer up: an invulnerable target
	# estimates at 0, and both ranked-attack paths drop a candidate scoring <= 0.
	var actor := StatusUnit.new(0, { "attack": 10 })
	var submerged_enemy := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(submerged_enemy, Vector2i(1, 0))
	_controller_for(submerged_enemy).add_status(_submerged())

	var bot := BotController.new()
	var decision: Dictionary = bot.decide(actor, [MoveLibrary.basic_strike()], board)
	assert_ne(int(decision["action"]), BotController.ActionType.MOVE,
		"the bot does not attack a unit it cannot possibly hurt")

	# Control: the identical board with the status lifted IS attacked, so the test is
	# measuring the invulnerability and not some unrelated refusal.
	submerged_enemy.controller.remove_status(&"submerged")
	var after: Dictionary = bot.decide(actor, [MoveLibrary.basic_strike()], board)
	assert_eq(int(after["action"]), BotController.ActionType.MOVE,
		"and it attacks the same unit the moment it surfaces")


# ===========================================================================
# SHADOW DASH -- through the line, and moving again
# ===========================================================================

## Cast Shadow Dash from [param caster] toward [param aim].
func _cast_dash(caster, board, aim: Vector2i, bus) -> MoveContext:
	var move := _shadow_dash()
	var ctx := MoveContext.new(caster, board, move, aim, [aim] as Array[Vector2i])
	ctx.event_bus = bus
	for effect in move.effects:
		effect.apply(ctx)
	return ctx


func test_shadow_dash_runs_through_enemies_and_lands_on_the_first_free_cell():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	var victims: Array = []
	for x in [1, 2]:
		var e := StatusUnit.new(1, { "health": 100 })
		board.place(e, Vector2i(x, 0))
		victims.append(e)
	_controller_for(caster)
	var bus := MockBus.new()

	_cast_dash(caster, board, Vector2i(3, 0), bus)

	assert_eq(board.cell_of(caster), Vector2i(3, 0),
		"the caster comes to rest on the first free cell beyond the last enemy")
	# power 10 + magic 10 = 20 raw, mitigated by 0 magic defense.
	for v in victims:
		assert_eq(v.hp, 80, "every enemy it ran through takes the pass-through hit")


func test_shadow_dash_caps_at_three_enemies():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	var line: Array = []
	for x in [1, 2, 3, 4]:
		var e := StatusUnit.new(1, { "health": 100 })
		board.place(e, Vector2i(x, 0))
		line.append(e)
	_controller_for(caster)
	var bus := MockBus.new()

	_cast_dash(caster, board, Vector2i(2, 0), bus)

	assert_eq(board.cell_of(caster), Vector2i(0, 0),
		"a FOURTH body in the way stops the charge dead -- nobody moves")
	for e in line:
		assert_eq(e.hp, 100, "and a refused dash deals no damage at all")


func test_shadow_dash_refuses_cleanly_when_there_is_nowhere_to_land():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var enemy := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))
	board.block(Vector2i(2, 0))   # a wall right behind the enemy
	_controller_for(caster)
	var bus := MockBus.new()

	var ctx := _cast_dash(caster, board, Vector2i(1, 0), bus)

	assert_eq(board.cell_of(caster), Vector2i(0, 0), "the caster does not move")
	assert_eq(enemy.hp, 100, "and nothing is damaged")
	var refusal := {}
	for e in ctx.results:
		if e.get("effect") == "dash":
			refusal = e
	assert_false(bool(refusal.get("moved", true)), "the dash reports that it did not move")
	assert_eq(String(refusal.get("reason", "")), "no_free_cell",
		"...and says why, as a VALUE -- a refused dash is board state, never an error")


func test_shadow_dash_will_not_run_through_its_own_side():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var ally := StatusUnit.new(0, { "health": 100 })
	var enemy := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(ally, Vector2i(1, 0))
	board.place(enemy, Vector2i(2, 0))
	_controller_for(caster)
	var bus := MockBus.new()

	var ctx := _cast_dash(caster, board, Vector2i(2, 0), bus)

	assert_eq(board.cell_of(caster), Vector2i(0, 0), "an ally in the lane blocks the charge")
	assert_eq(ally.hp, 100, "the ally is never damaged")
	assert_eq(enemy.hp, 100, "and the enemy behind it is never reached")
	var refusal := {}
	for e in ctx.results:
		if e.get("effect") == "dash":
			refusal = e
	assert_eq(String(refusal.get("reason", "")), "blocked_line", "reported as a blocked line")


func test_shadow_dash_crosses_open_ground_to_reach_the_first_enemy():
	# Empty cells before the first enemy are run across, not landed on -- otherwise a dash
	# aimed down a corridor would stop one step out having hit nobody.
	var caster := StatusUnit.new(0, { "magic": 10 })
	var enemy := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy, Vector2i(3, 0))
	_controller_for(caster)
	var bus := MockBus.new()

	_cast_dash(caster, board, Vector2i(2, 0), bus)

	assert_eq(board.cell_of(caster), Vector2i(4, 0), "it lands past the enemy it found")
	assert_eq(enemy.hp, 80, "having run through it on the way")


func test_shadow_dash_resolves_identically_when_replayed():
	# Determinism pin: the lane walk, the landing rule and the damage all read only the
	# board and authored numbers -- no generator is touched.
	var runs: Array = []
	for _i in range(2):
		var caster := StatusUnit.new(0, { "magic": 10 })
		var board := MockBoard.new()
		board.place(caster, Vector2i(0, 0))
		var hps: Array = []
		var mobs: Array = []
		for x in [1, 2]:
			var e := StatusUnit.new(1, { "health": 100, "magic_defense": x })
			board.place(e, Vector2i(x, 0))
			mobs.append(e)
		_controller_for(caster)
		_cast_dash(caster, board, Vector2i(3, 0), MockBus.new())
		for m in mobs:
			hps.append(m.hp)
		runs.append([board.cell_of(caster), hps])
	assert_eq(runs[0], runs[1],
		"the same dash replayed lands on the same cell for the same damage")


func test_the_dash_grants_canto_on_a_shortened_leash():
	var caster := StatusUnit.new(0, { "magic": 10 })
	var enemy := StatusUnit.new(1, { "health": 100 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))
	var controller := _controller_for(caster)
	var bus := MockBus.new()

	_cast_dash(caster, board, Vector2i(1, 0), bus)

	assert_true(controller.has_status(&"void_surge"), "the dash leaves the caster surging")
	assert_eq(caster.canto_grants, 1,
		"which arms CANTO exactly once -- one more MOVEMENT, not one more action")
	assert_eq(caster.modifiers.size(), 1, "one stat modifier was taken")
	assert_eq(caster.modifiers[0]["stat"], "movement", "on movement")
	assert_eq(int(caster.modifiers[0]["amount"]), -2, "shortening the leash by 2")


func test_the_void_surge_never_touches_the_arena_action_budget():
	# The user decision this kit was rebuilt around: "they shouldn't be able to attack
	# after dashing, simply move". The Arena's act-twice budget is a DIFFERENT mechanic
	# and the dash must not reach for it -- if it did, the unit could strike again.
	var caster := StatusUnit.new(0, {})
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	var controller := _controller_for(caster)

	controller.add_status(_void_surge())

	assert_eq(caster.arena_extra_actions, 0,
		"Void Surge grants no extra ACTION at all -- the arena budget is left alone")
	assert_eq(caster.canto_grants, 1, "what it grants is the movement-only canto")


func test_the_void_surge_hands_the_stride_back_when_it_expires():
	var caster := StatusUnit.new(0, {})
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	var controller := _controller_for(caster)

	controller.add_status(_void_surge())
	assert_eq(caster.canto_grants, 1, "granted")

	controller.tick_all(board)

	assert_false(controller.has_status(&"void_surge"), "it is a one-turn grant")
	assert_true(bool(caster.modifiers[0].get("removed", false)),
		"and the movement penalty is revoked when it goes")


func test_the_void_surge_refreshes_and_never_stacks():
	# CONQUEST.md rule 6: two dashes in one turn must not bank two movements or double
	# the slow -- and expiry must then return exactly what was taken, once.
	var caster := StatusUnit.new(0, {})
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	var controller := _controller_for(caster)

	controller.add_status(_void_surge())
	controller.add_status(_void_surge())
	controller.add_status(_void_surge())

	assert_eq(controller.stack_count(&"void_surge"), 1, "one instance")
	assert_eq(caster.canto_grants, 1, "canto armed once, not three times")
	assert_eq(caster.modifiers.size(), 1, "one movement penalty, not three")

	controller.tick_all(board)
	assert_true(bool(caster.modifiers[0].get("removed", false)),
		"and it all comes back exactly once")


# ===========================================================================
# THE CHARACTER
# ===========================================================================

func test_the_monster_roster_entry_loads_and_validates():
	var character := load("res://game/characters/roster/monster.tres") as CharacterResource
	assert_not_null(character, "monster.tres loads as a CharacterResource")
	assert_eq(character.character_id, &"monster", "its id is 'monster'")
	assert_eq(character.element, &"dark", "it is a dark unit")
	assert_eq(character.model_yaw_deg, 180.0,
		"yawed 180 like the rest of the roster -- the sculpts face -Y in Blender")
	assert_not_null(character.model_scene, "and it carries its imported model")
	var validation: Dictionary = character.validate()
	assert_true(bool(validation["valid"]),
		"the resource passes its own content check: %s" % str(validation["issues"]))


func test_the_monster_is_a_squishier_faster_ranged_caster():
	var character := load("res://game/characters/roster/monster.tres") as CharacterResource
	var mortis := load("res://game/characters/roster/necromancer.tres") as CharacterResource
	assert_true(character.base_magic > character.base_attack,
		"it scales on magic, like the other ranged dark caster")
	assert_true(character.base_health < mortis.base_health,
		"squishier than Mortis")
	assert_true(character.base_defense < mortis.base_defense
		and character.base_magic_defense < mortis.base_magic_defense,
		"...on both defences")
	assert_true(character.base_speed > mortis.base_speed, "and faster")
	assert_true(character.base_movement > mortis.base_movement, "with a longer stride")
	assert_true(character.attack_range >= 3, "it is a long-range attacker")


func test_the_moveset_and_passive_are_intact():
	var character := load("res://game/characters/roster/monster.tres") as CharacterResource
	assert_eq(character.move_count(), 4, "all four moves are authored")
	var ids: Array = []
	for i in range(character.move_count()):
		ids.append(character.get_move(i).move_id)
	assert_eq(ids, [&"abyssal_maw", &"umbral_claw", &"voidwalk", &"shadow_dash"],
		"in the authored order")
	for i in range(character.move_count()):
		assert_eq(character.get_move(i).element, &"dark", "every move is dark")
	assert_eq(character.ability_count(), 1, "one passive")
	assert_eq(character.abilities[0].id, &"dread_brand", "and it is Dread Brand")


func test_character_library_picks_the_roster_file_up():
	# CharacterLibrary SCANS res://game/characters/roster/ -- there is no registration list
	# to edit -- so dropping the .tres in is the whole wiring. This pins that, and pins the
	# id-keyed load path every spawn uses.
	CharacterLibrary.clear_cache()
	assert_true(&"monster" in CharacterLibrary.all_ids(),
		"the directory scan lists the new character")
	var character: CharacterResource = CharacterLibrary.get_character(&"monster")
	assert_not_null(character, "and it resolves by id")
	assert_eq(character.display_name, "Duskmaw", "with its display name")
	CharacterLibrary.clear_cache()


func test_the_creature_is_named_duskmaw_and_its_fiction_says_so():
	# The id stays &"monster" -- the .glb, the roster filename and every spawn path are
	# keyed on it -- so this is a DISPLAY-ONLY rename and the two must not drift.
	var character := load("res://game/characters/roster/monster.tres") as CharacterResource
	assert_eq(character.display_name, "Duskmaw",
		"the roster creature-compound name, like Petalfang / Blightcap / Timberfall")
	assert_eq(character.character_id, &"monster",
		"while the id -- which the model path and every spawn are keyed on -- is unchanged")
	assert_eq(character.display_name.split(" ").size(), 1,
		"one word: it is not a boss (CONQUEST.md, Units/Names)")
	assert_string_contains(character.description, "Duskmaw",
		"and the fiction names the creature rather than describing an anonymous thing")


func test_the_unit_gallery_can_build_a_row_for_it():
	# Exactly what UnitGallery._load_all_characters does: every id from the scan that
	# resolves becomes a gallery entry. A character that failed either half would simply
	# be missing from the compendium with no error anywhere, so it is pinned here.
	CharacterLibrary.clear_cache()
	var listed: Array = []
	for character_id in CharacterLibrary.all_ids():
		var character: CharacterResource = CharacterLibrary.get_character(character_id)
		if character != null:
			listed.append(character.character_id)
	assert_true(&"monster" in listed, "the gallery's own load pass includes Monster")
	CharacterLibrary.clear_cache()
