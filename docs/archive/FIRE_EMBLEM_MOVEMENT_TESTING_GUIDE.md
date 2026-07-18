# Fire Emblem Movement System - Testing Guide

## Overview
The Fire Emblem style movement system is **already implemented** and should be working! This guide helps you test and verify it's working correctly.

## How Fire Emblem Movement Works

### 1. **Immediate Movement Range Display**
- When you **select any unit**, blue highlighted tiles immediately appear
- These blue tiles show where the unit can move (based on unit's movement stat)
- **No need to click a "Move" button first** - range appears instantly

### 2. **Direct Tile Clicking**
- Click on **any blue highlighted tile** to move the unit there
- Unit will smoothly animate to the destination
- Movement range disappears after moving
- Unit is marked as "acted" and can't move again this turn

### 3. **Turn System Integration**
- Works with both Traditional and Speed First turn systems
- Respects unit ownership (can only move your units)
- Validates moves through active turn system

## Testing Steps

### Step 1: Load the Game
1. Open the project in Godot
2. Run the `GameWorld.tscn` scene
3. You should see a 5x5 grid with units from both players

### Step 2: Test Unit Selection
1. **Click on any unit** (preferably Player 1 units: Warrior1, Warrior2, or Archer1)
2. **Blue tiles should immediately appear** around the selected unit
3. The UnitActionsPanel should appear on the right side

### Step 3: Test Movement
1. With blue tiles visible, **click on any blue tile**
2. The unit should **smoothly move** to that position
3. Blue tiles should **disappear** after movement
4. Unit should be marked as "acted" (grayed out or different visual)

### Step 4: Test Different Units
1. Try selecting different unit types:
   - **Warriors**: 3 movement range (3 tiles)
   - **Archers**: 4 movement range (4 tiles)
   - **Scouts**: 5 movement range (5 tiles)
   - **Tanks**: 2 movement range (2 tiles)

## Debug Keys for Testing

Press these keys while the game is running:

- **F8**: Run Fire Emblem movement test script
- **F9**: Run full movement system test
- **F10**: Test movement range calculation
- **F11**: Test Fire Emblem style unit selection
- **F12**: Test movement range display directly

## Expected Behavior

### ✅ What Should Work
- **Instant blue highlighting** when selecting units
- **Direct tile clicking** to move units
- **Smooth movement animation** (0.5 seconds)
- **Turn system validation** (only move your units on your turn)
- **Movement range calculation** based on unit stats
- **Obstacle avoidance** (can't move through other units)

### ❌ Common Issues
- **No blue tiles appear**: Check console for errors, unit might have 0 movement
- **Can't click tiles**: UI might be blocking mouse input, try right-click
- **Unit doesn't move**: Turn system might be blocking the action
- **Wrong movement range**: Check unit's movement stat in resources

## Troubleshooting

### Issue: No Blue Tiles Appear
1. Check console for error messages
2. Verify unit has movement > 0: `unit.get_movement_range()`
3. Check if MovementVisualizer is in scene
4. Try pressing F11 to test selection directly

### Issue: Can't Click on Tiles
1. UI might be blocking mouse input
2. Try **right-clicking** instead of left-clicking
3. Check if UILayoutManager is being too aggressive
4. Use keyboard navigation (arrow keys + Enter)

### Issue: Unit Won't Move
1. Check if it's your turn (Traditional mode)
2. Check if unit has already acted this turn
3. Verify destination is within movement range
4. Check console for turn system validation messages

## Manual Testing Script

If you want to test manually, add this to GameWorld scene:

```gdscript
# Add this as a script to a Node in GameWorld
extends Node

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_T:
            _test_fire_emblem_movement()

func _test_fire_emblem_movement():
    var units = get_tree().get_nodes_in_group("units")
    if units.size() > 0:
        var test_unit = units[0]
        GameEvents.unit_selected.emit(test_unit, test_unit.global_position)
        print("Selected unit - blue tiles should appear!")
```

## System Architecture

The Fire Emblem movement system consists of:

1. **UnitActionsPanel.gd**: Handles unit selection and movement range calculation
2. **MovementVisualizer.gd**: Creates blue tile highlighting
3. **cursor.gd**: Handles mouse/keyboard input and tile selection
4. **GameEvents**: Coordinates communication between components

## Files Involved

- `game/ui/UnitActionsPanel.gd` - Main movement logic
- `game/visuals/MovementVisualizer.gd` - Visual feedback
- `board/cursor/cursor.gd` - Input handling
- `systems/game_events.gd` - Event coordination
- `game/units/resources/unit_types/*.tres` - Unit movement stats

## Conclusion

The Fire Emblem movement system is **fully implemented** and should work out of the box. If you're not seeing blue tiles when selecting units, check the troubleshooting section above.

The system provides the exact Fire Emblem experience:
- **Select unit** → **See movement range** → **Click destination** → **Unit moves**

No additional implementation needed - just test and enjoy!