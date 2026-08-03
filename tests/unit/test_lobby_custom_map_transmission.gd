extends GutTest

# COMMUNITY / CUSTOM MAPS IN A NETWORKED VERSUS MATCH.
#
# A builtin map needs no transmission: it shipped with both installs, so the path alone names
# the same board on both machines. A Map Creator save or a community download exists on ONE
# disk, so the versus lobby has to ship the content itself -- and the moment it does, that
# content is untrusted peer input.
#
# The rules pinned here:
#   1. game_start carries "map_payload" for a NON-builtin map and omits it for a builtin
#      (shipping a map both peers already have is pure waste).
#   2. A payload over the cap is never sent, and its map is never a startable candidate --
#      the host refuses rather than half-starting a match.
#   3. A CLIENT re-validates everything it receives. A garbage payload is refused QUIETLY
#      (a returned/displayed outcome, never push_error, never a crash) and the match does not
#      start -- an unverifiable map is strictly worse than no match, because two peers on two
#      different boards is a desync from frame 1.
#   4. A vote carries the map's NAME as well as its path, so the opponent's vote line reads
#      properly for a map this machine has never seen. Content still ships only at game_start.
#
# Both transports are stand-ins (the MockNetSession pattern from test_lobby_transport_adapter),
# and every map path is injected at a temp location -- no socket, no real library.

## Stand-in for the NetSession autoload. Roster left at 1 so the host's connection POLL never
## fires and every assertion stays synchronous.
class MockNetSession extends Node:
	signal lobby_message(message_type: String, data: Dictionary, from_slot: int)
	var live: bool = true
	var sent: Array = []
	var players: int = 1
	var server: bool = true

	func is_connected_session() -> bool:
		return live
	func is_server() -> bool:
		return server
	func player_count() -> int:
		return players
	func send_lobby_message(message_type: String, data: Dictionary) -> void:
		sent.append({ "type": message_type, "data": data })
	func begin_match_rng_handshake() -> void:
		pass
	func deliver(message_type: String, data: Dictionary) -> void:
		lobby_message.emit(message_type, data, 1)


const MAPS_DIR := "user://test_lobby_maps/"
const SESSION_DIR := "user://test_lobby_session/"
const INDEX_PATH := "user://test_lobby_map_index.json"

const BUILTIN_MAP := "res://game/maps/resources/default_skirmish.tres"
## A path that is perfectly meaningful on the OPPONENT's machine and meaningless on this one.
const OPPONENTS_MAP := "user://maps/sunken_causeway.json"

var lobby: Control
var net: MockNetSession


func before_each() -> void:
	MapCatalog.set_maps_dir(MAPS_DIR)
	MapCatalog.set_session_maps_dir(SESSION_DIR)
	MapCatalog.set_community_index_path(INDEX_PATH)
	_wipe()
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	DirAccess.make_dir_recursive_absolute(SESSION_DIR)

	net = MockNetSession.new()
	add_child_autofree(net)

	lobby = Control.new()
	lobby.set_script(load("res://menus/CollaborativeLobby.gd"))
	add_child_autofree(lobby)
	await get_tree().process_frame

	lobby.set_net_session(net)
	# The host-only settings panel writes to GameSettings when a start is finalised. Nothing in
	# this suite is about those settings, so it is unhooked rather than guarded -- the panel
	# node itself stays parented to the lobby and is freed with it.
	lobby.versus_config_panel = null


func after_each() -> void:
	lobby = null
	net = null
	# From after_each so a failing assertion still cleans up (tests/README.md rule 3).
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

func _valid_payload(map_name: String) -> Dictionary:
	var res: MapResource = MapLoader.create_default_map()
	res.map_name = map_name
	var json := JSON.new()
	if json.parse(res.export_to_json()) != OK or not (json.data is Dictionary):
		return {}
	return json.data


func _write_library_map(stem: String, payload: Dictionary) -> String:
	var path: String = MAPS_DIR + stem + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	return path


func _last_game_start() -> Dictionary:
	for i in range(net.sent.size() - 1, -1, -1):
		if String(net.sent[i]["type"]) == "game_start":
			return net.sent[i]["data"]
	return {}


# --- 1. what game_start carries ----------------------------------------------

func test_game_start_ships_the_content_of_a_custom_map() -> void:
	var path: String = _write_library_map("custom_arena", _valid_payload("Custom Arena"))
	lobby.is_host = true

	lobby._broadcast_game_start(path)

	var settings: Dictionary = _last_game_start()
	assert_eq(String(settings.get("map", "")), path,
		"'map' still names the host's own path -- it is the identity, and the display name")
	assert_true(settings.has("map_payload"),
		"a map only this machine has must travel WITH the start, or the boards cannot agree")
	var payload: Dictionary = settings.get("map_payload", {})
	assert_eq(String((payload.get("map_info", {}) as Dictionary).get("name", "")), "Custom Arena",
		"and the payload is the map itself, not a reference to it")


func test_game_start_omits_the_payload_for_a_builtin() -> void:
	lobby.is_host = true

	lobby._broadcast_game_start(BUILTIN_MAP)

	var settings: Dictionary = _last_game_start()
	assert_eq(String(settings.get("map", "")), BUILTIN_MAP, "the shipped map is named by path")
	assert_false(settings.has("map_payload"),
		"both peers already have it, so shipping it would be pure waste")
	assert_true(settings.has("turn_system"), "the rest of the MatchSettings is unchanged")
	assert_true(settings.has("versus_rounds"), "including the best-of round count")


func test_game_start_omits_an_over_cap_payload() -> void:
	var payload: Dictionary = _valid_payload("Bloated")
	(payload["map_info"] as Dictionary)["description"] = "x".repeat(MapCatalog.MAX_NETWORK_PAYLOAD_BYTES + 1024)
	var path: String = _write_library_map("bloated", payload)
	lobby.is_host = true

	lobby._broadcast_game_start(path)

	assert_false(_last_game_start().has("map_payload"),
		"a map that would not fit in a lobby message is never pushed into one")


# --- 2. which votes the host can actually start on ----------------------------

func test_only_maps_this_host_can_ship_are_startable() -> void:
	lobby.local_map_vote = BUILTIN_MAP
	lobby.remote_map_vote = OPPONENTS_MAP

	assert_eq(lobby._startable_votes(), [BUILTIN_MAP],
		"the opponent's community map exists only on their disk, so the host cannot ship it "
		+ "-- it loses the tie-break instead of killing the lobby")


func test_a_custom_map_the_host_owns_is_startable() -> void:
	var path: String = _write_library_map("custom_arena", _valid_payload("Custom Arena"))
	lobby.local_map_vote = path
	lobby.remote_map_vote = BUILTIN_MAP

	var candidates: Array = lobby._startable_votes()

	assert_eq(candidates.size(), 2, "both votes can be shipped, so both may win the coin flip")
	assert_true(candidates.has(path), "including the host's own custom map")


func test_two_votes_for_the_same_map_are_one_candidate() -> void:
	lobby.local_map_vote = BUILTIN_MAP
	lobby.remote_map_vote = BUILTIN_MAP

	assert_eq(lobby._startable_votes(), [BUILTIN_MAP], "agreement is not a coin flip")


# --- 3. the client re-validates everything --------------------------------------

func test_a_shipped_payload_becomes_the_clients_boot_map() -> void:
	var boot_path: String = lobby._resolve_boot_map(OPPONENTS_MAP, _valid_payload("Sunken Causeway"))

	assert_true(boot_path.begins_with(SESSION_DIR),
		"the host's map is materialised into the session directory, not the player's library")
	assert_true(FileAccess.file_exists(boot_path), "and the client boots from that local copy")
	assert_eq(MapCatalog.map_name_for(boot_path), "Sunken Causeway",
		"which is the host's map, under its own name")


func test_a_builtin_with_no_payload_boots_from_its_own_path() -> void:
	assert_eq(lobby._resolve_boot_map(BUILTIN_MAP, {}), BUILTIN_MAP,
		"a shipped map needs nothing shipped -- this is the pre-existing path, unchanged")


func test_a_non_builtin_with_no_payload_is_refused() -> void:
	assert_eq(lobby._resolve_boot_map(OPPONENTS_MAP, {}), "",
		"a host that named a map it did not ship gets no match: booting a same-named local "
		+ "file would be two different boards")


func test_a_garbage_payload_is_refused_quietly() -> void:
	lobby.is_host = false
	lobby.local_player_name = "Client"

	lobby.handle_network_message("game_start", {
		"map": OPPONENTS_MAP,
		"map_payload": {"map_info": {"name": "Evil"}, "layout": {"tiles": [], "unit_spawns": []}},
		"turn_system": 0,
	})

	assert_false(lobby.vote_status_label.text.is_empty(),
		"the refusal is surfaced to the player rather than logged to the engine")
	assert_false(lobby.ready_button.disabled,
		"and the lobby stays usable -- the player can pick again")


func test_a_hostile_oversized_payload_is_refused_by_the_client_too() -> void:
	var payload: Dictionary = _valid_payload("Bloated")
	(payload["map_info"] as Dictionary)["description"] = "x".repeat(MapCatalog.MAX_NETWORK_PAYLOAD_BYTES + 1024)

	assert_eq(lobby._resolve_boot_map(OPPONENTS_MAP, payload), "",
		"the cap is enforced on the receiving side as well -- a client is never at the "
		+ "host's mercy for how much it has to swallow")


# --- 4. voting on a map the other peer does not have ---------------------------

func test_a_vote_carries_the_maps_name() -> void:
	lobby.local_player_name = "Host"

	lobby._broadcast_map_vote(BUILTIN_MAP)

	var vote: Dictionary = net.sent[0]["data"]
	assert_eq(String(vote.get("map_path", "")), BUILTIN_MAP, "the path is still the identity")
	assert_false(String(vote.get("map_name", "")).is_empty(),
		"and the name rides along so the opponent's vote line is readable")


func test_an_unknown_map_is_shown_by_the_name_that_came_with_the_vote() -> void:
	lobby.initialize(true, "Host")

	net.deliver("map_vote", {
		"player_name": "Opponent",
		"map_path": OPPONENTS_MAP,
		"map_name": "Sunken Causeway",
	})

	assert_eq(lobby.remote_map_vote, OPPONENTS_MAP, "the vote is recorded by path")
	assert_eq(lobby.remote_map_vote_name, "Sunken Causeway", "and by announced name")
	assert_eq(lobby._display_name_for_vote(lobby.remote_map_vote, lobby.remote_map_vote_name),
		"Sunken Causeway",
		"a map this machine does not have still reads as its title, not a file stem")

	lobby.local_map_vote = BUILTIN_MAP
	lobby._update_vote_status()
	assert_true(lobby.vote_status_label.text.contains("Sunken Causeway"),
		"and that is what the player sees in the vote status line")


func test_a_locally_resolvable_map_is_named_from_the_file_not_the_announcement() -> void:
	# The announced name is untrusted peer input: it is a FALLBACK for a map we cannot read,
	# never an override of one we can.
	assert_eq(lobby._display_name_for_vote(BUILTIN_MAP, "Not This Name"),
		MapCatalog.map_name_for(BUILTIN_MAP),
		"what is on this disk wins over what a peer claims")


func test_a_junk_announced_name_cannot_reach_the_label() -> void:
	lobby.initialize(true, "Host")

	net.deliver("map_vote", {"player_name": "Opponent", "map_path": OPPONENTS_MAP, "map_name": {"evil": true}})

	assert_true(lobby.remote_map_vote_name.begins_with("{") or lobby.remote_map_vote_name.is_empty(),
		"a non-string name is coerced to a plain String rather than handed to a Label as-is")
	assert_eq(typeof(lobby.remote_map_vote_name), TYPE_STRING,
		"the stored name is always a String, whatever the payload held")
