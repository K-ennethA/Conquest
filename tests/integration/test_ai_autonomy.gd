extends GutTest

## Integration test: proves an AI-controlled player acts AUTONOMOUSLY through the
## turn system + [BotTurnDriver], for BOTH turn systems.
##
## Unlike tests/integration/test_ai_live_board.gd (which calls BotController.decide
## / Unit.perform_move directly), this test exercises the DRIVER's public act step
## against a real turn system:
##   1. Build a live two-unit board (real CharacterResource-backed units, real
##      CombatServices / BoardAdapter / MoveExecutor).
##   2. Register a human player and an AI player (is_ai = true) with a real turn
##      system and start it.
##   3. Advance to the AI player's turn.
##   4. Call BotTurnDriver.act_for_turn_system(ts) -- the exact per-unit step the
##      0.4s Timer normally calls -- WITHOUT the Timer.
##   5. Assert the world changed: the enemy took damage (attack) or the AI unit
##      moved toward the enemy (advance). An inert AI (the bug) changes nothing.
##
## This is the seam the driver was refactored to expose (act_for_turn_system), so
## autonomy is verifiable headlessly and does not depend on wall-clock polling.
##
## TurnSystemManager (autoload) is NOT used to register/activate the system here:
## act_for_turn_system(ts) takes the turn system directly, so the test owns a fresh
## TraditionalTurnSystem / SpeedFirstTurnSystem instance and there is no autoload
## cross-test state to reset. (act_one_ai_unit(), by contrast, would read the
## TurnSystemManager autoload's active system.)

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

# Deterministic synthetic combatants (built in code and injected into
# CharacterLibrary in before_each) instead of roster units: the attacker carries
# ONE range-1 strike whose accuracy overshoots any evasion, so the adjacent
# "HP must drop" assertion never rides on a probabilistic hit, and its ONLY reach
# is range 1 so the "must close the distance" scenarios (dist 3/4) stay out of range.
const ATTACKER_ID: StringName = &"test_ai_attacker"
const TARGET_ID: StringName = &"test_ai_target"

var _map_root: Node3D
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose: a `: RefCounted` annotation would make the static analyser reject
## _guard.set_setting() / .watch_file() as "not found in base RefCounted".
var _guard


func before_each() -> void:
	CombatServices.clear()
	_map_root = null
	# Pin NORMAL difficulty so the AI is deterministic (EASY dithers via RNG); the
	# driver reads this from the GameSettings autoload, which other tests may touch.
	# The guard restores it from after_each, which runs on the failure path too.
	_guard = Guard.new()
	_guard.set_setting("ai_difficulty", BotController.Difficulty.NORMAL)
	_install_test_characters()


func after_each() -> void:
	CombatServices.clear()
	_map_root = null
	_guard.restore()
	# Evict the injected synthetic characters so they never leak into other suites.
	CharacterLibrary.clear_cache()


# --- Helpers -----------------------------------------------------------------

func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(GRID, []).cell_to_world(cell)


## Build the two throwaway combatants and inject them straight into the
## CharacterLibrary cache so _spawn_character_unit -> CharacterLibrary.get_character
## resolves them without any .tres on disk.
func _install_test_characters() -> void:
	CharacterLibrary._cache[ATTACKER_ID] = _make_test_character(ATTACKER_ID, "Test Attacker", 100, 34)
	CharacterLibrary._cache[TARGET_ID] = _make_test_character(TARGET_ID, "Test Target", 90, 20)


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


## A range-1 physical strike whose accuracy (5.0) overshoots any target evasion, so
## hit% clamps to 100 -- the attack ALWAYS lands. Non-lethal against the target HP
## above, so the struck unit survives and get_hp() stays valid for the assert.
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


func _spawn_character_unit(map_root: Node3D, character_id: StringName, cell: Vector2i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character  # set before add_child so _ready() builds stats
	unit.position = _cell_to_world(cell)
	map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


## Build a live board with an AI-owned attacker and a human-owned target [param apart]
## cells apart along Z. Returns {} (skip signal) if a roster character fails to load.
func _build_scene(apart: int) -> Dictionary:
	return await _build_scene_cells(Vector2i(0, 0), Vector2i(0, apart))


## Build a live board with the AI attacker on [param ai_cell] and the human target
## on [param target_cell] (both must lie within the 5x5 grid). Returns {} if a
## roster character fails to load.
func _build_scene_cells(ai_cell: Vector2i, target_cell: Vector2i) -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	# player_id 0 = human (so ownership / player-1 mirrors the live game), 1 = AI.
	var human_player := Player.new(0, "Human")
	var ai_player := Player.new(1, "AI")
	ai_player.is_ai = true

	var ai_unit := _spawn_character_unit(_map_root, ATTACKER_ID, ai_cell, ai_player)
	var human_unit := _spawn_character_unit(_map_root, TARGET_ID, target_cell, human_player)
	if ai_unit == null or human_unit == null:
		return {}

	await get_tree().process_frame
	CombatServices.rebuild(_map_root)

	return {
		"human_player": human_player,
		"ai_player": ai_player,
		"ai_unit": ai_unit,
		"human_unit": human_unit,
		"board": CombatServices.board(),
	}


## A BotTurnDriver in the tree (so its /root/GameSettings lookup resolves) but with
## its poll Timer stopped -- this test drives the AI deterministically instead.
func _make_driver() -> BotTurnDriver:
	var driver := BotTurnDriver.new()
	add_child_autofree(driver)
	if driver._timer != null:
		driver._timer.stop()
	return driver


# --- Traditional: AI attacks an adjacent enemy -------------------------------

func test_traditional_ai_attacks_adjacent_enemy() -> void:
	var scene: Dictionary = await _build_scene(1)  # adjacent: within cleave range 1
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human_player"])  # registered_players[0] -> starts on human
	ts.register_player(scene["ai_player"])
	ts.start_turn_system()

	# Advance out of the human's turn and into the AI's turn.
	ts.end_turn_manually()
	assert_true(ts.get_current_active_player() == scene["ai_player"],
		"turn should have advanced to the AI player")
	assert_true(ts.get_current_active_player().is_ai, "the active player must be flagged AI")

	var human_unit: Unit = scene["human_unit"]
	var start_hp := human_unit.get_hp()

	var driver := _make_driver()
	var acted: bool = await driver.act_for_turn_system(ts)

	assert_true(acted, "the driver should act for the AI player (not sit inert)")
	assert_lt(human_unit.get_hp(), start_hp,
		"AI autonomously attacked the adjacent enemy, so its HP must drop")


# --- Traditional: AI advances toward a distant enemy -------------------------

func test_traditional_ai_advances_toward_distant_enemy() -> void:
	var scene: Dictionary = await _build_scene(4)  # far: outside every move's range
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human_player"])
	ts.register_player(scene["ai_player"])
	ts.start_turn_system()
	ts.end_turn_manually()  # -> AI turn
	assert_true(ts.get_current_active_player() == scene["ai_player"], "should reach AI turn")

	var board = scene["board"]
	var ai_unit: Unit = scene["ai_unit"]
	var human_unit: Unit = scene["human_unit"]
	var start_cell: Vector2i = board.cell_of(ai_unit)
	var start_dist := _manhattan(start_cell, board.cell_of(human_unit))

	var driver := _make_driver()
	var acted: bool = await driver.act_for_turn_system(ts)

	assert_true(acted, "the driver should act for the AI player (not sit inert)")
	var end_cell: Vector2i = board.cell_of(ai_unit)
	assert_ne(end_cell, start_cell, "AI with no enemy in range should move (its cell changes)")
	assert_lt(_manhattan(end_cell, board.cell_of(human_unit)), start_dist,
		"the AI's move should reduce the distance to the enemy (advance toward it)")


# --- Traditional: AI closes the gap AND attacks in the same turn -------------

## The key move-then-attack fix: an enemy 3 cells away is beyond every move's range
## from the origin, but reachable within the unit's movement range. In ONE turn the
## AI must walk adjacent and strike -- the cell changes AND the target takes damage.
func test_traditional_ai_moves_into_range_and_attacks_same_turn() -> void:
	var scene: Dictionary = await _build_scene(3)  # 2 cells past cleave range 1, inside move+attack
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human_player"])
	ts.register_player(scene["ai_player"])
	ts.start_turn_system()
	ts.end_turn_manually()  # -> AI turn
	assert_true(ts.get_current_active_player() == scene["ai_player"], "should reach AI turn")

	var board = scene["board"]
	var ai_unit: Unit = scene["ai_unit"]
	var human_unit: Unit = scene["human_unit"]
	var start_cell: Vector2i = board.cell_of(ai_unit)
	var start_hp := human_unit.get_hp()

	var driver := _make_driver()
	var acted: bool = await driver.act_for_turn_system(ts)

	assert_true(acted, "the driver should act for the AI player (not sit inert)")
	assert_ne(board.cell_of(ai_unit), start_cell,
		"the AI must move up to the enemy (it starts out of every move's range)")
	# Move-then-attack is SPLIT across two beats so each is watchable: the first beat
	# slid the unit into range; the strike lands on the next. Drive one more beat to
	# resolve it -- still the SAME turn (the unit never yielded, it just spread its
	# move and its strike over two readable moments).
	if human_unit.get_hp() >= start_hp:
		await driver.act_for_turn_system(ts)
	assert_lt(human_unit.get_hp(), start_hp,
		"after closing the gap the AI attacks the same turn, so the enemy's HP drops")


# --- Traditional: AI advances its FULL move range, not one cell --------------

## Regression for the "creeps one cell" bug: with the enemy too far to reach even
## after a full move, the AI must still advance MORE THAN ONE cell (about its whole
## movement range) toward it -- not inch forward a single tile.
func test_traditional_ai_advances_full_move_range_not_one_cell() -> void:
	# Enemy at the far corner (Manhattan 8 away) on the 5x5 grid: movement range 3
	# cannot bring it into any move's range (max reach 1), so this is a pure advance.
	var scene: Dictionary = await _build_scene_cells(Vector2i(0, 0), Vector2i(4, 4))
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human_player"])
	ts.register_player(scene["ai_player"])
	ts.start_turn_system()
	ts.end_turn_manually()  # -> AI turn
	assert_true(ts.get_current_active_player() == scene["ai_player"], "should reach AI turn")

	var board = scene["board"]
	var ai_unit: Unit = scene["ai_unit"]
	var human_unit: Unit = scene["human_unit"]
	var start_cell: Vector2i = board.cell_of(ai_unit)
	var start_dist := _manhattan(start_cell, board.cell_of(human_unit))

	var driver := _make_driver()
	var acted: bool = await driver.act_for_turn_system(ts)

	assert_true(acted, "the driver should act for the AI player (not sit inert)")
	var end_cell: Vector2i = board.cell_of(ai_unit)
	assert_gt(_manhattan(start_cell, end_cell), 1,
		"the AI must use its full movement range in one turn, not creep a single cell")
	assert_lt(_manhattan(end_cell, board.cell_of(human_unit)), start_dist,
		"advancing must reduce the distance to the enemy")


# --- Speed First: parity (same AI driving, only the order differs) ------------

func test_speed_first_ai_acts_on_its_unit_turn() -> void:
	var scene: Dictionary = await _build_scene(1)  # adjacent
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var ts := SpeedFirstTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human_player"])
	ts.register_player(scene["ai_player"])
	ts.start_turn_system()

	# Speed First orders by speed, so the acting unit may start on either side.
	# Advance the queue until the AI unit is the current acting unit (its turn).
	var guard := 0
	while ts.get_current_active_player() != scene["ai_player"] and guard < 8:
		ts.advance_turn()
		guard += 1

	if ts.get_current_active_player() != scene["ai_player"]:
		pending("Could not reach the AI unit's turn in Speed First within the queue; skipping.")
		return
	assert_true(ts.get_current_active_player().is_ai, "the acting unit's owner must be AI")

	var human_unit: Unit = scene["human_unit"]
	var board = scene["board"]
	var start_hp := human_unit.get_hp()
	var ai_unit: Unit = scene["ai_unit"]
	var start_cell: Vector2i = board.cell_of(ai_unit)

	var driver := _make_driver()
	var acted: bool = await driver.act_for_turn_system(ts)

	assert_true(acted, "the driver should act the AI's current unit in Speed First too")
	# Adjacent enemy: expect an attack; accept a move as well so the assertion tracks
	# "the AI did SOMETHING autonomous" rather than a specific move choice.
	var changed: bool = human_unit.get_hp() < start_hp or board.cell_of(ai_unit) != start_cell
	assert_true(changed,
		"AI acting in Speed First must change the world (damage dealt or unit moved)")


# --- small helper ------------------------------------------------------------

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
