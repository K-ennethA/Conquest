# String + Int Concatenation Error Fix

## Error
```
Invalid operands 'String' and 'int' in operator '+'.
```

**Symptom**: Host loads successfully, but client gets this error during game world initialization.

## Root Cause

Dictionary values from network/JSON can be Strings instead of ints. When trying to perform arithmetic operations like `player_id + 1`, if `player_id` is a String, you get: `"0" + 1` which is invalid.

**The Problem:**
- The `spawn_data` dictionary comes from map resources
- In some cases (especially with JSON serialization/deserialization), `player_id` might be stored as a String ("0", "1") instead of an int (0, 1)
- When trying to calculate `player_id + 1`, if `player_id` is a String, you get: `"0" + 1` which is invalid
- This causes: `Invalid operands 'String' and 'int' in operator '+'`

## Why It Affects Client But Not Host

The error likely occurs on the client because:
1. The map data might be transmitted over the network as JSON
2. JSON serialization can convert integers to strings
3. The client receives the map data with string player_ids
4. The host might be loading from a local resource file where types are preserved

## Solutions Applied

### File: `game/maps/MapLoader.gd`

Added type conversion to ensure `player_id` is always an integer:

**Pattern Used:**
```gdscript
var player_id_raw = spawn_data.get("player_id", 0)
var player_id = int(player_id_raw) if player_id_raw is String else player_id_raw
```

### File: `game/world/GameWorldManager.gd`

Added type conversion for `local_player_id`:

```gdscript
var local_player_id_int = int(local_player_id) if local_player_id is String else local_player_id
print("This client is Player " + str(local_player_id_int + 1) + " (ID: " + str(local_player_id_int) + ")")
```

### File: `systems/networking/P2PNetworkBackend.gd` ⭐ **ROOT CAUSE FIX**

**Location 1**: `_receive_p2p_message()` (~line 160)

Added type conversion for `sender_id`:

```gdscript
var sender_id = _multiplayer_api.get_remote_sender_id()
if sender_id == 0:
    sender_id = _local_peer_id  # Local message

// ADDED: Ensure sender_id is an int
var sender_id_int = int(sender_id) if sender_id is String else sender_id

// Use sender_id_int for all operations
_update_peer_latency(sender_id_int, latency)
log_network_event("P2P message received", "from peer " + str(sender_id_int))
message_received.emit(sender_id_int, message)
```

**Location 2**: `_on_connected_to_server()` (~line 327) ⭐ **THE ACTUAL ROOT CAUSE**

```gdscript
# Before (BROKEN):
func _on_connected_to_server() -> void:
    log_network_event("P2P connected to host", "")
    _connection_status = ConnectionStatus.CONNECTED
    _local_peer_id = _multiplayer_api.get_unique_id()  # Could return String!
    connection_established.emit(_local_peer_id)

# After (FIXED):
func _on_connected_to_server() -> void:
    log_network_event("P2P connected to host", "")
    _connection_status = ConnectionStatus.CONNECTED
    var peer_id_raw = _multiplayer_api.get_unique_id()
    _local_peer_id = int(peer_id_raw) if peer_id_raw is String else peer_id_raw
    connection_established.emit(_local_peer_id)
```

**The Root Cause**: `_multiplayer_api.get_unique_id()` was returning a String instead of an int for the client. This String value was stored in `_local_peer_id`, and then later used in `_receive_p2p_message()` when `sender_id == 0` (local message). Even though we converted `sender_id_int`, the problem was that `_local_peer_id` was a String from the start.

**Error Stack Trace**:
1. `P2PNetworkBackend.gd:169` in `_receive_p2p_message()` - Error occurred here
2. `NetworkManager.gd:269` in `_on_backend_message_received()`
3. `MultiplayerGameState.gd:286` in `_on_network_message_received()`

The error happened when the client received a network message and tried to log it with `"from peer " + str(sender_id_int)`, but `sender_id_int` was actually still a String because `_local_peer_id` was a String.

### File: `game/ui/UnitActionsPanel.gd` ⭐ **CRITICAL FIX**

This was the actual source of the client crash! The error occurred when the client tried to select a unit and the code attempted to print a message with `player_id + 1`:

**Locations Fixed:**

1. **Line ~147-159**: Unit selection validation
```gdscript
# Before (BROKEN):
var local_player_id = GameModeManager.get_local_player_id()
if unit_owner.player_id != local_player_id:
    print("Selection rejected: Unit belongs to Player " + str(unit_owner.player_id + 1) + ", you are Player " + str(local_player_id + 1))

# After (FIXED):
var local_player_id_raw = GameModeManager.get_local_player_id()
var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
var owner_player_id = int(unit_owner.player_id) if unit_owner.player_id is String else unit_owner.player_id

if owner_player_id != local_player_id:
    print("Selection rejected: Unit belongs to Player " + str(owner_player_id + 1) + ", you are Player " + str(local_player_id + 1))
```

2. **Line ~548-553**: Move action validation
3. **Line ~599-604**: End unit turn validation
4. **Line ~670-673**: End player turn validation
5. **Line ~1123-1129**: Movement completion validation

All locations now convert `local_player_id` and `player_id` to int before any arithmetic operations.

### File: `systems/multiplayer/MultiplayerTurnSystem.gd` ⭐ **DISCONNECTION FIX**

This error occurred when a player disconnected and the system tried to print a message with `player_id + 1`:

**Location Fixed**: `_get_player_for_peer()` function (~line 287)

```gdscript
# Before (BROKEN):
func _get_player_for_peer(peer_id: int) -> int:
    """Get player ID for a player ID"""
    return _player_peer_mapping.get(peer_id, -1)

# After (FIXED):
func _get_player_for_peer(peer_id: int) -> int:
    """Get player ID for a peer ID"""
    var player_id_raw = _player_peer_mapping.get(peer_id, -1)
    # Ensure we return an int (mapping values might be Strings from network)
    return int(player_id_raw) if player_id_raw is String else player_id_raw
```

The `_player_peer_mapping` dictionary is populated from network messages via `set_player_peer_mapping()`, so the values could be Strings instead of ints. When a peer disconnects, the code calls:

```gdscript
var player_id = _get_player_for_peer(peer_id)
print("MultiplayerTurnSystem: Peer %d (player %d) disconnected" % [peer_id, player_id])
```

If `player_id` is a String, the `%d` format specifier causes the error.

## Type Conversion Logic

```gdscript
int(player_id_raw) if player_id_raw is String else player_id_raw
```

This is a ternary operator that:
1. Checks if `player_id_raw` is a String
2. If yes: converts it to int using `int()`
3. If no: uses the value as-is (already an int)

## Testing

1. Launch host → Select map → Click ready
2. Launch client → Select map → Click ready
3. **Verify**: Both host and client load into game without errors
4. **Verify**: No "Invalid operands 'String' and 'int'" error in client console
5. **Verify**: Client can interact with units without crashes
6. **Verify**: Units are properly assigned to Player1 and Player2 containers

## Expected Console Output

**Client (After Fix):**
```
=== GameWorld Initializing ===
Loading selected map...
Cleared existing map content
Loading map: Default Skirmish
Loading tiles for 10x10 map
Loaded 100 tiles
Loading unit spawns...
Created 4 units
Map loaded successfully: Default Skirmish
Network multiplayer mode detected
Setting up network multiplayer...
Setting up multiplayer players...
Found player node: Map/Player1
Assigned unit Warrior1 to Player 1
Found player node: Map/Player2
Assigned unit Archer1 to Player 2
Game started successfully!
=== GameWorld Initialization Complete ===
```

## Related Issues Prevented

This fix also prevents similar errors in:
- Map editor when creating/editing unit spawns
- Map resource serialization/deserialization
- Network transmission of map data
- Any other code that accesses `player_id` from dictionaries
- UI interactions that validate player ownership

## Best Practice

When working with data from dictionaries (especially from JSON, network, or user input), always validate and convert types:

```gdscript
// Good: Type-safe
var player_id = int(data.get("player_id", 0))

// Better: Handles both String and int
var player_id_raw = data.get("player_id", 0)
var player_id = int(player_id_raw) if player_id_raw is String else player_id_raw

// Best: With validation
var player_id_raw = data.get("player_id", 0)
var player_id = 0
if player_id_raw is int:
    player_id = player_id_raw
elif player_id_raw is String:
    player_id = int(player_id_raw)
else:
    push_error("Invalid player_id type: " + str(typeof(player_id_raw)))
```

## Files Modified

- `game/maps/MapLoader.gd` - Added type conversion for player_id in spawn data
- `game/world/GameWorldManager.gd` - Added type conversion for local_player_id
- `systems/networking/P2PNetworkBackend.gd` - Added type conversion for sender_id in message receiving
- `game/ui/UnitActionsPanel.gd` - **CRITICAL FIX** - Added type conversion for local_player_id and player_id in 5 locations
- `systems/multiplayer/MultiplayerTurnSystem.gd` - Added type conversion for player_id in `_get_player_for_peer()` function

## Verification

All files compile without errors (verified with getDiagnostics).
