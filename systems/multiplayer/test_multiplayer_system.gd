extends Node

# Test script for the multiplayer system
# Demonstrates how to use the modular networking architecture
# Tests local development mode, P2P mode, and basic game actions

var multiplayer_manager: MultiplayerManager
var network_manager: NetworkManager
var status_label: Label

func _ready() -> void:
	print("=== Multiplayer System Test ===")
	
	# Get UI elements
	status_label = $UI/VBoxContainer/StatusLabel
	
	# Connect UI buttons
	$UI/VBoxContainer/LocalTestButton.pressed.connect(_on_local_test_pressed)
	$UI/VBoxContainer/P2PHostButton.pressed.connect(_on_p2p_host_pressed)
	$UI/VBoxContainer/P2PJoinButton.pressed.connect(_on_p2p_join_pressed)
	
	# Create multiplayer manager
	multiplayer_manager = MultiplayerManager.new()
	add_child(multiplayer_manager)
	
	# Get network manager reference
	network_manager = multiplayer_manager._network_manager
	
	# Connect signals for testing
	multiplayer_manager.multiplayer_game_started.connect(_on_game_started)
	multiplayer_manager.player_joined.connect(_on_player_joined)
	multiplayer_manager.connection_status_changed.connect(_on_connection_status_changed)
	
	_update_status("Multiplayer system initialized")
	print("Available network modes:")
	for mode in NetworkBackend.NetworkMode.values():
		print("  - " + NetworkBackend.NetworkMode.keys()[mode])

func _update_status(text: String) -> void:
	"""Update status label"""
	if status_label:
		status_label.text = "Status: " + text
	print("Status: " + text)

func _on_local_test_pressed() -> void:
	"""Handle local test button press"""
	print("\n--- Local Development Mode Test ---")
	_test_local_development_mode()

func _on_p2p_host_pressed() -> void:
	"""Handle P2P host button press"""
	print("\n--- P2P Host Test ---")
	_test_p2p_mode()

func _on_p2p_join_pressed() -> void:
	"""Handle P2P join button press"""
	print("\n--- P2P Join Test ---")
	_manual_test_p2p_join()

func _start_test_sequence() -> void:
	"""Start the test sequence"""
	print("\n=== Starting Test Sequence ===")
	
	# Test 1: Local development mode
	print("\n--- Test 1: Local Development Mode ---")
	await _test_local_development_mode()
	
	# Test 2: P2P mode
	print("\n--- Test 2: P2P Mode ---")
	await _test_p2p_mode()
	
	# Test 3: Network mode switching
	print("\n--- Test 3: Network Mode Switching ---")
	await _test_network_mode_switching()
	
	print("\n=== Test Sequence Complete ===")

func _test_local_development_mode() -> void:
	"""Test local development networking"""
	_update_status("Testing local development mode...")
	
	# Start local multiplayer game
	var success = multiplayer_manager.start_local_multiplayer_game(["Alice", "Bob"])
	
	if success:
		_update_status("Local multiplayer game started successfully")
		
		# Test network simulation features
		if network_manager._local_backend:
			network_manager._local_backend.set_latency_simulation(true, 100)
			network_manager._local_backend.set_packet_loss_simulation(true, 0.05)
			print("✓ Network simulation enabled (100ms latency, 5% packet loss)")
		
		# Test game action submission
		await _test_game_actions()
		
		# Disconnect
		multiplayer_manager.disconnect_from_multiplayer()
		_update_status("Disconnected from local game")
	else:
		_update_status("Failed to start local multiplayer game")

func _test_p2p_mode() -> void:
	"""Test P2P networking"""
	_update_status("Testing P2P mode...")
	
	# Start P2P host
	var success = multiplayer_manager.start_p2p_multiplayer_game("Host Player", 4)
	
	if success:
		_update_status("P2P host started successfully")
		
		# Get connection info
		var connection_info = multiplayer_manager.get_host_connection_info()
		print("✓ Host connection info: %s" % str(connection_info))
		
		# Test UPnP settings
		network_manager.set_upnp_enabled(true)
		print("✓ UPnP enabled for NAT traversal")
		
		# Test game actions
		await _test_game_actions()
		
		# Keep host running for potential connections
		_update_status("P2P host running - others can join at localhost:8910")
	else:
		_update_status("Failed to start P2P host")

func _test_network_mode_switching() -> void:
	"""Test switching between network modes"""
	print("Testing network mode switching...")
	
	# Test switching to each mode
	var modes = [
		NetworkBackend.NetworkMode.LOCAL_DEVELOPMENT,
		NetworkBackend.NetworkMode.P2P_DIRECT,
		NetworkBackend.NetworkMode.DEDICATED_SERVER
	]
	
	for mode in modes:
		var mode_name = NetworkBackend.NetworkMode.keys()[mode]
		print("Switching to %s mode..." % mode_name)
		
		var success = network_manager.set_network_mode(mode)
		if success:
			print("✓ Successfully switched to %s mode" % mode_name)
			
			# Get backend info
			var backend_info = network_manager.get_backend_info()
			print("  Backend info: %s" % str(backend_info))
		else:
			print("✗ Failed to switch to %s mode" % mode_name)
		
		await get_tree().create_timer(0.5).timeout
	
	print("✓ Network mode switching test complete")

func _test_game_actions() -> void:
	"""Test submitting game actions"""
	print("Testing game actions...")
	
	# Test various game actions
	var actions = [
		{
			"type": "unit_select",
			"data": {"unit_id": "warrior_1", "player_id": 0}
		},
		{
			"type": "unit_move", 
			"data": {
				"unit_id": "warrior_1",
				"from_position": Vector3(0, 0, 0),
				"to_position": Vector3(2, 0, 1)
			}
		},
		{
			"type": "end_turn",
			"data": {"player_id": 0}
		}
	]
	
	for action in actions:
		var success = multiplayer_manager.submit_game_action(action.type, action.data)
		if success:
			print("✓ Action submitted: %s" % action.type)
		else:
			print("✗ Failed to submit action: %s" % action.type)
		
		await get_tree().create_timer(0.2).timeout
	
	print("✓ Game actions test complete")

# Signal handlers for testing
func _on_game_started(players: Array) -> void:
	"""Handle game started signal"""
	_update_status("Multiplayer game started with %d players" % players.size())

func _on_player_joined(player_id: int, player_name: String) -> void:
	"""Handle player joined signal"""
	_update_status("Player joined: %s (ID: %d)" % [player_name, player_id])

func _on_connection_status_changed(status: String) -> void:
	"""Handle connection status change"""
	_update_status("Connection: " + status)

# Input handling for manual testing
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				print("\n--- Manual Test: Local Development Mode ---")
				_test_local_development_mode()
			
			KEY_2:
				print("\n--- Manual Test: P2P Host ---")
				_test_p2p_mode()
			
			KEY_3:
				print("\n--- Manual Test: P2P Join ---")
				_manual_test_p2p_join()
			
			KEY_4:
				print("\n--- Manual Test: Dedicated Server ---")
				_manual_test_dedicated_server()
			
			KEY_D:
				print("\n--- Debug Info ---")
				_print_debug_info()
			
			KEY_Q:
				print("\n--- Disconnect ---")
				multiplayer_manager.disconnect_from_multiplayer()
			
			KEY_H:
				_print_help()

func _manual_test_p2p_join() -> void:
	"""Manual test for joining P2P game"""
	_update_status("Testing P2P join (connecting to localhost:8910)...")
	
	var success = multiplayer_manager.join_p2p_multiplayer_game("127.0.0.1", 8910, "Client Player")
	
	if success:
		_update_status("P2P join initiated")
	else:
		_update_status("Failed to initiate P2P join")

func _manual_test_dedicated_server() -> void:
	"""Manual test for dedicated server connection"""
	print("Testing dedicated server connection...")
	
	var success = multiplayer_manager.join_dedicated_server_game("127.0.0.1", 8080, "TestUser", "password")
	
	if success:
		print("✓ Dedicated server connection initiated")
	else:
		print("✗ Failed to initiate dedicated server connection")

func _print_debug_info() -> void:
	"""Print debug information"""
	print("\n=== Debug Information ===")
	
	# Multiplayer status
	var mp_status = multiplayer_manager.get_multiplayer_status()
	print("Multiplayer Status:")
	for key in mp_status:
		print("  %s: %s" % [key, str(mp_status[key])])
	
	# Network statistics
	var net_stats = network_manager.get_network_statistics()
	print("\nNetwork Statistics:")
	for key in net_stats:
		print("  %s: %s" % [key, str(net_stats[key])])
	
	# Backend info
	var backend_info = network_manager.get_backend_info()
	print("\nBackend Info:")
	for key in backend_info:
		print("  %s: %s" % [key, str(backend_info[key])])
	
	print("=== End Debug Info ===\n")

func _print_help() -> void:
	"""Print help information"""
	print("\n=== Multiplayer Test Controls ===")
	print("1 - Test Local Development Mode")
	print("2 - Test P2P Host")
	print("3 - Test P2P Join (localhost:8910)")
	print("4 - Test Dedicated Server")
	print("D - Print Debug Info")
	print("Q - Disconnect")
	print("H - Show this help")
	print("================================\n")

# Cleanup
func _exit_tree() -> void:
	if multiplayer_manager:
		multiplayer_manager.disconnect_from_multiplayer()
	print("Multiplayer test cleanup complete")