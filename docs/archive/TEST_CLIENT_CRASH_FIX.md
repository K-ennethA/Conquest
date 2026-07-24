# Test Guide: Client Crash Fix Verification

## Quick Test (2 Minutes)

### Setup
1. Open Godot editor (Host instance)
2. Open second Godot instance via command line (Client instance)

### Host Steps
1. Click "Multiplayer" → "Host Game"
2. Enter port (e.g., 7777)
3. Click "Host"
4. Select any map from gallery
5. Click "Ready"
6. Wait for client to join and vote
7. **Observe**: Game should start and load successfully

### Client Steps
1. Launch with: `godot --multiplayer-client --multiplayer-address=127.0.0.1 --multiplayer-port=7777`
2. Should auto-join lobby
3. Select any map from gallery
4. Click "Ready"
5. Wait for voting to complete
6. **CRITICAL**: Watch console for errors during game load

### Expected Results

#### ✅ Success Indicators
- Both host and client load into game world
- No "Invalid operands 'String' and 'int'" error in client console
- Client console shows:
  ```
  === GameWorld Initializing ===
  Loading selected map...
  Map loaded successfully: [Map Name]
  Network multiplayer mode detected
  Setting up multiplayer players...
  This client is Player 2 (ID: 1)
  Game started successfully!
  === GameWorld Initialization Complete ===
  ```
- Both players can see the game world
- UI initializes without errors

#### ❌ Failure Indicators
- Client crashes with "Invalid operands 'String' and 'int'" error
- Client console shows error during game load
- Client doesn't load into game world
- Black screen or frozen UI on client

## Detailed Test (5 Minutes)

### Additional Verification Steps

1. **Unit Selection Test**:
   - Client clicks on a unit
   - Should see unit info panel update
   - No console errors about player ownership

2. **Action Validation Test**:
   - Client tries to move a unit
   - Should either succeed (if their unit) or show rejection message
   - No crashes or String + int errors

3. **Turn System Test**:
   - Wait for turn to change
   - Client should see turn indicator update
   - No errors when turn changes

4. **End Turn Test**:
   - Client clicks "End Turn" button
   - Should either succeed (if their turn) or show rejection message
   - No crashes or type errors

## Console Monitoring

### What to Watch For

**Good Signs** ✅:
```
Local player ID: 1
Unit owner: Player 1
Unit owner ID: 0
Selection rejected: Unit belongs to Player 1, you are Player 2
```

**Bad Signs** ❌:
```
Invalid operands 'String' and 'int' in operator '+'
[CRASH]
```

## Debugging Failed Tests

If the test fails:

1. **Check Console Output**:
   - Look for the exact line number of the error
   - Check if it's in UnitActionsPanel.gd or another file

2. **Verify Fix Applied**:
   - Open `game/ui/UnitActionsPanel.gd`
   - Search for `local_player_id_raw`
   - Should see type conversion code in 5 locations

3. **Check Other Files**:
   - `game/maps/MapLoader.gd` - Should have `player_id_raw` conversion
   - `game/world/GameWorldManager.gd` - Should have `local_player_id_int` conversion
   - `systems/networking/P2PNetworkBackend.gd` - Should have `sender_id_int` conversion

4. **Run Diagnostics**:
   ```
   getDiagnostics on all modified files
   Should show: "No diagnostics found"
   ```

## Quick Command Reference

### Launch Host (Editor)
Just run normally from Godot editor

### Launch Client (Command Line)
```bash
# Windows
godot.exe --multiplayer-client --multiplayer-address=127.0.0.1 --multiplayer-port=7777

# Linux/Mac
godot --multiplayer-client --multiplayer-address=127.0.0.1 --multiplayer-port=7777
```

### Alternative: Launch Both from Command Line
```bash
# Terminal 1 (Host)
godot.exe

# Terminal 2 (Client)
godot.exe --multiplayer-client --multiplayer-address=127.0.0.1 --multiplayer-port=7777
```

## Success Criteria

The fix is successful if:
1. ✅ Client loads into game without crashes
2. ✅ No "Invalid operands 'String' and 'int'" errors
3. ✅ Client can interact with UI
4. ✅ Both players can see game world
5. ✅ Turn system works for both players

## Regression Testing

Also verify these still work:
- ✅ Lobby voting system
- ✅ Map selection gallery
- ✅ Player name display
- ✅ Turn queue display
- ✅ Unit info panel
- ✅ Action buttons

## Performance Check

Monitor for:
- No memory leaks
- Smooth frame rate on both instances
- No network lag or disconnections
- Proper cleanup when returning to menu

## Next Steps After Successful Test

1. Mark task as complete
2. Update project documentation
3. Consider adding unit tests for type conversion
4. Review other files for similar issues
5. Add type safety checks to code review checklist
