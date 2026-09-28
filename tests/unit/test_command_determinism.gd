extends GutTest

# The core lockstep guarantee: applying the SAME scripted command sequence from the
# SAME initial state with the SAME seeds produces byte-identical results on two
# independent runs -- identical state hashes after every command, identical event
# logs. This is what makes the ONE apply path (NetGameRules, which CommandApplier --
# the battle / replay seam -- extends) safe to run on every networked peer.
#
# Mock style mirrors tests/unit/test_blightcap.gd / test_move_modes.gd: a duck-typed
# board and units, with a seeded RNG injected into MoveExecutor (here via MatchRng ->
# NetProtocol resolution stamp -> CommandApplier).
#
# MERGED CORE: units are named by NetUnitIds ("<slot>:<n>", assigned from the board) instead
# of the retired int registry; END_TURN drives end_turn_manually (the UI's End Turn) and WAIT
# hands the unit to the turn system's mark_unit_acted (the UI's Wait), so the turn double
# models those; and the digest now INCLUDES the per-turn flags (see the last-but-one test).

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
	var has_moved_this_turn: bool = false
	var has_acted_this_turn: bool = false

	func _init(p_team: int, p_stats: Dictionary, p_moveset: Dictionary = {}) -> void:
		team = p_team
		stats = p_stats
		max_health = int(p_stats.get("health", 100))
		hp = max_health
		moveset = p_moveset

	func get_team() -> int:
		return team
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
		has_moved_this_turn = true
	func mark_action_completed(_action: String) -> void:
		has_acted_this_turn = true
	func perform_move(slot: int, aim_cell: Vector3i, board, rng: RandomNumberGenerator = null) -> Dictionary:
		var move = moveset.get(slot, null)
		if move == null:
			return { "success": false, "reason": "no_move_in_slot", "events": [], "cells": [] }
		return MoveExecutor.execute(move, self, board, aim_cell, rng)

## The same small board double the combat tests use, plus all_units() (NetUnitIds).
class MockBoard:
	var placements: Array = []
	var blocked: Array = []
	var bounds: Rect2i = Rect2i(0, 0, 12, 12)
	func place(unit, cell: Vector3i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out
	func cell_of(unit) -> Vector3i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector3i(-999, -999, 0)
	func units_at(cell: Vector3i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team
	func set_tile(_cell: Vector3i, _tile_id) -> void:
		pass
	func move_unit(unit, to_cell: Vector3i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	func in_bounds(cell: Vector3i) -> bool:
		return cell.z == 0 and bounds.has_point(Cells.flat(cell))
	func is_blocked(cell: Vector3i) -> bool:
		return cell in blocked
	func is_occupied(cell: Vector3i) -> bool:
		return not units_at(cell).is_empty()
	func can_fit(unit, anchor: Vector3i) -> bool:
		if not in_bounds(anchor) or is_blocked(anchor):
			return false
		for other in units_at(anchor):
			if other != unit:
				return false
		return true

## A turn system double for END_TURN / WAIT, so the apply path's turn calls are exercised
## without touching the live TurnSystemManager.
class MockTurn:
	var calls: int = 0
	func end_turn_manually() -> bool:
		calls += 1
		return true
	func mark_unit_acted(unit) -> void:
		unit.has_acted_this_turn = true

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

## A fresh, identically-arranged battle plus its applier. Ids come from the board
## (owner slot, then floor / row / column), so both runs name the same units the same way:
## attacker "0:0", defender "1:0", bystander "1:1".
func _build() -> Dictionary:
	var board := MockBoard.new()
	var attacker := MockUnit.new(0, { "health": 100, "crit": 0 }, { 0: _strike() })
	var defender := MockUnit.new(1, { "health": 100, "defense": 0 })
	var bystander := MockUnit.new(1, { "health": 80 })
	board.place(attacker, Vector3i(1, 1, 0))
	board.place(defender, Vector3i(3, 1, 0))
	board.place(bystander, Vector3i(6, 6, 0))

	var mr := MatchRng.new()
	mr.begin_solo(_SEED)
	var applier := CommandApplier.new(null, mr, func(): return board, func(): return null)
	applier.assign_initial_ids()
	return { "board": board, "applier": applier }

## The scripted sequence, stamped with per-command seeds from a match seed shared by
## both runs (built independently of any run so the commands themselves are identical).
func _script() -> Array:
	var mr := MatchRng.new()
	mr.begin_solo(_SEED)
	var cmds: Array = []
	cmds.append(_stamp(NetProtocol.make_cast_move("0:0", 0, Vector3i(3, 1, 0), 0), 1, mr))   # attacker hits defender (rolls)
	cmds.append(_stamp(NetProtocol.make_wait_unit("1:0", 1), 2, mr))                      # defender waits
	cmds.append(_stamp(NetProtocol.make_move_unit("0:0", Vector3i(2, 1, 0), 0), 3, mr))      # attacker steps up
	cmds.append(_stamp(NetProtocol.make_end_turn(0, 0), 4, mr))                           # end player 0's turn
	cmds.append(_stamp(NetProtocol.make_cast_move("0:0", 0, Vector3i(3, 1, 0), 0), 5, mr))   # attacker hits again (rolls)
	return cmds

func _stamp(cmd: Dictionary, seq: int, mr: MatchRng) -> Dictionary:
	return NetProtocol.stamp_resolution(cmd, seq, mr.seed_for(seq))

func after_each():
	# The apply path installs each action's generator as CombatServices.match_rng.
	if CombatServices != null:
		CombatServices.match_rng = null

## Apply the whole script to a fresh build, capturing the state hash and an
## id-stable event digest after every command.
func _replay(cmds: Array) -> Dictionary:
	var b := _build()
	var applier: CommandApplier = b["applier"]
	var board = b["board"]
	var turn := MockTurn.new()

	var start_hash := applier.hash_match_state(board)
	var hashes: Array = []
	var digests: Array = []
	for cmd in cmds:
		var res: Dictionary = applier.apply_command(cmd, board, { "turn_system": turn })
		digests.append(_digest(res))
		hashes.append(applier.hash_match_state(board))
	return {
		"start_hash": start_hash,
		"hashes": hashes,
		"digests": digests,
		"turn_calls": turn.calls,
	}

## Replay the script on a fresh build, capturing every unit's turn-consumption flags
## ([acted, has_moved]) after every command. Proves the apply layer consumes actions/moves
## deterministically -- the property live networked turn flow (greying units, advancing Speed
## First) depends on.
func _replay_flags(cmds: Array) -> Array:
	var b := _build()
	var applier: CommandApplier = b["applier"]
	var board = b["board"]
	var turn := MockTurn.new()
	var snapshots: Array = []
	for cmd in cmds:
		applier.apply_command(cmd, board, { "turn_system": turn })
		snapshots.append(_flags(board))
	return snapshots

## Per-unit [acted, has_moved] keyed by net id (null when a unit is gone).
func _flags(board) -> Dictionary:
	var out: Dictionary = {}
	for id in ["0:0", "1:0", "1:1"]:
		var u = NetUnitIds.find(board, id)
		out[id] = null if u == null else [u.has_acted_this_turn, u.has_moved_this_turn]
	return out

## A comparable form of an apply result: unit object references (which differ between
## runs) are replaced by their stable net ids.
func _digest(res: Dictionary) -> Dictionary:
	var events: Array = []
	for e in res.get("events", []):
		var d: Dictionary = {}
		for k in e.keys():
			if k == "target" or e[k] is Object:
				d[k] = NetUnitIds.id_of(e[k])
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
	var before := applier.hash_match_state(board)
	# Mutate a unit's HP directly and re-hash.
	NetUnitIds.find(board, "1:0").take_damage(5)
	var after := applier.hash_match_state(board)
	assert_ne(before, after, "changing a unit's HP changes the state hash")

func test_cast_and_move_consume_flags_identically_across_runs():
	# The apply layer must consume actions/moves deterministically: two independent runs of
	# the same command stream leave every unit's [acted, has_moved] flags identical after
	# every command. This is what keeps turn flow (greying, Speed First advance) in lockstep.
	var cmds := _script()
	var run_a := _replay_flags(cmds)
	var run_b := _replay_flags(cmds)
	assert_eq(str(run_a), str(run_b),
		"per-unit acted/has_moved flags are identical after every command across two runs")

func test_cast_consumes_action_move_marks_moved():
	# The concrete apply semantics: a CAST_MOVE consumes the caster's ACTION (acted) but not
	# its move; a WAIT hands the unit to the turn system as acted; a MOVE_UNIT marks the move.
	var cmds := _script()
	var snaps := _replay_flags(cmds)
	assert_eq(snaps[0]["0:0"], [true, false], "cmd0 CAST_MOVE: caster's action consumed, move not")
	assert_eq(snaps[1]["1:0"], [true, false], "cmd1 WAIT_UNIT: defender's action consumed")
	assert_eq(snaps[2]["0:0"], [true, true], "cmd2 MOVE_UNIT: caster now also marked moved")

func test_hash_includes_turn_flags():
	# MERGED DECISION (the network core's digest): acted/has_moved ARE part of the state
	# hash. They are derived from the same stream on every peer, so they never differ between
	# honest peers -- and including them catches a peer that skipped a mark_moved / action the
	# moment it happens instead of a turn later. (The pre-merge command hash left them out.)
	var b := _build()
	var applier: CommandApplier = b["applier"]
	var board = b["board"]
	var before := applier.hash_match_state(board)
	var unit = NetUnitIds.find(board, "0:0")
	unit.mark_action_completed("move")
	unit.mark_moved()
	assert_ne(before, applier.hash_match_state(board),
		"acted/has_moved change the state hash")

func test_summoned_units_get_deterministic_ids():
	# Units that appear mid-match (summons, reinforcements) are named after every applied
	# action, "<slot>:s<k>", in (owner, floor, row, column) order -- identical on every peer.
	var names: Array = []
	for _run in range(2):
		var b := _build()
		var board: MockBoard = b["board"]
		var summoned := MockUnit.new(0, { "health": 10 })
		board.place(summoned, Vector3i(4, 4, 0))
		var counter: Array = [0]
		NetUnitIds.assign(board, false, counter)
		names.append(NetUnitIds.id_of(summoned))
	assert_eq(names[0], "0:s0", "a mid-match arrival gets the next spawn id of its owner")
	assert_eq(names[0], names[1], "and the same id on an independent run")
