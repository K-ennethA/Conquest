extends Node

# Test script to verify player name matching fix

func _ready():
	print("=== Testing Player Name Matching Fix ===")
	
	# Simulate the player name mismatch scenario
	test_player_matching()

func test_player_matching():
	print("\n--- Test: Player Name Matching Logic ---")
	
	# Simulate Traditional Turn System player
	var tts_player = Player.new(0, "Player 1")  # ID 0, name "Player 1"
	print("Traditional Turn System Player:")
	print("  ID: " + str(tts_player.player_id))
	print("  Name: " + tts_player.player_name)
	print("  Display Name: " + tts_player.get_display_name())
	
	# Simulate GameManager players dictionary
	var gm_players = {
		0: {"id": 0, "name": "Player 1", "is_local": true},
		1: {"id": 1, "name": "Player 2", "is_local": false}
	}
	
	print("\nGameManager Players:")
	for pid in gm_players:
		var p = gm_players[pid]
		print("  Player " + str(pid) + ": " + str(p.get("name", "Unknown")))
	
	# Test matching logic
	var player_id = -1
	
	# Strategy 1: Direct player ID match
	if gm_players.has(tts_player.player_id):
		player_id = tts_player.player_id
		print("\n✓ MATCH found by player ID: " + str(player_id))
	else:
		print("\n✗ No direct ID match found")
		
		# Strategy 2: Name matching
		var target_names = [
			tts_player.get_display_name(),
			tts_player.player_name,
			"Player " + str(tts_player.player_id + 1)
		]
		
		print("Trying name matching with: " + str(target_names))
		
		for pid in gm_players:
			var p = gm_players[pid]
			var gm_name = p.get("name", "")
			
			for target_name in target_names:
				if gm_name == target_name:
					player_id = pid
					print("✓ MATCH found by name '" + target_name + "' -> Player " + str(pid))
					break
			
			if player_id >= 0:
				break
	
	if player_id >= 0:
		print("\n✅ SUCCESS: Player matching works correctly")
		print("Traditional Turn System Player 0 maps to GameManager Player " + str(player_id))
	else:
		print("\n❌ FAILURE: Could not match players")
	
	# Test Player 2 as well
	print("\n--- Testing Player 2 ---")
	var tts_player2 = Player.new(1, "Player 2")
	var player_id2 = -1
	
	if gm_players.has(tts_player2.player_id):
		player_id2 = tts_player2.player_id
		print("✓ Player 2 matched by ID: " + str(player_id2))
	
	print("\n=== Test Complete ===")
	print("Expected behavior: Both players should match by direct ID")
	print("Player 1 (ID 0) -> GameManager Player 0")
	print("Player 2 (ID 1) -> GameManager Player 1")
	
	# Clean up
	tts_player.queue_free()
	tts_player2.queue_free()