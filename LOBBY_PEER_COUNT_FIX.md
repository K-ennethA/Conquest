# Lobby Peer Count Fix

## Issue
After the P2P connection polling fix, clients could connect to the host successfully, but both host and client remained stuck in "Waiting for player" screen. The lobby never transitioned to map selection.

### Symptoms
```
[P2P_DIRECT] P2P peer connected: peer_id: 1094496368  ✓ Connection works!
[LOBBY] Checking connections... Peers: 0  ❌ But lobby sees 0 peers
[LOBBY] Checking connections... Peers: 0  ❌ Keeps checking forever
```

## Root Cause
The lobby was checking `network_stats.connected_peers` expecting an **Array**, but `NetworkManager.get_network_statistics()` returns it as an **integer** (peer count).

### The Bug
```gdscript
// In CollaborativeLobby.gd
var connected_peers = network_stats.get("connected_peers", [])  // Expects array

// But NetworkManager returns:
stats["connected_peers"] = get_connected_peers().size()  // Returns integer!

// So this check always failed:
if connected_peers is Array:  // False! It's an int!
    peer_count = connected_peers.size()  // Never executed
```

Result: `peer_count` was always 0, so the lobby never detected the connected client.

## Solution
Fixed the type checking to handle both integer and array:

```gdscript
var connected_peers = network_stats.get("connected_peers", 0)  // Default to 0

// Handle both types
var peer_count = 0
if connected_peers is int:
    peer_count = connected_peers  // Direct integer
elif connected_peers is Array:
    peer_count = connected_peers.size()  // Array size
```

Now the lobby correctly detects when a client connects!

## Files Modified
- `menus/CollaborativeLobby.gd` - Fixed peer count type checking

## Expected Behavior After Fix

### Host Console
```
[LOBBY] Monitoring for client connections...
[LOBBY] Checking connections... Peers: 0
[LOBBY] Checking connections... Peers: 0
[LOBBY] Checking connections... Peers: 1  ✓ Detects client!
[LOBBY] Client connected!
[LOBBY] Showing map selection
```

### Client Console
```
[CLIENT] Connection established successfully!
[LOBBY] Initialized as CLIENT
[LOBBY] Received lobby state: map_selection
[LOBBY] Showing map selection
```

### Both Screens
- Host: Transitions from "Waiting for opponent..." to map selection gallery
- Client: Transitions from "Waiting for host..." to map selection gallery
- Both can see and click on maps to vote

## Testing
Run the same test as before:

1. **Host:** Run game → Multiplayer → Network Multiplayer → Host Game
2. **Client:** Run second instance → Join Game → 127.0.0.1:8910 → Connect
3. **Expected:** Both should now see the map selection screen!

## Status
✅ **FIXED** - Lobby now correctly detects connected peers and transitions to map selection

## Related Fixes
1. **P2P Connection Polling** - Fixed connection establishment (see `P2P_CONNECTION_FIX_SUMMARY.md`)
2. **Lobby Peer Count** - Fixed peer detection (this fix)

Both fixes together enable the full collaborative lobby flow!
