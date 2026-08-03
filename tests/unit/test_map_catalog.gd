extends GutTest

# MapCatalog -- the ONE listing API behind "which maps may a match be played on".
#
# What it has to get right, and why each rule exists:
#   * the three SOURCES are distinguishable (builtin / custom / community), because a picker
#     badges them and because only non-builtins have to be transmitted to an opponent;
#   * a file that fails the catalog-strict gate is NEVER LISTED. A corrupt or hostile download
#     that reached the library must not be offerable -- picking it would fail at battle load,
#     or worse, load differently on the two peers;
#   * versus needs TWO SIDES. A map whose second "player" is only furniture (a respawn
#     garrison) has nobody for the opponent to be;
#   * a payload that will not fit in a lobby message is not offered for networked play;
#   * a payload received from a host is materialised ONLY after it passes the same gate.
#
# Every path is injected at a temp location (tests/README.md rule 4): this suite never reads
# or writes the player's real user://maps library.

const MAPS_DIR := "user://test_map_catalog_maps/"
const SESSION_DIR := "user://test_map_catalog_session/"
const INDEX_PATH := "user://test_map_catalog_index.json"

const BUILTIN_MAP := "res://game/maps/resources/default_skirmish.tres"


func before_each() -> void:
	MapCatalog.set_maps_dir(MAPS_DIR)
	MapCatalog.set_session_maps_dir(SESSION_DIR)
	MapCatalog.set_community_index_path(INDEX_PATH)
	_wipe()
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	DirAccess.make_dir_recursive_absolute(SESSION_DIR)


func after_each() -> void:
	# From after_each, not the test body: GUT runs it even when an assertion fails, so a red
	# test can never leave temp maps behind or leave the catalog pointed at them.
	_wipe()
	MapCatalog.reset_paths()


func _wipe() -> void:
	for dir_path in [MAPS_DIR, SESSION_DIR]:
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))
	if FileAccess.file_exists(INDEX_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INDEX_PATH))


# --- fixtures ----------------------------------------------------------------

## A map payload that is VALID by construction: the engine's own default 5x5 skirmish
## (normal tiles everywhere, three Start spawns per side, no catalog references to resolve),
## exported through MapResource's own serialiser. Built rather than copied off disk so this
## suite cannot be broken by someone editing a shipped .tres.
func _valid_payload(map_name: String) -> Dictionary:
	var res: MapResource = MapLoader.create_default_map()
	res.map_name = map_name
	return _as_dict(res.export_to_json())


func _as_dict(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return json.data


## Write [param text] into the injected library as <stem>.json and return its path.
func _write_library_file(stem: String, text: String) -> String:
	var path: String = MAPS_DIR + stem + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func _write_library_map(stem: String, payload: Dictionary) -> String:
	return _write_library_file(stem, JSON.stringify(payload))


## The listed entry for [param path], or {} when it was not listed at all.
func _entry_for(path: String) -> Dictionary:
	for entry in MapCatalog.versus_maps():
		if String((entry as Dictionary).get("path", "")) == path:
			return entry
	return {}


# --- listing: the three sources ----------------------------------------------

func test_builtin_maps_are_listed_and_tagged_builtin() -> void:
	var builtins: Array = MapCatalog.versus_maps().filter(
		func(e): return String(e.get("source", "")) == MapCatalog.SOURCE_BUILTIN)

	assert_gt(builtins.size(), 0, "the shipped maps are still the backbone of the versus list")
	for entry in builtins:
		assert_true(String(entry.get("path", "")).begins_with("res://"),
			"a builtin entry names a res:// map that shipped with the build")
		assert_false(String(entry.get("name", "")).is_empty(),
			"and carries a display name the picker can render")


func test_a_library_map_is_listed_as_custom() -> void:
	var path: String = _write_library_map("custom_arena", _valid_payload("Custom Arena"))

	var entry: Dictionary = _entry_for(path)

	assert_false(entry.is_empty(), "a player-authored map in the library is offered for versus")
	assert_eq(String(entry.get("source", "")), MapCatalog.SOURCE_CUSTOM,
		"an unrecorded library map is the player's own work")
	assert_eq(String(entry.get("name", "")), "Custom Arena",
		"listed under the name its author gave it, not its file stem")


func test_a_recorded_install_is_listed_as_community() -> void:
	# A download lands in the SAME directory and format as a Map Creator save, so the install
	# record is the only thing that can tell them apart.
	var path: String = _write_library_map("downloaded_arena", _valid_payload("Downloaded Arena"))
	assert_true(MapCatalog.note_community_install(path), "the install was recorded")

	var entry: Dictionary = _entry_for(path)

	assert_eq(String(entry.get("source", "")), MapCatalog.SOURCE_COMMUNITY,
		"a map that came from the service is badged as community content")
	assert_eq(MapCatalog.source_for(path), MapCatalog.SOURCE_COMMUNITY,
		"and source_for agrees with the listing")


func test_the_install_record_is_idempotent_and_forgets_deleted_files() -> void:
	var path: String = _write_library_map("downloaded_arena", _valid_payload("Downloaded Arena"))
	MapCatalog.note_community_install(path)
	MapCatalog.note_community_install(path)

	assert_true(MapCatalog.is_community_install(path), "recording twice is still one record")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	assert_false(MapCatalog.is_community_install(path),
		"a record whose file is gone is dropped rather than kept forever")


func test_is_builtin_is_decided_by_the_res_prefix() -> void:
	assert_true(MapCatalog.is_builtin(BUILTIN_MAP), "only the build can put a file in res://")
	assert_false(MapCatalog.is_builtin("user://maps/mine.json"),
		"a library map is not shipped content")
	assert_false(MapCatalog.is_builtin(""), "an empty path is not a builtin")


# --- listing: what must NOT appear --------------------------------------------

func test_a_corrupt_file_is_never_listed() -> void:
	var broken: String = _write_library_file("broken", "{ this is not json")

	assert_true(_entry_for(broken).is_empty(),
		"an unparseable file is skipped -- a corrupt download must never be offerable")


func test_a_map_naming_an_asset_this_install_lacks_is_never_listed() -> void:
	# The catalog-strict gate's whole job: a shared map that references a character this build
	# does not have would silently substitute a default, so it is rejected instead.
	var payload: Dictionary = _valid_payload("Smuggled")
	var spawns: Array = ((payload["layout"] as Dictionary)["unit_spawns"] as Array)
	(spawns[0] as Dictionary)["character_id"] = "definitely_not_a_real_character"
	var path: String = _write_library_map("smuggled", payload)

	assert_true(_entry_for(path).is_empty(), "an unresolvable character id costs the whole map")


func test_a_map_with_only_one_side_is_not_a_versus_map() -> void:
	var payload: Dictionary = _valid_payload("Solitaire")
	var spawns: Array = ((payload["layout"] as Dictionary)["unit_spawns"] as Array)
	var solo: Array = []
	for spawn in spawns:
		if int((spawn as Dictionary).get("player_id", 0)) == 0:
			solo.append(spawn)
	(payload["layout"] as Dictionary)["unit_spawns"] = solo
	var path: String = _write_library_map("solitaire", payload)

	assert_true(_entry_for(path).is_empty(), "versus needs an opponent, so a one-sided map is not offered")


func test_a_second_side_made_only_of_furniture_is_not_a_versus_map() -> void:
	# Start points are SQUAD CHAIRS -- the slots a participant's roster fills. Respawn /
	# Reinforcement points are map furniture the map itself owns, so a map whose only "player 2"
	# is a reinforcement wave has no seat for a second player.
	var payload: Dictionary = _valid_payload("Garrison")
	for spawn in ((payload["layout"] as Dictionary)["unit_spawns"] as Array):
		if int((spawn as Dictionary).get("player_id", 0)) == 1:
			(spawn as Dictionary)["spawn_kind"] = MapResource.SPAWN_KIND_REINFORCEMENT

	var res: MapResource = MapResource.import_from_json(JSON.stringify(payload), true)
	assert_not_null(res, "the map itself is perfectly valid -- it is just not a versus map")
	assert_false(MapCatalog.is_versus_eligible(res),
		"two Start-slot owners are what makes a map playable head to head")

	var path: String = _write_library_map("garrison", payload)
	assert_true(_entry_for(path).is_empty(), "so it is left out of the versus list")


func test_a_two_sided_map_is_versus_eligible() -> void:
	var res: MapResource = MapLoader.create_default_map()
	assert_true(MapCatalog.is_versus_eligible(res),
		"two players own Start slots on the default skirmish")
	assert_false(MapCatalog.is_versus_eligible(null), "a missing map is never eligible")


# --- payloads ----------------------------------------------------------------

func test_load_payload_round_trips_a_builtin() -> void:
	var payload: Dictionary = MapCatalog.load_payload(BUILTIN_MAP)

	assert_true(payload.has("map_info"), "the payload carries the map's identity")
	assert_true(payload.has("layout"), "and its tiles + spawns")
	assert_not_null(MapResource.import_from_json(JSON.stringify(payload), true),
		"and what a host would send is exactly what a client's own gate accepts")


func test_load_payload_normalises_a_library_map() -> void:
	var path: String = _write_library_map("custom_arena", _valid_payload("Custom Arena"))

	var payload: Dictionary = MapCatalog.load_payload(path)

	assert_eq(String((payload.get("map_info", {}) as Dictionary).get("name", "")), "Custom Arena",
		"the library map serialises back out under its own name")


func test_load_payload_is_empty_for_anything_it_cannot_validate() -> void:
	assert_eq(MapCatalog.load_payload(""), {}, "no path, no payload")
	assert_eq(MapCatalog.load_payload("user://maps/not_there.json"), {},
		"a missing file reports {} instead of throwing")
	assert_eq(MapCatalog.load_payload(_write_library_file("broken", "{ nope")), {},
		"and so does a file that cannot survive the strict gate")


# --- the network cap ----------------------------------------------------------

func test_a_builtin_is_always_network_eligible() -> void:
	assert_true(MapCatalog.network_eligible(BUILTIN_MAP),
		"both machines already have it, so nothing has to be transmitted")


func test_a_small_library_map_is_network_eligible() -> void:
	var path: String = _write_library_map("custom_arena", _valid_payload("Custom Arena"))

	assert_true(MapCatalog.network_eligible(path),
		"an ordinary custom map fits comfortably inside a lobby message")
	assert_lt(MapCatalog.payload_size_bytes(MapCatalog.load_payload(path)),
		MapCatalog.MAX_NETWORK_PAYLOAD_BYTES, "well under the cap")


func test_an_over_cap_map_is_refused_for_networked_play() -> void:
	var payload: Dictionary = _valid_payload("Bloated")
	(payload["map_info"] as Dictionary)["description"] = "x".repeat(MapCatalog.MAX_NETWORK_PAYLOAD_BYTES + 1024)
	var path: String = _write_library_map("bloated", payload)

	assert_gt(MapCatalog.payload_size_bytes(MapCatalog.load_payload(path)),
		MapCatalog.MAX_NETWORK_PAYLOAD_BYTES, "the fixture really is over the cap")
	assert_false(MapCatalog.network_eligible(path),
		"a payload that would not fit in a lobby message is not offered for networked play")
	assert_false(_entry_for(path).is_empty(),
		"but it is still a perfectly good map for a local match, so it stays listed")


func test_network_eligible_is_false_for_a_map_this_machine_does_not_have() -> void:
	assert_false(MapCatalog.network_eligible("user://maps/the_opponents_map.json"),
		"we cannot ship what we never received -- this is what stops a host starting a "
		+ "match on the opponent's own community map")


# --- session installs ---------------------------------------------------------

func test_a_valid_payload_installs_into_the_session_directory() -> void:
	var path: String = MapCatalog.install_session_payload(_valid_payload("Hosts Pick"))

	assert_true(path.begins_with(SESSION_DIR),
		"an opponent's map is match scratch space, not an addition to the player's library")
	assert_true(FileAccess.file_exists(path), "and the file is actually written")
	assert_eq(MapCatalog.map_name_for(path), "Hosts Pick", "under the author's own name")
	assert_not_null(MapResource.import_from_json(_read(path), true),
		"what was written is the VALIDATED resource's own export, so it re-imports cleanly")


func test_an_invalid_payload_installs_nothing() -> void:
	var garbage: Dictionary = {"map_info": {"name": "Evil"}, "layout": {"tiles": [], "unit_spawns": []}}

	assert_eq(MapCatalog.install_session_payload(garbage), "",
		"a payload that fails the strict gate is refused through the return value")
	assert_eq(MapCatalog.install_session_payload({}), "", "and so is an empty one")
	assert_eq(_session_file_count(), 0, "nothing was written for either")


func test_an_over_cap_payload_is_refused_before_it_is_even_parsed() -> void:
	var payload: Dictionary = _valid_payload("Bloated")
	(payload["map_info"] as Dictionary)["description"] = "x".repeat(MapCatalog.MAX_NETWORK_PAYLOAD_BYTES + 1024)

	assert_eq(MapCatalog.install_session_payload(payload), "",
		"the cap is enforced on the receiving side too -- a client is never at the host's mercy")
	assert_eq(_session_file_count(), 0, "and nothing hit the disk")


func test_clearing_session_maps_removes_them() -> void:
	MapCatalog.install_session_payload(_valid_payload("Hosts Pick"))
	assert_eq(_session_file_count(), 1, "one map was installed for the match")

	MapCatalog.clear_session_maps()

	assert_eq(_session_file_count(), 0, "and the match's scratch copy does not outlive it")


func _session_file_count() -> int:
	var dir: DirAccess = DirAccess.open(SESSION_DIR)
	if dir == null:
		return 0
	var count: int = 0
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return count


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
