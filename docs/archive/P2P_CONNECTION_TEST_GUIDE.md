# P2P Connection Test Guide

## Quick Test (Automated)

### Using the Test Script
The fastest way to verify the fix:

```bash
# Terminal 1 - Start Host
godot --path . test_p2p_connection_fix.gd

# Terminal 2 - Start Client (wait 2 seconds after host starts)
godot --path . test_p2p_connection_fix.gd --multiplayer-auto-join
```

**Expected Results:**
- Host terminal shows: `[HOST] ✓✓✓ CLIENT CONNECTED! ✓✓✓`
- Client terminal shows: `[CLIENT] ✓✓✓ CONNECTED TO HOST! ✓✓✓`
- Both show "TEST PASSED!"

**If Test Fails:**
- Check firewall settings (allow port 8910)
- Verify both instances are running
- Check for error messages in output

---

## Full Lobby Test (Manual)

### Step 1: Start Host Instance
1. Run Godot project (F5 or play button)
2. Navigate: Main Menu → Multiplayer → Network Multiplayer
3. Click "HOST GAME"
4. You should see: "Waiting for opponent..."
5. Note the address shown: `127.0.0.1:8910`

### Step 2: Start Client Instance
1. Open a **second** Godot editor window
2. Run the project (F5)
3. Navigate: Main Menu → Multiplayer → Network Multiplayer
4. Click "JOIN GAME"
5. Enter:
   - Address: `127.0.0.1`
   - Port: `8910`
   - Player Name: `Client Player`
6. Click "CONNECT"

### Step 3: Verify Connection
**Host should show:**
- "Client connected!" message
- Transition to map selection screen

**Client should show:**
- "Connected! Waiting for lobby..."
- Transition to map selection screen

### Step 4: Test Map Voting
1. Both players should see map gallery
2. Each player clicks a map to vote
3. Vote status updates showing both votes
4. Click "READY - START GAME" on both sides

### Step 5: Verify Game Start
- If both chose same map: Game starts with that map
- If different maps: Coin flip decides, game starts
- Both instances should load into GameWorld

---

## Troubleshooting

### "Connection timeout" on Client
**Possible causes:**
1. Host not started yet → Start host first
2. Wrong port → Verify host is on 8910
3. Firewall blocking → Allow Godot through firewall
4. Polling not working → Check P2PNetworkBackend has `_process()` method

**Debug steps:**
```bash
# Check if host is listening
netstat -an | findstr 8910

# Should show:
# UDP    0.0.0.0:8910    *:*
```

### "No client connected" on Host
**Possible causes:**
1. Client not connecting → Check client logs
2. Network issue → Test with automated script first
3. Polling not working → Verify `_process()` is being called

**Debug steps:**
- Add print statements in `P2PNetworkBackend._process()`
- Verify `_multiplayer_api.poll()` is being called
- Check `_multiplayer_api.has_multiplayer_peer()` returns true

### Both Connect but Lobby Doesn't Show
**Possible causes:**
1. Signal not connected → Check `connection_established` signal
2. Lobby initialization failed → Check CollaborativeLobby logs
3. UI not updating → Check `_show_map_selection()` is called

**Debug steps:**
- Look for `[LOBBY]` prefixed messages in console
- Verify `is_client_connected` becomes true on host
- Check `_check_for_connections()` loop is running

---

## Expected Console Output

### Host Console
```
[HOST] Starting network multiplayer host...
[HOST] NetworkManager: Starting host with P2P_DIRECT backend on port 8910
[HOST] Host started successfully
[LOBBY] Initialized as HOST
[LOBBY] Monitoring for client connections...
[LOBBY] Checking connections... Peers: 0
[LOBBY] Checking connections... Peers: 0
[LOBBY] Checking connections... Peers: 1
[LOBBY] Client connected!
[LOBBY] Showing map selection
```

### Client Console
```
[CLIENT] Joining network game at 127.0.0.1:8910 as Client Player
[CLIENT] NetworkManager: Joining host at 127.0.0.1:8910 with P2P_DIRECT backend
[CLIENT] Connection attempt started
[CLIENT] Connected to host! Local peer_id: 1234567890
[LOBBY] Initialized as CLIENT
[LOBBY] Received lobby state: map_selection
[LOBBY] Showing map selection
```

---

## Performance Checks

### Network Stats
After connection, check network statistics:

```gdscript
var network_manager = get_node("/root/NetworkManager")
var stats = network_manager.get_network_statistics()
print(stats)
```

Expected output:
```
{
  "mode": "P2P_DIRECT",
  "connected_peers": 1,
  "is_host": true,
  "connection_status": "CONNECTED",
  "average_connection_quality": 1.0
}
```

### Connection Quality
```gdscript
var quality = network_manager.get_p2p_connection_quality(peer_id)
print("Connection quality: %.2f" % quality)
```

Expected: `1.0` (excellent) for local connections

---

## Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| "NetworkManager not found" | Ensure NetworkManager is autoloaded in project settings |
| "Failed to create P2P host" | Port 8910 already in use, try different port |
| "Connection timeout" | Verify polling fix is applied, check firewall |
| "Lobby not showing" | Check CollaborativeLobby.gd is loaded correctly |
| "Maps not loading" | Verify MapSelectorPanel.tscn exists |
| "Game doesn't start" | Check GameWorld.tscn path is correct |

---

## Next Steps After Successful Test

1. ✅ Verify P2P connection works
2. ✅ Test map voting system
3. ✅ Test coin flip logic
4. ✅ Test game start synchronization
5. ✅ Run unit tests
6. ✅ Test with different maps
7. ✅ Test disconnect/reconnect scenarios

---

## Unit Tests

Run the comprehensive unit tests:

```bash
godot --path . tests/run_collaborative_lobby_tests.gd
```

Expected: All 39+ tests pass

---

## Questions to Ask

If the test fails, ask yourself:

1. **Is the host actually listening?**
   - Check console for "Host started successfully"
   - Verify port 8910 is open

2. **Is the client attempting connection?**
   - Check console for "Connection attempt started"
   - Verify address and port are correct

3. **Is polling happening?**
   - Add debug print in `_process()` method
   - Should print every frame

4. **Are signals connected?**
   - Check `_multiplayer_api.peer_connected.connect()`
   - Verify signal names are correct

5. **Is the MultiplayerAPI valid?**
   - Check `_multiplayer_api.has_multiplayer_peer()` returns true
   - Verify `_enet_peer` is assigned correctly
