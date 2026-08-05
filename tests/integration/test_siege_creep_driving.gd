extends GutTest

## Integration test for the load-bearing half of Siege's creep design: a creep is owned by the
## side it fights for -- so it is that side's squad's ALLY, which is the whole reason it is not
## given a player slot of its own ([code]BoardAdapter.are_enemies[/code] keys purely on owner,
## so an "ally AI" player would have made a side's own creeps its enemies) -- and it still acts
## by itself, during its owner's turn, even when that owner is the HUMAN.
##
## Built on the same live-board fixture as integration/test_ai_autonomy.gd: real
## CharacterResource-backed [Unit]s, real [CombatServices] / [BoardAdapter], a real turn
## system, and [method BotTurnDriver.act_for_turn_system] called directly (the exact per-unit
## step the driver's Timer normally makes) so nothing depends on wall-clock polling.
##
## Covered here and nowhere else:
##   * the driver acts a HUMAN-owned creep and leaves the human's own units alone;
##   * it does so under BOTH turn systems;
##   * a creep marching a lane walks the LANE rather than at the nearest enemy;
##   * the same adoption path every runtime spawn uses ([method SpawnManager.spawn_and_adopt])
##     really does hand a fresh unit an owner AND a place in the turn order, which is what
##     makes a respawned squad unit act on its owner's next turn.

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

const CREEP_ID: StringName = &"test_siege_creep"
const HERO_ID: StringName = &"test_siege_hero"

var _map_root: Node3D
## Untyped on purpose (see tests/README.md rule 3).
var _guard


func before_each() -> void:
	CombatServices.clear()
	_map_root = null
	_guard = Guard.new()
	_guard.set_setting("ai_difficulty", BotController.Difficulty.NORMAL)
	CharacterLibrary._cache[CREEP_ID] = _make_character(CREEP_ID, "Test Creep")
	CharacterLibrary._cache[HERO_ID] = _make_character(HERO_ID, "Test Hero")


func after_each() -> void:
	CombatServices.clear()
	_map_root = null
	_guard.restore()
	CharacterLibrary.clear_cache()
	# The adoption test points the two autoloads the adoption path reads at its own fixtures;
	# put them back from here so a failing assertion cannot leak them into the next suite.
	if TurnSystemManager != null:
		TurnSystemManager.active_turn_system = null
	if PlayerManager != null:
		PlayerManager.reset_for_new_game()


# --- Fixture ------------------------------------------------------------------

func _make_character(id: StringName, name: String) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = name
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 100
	c.base_attack = 20
	c.base_defense = 8
	c.base_magic = 4
	c.base_magic_defense = 8
	c.base_speed = 10
	c.base_movement = 3
	c.attack_range = 1
	c.moveset = [_strike()] as Array[MoveResource]
	return c


func _strike() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_siege_strike"
	m.display_name = "Test Strike"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.accuracy = 5.0
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 10
	d.scaling_stat = "attack"
	d.scale = 1.0
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(GRID, []).cell_to_world(cell)


func _spawn(character_id: StringName, cell: Vector2i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character
	unit.position = _cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


## A live board: the HUMAN (player 0) fields a hero and a creep; the AI (player 1) fields one
## enemy. Returns {} when the roster/board could not be built.
func _build() -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var human := Player.new(0, "Human")
	var ai := Player.new(1, "AI")
	ai.is_ai = true

	var hero := _spawn(HERO_ID, Vector2i(0, 0), human)
	var creep := _spawn(CREEP_ID, Vector2i(1, 0), human)
	var enemy := _spawn(HERO_ID, Vector2i(0, 4), ai)
	if hero == null or creep == null or enemy == null:
		return {}

	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	return {
		"human": human, "ai": ai,
		"hero": hero, "creep": creep, "enemy": enemy,
		"board": CombatServices.board(),
	}


func _make_driver() -> BotTurnDriver:
	var driver := BotTurnDriver.new()
	add_child_autofree(driver)
	if driver._timer != null:
		driver._timer.stop()
	return driver


# --- The human's turn drives the human's creeps ------------------------------

func test_traditional_the_driver_acts_a_human_owned_creep_and_nothing_else() -> void:
	var scene: Dictionary = await _build()
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var creep: Unit = scene["creep"]
	var hero: Unit = scene["hero"]
	SiegeController.stamp_creep(creep, [Vector2i(1, 0), Vector2i(1, 6)], 3)

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human"])
	ts.register_player(scene["ai"])
	ts.register_unit(hero)
	ts.register_unit(creep)
	ts.register_unit(scene["enemy"])
	ts.start_turn_system()
	assert_false(ts.get_current_active_player().is_ai, "the HUMAN opens the battle")

	var board = scene["board"]
	var hero_cell: Vector2i = board.cell_of(hero)
	var creep_cell: Vector2i = board.cell_of(creep)

	var driver := _make_driver()
	var acted: bool = await driver.act_for_turn_system(ts)

	assert_true(acted, "the driver resolves the human's AI-driven creep on the human's own turn")
	assert_ne(board.cell_of(creep), creep_cell, "the creep acted for itself -- it moved")
	assert_eq(board.cell_of(hero), hero_cell,
		"and the human's own unit was not touched: the player still commands it")

	# With the creep spent, there is nothing left for the driver on this turn.
	var again: bool = await driver.act_for_turn_system(ts)
	assert_false(again,
		"the driver never reaches for a unit the player commands, so the human's turn is theirs")


func test_speed_first_the_driver_acts_a_human_owned_creep_when_the_queue_reaches_it() -> void:
	var scene: Dictionary = await _build()
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var creep: Unit = scene["creep"]
	SiegeController.stamp_creep(creep, [Vector2i(1, 0), Vector2i(1, 6)], 3)

	var ts := SpeedFirstTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human"])
	ts.register_player(scene["ai"])
	ts.register_unit(scene["hero"])
	ts.register_unit(creep)
	ts.register_unit(scene["enemy"])
	ts.start_turn_system()

	var board = scene["board"]
	var driver := _make_driver()

	# Step the queue until the creep's own turn comes up (bounded, never wall-clock).
	var acted_for_creep: bool = false
	var creep_cell: Vector2i = board.cell_of(creep)
	for _i in range(8):
		if ts.current_acting_unit == creep:
			acted_for_creep = await driver.act_for_turn_system(ts)
			break
		ts.advance_turn()

	assert_true(acted_for_creep,
		"under Speed First a human-owned creep's own turn is resolved by the driver too")
	assert_ne(board.cell_of(creep), creep_cell, "and it really acted")


# --- A creep walks its LANE, not at the nearest enemy -------------------------

func test_a_marching_creep_walks_its_lane_rather_than_at_the_nearest_enemy() -> void:
	var scene: Dictionary = await _build()
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var creep: Unit = scene["creep"]
	var enemy: Unit = scene["enemy"]
	var board = scene["board"]

	# Lane runs along +x from the creep; the only enemy is 4 cells away along +y, outside a
	# radius of 1 -- so an ordinary aggressive unit would charge it and a marcher must not.
	SiegeController.stamp_creep(creep, [Vector2i(1, 0), Vector2i(4, 0)], 1)

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human"])
	ts.register_player(scene["ai"])
	ts.register_unit(creep)
	ts.register_unit(scene["hero"])
	ts.register_unit(enemy)
	ts.start_turn_system()

	var enemy_cell: Vector2i = board.cell_of(enemy)
	var start: Vector2i = board.cell_of(creep)
	var driver := _make_driver()
	assert_true(await driver.act_for_turn_system(ts), "the creep acts")

	var landed: Vector2i = board.cell_of(creep)
	assert_gt(landed.x, start.x, "it pushed DOWN THE LANE (+x toward the waypoint)")
	assert_eq(landed.y, start.y,
		"and never stepped toward the enemy on +y -- an out-of-aggro enemy is not its problem")
	assert_gt(_manhattan(landed, enemy_cell), _manhattan(start, enemy_cell),
		"marching down the lane actually took it FURTHER from the enemy, which an ordinary "
		+ "aggressive unit would never do")


# --- Adoption: what makes a respawned unit act next turn ----------------------

func test_spawn_and_adopt_gives_a_runtime_unit_an_owner_and_a_place_in_the_turn_order() -> void:
	# This is the single path BOTH Siege creep waves and Siege squad respawns take, so proving
	# it here proves the adoption for both (CONQUEST.md rule 4: a runtime-spawned unit that is
	# not adopted can neither attack nor be attacked and never gets a turn).
	var scene: Dictionary = await _build()
	if scene.is_empty() or scene["board"] == null:
		pending("Could not build live board (roster/board unavailable); skipping.")
		return

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(scene["human"])
	ts.register_player(scene["ai"])
	ts.start_turn_system()

	# Route the two autoloads the adoption path reads at this test's own fixtures. Assigned
	# directly rather than through activate_turn_system(), which would restart the system and
	# sweep the whole scene for units -- neither of which this test is about. after_each puts
	# both back.
	var human: Player = scene["human"]
	var ai: Player = scene["ai"]
	PlayerManager.reset_for_new_game()
	PlayerManager.players.append(human)
	PlayerManager.players.append(ai)
	TurnSystemManager.active_turn_system = ts

	var fresh: Unit = CHARACTER_UNIT_SCENE.instantiate()
	fresh.character_resource = CharacterLibrary.get_character(HERO_ID)
	fresh.position = _cell_to_world(Vector2i(3, 3))
	_map_root.add_child(fresh)

	var spawner := SpawnManager.new()
	add_child_autofree(spawner)
	spawner._map_loader = _StubLoader.new(fresh)

	var produced = spawner.spawn_and_adopt(
		{"position": Vector2i(3, 3), "player_id": 0, "character_id": String(HERO_ID)}, 0)

	assert_eq(produced, fresh, "the spawner hands back the unit the loader made")
	assert_eq(fresh.get_owner_player(), scene["human"],
		"it is ADOPTED: the owning player is assigned, so are_enemies resolves on both sides")
	assert_true(ts.registered_units.has(fresh),
		"and it is registered with the active turn system, so it actually gets a turn")
	assert_false(fresh.can_act(),
		"but marked already-acted, so it holds this turn and acts on its owner's NEXT one")

	PlayerManager.reset_for_new_game()


## Stands in for MapLoader: hands back one prepared unit.
class _StubLoader extends RefCounted:
	var unit
	func _init(p_unit) -> void:
		unit = p_unit
	func spawn_unit_now(_spawn_data, _count_hint = 0):
		return unit


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
