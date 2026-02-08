# Multiplayer System

A modular multiplayer system for the tactical combat game that supports P2P-first architecture with easy migration to dedicated servers.

## 🏗️ Architecture

### Core Components

1. **NetworkBackend** - Abstract base class for all networking modes
2. **LocalNetworkBackend** - Development mode with network simulation
3. **P2PNetworkBackend** - Production P2P networking with UPnP
4. **DedicatedServerBackend** - Future migration path to dedicated servers
5. **NetworkManager** - Unified interface that switches between backends
6. **MultiplayerGameState** - Handles state synchronization and prediction
7. **MultiplayerTurnSystem** - Multiplayer-aware turn management
8. **MultiplayerManager** - High-level coordinator

### Network Modes

- **Local Development** - Two instances on same machine for testing
- **P2P Direct** - Peer-to-peer networking for production launch
- **Dedicated Server** - Future server-authoritative mode

## 🚀 Quick Start

### 1. Testing the System

Run the test scene to verify everything works:

```gdscript
# Load the test scene
get_tree().change_scene_to_file("res://systems/multiplayer/MultiplayerTestScene.tscn")
```

### 2. Basic Usage

```gdscript
# Get the multiplayer manager
var multiplayer_manager = MultiplayerManager.new()
add_child(multiplayer_manager)

# Start local development game
multiplayer_manager.start_local_multiplayer_game(["Player 1", "Player 2"])

# Submit game actions
multiplayer_manager.submit_game_action("unit_move", {
    "unit_id": "warrior_1",
    "from_position": Vector3(0,0,0),
    "to_position": Vector3(2,0,1)
})
```

### 3. P2P Hosting

```gdscript
# Start P2P host
multiplayer_manager.start_p2p_multiplayer_game("Host Player", 4)

# Get connection info to share with other players
var connection_info = multiplayer_manager.get_host_connection_info()
print("Share this address: %s:%d" % [connection_info.address, connection_info.port])
```

### 4. P2P Joining

```gdscript
# Join P2P game
multiplayer_manager.join_p2p_multiplayer_game("192.168.1.100", 8910, "Player 2")
```

## 🔧 Integration with Existing Systems

### Modifying UnitActionsPanel

Add multiplayer checks to existing action methods:

```gdscript
func _on_move_pressed() -> void:
    if not selected_unit:
        return
    
    # Check if multiplayer is active and if it's our turn
    var multiplayer_manager = get_node("/root/MultiplayerManager")
    if multiplayer_manager and multiplayer_manager.is_multiplayer_active():
        if not multiplayer_manager.is_local_player_turn():
            print("Cannot move: not your turn")
            return
        
        # Submit to multiplayer system
        var action_data = {
            "unit_id": selected_unit.get_id(),
            "player_id": multiplayer_manager.get_local_player_id()
        }
        multiplayer_manager.submit_game_action("unit_move_start", action_data)
        return
    
    # Existing single-player code...
    _enter_movement_mode()
```

### Handling Multiplayer Actions

```gdscript
func _ready() -> void:
    # Connect to multiplayer events
    var multiplayer_manager = get_node("/root/MultiplayerManager")
    if multiplayer_manager:
        multiplayer_manager._multiplayer_game_state.message_received.connect(_on_multiplayer_action)

func _on_multiplayer_action(sender_id: int, message: Dictionary) -> void:
    if message.get("type") == "game_action":
        var action_type = message.get("action_type", "")
        var action_data = message.get("action_data", {})
        
        match action_type:
            "unit_move":
                _handle_remote_unit_move(action_data)
            "unit_attack":
                _handle_remote_unit_attack(action_data)
```

## 🎮 Testing Controls

When running the test scene, use these keyboard shortcuts:

- **1** - Test Local Development Mode
- **2** - Test P2P Host
- **3** - Test P2P Join (localhost:8910)
- **4** - Test Dedicated Server (future)
- **D** - Print Debug Info
- **Q** - Disconnect
- **H** - Show Help

## 🔄 Network Mode Switching

The system supports switching between network modes at runtime:

```gdscript
var network_manager = get_node("/root/NetworkManager")

# Switch to local development
network_manager.set_network_mode(NetworkBackend.NetworkMode.LOCAL_DEVELOPMENT)

# Switch to P2P
network_manager.set_network_mode(NetworkBackend.NetworkMode.P2P_DIRECT)

# Switch to dedicated server (future)
network_manager.set_network_mode(NetworkBackend.NetworkMode.DEDICATED_SERVER)
```

## 🛠️ Development Features

### Network Simulation

Test network conditions in development mode:

```gdscript
var network_manager = get_node("/root/NetworkManager")
if network_manager._local_backend:
    # Simulate 100ms latency and 5% packet loss
    network_manager._local_backend.set_latency_simulation(true, 100)
    network_manager._local_backend.set_packet_loss_simulation(true, 0.05)
```

### Debug Information

Get comprehensive debug info:

```gdscript
var multiplayer_manager = get_node("/root/MultiplayerManager")
var status = multiplayer_manager.get_multiplayer_status()
print("Multiplayer Status: %s" % str(status))

var network_stats = network_manager.get_network_statistics()
print("Network Stats: %s" % str(network_stats))
```

## 🚀 Migration Path

The system is designed for easy migration:

1. **Phase 1** - Launch with P2P (current implementation)
2. **Phase 2** - Add dedicated servers when user base grows
3. **Phase 3** - Switch to server-authoritative for competitive play

Migration is as simple as changing the network mode - no code changes required in game logic.

## 📁 File Structure

```
systems/multiplayer/
├── README.md                           # This file
├── MultiplayerManager.gd               # Main coordinator
├── MultiplayerGameState.gd             # State synchronization
├── MultiplayerTurnSystem.gd            # Turn management
├── multiplayer_autoload.gd             # Global access (optional)
├── test_multiplayer_system.gd          # Test framework
├── MultiplayerTestScene.tscn           # Test scene
└── multiplayer_integration_example.gd  # Integration examples

systems/networking/
├── NetworkBackend.gd                   # Abstract base class
├── LocalNetworkBackend.gd              # Development mode
├── P2PNetworkBackend.gd                # P2P networking
├── DedicatedServerBackend.gd           # Future server mode
└── NetworkManager.gd                   # Unified interface
```

## 🎯 Benefits

- **Fast Time to Market** - P2P gets you multiplayer quickly
- **Low Initial Costs** - No server infrastructure needed
- **Easy Migration** - Switch to dedicated servers when ready
- **Development Friendly** - Local testing without network complexity
- **Future Proof** - Supports all networking modes

## 🔍 Troubleshooting

### Common Issues

1. **Connection Failed** - Check firewall settings and port availability
2. **NAT Traversal Issues** - Enable UPnP or use port forwarding
3. **High Latency** - P2P connections may have higher latency than dedicated servers
4. **Disconnections** - P2P is less stable than dedicated servers

### Debug Steps

1. Run the test scene to verify basic functionality
2. Check debug output with the 'D' key
3. Test with local development mode first
4. Verify network connectivity between peers

## 📝 Next Steps

1. Integrate with your existing game systems
2. Test with multiple players
3. Implement game-specific actions
4. Plan for dedicated server migration when ready
5. Add UI for multiplayer lobby and matchmaking