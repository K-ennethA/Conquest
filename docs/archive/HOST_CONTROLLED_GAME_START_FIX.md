# Host-Controlled Game Start Fix

## Problem
```
Cannot call method 'get_children' on a null value.
```

**Root Cause**: Both host and client were calling `_start_game()` and changing scenes independently. This caused race conditions where one player would change scenes before the other was ready, leading to null reference errors.

## Issue Analysis
The previous implementation had both players independently deciding when to start the game:
1. Host clicks ready → calls `_finalize_map_selection()` → calls `_start_game()`
2. Client clicks ready → calls `_finalize_map_selection()` → calls `_start_game()`
3. Both try to change scenes at different times
4. Scene loading fails because network state isn't synchronized

## Solution: Host-Controlled Game Start

Only the **host** should finalize the map selection and broadcast the game start command. The **client** waits for the host's `game_start` message before starting.

### Changes Made

#### File: `menus/CollaborativeLobby.gd`

**1. Modified `_finalize_map_selection()` - Host Only**

```gdscript
func _finalize_map_selection() -> void:
    """Finalize map selection and start game (HOST ONLY)"""
    print("[LOBBY] Finalizing map selection...")
    
    # Only host should finalize
    if not is_host:
        print("[LOBBY] Client waiting for host to finalize...")
        return  // CLIENT EXITS HERE
    
    // ... host performs coin flip ...
    
    # Host broadcasts final map to client
    _broadcast_game_start(final_map)
    
    # Small delay to ensure message is sent before scene change
    await get_tree().create_timer(0.5).timeout
    
    # Host starts game
    _start_game(final_map)
```

**Key Changes:**
- Added early return for client (client does NOT start game here)
- Host broadcasts game start message
- Added 0.5s delay to ensure message is sent before scene change
- Only host calls `_start_game()`

**2. Added `_handle_game_start()` - Client Handler**

```gdscript
func _handle_game_start(data: Dictionary) -> void:
    """Handle game start message from host (CLIENT ONLY)"""
    print("[LOBBY] _handle_game_start called with data: " + str(data))
    
    if is_host:
        print("[LOBBY] Host ignoring own game_start message")
        return
    
    var map_path = data.get("map", "")
    var turn_system = data.get("turn_system", "")
    
    // ... update settings ...
    
    # Small delay for UI feedback
    await get_tree().create_timer(1.0).timeout
    
    # Client starts game with host's chosen map
    _start_game(map_path)
```

**Key Features:**
- Only client processes this message (host ignores it)
- Extracts map path and turn system from host's message
- Updates GameSettings with host's choices
- Shows UI feedback before starting
- Calls `_start_game()` with host's chosen map

**3. Updated Message Router**

```gdscript
match message_type:
    "lobby_state":
        _handle_lobby_state(data)
    "map_vote":
        _handle_map_vote(data)
    "player_ready":
        _handle_player_ready(data)
    "game_start":  // ADDED
        _handle_game_start(data)
    _:
        print("[LOBBY] Unknown message type: " + message_type)
```

## Flow Diagram

### Before Fix (BROKEN):
```
Host clicks ready → _finalize_map_selection() → _start_game() → Scene change
Client clicks ready → _finalize_map_selection() → _start_game() → Scene change
❌ Race condition! Both change scenes independently
```

### After Fix (WORKING):
```
Host clicks ready → _finalize_map_selection() → broadcast "game_start" → wait 0.5s → _start_game()
                                                        ↓
Client clicks ready → _finalize_map_selection() → RETURN (wait for host)
                                                        ↓
                                            Client receives "game_start" message
                                                        ↓
                                            _handle_game_start() → wait 1.0s → _start_game()
✅ Synchronized! Host starts first, client follows
```

## Expected Behavior

### Host Console:
```
[LOBBY] Opponent is ready!
[LOBBY] We're also ready! Finalizing map selection...
[LOBBY] Finalizing map selection...
[LOBBY] Both players chose same map: res://game/maps/DefaultMap.tres
[LOBBY] Broadcasting game start with map: res://game/maps/DefaultMap.tres
[LOBBY] Starting game with map: res://game/maps/DefaultMap.tres
```

### Client Console:
```
[LOBBY] Opponent is ready!
[LOBBY] We're also ready! Finalizing map selection...
[LOBBY] Finalizing map selection...
[LOBBY] Client waiting for host to finalize...
[LOBBY] _handle_game_start called with data: {...}
[LOBBY] Client received game start command
[LOBBY]   Map: res://game/maps/DefaultMap.tres
[LOBBY]   Turn System: traditional
[LOBBY] Starting game with map: res://game/maps/DefaultMap.tres
```

## Benefits

1. **Synchronized Start**: Both players start at nearly the same time
2. **Host Authority**: Host makes final decisions (coin flip, timing)
3. **No Race Conditions**: Client waits for host's signal
4. **Consistent State**: Both players load the same map with same settings
5. **Network Delay Handling**: Built-in delays ensure messages are sent/received

## Testing

1. Launch host → Click "Host Game"
2. Launch client → Click "Join Game"
3. Both select maps and click ready
4. **Verify**: Host starts game first, client follows ~1 second later
5. **Verify**: Both load into the same game scene without errors
6. **Verify**: No "Cannot call method on null value" errors

## Files Modified

- `menus/CollaborativeLobby.gd` - Host-controlled game start logic

## Verification

All files compile without errors (verified with getDiagnostics).
