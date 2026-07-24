# P2P Connection Polling Fix - Visual Diagram

## Before Fix (Connection Failed)

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST INSTANCE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  NetworkManager                                                  │
│    └─> P2PNetworkBackend                                        │
│          ├─> _multiplayer_api (custom instance)                 │
│          │     ├─> peer_connected signal ❌ (never fires)       │
│          │     └─> NO POLLING! ❌                                │
│          │                                                       │
│          └─> _enet_peer (ENetMultiplayerPeer)                   │
│                └─> Listening on port 8910 ✓                     │
│                    └─> Receives packets ✓                       │
│                        └─> But packets never processed! ❌       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              ↕ Network
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT INSTANCE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  NetworkManager                                                  │
│    └─> P2PNetworkBackend                                        │
│          ├─> _multiplayer_api (custom instance)                 │
│          │     ├─> connected_to_server signal ❌ (never fires)  │
│          │     └─> NO POLLING! ❌                                │
│          │                                                       │
│          └─> _enet_peer (ENetMultiplayerPeer)                   │
│                └─> Connecting to 127.0.0.1:8910 ✓               │
│                    └─> Sends packets ✓                          │
│                        └─> But packets never processed! ❌       │
│                                                                  │
│  Status: CONNECTING → TIMEOUT (10s) → FAILED ❌                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why It Failed
1. ❌ Custom MultiplayerAPI created but never polled
2. ❌ ENet peer receives/sends packets but they sit in buffer
3. ❌ No `_process()` method to call `_multiplayer_api.poll()`
4. ❌ Signals never fire because events never processed
5. ❌ Connection handshake never completes

---

## After Fix (Connection Succeeds)

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST INSTANCE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  NetworkManager                                                  │
│    └─> P2PNetworkBackend                                        │
│          ├─> _process(delta) ✓ NEW!                             │
│          │     └─> _multiplayer_api.poll() ✓ EVERY FRAME!       │
│          │                                                       │
│          ├─> _multiplayer_api (custom instance)                 │
│          │     ├─> Processes packets ✓                          │
│          │     ├─> peer_connected signal ✓ FIRES!               │
│          │     └─> connection_established(peer_id) ✓            │
│          │                                                       │
│          └─> _enet_peer (ENetMultiplayerPeer)                   │
│                └─> Listening on port 8910 ✓                     │
│                    └─> Receives packets ✓                       │
│                        └─> Packets processed! ✓                 │
│                                                                  │
│  Status: CONNECTED ✓                                            │
│  Connected Peers: [1234567890] ✓                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              ↕ Network
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT INSTANCE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  NetworkManager                                                  │
│    └─> P2PNetworkBackend                                        │
│          ├─> _process(delta) ✓ NEW!                             │
│          │     └─> _multiplayer_api.poll() ✓ EVERY FRAME!       │
│          │                                                       │
│          ├─> _multiplayer_api (custom instance)                 │
│          │     ├─> Processes packets ✓                          │
│          │     ├─> connected_to_server signal ✓ FIRES!          │
│          │     └─> connection_established(peer_id) ✓            │
│          │                                                       │
│          └─> _enet_peer (ENetMultiplayerPeer)                   │
│                └─> Connected to 127.0.0.1:8910 ✓                │
│                    └─> Sends packets ✓                          │
│                        └─> Packets processed! ✓                 │
│                                                                  │
│  Status: CONNECTED ✓                                            │
│  Local Peer ID: 1234567890 ✓                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why It Works Now
1. ✅ `_process()` method added to P2PNetworkBackend
2. ✅ `_multiplayer_api.poll()` called every frame
3. ✅ Network packets processed in real-time
4. ✅ Connection handshake completes
5. ✅ Signals fire correctly
6. ✅ Both instances can communicate

---

## The Fix (Code)

```gdscript
# systems/networking/P2PNetworkBackend.gd

func _process(_delta: float) -> void:
	"""Poll the multiplayer API to process network events"""
	if _multiplayer_api and _multiplayer_api.has_multiplayer_peer():
		_multiplayer_api.poll()
```

**That's it!** Just 4 lines of code to fix the connection issue.

---

## Connection Flow Timeline

### Before Fix
```
Time    Host                          Client
────────────────────────────────────────────────────────────
0.0s    create_server(8910) ✓         
0.5s    Listening... ✓                create_client() ✓
1.0s    [waiting]                     Connecting...
2.0s    [waiting]                     Connecting...
3.0s    [waiting]                     Connecting...
...
10.0s   [no peers]                    TIMEOUT ❌
```

### After Fix
```
Time    Host                          Client
────────────────────────────────────────────────────────────
0.0s    create_server(8910) ✓         
        poll() every frame ✓
0.5s    Listening... ✓                create_client() ✓
                                      poll() every frame ✓
0.6s    Receives SYN packet ✓         Sends SYN packet ✓
        Processes packet ✓            
        Sends SYN-ACK ✓               
0.7s    peer_connected fires ✓        Receives SYN-ACK ✓
        Peer added ✓                  Processes packet ✓
                                      connected_to_server fires ✓
0.8s    CONNECTED ✓                   CONNECTED ✓
        Peers: [1234567890]           Peer ID: 1234567890
```

---

## Key Concepts

### What is Polling?
Polling is the process of checking for and processing pending events. In networking:

```gdscript
# Without polling:
_enet_peer.send_packet(data)  # Packet sits in buffer
# ... nothing happens ...

# With polling:
_enet_peer.send_packet(data)  # Packet sits in buffer
_multiplayer_api.poll()        # Process buffer, send packet!
```

### Why Custom MultiplayerAPI?
Our architecture uses a custom MultiplayerAPI for:
- **Isolation**: Separate multiplayer state per backend
- **Control**: Fine-grained control over network events
- **Testing**: Easier to mock and test
- **Flexibility**: Can switch backends without affecting scene tree

But custom APIs require manual polling!

### Alternative: Scene Tree API
If we used the scene tree's default API:

```gdscript
# This is auto-polled by the engine
get_tree().get_multiplayer().multiplayer_peer = _enet_peer
```

But we'd lose isolation and control.

---

## Debugging Tips

### Add Debug Polling
```gdscript
var _poll_count: int = 0

func _process(_delta: float) -> void:
	if _multiplayer_api and _multiplayer_api.has_multiplayer_peer():
		_poll_count += 1
		if _poll_count % 60 == 0:  # Every second at 60 FPS
			print("[P2P] Polled %d times" % _poll_count)
		_multiplayer_api.poll()
```

### Check Peer State
```gdscript
func _process(_delta: float) -> void:
	if _multiplayer_api and _multiplayer_api.has_multiplayer_peer():
		var peer = _multiplayer_api.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			var state = peer.get_connection_status()
			print("[P2P] Peer state: " + str(state))
		_multiplayer_api.poll()
```

### Monitor Signals
```gdscript
func _on_peer_connected(peer_id: int) -> void:
	print("[P2P] ✓ peer_connected signal fired! peer_id: " + str(peer_id))
	# ... rest of handler ...

func _on_connected_to_server() -> void:
	print("[P2P] ✓ connected_to_server signal fired!")
	# ... rest of handler ...
```

---

## Summary

| Aspect | Before Fix | After Fix |
|--------|-----------|-----------|
| Polling | ❌ None | ✅ Every frame |
| Packets | ❌ Buffered, not processed | ✅ Processed immediately |
| Signals | ❌ Never fire | ✅ Fire correctly |
| Connection | ❌ Timeout | ✅ Succeeds |
| Time to connect | ❌ Never | ✅ ~0.2 seconds |

**The fix is simple but critical: Poll the MultiplayerAPI every frame!**
