# Multiplayer RPC Null Instance Fix Summary

## Issue Fixed
**Error**: "Attempt to call function 'rpc' in base 'Callable' on a null instance."

## Root Cause
The networking backend classes were extending `RefCounted` instead of `Node`, which meant:
1. They couldn't be added to the scene tree
2. RPC methods require nodes to be part of the scene tree to work properly
3. The `_receive_network_message.rpc()` and `_receive_p2p_message.rpc()` calls were failing

## Changes Made

### 1. Changed NetworkBackend Base Class
**File**: `systems/networking/NetworkBackend.gd`
- **Before**: `extends RefCounted`
- **After**: `extends Node`
- **Reason**: RPC methods only work on Node objects that are part of the scene tree

### 2. Added Backends to Scene Tree
**File**: `systems/networking/NetworkManager.gd`
- **initialize_backends()**: Now adds each backend as a child node
- Added proper naming for debugging: "LocalNetworkBackend", "P2PNetworkBackend", "DedicatedServerBackend"
- Added debug logging to confirm scene tree addition

### 3. Added Null Checks for RPC Calls
**File**: `systems/networking/LocalNetworkBackend.gd`
- **_send_to_all_peers()**: Added null checks for `_multiplayer_api` and `_multiplayer_api.multiplayer_peer`
- **_send_to_peer()**: Added null checks before making RPC calls
- **_receive_network_message()**: Added null check for `_multiplayer_api`

**File**: `systems/networking/P2PNetworkBackend.gd`
- **_send_to_all_peers()**: Added null checks for `_multiplayer_api` and `_multiplayer_api.multiplayer_peer`
- **_send_to_peer()**: Added null checks before making RPC calls
- **_receive_p2p_message()**: Added null check for `_multiplayer_api`

## How It Works Now

### Scene Tree Structure:
```
NetworkManager (Node)
├── LocalNetworkBackend (Node)
├── P2PNetworkBackend (Node)
└── DedicatedServerBackend (Node)
```

### RPC Call Flow:
1. **Message Send**: `send_message()` called on NetworkManager
2. **Backend Routing**: Message routed to current backend (LocalNetworkBackend for development)
3. **RPC Validation**: Backend checks if multiplayer API is ready
4. **RPC Call**: `_receive_network_message.rpc(message)` called on scene tree node
5. **Message Receive**: RPC method receives message and emits signal

### Error Prevention:
- **Null Checks**: All RPC calls now check if multiplayer API is ready
- **Scene Tree**: All backends are proper Node objects in the scene tree
- **Graceful Failure**: Failed RPC calls log errors instead of crashing

## Expected Behavior Now
- **No More RPC Errors**: The "null instance" error should be resolved
- **Proper Networking**: Messages should be sent and received correctly
- **Better Debugging**: Clear logging shows when RPC calls fail and why
- **Stable Multiplayer**: The multiplayer system should work without crashes

## Debug Information Added
- "LocalNetworkBackend created and added to scene tree"
- "Send failed: multiplayer API not ready" (when RPC would fail)
- "Receive failed: multiplayer API not available" (when receive fails)

The multiplayer system should now work properly without RPC-related crashes!