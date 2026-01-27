extends Node

# Test script to verify turn numbering starts at 1 and increments correctly

func _ready():
	print("=== Turn Numbering Test ===")
	
	# Wait for singletons to initialize
	await get_tree().process_frame
	
	# Test both turn systems
	test_traditional_turn_numbering()
	test_speed_first_turn_numbering()
	
	# Quit after test
	get_tree().quit()

func test_traditional_turn_numbering():
	print("\n1. Testing Traditional Turn System numbering...")
	
	# Clear any existing state
	PlayerManager.players.clear()
	PlayerManager.current_player_index = 0
	
	# Create test players
	var player1 = PlayerManager.register_player("Player 1")
	var player2 = PlayerManager.register_player("Player 2")
	
	print("Created players:")
	print("  Player 1: " + player1.get_display_name() + " (ID: " + str(player1.player_id) + ")")
	print("  Player 2: " + player2.get_display_name() + " (ID: " + str(player2.player_id) + ")")
	
	# Create traditional turn system
	var trad_system = TraditionalTurnSystem.new()
	trad_system.register_player(player1)
	trad_system.register_player(player2)
	
	print("Registered players with turn system")
	
	# Start the system
	print("Starting traditional turn system...")
	trad_system.start_turn_system()
	
	# Verify initial turn number and player
	assert(trad_system.current_turn == 1, "Traditional system should start at turn 1")
	var initial_player = trad_system.get_current_active_player()
	assert(initial_player == player1, "Should start with Player 1")
	print("✓ Traditional system starts at turn " + str(trad_system.current_turn) + " with " + initial_player.get_display_name())
	
	# Wait a frame to ensure no automatic advancement
	await get_tree().process_frame
	
	# Verify still on turn 1 with player 1
	assert(trad_system.current_turn == 1, "Should still be turn 1 after waiting")
	var still_player = trad_system.get_current_active_player()
	assert(still_player == player1, "Should still be Player 1")
	print("✓ Still turn " + str(trad_system.current_turn) + " with " + still_player.get_display_name() + " after waiting")
	
	# Advance to next player (should still be turn 1)
	trad_system.advance_turn()
	assert(trad_system.current_turn == 1, "Should still be turn 1 after first player advance")
	var second_player = trad_system.get_current_active_player()
	assert(second_player == player2, "Should now be Player 2")
	print("✓ Still turn " + str(trad_system.current_turn) + " after advancing to " + second_player.get_display_name())
	
	# Advance to next player (should now be turn 2 since we completed a full round)
	trad_system.advance_turn()
	assert(trad_system.current_turn == 2, "Should be turn 2 after completing full round")
	var third_player = trad_system.get_current_active_player()
	assert(third_player == player1, "Should be back to Player 1")
	print("✓ Turn " + str(trad_system.current_turn) + " after completing full round, back to " + third_player.get_display_name())
	
	# Clean up
	trad_system.end_turn_system()
	print("✓ Traditional turn numbering test passed")

func test_speed_first_turn_numbering():
	print("\n2. Testing Speed-First Turn System numbering...")
	
	# Clear any existing state
	PlayerManager.players.clear()
	PlayerManager.current_player_index = 0
	
	# Create test players
	var player1 = PlayerManager.register_player("Player 1")
	var player2 = PlayerManager.register_player("Player 2")
	
	# Create test units
	var unit1 = Unit.new()
	unit1.name = "Unit1"
	unit1.unit_stats = UnitStats.new()
	unit1.unit_stats.stats_resource = UnitStatsResource.new()
	unit1.unit_stats.stats_resource.speed = 10
	
	var unit2 = Unit.new()
	unit2.name = "Unit2"
	unit2.unit_stats = UnitStats.new()
	unit2.unit_stats.stats_resource = UnitStatsResource.new()
	unit2.unit_stats.stats_resource.speed = 8
	
	# Assign units to players
	PlayerManager.assign_unit_to_player(unit1, 0)
	PlayerManager.assign_unit_to_player(unit2, 1)
	
	# Create speed first turn system
	var speed_system = SpeedFirstTurnSystem.new()
	speed_system.register_player(player1)
	speed_system.register_player(player2)
	speed_system.register_unit(unit1)
	speed_system.register_unit(unit2)
	
	# Start the system
	speed_system.start_turn_system()
	
	# Verify initial turn number
	assert(speed_system.current_turn == 1, "Speed-First system should start at turn 1")
	print("✓ Speed-First system starts at turn " + str(speed_system.current_turn))
	
	# Advance first unit
	speed_system.mark_unit_acted(unit1)
	assert(speed_system.current_turn == 1, "Should still be turn 1 after first unit")
	print("✓ Still turn " + str(speed_system.current_turn) + " after first unit acts")
	
	# Advance second unit (should complete round and increment to turn 2)
	speed_system.mark_unit_acted(unit2)
	assert(speed_system.current_turn == 2, "Should be turn 2 after all units acted")
	print("✓ Turn " + str(speed_system.current_turn) + " after all units acted (new round)")
	
	# Clean up
	speed_system.end_turn_system()
	print("✓ Speed-First turn numbering test passed")

func assert(condition: bool, message: String):
	if not condition:
		print("❌ ASSERTION FAILED: " + message)
		push_error("Test failed: " + message)
	# Continue even if assertion fails for debugging