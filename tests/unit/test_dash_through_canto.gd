extends GutTest

# THE DASH-THROUGH + CANTO ENGINE, on its own.
#
# [DashThroughEffect] (charge through a line of bodies, land on the first free cell beyond)
# and [CantoStatus] / Void Surge (having acted, still owe exactly ONE movement, on a
# shortened stride) are GENERIC mechanics. They shipped as Duskmaw's Shadow Dash and were
# tested there; Duskmaw's slot 3 is now VOIDSTEP (see tests/integration/test_voidstep.gd),
# so these tests MIGRATED here rather than being retired with the kit slot. The machinery is
# kept deliberately: it is what a future charger character is built from.
#
# `game/combat/moves/shadow_dash.tres` is still the authored exemplar -- no character's
# moveset references it any more, and this suite is the only thing that loads it. Read it as
# the reference authoring of a dash, not as live content.
#
# Everything here is pure mocks + resources: no scene tree, no autoloads, no disk. The
# fixtures are the ones the kit suite used, copied rather than shared, because
# `tests/helpers/test_doubles.gd` is deliberately not allowed to grow a method per caller
# (tests/README rule 5) and these two need `move_unit` + blocked terrain + a canto sink.


# --- Mocks -----------------------------------------------------------------

## Stand-in for the GameEvents autoload, injected via MoveContext.event_bus: the real
## signal is typed (Unit, Unit, int) and rejects mocks.
class MockBus:
	extends RefCounted
	signal damage_dealt(attacker, defender, amount)
	var damage_calls: Array = []
	func _init() -> void:
		damage_dealt.connect(_on_damage)
	func _on_damage(attacker, defender, amount) -> void:
		damage_calls.append({ "attacker": attacker, "defender": defender, "amount": amount })


## A duck-typed unit with a real [StatusController] hanging off it.
##
## The controller is a Node, so it is NOT created here: tests/README.md rule 2 warns that a
## RefCounted double constructing a Node in _init leaks it past every autofree. It is built
## in the test body with autofree() and handed in.
class StatusUnit:
	extends RefCounted
	var team: int
	var stats: Dictionary
	var hp: int
	## How many times CantoStatus armed the movement-only grant on this unit. A COUNT, not a
	## bool, so "refresh never grants twice" is provable.
	var canto_grants: int = 0
	## The Arena's full-extra-action budget, present so a test can prove the canto path never
	## touches it (that mechanic is a different one, and unused here).
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


## Placement, allegiance, and the two mutators a dash needs (move_unit) plus a
## blocked-terrain set so the "nowhere to land" edge case can be built without a live map.
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


# --- Fixtures --------------------------------------------------------------

func _void_surge() -> StatusCondition:
	return load("res://game/combat/status/void_surge.tres") as StatusCondition


func _shadow_dash() -> MoveResource:
	return load("res://game/combat/moves/shadow_dash.tres") as MoveResource


## A controller wired to [param unit], registered for automatic freeing.
func _controller_for(unit) -> StatusController:
	var controller: StatusController = autofree(StatusController.new())
	controller.owner_unit = unit
	unit.controller = controller
	return controller


## Cast the dash from [param caster] toward [param aim].
func _cast_dash(caster, board, aim: Vector2i, bus) -> MoveContext:
	var move := _shadow_dash()
	var ctx := MoveContext.new(caster, board, move, aim, [aim] as Array[Vector2i])
	ctx.event_bus = bus
	for effect in move.effects:
		effect.apply(ctx)
	return ctx


# ===========================================================================
# DASH THROUGH -- the lane walk and the landing rule
# ===========================================================================

func test_a_dash_runs_through_enemies_and_lands_on_the_first_free_cell():
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


func test_a_dash_caps_at_the_authored_pierce_count():
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


func test_a_dash_refuses_cleanly_when_there_is_nowhere_to_land():
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


func test_a_dash_will_not_run_through_its_own_side():
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


func test_a_dash_crosses_open_ground_to_reach_the_first_enemy():
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


func test_a_dash_resolves_identically_when_replayed():
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


# ===========================================================================
# CANTO -- it has acted, and still owes ONE movement
# ===========================================================================

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
	# The user decision this machinery was rebuilt around: "they shouldn't be able to attack
	# after dashing, simply move". The Arena's act-twice budget is a DIFFERENT mechanic and
	# the canto grant must not reach for it -- if it did, the unit could strike again.
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
	# CONQUEST.md rule 6: two dashes in one turn must not bank two movements or double the
	# slow -- and expiry must then return exactly what was taken, once.
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


func test_the_dash_exemplar_is_no_longer_in_any_characters_kit():
	# The kit reference was REMOVED, the machinery kept. If a future character picks the dash
	# up, this test is the one to delete -- deliberately, with the new kit's own coverage.
	var duskmaw := load("res://game/characters/roster/monster.tres") as CharacterResource
	assert_not_null(duskmaw, "the roster entry loads")
	if duskmaw == null:
		return
	var ids: Array = []
	for move in duskmaw.moveset:
		if move != null:
			ids.append(move.move_id)
	assert_false(ids.has(&"shadow_dash"),
		"Duskmaw no longer carries Shadow Dash -- its slot 3 is Voidstep")
	assert_not_null(_shadow_dash(),
		"but the authored exemplar is still on disk, and this suite still exercises it")
