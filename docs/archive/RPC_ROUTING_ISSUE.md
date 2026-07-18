# RPC Routing Issue - Messages Not Crossing Network

## Problem Identified
Each player is only receiving their OWN messages, not the opponent's messages.

### Evidence from Logs

**Host sends and receives its own message:**
```
[LOBBY] Extracted player_name: 'Host Player', local_player_name: 'Host Player'
[LOBBY] Ignoring own ready (player_name matches local_player_name)
```

**Client sends and receives its own message:**
```
[LOBBY] Extracted player_name: 'Player', local_player_name: 'Player'
[LOBBY] Ignoring own ready (player_name matches local_player_name)
```

**Network logs show messages from self:**
- Host: `[P2P_DIRECT] P2P message received: from peer 1` (host is peer 1)
- Client: `[P2P_DIRECT] P2P message received: from peer 1512580714` (client is peer 1512580714)

## Root Cause

The RPC system in P2PNetworkBackend is using `"call_local"` which correctly calls the method locally, but the messages aren't reaching the OTHER peer.

### Current RPC Setup
```gdscript
@rpc("any_peer", "call_local", "reliable")
func _receive_p2p_message(message: Dictionary) -> void:
    # This is called locally but NOT on remote peers!
```

### Why It's Failing

In Godot 4, RPC methods need to be on nodes in the scene tree with **consistent node paths** across all peers. The issue is:

1. Each instance creates its own NetworkManager
2. Each NetworkManager creates its own P2PNetworkBackend
3. The P2PNetworkBackend is added as a child: `add_child(_p2p_backend)`
4. But the RPC system can't find the corresponding node on the remote peer

The RPC call `.rpc(message)` is trying to call `_receive_p2p_message` on the remote peer's P2PNetworkBackend, but it can't find it because:
- The node paths might be different
- The RPC registration isn't working across peers
- The multiplayer authority isn't set correctly

## Solution Options

### Option 1: Use NetworkManager's Message System (Recommended)
Instead of using RPC directly in P2PNetworkBackend, use the existing message passing through NetworkManager which already handles this correctly.

The issue is that lobby actions are going through GameManager's action system, which then tries to use P2PNetworkBackend's RPC, but the RPC isn't working.

### Option 2: Fix RPC Registration
Ensure P2PNetworkBackend is properly registered in the scene tree with a consistent path and the RPC methods are properly set up.

### Option 3: Use Different RPC Approach
Instead of RPC on the backend, use RPC on a singleton or autoload that exists in both instances.

## Immediate Fix

The quickest fix is to check why the existing RPC isn't working. Let me check if the multiplayer peer is properly set on the scene tree's multiplayer API, not just the custom one.

Actually, looking at the code again, I see that P2PNetworkBackend creates a CUSTOM MultiplayerAPI:
```gdscript
_multiplayer_api = MultiplayerAPI.create_default_interface()
```

But RPC calls use the SCENE TREE's multiplayer API, not the custom one! That's why the messages aren't crossing the network - the RPC is using `get_tree().get_multiplayer()` but the peer is set on `_multiplayer_api` (the custom one).

## The Real Fix

The P2PNetworkBackend needs to either:
1. Set the peer on the scene tree's multiplayer API: `get_tree().get_multiplayer().multiplayer_peer = _enet_peer`
2. OR use the custom API for RPC calls (but this is complex)

The architecture uses a custom MultiplayerAPI for isolation, but RPC methods use the scene tree's API. These need to be aligned.

## Next Steps

1. Verify which multiplayer API the RPC system is using
2. Ensure the ENet peer is set on the correct API
3. Test if messages cross the network after the fix

This is a fundamental architecture issue that needs to be resolved for multiplayer to work.
