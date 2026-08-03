extends GutTest

# BOOTING A BATTLE FROM A MAP THAT DID NOT SHIP WITH THE GAME.
#
# A map received from a networked host is materialised as inert JSON in the session directory
# (MapCatalog.install_session_payload). For that to be worth anything, the ordinary battle boot
# has to be able to LOAD it -- and it must do so through the hardened importer, never
# ResourceLoader (CONQUEST.md convention 8: a shared .tres is an arbitrary-code-execution
# vector).
#
# MapLoader.load_map_from_file is the single seam every battle boot already goes through
# (GameWorldManager._load_selected_map hands it GameSettings.selected_map). Routing .json there
# means custom, community and host-shipped maps all reach the board by ONE path, and nothing
# above it had to learn about map sources at all.
#
# Follows integration/test_net_host_squad.gd's map-load pattern: a real MapLoader under a real
# Node3D, and the shared CombatServices board cleared in BOTH hooks so one map load can never
# be read by the next suite.

const SESSION_DIR := "user://test_session_map_boot/"

const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose (tests/README.md rule 3): a `: RefCounted` annotation makes the static
## analyser reject _guard.watch_setting().
var _guard


func before_each() -> void:
	_guard = Guard.new()
	# player 0's slots are filled from the local pick when one is set; empty means "the map's
	# own authored roster", which is what this suite is asserting about. set_setting snapshots
	# AND assigns the field directly -- never the persisting GameSettings setter.
	_guard.set_setting("selected_squad", [])
	_guard.set_setting("host_squad", [])
	MatchLoadouts.clear()
	MapCatalog.set_session_maps_dir(SESSION_DIR)
	_wipe()
	_clear_combat_services()


func after_each() -> void:
	_guard.restore()
	MatchLoadouts.clear()
	_wipe()
	MapCatalog.reset_paths()
	_clear_combat_services()


func _wipe() -> void:
	var dir: DirAccess = DirAccess.open(SESSION_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_DIR))


func _clear_combat_services() -> void:
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("clear"):
		CombatServices.clear()


# --- fixtures ----------------------------------------------------------------

## Roster id every spawn in the fixture fields. This is MapLoader.DEFAULT_CHARACTER_ID -- the
## loader's own guaranteed fallback -- so it always resolves against the live CharacterLibrary
## and is never difficulty-gated. Spelled out rather than referenced because a const must be a
## constant expression; [method _roster_has_fixture_character] keeps the two honest.
const FIXTURE_CHARACTER := "vineweave"


## True when the fixture's character is really on the roster (it is also the loader's declared
## default, so this failing means the roster, not this suite, moved).
func _roster_has_fixture_character() -> bool:
	if String(MapLoader.DEFAULT_CHARACTER_ID) != FIXTURE_CHARACTER:
		return false
	for id in CharacterLibrary.all_ids():
		if String(id) == FIXTURE_CHARACTER:
			return true
	return false


## The payload a host would ship for a map it authored: valid by construction, renamed so the
## loaded board can be identified as THIS map rather than any shipped one.
##
## Every Start point is given an explicit character: the engine's default layout leaves them as
## UNASSIGNED SLOTS (unit_type only, no unit reference), which load as an empty board on
## purpose -- fine for a validation fixture, useless for one that asserts units spawned.
func _hosts_payload() -> Dictionary:
	var res: MapResource = MapLoader.create_default_map()
	res.map_name = "Hosts Own Arena"
	for spawn_data in res.unit_spawns:
		(spawn_data as Dictionary)["character_id"] = FIXTURE_CHARACTER
	var json := JSON.new()
	if json.parse(res.export_to_json()) != OK or not (json.data is Dictionary):
		return {}
	return json.data


## Load [param map_path] the way a battle boot does, and report what landed on the board.
func _boot(map_path: String) -> Dictionary:
	var root3d := Node3D.new()
	add_child_autofree(root3d)
	var loader := MapLoader.new()
	root3d.add_child(loader)

	var loaded: bool = loader.load_map_from_file(map_path, root3d)

	var units_per_player: Array = []
	for player_index in [1, 2]:
		var container := root3d.get_node_or_null("Player" + str(player_index))
		units_per_player.append(container.get_child_count() if container != null else 0)

	return {
		"loaded": loaded,
		"map_name": loader.current_map.map_name if loader.current_map != null else "",
		"units": units_per_player,
	}


# --- the boot ----------------------------------------------------------------

func test_a_host_shipped_map_installs_and_boots() -> void:
	if not _roster_has_fixture_character():
		pending("the roster has no '%s' character to build a spawning fixture from" % FIXTURE_CHARACTER)
		return
	var path: String = MapCatalog.install_session_payload(_hosts_payload())
	assert_false(path.is_empty(), "the host's payload passed the strict gate and was written")

	var result: Dictionary = _boot(path)

	assert_true(bool(result["loaded"]),
		"the ordinary battle boot loads a session map -- no new entry point was needed")
	assert_eq(String(result["map_name"]), "Hosts Own Arena",
		"and the board is the HOST's map, not a fallback")
	assert_gt(int((result["units"] as Array)[0]), 0, "player 0's side spawned")
	assert_gt(int((result["units"] as Array)[1]), 0, "and so did player 1's -- it is a versus map")


func test_a_builtin_still_boots_exactly_as_before() -> void:
	var result: Dictionary = _boot("res://game/maps/resources/default_skirmish.tres")

	assert_true(bool(result["loaded"]), "the .tres path is untouched by the .json routing")
	assert_gt(int((result["units"] as Array)[0]), 0, "and still fills the board")


func test_a_missing_json_map_fails_without_crashing() -> void:
	var result: Dictionary = _boot(SESSION_DIR + "never_written.json")

	assert_false(bool(result["loaded"]),
		"a missing session map reports failure through the return value (the caller falls back)")


func test_a_json_map_that_fails_the_gate_is_not_loaded() -> void:
	# The seam must not become a way to smuggle an unvalidated map onto the board: the file is
	# on disk and addressed by path, and the importer still refuses it.
	DirAccess.make_dir_recursive_absolute(SESSION_DIR)
	var path: String = SESSION_DIR + "smuggled.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"map_info": {"name": "Smuggled"}, "layout": {"tiles": [], "unit_spawns": []}}))
	file.close()

	var result: Dictionary = _boot(path)

	assert_false(bool(result["loaded"]), "a map with no second side never reaches the board")
