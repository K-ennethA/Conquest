# Simple Client Launch Fix

## Problem Identified

The command line argument approach for client auto-join is not working because:

1. **Arguments not reaching second instance**: The launched instance shows `["--scene", "res://menus/MainMenu.tscn"]` instead of the multiplayer arguments
2. **Editor vs Export differences**: `OS.create_process()` behaves differently when running from editor
3. **Complex argument parsing**: Multiple formats and edge cases make it unreliable

## New Solution: File-Based Communication

Instead of relying on command line arguments, use a simple file-based approach:

### How It Works

1. **Host wants to launch client**: Creates a flag file `user://client_instance.flag`
2. **Launches second instance**: Uses simple `OS.create_process()` without complex arguments
3. **Second instance starts**: Checks for flag file in `_ready()`
4. **If flag file exists**: Instance becomes a client and auto-joins
5. **Flag file deleted**: After detection to prevent future instances from being clients

### Advantages

- **Simple and reliable**: No complex command line parsing
- **Works in editor and export**: Same behavior regardless of environment
- **No argument conflicts**: Doesn't interfere with Godot's internal arguments
- **Easy to debug**: Clear file-based state that can be inspected

## Implementation

### 1. `simple_client_launcher.gd`
- Detects client flag file on startup
- Handles client auto-join process
- Manages flag file lifecycle
- Provides launch method for host

### 2. Modified `NetworkMultiplayerSetup.gd`
- Uses simple client launcher instead of command line arguments
- Cleaner launch process
- Better error handling

### 3. Modified `MainMenu.gd`
- Includes simple client launcher automatically
- Detects client instances on startup
- Handles both command line and file-based detection

## Usage

### For Host + Auto Client:
1. Click "Host + Auto Client" button
2. System creates flag file and launches second instance
3. Second instance detects flag file and becomes client
4. Client automatically joins host
5. Both instances load game scene

### Expected Logs:

#### Host Instance:
```
[HOST] Starting network multiplayer host...
[HOST] Host started successfully!
Launching client instance with simple method...
Client flag file created: user://client_instance.flag
Client instance launched with PID: [number]
```

#### Client Instance:
```
[CLIENT] Client flag file found - this is a client instance!
[CLIENT] Starting client auto-join process...
[CLIENT] Attempting to join multiplayer game...
[CLIENT] Join result: true
[CLIENT] Successfully joined! Loading game scene...
```

## Testing

1. **Run the game**
2. **Go to Versus → Network Multiplayer**
3. **Click "Host + Auto Client"**
4. **Watch for both `[HOST]` and `[CLIENT]` logs**
5. **Verify second window opens and connects**

## Fallback Support

The system maintains backward compatibility:
- Still supports command line arguments if they work
- File-based detection as primary method
- Graceful fallback to main menu on failure

This approach should resolve the client auto-join issues by using a more reliable communication method between instances.