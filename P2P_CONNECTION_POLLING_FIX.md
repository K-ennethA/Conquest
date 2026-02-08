# P2P Connection Polling Fix

## Problem
Client could not connect to host in P2P multiplayer mode. The connection would timeout after 10 seconds with the client stuck in "CONNECTING" state.

### Symptoms
- Host starts successfully on port 8910
- Client creates ENet peer successfully
- Client never receives `connected_to_server` signal
- Host never receives `peer_connected` signal
- Connection times out after 10 seconds

### Root Cause
The `P2PNetworkBackend` creates a custom `MultiplayerAPI` instance but **never polls it**. In Godot 4, the MultiplayerAPI needs to be polled every frame to process network events.

```gdscript
# In _init():
_multiplayer_api = MultiplayerAPI.create_default_interface()
_enet_peer = ENetMultiplayerPeer.new()

# Signals connected to custom API
_multiplayer_api.peer_connected.connect(_on_peer_connected)
_multiplayer_api.connected_to_server.connect(_on_connected_to_server)
```

The problem: **No `_process()` method to call `_multiplayer_api.poll()`**

Without polling, the MultiplayerAPI never processes incoming network packets, so:
- ENet peer receives packets but they're never processed
- Signals never fire
- Connection appears to hang

## Solution
Added a `_process()` method to poll the MultiplayerAPI every frame:

```gdscript
func _process(_delta: float) -> void:
	"""Poll the multiplayer API to process network events"""
	if _multiplayer_api and _multiplayer_api.has_multiplayer_peer():
		_multiplayer_api.poll()
```

This ensures:
1. Network packets are processed every frame
2. Connection handshakes complete
3. Signals fire correctly
4. Both host and client can communicate

## Testing
Run the test script to verify the fix:

```bash
# Terminal 1 (Host)
godot --path . test_p2p_connection_fix.gd

# Terminal 2 (Client)
godot --path . test_p2p_connection_fix.gd --multiplayer-auto-join
```

Expected output:
- Host: "✓✓✓ CLIENT CONNECTED! ✓✓✓"
- Client: "✓✓✓ CONNECTED TO HOST! ✓✓✓"

## Technical Details

### Why Polling is Needed
In Godot 4, `MultiplayerAPI` is responsible for:
- Processing incoming network packets
- Dispatching RPC calls
- Emitting connection signals
- Managing peer state

When you create a custom MultiplayerAPI (not using the scene tree's default), you must manually poll it:

```gdscript
# Option 1: Poll in _process()
func _process(_delta):
    _multiplayer_api.poll()

# Option 2: Poll in _physics_process()
func _physics_process(_delta):
    _multiplayer_api.poll()
```

### Alternative Approach
Instead of a custom MultiplayerAPI, you could use the scene tree's default:

```gdscript
# Use scene tree's multiplayer API (auto-polled)
get_tree().get_multiplayer().multiplayer_peer = _enet_peer
```

However, our architecture uses a custom API for better control and isolation.

## Files Modified
- `systems/networking/P2PNetworkBackend.gd` - Added `_process()` method

## Files Created
- `test_p2p_connection_fix.gd` - Test script to verify the fix
- `P2P_CONNECTION_POLLING_FIX.md` - This documentation

## Next Steps
1. Run the test script to verify the fix works
2. Test the full collaborative lobby flow
3. Verify map voting and game start work correctly
4. Run unit tests to ensure no regressions

## References
- Godot 4 MultiplayerAPI documentation: https://docs.godotengine.org/en/stable/classes/class_multiplayerapi.html
- ENetMultiplayerPeer documentation: https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html
