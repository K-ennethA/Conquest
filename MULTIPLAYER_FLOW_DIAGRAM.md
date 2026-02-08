# Multiplayer Host/Join Flow Diagram

## Current Implementation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST FLOW                                │
└─────────────────────────────────────────────────────────────────┘

1. Click "Host Game"
         ↓
2. GameModeManager.start_network_multiplayer_host("p2p")
         ↓
3. MultiplayerNetworkHandler.initialize()
         ↓
4. NetworkManager.set_network_mode(P2P_DIRECT)
         ↓
5. P2PNetworkBackend.start_host(8910)
         ↓
6. ENetMultiplayerPeer.create_server(8910)
         ↓
7. Lobby Opens
         ↓
8. "Start Game" button = DISABLED (only 1 player)
         ↓
9. Wait for client connection...
         ↓
10. Client connects → "Start Game" = ENABLED ✅
         ↓
11. Host clicks "Start Game"
         ↓
12. Broadcast "game_start" message ✅
         ↓
13. Load GameWorld ✅


┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT FLOW                               │
└─────────────────────────────────────────────────────────────────┘

1. Click "Join Game"
         ↓
2. Enter address (127.0.0.1) and port (8910)
         ↓
3. Click "Connect"
         ↓
4. GameModeManager.join_network_multiplayer("p2p")
         ↓
5. MultiplayerNetworkHandler.initialize()
         ↓
6. NetworkManager.set_network_mode(P2P_DIRECT)
         ↓
7. P2PNetworkBackend.join_host("127.0.0.1", 8910)
         ↓
8. ENetMultiplayerPeer.create_client()
         ↓
9. Connection polling (every 0.5s, max 5s)
         ↓
10. Connection established ✅
         ↓
11. Show "Waiting for host to start game..." ✅
         ↓
12. Wait for "game_start" message...
         ↓
13. Receive "game_start" message ⏳ TODO
         ↓
14. Load GameWorld ⏳ TODO
```

## Network Message Flow

```
┌──────────┐                                    ┌──────────┐
│   HOST   │                                    │  CLIENT  │
└────┬─────┘                                    └────┬─────┘
     │                                               │
     │  1. Start hosting on port 8910               │
     │  ────────────────────────────────────>       │
     │                                               │
     │                                               │  2. Connect to 127.0.0.1:8910
     │  <────────────────────────────────────       │
     │                                               │
     │  3. Connection established                   │
     │  ────────────────────────────────────>       │
     │     (peer_connected signal)                  │
     │                                               │
     │                                               │  4. Connection confirmed
     │  <────────────────────────────────────       │
     │     (connected_to_server signal)             │
     │                                               │
     │  5. Host clicks "Start Game"                 │
     │                                               │
     │  6. Broadcast "game_start" message           │
     │  ────────────────────────────────────>       │
     │     {                                         │
     │       type: "game_action",                   │
     │       action_type: "game_start",             │
     │       action_data: {                         │
     │         map: "...",                          │
     │         turn_system: ...                     │
     │       }                                       │
     │     }                                         │
     │                                               │
     │  7. Load GameWorld                           │  8. Receive message ⏳
     │                                               │  9. Load GameWorld ⏳
     │                                               │
```

## Lobby State Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         LOBBY STATES                             │
└─────────────────────────────────────────────────────────────────┘

HOST:
┌──────────────┐
│   WAITING    │  ← Initial state after hosting
│ (1 player)   │  ← "Start Game" = DISABLED
└──────┬───────┘
       │
       │ Client connects
       ↓
┌──────────────┐
│    READY     │  ← 2+ players connected
│ (2+ players) │  ← "Start Game" = ENABLED
└──────┬───────┘
       │
       │ Host clicks "Start Game"
       ↓
┌──────────────┐
│   STARTING   │  ← Broadcasting game start
│              │  ← Loading GameWorld
└──────────────┘


CLIENT:
┌──────────────┐
│ CONNECTING   │  ← Attempting to join host
│              │  ← Polling connection status
└──────┬───────┘
       │
       │ Connection established
       ↓
┌──────────────┐
│   WAITING    │  ← Connected to host
│              │  ← Waiting for host to start
└──────┬───────┘
       │
       │ Receive "game_start" message
       ↓
┌──────────────┐
│   STARTING   │  ← Loading GameWorld ⏳
│              │
└──────────────┘
```

## Component Interaction Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMPONENT ARCHITECTURE                        │
└─────────────────────────────────────────────────────────────────┘

NetworkMultiplayerSetup.gd (UI Layer)
         │
         │ calls
         ↓
GameModeManager (Autoload)
         │
         │ creates & uses
         ↓
MultiplayerNetworkHandler
         │
         │ uses
         ↓
NetworkManager (Autoload)
         │
         │ delegates to
         ↓
P2PNetworkBackend
         │
         │ uses
         ↓
ENetMultiplayerPeer (Godot Built-in)
         │
         │ signals
         ↓
peer_connected / connected_to_server
         │
         │ bubbles up through
         ↓
connection_established signal
         │
         │ handled by
         ↓
NetworkMultiplayerSetup (updates UI)
```

## What's Working vs What's Not

```
┌─────────────────────────────────────────────────────────────────┐
│                      IMPLEMENTATION STATUS                       │
└─────────────────────────────────────────────────────────────────┘

✅ WORKING:
├─ Host creates lobby
├─ Host waits for players (button disabled)
├─ Client connects to host
├─ Connection status polling
├─ P2P network mode setup
├─ Host enables "Start Game" when 2+ players
├─ Host broadcasts "game_start" message
└─ Host loads GameWorld

⏳ PARTIALLY WORKING:
├─ Lobby player count (needs real-time updates)
└─ Connection monitoring (implemented but not updating UI)

❌ NOT WORKING:
├─ Client doesn't receive "game_start" message
├─ Client doesn't load GameWorld
├─ Lobby doesn't show connected players in real-time
└─ No disconnect handling
```

## Critical Path to Working Multiplayer

```
Current State:
┌──────────┐     ┌──────────┐
│   HOST   │ ──> │  CLIENT  │
│  Loads   │     │  Stuck   │
│  Game    │     │ in Lobby │
└──────────┘     └──────────┘

Needed:
┌──────────┐     ┌──────────┐
│   HOST   │ ──> │  CLIENT  │
│  Loads   │     │  Loads   │
│  Game    │     │  Game    │
└──────────┘     └──────────┘

Required Steps:
1. Add message handler in MultiplayerGameState
2. Connect handler to NetworkMultiplayerSetup
3. On "game_start" message → load GameWorld
4. Synchronize game settings between host and client
```

## Next Implementation Steps

```
Priority 1: Client Game Start Listener
├─ Modify MultiplayerGameState.gd
│  └─ Add handler for "game_start" action type
├─ Modify NetworkMultiplayerSetup.gd
│  └─ Connect to game_start signal
└─ Test: Both players load into game

Priority 2: Real-Time Lobby Updates
├─ Implement peer connection monitoring
├─ Update player list when peers connect/disconnect
└─ Test: Lobby shows accurate player count

Priority 3: Disconnect Handling
├─ Handle client disconnect in lobby
├─ Handle client disconnect in game
└─ Test: Graceful handling of disconnections
```
