extends GutTest

## A battle's turn start applies the weather: real roster Units (character-backed,
## with their abilities) on a live CombatServices board, ticked by a real
## TraditionalTurnSystem. Covers the round-driven schedule, Desert Storm chip +
## Geode's Sand Veil, Rain + Mycothrall's Rain Bath, Overbloom healing.

const GRID: Grid = preload("res://board/Grid.tres")

var _root: Node3D


func before_each() -> void:
	CombatServices.clear()
	_root = Node3D.new()
	add_child_autofree(_root)


func after_each() -> void:
	CombatServices.clear()


func _unit(character: String, cell: Vector3i) -> Unit:
	var u := Unit.new()
	u.character_resource = load("res://game/characters/roster/%s.tres" % character)
	_root.add_child(u)
	u.global_position = Cells.cell_to_world(cell) + Vector3(0, 0.1, 0)
	return u


func _setup() -> Dictionary:
	var myco := _unit("mycothrall", Vector3i(1, 1, 0))
	var geode := _unit("gem_knight", Vector3i(4, 1, 0))
	var necro := _unit("necromancer", Vector3i(6, 1, 0))
	CombatServices._board = BoardAdapter.new(GRID, _root)
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var p1 := Player.new(0, "P1")
	var p2 := Player.new(1, "P2")
	p1.add_unit(myco)
	p2.add_unit(geode)
	p2.add_unit(necro)
	ts.register_player(p1)
	ts.register_player(p2)
	return { "ts": ts, "myco": myco, "geode": geode, "necro": necro }


func test_desert_storm_turn_start_chips_and_veils() -> void:
	var s := _setup()
	CombatServices.configure_weather(_map({ "mode": "fixed", "weather": "desert_storm" }), 1)
	var ts: TraditionalTurnSystem = s["ts"]
	var myco: Unit = s["myco"]
	var geode: Unit = s["geode"]
	var necro: Unit = s["necro"]
	var myco_max := myco.max_health
	var necro_max := necro.max_health
	for u in [myco, geode, necro]:
		ts._tick_unit_turn_start(u)
	assert_eq(myco.current_health, myco_max - maxi(1, myco_max / 16), "nature unit chipped 1/16")
	assert_eq(necro.current_health, necro_max - maxi(1, necro_max / 16), "dark unit chipped 1/16")
	assert_eq(geode.current_health, geode.max_health, "earth unit immune")
	assert_eq(geode.get_stat("evasion"), 15, "Sand Veil fired at Geode's turn start")


func test_rain_bath_and_schedule_follow_the_round() -> void:
	var s := _setup()
	# Round 1 clear, round 2 rain (2 players -> current_turn 3 is round 2).
	CombatServices.configure_weather(_map({ "mode": "schedule",
		"schedule": [{ "weather": "clear", "rounds": 1 }, { "weather": "rain", "rounds": 1 }] }), 1)
	var ts: TraditionalTurnSystem = s["ts"]
	var myco: Unit = s["myco"]
	myco.take_damage(30)
	var hurt := myco.current_health
	ts._tick_unit_turn_start(myco)
	assert_eq(Weather.current_id(), &"clear")
	assert_eq(myco.current_health, hurt, "no Rain Bath on a clear round")
	ts.current_turn = 3
	ts._tick_unit_turn_start(myco)
	assert_eq(Weather.current_id(), &"rain", "round 2 brings the rain")
	assert_eq(myco.current_health, hurt + roundi(myco.max_health * 0.125), "Rain Bath heals 1/8")
	ts.current_turn = 5
	ts._tick_unit_turn_start(myco)
	assert_eq(Weather.current_id(), &"clear", "the schedule loops")


func test_overbloom_heals_nature_units_at_turn_start() -> void:
	var s := _setup()
	CombatServices.configure_weather(_map({ "mode": "fixed", "weather": "overbloom" }), 1)
	var ts: TraditionalTurnSystem = s["ts"]
	var myco: Unit = s["myco"]
	var necro: Unit = s["necro"]
	myco.take_damage(10)
	necro.take_damage(10)
	var m := myco.current_health
	var n := necro.current_health
	ts._tick_unit_turn_start(myco)
	ts._tick_unit_turn_start(necro)
	assert_eq(myco.current_health, m + roundi(myco.max_health * 0.1), "nature regrowth")
	assert_eq(necro.current_health, n, "dark unit does not bloom")


func _map(settings: Dictionary) -> MapResource:
	var m := MapResource.new()
	m.set_weather_settings(settings)
	return m
