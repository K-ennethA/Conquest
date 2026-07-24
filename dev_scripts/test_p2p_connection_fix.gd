extends Node

# Test P2P connection with the polling fix
# This test verifies that the multiplayer API is being polled correctly

func _ready() -> void:
	print("=== P2P Connection Fix Test ===")
	print("Testing if multiplayer API polling resolves connection issue")
	
	# Wait a frame for everything to initialize
	await get_tree().process_frame
	
	# Check if we're running as host or client
	var args = OS.get_cmdline_args()
	var is_auto_join = args.has("--multiplayer-auto-join")
	
	if is_auto_join:
		print("\n[CLIENT TEST] Running as auto-join client")
		_test_as_client()
	else:
		print("\n[HOST TEST] Running as host")
		_test_as_host()

func _test_as_host() -> void:
	"""Test as host"""
	print("[HOST] Initializing NetworkManager...")
	
	# Get NetworkManager
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		print("[HOST] ERROR: NetworkManager not found")
		return
	
	print("[HOST] Setting network mode to P2P...")
	network_manager.set_network_mode(NetworkBackend.NetworkMode.P2P_DIRECT)
	
	# Connect signals
	network_manager.connection_established.connect(_on_host_connection_established)
	network_manager.connection_failed.connect(_on_host_connection_failed)
	
	print("[HOST] Starting host on port 8910...")
	var success = network_manager.start_host(8910)
	
	if success:
		print("[HOST] ✓ Host started successfully")
		print("[HOST] Waiting for client to connect...")
		_monitor_host_connections()
	else:
		print("[HOST] ✗ Failed to start host")

func _test_as_client() -> void:
	"""Test as client"""
	print("[CLIENT] Initializing NetworkManager...")
	
	# Get NetworkManager
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		print("[CLIENT] ERROR: NetworkManager not found")
		return
	
	print("[CLIENT] Setting network mode to P2P...")
	network_manager.set_network_mode(NetworkBackend.NetworkMode.P2P_DIRECT)
	
	# Connect signals
	network_manager.connection_established.connect(_on_client_connection_established)
	network_manager.connection_failed.connect(_on_client_connection_failed)
	
	# Wait a moment for host to be ready
	await get_tree().create_timer(1.0).timeout
	
	print("[CLIENT] Connecting to host at 127.0.0.1:8910...")
	var success = network_manager.join_host("127.0.0.1", 8910)
	
	if success:
		print("[CLIENT] ✓ Connection attempt started")
		print("[CLIENT] Waiting for connection to establish...")
		_monitor_client_connection()
	else:
		print("[CLIENT] ✗ Failed to start connection")

func _monitor_host_connections() -> void:
	"""Monitor for client connections on host"""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		return
	
	for i in range(20):  # Check for 10 seconds
		await get_tree().create_timer(0.5).timeout
		
		var peers = network_manager.get_connected_peers()
		var status = network_manager.get_connection_status()
		
		print("[HOST] Check %d: Status=%s, Peers=%d" % [i+1, NetworkBackend.ConnectionStatus.keys()[status], peers.size()])
		
		if peers.size() > 0:
			print("[HOST] ✓✓✓ CLIENT CONNECTED! ✓✓✓")
			print("[HOST] Connected peer IDs: " + str(peers))
			print("[HOST] TEST PASSED!")
			return
	
	print("[HOST] ✗ No client connected after 10 seconds")
	print("[HOST] TEST FAILED")

func _monitor_client_connection() -> void:
	"""Monitor connection status on client"""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		return
	
	for i in range(20):  # Check for 10 seconds
		await get_tree().create_timer(0.5).timeout
		
		var status = network_manager.get_connection_status()
		var peer_id = network_manager.get_local_peer_id()
		
		print("[CLIENT] Check %d: Status=%s, PeerID=%d" % [i+1, NetworkBackend.ConnectionStatus.keys()[status], peer_id])
		
		if status == NetworkBackend.ConnectionStatus.CONNECTED:
			print("[CLIENT] ✓✓✓ CONNECTED TO HOST! ✓✓✓")
			print("[CLIENT] Local peer ID: " + str(peer_id))
			print("[CLIENT] TEST PASSED!")
			return
	
	print("[CLIENT] ✗ Connection failed after 10 seconds")
	print("[CLIENT] TEST FAILED")

func _on_host_connection_established(peer_id: int) -> void:
	"""Handle connection established on host"""
	if peer_id == 1:
		print("[HOST] Host peer established (peer_id: 1)")
	else:
		print("[HOST] ✓ Client connected with peer_id: " + str(peer_id))

func _on_host_connection_failed(error: String) -> void:
	"""Handle connection failure on host"""
	print("[HOST] ✗ Connection failed: " + error)

func _on_client_connection_established(peer_id: int) -> void:
	"""Handle connection established on client"""
	print("[CLIENT] ✓ Connected to host! Local peer_id: " + str(peer_id))

func _on_client_connection_failed(error: String) -> void:
	"""Handle connection failure on client"""
	print("[CLIENT] ✗ Connection failed: " + error)
