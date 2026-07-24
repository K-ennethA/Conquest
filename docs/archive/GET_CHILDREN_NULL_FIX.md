# Get Children Null Reference Fix

## Error
```
Cannot call method 'get_children' on a null value.
```

## Root Cause

The error occurred during game world initialization when trying to assign units to players. The issue was a timing problem with node deletion:

1. `GameWorldManager._clear_existing_map_content()` called `queue_free()` on Player1/Player2 nodes
2. `MapLoader` created new Player1/Player2 nodes
3. `PlayerManager.assign_units_by_parent()` tried to access the nodes
4. **Problem**: `queue_free()` doesn't delete immediately - it happens at end of frame
5. The code might find old nodes that are queued for deletion but not yet deleted
6. Calling `get_children()` on these "zombie" nodes caused the null reference error

## Solution

### 1. Use Immediate Deletion (`free()` instead of `queue_free()`)

**File: `game/world/GameWorldManager.gd`**

Changed `_clear_existing_map_content()` to use `free()` for immediate deletion:

```gdscript
func _clear_existing_map_content(map_node: Node3D) -> void:
    """Clear existing hardcoded map content while preserving structure"""
    # Remove existing tiles
    var tiles_node = map_node.get_node_or_null("Tiles")
    if tiles_node:
        for child in tiles_node.get_children():
            child.free()  # Immediate deletion
        tiles_node.free()  # Immediate deletion
    
    # Remove existing player containers
    var player1_node = map_node.get_node_or_null("Player1")
    if player1_node:
        for child in player1_node.get_children():
            child.free()  # Immediate deletion
        player1_node.free()  # Immediate deletion
    
    var player2_node = map_node.get_node_or_null("Player2")
    if player2_node:
        for child in player2_node.get_children():
            child.free()  # Immediate deletion
        player2_node.free()  # Immediate deletion
    
    print("Cleared existing map content")
```

**Why `free()` instead of `queue_free()`:**
- `free()` deletes the node immediately
- `queue_free()` schedules deletion for end of frame
- We need immediate deletion to avoid accessing deleted nodes

### 2. Add Null Checks and Validation

**File: `systems/player_manager.gd`**

Added safety checks to `assign_units_by_parent()`:

```gdscript
func assign_units_by_parent() -> void:
    """Auto-assign units based on their parent node names"""
    var scene_root = get_tree().current_scene
    
    if not scene_root:
        print("ERROR: No current scene found")
        return
    
    # Look for Player1 and Player2 nodes
    for i in range(players.size()):
        var player_node_name = "Map/Player" + str(i + 1)
        var player_node = scene_root.get_node_or_null(player_node_name)
        
        if player_node and is_instance_valid(player_node):  // ADDED VALIDATION
            print("Found player node: " + player_node_name)
            for child in player_node.get_children():
                if child is Unit and is_instance_valid(child):  // ADDED VALIDATION
                    assign_unit_to_player(child, i)
        else:
            print("Player node not found or invalid: " + player_node_name)
```

**Added Checks:**
- `if not scene_root:` - Ensure scene exists
- `is_instance_valid(player_node)` - Verify node is valid (not freed/deleted)
- `is_instance_valid(child)` - Verify child unit is valid

## Why This Matters for Multiplayer

In multiplayer, the game world loads dynamically based on the selected map. The sequence is:

1. CollaborativeLobby → Host finalizes map selection
2. Both players call `get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")`
3. GameWorld loads and initializes
4. GameWorldManager clears old content and loads new map
5. PlayerManager assigns units to players

If step 4 doesn't complete properly (nodes not fully deleted), step 5 fails with null reference errors.

## Testing

1. Launch host → Select map → Click ready
2. Launch client → Select map → Click ready
3. **Verify**: Game loads without "Cannot call method 'get_children' on a null value" error
4. **Verify**: Both players see the game world with units properly assigned
5. **Verify**: Console shows "Cleared existing map content" and "Found player node: Map/Player1" messages

## Expected Console Output

```
=== GameWorld Initializing ===
Loading selected map...
Cleared existing map content
Map loaded successfully: Default Skirmish
Network multiplayer mode detected
Setting up network multiplayer...
Setting up multiplayer players...
Found player node: Map/Player1
Assigned unit Warrior to Player 1
Found player node: Map/Player2
Assigned unit Archer to Player 2
Game started successfully!
=== GameWorld Initialization Complete ===
```

## Files Modified

- `game/world/GameWorldManager.gd` - Changed to immediate deletion with `free()`
- `systems/player_manager.gd` - Added null checks and validation

## Verification

All files compile without errors (verified with getDiagnostics).

## Related Issues Fixed

This also prevents potential issues with:
- Units being assigned to deleted player nodes
- Tiles being accessed after deletion
- Race conditions during scene transitions
- Memory leaks from improperly freed nodes
