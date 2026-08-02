extends GutTest

# CLIENT SQUAD -> the units that actually spawn in PLAYER 1's slots, on BOTH machines.
#
# The host's pick had a wire path (game_start's "host_squad", which names slot 0 everywhere)
# and the client's did not. A client's Character Select pick reached nobody, so player 1 --
# the client's own side of the board -- fielded the MAP's authored roster on both peers, and
# the client's choice was silently discarded. This closes it: every peer announces its own
# squad on the bidirectional "match_loadout" lobby card, keyed by the server-stamped sender
# slot, and MapLoader.resolve_player_squad fills a slot from OUR pick when it is ours and from
# that slot's replicated announcement when it is not.
#
# What this proves, end to end with a crafted payload:
#   1. The card survives NetSession's lobby delivery with the squad intact.
#   2. Loading the map AS THE HOST spawns the CLIENT's announced characters in player 1's slots.
#   3. Loading the map AS THE CLIENT spawns its OWN pick there -- the same characters, so the
#      two boards agree -- while player 0 still comes from the host's squad.
#   4. A peer that announced no squad leaves the map's authored roster, on both peers.
#   5. An untrusted payload (junk entries, unknown ids) costs at most the slots it names.
#   6. A human opponent's pick is NOT filtered by the local ai_difficulty setting (that would
#      drop the unit on one peer and keep it on the other).
#   7. Solo / hotseat is untouched, INCLUDING after a networked match: a battle that is not a
#      live networked match clears the stale replication state before it spawns anything.
#
# No socket is dialled: the card is driven through NetSession's own delivery entry point and
# the peer-identity half is injected into MapLoader (net_context_override), the same
# "server-half, no dialling" discipline as integration/test_net_host_squad.gd.

const MAP_PATH := "res://game/maps/resources/proving_grounds.tres"

const HOST_SQUAD := ["gem_knight", "necromancer"]
const CLIENT_SQUAD := ["vineweave", "petalfang"]

const HOST_SLOT := 0
const CLIENT_SLOT := 1

## Requires ai_difficulty >= HARD to spawn as an ENEMY (roster min_difficulty = 2). Used to
## prove a deliberate PICK is exempt from that gate on a remote human's slot too.
const GATED_PICK := "mycothrall"

const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose: a `: RefCounted` annotation would make the static analyser reject
## _guard.set_setting() / .watch_setting() as "not found in base RefCounted".
var _guard

func before_each() -> void:
	_guard = Guard.new()
	_guard.watch_setting("selected_squad")
	_guard.watch_setting("host_squad")
	_guard.watch_setting("ai_difficulty")
	# Process-wide static state that outlives a scene change -- and the thing under test here.
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

## A NetSession parented under the test node: its `multiplayer` is the tree's default API with
## no peer installed, so nothing is dialled and is_connected_session() is safely false.
func _fresh_netsession() -> Node:
	var n := Node.new()
	n.set_script(load("res://systems/net/NetSession.gd"))
	add_child_autofree(n)
	return n

## Receive a "match_loadout" card the way the OTHER machine does -- off the session's lobby
## channel -- and park it the way the lobby does. Returns the payload as it came out of the
## session (not the one that went in).
func _receive_card(from_slot: int, card: Dictionary) -> Dictionary:
	var net := _fresh_netsession()
	var received: Array = []
	net.lobby_message.connect(func(_type, data, _slot): received.append(data))
	net._rpc_lobby_deliver("match_loadout", card, from_slot)
	if received.is_empty():
		return {}
	MatchLoadouts.set_peer_loadout(from_slot, received[0])
	return received[0]

## The card a peer announces for itself, in the shape MatchLoadouts.build_local_payload emits.
func _card(squad: Array) -> Dictionary:
	return { "equipped": {}, "team": [], "skins": {}, "squad": squad }

## Load the real map with this peer's identity injected, and report the character ids that
## ended up in [param player_id]'s container. [param local_slot] < 0 with [param networked]
## false is the solo case.
func _ids_for(player_id: int, networked: bool, local_slot: int) -> Array:
	var root3d := Node3D.new()
	add_child_autofree(root3d)
	var loader := MapLoader.new()
	if networked or local_slot >= 0:
		loader.net_context_override = { "networked": networked, "local_slot": local_slot }
	root3d.add_child(loader)
	loader.load_map(load(MAP_PATH), root3d)

	var container := root3d.get_node_or_null("Player" + str(player_id + 1))
	var ids: Array = []
	if container != null:
		for u in container.get_children():
			var cr = u.get("character_resource")
			if cr != null:
				ids.append(String(cr.character_id))
	ids.sort()
	return ids

## What the map fields for [param player_id] when nobody picked anything -- read from the
## loader itself, so the baseline is never a value written into this test.
func _authored_ids(player_id: int) -> Array:
	GameSettings.set_selected_squad([])
	GameSettings.set_host_squad([])
	var ids := _ids_for(player_id, false, -1)
	MatchLoadouts.clear()   # the solo load above is entitled to clear it; keep the hook honest
	return ids


# --- 1. The card survives the session boundary --------------------------------

func test_the_clients_squad_arrives_intact_on_the_host():
	var payload := _receive_card(CLIENT_SLOT, _card(CLIENT_SQUAD))
	assert_false(payload.is_empty(), "the client's card reached the host")
	assert_eq(payload.get("squad", []), CLIENT_SQUAD,
		"carrying its pick exactly as the client sent it")
	assert_eq(MatchLoadouts.squad_for(CLIENT_SLOT), CLIENT_SQUAD,
		"and the host parks it under the SERVER-STAMPED sender slot")
	assert_eq(MatchLoadouts.squad_for(HOST_SLOT), [],
		"without inventing one for any other slot")


# --- 2 & 3. Both machines field the same characters in player 1 ---------------

func test_the_host_fields_the_clients_characters_in_slot_one():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	# The host's own pick is slot 0's; it must NOT leak into the opponent's slots.
	GameSettings.set_selected_squad(HOST_SQUAD)
	_receive_card(CLIENT_SLOT, _card(CLIENT_SQUAD))

	var ids := _ids_for(1, true, HOST_SLOT)

	assert_eq(ids, ["petalfang", "vineweave"],
		"player 1 is the CLIENT's side, so the host spawns the client's announced characters")
	assert_eq(_ids_for(0, true, HOST_SLOT), ["gem_knight", "necromancer"],
		"and its own pick still fills its own slots")


func test_the_client_fields_its_own_pick_there_and_the_two_boards_agree():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	# On the CLIENT machine slot 1 is OURS, so it is the local pick that fills it -- never the
	# card we (also) announced. Same characters either way, which is the entire point.
	GameSettings.set_selected_squad(CLIENT_SQUAD)
	GameSettings.set_host_squad(HOST_SQUAD)
	_receive_card(HOST_SLOT, _card(HOST_SQUAD))

	assert_eq(_ids_for(1, true, CLIENT_SLOT), ["petalfang", "vineweave"],
		"the client fields its own pick in its own slots")
	assert_eq(_ids_for(0, true, CLIENT_SLOT), ["gem_knight", "necromancer"],
		"and the host's replicated squad in the host's slots")


func test_a_seatless_peer_reads_both_sides_from_the_wire():
	# Not yet seated (slot -1): NO slot is ours, so every side comes from its announcement
	# rather than from our own pick, which would otherwise land in a stranger's slots.
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	GameSettings.set_selected_squad([GATED_PICK])
	GameSettings.set_host_squad(HOST_SQUAD)
	_receive_card(CLIENT_SLOT, _card(CLIENT_SQUAD))

	assert_eq(_ids_for(1, true, -1), ["petalfang", "vineweave"], "slot 1 from its card")
	assert_eq(_ids_for(0, true, -1), ["gem_knight", "necromancer"], "slot 0 from the host squad")


# --- 4. Nothing announced -> the map's authored roster, on both peers ---------

func test_a_peer_that_announced_no_squad_leaves_the_maps_own_roster():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	var authored := _authored_ids(1)

	# The host's view: the client announced a card but no squad (or is an older build).
	GameSettings.set_selected_squad(HOST_SQUAD)
	_receive_card(CLIENT_SLOT, _card([]))
	var on_host := _ids_for(1, true, HOST_SLOT)

	# The client's view of the same match: its own pick is empty, so the same fallback.
	GameSettings.set_selected_squad([])
	var on_client := _ids_for(1, true, CLIENT_SLOT)

	assert_eq(on_host, authored,
		"an empty announcement means the map's authored roster, not the reader's own pick")
	assert_eq(on_client, authored, "and the client lands on the same roster, so the boards agree")
	assert_gt(authored.size(), CLIENT_SQUAD.size(), "that is the map's full roster, not a pick")


# --- 5. The payload is untrusted peer input ----------------------------------

func test_a_junk_squad_entry_costs_its_slot_not_the_map():
	# The squad is a plain Dictionary value off the lobby channel. MapLoader falls back to its
	# DEFAULT_CHARACTER_ID for an id it cannot resolve, so an unknown id MUST be dropped at the
	# boundary -- otherwise "sword_of_power" would quietly become a real unit on the board.
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	GameSettings.set_selected_squad(HOST_SQUAD)
	_receive_card(CLIENT_SLOT, _card(
		["vineweave", { "evil": true }, "", null, 7, "not_a_character", "petalfang"]))

	assert_eq(MatchLoadouts.squad_for(CLIENT_SLOT), ["vineweave", "petalfang"],
		"only ids that resolve in the roster survive the boundary")
	assert_eq(_ids_for(1, true, HOST_SLOT), ["petalfang", "vineweave"],
		"so the real picks spawn and the junk entries are simply dropped")


func test_an_absurd_squad_is_capped():
	var flood: Array = []
	for i in range(MatchLoadouts.MAX_SQUAD + 25):
		flood.append("vineweave")
	_receive_card(CLIENT_SLOT, _card(flood))
	assert_eq(MatchLoadouts.squad_for(CLIENT_SLOT).size(), MatchLoadouts.MAX_SQUAD,
		"a peer cannot hand us an unbounded roster")


# --- 6. A human's pick is not filtered by the LOCAL difficulty setting -------

func test_the_opponents_pick_is_not_gated_by_our_difficulty_setting():
	# mycothrall demands ai_difficulty >= HARD to appear as an ENEMY spawn. That gate exists for
	# the MAP's authored enemies; applying it to a human opponent's deliberate pick would drop
	# the unit on the peer set to Normal and keep it on the peer set to Hard -- a board
	# disagreement dressed up as a difficulty rule.
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	GameSettings.set_ai_difficulty(1)   # NORMAL: below mycothrall's requirement
	GameSettings.set_selected_squad(HOST_SQUAD)
	_receive_card(CLIENT_SLOT, _card([GATED_PICK, "vineweave"]))

	assert_eq(_ids_for(1, true, HOST_SLOT), ["mycothrall", "vineweave"],
		"the opponent gets the units it chose regardless of OUR difficulty setting")
	assert_false(_authored_ids(1).has(GATED_PICK),
		"while the map's own authored enemy of the same character is still gated out")


# --- 7. Solo is untouched, including AFTER a networked match ------------------

func test_solo_play_leaves_player_one_to_the_map():
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	var authored := _authored_ids(1)
	GameSettings.set_selected_squad(CLIENT_SQUAD)

	assert_eq(_ids_for(1, false, -1), authored,
		"with no networked match the local pick fills player 0 only, exactly as before")
	assert_eq(_ids_for(0, false, -1), ["petalfang", "vineweave"],
		"and player 0 is still the local pick")


func test_a_solo_battle_after_a_networked_one_starts_from_a_clean_slate():
	# THE STALENESS BUG. MatchLoadouts and host_squad are process-wide and only cleared when a
	# NEW LOBBY initialises -- so lobby -> versus -> Main Menu -> a solo battle never passes a
	# lobby again and would read the previous opponent's card and the previous host's roster.
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	var authored := _authored_ids(1)

	# Leftovers from the match that just ended.
	MatchLoadouts.set_local_slot(HOST_SLOT)
	MatchLoadouts.set_peer_loadout(CLIENT_SLOT, _card(CLIENT_SQUAD))
	GameSettings.set_host_squad(HOST_SQUAD)
	GameSettings.set_selected_squad([GATED_PICK])

	var ids := _ids_for(1, false, -1)

	assert_eq(ids, authored, "the solo board is the map's, not the last opponent's pick")
	assert_false(MatchLoadouts.is_active(),
		"replication is switched back off, so ItemSystem/Unit read the local profile again")
	assert_eq(MatchLoadouts.peer_count(), 0, "and the last opponent's card is forgotten")
	assert_eq(GameSettings.get_host_squad(), [], "as is the last host's roster")


func test_a_live_networked_load_keeps_the_replicated_state():
	# The mirror of the test above: the clear must be gated on "not a live networked match", or
	# it would wipe the very data the battle it is starting depends on (and every later round
	# of a best-of series reloads the map).
	if GameSettings == null:
		pending("no GameSettings autoload")
		return
	GameSettings.set_selected_squad(HOST_SQUAD)
	GameSettings.set_host_squad(HOST_SQUAD)
	MatchLoadouts.set_local_slot(HOST_SLOT)
	_receive_card(CLIENT_SLOT, _card(CLIENT_SQUAD))

	_ids_for(1, true, HOST_SLOT)

	assert_true(MatchLoadouts.is_active(), "a networked load leaves replication switched on")
	assert_eq(MatchLoadouts.squad_for(CLIENT_SLOT), CLIENT_SQUAD, "with the opponent's card")
	assert_eq(GameSettings.get_host_squad(), HOST_SQUAD, "and the host's roster")


# --- The pure decision --------------------------------------------------------

func test_the_resolver_picks_the_right_source_for_each_slot():
	# No map, no session, no tree: just the rule.
	var local := ["mycothrall"]
	var replicated := ["gem_knight"]

	assert_eq(MapLoader.resolve_player_squad(0, local, replicated, -1, false), local,
		"solo: player 0 is the local pick")
	assert_eq(MapLoader.resolve_player_squad(1, local, replicated, -1, false), [],
		"solo: every other player is the map's authored roster, as it always was")

	assert_eq(MapLoader.resolve_player_squad(1, local, replicated, 1, true), local,
		"networked: OUR slot is our own pick, whichever number it is")
	assert_eq(MapLoader.resolve_player_squad(1, local, replicated, 0, true), replicated,
		"networked: somebody else's slot is their replicated announcement")
	assert_eq(MapLoader.resolve_player_squad(0, local, replicated, 0, true), local,
		"networked host: slot 0 is its own pick")
	assert_eq(MapLoader.resolve_player_squad(1, local, replicated, -1, true), replicated,
		"networked but not yet seated: no slot is ours, so nothing of ours is applied")
	assert_eq(MapLoader.resolve_player_squad(1, local, [], 0, true), [],
		"an empty announcement is the map's authored roster, never a fallback to our pick")


func test_the_squad_normaliser_whitelists_against_the_roster():
	# The pure half of the trust boundary, so a failure points at the coercion, not the map.
	assert_eq(MatchLoadouts.normalise_squad(["vineweave", &"petalfang"]),
		["vineweave", "petalfang"], "Strings and StringNames are both ids")
	assert_eq(MatchLoadouts.normalise_squad([" vineweave "]), ["vineweave"], "ids are trimmed")
	assert_eq(MatchLoadouts.normalise_squad(["vineweave", "vineweave"]),
		["vineweave", "vineweave"], "duplicates are a legal pick, so they are kept")
	assert_eq(MatchLoadouts.normalise_squad(["nope", "", {}, [], null, 7]), [],
		"an unknown id, a container, a null or a number is never a character")
	assert_eq(MatchLoadouts.normalise_squad("not an array"), [],
		"a payload whose squad is not even an Array degrades to no override")
