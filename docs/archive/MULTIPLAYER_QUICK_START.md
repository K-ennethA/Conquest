# Multiplayer Quick Start Guide

## How to Test Multiplayer (2 Instances)

### Step 1: Start Host
```
1. Run the game
2. Main Menu → Versus → Network Multiplayer
3. Click "Host Game"
4. Wait in lobby (Start Game button will be disabled)
```

**Expected:**
- Console shows: `[HOST] Host started successfully on port 8910`
- Lobby displays: "Hosting on port 8910 - Waiting for players to join..."
- "Start Game" button is grayed out (need 2+ players)

### Step 2: Launch Client
```
1. Launch a SECOND instance of the game
2. Main Menu → Versus → Network Multiplayer
3. Click "Join Game"
4. Enter address: 127.0.0.1
5. Enter port: 8910
6. Enter name: Client Player
7. Click "Connect"
```

**Expected:**
- Console shows: `[CLIENT] Connection established successfully!`
- Status shows: "Connected! Waiting for host to start game..."
- Host's "Start Game" button becomes ENABLED

### Step 3: Start Game (Host Only)
```
1. On HOST instance, click "Start Game"
```

**Expected:**
- Host console: `[HOST] Broadcasting game start...`
- Client console: `[CLIENT] Received game_start message from host`
- Both instances load into GameWorld
- Both see the same 5x5 map with 3 warriors per player

### Step 4: Play!
```
- Host is Player 1 (ID: 0)
- Client is Player 2 (ID: 1)
- Take turns moving units and attacking
```

## Quick Troubleshooting

### "Failed to connect"
- **Check**: Is host running?
- **Check**: Correct port (8910)?
- **Check**: Firewall blocking?

### "Start Game button disabled"
- **Check**: Do you have 2+ players?
- **Expected**: This is correct! Need opponent to play.

### "Client doesn't load game"
- **Check**: Did host click "Start Game"?
- **Check**: Console shows `[CLIENT] Received game_start message`?
- **If not**: Check MULTIPLAYER_CLIENT_GAME_START_FIX.md

### "Connection timeout"
- **Wait**: Connection can take up to 5 seconds
- **Check**: Console for connection status updates
- **Retry**: Click "Connect" again if it fails

## Console Output Reference

### Successful Host:
```
[HOST] === START NETWORK MULTIPLAYER HOST ===
[HOST] Host started successfully on port 8910
[HOST] Share this address with other players: 127.0.0.1:8910
```

### Successful Client Connection:
```
[CLIENT] === JOIN NETWORK MULTIPLAYER START ===
[CLIENT] Connection status after 1.5s: connected
[CLIENT] Connection established successfully!
```

### Successful Game Start:
```
[HOST] Broadcasting game start with map: res://game/maps/resources/default_skirmish.tres
[CLIENT] Received game_start message from host
[CLIENT] Loading GameWorld...
```

## Key Features

✅ **Host requires 2+ players** - Can't start alone
✅ **P2P networking** - Direct connection between players
✅ **Automatic sync** - Client loads same map as host
✅ **5-second timeout** - Connection attempts with polling
✅ **Comprehensive logging** - Easy to debug issues

## File Locations

- **Host/Join UI**: `menus/NetworkMultiplayerSetup.gd`
- **Network Handler**: `systems/multiplayer/MultiplayerGameState.gd`
- **Game Manager**: `systems/game_core/GameModeManager.gd`
- **Default Map**: `game/maps/resources/default_skirmish.tres`

## Documentation

- **MULTIPLAYER_HOST_JOIN_FIX.md** - Detailed implementation
- **MULTIPLAYER_CLIENT_GAME_START_FIX.md** - Client-side sync
- **MULTIPLAYER_SESSION_COMPLETE_SUMMARY.md** - Full session summary
- **DEFAULT_MAP_SETUP_SUMMARY.md** - Map configuration

## Status: ✅ READY TO TEST

All core multiplayer functionality is implemented and ready for testing!
