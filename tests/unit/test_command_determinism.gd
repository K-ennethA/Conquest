extends GutTest

# The core lockstep guarantee: applying the SAME scripted command sequence from the
# SAME initial state with the SAME match seed produces byte-identical results on two
# independent runs -- identical state hashes after every command, identical event
# logs. This is what makes CommandApplier safe to run on every networked peer.
#
# Mock style mirrors tests/unit/test_blightcap.gd / test_move_modes.gd: a duck-typed
# board and units, with a seeded RNG injected into MoveExecutor (here via MatchRng ->
# NetProtocol resolution stamp -> CommandApplier).

const _SEED := 0xC0FFEE

# --- mocks -----------------------------------------------------------------

## A duck-typed unit that can resolve a move exactly as the live Unit.perform_move
## does: delegate to MoveExecutor with the injected (seeded) RNG.
class MockUnit:
	var team: int
	var stats: Dictionary
	var max_health: int
	var hp: int
	var moveset: Dictionary   # slot:int -> MoveResource
	var has_moved: bool = false
	var acted: bool = false

	func _init(p_team: int, p_stats: Dictionary, p_moveset: Dictionary = {}) -> void:
		team = p_team
		stats = p_stats
		max_health = int(p_stats.get("health", 100))
		hp = max_health
		moveset = p_moveset

	func get_stat(n: String) -> int:
		return stats.get(n, 0)
	func get_base_stat(n: String) -> int:
		return stats.get(n, 0)
	func get_hp() -> int:
		return hp
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
	func mark_moved() -> void:
		has_moved = true
	func mark_action_completed(_action: String) -> void:
		acted = true
	func perform_move(slot: int, aim_cell: Vector2i, board, rng: RandomNumberGenerator = null) -> Dictionary:
		var move = moveset.get(slot, null)
		if move == null:
			return { "success": false, "reason": "no_move_in_slot", "events": [], "cells": [] }
		return MoveExecutor.execute(move, self, board, aim_cell, rng)

## The same small board double the combat tests use.
class MockBoard:
	var placements: Array = []
	var blocked: Array = []
	var bounds: Rect2i = Rect2i(0, 0, 12, 12)
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
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
	func set_tile(_cell: Vector2i, _tile_id) -> void:
		pass
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	func in_bounds(cell: Vector2i) -> bool:
		return bounds.has_point(cell)
	func is_blocked(cell: Vector2i) -> bool:
		return cell in blocked
	func is_occupied(cell: Vector2i) -> bool:
		return not units_at(cell).is_empty()
	func can_fit(unit, anchor: Vector2i) -> bool:
		if not in_bounds(anchor) or is_blocked(anchor):
			return false
		for other in units_at(anchor):
			if other != unit:
				return false
		return true

## A turn system stub for END_TURN, so the applier's turn-advance path is exercised
## without touching the live TurnSystemManager.
class MockTurn:
	var calls: int = 0
	func advance_turn() -> void:
		calls += 1

# --- fixtures --------------------------------------------------------------

## A move that rolls to hit (accuracy < 1) and to crit (crit_chance > 0), so its
## resolution genuinely consumes the injected RNG stream.
func _strike() -> MoveResource:
	var move := MoveResource.new()
	move.move_id = &"test_strike"
	move.accuracy = 0.75
	move.crit_chance = 0.5
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 5
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	var dmg := DamageEffect.new()
	dmg.power = 20
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	move.effects = [dmg]
	return move

## A fresh, identically-arranged battle plus its registry/applier. net_ids are
## assigned in a fixed order, so both runs name the same units the same way.
func _build() -> Dictionary:
	var board := MockBoard.new()
	var attacker := MockUnit.new(0, { "health": 100, "crit": 0 }, { 0: _strike() })
	var defender := MockUnit.new(1, { "health": 100, "defense": 0 })
	var bystander := MockUnit.new(1, { "health": 80 })
	board.place(attacker, Vector2i(1, 1))
	board.place(defender, Vector2i(3, 1))
	board.place(bystander, Vector2i(6, 6))

	var reg := CommandApplier.UnitRegistry.new()
	reg.assign_map_units([attacker, defender, bystander])   # ids 1, 2, 3

	var mr := MatchRng.new()
	mr.begin_solo(_SEED)
	var applier := CommandApplier.new(reg, mr)
	return { "board": board, "applier": applier, "reg": reg }

## The scripted sequence, stamped with per-command seeds from a match seed shared by
## both runs (built independently of any run so the commands themselves are identical).
func _script() -> Array:
	var mr := MatchRng.new()
	mr.begin_solo(_SEED)
	var cmds: Array = []
	cmds.append(_stamp(NetProtocol.make_cast_move(1, 0, Vector2i(3, 1), 0), 1, mr))   # attacker hits defender (rolls)
	cmds.append(_stamp(NetProtocol.make_wait_unit(2, 1), 2, mr))                      # defender waits
	cmds.append(_stamp(NetProtocol.make_move_unit(1, Vector2i(2, 1), 0), 3, mr))      # attacker steps up
	cmds.append(_stamp(NetProtocol.make_end_turn(0, 0), 4, mr))                       # end player 0's turn
	cmds.append(_stamp(NetProtocol.make_cast_move(1, 0, Vector2i(3, 1), 0), 5, mr))   # attacker hits again (rolls)
	return cmds

func _stamp(cmd: Dictionary, seq: int, mr: MatchRng) -> Dictionary:
	return NetProtocol.stamp_resolution(cmd, seq, mr.seed_for(seq))

## Apply the whole script to a fresh build, capturing the state hash and a
## registry-stable event digest after every command.
func _replay(cmds: Array) -> Dictionary:
	var b := _build()
	var applier: CommandApplier = b["applier"]
	var board = b["board"]
	var reg = b["reg"]
	var turn := MockTurn.new()

	var start_hash := applier.hash_match_state(board)
	var hashes: Array = []
	var digests: Array = []
	for cmd in cmds:
		var res: Dictionary = applier.apply_command(cmd, board, { "turn_system": turn })
		digests.append(_digest(res, reg))
		hashes.append(applier.hash_match_state(board))
	return {
		"start_hash": start_hash,
		"hashes": hashes,
		"digests": digests,
		"turn_calls": turn.calls,
	}

## A comparable form of an apply result: unit object references (which differ between
## runs) are replaced by their stable net_ids.
func _digest(res: Dictionary, reg) -> Dictionary:
	var events: Array = []
	for e in res.get("events", []):
		var d: Dictionary = {}
		for k in e.keys():
			if k == "target":
				d[k] = reg.id_for(e[k])
			else:
				d[k] = e[k]
		events.append(d)
	return {
		"ok": res.get("ok", null),
		"type": res.get("type", null),
		"seq": res.get("seq", null),
		"reason": res.get("reason", ""),
		"events": events,
	}

# --- the guarantee ---------------------------------------------------------

func test_two_identical_runs_stay_in_lockstep():
	var cmds := _script()
	var run_a := _replay(cmds)
	var run_b := _replay(cmds)

	assert_eq(str(run_a["hashes"]), str(run_b["hashes"]),
		"the state hash is identical after every command across two independent runs")
	assert_eq(str(run_a["digests"]), str(run_b["digests"]),
		"the event log is identical after every command across two independent runs")
	assert_eq(run_a["start_hash"], run_b["start_hash"],
		"the two runs even start from an identical hash")

func test_the_sequence_actually_mutates_state():
	# Guards against a false pass where nothing changed and every hash trivially matched.
	var cmds := _script()
	var run := _replay(cmds)
	var final_hash: int = run["hashes"][run["hashes"].size() - 1]
	assert_ne(final_hash, run["start_hash"], "the scripted casts/moves changed the board state")
	assert_eq(run["turn_calls"], 1, "END_TURN drove the turn system exactly once")

func test_cast_move_rolled_and_dealt_damage():
	# Prove the CAST_MOVE genuinely rolled a hit/crit through the seeded RNG and the
	# result is a stable, non-empty damage event.
	var cmds := _script()
	var run := _replay(cmds)
	var first: Dictionary = run["digests"][0]
	assert_true(bool(first["ok"]), "the cast resolved")
	assert_gt(first["events"].size(), 0, "and produced at least one event")
	var saw_damage := false
	for e in first["events"]:
		if String(e.get("effect", "")) == "damage":
			saw_damage = true
	assert_true(saw_damage, "including a damage event from the seeded roll")

func test_hash_is_sensitive_to_state():
	# The oracle must actually depend on unit state, or lockstep equality is vacuous.
	var b := _build()
	var applier: CommandApplier = b["applier"]
	var board = b["board"]
	var reg = b["reg"]
	var before := applier.hash_match_state(board)
	# Mutate a unit's HP directly and re-hash.
	reg.unit_for(2).take_damage(5)
	var after := applier.hash_match_state(board)
	assert_ne(before, after, "changing a unit's HP changes the state hash")

func test_summoned_units_get_deterministic_ids():
	# Even without a live summon, the registry's summon id derivation is a pure
	# function of (seq, index) -- the property the reactive event-log assignment relies on.
	var reg := CommandApplier.UnitRegistry.new()
	assert_eq(reg.summon_id(5, 0), reg.summon_id(5, 0), "same seq+index -> same id")
	assert_ne(reg.summon_id(5, 0), reg.summon_id(5, 1), "different index -> different id")
	assert_ne(reg.summon_id(5, 0), reg.summon_id(6, 0), "different seq -> different id")
	assert_gt(reg.summon_id(1, 0), 3, "summon ids sit well above the small map-unit id range")
