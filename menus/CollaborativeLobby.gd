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

func _ready() -> void:
	print("[LOBBY] _ready() called")
	theme = MenuTheme.build()  # dark Legends-style menu look (also inherited when nested)
	game_mode_manager = GameModeManager
	if not game_mode_manager:
		print("[LOBBY] ERROR: GameModeManager not found")
		return
	
	print("[LOBBY] Building UI...")
	_build_ui()
	print("[LOBBY] UI built successfully")

func initialize(as_host: bool, player_name: String) -> void:
	"""Initialize the lobby as host or client"""
	is_host = as_host
	local_player_name = player_name
	
	print("[LOBBY] Initialized as " + ("HOST" if is_host else "CLIENT"))
	print("[LOBBY] Player name: " + player_name)
	
	if is_host:
		_show_waiting_for_client()
		_start_monitoring_connections()
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

	if not game_mode_manager:
		print("[LOBBY] ERROR: game_mode_manager is null")
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
	
	var status = game_mode_manager.get_game_status()
	var network_stats = status.get("network_stats", {})
	var connected_peers = network_stats.get("connected_peers", 0)
	
	# connected_peers is an integer (peer count), not an array
	var peer_count = 0
	if connected_peers is int:
		peer_count = connected_peers
	elif connected_peers is Array:
		peer_count = connected_peers.size()
	
	print("[LOBBY] Checking connections... Peers: " + str(peer_count))
	
	if peer_count > 0:
		print("[LOBBY] Client connected!")
		is_client_connected = true
		remote_player_name = "Opponent"
		
		# Show map selection for host
		_show_map_selection()
		
		# Tell client to show map selection
		_broadcast_lobby_state("map_selection")
	else:
		# Keep checking (but with safety limit)
		_check_for_connections()

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
	if not game_mode_manager:
		return
	
	var vote_data = {
		"player_name": local_player_name,
		"map_path": map_path
	}
	
	game_mode_manager.submit_action("map_vote", vote_data)
	print("[LOBBY] Broadcasted map vote: " + map_path)

func _broadcast_lobby_state(state: String) -> void:
	"""Broadcast lobby state change (host only)"""
	if not is_host or not game_mode_manager:
		return
	
	game_mode_manager.submit_action("lobby_state", {
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
	if not game_mode_manager:
		return
	
	game_mode_manager.submit_action("player_ready", {
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
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return
	if NetSession.is_server() and NetSession.is_connected_session():
		NetSession.begin_match_rng_handshake()

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
	if not is_host or not game_mode_manager:
		return

	print("[LOBBY] Broadcasting game start with map: " + map_path)

	game_mode_manager.submit_action("game_start", _build_match_settings(map_path))

func _start_game(map_path: String) -> void:
	"""Start the game with selected map"""
	print("[LOBBY] Starting game with map: " + map_path)
	
	# Update settings
	GameSettings.set_selected_map(map_path)
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	
	# Emit signal
	game_starting.emit(map_path)
	
	# Load game
	get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")

# Network message handlers (called by parent)
func handle_network_message(message_type: String, data: Dictionary) -> void:
	"""Handle network messages from other player"""
	print("[LOBBY] handle_network_message called: " + message_type)
	print("[LOBBY] Message data: " + str(data))
	
	match message_type:
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

func _handle_lobby_state(data: Dictionary) -> void:
	"""Handle lobby state change from host"""
	var state = data.get("state", "")
	print("[LOBBY] Received lobby state: " + state)
	
	match state:
		"map_selection":
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
