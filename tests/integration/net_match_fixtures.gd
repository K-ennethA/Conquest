extends RefCounted
## Shared game fixtures for the multi-peer network tests (commit-reveal RNG,
## dedicated server): per-peer worlds of real CharacterResource-backed [Unit]s on
## a [BoardAdapter], a turn-system node and a [NetGameRules]. Mirrors the
## fixtures in test_net_match.gd.

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

const FIGHTER_ID: StringName = &"test_netfx_fighter"

## slot 0: (0,0) and (4,0); slot 1: (0,1) (adjacent to 0:0) and (4,4).
const LAYOUT := [
	{"id": FIGHTER_ID, "cell": Vector3i(0, 0, 0), "owner": 0},
	{"id": FIGHTER_ID, "cell": Vector3i(4, 0, 0), "owner": 0},
	{"id": FIGHTER_ID, "cell": Vector3i(0, 1, 0), "owner": 1},
	{"id": FIGHTER_ID, "cell": Vector3i(4, 4, 0), "owner": 1},
]


static func register_characters() -> void:
	CharacterLibrary._cache[FIGHTER_ID] = make_character(FIGHTER_ID, "Fighter", 12)


## Slot 0: sure-hit range-1 strike; slot 1: 50% "coin" strike at range 1-4.
static func make_character(id: StringName, display: String, speed: int) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = display
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 1000
	c.base_attack = 20
	c.base_defense = 5
	c.base_magic = 4
	c.base_magic_defense = 5
	c.base_speed = speed
	c.base_movement = 3
	c.attack_range = 1
	c.moveset = [strike(&"netfx_sure", 5.0, 1), strike(&"netfx_coin", 0.5, 4)] as Array[MoveResource]
	return c


static func strike(id: StringName, accuracy: float, max_range: int) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id
	m.display_name = String(id)
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.accuracy = accuracy
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = max_range
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 10
	d.scaling_stat = "attack"
	d.scale = 1.0
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


## Build one peer's copy of the game under [param parent].
static func build_world(parent: Node, seed_value: int, layout: Array = LAYOUT) -> Dictionary:
	var world := Node3D.new()
	world.name = "World"
	parent.add_child(world)
	var map := Node3D.new()
	map.name = "Map"
	world.add_child(map)
	var players: Array = [Player.new(0, "P1"), Player.new(1, "P2")]
	for spec in layout:
		var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
		unit.character_resource = CharacterLibrary.get_character(spec["id"])
		unit.position = BoardAdapter.new(GRID, []).cell_to_world(spec["cell"])
		map.add_child(unit)
		players[spec["owner"]].add_unit(unit)
	var ts: TurnSystemBase = TraditionalTurnSystem.new()
	world.add_child(ts)
	for p in players:
		ts.register_player(p)
	ts.start_turn_system()
	var board := BoardAdapter.new(GRID, map)
	var rules := NetGameRules.new(func(): return board, func(): return ts, seed_value)
	rules.assign_initial_ids()
	return {"world": world, "map": map, "players": players, "ts": ts, "board": board, "rules": rules}


static func hp(world: Dictionary, unit_id: String) -> int:
	var u = world["rules"].find_unit(unit_id)
	return u.get_hp() if u != null else -1


static func cell(world: Dictionary, unit_id: String) -> Vector3i:
	var u = world["rules"].find_unit(unit_id)
	return world["board"].cell_of(u) if u != null else Vector3i(-99, -99, 0)
