extends GutTest

## MapLoader + CombatServices on a multi-floor map (the bridge fixture): per-floor
## tile containers and node names, floor heights, upper-floor spawns, link markers,
## and the live board seeing the floors/links. Runs in GUT's real tree + autoloads.

const MAP_PATH := "res://game/maps/resources/test_bridge_map.tres"

var _saved_squad: Array = []
var _root: Node3D


func before_each() -> void:
	if GameSettings != null:
		_saved_squad = GameSettings.get_selected_squad()
		GameSettings.set_selected_squad([])
	CombatServices.clear()
	_root = Node3D.new()
	add_child_autofree(_root)
	var loader := MapLoader.new()
	_root.add_child(loader)
	assert_true(loader.load_map(load(MAP_PATH), _root), "fixture loads")


func after_each() -> void:
	CombatServices.clear()
	if GameSettings != null:
		GameSettings.set_selected_squad(_saved_squad)


func test_tiles_are_grouped_per_floor_at_floor_height() -> void:
	var deck := _root.get_node_or_null("Tiles/Floor_1/Tile_3_1_1") as Node3D
	assert_not_null(deck, "floor-1 tiles live under Tiles/Floor_1 named Tile_x_y_f")
	assert_almost_eq(deck.position.y, Cells.FLOOR_HEIGHT, 0.001)
	var ground := _root.get_node_or_null("Tiles/Floor_0/Tile_3_1_0") as Node3D
	assert_not_null(ground, "the ground under the bridge still exists")
	assert_almost_eq(ground.position.y, 0.0, 0.001)
	assert_null(_root.get_node_or_null("Tiles/Floor_1/Tile_4_3_1"), "no tile in the broken-bridge gap")
	assert_eq(_root.get_node("Tiles/Floor_1").get_child_count(), 9)
	assert_eq(_root.get_node("Tiles/Floor_0").get_child_count(), 9 * 7, "floor 0 is full")
	var links := _root.get_node_or_null("Tiles/Links")
	assert_not_null(links, "simple link markers are rendered")
	assert_eq(links.get_child_count(), 4)


func test_upper_floor_spawn_stands_on_the_deck() -> void:
	var archer: Node3D = null
	for u in _root.get_node("Player2").get_children():
		if u.get("character_resource") != null and String(u.character_resource.character_id) == "petalfang":
			archer = u
	assert_not_null(archer, "the floor-1 spawn was placed")
	assert_almost_eq(archer.position.y, Cells.FLOOR_HEIGHT + MapLoader.UNIT_GROUND_Y, 0.001)
	assert_eq(archer.get_home_cell(), Vector3i(5, 1, 1), "home cell carries the floor")


func test_live_board_sees_floors_and_links() -> void:
	CombatServices.rebuild(_root)
	var b := CombatServices.board()
	assert_not_null(b)
	assert_eq(b.floor_count(), 2)
	assert_true(b.has_tile(Vector3i(2, 3, 1)))
	assert_false(b.has_tile(Vector3i(4, 3, 1)))
	assert_true(b.are_linked(Vector3i(1, 1, 0), Vector3i(2, 1, 1)))
	assert_eq(b.links().size(), 4)
	assert_eq(b.units_on_floor(1).size(), 1, "the archer on the bridge")
	# set_tile finds the per-floor tile node.
	assert_not_null(b._tile_node_at(Vector3i(3, 1, 1)))
	assert_not_null(b._tile_node_at(Vector3i(3, 1, 0)))
