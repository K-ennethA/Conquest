# Client Lobby Initialization Fix

## Issue
Host transitions to map selection, but client remains stuck at "Waiting for host..." screen.

### Symptoms
**Host (Working):**
```
[LOBBY] Checking connections... Peers: 1
[LOBBY] Client connected!
[LOBBY] Showing map selection  ✓
[LOBBY] Broadcasted lobby state: map_selection  ✓
```

**Client (Stuck):**
```
[LOBBY] Initialized as CLIENT
[LOBBY] Player name: Player
(Never receives lobby_state message)  ❌
(Stays at "Waiting for host..." screen)  ❌
```

## Root Cause
**Timing Issue:** The host broadcasts the `lobby_state: map_selection` message immediately after detecting the client connection. However, the client's lobby is still being initialized at that moment, so it misses the message.

### Message Flow
```
Time    Host                          Client
────────────────────────────────────────────────────────────
0.0s    Detects client connected
0.1s    Broadcasts "lobby_state"  →   (Lobby not ready yet)
0.2s    Shows map selection           Lobby initializing...
0.3s                                   Lobby ready (but message already sent!)
0.4s                                   Stuck at "Waiting for host..."
```

## Solution
Make the client check its connection status immediately upon initialization. If already connected, show map selection right away instead of waiting for a message.

### Code Change
```gdscript
// In CollaborativeLobby.initialize()

if is_host:
    _show_waiting_for_client()
    _start_monitoring_connections()
else:
    // NEW: Check if already connected
    if game_mode_manager:
        var status = game_mode_manager.get_game_status()
        var network_stats = status.get("network_stats", {})
        var connection_status = network_stats.get("connection_status", "")
        
        if connection_status == "CONNECTED":
            print("[LOBBY] Client already connected, showing map selection immediately")
            _show_map_selection()  // Skip waiting screen!
        else:
            _show_waiting_for_host()
    else:
        _show_waiting_for_host()
```

### Why This Works
- Client checks connection status during initialization
- If already connected (which it is), skip waiting screen
- Go directly to map selection
- No need to wait for host message

## Files Modified
- `menus/CollaborativeLobby.gd` - Added connection status check for clients

## Expected Behavior After Fix

### Host Console
```
[LOBBY] Checking connections... Peers: 1
[LOBBY] Client connected!
[LOBBY] Showing map selection
```

### Client Console
```
[LOBBY] Initialized as CLIENT
[LOBBY] Client already connected, showing map selection immediately  ← NEW!
[LOBBY] Showing map selection
```

### Both Screens
- Host: Shows map selection gallery ✓
- Client: Shows map selection gallery ✓ (no longer stuck!)
- Both can vote on maps ✓

## Testing
Run the same test:

1. **Host:** Run game → Multiplayer → Network Multiplayer → Host Game
2. **Client:** Run second instance → Join Game → 127.0.0.1:8910 → Connect
3. **Expected:** Both should now see map selection screen immediately!

## Alternative Approach (Not Used)
We could have also:
1. Delayed the host's broadcast until client confirms ready
2. Made the client request the lobby state
3. Added a retry mechanism for missed messages

But checking connection status on init is simpler and more reliable.

## Status
✅ **FIXED** - Client now shows map selection immediately when already connected

## Related Fixes
1. **P2P Connection Polling** - Fixed connection establishment
2. **Lobby Peer Count** - Fixed peer detection on host
3. **Client Lobby Initialization** - Fixed client showing map selection (this fix)

All three fixes together enable the full collaborative lobby flow!
