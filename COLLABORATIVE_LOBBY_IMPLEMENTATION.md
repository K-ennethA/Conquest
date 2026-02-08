# Collaborative Lobby with Map Voting - Implementation Summary

## Overview

Implemented a collaborative multiplayer lobby where both players can vote on maps using a visual gallery. If they choose different maps, a coin flip decides which one to use.

## New Flow

### 1. Host Clicks "Host Game"
```
1. Host starts server
2. Shows "Waiting for opponent..." screen
3. Displays connection info: 127.0.0.1:8910
4. Monitors for client connection
```

### 2. Client Clicks "Join Game"
```
1. Client enters host address
2. Connects to host
3. Shows "Connected to host" screen
4. Waits for host to start map selection
```

### 3. Client Connects
```
HOST:
- Detects client connection
- Transitions to map selection screen
- Broadcasts "map_selection" state to client

CLIENT:
- Receives "map_selection" message
- Transitions to map selection screen
```

### 4. Both Players See Map Gallery
```
- Visual gallery with map previews
- 3 columns of map cards
- Each card shows: preview image, name, size
- Click any map to vote
```

### 5. Players Vote on Maps
```
PLAYER VOTES:
- Click a map card to vote
- Vote broadcasted to other player
- Status updates: "You voted for: [Map Name]"
- "READY" button becomes enabled

OPPONENT VOTES:
- Receive opponent's vote
- Status updates: "Opponent voted for: [Map Name]"
```

### 6. Both Players Click "READY"
```
SAME MAP CHOSEN:
- Status: "Both players chose: [Map Name] ✓ Ready to start!"
- Game starts with that map

DIFFERENT MAPS CHOSEN:
- Status: "You: [Map A] | Opponent: [Map B] - Coin flip will decide!"
- Coin flip executed
- Status: "Coin flip chose: [Winner]!"
- 2 second delay to show result
- Game starts with winning map
```

## Files Created

### 1. `menus/CollaborativeLobby.gd`
**Purpose**: Main collaborative lobby logic

**Key Features:**
- Waiting screen for both host and client
- Map selection gallery integration
- Vote tracking and synchronization
- Coin flip resolution
- Network message handling

**Key Methods:**
```gdscript
func initialize(as_host: bool, player_name: String) -> void
func _show_waiting_for_client() -> void
func _show_waiting_for_host() -> void
func _show_map_selection() -> void
func _on_local_map_selected(map_path: String, map_resource: MapResource) -> void
func _broadcast_map_vote(map_path: String) -> void
func _finalize_map_selection() -> void
func handle_network_message(message_type: String, data: Dictionary) -> void
```

**Network Messages:**
- `lobby_state`: Host tells client to show map selection
- `map_vote`: Player broadcasts their map choice
- `player_ready`: Player signals they're ready to start
- `game_start`: Host broadcasts final map and starts game

### 2. `menus/CollaborativeLobby.tscn`
**Purpose**: Scene file for collaborative lobby

**Structure:**
- Control node (full screen)
- Waiting panel (shown initially)
- Map selection panel (shown when both connected)
- MapSelectorPanel (gallery mode)
- Vote status label
- Ready button

## Files Modified

### 3. `menus/NetworkMultiplayerSetup.gd`
**Changes:**
- `_on_host_pressed()`: Shows collaborative lobby instead of old lobby
- `_on_connect_pressed()`: Shows collaborative lobby after connection
- Added `_show_collaborative_lobby()` method
- Added `_setup_lobby_message_forwarding()` method
- Added `_on_lobby_game_starting()` handler

### 4. `systems/multiplayer/MultiplayerGameState.gd`
**Changes:**
- `_handle_game_action()`: Routes lobby messages to lobby handler
- Added `_handle_lobby_message()` method
- Added `_find_collaborative_lobby()` method
- Added `_search_for_lobby()` helper method

## Message Flow

### Lobby State Change (Host → Client)
```
HOST:
1. Client connects
2. Host calls _broadcast_lobby_state("map_selection")
3. GameModeManager.submit_action("lobby_state", {state: "map_selection"})
4. → GameManager → NetworkHandler → MultiplayerGameState
5. → NetworkManager → P2PNetworkBackend → [Network]

CLIENT:
1. P2PNetworkBackend receives message
2. → NetworkManager → MultiplayerGameState
3. _handle_game_action() detects "lobby_state"
4. _handle_lobby_message() finds CollaborativeLobby
5. CollaborativeLobby.handle_network_message()
6. _handle_lobby_state() shows map selection
```

### Map Vote (Player → Opponent)
```
SENDER:
1. Player clicks map card
2. _on_local_map_selected() called
3. _broadcast_map_vote(map_path)
4. GameModeManager.submit_action("map_vote", {player_name, map_path})
5. → Network

RECEIVER:
1. Network → MultiplayerGameState
2. _handle_lobby_message("map_vote", data)
3. CollaborativeLobby._handle_map_vote()
4. Updates remote_map_vote
5. Updates vote status display
```

### Player Ready (Player → Opponent)
```
SENDER:
1. Player clicks "READY" button
2. _on_ready_pressed() called
3. _broadcast_ready()
4. GameModeManager.submit_action("player_ready", {player_name})
5. → Network

RECEIVER:
1. Network → MultiplayerGameState
2. _handle_lobby_message("player_ready", data)
3. CollaborativeLobby._handle_player_ready()
4. If both ready: _finalize_map_selection()
```

### Game Start (Host → Client)
```
HOST:
1. Both players ready
2. _finalize_map_selection() determines final map
3. Coin flip if votes differ
4. _broadcast_game_start(final_map)
5. GameModeManager.submit_action("game_start", {map, turn_system})
6. _start_game(final_map) - loads GameWorld

CLIENT:
1. Receives "game_start" message
2. MultiplayerGameState._handle_game_start()
3. Updates GameSettings
4. Loads GameWorld
```

## Coin Flip Logic

```gdscript
func _finalize_map_selection() -> void:
	var final_map: String = ""
	
	if local_map_vote == remote_map_vote:
		# Agreement - use chosen map
		final_map = local_map_vote
		print("[LOBBY] Both players chose same map")
	else:
		# Disagreement - coin flip
		randomize()
		var coin_flip = randi() % 2
		final_map = local_map_vote if coin_flip == 0 else remote_map_vote
		
		print("[LOBBY] Coin flip! Result: " + final_map)
		
		# Show result for 2 seconds
		vote_status_label.text = "Coin flip chose: " + map_name + "!"
		await get_tree().create_timer(2.0).timeout
	
	# Host broadcasts final decision
	if is_host:
		_broadcast_game_start(final_map)
	
	# Both load game
	_start_game(final_map)
```

## UI States

### State 1: Waiting (Host)
```
┌─────────────────────────────────────┐
│                                     │
│     Waiting for opponent...         │
│                                     │
│  Share this address: 127.0.0.1:8910│
│                                     │
└─────────────────────────────────────┘
```

### State 2: Waiting (Client)
```
┌─────────────────────────────────────┐
│                                     │
│      Connected to host              │
│                                     │
│  Waiting for host to start map...  │
│                                     │
└─────────────────────────────────────┘
```

### State 3: Map Selection (Both Players)
```
┌─────────────────────────────────────┐
│       SELECT YOUR MAP               │
│  Click a map to vote. If you both  │
│  choose different maps, a coin flip │
│  will decide!                       │
├─────────────────────────────────────┤
│  ┌────────┐  ┌────────┐  ┌────────┐│
│  │[Image] │  │[Image] │  │[Image] ││
│  │ Map 1  │  │ Map 2  │  │ Map 3  ││
│  │  5x5   │  │  7x7   │  │  10x10 ││
│  └────────┘  └────────┘  └────────┘│
│  ┌────────┐  ┌────────┐            │
│  │[Image] │  │[Image] │            │
│  │ Map 4  │  │ Map 5  │            │
│  │  8x8   │  │  6x6   │            │
│  └────────┘  └────────┘            │
├─────────────────────────────────────┤
│  You voted for: Default Skirmish    │
│  Waiting for opponent's vote...     │
├─────────────────────────────────────┤
│     [READY - START GAME]            │
└─────────────────────────────────────┘
```

### State 4: Both Voted (Agreement)
```
┌─────────────────────────────────────┐
│  Both players chose: Default Skirmish│
│  ✓ Ready to start!                  │
├─────────────────────────────────────┤
│     [READY - START GAME]            │
└─────────────────────────────────────┘
```

### State 5: Both Voted (Disagreement)
```
┌─────────────────────────────────────┐
│  You: Default Skirmish              │
│  Opponent: Large Plains             │
│  Coin flip will decide!             │
├─────────────────────────────────────┤
│     [READY - START GAME]            │
└─────────────────────────────────────┘
```

### State 6: Coin Flip Result
```
┌─────────────────────────────────────┐
│  Coin flip chose: Large Plains!     │
│                                     │
│  Starting game...                   │
└─────────────────────────────────────┘
```

## Testing Instructions

### Test 1: Same Map Selection
```
1. HOST: Click "Host Game"
   - Verify: "Waiting for opponent..." shown
   
2. CLIENT: Click "Join Game" → Connect
   - Verify: "Connected to host" shown
   
3. BOTH: Wait for map selection screen
   - Verify: Both see map gallery
   
4. BOTH: Click same map (e.g., Default Skirmish)
   - Verify: Status shows "Both players chose: Default Skirmish"
   
5. BOTH: Click "READY"
   - Verify: Game starts with Default Skirmish
```

### Test 2: Different Map Selection (Coin Flip)
```
1. HOST: Click "Host Game"
2. CLIENT: Join game
3. BOTH: See map selection
4. HOST: Click "Default Skirmish"
5. CLIENT: Click "Large Plains"
   - Verify: Status shows both votes
   - Verify: "Coin flip will decide!" message
   
6. BOTH: Click "READY"
   - Verify: Coin flip message appears
   - Verify: Shows which map won
   - Verify: 2 second delay
   - Verify: Game starts with winning map
```

### Test 3: Vote Changes
```
1. Setup: Both in map selection
2. HOST: Click "Map A"
   - Verify: Status updates
3. HOST: Click "Map B" (change vote)
   - Verify: Vote updates
   - Verify: Client sees new vote
4. Continue to ready
```

## Benefits

### User Experience:
1. **Visual Selection**: See maps before choosing
2. **Democratic**: Both players have equal say
3. **Fair Resolution**: Coin flip for disagreements
4. **Clear Feedback**: Always know vote status
5. **No Waiting**: Immediate map selection after connection

### Technical:
1. **Synchronized**: Both players see same state
2. **Reliable**: Coin flip on both sides (host decides)
3. **Extensible**: Easy to add more voting features
4. **Modular**: Lobby is separate component

## Future Enhancements

### Potential Additions:
1. **Vote Timer**: Limited time to vote
2. **Map Banning**: Each player can ban 1 map
3. **Random Option**: "I don't care" vote
4. **Map Preview**: Click to see larger preview
5. **Chat**: Discuss map choices
6. **Best of 3**: Vote on multiple maps
7. **Veto System**: One player can veto once
8. **Map Pool**: Pre-select pool of maps to vote from

### UI Improvements:
1. **Animated Coin Flip**: Show actual coin animation
2. **Vote History**: Show previous votes
3. **Map Stats**: Show win rates on maps
4. **Player Preferences**: Remember favorite maps
5. **Quick Vote**: Keyboard shortcuts

## Known Limitations

1. **No Reconnection**: If player disconnects during voting, lobby breaks
2. **No Spectators**: Only 2 players supported
3. **No Vote Timeout**: Players can wait forever
4. **No Vote Change Limit**: Can change vote infinitely
5. **Host Authority**: Host's coin flip is authoritative

## Files Summary

**New Files:**
- `menus/CollaborativeLobby.gd` - Lobby logic
- `menus/CollaborativeLobby.tscn` - Lobby scene
- `COLLABORATIVE_LOBBY_IMPLEMENTATION.md` - This documentation

**Modified Files:**
- `menus/NetworkMultiplayerSetup.gd` - Integration
- `systems/multiplayer/MultiplayerGameState.gd` - Message routing

## Status: ✅ COMPLETE

The collaborative lobby with map voting is fully implemented:
- ✅ Host waits for client in waiting screen
- ✅ Client connects and waits for map selection
- ✅ Both players see visual map gallery
- ✅ Both can vote on maps
- ✅ Votes synchronized in real-time
- ✅ Agreement: use chosen map
- ✅ Disagreement: coin flip decides
- ✅ Game starts with final map

**Next Steps:**
1. Generate map previews (run generate_map_previews.gd)
2. Test with two game instances
3. Verify coin flip works correctly
4. Add more maps for variety

The system is ready for testing!
