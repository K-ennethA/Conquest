extends GutTest

## Integration test (T12): proves the migrated AI plans AND executes real moves
## against the shared LIVE board -- real CharacterResource-backed [Unit]s, the
## real [CombatServices] / [BoardAdapter], and the real [MoveExecutor] damage
## pipeline. No mocks stand in for board or unit behaviour here (contrast with
## tests/unit/test_bot_controller.gd, which uses lightweight duck-typed mocks).
##
## [BotTurnDriver] (game/ai/BotTurnDriver.gd) normally drives this by polling a
## 0.4s wall-clock [Timer] (see [method BotTurnDriver._tick]) and then routing
## through [method BotTurnDriver._act_character]. Ticking a real Timer
## deterministically in a headless test run is impractical, so instead this
## test performs the exact two steps [method BotTurnDriver._act_character] /
## [method BotTurnDriver._execute_move_decision] perform when the driver fires:
##   1. `BotController.new().decide(actor, actor.get_moveset(), board)` -- planning.
##   2. `actor.perform_move(slot, aim_cell, board)` -- execution, i.e. exactly
##      what [method Unit.perform_move] / [MoveExecutor] do; BotTurnDriver
##      itself contains no combat logic beyond looking up the slot.
## This exercises real planning + real damage resolution on a live board without
## depending on the Timer or the turn-system polling loop.

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

## Deterministic synthetic combatants (built in code and injected into
## CharacterLibrary in before_each) instead of roster units: the attacker carries
## ONE range-1 strike whose accuracy overshoots any evasion, so "HP drops" never
## rides on a probabilistic hit, and its ONLY reach is range 1 so the "advance
## instead of attacking" scenario at range 4 is genuinely out of range.
const ATTACKER_ID: StringName = &"test_ai_attacker"
const TARGET_ID: StringName = &"test_ai_target"

var _map_root: Node3D


func before_each() -> void:
	# CombatServices is a global autoload; a stale board/registry from a
	# previous test (this file or another) must never leak into this one.
	CombatServices.clear()
	_map_root = null
	_install_test_characters()


func after_each() -> void:
	# Drop the live adapter before GUT frees _map_root's units, so nothing is
	# left pointing at freed nodes for the next test.
	CombatServices.clear()
	_map_root = null
	# Evict the injected synthetic characters so they never leak into other suites.
	CharacterLibrary.clear_cache()


# --- Helpers -----------------------------------------------------------------

## Throwaway adapter used only for cell<->world math while placing units before
## the real board exists, built against the same GRID CombatServices.rebuild()
## uses -- mirrors the placement pattern in tests/unit/test_board_adapter.gd.
func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(GRID, []).cell_to_world(cell)


## Build the two throwaway combatants and inject them straight into the
## CharacterLibrary cache so _spawn_character_unit -> CharacterLibrary.get_character
## resolves them without any .tres on disk.
func _install_test_characters() -> void:
	CharacterLibrary._cache[ATTACKER_ID] = _make_test_attacker()
	CharacterLibrary._cache[TARGET_ID] = _make_test_target()


func _make_test_attacker() -> CharacterResource:
	return _make_test_character(ATTACKER_ID, "Test Attacker", 100, 34)


func _make_test_target() -> CharacterResource:
	return _make_test_character(TARGET_ID, "Test Target", 90, 20)


func _make_test_character(id: StringName, name: String, hp: int, atk: int) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = name
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = hp
	c.base_attack = atk
	c.base_defense = 8
	c.base_magic = 4
	c.base_magic_defense = 8
	c.base_speed = 10
	c.base_movement = 3
	c.attack_range = 1
	c.moveset = [_test_cleave()] as Array[MoveResource]
	return c


## A range-1 physical strike whose accuracy (5.0) overshoots any target evasion,
## so hit% clamps to 100 -- the attack ALWAYS lands. Non-lethal against the target
## HP above, so the struck unit survives (get_hp() stays valid for the assert).
func _test_cleave() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_cleave"
	m.display_name = "Test Cleave"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.accuracy = 5.0
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 20
	d.scaling_stat = "attack"
	d.scale = 1.0
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


## Spawns a character-backed Unit (CharacterUnit.tscn + CharacterLibrary) at
## [param cell] under [param map_root], owned by [param owner]. Returns null
## instead of crashing if the roster entry can't load, so callers can skip.
func _spawn_character_unit(map_root: Node3D, character_id: StringName, cell: Vector2i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null

	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character  # must be set before add_child so _ready() builds stats from it
	unit.position = _cell_to_world(cell)
	map_root.add_child(unit)  # map_root is already in the tree -> _ready runs now
	owner.add_unit(unit)
	return unit


## Slot index of [param move] within [param unit]'s moveset -- mirrors
## [method BotTurnDriver._slot_of_move]; [method Unit.perform_move] wants a
## slot, not the [MoveResource] itself.
func _slot_of(unit: Unit, move: MoveResource) -> int:
	var moveset := unit.get_moveset()
	for i in range(moveset.size()):
		if moveset[i] == move:
			return i
	return -1


## Builds a live two-unit board: an AI-owned attacker at (0,0) and a
## human-owned target [param apart] cells away along Z, then rebuilds
## [CombatServices] so [method CombatServices.board] is the live adapter over
## them. Returns {} (a clean "could not build scene, skip" signal) instead of
## crashing if a roster character fails to load.
func _build_live_board(apart: int) -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var ai_player := Player.new(0, "AI")
	ai_player.is_ai = true
	var human_player := Player.new(1, "Human")

	var ai_unit := _spawn_character_unit(_map_root, ATTACKER_ID, Vector2i(0, 0), ai_player)
	var human_unit := _spawn_character_unit(_map_root, TARGET_ID, Vector2i(0, apart), human_player)
	if ai_unit == null or human_unit == null:
		return {}

	await get_tree().process_frame

	CombatServices.rebuild(_map_root)

	return {
		"ai_unit": ai_unit,
		"human_unit": human_unit,
		"board": CombatServices.board(),
	}


# --- Scenario 1: enemy in range -> AI attacks and deals real damage --------

func test_ai_attacks_and_damages_live_enemy_in_range() -> void:
	var scene: Dictionary = await _build_live_board(1)  # adjacent: within cleave's range 1
	if scene.is_empty():
		pending("Could not load roster characters (CharacterLibrary); skipping.")
		return

	var ai_unit: Unit = scene["ai_unit"]
	var human_unit: Unit = scene["human_unit"]
	var board = scene["board"]

	if board == null:
		pending("CombatServices.board() is null after rebuild(); skipping (no live board to plan/execute against).")
		return

	var decision: Dictionary = BotController.new().decide(ai_unit, ai_unit.get_moveset(), board)
	assert_ne(int(decision.get("action", -1)), BotController.ActionType.WAIT,
		"AI should not wait when a live enemy sits in attack range")
	assert_eq(int(decision["action"]), BotController.ActionType.MOVE,
		"a damaging move is available at range 1, so the AI should choose to attack")

	var move: MoveResource = decision["move"]
	assert_not_null(move, "a MOVE decision must carry the chosen move")
	var slot := _slot_of(ai_unit, move)
	assert_true(slot >= 0, "the chosen move must be one of the unit's own moveset slots")

	var start_hp := human_unit.get_hp()

	# Execute exactly what BotTurnDriver._execute_move_decision does: run the
	# real move through Unit.perform_move -> MoveExecutor against the live board.
	var result: Dictionary = ai_unit.perform_move(slot, decision["aim_cell"], board)
	assert_true(bool(result.get("success", false)),
		"perform_move should resolve successfully: %s" % str(result.get("reason", "")))

	assert_lt(human_unit.get_hp(), start_hp,
		"a real attack move executed against the live board should reduce the target's HP")


# --- Scenario 2: enemy far away -> AI advances instead ----------------------

func test_ai_steps_toward_distant_enemy_within_reachable_cells() -> void:
	var scene: Dictionary = await _build_live_board(4)  # far along Z: outside every move's range
	if scene.is_empty():
		pending("Could not load roster characters (CharacterLibrary); skipping.")
		return

	var ai_unit: Unit = scene["ai_unit"]
	var board = scene["board"]

	if board == null:
		pending("CombatServices.board() is null after rebuild(); skipping (no live board to plan against).")
		return

	var decision: Dictionary = BotController.new().decide(ai_unit, ai_unit.get_moveset(), board)
	assert_eq(int(decision.get("action", -1)), BotController.ActionType.STEP,
		"with no move in range, the AI should advance toward the enemy instead of attacking or waiting")

	var profile: MovementProfile = ai_unit.get_movement_profile()
	assert_not_null(profile, "a character-backed unit should expose a movement profile")

	var origin: Vector2i = board.cell_of(ai_unit)
	# The MOVER is passed, exactly as every production caller does: the flood budget is the
	# unit's movement stat, so omitting it here would measure the profile's fallback range
	# instead of the reach the AI actually planned against.
	var reachable: Array[Vector2i] = MovementResolver.new().reachable_cells(
		origin, profile, board, ai_unit)
	assert_true(reachable.has(decision["step_to"]),
		"the chosen step_to cell (%s) must be one MovementResolver actually considers reachable from %s"
			% [decision["step_to"], origin])
