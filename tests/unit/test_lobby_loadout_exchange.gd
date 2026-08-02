extends GutTest

## The lobby's SQUAD + LOADOUT + SKIN exchange -- the "match_loadout" message.
##
## A squad decides which units exist at all, items are real buffs, skins change what a unit
## looks like -- and all three live in process-local storage. So BOTH machines need BOTH sides'
## data BEFORE a single unit spawns, which is why this is its own bidirectional message rather
## than a wider game_start payload: game_start is host -> client only and has no client -> host
## twin (which is exactly why a client's own squad pick used to reach nobody).
##
## What is pinned here:
##   * the HOST announces its card when it admits the opponent, and the CLIENT announces its
##     card when it announces itself -- the same two moments the profile card is exchanged;
##   * the announcement records which slot is OURS, which is what tells the battle to keep
##     reading the local inventory for our own units;
##   * an inbound card is stored under the SERVER-STAMPED sender slot and normalised on the
##     way in, so a hostile payload cannot plant buffs;
##   * none of it fires without a live session.
##
## The transport is the same stand-in the adapter suite uses (see
## tests/unit/test_lobby_transport_adapter.gd), with local_slot() added -- the lobby reads it
## to learn its own seat.

## Stand-in for the NetSession autoload.
class MockNetSession extends Node:
	signal lobby_message(message_type: String, data: Dictionary, from_slot: int)
	var live: bool = true
	var sent: Array = []
	## Roster size. Left at 1 so the host's connection POLL never fires during a test --
	## admission is driven explicitly via deliver("lobby_hello", ...) instead.
	var players: int = 1
	var server: bool = true
	var slot: int = 0

	func is_connected_session() -> bool:
		return live
	func is_server() -> bool:
		return server
	func player_count() -> int:
		return players
	func local_slot() -> int:
		return slot
	func send_lobby_message(message_type: String, data: Dictionary) -> void:
		sent.append({ "type": message_type, "data": data })
	func begin_match_rng_handshake() -> void:
		pass
	## Deliver a message as if the server relayed it from the participant in [param from_slot].
	func deliver(message_type: String, data: Dictionary, from_slot: int) -> void:
		lobby_message.emit(message_type, data, from_slot)

## Stand-in for the GameModeManager autoload (the legacy envelope).
class MockGameModeManager extends Node:
	var sent: Array = []
	func submit_action(action_type: String, action_data: Dictionary) -> bool:
		sent.append({ "type": action_type, "data": action_data })
		return true
	func get_game_status() -> Dictionary:
		return { "network_stats": { "connected_peers": 0, "connection_status": "disconnected" } }

const TEMP_SAVE_PATH := "user://test_lobby_loadout_exchange.json"

const UNIT_ITEM := "heartwood_charm"       # +5 Max HP, unit-scope
const TEAM_ITEM := "elderroot_standard"    # +2 Defense, team-scope
const BLIGHTCAP_SKIN := "blightcap_ashcap"

const HOST_SLOT := 0
const CLIENT_SLOT := 1

const LOCAL_SQUAD := ["vineweave", "petalfang"]

const Guard := preload("res://tests/helpers/global_state_guard.gd")

var lobby: Control
var net: MockNetSession
var gmm: MockGameModeManager

## Untyped on purpose: a `: RefCounted` annotation would make the static analyser reject
## _guard.set_setting() / .watch_setting() as "not found in base RefCounted".
var _guard


func before_all() -> void:
	ItemInventory.set_save_path(TEMP_SAVE_PATH)
	ItemLibrary.rescan()


func before_each() -> void:
	ItemInventory.reset()
	MatchLoadouts.clear()
	# The card carries this peer's Character Select pick, which is an autoload field.
	_guard = Guard.new()
	_guard.set_setting("selected_squad", [])

	net = MockNetSession.new()
	add_child_autofree(net)
	gmm = MockGameModeManager.new()
	add_child_autofree(gmm)

	lobby = Control.new()
	lobby.set_script(load("res://menus/CollaborativeLobby.gd"))
	add_child_autofree(lobby)
	await get_tree().process_frame

	# Swap both transports for stand-ins AFTER _ready has bound the real autoloads.
	lobby.set_net_session(net)
	lobby.game_mode_manager = gmm


func after_each() -> void:
	# Static and process-wide: a leak here would equip the NEXT suite's units.
	MatchLoadouts.clear()
	ItemInventory.reset()
	_guard.restore()
	lobby = null
	net = null
	gmm = null


func after_all() -> void:
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)
	ItemInventory.reset()


## Every "match_loadout" message the lobby pushed at the live session.
func _loadout_sends() -> Array:
	return net.sent.filter(func(m): return m["type"] == "match_loadout")


# --- Sending: the host side --------------------------------------------------

func test_the_host_announces_its_loadout_when_it_admits_the_opponent() -> void:
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	net.slot = HOST_SLOT

	lobby.initialize(true, "Host")
	net.sent.clear()
	net.deliver("lobby_hello", { "player_name": "Opponent" }, CLIENT_SLOT)

	var sends: Array = _loadout_sends()
	assert_eq(sends.size(), 1, "admitting the opponent announces the host's card exactly once")
	var payload: Dictionary = sends[0]["data"]
	assert_eq(String((payload["equipped"] as Dictionary).get("vineweave", "")), UNIT_ITEM,
		"carrying what the host has equipped -- the client needs it BEFORE it spawns slot 0")
	assert_true(payload.has("team"), "and the team slots")
	assert_true(payload.has("skins"), "and the skins")


func test_a_late_hello_re_announces_the_hosts_card() -> void:
	# The host may already have flipped to map selection (roster poll) when the hello lands;
	# the client still needs the card, so the answer must repeat.
	net.slot = HOST_SLOT
	lobby.initialize(true, "Host")
	lobby.is_client_connected = true
	net.sent.clear()

	net.deliver("lobby_hello", { "player_name": "Opponent" }, CLIENT_SLOT)

	assert_eq(_loadout_sends().size(), 1, "a late hello is answered with the card as well")


# --- Sending: the client side ------------------------------------------------

func test_the_client_announces_its_loadout_when_it_announces_itself() -> void:
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)
	net.slot = CLIENT_SLOT
	net.server = false

	lobby.initialize(false, "Client")

	var sends: Array = _loadout_sends()
	assert_eq(sends.size(), 1, "the client's card rides the same breath as its hello")
	var payload: Dictionary = sends[0]["data"]
	assert_eq((payload["team"] as Array).size(), 1, "carrying its filled team slot")
	assert_eq(String((payload["team"] as Array)[0]), TEAM_ITEM, "with the item's id")


# --- Sending: the squad rides the same card ----------------------------------

func test_the_card_carries_this_peers_character_select_pick() -> void:
	# THE GAP THIS CLOSES: game_start's host_squad names slot 0 on every peer and has no
	# client -> host twin, so a client's own pick reached nobody and player 1 fielded the map's
	# authored roster on both machines.
	_guard.set_setting("selected_squad", LOCAL_SQUAD.duplicate())
	net.slot = CLIENT_SLOT
	net.server = false

	lobby.initialize(false, "Client")

	var sends: Array = _loadout_sends()
	assert_eq(sends.size(), 1, "the client announces exactly one card")
	assert_eq((sends[0]["data"] as Dictionary).get("squad", []), LOCAL_SQUAD,
		"carrying its pick, in order -- the host needs it BEFORE it spawns slot 1")


func test_the_host_announces_its_squad_too() -> void:
	# Slot 0 also has the game_start channel, but the card is announced by WHOEVER is
	# announcing: one shape for every seat, and the fallback if host_squad never arrives.
	_guard.set_setting("selected_squad", LOCAL_SQUAD.duplicate())
	net.slot = HOST_SLOT

	lobby.initialize(true, "Host")
	net.sent.clear()
	net.deliver("lobby_hello", { "player_name": "Opponent" }, CLIENT_SLOT)

	assert_eq((_loadout_sends()[0]["data"] as Dictionary).get("squad", []), LOCAL_SQUAD,
		"the host's card names its own pick as well")


func test_no_pick_is_announced_as_an_empty_squad() -> void:
	# "I picked nothing" is an answer: it means "field the map's authored roster for my slot",
	# which is what the other peer must do for us too.
	_guard.set_setting("selected_squad", [])
	net.slot = CLIENT_SLOT
	net.server = false

	lobby.initialize(false, "Client")

	var payload: Dictionary = _loadout_sends()[0]["data"]
	assert_true(payload.has("squad"), "the field is always present")
	assert_eq(payload["squad"], [], "and empty rather than absent")


func test_only_ids_the_local_roster_knows_go_on_the_wire() -> void:
	# The receiving side whitelists anyway; this keeps the honest case with nothing to reject.
	_guard.set_setting("selected_squad", ["vineweave", "not_a_character", "petalfang"])
	net.slot = CLIENT_SLOT
	net.server = false

	lobby.initialize(false, "Client")

	assert_eq((_loadout_sends()[0]["data"] as Dictionary)["squad"], LOCAL_SQUAD,
		"an id this build cannot resolve is never announced")


# --- Receiving: the squad half of the trust boundary -------------------------

func test_an_inbound_squad_is_stored_under_the_server_stamped_slot() -> void:
	lobby.initialize(true, "Host")

	net.deliver("match_loadout", { "squad": LOCAL_SQUAD }, CLIENT_SLOT)

	assert_eq(MatchLoadouts.squad_for(CLIENT_SLOT), LOCAL_SQUAD,
		"the opponent's roster is recorded against the slot the SERVER says sent it")
	assert_eq(MatchLoadouts.squad_for(HOST_SLOT), [],
		"and nothing is invented for any other slot")


func test_a_hostile_squad_lands_as_an_empty_one() -> void:
	# MapLoader falls back to a DEFAULT character for an id it cannot resolve, so an unknown id
	# must die at the boundary -- otherwise it would become a real unit on the board.
	lobby.initialize(true, "Host")

	net.deliver("match_loadout", {
		"squad": ["sword_of_infinite_power", { "nested": true }, null, 7, ""],
	}, CLIENT_SLOT)

	assert_eq(MatchLoadouts.squad_for(CLIENT_SLOT), [], "no fabricated character was fielded")
	assert_true(MatchLoadouts.has_peer_loadout(CLIENT_SLOT),
		"the peer still counts as having answered -- an empty squad is an answer")


func test_announcing_records_which_slot_is_ours() -> void:
	# This is what keeps our OWN units reading the local inventory instead of a peer's card.
	net.slot = CLIENT_SLOT
	net.server = false

	lobby.initialize(false, "Client")

	assert_true(MatchLoadouts.is_active(), "a seated networked lobby switches replication on")
	assert_eq(MatchLoadouts.local_slot(), CLIENT_SLOT, "and records the seat the server gave us")


func test_an_unseated_peer_leaves_replication_off_rather_than_guessing() -> void:
	# A peer the server has not seated yet reports slot -1. Replication must stay OFF -- with
	# no idea which side is ours, equipping anything would be a coin flip.
	net.slot = -1
	net.server = false

	lobby._broadcast_match_loadout()

	assert_eq(_loadout_sends().size(), 1, "the card is still announced (the server stamps it)")
	assert_false(MatchLoadouts.is_active(), "but nothing is applied until we know our own seat")


func test_a_new_lobby_forgets_the_previous_matchs_loadouts() -> void:
	MatchLoadouts.set_peer_loadout(CLIENT_SLOT, { "equipped": { "vineweave": UNIT_ITEM } })
	net.live = false   # no session: initialize takes the legacy branch and announces nothing

	lobby.initialize(true, "Host")

	assert_eq(MatchLoadouts.peer_count(), 0, "last match's opponent card is gone")
	assert_false(MatchLoadouts.is_active(), "and replication is off until this lobby seats us")


# --- Not without a live session ----------------------------------------------

func test_nothing_is_announced_without_a_live_session() -> void:
	net.live = false

	lobby._broadcast_match_loadout()

	assert_eq(net.sent.size(), 0, "nothing was pushed at a dead session")
	assert_eq(gmm.sent.size(), 0, "and the card never falls through to the legacy envelope")
	assert_false(MatchLoadouts.is_active(), "a solo/menu lobby leaves replication off entirely")


# --- Receiving: the trust boundary -------------------------------------------

func test_an_inbound_card_is_stored_under_the_server_stamped_slot() -> void:
	lobby.initialize(true, "Host")

	net.deliver("match_loadout", {
		"equipped": { "vineweave": UNIT_ITEM },
		"team": [TEAM_ITEM],
		"skins": { "blightcap": BLIGHTCAP_SKIN },
	}, CLIENT_SLOT)

	assert_true(MatchLoadouts.has_peer_loadout(CLIENT_SLOT), "the opponent's card was recorded")
	var ids: Array[String] = MatchLoadouts.item_ids_for(CLIENT_SLOT, "vineweave")
	assert_eq(ids.size(), 2, "with its worn item and its team item")
	var card: Dictionary = MatchLoadouts.get_peer_loadout(CLIENT_SLOT)
	assert_eq(String((card["skins"] as Dictionary).get("blightcap", "")), BLIGHTCAP_SKIN,
		"and the skin it announced")


func test_a_hostile_card_lands_as_an_empty_one() -> void:
	# Unknown ids, an item announced in the wrong scope, a skin authored for someone else, and
	# values that are not even strings. Every one is dropped at the boundary; nothing crashes.
	lobby.initialize(true, "Host")

	net.deliver("match_loadout", {
		"equipped": { "vineweave": "sword_of_infinite_power", "blightcap": TEAM_ITEM },
		"team": [UNIT_ITEM, { "nested": true }, "nope"],
		"skins": { "vineweave": BLIGHTCAP_SKIN, "blightcap": 42 },
	}, CLIENT_SLOT)

	var card: Dictionary = MatchLoadouts.get_peer_loadout(CLIENT_SLOT)
	assert_eq((card["equipped"] as Dictionary).size(), 0, "no fabricated item was granted")
	assert_eq((card["team"] as Array).size(), 0, "no mis-scoped team item either")
	assert_eq((card["skins"] as Dictionary).size(), 0, "and no skin the sender cannot wear")
	assert_true(MatchLoadouts.has_peer_loadout(CLIENT_SLOT),
		"the peer still counts as having answered -- an empty card is an answer")


func test_a_second_card_from_the_same_slot_replaces_the_first() -> void:
	lobby.initialize(true, "Host")

	net.deliver("match_loadout", { "team": [TEAM_ITEM] }, CLIENT_SLOT)
	net.deliver("match_loadout", { "team": [] }, CLIENT_SLOT)

	assert_eq((MatchLoadouts.get_peer_loadout(CLIENT_SLOT)["team"] as Array).size(), 0,
		"the latest announcement wins rather than accumulating")


func test_an_unrelated_message_type_does_not_disturb_the_cards() -> void:
	lobby.initialize(true, "Host")
	net.deliver("match_loadout", { "team": [TEAM_ITEM] }, CLIENT_SLOT)

	net.deliver("profile_info", { "name": "Opponent" }, CLIENT_SLOT)

	assert_eq((MatchLoadouts.get_peer_loadout(CLIENT_SLOT)["team"] as Array).size(), 1,
		"the profile card and the loadout card are separate records")
