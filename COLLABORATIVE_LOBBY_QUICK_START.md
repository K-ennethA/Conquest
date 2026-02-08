# Collaborative Lobby - Quick Start Guide

## What's New

Both players now vote on maps using a visual gallery. If they disagree, a coin flip decides!

## How to Test (2 Instances)

### Step 1: Generate Map Previews
```
1. Open Godot Editor
2. File → Run
3. Select: game/maps/generate_map_previews.gd
4. Wait for completion
```

### Step 2: Start Host
```
1. Run game (Instance 1)
2. Main Menu → Versus → Network Multiplayer
3. Click "Host Game"
4. See: "Waiting for opponent..."
5. Note: Address shown is 127.0.0.1:8910
```

### Step 3: Join as Client
```
1. Launch second game instance (Instance 2)
2. Main Menu → Versus → Network Multiplayer
3. Click "Join Game"
4. Enter: 127.0.0.1:8910
5. Click "Connect"
6. See: "Connected to host"
```

### Step 4: Map Selection Appears
```
BOTH PLAYERS:
- Waiting screens disappear
- Map gallery appears
- See all maps with previews
- Can click any map to vote
```

### Step 5: Vote on Maps

**Option A: Both Choose Same Map**
```
1. BOTH: Click "Default Skirmish"
2. Status: "Both players chose: Default Skirmish ✓"
3. BOTH: Click "READY - START GAME"
4. Game starts with Default Skirmish
```

**Option B: Choose Different Maps**
```
1. HOST: Click "Default Skirmish"
2. CLIENT: Click "Large Plains"
3. Status: "You: [Your Map] | Opponent: [Their Map]"
4. Status: "Coin flip will decide!"
5. BOTH: Click "READY - START GAME"
6. See: "Coin flip chose: [Winner]!"
7. Wait 2 seconds
8. Game starts with winning map
```

## Visual Flow

```
HOST CLICKS "HOST GAME"
         ↓
   Waiting Screen
   "Waiting for opponent..."
         ↓
CLIENT CONNECTS
         ↓
   Map Selection Gallery
   (Both players see this)
         ↓
   Players Click Maps to Vote
         ↓
   ┌─────────────┬─────────────┐
   │ Same Vote   │ Different   │
   │             │ Votes       │
   ├─────────────┼─────────────┤
   │ Use that    │ Coin Flip   │
   │ map         │ Decides     │
   └─────────────┴─────────────┘
         ↓
   Both Click "READY"
         ↓
   Game Starts!
```

## Key Features

✅ **Visual Gallery**: See map previews before voting
✅ **Real-Time Sync**: See opponent's vote instantly
✅ **Fair Resolution**: Coin flip for disagreements
✅ **Clear Status**: Always know what's happening
✅ **No Host Advantage**: Both players equal

## Console Output

### Successful Flow:
```
[HOST] Starting network multiplayer host...
[HOST] Host started successfully
[LOBBY] Initialized as HOST
[LOBBY] Monitoring for client connections...
[LOBBY] Client connected!
[LOBBY] Showing map selection
[LOBBY] Local vote: Default Skirmish
[LOBBY] Opponent voted for: Large Plains
[LOBBY] Player ready, waiting for opponent...
[LOBBY] Opponent is ready!
[LOBBY] Finalizing map selection...
[LOBBY] Coin flip! Result: Large Plains
[LOBBY] Broadcasting game start with map: ...
[LOBBY] Starting game with map: ...
```

## Troubleshooting

### "No maps showing"
- Run generate_map_previews.gd first
- Check game/maps/resources/ has .tres files

### "Opponent vote not showing"
- Check network connection
- Verify both in map selection screen
- Check console for network errors

### "Coin flip not working"
- Verify both players clicked different maps
- Check both clicked "READY"
- Look for coin flip message in console

### "Game doesn't start"
- Ensure both players clicked "READY"
- Check console for errors
- Verify map file exists

## Files

**Main Files:**
- `menus/CollaborativeLobby.gd` - Lobby logic
- `menus/CollaborativeLobby.tscn` - Lobby scene
- `menus/NetworkMultiplayerSetup.gd` - Integration

**Documentation:**
- `COLLABORATIVE_LOBBY_IMPLEMENTATION.md` - Full details
- `COLLABORATIVE_LOBBY_QUICK_START.md` - This guide

## Status: ✅ READY TO TEST

Everything is implemented and ready:
- ✅ Waiting screens for both players
- ✅ Visual map gallery
- ✅ Vote synchronization
- ✅ Coin flip resolution
- ✅ Game start with chosen map

**Test it now with two game instances!**
