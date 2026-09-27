extends GutTest

## Unit facing on a LIVE board: real CharacterUnit.tscn units, the real
## CombatServices board, the UnitAnimator autoload's walk and a FacingController.
## After a board move the unit faces its LAST STEP; after the settle pass it faces
## its REST direction (nearest enemy); a move turns attacker and target toward each
## other; the model's yaw follows (incl. the per-character model_yaw_deg).

const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const HERO_ID: StringName = &"test_facing_hero"
const FOE_ID: StringName = &"test_facing_foe"

var _map_root: Node3D
var _fc: FacingController
var _anims_were: bool = true


func before_each() -> void:
	CombatServices.clear()
	CharacterLibrary._cache[HERO_ID] = _make_character(HERO_ID, 0.0)
	CharacterLibrary._cache[FOE_ID] = _make_character(FOE_ID, 180.0)
	_anims_were = GameSettings.animations_enabled
	GameSettings.animations_enabled = true


func after_each() -> void:
	GameSettings.animations_enabled = _anims_were
	CombatServices.clear()
	CharacterLibrary._cache.erase(HERO_ID)
	CharacterLibrary._cache.erase(FOE_ID)
	_map_root = null


func _make_character(id: StringName, yaw: float) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = String(id)
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.model_yaw_deg = yaw
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 200
	c.base_attack = 10
	c.base_defense = 8
	c.base_speed = 10
	c.base_movement = 5
	c.attack_range = 1
	c.moveset = [_strike()] as Array[MoveResource]
	return c


func _strike() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_facing_strike"
	m.display_name = "Strike"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.accuracy = 5.0
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 5
	d.scaling_stat = "attack"
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


func _spawn(id: StringName, cell: Vector3i, owner: Player) -> Unit:
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = CharacterLibrary.get_character(id)
	unit.position = Cells.cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


func _build(hero_cell: Vector3i, foe_cell: Vector3i) -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)
	var p0 := Player.new(0, "Hero")
	var p1 := Player.new(1, "Foe")
	var hero := _spawn(HERO_ID, hero_cell, p0)
	var foe := _spawn(FOE_ID, foe_cell, p1)
	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	_fc = FacingController.new()
	add_child_autofree(_fc)
	await get_tree().process_frame
	return {"hero": hero, "foe": foe, "board": CombatServices.board()}


func _model_yaw(u: Unit) -> float:
	return (u.get_node("CharacterModel") as Node3D).rotation.y


func _assert_yaw(u: Unit, dir: Vector2i) -> void:
	var want := UnitFacing.model_yaw(u.character_resource.model_yaw_deg, dir)
	assert_almost_eq(wrapf(_model_yaw(u) - want, -PI, PI), 0.0, 0.01,
		"model yaw matches facing %s" % dir)


func _wait_until_still(u: Unit) -> void:
	for i in 240:
		if not UnitAnimator.is_moving(u) and not u.is_turning():
			return
		await get_tree().process_frame


func test_rest_facing_on_board_ready_and_model_yaw() -> void:
	var s: Dictionary = await _build(Vector3i(1, 6, 0), Vector3i(1, 1, 0))
	_fc.settle_all(true)
	assert_eq(s.hero.get_facing(), Vector2i(0, -1), "hero looks north at the foe")
	assert_eq(s.foe.get_facing(), Vector2i(0, 1), "foe looks south at the hero")
	_assert_yaw(s.hero, Vector2i(0, -1))
	_assert_yaw(s.foe, Vector2i(0, 1))  # includes its 180 deg model correction


func test_walk_faces_last_step_then_settles_to_rest() -> void:
	var s: Dictionary = await _build(Vector3i(1, 6, 0), Vector3i(6, 1, 0))
	var hero: Unit = s.hero
	var board = s.board
	_fc.settle_all(true)
	# Walk north twice then east twice: (1,6) -> (1,4) -> (3,4).
	var route: Array[Vector3i] = [Vector3i(1, 6, 0), Vector3i(1, 5, 0), Vector3i(1, 4, 0),
		Vector3i(2, 4, 0), Vector3i(3, 4, 0)]
	board.move_unit(hero, Vector3i(3, 4, 0))
	UnitAnimator.walk_path(hero, route)
	await _wait_until_still(hero)
	assert_eq(hero.get_facing(), Vector2i(1, 0), "faces the last step (east)")
	_assert_yaw(hero, Vector2i(1, 0))
	# The settle pass: foe (6,1) is 3 east / 3 north -> an exact diagonal, and the
	# current facing (east) is one of the two candidates -> no churn, stays east.
	_fc.settle_all(false)
	assert_eq(hero.get_facing(), UnitFacing.rest_facing(UnitFacing.unit_center(hero, board),
		[UnitFacing.unit_center(s.foe, board)], Vector2i(1, 0)))
	assert_eq(hero.get_facing(), Vector2i(1, 0))
	# Now step next to the foe's row: rest facing flips to north.
	board.move_unit(hero, Vector3i(6, 4, 0))
	UnitAnimator.walk_path(hero, [Vector3i(3, 4, 0), Vector3i(4, 4, 0), Vector3i(5, 4, 0), Vector3i(6, 4, 0)])
	await _wait_until_still(hero)
	assert_eq(hero.get_facing(), Vector2i(1, 0))
	_fc.settle_all(false)
	await _wait_until_still(hero)
	assert_eq(hero.get_facing(), Vector2i(0, -1), "settled toward the nearest enemy")
	_assert_yaw(hero, Vector2i(0, -1))


func test_unit_moved_event_schedules_a_settle() -> void:
	var s: Dictionary = await _build(Vector3i(1, 6, 0), Vector3i(1, 1, 0))
	var hero: Unit = s.hero
	_fc.settle_all(true)
	hero.set_facing(Vector2i(1, 0), 0.0)  # e.g. just walked east
	GameEvents.unit_moved.emit(hero, Cells.to_grid(Vector3i(1, 6, 0)), Cells.to_grid(Vector3i(1, 6, 0)))
	for i in 120:
		if hero.get_facing() == Vector2i(0, -1):
			break
		await get_tree().process_frame
	assert_eq(hero.get_facing(), Vector2i(0, -1), "the controller settled after unit_moved")


func test_attack_turns_attacker_and_defender_toward_each_other() -> void:
	var s: Dictionary = await _build(Vector3i(3, 3, 0), Vector3i(4, 3, 0))
	var hero: Unit = s.hero
	var foe: Unit = s.foe
	hero.set_facing(Vector2i(0, 1), 0.0)
	foe.set_facing(Vector2i(0, -1), 0.0)
	var res: Dictionary = hero.perform_move(0, Vector3i(4, 3, 0), s.board)
	assert_true(bool(res.get("success", false)), "strike resolves: %s" % res.get("reason", ""))
	assert_eq(hero.get_facing(), Vector2i(1, 0), "attacker faces its aim")
	assert_eq(foe.get_facing(), Vector2i(-1, 0), "defender faces the attacker")


func test_facing_is_not_in_the_net_digest() -> void:
	var s: Dictionary = await _build(Vector3i(3, 3, 0), Vector3i(4, 6, 0))
	var rules := NetGameRules.new(func(): return s.board, func(): return null)
	var before: int = rules.state_digest()
	s.hero.set_facing(Vector2i(-1, 0), 0.0)
	s.foe.set_facing(Vector2i(1, 0), 0.0)
	assert_eq(rules.state_digest(), before, "facing never changes the lockstep digest")
