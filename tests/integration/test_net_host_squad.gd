extends GutTest

# HOST SQUAD -> the units that actually spawn on a CLIENT.
#
# In a networked match the host broadcasts its MatchSettings over the lobby channel, and
# "host_squad" names the roster for SLOT 0 -- the host's side of the board -- on EVERY peer.
# Storing it was already wired; APPLYING it was not. MapLoader fed player 0's spawn slots from
# GameSettings.selected_squad unconditionally, which on a client is the CLIENT's OWN pick. So
# the client fielded its own characters where the host fielded the host's, and the two boards
# disagreed on the very first frame of a lockstep match. host_squad was written and never read
# by anything.
#
# What this proves, end to end with a crafted payload:
#   1. The payload survives NetSession's client-side lobby delivery with its squad intact.
#   2. Loading the map AS A CLIENT spawns the HOST's characters in player 0's slots.
#   3. Loading the map AS THE HOST is unchanged -- its own pick IS the host squad.
#   4. Solo / hotseat is untouched: no session, so the local pick still wins.
#   5. An untrusted payload (junk entries -- it is peer input off the lobby channel) costs at
#      most the slots it names, never the map load.
#
# No socket is dialled: the lobby message is driven through NetSession's own delivery entry
# point, and the peer-identity half is injected into MapLoader (net_context_override) instead
# of standing up two live sessions -- the same "server-half, no dialling" discipline as
# integration/test_net_forfeit.gd.

const MAP_PATH := "res://game/maps/resources/proving_grounds.tres"

const HOST_SQUAD := ["gem_knight", "necromancer"]
const CLIENT_SQUAD := ["mycothrall"]

const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose: a `: RefCounted` annotation would make the static analyser reject
## _guard.set_setting() / .watch_setting() as "not found in base RefCounted".
var _guard

func before_each() -> void:
	# Both squads are autoload fields these tests overwrite. Restored from after_each, which
	# GUT runs even when a test fails part-way through.
	_guard = Guard.new()
	_guard.watch_setting("selected_squad")
	_guard.watch_setting("host_squad")
	# Slot 0 falls back to its "match_loadout" card when no host_squad was sent, so a card left
	# behind by another suite would answer for the host here. Process-wide static state.
	MatchLoadouts.clear()
	_clear_combat_services()

func after_each() -> void:
	_guard.restore()
	MatchLoadouts.clear()
	# Loading a real map registers its tiles on the shared CombatServices board; drop it in
	# BOTH hooks so one map load can never be read by the next suite (tests/README rule 3).
	_clear_combat_services()

func _clear_combat_services() -> void:
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("clear"):
		CombatServices.clear()


# --- fixtures ----------------------------------------------------------------

## The MatchSettings envelope a host broadcasts when it starts the game (the shape
## CollaborativeLobby builds). Only the fields this suite is about are filled in.
func _host_match_settings(squad: Array) -> Dictionary:
	return {
		"map": MAP_PATH,
		"map_json": "",
		"turn_system": 0,
		"versus_rounds": 1,
		"host_squad": squad,
	}

## A NetSession parented under the test node: its `multiplayer` is the tree's default API with
## no peer installed, so nothing is dialled and is_connected_session() is safely false.
func _fresh_netsession() -> Node:
	var n := Node.new()
	n.set_script(load("res://systems/net/NetSession.gd"))
	add_child_autofree(n)
	return n

## Receive [param settings] the way a CLIENT does -- off the session's lobby channel -- and
## apply the squad half of it, which is the step the lobby performs before changing scene.
## Returns the payload as it came out of the session (not the one that went in).
func _receive_and_apply(settings: Dictionary) -> Dictionary:
	var net := _fresh_netsession()
	var received: Array = []
	net.lobby_message.connect(func(_type, data, _slot): received.append(data))
	net._rpc_lobby_deliver("game_start", settings, 0)
	if received.is_empty():
		return {}
	var payload: Dictionary = received[0]
	GameSettings.set_host_squad(payload.get("host_squad", []))
	return payload

## Load the real map with this peer's identity injected, and report the character ids that
## ended up in player 0's containers. [param local_slot] < 0 with [param networked] false is
## the solo case.
func _player0_ids_as(networked: bool, local_slot: int) -> Array:
	var root3d := Node3D.new()
	add_child_autofree(root3d)
	var loader := MapLoader.new()
	if networked or local_slot >= 0:
		loader.net_context_override = { "networked": networked, "local_slot": local_slot }
	root3d.add_child(loader)
	loader.load_map(load(MAP_PATH), root3d)

	var container := root3d.get_node_or_null("Player1")   # player_id 0 -> "Player1" container
	var ids: Array = []
	if container != null:
		for u in container.get_children():
			var cr = u.get("character_resource")
			if cr != null:
				ids.append(String(cr.character_id))
	ids.sort()
	return ids


# --- 1. The payload survives the session boundary ----------------------------

func test_the_hosts_squad_arrives_intact_on_the_client():
	var payload := _receive_and_apply(_host_match_settings(HOST_SQUAD))
	assert_false(payload.is_empty(), "the host's MatchSettings reached the client")
	assert_eq(payload.get("host_squad", []), HOST_SQUAD,
		"carrying slot 0's roster exactly as the host sent it")
	assert_eq(GameSettings.get_host_squad(), HOST_SQUAD,
		"and the client stores it as the host squad, separate from its own pick")


# --- 2. The client SPAWNS the host's squad ------------------------------------

func test_a_client_fields_the_hosts_characters_in_slot_zero():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	# The client has its own, DIFFERENT pick -- the bug was that this is what spawned.
	GameSettings.set_selected_squad(CLIENT_SQUAD)
	_receive_and_apply(_host_match_settings(HOST_SQUAD))

	var ids := _player0_ids_as(true, 1)

	assert_eq(ids, ["gem_knight", "necromancer"],
		"player 0 is the HOST's side, so a client spawns the host's characters there")
	assert_false(ids.has("mycothrall"),
		"the client's own pick never lands in the host's slots (that was the desync)")


func test_a_legacy_host_that_sent_no_squad_leaves_the_maps_own_roster():
	# An older host omits host_squad entirely. The client must fall back to the map's authored
	# player-0 roster -- which is exactly what that host will field too, so the peers agree.
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	# What the map fields for player 0 when nobody picked anything -- the baseline both peers
	# must land on. Read from the loader itself, so this is not a value written in the test.
	GameSettings.set_selected_squad([])
	GameSettings.set_host_squad([])
	var authored := _player0_ids_as(false, -1)

	GameSettings.set_selected_squad(CLIENT_SQUAD)
	_receive_and_apply(_host_match_settings([]))
	var ids := _player0_ids_as(true, 1)

	assert_eq(ids, authored,
		"a client with no host squad falls back to the map's authored roster -- which is what "
		+ "that legacy host fields too, so the peers still agree")
	assert_gt(authored.size(), CLIENT_SQUAD.size(),
		"and that is the map's full roster, not the client's own (much shorter) pick")


# --- 3. The host is unchanged -------------------------------------------------

func test_the_host_still_fields_its_own_pick():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	# The host never receives a host_squad (it sends one), so its own selection is slot 0's.
	GameSettings.set_selected_squad(HOST_SQUAD)
	GameSettings.set_host_squad([])

	var ids := _player0_ids_as(true, 0)

	assert_eq(ids, ["gem_knight", "necromancer"],
		"slot 0 is the host itself, so its own Character Select pick still fills its slots")


# --- 4. Solo / hotseat is untouched ------------------------------------------

func test_solo_play_still_uses_the_local_pick():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	GameSettings.set_selected_squad(CLIENT_SQUAD)
	# A stale host_squad left over from a previous networked match must not leak into a solo
	# battle -- that is the regression this guards.
	GameSettings.set_host_squad(HOST_SQUAD)

	var ids := _player0_ids_as(false, -1)

	assert_eq(ids, ["mycothrall"],
		"with no networked match the local pick fills player 0, exactly as before")


# --- 5. The payload is untrusted peer input ----------------------------------

func test_a_junk_squad_entry_costs_its_slot_not_the_map():
	# host_squad is a plain Dictionary value off the lobby channel: a hostile or buggy host can
	# put anything in the array. Normalising at the spawn boundary means junk drops out instead
	# of resolving to a garbage character id (or failing the load).
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	GameSettings.set_selected_squad(CLIENT_SQUAD)
	_receive_and_apply(_host_match_settings(["gem_knight", { "evil": true }, "", null, "necromancer"]))

	var ids := _player0_ids_as(true, 1)

	assert_eq(ids, ["gem_knight", "necromancer"],
		"the real ids still spawn and the junk entries are simply dropped")


func test_the_normaliser_only_keeps_scalar_ids():
	# The pure half of the rule above, so a failure points at the coercion rather than the map.
	assert_eq(MapLoader.normalise_squad_ids(["a", &"b"]), ["a", "b"],
		"Strings and StringNames are both ids")
	assert_eq(MapLoader.normalise_squad_ids([" spaced "]), ["spaced"], "ids are trimmed")
	assert_eq(MapLoader.normalise_squad_ids(["", "  "]), [], "blank entries are not ids")
	assert_eq(MapLoader.normalise_squad_ids([{}, [], null, 7]), [],
		"a container, a null or a number is never a character id")
	assert_eq(MapLoader.normalise_squad_ids("not an array"), [],
		"a payload whose squad is not even an Array degrades to no override")


func test_the_resolver_picks_the_right_side_for_each_peer():
	# The pure decision, driven directly: no map, no session, no tree.
	var local := ["mycothrall"]
	var host := ["gem_knight"]
	assert_eq(MapLoader.resolve_player0_squad(local, host, -1, false), local,
		"solo: the local pick")
	assert_eq(MapLoader.resolve_player0_squad(local, host, 0, true), local,
		"networked host (slot 0): its own pick IS the host squad")
	assert_eq(MapLoader.resolve_player0_squad(local, host, 1, true), host,
		"networked client: the host's replicated squad fills the host's slots")
	assert_eq(MapLoader.resolve_player0_squad(local, host, -1, true), host,
		"networked but not yet seated: still the host's squad, never ours")
