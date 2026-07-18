# Lobby Message Routing Fix

## Issue
Both players can vote and click "READY - START GAME", but the game doesn't start. The `player_ready` messages are sent but not received by the lobby.

### Symptoms
```
[LOBBY] Player ready, waiting for opponent...
Network multiplayer: allowing action player_ready for player 0
NetworkManager: Game action from peer 1 - player_action
[HOST] Action type: player_ready
Unknown action type: player_ready  ← Not handled!
(Game never starts)
```

## Root Cause
Lobby actions (`map_vote`, `player_ready`, `lobby_state`) are submitted through `game_mode_manager.submit_action()`, which wraps them in a `player_action` envelope. 

MultiplayerGameState was checking for `action_type == "player_ready"` directly, but the actual structure is:
```json
{
  "action_type": "player_action",
  "action_data": {
    "type": "player_ready",
    "data": { "player_name": "..." }
  }
}
```

So the check `if action_type in ["lobby_state", "map_vote", "player_ready"]` never matched, and the messages were never routed to `_handle_lobby_message()`.

## Solution
Updated `_handle_game_action()` in MultiplayerGameState to unwrap `player_action` messages and check the inner type:

```gdscript
func _handle_game_action(sender_id: int, message: Dictionary) -> void:
    var action_type = message.get("action_type", "")
    var action_data = message.get("action_data", {})
    
    // NEW: Check inside player_action wrapper
    if action_type == "player_action":
        var inner_type = action_data.get("type", "")
        if inner_type in ["lobby_state", "map_vote", "player_ready"]:
            print("[MULTIPLAYER] Lobby message: " + inner_type)
            _handle_lobby_message(inner_type, action_data.get("data", {}))
            return
    
    // Fallback for direct lobby messages
    if action_type in ["lobby_state", "map_vote", "player_ready"]:
        _handle_lobby_message(action_type, action_data)
        return
    
    // ... rest of handler
```

Now lobby messages are properly unwrapped and routed to the lobby!

## Files Modified
- `systems/multiplayer/MultiplayerGameState.gd` - Added unwrapping of player_action messages

## Expected Behavior After Fix

### Console Output
```
[LOBBY] Player ready, waiting for opponent...
NetworkManager: Game action from peer 1 - player_action
[MULTIPLAYER] Lobby message: player_ready  ← NEW! Message routed!
[LOBBY] Opponent is ready!  ← NEW! Lobby receives it!
[LOBBY] Finalizing map selection...
[LOBBY] Starting game with map: ...
(Game starts!)
```

### Game Flow
1. Both players vote on maps ✓
2. Both click "READY - START GAME" ✓
3. `player_ready` messages sent ✓
4. Messages routed to lobby ✓ (was broken, now fixed!)
5. Lobby detects both ready ✓
6. Finalizes map selection (coin flip if different) ✓
7. Starts game ✓

## Testing
Run the same test:

1. **Host:** Run game → Multiplayer → Network Multiplayer → Host Game
2. **Client:** Run second instance → Join → 127.0.0.1:8910 → Connect
3. **Both:** Should see map selection screen
4. **Both:** Click a map to vote
5. **Both:** Click "READY - START GAME"
6. **Expected:** Game should start on both instances!

Look for this in the console:
```
[MULTIPLAYER] Lobby message: player_ready
[LOBBY] Opponent is ready!
[LOBBY] Finalizing map selection...
```

## Technical Details

### Message Flow Before Fix
```
Lobby: submit_action("player_ready", {...})
  ↓
GameModeManager: submit_player_action()
  ↓
GameManager: Wraps in player_action
  ↓
Network: Sends { action_type: "player_action", action_data: { type: "player_ready", ... }}
  ↓
MultiplayerGameState: Checks action_type == "player_ready"  ❌ Doesn't match!
  ↓
Falls through to GameManager
  ↓
"Unknown action type: player_ready"
```

### Message Flow After Fix
```
Lobby: submit_action("player_ready", {...})
  ↓
GameModeManager: submit_player_action()
  ↓
GameManager: Wraps in player_action
  ↓
Network: Sends { action_type: "player_action", action_data: { type: "player_ready", ... }}
  ↓
MultiplayerGameState: Checks action_type == "player_action"  ✓ Matches!
  ↓
Unwraps: inner_type = "player_ready"  ✓
  ↓
Checks inner_type in ["player_ready", ...]  ✓ Matches!
  ↓
Calls _handle_lobby_message("player_ready", data)  ✓
  ↓
Routes to CollaborativeLobby.handle_network_message()  ✓
  ↓
Lobby processes player_ready  ✓
```

## Status
✅ **FIXED** - Lobby messages now properly routed through MultiplayerGameState

## Related Fixes
1. **P2P Connection Polling** - Fixed connection establishment
2. **Lobby Peer Count** - Fixed peer detection on host
3. **Client Lobby Initialization** - Fixed client showing map selection
4. **Lobby Message Routing** - Fixed message routing to lobby (this fix)

All four fixes together enable the complete collaborative lobby flow with map voting and game start!
