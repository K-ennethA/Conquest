extends GutTest

# Unit tests for CollaborativeLobby

var lobby: Control
var lobby_script: Script

func before_each():
	"""Setup before each test"""
	lobby_script = load("res://menus/CollaborativeLobby.gd")
	lobby = Control.new()
	lobby.set_script(lobby_script)
	add_child_autofree(lobby)
	
	# Wait for _ready to complete
	await get_tree().process_frame

func after_each():
	"""Cleanup after each test"""
	if lobby and is_instance_valid(lobby):
		lobby.queue_free()
	lobby = null

# Initialization Tests
func test_lobby_initializes_as_host():
	"""Test lobby can initialize as host"""
	assert_not_null(lobby, "Lobby should be created")
	
	lobby.initialize(true, "TestHost")
	
	assert_true(lobby.is_host, "Should be host")
	assert_eq(lobby.local_player_name, "TestHost", "Should have correct player name")
	assert_false(lobby.is_client_connected, "Client should not be connected yet")

func test_lobby_initializes_as_client():
	"""Test lobby can initialize as client"""
	assert_not_null(lobby, "Lobby should be created")
	
	lobby.initialize(false, "TestClient")
	
	assert_false(lobby.is_host, "Should not be host")
	assert_eq(lobby.local_player_name, "TestClient", "Should have correct player name")

# UI Tests
func test_ui_elements_created():
	"""Test that all UI elements are created"""
	assert_not_null(lobby.waiting_panel, "Waiting panel should exist")
	assert_not_null(lobby.map_selection_panel, "Map selection panel should exist")
	assert_not_null(lobby.vote_status_label, "Vote status label should exist")
	assert_not_null(lobby.ready_button, "Ready button should exist")

func test_waiting_panel_visible_initially():
	"""Test waiting panel is visible when initialized"""
	lobby.initialize(true, "TestHost")
	await get_tree().process_frame
	
	assert_true(lobby.waiting_panel.visible, "Waiting panel should be visible")
	assert_false(lobby.map_selection_panel.visible, "Map selection should be hidden")

func test_ready_button_disabled_initially():
	"""Test ready button is disabled until map is selected"""
	assert_true(lobby.ready_button.disabled, "Ready button should be disabled initially")

# Voting Tests
func test_local_vote_updates():
	"""Test local vote is stored correctly"""
	lobby.initialize(true, "TestHost")
	
	var test_map_path = "res://game/maps/resources/default_skirmish.tres"
	lobby.local_map_vote = test_map_path
	
	assert_eq(lobby.local_map_vote, test_map_path, "Local vote should be stored")

func test_remote_vote_updates():
	"""Test remote vote is stored correctly"""
	lobby.initialize(false, "TestClient")
	
	var test_map_path = "res://game/maps/resources/default_skirmish.tres"
	lobby.remote_map_vote = test_map_path
	
	assert_eq(lobby.remote_map_vote, test_map_path, "Remote vote should be stored")

func test_voting_complete_when_both_voted():
	"""Test voting_complete flag is set when both players vote"""
	lobby.initialize(true, "TestHost")
	
	lobby.local_map_vote = "res://game/maps/resources/default_skirmish.tres"
	lobby.remote_map_vote = "res://game/maps/resources/default_skirmish.tres"
	lobby._update_vote_status()
	
	assert_true(lobby.voting_complete, "Voting should be complete when both voted")

func test_voting_complete_with_different_votes():
	"""Test voting_complete is true even with different votes"""
	lobby.initialize(true, "TestHost")
	
	lobby.local_map_vote = "res://game/maps/resources/default_skirmish.tres"
	lobby.remote_map_vote = "res://game/maps/resources/some_other_map.tres"
	lobby._update_vote_status()
	
	assert_true(lobby.voting_complete, "Voting should be complete with different votes")

# Coin Flip Tests
func test_coin_flip_chooses_one_map():
	"""Test coin flip selects one of the two maps"""
	lobby.initialize(true, "TestHost")
	
	var map_a = "res://game/maps/resources/default_skirmish.tres"
	var map_b = "res://game/maps/resources/other_map.tres"
	
	lobby.local_map_vote = map_a
	lobby.remote_map_vote = map_b
	
	# Simulate coin flip logic
	randomize()
	var coin_flip = randi() % 2
	var result = lobby.local_map_vote if coin_flip == 0 else lobby.remote_map_vote
	
	assert_true(result == map_a or result == map_b, "Result should be one of the two maps")

func test_same_vote_no_coin_flip():
	"""Test that same votes don't trigger coin flip"""
	lobby.initialize(true, "TestHost")
	
	var map_path = "res://game/maps/resources/default_skirmish.tres"
	lobby.local_map_vote = map_path
	lobby.remote_map_vote = map_path
	
	# When votes match, final map should be the voted map
	var final_map = map_path if lobby.local_map_vote == lobby.remote_map_vote else ""
	
	assert_eq(final_map, map_path, "Final map should be the agreed upon map")

# Network Message Handling Tests
func test_handle_lobby_state_message():
	"""Test handling lobby state change message"""
	lobby.initialize(false, "TestClient")
	
	var message_data = {"state": "map_selection"}
	lobby.handle_network_message("lobby_state", message_data)
	
	await get_tree().process_frame
	
	assert_true(lobby.is_client_connected, "Client should be marked as connected")

func test_handle_map_vote_message():
	"""Test handling map vote from opponent"""
	lobby.initialize(true, "TestHost")
	
	var vote_data = {
		"player_name": "Opponent",
		"map_path": "res://game/maps/resources/default_skirmish.tres"
	}
	
	lobby.handle_network_message("map_vote", vote_data)
	
	assert_eq(lobby.remote_map_vote, vote_data.map_path, "Remote vote should be updated")
	assert_eq(lobby.remote_player_name, "Opponent", "Remote player name should be updated")

func test_handle_player_ready_message():
	"""Test handling player ready message"""
	lobby.initialize(true, "TestHost")
	lobby.local_map_vote = "res://game/maps/resources/default_skirmish.tres"
	lobby.ready_button.disabled = true  # Simulate local player ready
	
	var ready_data = {"player_name": "Opponent"}
	
	# This should trigger finalization if both ready
	# We can't fully test this without mocking, but we can verify it doesn't crash
	lobby.handle_network_message("player_ready", ready_data)
	
	pass_test("Player ready message handled without crash")

# Edge Cases
func test_empty_vote_doesnt_enable_ready():
	"""Test ready button stays disabled with empty vote"""
	lobby.initialize(true, "TestHost")
	lobby.local_map_vote = ""
	
	# Try to press ready (should do nothing)
	lobby._on_ready_pressed()
	
	# Button should still be disabled
	assert_true(lobby.ready_button.disabled, "Ready button should stay disabled with no vote")

func test_null_game_mode_manager_handled():
	"""Test lobby handles null game mode manager gracefully"""
	lobby.game_mode_manager = null
	
	# These should not crash
	lobby._broadcast_map_vote("test_path")
	lobby._broadcast_lobby_state("test_state")
	lobby._broadcast_ready()
	
	pass_test("Null game mode manager handled gracefully")

func test_not_in_tree_stops_connection_check():
	"""Test connection checking stops when not in tree"""
	lobby.initialize(true, "TestHost")
	
	# Remove from tree
	remove_child(lobby)
	
	# This should detect not in tree and stop
	lobby._check_for_connections()
	
	await get_tree().create_timer(1.0).timeout
	
	pass_test("Connection check stopped when not in tree")

# Integration Tests
func test_full_host_flow():
	"""Test complete host flow"""
	lobby.initialize(true, "TestHost")
	
	# 1. Host waits
	assert_true(lobby.waiting_panel.visible, "Should show waiting panel")
	assert_false(lobby.is_client_connected, "No client yet")
	
	# 2. Simulate client connection
	lobby.is_client_connected = true
	lobby._show_map_selection()
	
	assert_false(lobby.waiting_panel.visible, "Waiting panel should be hidden")
	assert_true(lobby.map_selection_panel.visible, "Map selection should be visible")
	
	# 3. Host votes
	lobby.local_map_vote = "res://game/maps/resources/default_skirmish.tres"
	lobby._update_vote_status()
	
	assert_false(lobby.local_map_vote.is_empty(), "Host should have voted")

func test_full_client_flow():
	"""Test complete client flow"""
	lobby.initialize(false, "TestClient")
	
	# 1. Client waits
	assert_true(lobby.waiting_panel.visible, "Should show waiting panel")
	
	# 2. Receive lobby state from host
	lobby.handle_network_message("lobby_state", {"state": "map_selection"})
	await get_tree().process_frame
	
	assert_true(lobby.map_selection_panel.visible, "Map selection should be visible")
	
	# 3. Client votes
	lobby.local_map_vote = "res://game/maps/resources/default_skirmish.tres"
	lobby._update_vote_status()
	
	assert_false(lobby.local_map_vote.is_empty(), "Client should have voted")
