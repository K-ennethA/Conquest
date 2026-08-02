extends Control

class_name CollaborativeLobby

# Collaborative Multiplayer Lobby
# - Host waits for client to join
# - Both players see map selection gallery
# - Both can vote on maps
# - If votes match: use that map
# - If votes differ: coin flip decides

signal lobby_ready()
signal game_starting(map_path: String)

# Network state
var is_host: bool = false
var is_client_connected: bool = false
var local_player_name: String = ""
var remote_player_name: String = ""

# Map voting
var local_map_vote: String = ""
var remote_map_vote: String = ""
var voting_complete: bool = false

# UI Elements
var waiting_panel: Panel
var map_selection_panel: Control
var map_selector: Node
var vote_status_label: Label
var ready_button: Button

# Host-only match config (Turn System + Best-of rounds), embedded in the waiting panel.
# Added ALONGSIDE the existing waiting-panel nodes (never renaming them) and revealed only
# for the host. Applied locally to GameSettings at start via apply_settings().
var versus_config_panel: MatchConfigPanel

# Game mode manager
var game_mode_manager: Node

# --- Transport adapter --------------------------------------------------------
# The lobby's vote / ready / lobby-state / game-start messages have TWO possible carriers:
#
#   NetSession (preferred)  -- the consolidated server-authoritative transport. When Host/Join
#                              ran through it, it is the same session the battle's command
#                              seam reads, so the lobby and the battle share one connection.
#   GameModeManager (legacy) -- the old submit_action envelope, delivered by
#                              MultiplayerGameState._handle_lobby_message finding this node in
#                              the tree. Still the carrier for any caller that has not moved.
#
# The choice is made per SEND, on whether NetSession currently holds a live connected peer,
# so nothing needs to be told which mode it is in. Receiving is symmetric: NetSession's
# lobby_message signal and the legacy direct call both land in handle_network_message().

## The transport to prefer. Defaults to the NetSession autoload; tests inject a stand-in via
## [method set_net_session]. Never assume it is the autoload -- always go through the helpers.
var net_session: Node = null

func _ready() -> void:
	print("[LOBBY] _ready() called")
	theme = MenuTheme.build()  # dark Legends-style menu look (also inherited when nested)
	game_mode_manager = GameModeManager
	set_net_session(NetSession if typeof(NetSession) == TYPE_OBJECT else null)
	if not game_mode_manager:
		print("[LOBBY] ERROR: GameModeManager not found")
		return

	print("[LOBBY] Building UI...")
	_build_ui()
	print("[LOBBY] UI built successfully")

## Point this lobby at the transport it should prefer, subscribing to its inbound lobby
## messages. Idempotent, and rebinding cleanly drops the previous source's subscription.
func set_net_session(source) -> void:
	if net_session == source:
		return
	if net_session != null and is_instance_valid(net_session) \
			and net_session.has_signal("lobby_message") \
			and net_session.lobby_message.is_connected(_on_net_lobby_message):
		net_session.lobby_message.disconnect(_on_net_lobby_message)
	net_session = source
	if net_session != null and is_instance_valid(net_session) \
			and net_session.has_signal("lobby_message") \
			and not net_session.lobby_message.is_connected(_on_net_lobby_message):
		net_session.lobby_message.connect(_on_net_lobby_message)

func _exit_tree() -> void:
	# The autoload outlives this lobby; drop the subscription so a torn-down lobby can never
	# be woken by the next match's traffic.
	set_net_session(null)

## True when NetSession is the live transport for this process (a connected peer exists).
## False in solo/menu/test contexts, which is what routes sends down the legacy path.
func _net_active() -> bool:
	return net_session != null and is_instance_valid(net_session) \
		and net_session.has_method("is_connected_session") \
		and bool(net_session.is_connected_session())

## Send one lobby message over whichever transport is live. NetSession wins whenever it holds
## a connected peer; otherwise the legacy submit_action envelope carries it. Null-safe on both
## branches, so a lobby with neither transport is a silent no-op rather than a crash.
func _send_lobby_message(message_type: String, data: Dictionary) -> void:
	if _net_active():
		net_session.send_lobby_message(message_type, data)
		return
	if game_mode_manager != null and is_instance_valid(game_mode_manager):
		game_mode_manager.submit_action(message_type, data)

## Inbound lobby message off NetSession. Same entry point the legacy path calls, so there is
## exactly one place each message type is handled. NetSession never echoes our own sends back,
## so this only ever carries the OTHER participant's traffic.
##
## The sender's roster SLOT is forwarded: the server stamps it from its own roster, so it is
## the trustworthy answer to "who said this" and is what keys the profile cards in
## [MatchPeerInfo]. The legacy carrier has no slot and passes the default -1.
func _on_net_lobby_message(message_type: String, data: Dictionary, from_slot: int) -> void:
	handle_network_message(message_type, data, from_slot)

func initialize(as_host: bool, player_name: String) -> void:
	"""Initialize the lobby as host or client"""
	is_host = as_host
	local_player_name = player_name

	# A NEW lobby means a new match: forget whatever the LAST match's opponent announced, so
	# the post-match summary can never attribute the previous opponent to this one -- and so
	# the previous match's replicated loadouts/skins can never be applied in this one (a
	# cleared MatchLoadouts also reads as INACTIVE, which is what keeps solo play untouched).
	MatchPeerInfo.clear()
	MatchLoadouts.clear()

	print("[LOBBY] Initialized as " + ("HOST" if is_host else "CLIENT"))
	print("[LOBBY] Player name: " + player_name)
	
	if is_host:
		_show_waiting_for_client()
		_start_monitoring_connections()
	elif _net_active():
		# NetSession client: the connection already exists (we only get here after being
		# seated), so announce ourselves. The host answers with the current lobby state --
		# which also closes the race where the host reached map selection before this lobby
		# node existed and its broadcast had nobody to land on.
		print("[LOBBY] Announcing to host over NetSession")
		_show_waiting_for_host()
		_send_lobby_message("lobby_hello", {"player_name": local_player_name})
		# ...and, in the same breath, who we ARE (rank + lifetime points). See
		# _broadcast_profile_info for why this rides the START of the match.
		_broadcast_profile_info()
		# ...and WHAT WE BRING: the equipped items + cosmetic skins the HOST must know before
		# it spawns our units. See _broadcast_match_loadout.
		_broadcast_match_loadout()
	else:
		# Client: Check if already connected (late join scenario)
		if game_mode_manager:
			var status = game_mode_manager.get_game_status()
			var network_stats = status.get("network_stats", {})
			var connection_status = network_stats.get("connection_status", "")
			
			if connection_status == "CONNECTED":
				print("[LOBBY] Client already connected, showing map selection immediately")
				_show_map_selection()
			else:
				print("[LOBBY] Client waiting for connection")
				_show_waiting_for_host()
		else:
			_show_waiting_for_host()

func _build_ui() -> void:
	"""Build the lobby UI"""
	# Waiting panel (shown while waiting for other player)
	waiting_panel = Panel.new()
	waiting_panel.name = "WaitingPanel"
	waiting_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(waiting_panel)
	
	var waiting_content = VBoxContainer.new()
	waiting_content.set_anchors_preset(Control.PRESET_CENTER)
	waiting_content.offset_left = -200
	waiting_content.offset_top = -100
	waiting_content.offset_right = 200
	waiting_content.offset_bottom = 100
	waiting_panel.add_child(waiting_content)
	
	var waiting_title = Label.new()
	waiting_title.name = "WaitingTitle"
	waiting_title.text = "Waiting for player..."
	MenuTheme.style_title(waiting_title, 24)
	waiting_content.add_child(waiting_title)
	
	var waiting_status = Label.new()
	waiting_status.name = "WaitingStatus"
	waiting_status.text = "Please wait..."
	waiting_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_content.add_child(waiting_status)

	# Host-only match settings, added alongside the existing waiting-panel nodes. Hidden by
	# default; _show_waiting_for_client reveals it for the host. Client never sees it.
	var config_spacer = Control.new()
	config_spacer.name = "ConfigSpacer"
	config_spacer.custom_minimum_size = Vector2(0, 16)
	config_spacer.visible = false
	waiting_content.add_child(config_spacer)

	var config_heading = Label.new()
	config_heading.name = "ConfigHeading"
	config_heading.text = "Match Settings (host)"
	config_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuTheme.style_subtitle(config_heading)
	config_heading.visible = false
	waiting_content.add_child(config_heading)

	versus_config_panel = MatchConfigPanel.new()
	versus_config_panel.name = "VersusConfigPanel"
	versus_config_panel.custom_minimum_size = Vector2(360, 110)
	versus_config_panel.visible = false
	waiting_content.add_child(versus_config_panel)
	versus_config_panel.configure(MatchConfigPanel.MODE_VERSUS)

	# Map selection panel (shown when both players connected)
	map_selection_panel = Control.new()
	map_selection_panel.name = "MapSelectionPanel"
	map_selection_panel.visible = false
	map_selection_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(map_selection_panel)
	
	var selection_content = VBoxContainer.new()
	selection_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection_content.offset_left = 20
	selection_content.offset_top = 20
	selection_content.offset_right = -20
	selection_content.offset_bottom = -20
	map_selection_panel.add_child(selection_content)
	
	# Title
	var selection_title = Label.new()
	selection_title.text = "SELECT YOUR MAP"
	MenuTheme.style_title(selection_title, 28)
	selection_content.add_child(selection_title)
	
	# Subtitle
	var selection_subtitle = Label.new()
	selection_subtitle.text = "Click a map to vote. If you both choose different maps, a coin flip will decide!"
	selection_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_subtitle.add_theme_font_size_override("font_size", 14)
	selection_content.add_child(selection_subtitle)
	
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	selection_content.add_child(spacer1)
	
	# Map selector (gallery) - check if scene exists
	var map_selector_scene = load("res://game/ui/panels/MapSelectorPanel.tscn")
	if map_selector_scene:
		map_selector = map_selector_scene.instantiate()
		if map_selector.has_method("set_gallery_mode"):
			map_selector.set_gallery_mode(true)
		if map_selector.has_method("set_preview_size"):
			map_selector.set_preview_size(Vector2(200, 150))
		if map_selector.has_method("set_columns"):
			map_selector.set_columns(3)
		map_selector.set("show_title", false)
		map_selector.map_changed.connect(_on_local_map_selected)
		selection_content.add_child(map_selector)
	else:
		print("[LOBBY] ERROR: Could not load MapSelectorPanel scene")
		var error_label = Label.new()
		error_label.text = "Error: Map selector not available"
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		selection_content.add_child(error_label)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	selection_content.add_child(spacer2)
	
	# Vote status
	vote_status_label = Label.new()
	vote_status_label.text = "Select a map to vote"
	vote_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_status_label.add_theme_font_size_override("font_size", 16)
	selection_content.add_child(vote_status_label)
	
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 10)
	selection_content.add_child(spacer3)
	
	# Ready button
	ready_button = Button.new()
	ready_button.text = "READY - START GAME"
	ready_button.custom_minimum_size = Vector2(300, 60)
	ready_button.disabled = true
	ready_button.pressed.connect(_on_ready_pressed)
	
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_child(ready_button)
	selection_content.add_child(button_container)

func _show_waiting_for_client() -> void:
	"""Show waiting screen for host"""
	if not waiting_panel:
		print("[LOBBY] ERROR: waiting_panel is null")
		return
	
	waiting_panel.visible = true
	if map_selection_panel:
		map_selection_panel.visible = false
	
	var title = waiting_panel.get_node_or_null("VBoxContainer/WaitingTitle")
	var status = waiting_panel.get_node_or_null("VBoxContainer/WaitingStatus")
	
	if title:
		title.text = "Waiting for opponent..."
	if status:
		status.text = "Share this address: 127.0.0.1:8910"

	# Reveal the host-only match settings (Turn System + Best-of).
	for node_name in ["ConfigSpacer", "ConfigHeading", "VersusConfigPanel"]:
		var n = waiting_panel.get_node_or_null("VBoxContainer/" + node_name)
		if n != null:
			n.visible = true

func _show_waiting_for_host() -> void:
	"""Show waiting screen for client"""
	if not waiting_panel:
		print("[LOBBY] ERROR: waiting_panel is null")
		return
	
	waiting_panel.visible = true
	if map_selection_panel:
		map_selection_panel.visible = false
	
	var title = waiting_panel.get_node_or_null("VBoxContainer/WaitingTitle")
	var status = waiting_panel.get_node_or_null("VBoxContainer/WaitingStatus")
	
	if title:
		title.text = "Connected to host"
	if status:
		status.text = "Waiting for host to start map selection..."

func _show_map_selection() -> void:
	"""Show map selection screen"""
	print("[LOBBY] Showing map selection")
	
	if not waiting_panel or not map_selection_panel:
		print("[LOBBY] ERROR: UI panels not initialized")
		return
	
	waiting_panel.visible = false
	map_selection_panel.visible = true
	
	# Reset voting state
	local_map_vote = ""
	remote_map_vote = ""
	voting_complete = false
	_update_vote_status()

func _start_monitoring_connections() -> void:
	"""Monitor for client connections (host only)"""
	if not is_host:
		return
	
	print("[LOBBY] Monitoring for client connections...")
	_check_for_connections()

func _check_for_connections() -> void:
	"""Check if client has connected"""
	if not is_host or is_client_connected:
		return

	if not game_mode_manager and not _net_active():
		print("[LOBBY] ERROR: no transport available for connection checking")
		return

	# Safety check - the lobby may have already been removed from the tree (e.g. scene
	# teardown mid-loop). get_tree() is null in that case, so bail before touching it.
	if not is_inside_tree():
		print("[LOBBY] Not in tree, stopping connection check")
		return

	await get_tree().create_timer(0.5).timeout

	# Safety check - don't loop forever
	if not is_inside_tree():
		print("[LOBBY] Not in tree anymore, stopping connection check")
		return

	var peer_count: int = _remote_peer_count()

	print("[LOBBY] Checking connections... Peers: " + str(peer_count))

	if peer_count > 0:
		print("[LOBBY] Client connected!")
		_admit_remote_player("Opponent")
	else:
		# Keep checking (but with safety limit)
		_check_for_connections()

## How many OTHER participants are present. Reads NetSession's roster when it is the live
## transport (authoritative, no polling of a second stack), and falls back to the legacy
## GameModeManager network stats otherwise.
func _remote_peer_count() -> int:
	if _net_active() and net_session.has_method("player_count"):
		return maxi(0, int(net_session.player_count()) - 1)
	if game_mode_manager == null or not is_instance_valid(game_mode_manager):
		return 0
	var status = game_mode_manager.get_game_status()
	var network_stats = status.get("network_stats", {})
	var connected_peers = network_stats.get("connected_peers", 0)
	# connected_peers is an integer (peer count), not an array -- guard both shapes.
	if connected_peers is int:
		return int(connected_peers)
	if connected_peers is Array:
		return (connected_peers as Array).size()
	return 0

## Host: the opponent is present -- move to map selection and tell them to do the same.
## Idempotent on the state flip but ALWAYS re-broadcasts, so a hello that arrives after the
## poll already flipped us still gets an answer.
func _admit_remote_player(player_name: String) -> void:
	if not is_host:
		return
	if not is_client_connected:
		is_client_connected = true
		remote_player_name = player_name
		_show_map_selection()
	_broadcast_lobby_state("map_selection")
	# The lobby has FORMED -- answer the newcomer with our own profile card, exactly as the
	# lobby_state answer above closes the "host got there first" race for map selection.
	_broadcast_profile_info()
	# ...and with our loadout + skins, which the CLIENT must know before it spawns our units.
	_broadcast_match_loadout()

func _on_local_map_selected(map_path: String, map_resource: MapResource) -> void:
	"""Handle local player's map selection"""
	local_map_vote = map_path
	print("[LOBBY] Local vote: " + map_resource.map_name)
	
	# Broadcast vote to other player
	_broadcast_map_vote(map_path)
	
	# Update UI
	_update_vote_status()
	
	# Enable ready button
	if ready_button:
		ready_button.disabled = false

func _broadcast_map_vote(map_path: String) -> void:
	"""Broadcast map vote to other player"""
	_send_lobby_message("map_vote", {
		"player_name": local_player_name,
		"map_path": map_path
	})
	print("[LOBBY] Broadcasted map vote: " + map_path)

## Announce THIS player's profile card -- display name, local rank name, lifetime points --
## to the other participant(s).
##
## WHY AT THE START: the post-match summary ([GameOverScreen]) wants to show who you beat and
## what rank they carry, but by the time a versus match ENDS the opponent may have forfeited,
## crashed or dropped, so there is nobody left to ask. The exchange therefore happens while
## the lobby is forming and the answer is parked in [MatchPeerInfo] until the summary reads it.
##
## Sent on the same lobby channel as the votes / ready flags / game-start payload, through the
## same [method _send_lobby_message] adapter, so it works on whichever transport is live and is
## a silent no-op when neither is.
func _broadcast_profile_info() -> void:
	_send_lobby_message("profile_info", _build_profile_info())


## This player's card. Every profile read is guarded: the autoload is absent in some harnesses,
## and an older build may not carry the rank accessors. Missing data degrades to a name-only
## card rather than blocking the send.
func _build_profile_info() -> Dictionary:
	var info: Dictionary = { "name": local_player_name, "rank_name": "", "lifetime_points": 0 }
	if typeof(PlayerProfile) != TYPE_OBJECT or PlayerProfile == null:
		return info
	var lifetime: int = 0
	if PlayerProfile.has_method("get_points_total"):
		lifetime = int(PlayerProfile.get_points_total())
	info["lifetime_points"] = lifetime
	if PlayerProfile.has_method("get_rank_name"):
		info["rank_name"] = str(PlayerProfile.get_rank_name())
	else:
		info["rank_name"] = RankLadder.rank_for(lifetime)
	return info


## The other participant announced its card. [param from_slot] is the SERVER's stamp of who
## sent it (-1 on the legacy carrier, which has no slots), and it is what the card is keyed
## by -- the payload is untrusted peer input and [MatchPeerInfo] normalises it on the way in.
func _handle_profile_info(data: Dictionary, from_slot: int) -> void:
	MatchPeerInfo.set_peer_info(from_slot, data)
	var announced: Dictionary = MatchPeerInfo.get_peer_info(from_slot)
	print("[LOBBY] Opponent profile: %s (%s, %d pts) in slot %d" % [
		String(announced.get("name", "")), String(announced.get("rank_name", "")),
		int(announced.get("lifetime_points", 0)), from_slot])
	# Name the opponent from their own announcement when the poll only had a placeholder.
	var announced_name: String = String(announced.get("name", "")).strip_edges()
	if not announced_name.is_empty() and (remote_player_name.is_empty() or remote_player_name == "Opponent"):
		remote_player_name = announced_name


## Announce what THIS player brings into the match: the characters they will field, the item
## equipped on each of them, their shared team items, and the cosmetic skin each one wears.
##
## WHY IT IS ITS OWN MESSAGE, NOT PART OF game_start. Items are real buffs, skins change what a
## unit LOOKS like, and the squad decides which units exist at all -- so BOTH machines need
## BOTH sides' data before a single unit spawns. game_start is host -> client only and has no
## client -> host twin, so widening it would replicate the host's side and nothing else (which
## is exactly what "host_squad" is, and exactly why a client's own pick used to reach nobody).
## This message is the "profile_info" shape instead: announced by whoever is announcing, keyed
## by the sender's server-stamped slot, parked in [MatchLoadouts] until the battle reads it.
## Host and client each send exactly one, at the same two moments the profile card is exchanged.
##
## The local slot is recorded alongside, because it is what tells the battle which side is
## OURS -- our own units keep reading the local inventory/profile/pick, never a replicated card.
func _broadcast_match_loadout() -> void:
	if not _net_active():
		return
	if net_session.has_method("local_slot"):
		MatchLoadouts.set_local_slot(int(net_session.local_slot()))
	_send_lobby_message("match_loadout",
		MatchLoadouts.build_local_payload(_player_profile(), _local_squad()))


## This peer's own Character Select pick, or an empty Array where GameSettings is absent (a
## headless harness) or too old to answer. Empty means "field the map's authored roster for my
## slot", which is the pre-existing behaviour for a match launched without a pick.
func _local_squad() -> Array:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and GameSettings.has_method("get_selected_squad"):
		return GameSettings.get_selected_squad()
	return []


## The PlayerProfile autoload, or null where it is not registered (headless / tests). Fetched
## rather than referenced directly so a missing autoload degrades to "no skins" instead of
## failing to resolve.
func _player_profile() -> Object:
	if typeof(PlayerProfile) == TYPE_OBJECT and PlayerProfile != null:
		return PlayerProfile
	return null


## The other participant announced its squad + loadout + skins. [param from_slot] is the
## SERVER's stamp of who sent it, and it is what the card is keyed by -- the payload itself is
## untrusted peer input, so [MatchLoadouts] whitelists every id in it against the LOCAL
## character/item/skin libraries on the way in (an unknown or mis-scoped id is simply dropped).
func _handle_match_loadout(data: Dictionary, from_slot: int) -> void:
	MatchLoadouts.set_peer_loadout(from_slot, data)
	var stored: Dictionary = MatchLoadouts.get_peer_loadout(from_slot)
	print("[LOBBY] Opponent loadout in slot %d: %d unit(s), %d worn item(s), %d team item(s), %d skin(s)" % [
		from_slot, (stored["squad"] as Array).size(), (stored["equipped"] as Dictionary).size(),
		(stored["team"] as Array).size(), (stored["skins"] as Dictionary).size()])


func _broadcast_lobby_state(state: String) -> void:
	"""Broadcast lobby state change (host only)"""
	if not is_host:
		return

	_send_lobby_message("lobby_state", {
		"state": state
	})
	print("[LOBBY] Broadcasted lobby state: " + state)

func _display_name_for_vote(path: String) -> String:
	"""Best-effort display name for a map vote: the loaded MapResource's map_name when the
	resource actually loads, otherwise the path's file basename. Never null-derefs a failed
	load (missing file, or a custom user:// map the other peer hasn't received yet)."""
	if path.is_empty():
		return ""
	# Existence check BEFORE load: load() on a missing path logs engine errors on its
	# own (even though it returns null safely), which spams the log for the perfectly
	# normal "peer voted for a map this machine doesn't have" case.
	if not ResourceLoader.exists(path):
		return path.get_file().get_basename()
	var map_resource: MapResource = load(path) as MapResource
	if map_resource != null:
		return map_resource.map_name
	return path.get_file().get_basename()

func _update_vote_status() -> void:
	"""Update the vote status display"""
	if not vote_status_label:
		return

	var status_text = ""

	if local_map_vote.is_empty():
		status_text = "Select a map to vote"
	elif remote_map_vote.is_empty():
		status_text = "You voted for: " + _display_name_for_vote(local_map_vote) + "\nWaiting for opponent's vote..."
	else:
		if local_map_vote == remote_map_vote:
			voting_complete = true
			status_text = "Both players chose: " + _display_name_for_vote(local_map_vote) + "\n✓ Ready to start!"
		else:
			voting_complete = true
			status_text = "You: " + _display_name_for_vote(local_map_vote) + " | Opponent: " + _display_name_for_vote(remote_map_vote) + "\nCoin flip will decide!"

	vote_status_label.text = status_text

func _on_ready_pressed() -> void:
	"""Handle ready button press"""
	if local_map_vote.is_empty():
		return
	
	print("[LOBBY] Player ready, waiting for opponent...")
	
	if ready_button:
		ready_button.disabled = true
		ready_button.text = "WAITING FOR OPPONENT..."
	
	# Broadcast ready status
	_broadcast_ready()
	
	# If both players ready, start game
	if voting_complete and not remote_map_vote.is_empty():
		_finalize_map_selection()

func _broadcast_ready() -> void:
	"""Broadcast ready status"""
	_send_lobby_message("player_ready", {
		"player_name": local_player_name
	})

func _finalize_map_selection() -> void:
	"""Finalize map selection and start game (HOST ONLY)"""
	print("[LOBBY] Finalizing map selection...")
	
	# Only host should finalize
	if not is_host:
		print("[LOBBY] Client waiting for host to finalize...")
		return

	# Apply the host's match settings locally BEFORE broadcasting game start, so the chosen
	# turn system rides along in _broadcast_game_start (versus_rounds stays host-local).
	if versus_config_panel != null:
		versus_config_panel.apply_settings()

	# NETWORKED SEED: when NetSession is the connected transport, kick the commit-reveal
	# match-RNG handshake now (host side). It drives itself to completion on both peers via
	# NetSession's RPCs before the battle's command seam needs a seed. No-op / harmless when
	# NetSession is not the live transport (the battle then falls back to a solo seed).
	_begin_net_match_rng()

	var final_map: String = ""
	
	if local_map_vote == remote_map_vote:
		# Both chose same map
		final_map = local_map_vote
		print("[LOBBY] Both players chose same map: " + final_map)
	else:
		# Coin flip (host decides)
		randomize()
		var coin_flip = randi() % 2
		final_map = local_map_vote if coin_flip == 0 else remote_map_vote
		
		var local_name: String = _display_name_for_vote(local_map_vote)
		var remote_name: String = _display_name_for_vote(remote_map_vote)
		var chosen_name: String = _display_name_for_vote(final_map)
		
		print("[LOBBY] Coin flip! Result: " + chosen_name)
		print("[LOBBY]   Your vote: " + local_name)
		print("[LOBBY]   Opponent vote: " + remote_name)
		
		# Show coin flip result
		if vote_status_label:
			vote_status_label.text = "Coin flip chose: " + chosen_name + "!"
		await get_tree().create_timer(2.0).timeout
	
	# Host broadcasts final map to client
	_broadcast_game_start(final_map)
	
	# Small delay to ensure message is sent before scene change
	await get_tree().create_timer(0.5).timeout
	
	# Host starts game
	_start_game(final_map)

func _begin_net_match_rng() -> void:
	"""Host-side kick of the NetSession commit-reveal match-RNG handshake, guarded so it only
	fires when NetSession is actually the connected server transport. The handshake completes
	on both peers via NetSession's own RPCs (client responds automatically), so the battle's
	CommandApplier has a shared match seed. Safe no-op when NetSession is not the live match."""
	if not _net_active():
		return
	if net_session.has_method("is_server") and bool(net_session.is_server()):
		net_session.begin_match_rng_handshake()

func _build_match_settings(map_path: String) -> Dictionary:
	"""The MatchSettings payload the host broadcasts so the client plays the SAME match instead
	of trusting its own local GameSettings. Shape:
	  {
	    map: String,                # builtin map resource path
	    map_json: String,           # validated custom-map JSON payload ("" for builtin)
	    turn_system: int,           # TurnSystemBase.TurnSystemType
	    versus_rounds: int,         # best-of round count
	    host_squad: Array,          # host's selected character ids (player slot 0)
	  }
	The client keeps its OWN selected_squad for its slot; host_squad names slot 0's roster.
	Custom-map JSON is carried when present so a client that lacks the .tres can still build
	the board from the host's validated payload."""
	var map_json: String = ""
	if GameSettings.has_method("get_custom_map_json"):
		map_json = str(GameSettings.get_custom_map_json())
	return {
		"map": map_path,
		"map_json": map_json,
		"turn_system": GameSettings.selected_turn_system,
		"versus_rounds": GameSettings.versus_rounds,
		"host_squad": GameSettings.get_selected_squad(),
	}

func _broadcast_game_start(map_path: String) -> void:
	"""Broadcast game start with final map + the full MatchSettings payload (host only)."""
	if not is_host:
		return

	print("[LOBBY] Broadcasting game start with map: " + map_path)

	_send_lobby_message("game_start", _build_match_settings(map_path))

func _start_game(map_path: String) -> void:
	"""Start the game with selected map"""
	print("[LOBBY] Starting game with map: " + map_path)

	# Re-affirm which slot is OURS on the way into the battle. The announcement earlier in the
	# lobby already did this, but a peer seated after its lobby node existed would have stamped
	# -1 then; by now the roster is settled. Cheap, idempotent, and the difference between
	# "our units read the local inventory" and "nobody is equipped at all".
	if _net_active() and net_session.has_method("local_slot"):
		MatchLoadouts.set_local_slot(int(net_session.local_slot()))

	# Update settings
	GameSettings.set_selected_map(map_path)
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	
	# Emit signal
	game_starting.emit(map_path)
	
	# Load game
	get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")

# Network message handlers (called by parent)
func handle_network_message(message_type: String, data: Dictionary, from_slot: int = -1) -> void:
	"""Handle network messages from other player.

	[param from_slot] is the sender's roster slot as the SERVER stamped it. It is optional and
	defaults to -1 so every existing 2-argument caller (the legacy MultiplayerGameState relay,
	the lobby suite) keeps working unchanged; only profile_info currently needs it."""
	print("[LOBBY] handle_network_message called: " + message_type)
	print("[LOBBY] Message data: " + str(data))

	match message_type:
		"lobby_hello":
			print("[LOBBY] Routing to _handle_lobby_hello")
			_handle_lobby_hello(data)
		"profile_info":
			print("[LOBBY] Routing to _handle_profile_info")
			_handle_profile_info(data, from_slot)
		"match_loadout":
			print("[LOBBY] Routing to _handle_match_loadout")
			_handle_match_loadout(data, from_slot)
		"lobby_state":
			print("[LOBBY] Routing to _handle_lobby_state")
			_handle_lobby_state(data)
		"map_vote":
			print("[LOBBY] Routing to _handle_map_vote")
			_handle_map_vote(data)
		"player_ready":
			print("[LOBBY] Routing to _handle_player_ready")
			_handle_player_ready(data)
		"game_start":
			print("[LOBBY] Routing to _handle_game_start")
			_handle_game_start(data)
		_:
			print("[LOBBY] Unknown message type: " + message_type)

func _handle_lobby_hello(data: Dictionary) -> void:
	"""A joining client announced itself (NetSession path). Host-only: admit it and answer
	with the current lobby state, so the client never sits on 'waiting for host' because the
	host's broadcast went out before its lobby node existed."""
	if not is_host:
		return
	var player_name: String = str(data.get("player_name", "Opponent")).strip_edges()
	if player_name.is_empty():
		player_name = "Opponent"
	print("[LOBBY] Opponent announced itself: " + player_name)
	_admit_remote_player(player_name)

func _handle_lobby_state(data: Dictionary) -> void:
	"""Handle lobby state change from host"""
	var state = data.get("state", "")
	print("[LOBBY] Received lobby state: " + state)
	
	match state:
		"map_selection":
			# Idempotent: the host answers the join hello AND its own roster poll, so this can
			# legitimately arrive twice. _show_map_selection() CLEARS both votes, so a repeat
			# once the player has already voted must be ignored, not replayed.
			if is_client_connected and map_selection_panel != null and map_selection_panel.visible:
				print("[LOBBY] Already in map selection - ignoring duplicate state message")
				return
			is_client_connected = true
			_show_map_selection()

func _handle_map_vote(data: Dictionary) -> void:
	"""Handle map vote from other player"""
	print("[LOBBY] _handle_map_vote called with data: " + str(data))
	
	var player_name = data.get("player_name", "")
	var map_path = data.get("map_path", "")
	
	print("[LOBBY] Extracted player_name: '" + player_name + "', local_player_name: '" + local_player_name + "'")
	
	if player_name != local_player_name:
		remote_map_vote = map_path
		remote_player_name = player_name

		print("[LOBBY] Opponent voted for: " + _display_name_for_vote(map_path))

		_update_vote_status()
	else:
		print("[LOBBY] Ignoring own vote (player_name matches local_player_name)")

func _handle_player_ready(data: Dictionary) -> void:
	"""Handle player ready from other player"""
	print("[LOBBY] _handle_player_ready called with data: " + str(data))
	
	var player_name = data.get("player_name", "")
	
	print("[LOBBY] Extracted player_name: '" + player_name + "', local_player_name: '" + local_player_name + "'")
	print("[LOBBY] local_map_vote: '" + local_map_vote + "', ready_button.disabled: " + str(ready_button.disabled if ready_button else "null"))
	
	if player_name != local_player_name:
		print("[LOBBY] Opponent is ready!")
		
		# If we're also ready, finalize
		if not local_map_vote.is_empty() and ready_button and ready_button.disabled:
			print("[LOBBY] We're also ready! Finalizing map selection...")
			_finalize_map_selection()
		else:
			print("[LOBBY] We're not ready yet (local_map_vote empty: " + str(local_map_vote.is_empty()) + ", button disabled: " + str(ready_button.disabled if ready_button else "null") + ")")
	else:
		print("[LOBBY] Ignoring own ready (player_name matches local_player_name)")

func _handle_game_start(data: Dictionary) -> void:
	"""Handle game start message from host (CLIENT ONLY)"""
	print("[LOBBY] _handle_game_start called with data: " + str(data))
	
	if is_host:
		print("[LOBBY] Host ignoring own game_start message")
		return
	
	var map_path = data.get("map", "")
	var turn_system = data.get("turn_system", "")

	if map_path.is_empty():
		print("[LOBBY] ERROR: No map path in game_start message")
		return

	print("[LOBBY] Client received game start command")
	print("[LOBBY]   Map: " + map_path)
	print("[LOBBY]   Turn System: " + str(turn_system))

	# Update turn system if provided. Newer hosts send it as an int (TurnSystemType); the
	# legacy payload sent a String -- accept either so mismatched builds don't desync here.
	if turn_system is int:
		GameSettings.selected_turn_system = turn_system
	elif turn_system is String and not (turn_system as String).is_empty():
		GameSettings.selected_turn_system = turn_system

	# Apply the rest of the host's MatchSettings so the client plays the SAME match instead of
	# its own local config. The client keeps its OWN selected_squad (its slot's roster); the
	# host_squad names slot 0. Custom-map JSON is stored when the host sent one so a client
	# without the .tres can still build the board. All optional -- legacy payloads omit them.
	if data.has("versus_rounds") and GameSettings.has_method("set_versus_rounds"):
		GameSettings.set_versus_rounds(int(data.get("versus_rounds", 1)))
	if data.has("host_squad") and GameSettings.has_method("set_host_squad"):
		GameSettings.set_host_squad(data.get("host_squad", []))
	var custom_json: String = str(data.get("map_json", ""))
	if not custom_json.is_empty() and GameSettings.has_method("set_custom_map_json"):
		GameSettings.set_custom_map_json(custom_json)
	
	# Show starting message
	if vote_status_label:
		vote_status_label.text = "Starting game with: " + _display_name_for_vote(map_path) + "!"
	
	# Small delay for UI feedback
	await get_tree().create_timer(1.0).timeout
	
	# Client starts game with host's chosen map
	_start_game(map_path)
