# Multiplayer Two Instance Testing Guide

## The Problem

You cannot test multiplayer by clicking "Host" and "Join" in the **same game instance**. Multiplayer requires **two separate running instances** of the game.

## Solution: Launch Two Instances

### Method 1: Manual Launch (Recommended for Testing)

#### Instance 1 (Host):
```
1. Run the game normally from Godot Editor (F5)
2. Main Menu → Versus → Network Multiplayer
3. Click "Host Game"
4. Wait in lobby (you'll see "Waiting for opponent...")
```

#### Instance 2 (Client):
```
1. While first instance is running, launch ANOTHER instance:
   - Windows: Run the .exe from the export folder
   - OR: Open a second Godot Editor and run the project
   - OR: Use command line: godot --path "path/to/project"

2. In the second instance:
   - Main Menu → Versus → Network Multiplayer
   - Click "Join Game"
   - Enter: 127.0.0.1:8910
   - Click "Connect"
```

#### Result:
```
- Host lobby will detect client connection
- Both will see map selection gallery
- Both can vote on maps
- Click "Ready" to start
```

### Method 2: Export and Run

```
1. Export the game (Project → Export)
2. Run the exported .exe (Instance 1 - Host)
3. Run the exported .exe again (Instance 2 - Client)
4. Follow the host/join steps above
```

### Method 3: Command Line

```bash
# Terminal 1 (Host)
godot --path "path/to/project" res://menus/MainMenu.tscn

# Terminal 2 (Client) - after host is running
godot --path "path/to/project" res://menus/MainMenu.tscn
```

## Why Same Instance Doesn't Work

```
Same Instance:
┌─────────────────┐
│   Game.exe      │
│  ┌──────────┐   │  ← Host and Client in same process
│  │   Host   │   │  ← Cannot connect to itself
│  └──────────┘   │  ← Network stack sees same process
│  ┌──────────┐   │
│  │  Client  │   │
│  └──────────┘   │
└─────────────────┘
     ❌ FAILS

Two Instances:
┌─────────────┐      ┌─────────────┐
│  Game.exe   │      │  Game.exe   │
│  ┌───────┐  │      │  ┌───────┐  │
│  │ Host  │  │◄────►│  │Client │  │
│  └───────┘  │      │  └───────┘  │
└─────────────┘      └─────────────┘
     ✅ WORKS
```

## Current Log Analysis

From your log:
```
[HOST] Host started successfully on port 8910
[CLIENT] Attempting to join host at 127.0.0.1:8910
[CLIENT] Connection status after 5.0s: connecting
[CLIENT] ERROR: Connection not established after 5.0s
```

**Problem**: Both host and client are in the SAME instance, so they can't actually connect over the network.

## Quick Test Steps

### Step 1: Start Host
```
1. Run game from Godot (F5)
2. Navigate: Main Menu → Versus → Network Multiplayer
3. Click "Host Game"
4. See: "Waiting for opponent..."
5. LEAVE THIS RUNNING
```

### Step 2: Start Client (New Instance)
```
1. WITHOUT closing the first instance
2. Run the exported game .exe
   OR open another Godot Editor window
3. Navigate: Main Menu → Versus → Network Multiplayer
4. Click "Join Game"
5. Enter: 127.0.0.1
6. Port: 8910
7. Click "Connect"
```

### Step 3: Verify Connection
```
Host Instance:
- Should show: "Client connected!"
- Map selection appears

Client Instance:
- Should show: "Connected to host"
- Map selection appears
```

### Step 4: Play
```
Both Instances:
- Click a map to vote
- Click "READY - START GAME"
- Game starts with chosen/coin-flipped map
```

## Troubleshooting

### "I don't have an exported .exe"
**Solution**: Export the game first
```
1. Project → Export
2. Add Windows Desktop preset (if not exists)
3. Export Project
4. Run the .exe
```

### "Can I test without exporting?"
**Yes**, but it's more complex:
```
Option A: Open two Godot Editor windows
- Window 1: Your main project
- Window 2: Copy project to different folder, open it

Option B: Use command line
- Terminal 1: godot --path "." res://menus/MainMenu.tscn
- Terminal 2: godot --path "." res://menus/MainMenu.tscn
```

### "Connection still times out"
**Check**:
1. Firewall isn't blocking port 8910
2. Both instances are actually separate processes
3. Host is fully started before client connects
4. Using correct address (127.0.0.1 for same machine)

### "Host doesn't detect client"
**Check**:
1. Client actually connected (check client console)
2. Host is checking for connections (see "[LOBBY] Checking connections...")
3. Network mode is "p2p" not "local"

## Expected Console Output

### Host Console:
```
[HOST] Host started successfully on port 8910
[LOBBY] Monitoring for client connections...
[LOBBY] Checking connections... Peers: 0
[LOBBY] Checking connections... Peers: 0
[LOBBY] Checking connections... Peers: 1  ← Client connected!
[LOBBY] Client connected!
[LOBBY] Showing map selection
```

### Client Console:
```
[CLIENT] Attempting to join host at 127.0.0.1:8910
[CLIENT] Connection status after 1.5s: connected  ← Success!
[CLIENT] Connection established successfully!
[CLIENT] Received lobby state: map_selection
[LOBBY] Showing map selection
```

## Summary

**❌ Don't**: Try to host and join in the same game instance
**✅ Do**: Launch two separate instances of the game

The multiplayer system is working correctly - it just needs two actual separate processes to connect to each other!
