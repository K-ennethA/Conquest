extends GutTest

## Character Select -> MapLoader override: with GameSettings.selected_squad set, player 0's
## spawn slots are filled with the CHOSEN units (in order), and a squad shorter than the
## map's player-0 slot count leaves the surplus slots empty. Empty squad = the map's own
## authored roster (backward compatible). Runs in GUT's real tree + autoloads.

const MAP_PATH := "res://game/maps/resources/proving_grounds.tres"

var _saved_squad: Array = []

func before_each() -> void:
	if GameSettings != null:
		_saved_squad = GameSettings.get_selected_squad()

func after_each() -> void:
	if GameSettings != null:
		GameSettings.set_selected_squad(_saved_squad)


func _player0_ids(map_root: Node) -> Array:
	var p1 = map_root.get_node_or_null("Player1")  # player_id 0 -> "Player1" container
	var ids: Array = []
	if p1 != null:
		for u in p1.get_children():
			var cr = u.get("character_resource")
			if cr != null:
				ids.append(String(cr.character_id))
	ids.sort()
	return ids


func _load_with_squad(squad: Array) -> Node3D:
	GameSettings.set_selected_squad(squad)
	var mapres = load(MAP_PATH)
	var root3d := Node3D.new()
	add_child_autofree(root3d)
	var loader = MapLoader.new()
	root3d.add_child(loader)
	loader.load_map(mapres, root3d)
	return root3d


func test_chosen_squad_replaces_player0_units():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	var root3d := _load_with_squad(["gem_knight", "necromancer"])
	var ids := _player0_ids(root3d)
	assert_eq(ids, ["gem_knight", "necromancer"],
		"player 0 fields exactly the chosen squad (surplus map slots left empty)")


func test_empty_squad_keeps_the_maps_own_roster():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	var root3d := _load_with_squad([])
	var ids := _player0_ids(root3d)
	assert_gt(ids.size(), 2,
		"with no squad chosen the map fields its full authored player-0 roster")
	assert_true(ids.has("vineweave"),
		"the mirror's authored player-0 lead (Vineweave) is present when no squad is chosen")
