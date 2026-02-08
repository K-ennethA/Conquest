# Dual Instance Multiplayer Testing - IMPLEMENTED

## Overview
Added functionality to automatically launch two instances of the game for easy multiplayer testing - one as host and one as client. This eliminates the need to manually start two separate instances.

## New Features

### 1. Host + Auto Client Button
- **Location**: Network Multiplayer Setup menu
- **Function**: Starts a host and automatically launches a second instance as client
- **Benefit**: One-click multiplayer testing

### 2. Command Line Auto-Join
- **Arguments**: 
  - `--multiplayer-auto-join`: Enable auto-join mode
  - `--multiplayer-address=IP`: Set host address (default: 127.0.0.1)
  - `--multiplayer-port=PORT`: Set host port (default: 8910)
  - `--multiplayer-player-name=NAME`: Set client player name
- **Function**: Automatically joins multiplayer game on startup

### 3. MultiplayerLauncher Autoload
- **Purpose**: Handles command line arguments and auto-join logic
- **Features**: Parses args, skips main menu, auto-connects to host

## How It Works

### Host + Auto Client Flow
1. User clicks "Host + Auto Client (Testing)" button
2. Game starts hosting on port 8910
3. Game launches second instance with auto-join arguments
4. Second instance automatically connects as client
5. Both instances start the multiplayer game

### Command Line Arguments
```bash
# Example launch command for auto-join client
game.exe --multiplayer-auto-join --multiplayer-address=127.0.0.1 --multiplayer-port=8910 --multiplayer-player-name="Client Player"
```

### Auto-Join Process
1. MultiplayerLauncher detects command line arguments
2. Main menu is skipped for auto-join clients
3. GameModeManager automatically joins the specified host
4. Game scene loads when connection is established

## Files Created/Modified

### New Files
- `systems/multiplayer_launcher.gd`: Handles command line args and auto-join
- `test_dual_instance_multiplayer.gd`: Test script for dual instance functionality

### Modified Files
- `menus/NetworkMultiplayerSetup.gd`: Added host + client button and launch logic
- `menus/NetworkMultiplayerSetup.tscn`: Added new button to UI
- `menus/MainMenu.gd`: Added auto-join detection and status display
- `project.godot`: Added MultiplayerLauncher autoload

## Usage Instructions

### For Testing Multiplayer
1. Start the game normally
2. Go to: Main Menu → Versus → Network Multiplayer
3. Click "Host + Auto Client (Testing)"
4. Two game windows will open:
   - First window: Host player
   - Second window: Client player (auto-joined)
5. Test multiplayer functionality with both instances

### Manual Dual Instance (Alternative)
1. Start first instance normally and host a game
2. Run second instance with command line:
   ```bash
   game.exe --multiplayer-auto-join --multiplayer-player-name="Test Client"
   ```

## Technical Implementation

### Process Launching
```gdscript
# In NetworkMultiplayerSetup._launch_client_instance()
var executable_path = OS.get_executable_path()
var arguments = [
    "--multiplayer-auto-join",
    "--multiplayer-address=127.0.0.1", 
    "--multiplayer-port=8910",
    "--multiplayer-player-name=Client Player"
]
var pid = OS.create_process(executable_path, arguments)
```

### Auto-Join Detection
```gdscript
# In MultiplayerLauncher._parse_command_line_args()
var args = OS.get_cmdline_args()
for arg in args:
    if arg == "--multiplayer-auto-join":
        auto_join_enabled = true
```

### Automatic Connection
```gdscript
# In MultiplayerLauncher._auto_join_multiplayer()
var success = await GameModeManager.join_network_multiplayer(
    auto_join_address, auto_join_port, auto_join_player_name, "local"
)
```

## Benefits

### For Developers
- **Faster Testing**: No need to manually start two instances
- **Consistent Setup**: Same connection parameters every time
- **Easy Debugging**: Both instances visible simultaneously
- **Automated Process**: Reduces human error in setup

### For Users (Future)
- **Demo Mode**: Easy way to show multiplayer functionality
- **Tutorial**: Could be used for multiplayer tutorials
- **Testing**: Players can test multiplayer features solo

## Debug Features

### Status Display
- Auto-join clients show connection status on main menu
- Host shows connection info and port number
- Clear feedback when instances launch successfully

### Test Script
- `test_dual_instance_multiplayer.gd` provides manual testing
- Keyboard shortcut 'T' to test instance launching
- Debug output shows command line arguments and process IDs

## Keyboard Shortcuts

### In Network Multiplayer Setup
- `1`: Host Game (single instance)
- `2`: Host + Auto Client (dual instance)
- `3`: Join Game (manual join)

### In Test Script
- `T`: Test dual instance launching
- `H`: Show help

## Error Handling

### Launch Failures
- Shows error message if client instance fails to launch
- Provides process ID for successful launches
- Graceful fallback to single instance hosting

### Connection Failures
- Auto-join clients fall back to main menu if connection fails
- Clear error messages for debugging
- Timeout handling for connection attempts

## Status: ✅ IMPLEMENTED AND READY

The dual instance multiplayer testing system is fully implemented:
- ✅ Host + Auto Client button in network setup
- ✅ Command line argument parsing
- ✅ Automatic client launching and joining
- ✅ Status feedback and error handling
- ✅ Test scripts for verification

This makes multiplayer testing significantly easier by automating the process of starting both host and client instances with a single button click.