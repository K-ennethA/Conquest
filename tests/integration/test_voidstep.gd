extends GutTest

## VOIDSTEP -- Duskmaw's teleport anchor. ONE move with TWO resolutions, chosen by what is
## aimed at: free ground within 4 PLANTS a void spot, one of the caster's OWN spots (at any
## distance the move reaches) STEPS onto it.
##
## Integration rather than unit because the anchors themselves live in the real
## [CombatServices] APPLIED tile-effect layer -- the same layer a planted trap uses, and the
## only layer the expiry sweep is allowed to walk. That is an autoload, so it is cleared in
## BOTH hooks (tests/README rule 3); GUT runs `after_each` even when a test fails.
##
## What each section pins:
##   * PLACEMENT   -- the spot lands stamped with its owner, this caster's identity, and a
##                    12-turn clock frozen at cast time.
##   * THE CAP     -- three per caster; a fourth evicts the OLDEST, identically on two runs.
##   * EXPIRY      -- runs out on schedule in a PLAIN SKIRMISH (no mode armed) under BOTH
##                    turn systems, driven by TileEffectSystem's own turn hook.
##   * TELEPORT    -- relocates through the board and announces itself on the ONE move-apply
##                    seam, so the destination's terrain (a trap included) resolves; does not
##                    consume the spot; refused while a body stands on it.
##   * COOLDOWN    -- short after a placement, long after a step, with the recharge readout
##                    counting down from the wait that actually ran, and a snapshot that
##                    carries it.
##   * TARGETING   -- the aim rule that the highlight, the executor and the effect all share.

const Doubles := preload("res://tests/helpers/test_doubles.gd")


## A unit that reports an OWNING PLAYER -- which is the one thing the stomp rule reads off a
## unit to tell the anchor's own side from everybody else. Deliberately its own small class
## rather than a method bolted onto a shared double: the production code is duck-typed, and
## giving `Doubles.CombatUnit` a `get_owner_player` would silently reroute every suite that
## uses it through the placed-owner branch of TileEffectResource._faction_ok
## (tests/README rule 5). Pass a null player to model a NEUTRAL.
class OwnedUnit:
	extends RefCounted
	var team: int
	var player = null
	func _init(p_team: int, p_player = null) -> void:
		team = p_team
		player = p_player
	func get_owner_player():
		return player
	func get_stat(_stat_name: String) -> int:
		return 0
	func take_damage(_n: int) -> void:
		pass

const VOIDSTEP_PATH := "res://game/combat/moves/voidstep.tres"
const SPOT_PATH := "res://game/tiles/effects/resources/void_spot.tres"

## Duskmaw's authored numbers, asserted against the .tres in one place so the fixtures below
## may use faster ones without the suite quietly drifting off the shipped balance.
const AUTHORED_PLACE_RANGE := 4
const AUTHORED_LIFETIME := 12
const AUTHORED_MAX_SPOTS := 3
const AUTHORED_TELEPORT_CD := 4
const AUTHORED_PLACE_CD := 1


func before_each() -> void:
	CombatServices.clear()
	ModeTuning.clear()


func after_each() -> void:
	TurnSystemManager.active_turn_system = null
	ModeTuning.clear()
	CombatServices.clear()


# --- Fixtures ------------------------------------------------------------------


func _spot() -> TileEffectResource:
	return load(SPOT_PATH) as TileEffectResource


func _authored_move() -> MoveResource:
	return load(VOIDSTEP_PATH) as MoveResource


## The authored effect off the authored move -- the same object the move's targeting pattern
## points at as its aim rule.
func _authored_effect() -> VoidstepEffect:
	var move := _authored_move()
	if move == null or move.effects.is_empty():
		return null
	return move.effects[0] as VoidstepEffect


## A code-built Voidstep whose lifetime/cap can be dialled down, so the lifecycle tests do
## not have to drive twelve rounds of turns to watch one anchor expire. Everything else --
## the placement, the stamp, the eviction, the cooldown hook -- is the shipped code path.
func _effect(lifetime: int = 3, cap: int = 3, teleport_cd: int = AUTHORED_TELEPORT_CD) -> VoidstepEffect:
	var e := VoidstepEffect.new()
	e.spot = _spot()
	e.place_range = AUTHORED_PLACE_RANGE
	e.lifetime_turns = lifetime
	e.max_spots = cap
	e.teleport_cooldown = teleport_cd
	return e


## A move carrying [param effect], so a cast can go through the real executor. Slot-agnostic:
## the roster's slot-3 placement is pinned in `unit/test_monster_kit.gd`.
func _move_for(effect: VoidstepEffect) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"voidstep"
	m.display_name = "Voidstep"
	m.element = &"dark"
	m.category = CombatTypes.DamageCategory.MAGICAL
	m.cooldown = AUTHORED_PLACE_CD
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.EMPTY_TILE
	p.min_range = 1
	p.max_range = 12
	p.area_shape = CombatTypes.AreaShape.SINGLE
	p.aim_rule = effect
	m.targeting = p
	m.effects = [effect] as Array[MoveEffect]
	return m


## A LIVE [Unit] -- needed, not a double: the cooldown hook reads a real
## [MovesetController] child and the relocation announcement is a TYPED signal that rejects
## a mock. Built from a code character so no model has to import.
func _caster(player_id: int = 0) -> Unit:
	var c := CharacterResource.new()
	c.character_id = &"voidstep_caster"
	c.display_name = "Duskmaw"
	c.base_health = 78
	c.base_attack = 9
	c.base_magic = 32
	c.base_speed = 14
	c.base_movement = 5
	var u := Unit.new()
	u.character_resource = c
	var p := Player.new()
	p.player_id = player_id
	u.owner_player = p
	add_child_autofree(u)
	return u


## Resolve [param effect] for [param caster] aimed at [param cell], through a real
## [MoveContext] over [param board]. Returns the context so the event log can be read.
func _cast(effect: VoidstepEffect, caster, board, cell: Vector2i, move: MoveResource = null) -> MoveContext:
	var m: MoveResource = move if move != null else _move_for(effect)
	var ctx := MoveContext.new(caster, board, m, cell, [cell] as Array[Vector2i])
	effect.apply(ctx)
	return ctx


## Every cell currently carrying at least one runtime placement, row-major.
func _placed_cells() -> Array:
	var cells: Array = CombatServices.applied_effect_cells()
	cells.sort()
	return cells


func _spot_at(cell: Vector2i):
	for te in CombatServices.applied_tile_effects_at(cell):
		if te != null and String(te.id) == "void_spot":
			return te
	return null


# ===========================================================================
# PLACEMENT
# ===========================================================================


func test_the_authored_move_is_the_shipped_shape() -> void:
	var move := _authored_move()
	assert_not_null(move, "voidstep.tres loads")
	if move == null:
		return
	assert_eq(move.move_id, &"voidstep", "it is the move it says it is")
	assert_eq(move.element, &"dark", "and it is dark, like everything else Duskmaw does")
	assert_eq(move.cooldown, AUTHORED_PLACE_CD,
		"the AUTHORED cooldown is the SHORT one -- planting an anchor is cheap")
	assert_true(move.is_valid(), "it has both a pattern and an effect")

	var effect := _authored_effect()
	assert_not_null(effect, "its one effect is the Voidstep resolution")
	if effect == null:
		return
	assert_eq(effect.place_range, AUTHORED_PLACE_RANGE, "anchors are planted within 4")
	assert_eq(effect.lifetime_turns, AUTHORED_LIFETIME, "and last 12 turns")
	assert_eq(effect.max_spots, AUTHORED_MAX_SPOTS, "three at a time, never four")
	assert_eq(effect.teleport_cooldown, AUTHORED_TELEPORT_CD,
		"and STEPPING costs 4 turns -- the long half of the move's price")
	assert_not_null(effect.spot, "it knows which anchor it plants")


func test_the_move_and_its_targeting_share_ONE_aim_rule_object() -> void:
	# Not "they agree": they are the SAME resource, so they cannot drift. This is what makes
	# the lit tiles and the cells that actually resolve one answer.
	var move := _authored_move()
	if move == null or move.targeting == null:
		return
	assert_same(move.targeting.aim_rule, move.effects[0],
		"the pattern's aim rule IS the move's own effect -- one definition of a legal cell")


func test_a_placement_lands_an_anchor_stamped_with_its_owner_and_a_clock() -> void:
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))

	var effect := _effect(AUTHORED_LIFETIME)
	var ctx := _cast(effect, caster, board, Vector2i(2, 0))

	var placed = _spot_at(Vector2i(2, 0))
	assert_not_null(placed, "the anchor is on the board's runtime layer")
	if placed == null:
		return
	assert_eq(placed.owner_player, caster.get_owner_player(),
		"stamped with the placer's player, exactly as a planted trap is")
	assert_true(placed.is_runtime_placement(),
		"it is a runtime PLACEMENT, not authored terrain -- only those may ever be swept")
	assert_eq(placed.expires_on_round, placed.placed_round + AUTHORED_LIFETIME,
		"with its expiry FROZEN at cast time: the round it went down plus the authored 12")
	assert_true(_event(ctx, "place").get("placed", false), "and the cast reports it planted one")


func test_the_authored_resource_is_never_stamped() -> void:
	# CONQUEST.md rule 7: the .tres is loaded once and handed to every caster, so the owner
	# and the placement record have to land on a per-cast DUPLICATE.
	var shared := _spot()
	var effect := _effect()
	effect.spot = shared
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))

	_cast(effect, caster, board, Vector2i(1, 0))

	assert_null(shared.owner_player, "the shared anchor resource has no owner")
	assert_eq(shared.placed_round, -1, "and no placement record was written onto it")
	assert_false(_spot_at(Vector2i(1, 0)) == shared, "the board holds a copy, not the original")


func test_the_anchor_does_nothing_at_all_to_whoever_stands_on_it() -> void:
	# It is a MARKER. Anything else would make Duskmaw's own escape route a trap for its
	# allies, and would make a pure-anchor tile indistinguishable from a hazard.
	var spot := _spot()
	assert_eq(spot.trigger, TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING,
		"it is a standing STATE, not a per-event mutation")
	assert_true(spot.effects.is_empty(), "with no payload whatsoever")
	assert_true(spot.rule_flags.is_empty(), "and no rule flags for anything to read off it")
	assert_false(spot.is_pass_trap(), "it never springs on a unit crossing it")
	assert_eq(spot.move_cost_bonus, 0, "and it costs nothing extra to walk over")


func test_a_placement_onto_occupied_or_distant_ground_is_a_quiet_no_op() -> void:
	# CONQUEST.md rule 1: a foreseeable refusal is a VALUE, never an engine error.
	var caster := _caster()
	var other := Doubles.CombatUnit.new(1, {})
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(other, Vector2i(1, 0))
	var effect := _effect()

	var on_body := _cast(effect, caster, board, Vector2i(1, 0))
	assert_false(_event(on_body, "place").get("placed", true),
		"an anchor cannot be planted under a body")
	var too_far := _cast(effect, caster, board, Vector2i(9, 0))
	assert_false(_event(too_far, "place").get("placed", true),
		"nor beyond the planting reach of 4")
	assert_eq(_placed_cells().size(), 0, "and neither refusal left anything on the board")


# ===========================================================================
# THE CAP -- three per caster, oldest evicted
# ===========================================================================


func test_a_fourth_anchor_evicts_the_oldest_and_only_the_oldest() -> void:
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect(AUTHORED_LIFETIME, 3)

	for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		_cast(effect, caster, board, cell)
	assert_eq(_placed_cells().size(), 3, "three anchors stand")

	var ctx := _cast(effect, caster, board, Vector2i(0, 1))

	assert_eq(_placed_cells(), [Vector2i(0, 1), Vector2i(2, 0), Vector2i(3, 0)],
		"the FIRST anchor is gone and the newest took its place -- never four at once")
	assert_eq(_event(ctx, "evict").get("cell", null), Vector2i(1, 0),
		"and the cast names which one it gave up")


func test_the_cap_is_PER_CASTER_and_never_shared_between_two_of_them() -> void:
	var one := _caster(0)
	var two := _caster(0)
	two.owner_player = one.get_owner_player()  # the SAME side, deliberately: the cap is per
	                                           # UNIT, so two Duskmaws on one team get three each
	var board := Doubles.CombatBoard.new()
	board.place(one, Vector2i(0, 0))
	board.place(two, Vector2i(0, 5))
	var effect := _effect(AUTHORED_LIFETIME, 3)

	for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		_cast(effect, one, board, cell)
	for cell in [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)]:
		_cast(effect, two, board, cell)

	assert_eq(_placed_cells().size(), 6,
		"two Duskmaws hold three anchors EACH -- one of them planting does not evict the other's")
	assert_eq(VoidstepEffect.own_spot_cells(one).size(), 3, "three belong to the first")
	assert_eq(VoidstepEffect.own_spot_cells(two).size(), 3, "and three to the second")


func test_two_identical_runs_evict_the_same_anchors_in_the_same_order() -> void:
	var runs: Array = []
	for _run in range(2):
		CombatServices.clear()
		var caster := _caster()
		var board := Doubles.CombatBoard.new()
		board.place(caster, Vector2i(0, 0))
		var effect := _effect(AUTHORED_LIFETIME, 3)
		var signature: Array = []
		for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
				Vector2i(0, 1), Vector2i(0, 2), Vector2i(4, 0)]:
			var ctx := _cast(effect, caster, board, cell)
			signature.append("%s->%s" % [str(cell), str(_event(ctx, "evict").get("cell", null))])
			signature.append(str(_placed_cells()))
		runs.append(signature)

	assert_gt((runs[0] as Array).size(), 0, "the run produced a timeline to compare")
	assert_eq(runs[0], runs[1],
		"the eviction order is pure arithmetic on frozen stamps -- no RNG, no clock, so two "
		+ "lockstep peers drop the same anchor")


# ===========================================================================
# EXPIRY -- on schedule, in a PLAIN SKIRMISH, under both turn systems
# ===========================================================================


## A live [TileEffectSystem] driving its own expiry sweep off [param ts], exactly as
## GameWorldManager mounts one. [param ts] must already be the ACTIVE system.
func _expiry_system() -> TileEffectSystem:
	var sys: TileEffectSystem = TileEffectSystem.new()
	sys.name = "TileEffectSystem"
	add_child_autofree(sys)
	sys.setup()
	return sys


func _players(ts: TurnSystemBase, count: int = 2) -> Array:
	var out: Array = []
	for i in range(count):
		var p := Player.new(i, "P%d" % i)
		ts.register_player(p)
		out.append(p)
	return out


func test_anchors_expire_on_schedule_in_a_plain_skirmish_under_traditional() -> void:
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var players := _players(ts)
	ts.current_turn = 1
	TurnSystemManager.active_turn_system = ts
	_expiry_system()
	assert_false(ModeTuning.has_mode(), "no mode is armed -- this is a plain skirmish")

	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(2), caster, board, Vector2i(2, 0))
	var placed = _spot_at(Vector2i(2, 0))
	assert_not_null(placed, "the anchor is down")
	if placed == null:
		return
	var due: int = placed.expires_on_round

	# Traditional counts a ROUND as one pass through its registered players, so the round the
	# sweep reads is derived from current_turn. Drive the boundary the sweep actually rides.
	for turn in range(1, (due + 1) * players.size() + 1):
		ts.current_turn = turn
		ts.turn_started.emit(players[(turn - 1) % players.size()])
		if ModeTuning.current_round() < due:
			assert_not_null(_spot_at(Vector2i(2, 0)),
				"it is still there before its round: an AUTHORED lifetime is honoured to the turn")

	assert_null(_spot_at(Vector2i(2, 0)),
		"and it is swept off the board on its round -- with no mode armed, no ruleset consulted")


func test_anchors_expire_on_the_same_schedule_under_speed_first() -> void:
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	var players := _players(ts)
	TurnSystemManager.active_turn_system = ts
	_expiry_system()

	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(2), caster, board, Vector2i(2, 0))
	var placed = _spot_at(Vector2i(2, 0))
	if placed == null:
		assert_not_null(placed, "the anchor is down")
		return
	var due: int = placed.expires_on_round

	# Speed First keeps a real round_number, so the same sweep reads it straight off.
	for r in range(1, due):
		ts.round_number = r
		ts.turn_started.emit(players[0])
	assert_not_null(_spot_at(Vector2i(2, 0)), "still standing the round before it is due")

	ts.round_number = due
	ts.turn_started.emit(players[0])
	assert_null(_spot_at(Vector2i(2, 0)),
		"and gone on its round -- the schedule does not depend on which turn system is running")


func test_the_anchors_are_not_bound_to_their_caster_and_so_outlive_it() -> void:
	# The authored call: an anchor is terrain the caster left behind, not a summon bound to
	# it. That is STRUCTURAL rather than a rule someone remembered to skip -- the placed copy
	# holds an instance ID and a player, never a reference to the unit, so there is nothing
	# for a death to unwind and no cleanup hook to forget.
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(), caster, board, Vector2i(2, 0))

	var placed = _spot_at(Vector2i(2, 0))
	assert_not_null(placed, "the anchor is down")
	if placed == null:
		return
	var stamp = placed.get_meta(VoidstepEffect.OWNER_META)
	assert_eq(typeof(stamp), TYPE_INT,
		"the caster is remembered as an ID, not held as an object")
	assert_eq(int(stamp), caster.get_instance_id(), "and it is this caster's ID")
	assert_eq(_placed_cells().size(), 1,
		"so the anchor is board state from the moment it lands, on its own clock")


# ===========================================================================
# TELEPORT
# ===========================================================================


func test_a_teleport_relocates_the_caster_onto_its_own_anchor() -> void:
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	_cast(effect, caster, board, Vector2i(3, 0))

	var ctx := _cast(effect, caster, board, Vector2i(3, 0))

	assert_eq(board.cell_of(caster), Vector2i(3, 0), "the caster is standing on its anchor")
	assert_true(_event(ctx, "teleport").get("moved", false), "and the cast reports the step")


func test_a_teleport_CONSUMES_the_anchor_it_arrives_on() -> void:
	# A tear is a ONE-WAY door: stepping through closes it. Keeping an escape route means
	# keeping planting, which is what stops three anchors being a permanent free retreat.
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	_cast(effect, caster, board, Vector2i(3, 0))
	assert_eq(VoidstepEffect.own_spot_cells(caster).size(), 1, "one anchor stands")

	var ctx := _cast(effect, caster, board, Vector2i(3, 0))

	assert_null(_spot_at(Vector2i(3, 0)), "stepping through spent the anchor")
	assert_true(_event(ctx, "teleport").get("consumed", false), "and the cast says so")
	assert_eq(VoidstepEffect.own_spot_cells(caster).size(), 0,
		"which frees one of the caster's three slots the instant it happens")


func test_spending_an_anchor_frees_a_slot_without_evicting_anything() -> void:
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect(AUTHORED_LIFETIME, 3)
	for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		_cast(effect, caster, board, cell)

	_cast(effect, caster, board, Vector2i(3, 0))          # step through the third
	board.move_unit(caster, Vector2i(0, 0))
	var ctx := _cast(effect, caster, board, Vector2i(0, 1))  # plant a fresh one

	assert_eq(_event(ctx, "evict"), {},
		"the cap had room again, so nothing had to be given up")
	assert_eq(_placed_cells(), [Vector2i(0, 1), Vector2i(1, 0), Vector2i(2, 0)],
		"the two survivors plus the new anchor -- the spent one simply is not there")


func test_a_teleport_is_refused_while_a_body_stands_on_the_anchor() -> void:
	var caster := _caster()
	var squatter := Doubles.CombatUnit.new(1, {})
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	_cast(effect, caster, board, Vector2i(3, 0))
	board.place(squatter, Vector2i(3, 0))

	var ctx := _cast(effect, caster, board, Vector2i(3, 0))

	assert_eq(board.cell_of(caster), Vector2i(0, 0), "the caster did not move")
	assert_false(_event(ctx, "teleport").get("moved", true),
		"an occupied anchor is closed -- and refusing it is a VALUE, never an error")
	assert_false(effect.allows_aim(Vector2i(0, 0), Vector2i(3, 0), caster, board),
		"so the targeting layer will not offer it either, and the two agree by construction")


func test_a_teleport_announces_itself_on_the_one_move_apply_seam() -> void:
	# GameEvents.unit_moved is the ONLY seam GameWorldManager hangs the terrain side of a
	# move off, so announcing it IS the whole integration: ON_EXIT on the cell left, ON_ENTER
	# on the cell arrived at. In GRID space -- Vector3(col, 0, row) -- never metres
	# (CONQUEST.md rule 5).
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	_cast(effect, caster, board, Vector2i(3, 0))

	# GUT lambdas capture BY VALUE, so the announcement is collected through a shared Array.
	var seen: Array = []
	var sink := func(u, from, to) -> void: seen.append({ "unit": u, "from": from, "to": to })
	GameEvents.unit_moved.connect(sink)
	_cast(effect, caster, board, Vector2i(3, 0))
	GameEvents.unit_moved.disconnect(sink)

	assert_eq(seen.size(), 1, "the step announced itself exactly once")
	if seen.is_empty():
		return
	assert_eq(seen[0]["from"], Vector3(0, 0, 0), "from the cell it left")
	assert_eq(seen[0]["to"], Vector3(3, 0, 0), "to the anchor it arrived on, in GRID coords")


func test_a_trap_waiting_on_the_anchor_springs_the_instant_the_caster_arrives() -> void:
	# What GameWorldManager._on_unit_moved_tile_effects does with that announcement, run
	# here against a real TileEffectSystem: arriving somewhere is arriving, and the ground
	# gets its say. Teleporting onto a mined anchor is meant to hurt.
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	_cast(effect, caster, board, Vector2i(3, 0))

	var mine := TileEffectResource.new()
	mine.id = &"test_mine"
	mine.trigger = TileEffectResource.Trigger.ON_ENTER
	var bite := DamageEffect.new()
	bite.power = 11
	bite.category = CombatTypes.DamageCategory.TRUE
	mine.effects = [bite] as Array[MoveEffect]
	CombatServices.add_tile_effect(Vector2i(3, 0), mine)

	var before: int = caster.get_hp()
	var sys: TileEffectSystem = add_child_autofree(TileEffectSystem.new())
	_cast(effect, caster, board, Vector2i(3, 0))
	sys.tile_effects[Vector2i(3, 0)] = CombatServices.tile_effects_at(Vector2i(3, 0))
	sys.apply_move(caster, Vector2i(0, 0), Vector2i(3, 0), board)
	assert_eq(board.cell_of(caster), Vector2i(3, 0), "the step landed on the mined anchor")

	assert_lt(caster.get_hp(), before,
		"the mine on the anchor bit the arriving caster -- ON_ENTER resolves for a teleport "
		+ "exactly as it does for a walk, because it is the same seam")
	assert_null(_spot_at(Vector2i(3, 0)), "and the anchor was spent by the step through it")
	assert_eq(CombatServices.applied_tile_effects_at(Vector2i(3, 0)).size(), 1,
		"while the mine stays put: spending an anchor takes the anchor and nothing else")


func test_an_enemy_stomping_a_mined_anchor_takes_the_mine_AND_breaks_the_anchor() -> void:
	# BOTH resolve, in that order: the trap fires against a board that still holds the
	# anchor, and the anchor then dies. Stomping first would let a placement vanish before
	# an effect layered on the same cell had resolved against it.
	var caster := _caster(0)
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(), caster, board, Vector2i(3, 0))

	var mine := TileEffectResource.new()
	mine.id = &"test_mine"
	mine.trigger = TileEffectResource.Trigger.ON_ENTER
	var bite := DamageEffect.new()
	bite.power = 11
	bite.category = CombatTypes.DamageCategory.TRUE
	mine.effects = [bite] as Array[MoveEffect]
	CombatServices.add_tile_effect(Vector2i(3, 0), mine)

	var enemy := _caster(1)
	board.place(enemy, Vector2i(4, 0))
	var before: int = enemy.get_hp()
	var events: Array = _primed_system([Vector2i(3, 0)]).on_enter(enemy, Vector2i(3, 0), board)

	assert_lt(enemy.get_hp(), before, "the mine bit the stomper on the way in")
	assert_null(_spot_at(Vector2i(3, 0)), "and the anchor it stepped on is broken")
	assert_gte(events.size(), 1, "the arrival reported what it did")
	assert_eq(String(events[events.size() - 1].get("effect", "")), "tile_effect_stomped",
		"with the stomp LAST in the log -- the ground gets its say first")


# ===========================================================================
# THE STOMP -- an enemy stepping on an anchor destroys it
# ===========================================================================
#
# THE COUNTERPLAY. An anchor does nothing to whoever stands on it, so without this it would
# be a mark the enemy can see and cannot answer. Stepping on it IS the answer, and it costs
# the stomper the move it spent getting there. Run at the tile-ENTRY seam as an authored tile
# rule (TileEffectResource.destroyed_by_hostile_entry), so every relocation in the game --
# a walk, a leap, a knockback, another teleport -- gets it for free and nothing special-cases
# Voidstep.


## A live [TileEffectSystem] with [param cells]' current effects primed into its injected
## lookup, which is what a board with no `tile_effects_at` of its own reads.
func _primed_system(cells: Array) -> TileEffectSystem:
	var sys: TileEffectSystem = add_child_autofree(TileEffectSystem.new())
	for cell in cells:
		sys.tile_effects[cell] = CombatServices.tile_effects_at(cell)
	return sys


func test_an_enemy_LANDING_on_an_anchor_destroys_it() -> void:
	var caster := _caster(0)
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(), caster, board, Vector2i(3, 0))
	var enemy := OwnedUnit.new(1, Player.new(1, "Foe"))
	board.place(enemy, Vector2i(4, 0))

	_primed_system([Vector2i(3, 0)]).on_enter(enemy, Vector2i(3, 0), board)

	assert_null(_spot_at(Vector2i(3, 0)),
		"an enemy that stops on the anchor breaks it -- the escape route is denied")
	assert_eq(VoidstepEffect.own_spot_cells(caster).size(), 0,
		"and the slot it held is free again")


func test_an_enemy_merely_CROSSING_an_anchor_destroys_it_too() -> void:
	# The route-walk case: it is the ARRIVAL that breaks an anchor, and a unit running over
	# one has arrived on it however briefly. resolve_path is the exact function apply_move
	# walks the crossed cells with.
	var caster := _caster(0)
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(), caster, board, Vector2i(2, 0))
	var enemy := OwnedUnit.new(1, Player.new(1, "Foe"))
	board.place(enemy, Vector2i(0, 0))

	var sys := _primed_system([Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	var stop: Vector2i = sys.resolve_path(
		enemy, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], board, Vector2i(3, 0))

	assert_eq(stop, Vector2i(3, 0), "the walk ran its full course -- an anchor halts nobody")
	assert_null(_spot_at(Vector2i(2, 0)),
		"but the anchor it crossed on the way is gone: walking over it is enough")


func test_a_NEUTRAL_stomps_an_anchor_exactly_as_an_enemy_does() -> void:
	# A unit with no owner is not on the placer's side, so it breaks the mark. A wild beast
	# trampling an anchor reads right, and it falls out of the owner comparison rather than
	# needing a neutrality rule of its own.
	var caster := _caster(0)
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(), caster, board, Vector2i(3, 0))
	var beast := OwnedUnit.new(2, null)
	board.place(beast, Vector2i(4, 0))

	_primed_system([Vector2i(3, 0)]).on_enter(beast, Vector2i(3, 0), board)

	assert_null(_spot_at(Vector2i(3, 0)), "the unowned trampler broke it")


func test_an_ALLY_standing_on_an_anchor_only_closes_it_and_never_breaks_it() -> void:
	var owner := Player.new(0, "Us")
	var caster := _caster(0)
	caster.owner_player = owner
	var ally := OwnedUnit.new(0, owner)
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(), caster, board, Vector2i(3, 0))
	board.place(ally, Vector2i(4, 0))

	board.move_unit(ally, Vector2i(3, 0))
	_primed_system([Vector2i(3, 0)]).on_enter(ally, Vector2i(3, 0), board)

	assert_not_null(_spot_at(Vector2i(3, 0)),
		"our own side may stand on our anchor without breaking it")
	assert_false(_effect().allows_aim(Vector2i(0, 0), Vector2i(3, 0), caster, board),
		"it is merely CLOSED while occupied -- there is nowhere to arrive")

	board.move_unit(ally, Vector2i(4, 0))

	assert_true(_effect().allows_aim(Vector2i(0, 0), Vector2i(3, 0), caster, board),
		"and it opens again the moment they step off: blocking is not breaking")


func test_the_caster_walking_over_its_own_anchor_leaves_it_alone() -> void:
	var caster := _caster(0)
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	_cast(_effect(), caster, board, Vector2i(2, 0))

	var sys := _primed_system([Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	sys.resolve_path(caster, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], board, Vector2i(3, 0))
	sys.on_enter(caster, Vector2i(3, 0), board)

	assert_not_null(_spot_at(Vector2i(2, 0)),
		"Duskmaw may walk across its own marks all day -- only a hostile arrival breaks one")


func test_map_authored_terrain_is_structurally_out_of_the_stomps_reach() -> void:
	# The rule needs an OWNER to be hostile TO, and authored terrain has none. So no unit
	# anywhere can walk lava off a cell, without anything having to check for that.
	var lava := load("res://game/tiles/effects/resources/fire.tres") as TileEffectResource
	assert_not_null(lava, "the authored terrain effect loads")
	if lava == null:
		return
	assert_false(lava.destroyed_by_hostile_entry, "it is not authored as stompable at all")
	var stray := OwnedUnit.new(1, Player.new(1, "Foe"))
	assert_false(lava.destroyed_by(stray, null), "and nobody entering it destroys it")

	var spot := _spot()
	assert_true(spot.destroyed_by_hostile_entry, "the void spot IS authored as stompable")
	assert_false(spot.destroyed_by(stray, null),
		"but an UNSTAMPED copy has no owner either, so even it is untouched until it is placed")


# ===========================================================================
# THE DYNAMIC COOLDOWN
# ===========================================================================


## Resolve [param move] on [param caster] the way every caller does: effects first, THEN the
## caller books the use. Getting that order right is the whole reason on_used may not
## shorten a wait resolution already started.
func _cast_and_book(caster: Unit, move: MoveResource, effect: VoidstepEffect, board, cell: Vector2i) -> void:
	_cast(effect, caster, board, cell, move)
	var controller = caster.get_moveset_controller()
	if controller != null:
		controller.on_used(move)


func test_planting_starts_the_short_wait_and_stepping_the_long_one() -> void:
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	var move := _move_for(effect)
	var controller = caster.get_moveset_controller()

	_cast_and_book(caster, move, effect, board, Vector2i(3, 0))
	assert_eq(controller.remaining(move), AUTHORED_PLACE_CD,
		"planting an anchor costs the move's authored 1 turn -- marks are cheap")
	assert_eq(controller.total(move), AUTHORED_PLACE_CD, "and the bar counts down from 1")

	controller.tick_cooldowns()
	assert_true(controller.can_use(move), "one turn later it is ready again")

	_cast_and_book(caster, move, effect, board, Vector2i(3, 0))
	assert_eq(controller.remaining(move), AUTHORED_TELEPORT_CD,
		"but STEPPING to an anchor sets the long 4-turn wait, decided by what the cast DID")
	assert_eq(controller.total(move), AUTHORED_TELEPORT_CD,
		"and the recharge readout counts down from 4, not from the authored 1")


func test_the_long_wait_survives_the_caller_booking_the_use() -> void:
	# The ordering trap: effects resolve BEFORE on_used, so a caller that stamped the
	# authored cooldown unconditionally would erase the price the teleport just charged.
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	var move := _move_for(effect)
	var controller = caster.get_moveset_controller()
	_cast_and_book(caster, move, effect, board, Vector2i(3, 0))
	controller.tick_cooldowns()

	_cast(effect, caster, board, Vector2i(3, 0))
	assert_eq(controller.remaining(move), AUTHORED_TELEPORT_CD, "resolution set 4")
	controller.on_used(move)
	assert_eq(controller.remaining(move), AUTHORED_TELEPORT_CD,
		"and booking the use did NOT shorten it back to the authored 1")


func test_the_readout_returns_to_the_authored_number_once_the_wait_is_over() -> void:
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	var move := _move_for(effect)
	var controller = caster.get_moveset_controller()
	_cast_and_book(caster, move, effect, board, Vector2i(3, 0))
	controller.tick_cooldowns()
	_cast_and_book(caster, move, effect, board, Vector2i(3, 0))

	var seen: Array = []
	for _i in range(AUTHORED_TELEPORT_CD):
		seen.append("%d/%d" % [controller.remaining(move), controller.total(move)])
		controller.tick_cooldowns()

	assert_eq(seen, ["4/4", "3/4", "2/4", "1/4"],
		"the bar reads the wait that actually ran, all the way down")
	assert_eq(controller.total(move), AUTHORED_PLACE_CD,
		"and a READY move quotes its authored cooldown again -- nothing lingers")


func test_a_snapshot_carries_the_overridden_wait_through_a_restore() -> void:
	# Respawns and the mid-battle save both round-trip a MovesetController through
	# snapshot_state/restore_state. A dynamic wait is RESOLUTION state, so it has to ride
	# along or a resumed battle would silently hand the teleport back four turns early.
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	var move := _move_for(effect)
	var controller = caster.get_moveset_controller()
	_cast_and_book(caster, move, effect, board, Vector2i(3, 0))
	controller.tick_cooldowns()
	_cast_and_book(caster, move, effect, board, Vector2i(3, 0))

	var state: Dictionary = controller.snapshot_state()
	var restored: MovesetController = autofree(MovesetController.new())
	restored.restore_state(state)

	assert_eq(restored.remaining(move), AUTHORED_TELEPORT_CD, "the long wait came back")
	assert_eq(restored.total(move), AUTHORED_TELEPORT_CD,
		"and so did the number the bar divides by -- a resumed battle still reads 4/4")
	assert_true(state.has("cooldown_totals"), "the snapshot carries the dynamic wait section")
	assert_eq(state["cooldown_totals"], { "voidstep": AUTHORED_TELEPORT_CD },
		"keyed by a STRING move id, so it survives the JSON round trip the save does")


# ===========================================================================
# TARGETING -- one rule, shared by the highlight, the executor and the effect
# ===========================================================================


func test_the_aim_rule_offers_free_ground_near_the_caster_and_own_anchors_further_out() -> void:
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	var origin := Vector2i(0, 0)

	assert_true(effect.allows_aim(origin, Vector2i(4, 0), caster, board),
		"free ground at the edge of the planting reach is a legal PLACE")
	assert_false(effect.allows_aim(origin, Vector2i(5, 0), caster, board),
		"one cell further is not -- planting is the tight half of the move")

	# Plant an anchor, then WALK AWAY until it is far past anything a placement could reach.
	_cast(effect, caster, board, Vector2i(4, 0))
	var away := Vector2i(0, 6)
	board.move_unit(caster, away)

	assert_eq(_manhattan(away, Vector2i(4, 0)), 10, "the anchor is now 10 cells off")
	assert_true(effect.allows_aim(away, Vector2i(4, 0), caster, board),
		"and the caster's OWN anchor is still aimable -- this is the LONG half of the move")
	assert_false(effect.allows_aim(away, Vector2i(4, 1), caster, board),
		"while the bare ground beside it is not: nothing out there but an anchor may be aimed at")


func test_another_units_anchor_is_not_a_teleport_target() -> void:
	var mine := _caster(0)
	var theirs := _caster(1)
	var board := Doubles.CombatBoard.new()
	board.place(mine, Vector2i(0, 0))
	board.place(theirs, Vector2i(9, 9))
	var effect := _effect()
	_cast(effect, theirs, board, Vector2i(9, 8))

	assert_false(VoidstepEffect.is_own_spot_cell(mine, Vector2i(9, 8)),
		"an enemy's anchor is not one of ours")
	assert_false(effect.allows_aim(Vector2i(0, 0), Vector2i(9, 8), mine, board),
		"so it is not somewhere we may step -- and it is far past our planting reach")


func test_the_executor_accepts_a_long_step_and_refuses_an_unanchored_far_cell() -> void:
	# The end-to-end legality path: MoveExecutor validates through the SAME can_target the
	# highlight sweeps with, so a cell the player can see lit is a cell that resolves.
	var caster := _caster()
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	var effect := _effect()
	var move := _move_for(effect)
	_cast(effect, caster, board, Vector2i(4, 0))
	board.move_unit(caster, Vector2i(0, 6))

	var far := MoveExecutor.execute(move, caster, board, Vector2i(4, 0))
	assert_true(far.get("success", false),
		"an anchor 10 cells away is a legal cast -- this is a LONG-range teleport")
	assert_eq(board.cell_of(caster), Vector2i(4, 0), "and the caster arrived on it")

	board.move_unit(caster, Vector2i(0, 6))
	var nowhere := MoveExecutor.execute(move, caster, board, Vector2i(5, 1))
	assert_false(nowhere.get("success", true), "bare ground that far out is refused")
	assert_eq(String(nowhere.get("reason", "")), "invalid_target_cell",
		"and says why, as a value the UI can act on")


# --- helpers -----------------------------------------------------------------


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## The first logged Voidstep event of [param mode] in [param ctx], or {}.
func _event(ctx: MoveContext, mode: String) -> Dictionary:
	for e in ctx.results:
		if String(e.get("effect", "")) == "voidstep" and String(e.get("mode", "")) == mode:
			return e
	return {}
