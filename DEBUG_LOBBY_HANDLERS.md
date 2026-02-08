# Debug Lobby Message Handlers

## Current Status
The lobby IS being found and `handle_network_message()` IS being called, but the messages aren't being processed. No `[LOBBY] Opponent voted for:` or `[LOBBY] Opponent is ready!` messages appear.

## Added Comprehensive Debug Logging

Added detailed logging to track the message flow through the lobby:

### 1. Entry Point Logging
```gdscript
func handle_network_message(message_type: String, data: Dictionary) -> void:
    print("[LOBBY] handle_network_message called: " + message_type)
    print("[LOBBY] Message data: " + str(data))
    print("[LOBBY] Routing to _handle_" + message_type)
```

### 2. Map Vote Handler Logging
```gdscript
func _handle_map_vote(data: Dictionary) -> void:
    print("[LOBBY] _handle_map_vote called with data: " + str(data))
    print("[LOBBY] Extracted player_name: '" + player_name + "', local_player_name: '" + local_player_name + "'")
    
    if player_name != local_player_name:
        print("[LOBBY] Opponent voted for: " + map_resource.map_name)
    else:
        print("[LOBBY] Ignoring own vote")
```

### 3. Player Ready Handler Logging
```gdscript
func _handle_player_ready(data: Dictionary) -> void:
    print("[LOBBY] _handle_player_ready called with data: " + str(data))
    print("[LOBBY] Extracted player_name: '" + player_name + "', local_player_name: '" + local_player_name + "'")
    
    if player_name != local_player_name:
        print("[LOBBY] Opponent is ready!")
        if ready to finalize:
            print("[LOBBY] We're also ready! Finalizing...")
        else:
            print("[LOBBY] We're not ready yet")
    else:
        print("[LOBBY] Ignoring own ready")
```

## What to Look For in Next Test

When you run the test and both players click "READY - START GAME", you should see:

### If Working Correctly
```
[MULTIPLAYER] Calling lobby.handle_network_message()
[LOBBY] handle_network_message called: player_ready
[LOBBY] Message data: { "player_name": "Player" }
[LOBBY] Routing to _handle_player_ready
[LOBBY] _handle_player_ready called with data: { "player_name": "Player" }
[LOBBY] Extracted player_name: 'Player', local_player_name: 'Host Player'
[LOBBY] Opponent is ready!
[LOBBY] We're also ready! Finalizing map selection...
[LOBBY] Finalizing map selection...
[LOBBY] Starting game with map: ...
```

### Possible Issues

**Issue 1: Method Not Called**
If you don't see `[LOBBY] handle_network_message called`, the method isn't being invoked.

**Issue 2: Player Name Mismatch**
If you see `[LOBBY] Ignoring own vote/ready`, the `player_name` in the data matches `local_player_name`, so it's being filtered out.

**Issue 3: Empty Player Name**
If `player_name` is empty (`""`), it might match an empty `local_player_name`.

**Issue 4: Not Ready Yet**
If you see `[LOBBY] We're not ready yet`, the local player hasn't clicked ready or the button state is wrong.

## Test Instructions

1. Run the full test again
2. Both players vote and click "READY - START GAME"
3. Check the console for the new detailed debug messages
4. Report back what you see!

The debug output will show us exactly why the messages aren't being processed.
