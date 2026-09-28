extends GutTest

## STATUS DURATION CLOCKS on a LIVE board with BOTH real turn systems (CONQUEST.md rule 6a).
##
## The bug being pinned: a status counted down at the afflicted unit's turn START, so a
## 1-turn debuff a foe inflicted on its own turn was expired by the tick that opened the
## victim's next turn -- the victim never played a turn under it. Grave Grasp's Ensnared
## let the victim walk away, a 1-turn defense-down lapsed before it mattered.
##
## Everything here is the real stack: character-backed [Unit]s under a real "Map" root, the
## real [CombatServices] / [BoardAdapter], the shipped moves and statuses through
## [method Unit.perform_move], and the REAL turn systems opening and closing turns through
## their own entry points (Traditional: [code]_start_player_turn[/code], which also closes
## the previous side; Speed First: [code]_start_unit_turn[/code] / [code]_end_unit_turn[/code]).
## Speed First with one unit per side is the 1v1 alternation the duel mode derives from.
##
## Scaffolding mirrors integration/test_status_tick_lifecycle.gd.

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

const GRAVE_GRASP_PATH := "res://game/combat/moves/grave_grasp.tres"
const SUNDER_GUARD_PATH := "res://game/combat/moves/sunder_guard.tres"
const ABYSSAL_MAW_PATH := "res://game/combat/moves/abyssal_maw.tres"
const THORNWARD_PATH := "res://game/combat/moves/thornward.tres"
const POISON_PATH := "res://game/combat/status/poisoned.tres"
const FLINCHED_PATH := "res://game/combat/status/flinched.tres"

const ATTACKER_ID: StringName = &"test_clock_attacker"
const VICTIM_ID: StringName = &"test_clock_victim"

const ATTACKER_CELL := Vector3i(2, 2, 0)
const VICTIM_CELL := Vector3i(2, 4, 0)   # 2 away: in reach of every attacker move
const VICTIM_DEFENSE: int = 10
const POISON_TICK: int = 4

var _map_root: Node3D = null
## Untyped on purpose (tests/README rule 3).
var _guard


func before_each() -> void:
	_guard = Guard.new()
	# Nothing here completes an action, but pin the auto-end so no other suite's setting
	# can advance a turn behind the test's back.
	_guard.set_setting("auto_end_turn", false)
	CombatServices.clear()
	_map_root = null
	CharacterLibrary._cache[ATTACKER_ID] = _make_character(ATTACKER_ID, "Clock Attacker", 0,
		[load(GRAVE_GRASP_PATH), load(SUNDER_GUARD_PATH), load(ABYSSAL_MAW_PATH)])
	CharacterLibrary._cache[VICTIM_ID] = _make_character(VICTIM_ID, "Clock Victim", VICTIM_DEFENSE,
		[load(THORNWARD_PATH)])


func after_each() -> void:
	CombatServices.clear()
	_map_root = null
	CharacterLibrary.clear_cache()
	_guard.restore()


# --- Scaffolding ------------------------------------------------------------

func _make_character(id: StringName, display_name: String, defense: int, moves: Array) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = display_name
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 400
	c.base_attack = 12
	c.base_defense = defense
	c.base_magic = 6
	c.base_magic_defense = 0
	c.base_speed = 10
	c.base_movement = 3
	c.attack_range = 1
	var typed: Array[MoveResource] = []
	for m in moves:
		typed.append(m)
	c.moveset = typed
	return c


## Two sides, one unit each, on a live board. Returns { attacker, victim, a, b } or {}.
func _battle() -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)
	var side_a := Player.new(0, "Attackers")
	var side_b := Player.new(1, "Defenders")
	var attacker := _spawn(ATTACKER_ID, ATTACKER_CELL, side_a)
	var victim := _spawn(VICTIM_ID, VICTIM_CELL, side_b)
	if attacker == null or victim == null:
		return {}
	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	return { "attacker": attacker, "victim": victim, "a": side_a, "b": side_b }


func _spawn(character_id: StringName, cell: Vector3i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character   # before add_child: _ready builds the controllers
	unit.position = BoardAdapter.new(GRID, []).cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


func _traditional(fx: Dictionary) -> TraditionalTurnSystem:
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	ts.register_player(fx["a"])
	ts.register_player(fx["b"])
	ts.is_active = true
	return ts


func _speed_first(fx: Dictionary) -> SpeedFirstTurnSystem:
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	ts.register_player(fx["a"])
	ts.register_player(fx["b"])
	ts.is_active = true
	return ts


## A turn driver that speaks both systems: open(side_key, round) / close(). Traditional
## closes the previous side inside _start_player_turn; Speed First closes explicitly.
class Driver:
	extends RefCounted
	var ts
	var fx: Dictionary
	var open_unit = null

	func _init(p_ts, p_fx: Dictionary) -> void:
		ts = p_ts
		fx = p_fx

	func open(side_key: String, round_number: int) -> void:
		ts.current_turn = round_number
		if ts is TraditionalTurnSystem:
			ts._start_player_turn(fx[side_key])
			return
		close()
		open_unit = fx["attacker"] if side_key == "a" else fx["victim"]
		ts._start_unit_turn(open_unit)

	func close() -> void:
		if ts is SpeedFirstTurnSystem and open_unit != null:
			ts._end_unit_turn(open_unit)
			open_unit = null


func _systems() -> Array:
	return ["traditional", "speed_first"]


func _driver(kind: String, fx: Dictionary) -> Driver:
	var ts = _traditional(fx) if kind == "traditional" else _speed_first(fx)
	return Driver.new(ts, fx)


func _cast(caster: Unit, move_path: String, aim: Vector3i, seed_value: int = 7) -> Dictionary:
	var move: MoveResource = load(move_path)
	var slot := -1
	var moveset := caster.get_moveset()
	for i in range(moveset.size()):
		if moveset[i] == move:
			slot = i
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return caster.perform_move(slot, aim, CombatServices.board(), rng)


func _stamped(path: String, source) -> StatusCondition:
	var s: StatusCondition = (load(path) as StatusCondition).duplicate(true)
	s.set_source(source)
	return s


# ===========================================================================
# 1. A foe's 1-turn IMMOBILIZE stops the victim's next move, then lets go
# ===========================================================================

func test_grave_grasp_holds_the_victim_for_its_next_turn_in_both_systems() -> void:
	for kind in _systems():
		var fx: Dictionary = await _battle()
		if fx.is_empty():
			pending("Could not build the character-backed units; skipping.")
			return
		var d := _driver(kind, fx)
		var victim: Unit = fx["victim"]

		d.open("a", 1)
		var result := _cast(fx["attacker"], GRAVE_GRASP_PATH, VICTIM_CELL)
		assert_true(bool(result.get("success", false)), "%s: Grave Grasp resolves" % kind)
		assert_true(victim.is_immobilized(), "%s: the victim is ensnared" % kind)

		d.open("b", 1)
		assert_true(victim.is_immobilized(),
			"%s: THE BUG -- still ensnared once the victim's own turn has opened" % kind)
		assert_false(victim.can_move(), "%s: so the victim cannot move this turn" % kind)
		assert_false(d.ts.validate_turn_action(victim, "move"),
			"%s: and the turn system refuses the move" % kind)

		d.open("a", 2)
		assert_false(victim.get_status_controller().has_status(&"ensnared"),
			"%s: the snare is gone once the turn it cost has ended" % kind)
		d.open("b", 2)
		assert_true(victim.can_move(), "%s: and the victim's following turn is free" % kind)
		d.close()


# ===========================================================================
# 2. A 1-turn STUN skips exactly one victim turn, in both systems
# ===========================================================================

func test_a_foes_stun_skips_exactly_one_turn_in_both_systems() -> void:
	for kind in _systems():
		var fx: Dictionary = await _battle()
		if fx.is_empty():
			pending("Could not build the character-backed units; skipping.")
			return
		var d := _driver(kind, fx)
		var victim: Unit = fx["victim"]

		d.open("a", 1)
		victim.get_status_controller().add_status(_stamped(FLINCHED_PATH, fx["attacker"]))
		assert_true(victim.is_stunned(), "%s: flinched" % kind)

		d.open("b", 1)
		assert_true(d.ts.is_turn_skipped(victim), "%s: the victim's next turn is skipped" % kind)
		assert_false(d.ts.can_unit_act(victim), "%s: and it cannot act in it" % kind)
		assert_true(victim.is_stunned(), "%s: the stun is on for the whole skipped turn" % kind)

		d.open("a", 2)
		assert_false(victim.is_stunned(), "%s: and gone once that turn is over" % kind)

		d.open("b", 2)
		assert_false(d.ts.is_turn_skipped(victim), "%s: NOT skipped a second time" % kind)
		assert_true(d.ts.can_unit_act(victim), "%s: the victim acts again -- no lockout" % kind)
		d.close()


# ===========================================================================
# 3. A 1-turn SELF-GUARD still covers the enemy's next turn
# ===========================================================================

func test_a_self_cast_guard_covers_the_enemy_turn_and_lapses_at_the_casters_next_turn() -> void:
	for kind in _systems():
		var fx: Dictionary = await _battle()
		if fx.is_empty():
			pending("Could not build the character-backed units; skipping.")
			return
		var d := _driver(kind, fx)
		var victim: Unit = fx["victim"]
		var controller = victim.get_status_controller()

		d.open("b", 1)
		var result := _cast(victim, THORNWARD_PATH, VICTIM_CELL)
		assert_true(bool(result.get("success", false)), "%s: Thornward resolves" % kind)
		assert_true(controller.has_status(&"braced"), "%s: braced" % kind)

		d.open("a", 1)   # closes the caster's turn
		assert_true(controller.has_status(&"braced"),
			"%s: a 1-turn self-guard does NOT vanish at the end of the turn it was cast" % kind)
		assert_almost_eq(victim.status_damage_taken_scale(), 0.6, 0.0001,
			"%s: it is guarding through the enemy's turn" % kind)

		d.open("b", 2)
		assert_false(controller.has_status(&"braced"),
			"%s: and lapses as the caster's next turn begins, exactly as before" % kind)
		d.close()


# ===========================================================================
# 4. A foe's POISON still ticks exactly its duration
# ===========================================================================

func test_a_foes_poison_tick_count_is_unchanged_in_both_systems() -> void:
	for kind in _systems():
		var fx: Dictionary = await _battle()
		if fx.is_empty():
			pending("Could not build the character-backed units; skipping.")
			return
		var d := _driver(kind, fx)
		var victim: Unit = fx["victim"]
		var controller = victim.get_status_controller()
		var poison: StatusCondition = load(POISON_PATH)

		d.open("a", 1)
		controller.add_status(_stamped(POISON_PATH, fx["attacker"]))
		var start_hp: int = victim.get_hp()

		for turn in range(poison.duration_turns):
			d.open("b", turn + 1)
			assert_eq(victim.get_hp(), start_hp - POISON_TICK * (turn + 1),
				"%s: victim turn %d -- one tick" % [kind, turn + 1])
			d.open("a", turn + 2)
		assert_false(controller.has_status(&"poisoned"),
			"%s: gone after its %d ticks" % [kind, poison.duration_turns])
		var settled: int = victim.get_hp()
		d.open("b", poison.duration_turns + 1)
		assert_eq(victim.get_hp(), settled, "%s: and never ticks a fourth time" % kind)
		d.close()


# ===========================================================================
# 5. ABYSSAL MAW still erupts at the start of the caster's next turn
# ===========================================================================

func test_abyssal_maw_still_erupts_at_the_casters_next_turn_start() -> void:
	for kind in _systems():
		var fx: Dictionary = await _battle()
		if fx.is_empty():
			pending("Could not build the character-backed units; skipping.")
			return
		var d := _driver(kind, fx)
		var attacker: Unit = fx["attacker"]
		var victim: Unit = fx["victim"]

		d.open("a", 1)
		var result := _cast(attacker, ABYSSAL_MAW_PATH, VICTIM_CELL)
		assert_true(bool(result.get("success", false)), "%s: the maw is cast" % kind)
		assert_true(attacker.get_status_controller().has_status(&"void_maw_fuse"), "%s: fuse armed" % kind)
		var before: int = victim.get_hp()

		d.open("b", 1)   # closes the caster's turn: a turn-END must not set it off
		assert_eq(victim.get_hp(), before, "%s: nothing at the end of the cast turn or on the enemy's turn" % kind)
		assert_true(attacker.get_status_controller().has_status(&"void_maw_fuse"), "%s: still burning" % kind)

		d.open("a", 2)
		assert_lt(victim.get_hp(), before, "%s: erupts at the start of the CASTER's next turn" % kind)
		assert_false(attacker.get_status_controller().has_status(&"void_maw_fuse"), "%s: fuse spent" % kind)
		d.close()


# ===========================================================================
# 6. A timed STAT DEBUFF from a foe is in force through the victim's turn(s)
# ===========================================================================

func test_a_foes_one_turn_defense_down_holds_through_the_victims_next_turn() -> void:
	for kind in _systems():
		var fx: Dictionary = await _battle()
		if fx.is_empty():
			pending("Could not build the character-backed units; skipping.")
			return
		var d := _driver(kind, fx)
		var attacker: Unit = fx["attacker"]
		var victim: Unit = fx["victim"]

		d.open("a", 1)
		# A 1-turn -8 defense, resolved from the attacker through the ordinary effect
		# pipeline (the same StatModifierEffect Sunder Guard carries).
		var shred := StatModifierEffect.new()
		shred.stat_name = "defense"
		shred.amount = -8
		shred.duration = 1
		var move: MoveResource = load(SUNDER_GUARD_PATH)
		var ctx := MoveContext.new(attacker, CombatServices.board(), move, VICTIM_CELL,
			[VICTIM_CELL] as Array[Vector3i])
		shred.apply(ctx)
		assert_eq(victim.get_stat("defense"), VICTIM_DEFENSE - 8,
			"%s: lowered for the rest of the attacker's turn (its side's next attack)" % kind)

		d.open("b", 1)
		assert_eq(victim.get_stat("defense"), VICTIM_DEFENSE - 8,
			"%s: THE BUG -- still lowered once the victim's own turn has opened" % kind)

		d.open("a", 2)
		assert_eq(victim.get_stat("defense"), VICTIM_DEFENSE,
			"%s: restored once the victim's turn has ended" % kind)
		d.close()


func test_sunder_guard_lowers_defense_for_the_victims_next_two_turns() -> void:
	for kind in _systems():
		var fx: Dictionary = await _battle()
		if fx.is_empty():
			pending("Could not build the character-backed units; skipping.")
			return
		var d := _driver(kind, fx)
		var victim: Unit = fx["victim"]

		d.open("a", 1)
		var result := _cast(fx["attacker"], SUNDER_GUARD_PATH, VICTIM_CELL)
		assert_true(bool(result.get("success", false)), "%s: Sunder Guard resolves" % kind)
		assert_eq(victim.get_stat("defense"), VICTIM_DEFENSE - 8, "%s: -8 defense" % kind)
		for turn in range(2):
			d.open("b", turn + 1)
			assert_eq(victim.get_stat("defense"), VICTIM_DEFENSE - 8,
				"%s: in force for victim turn %d" % [kind, turn + 1])
			d.open("a", turn + 2)
			assert_eq(victim.get_stat("defense"), VICTIM_DEFENSE - 8 if turn == 0 else VICTIM_DEFENSE,
				"%s: %s the attacker's following turn" % [kind, "still lowered for" if turn == 0 else "restored before"])
		d.close()
