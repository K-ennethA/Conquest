# Unit Selection Debug Summary

## Issue
The Traditional turn system appears to be working correctly, but the UnitActionsPanel is not appearing when units are selected. The logs show that the UnitActionsPanel is being initialized correctly, but unit selection events may not be reaching it.

## Debug Changes Made

### 1. Enhanced UnitActionsPanel Debug Output
- **Added detailed logging** in `_ready()` method to confirm GameEvents and PlayerManager connections
- **Enhanced `_on_unit_selected()`** with comprehensive debug output to track selection events
- **Added F4 key test** to manually trigger unit selection for testing
- **Added `_test_manual_unit_selection()`** method to bypass cursor and directly test panel functionality

### 2. Enhanced Cursor Debug Output  
- **Enhanced `_select_unit()`** with detailed logging to track signal emission
- **Added F5 key test** to manually emit GameEvents.unit_selected signal
- **Added `_test_unit_selection_signal()`** method to test signal emission directly
- **Enhanced mouse click logging** with position and raycast information

### 3. Test Debug Script
- **Created `test_unit_selection.gd`** to verify GameEvents connections and node structure

## Testing Instructions

### Manual Testing Keys
- **F4**: Test UnitActionsPanel by manually selecting first Player1 unit
- **F5**: Test GameEvents.unit_selected signal emission from cursor
- **F2**: Force show UnitActionsPanel for visual confirmation
- **F3**: Force hide UnitActionsPanel
- **Arrow Keys + Enter**: Use keyboard to move cursor and select units
- **Mouse Click**: Click on units to test mouse selection

### Expected Debug Output

#### Successful Unit Selection Should Show:
```
=== Cursor: Selecting unit ===
Unit: [UnitName]
World position: [Vector3]
Emitting GameEvents.unit_selected signal...
GameEvents.unit_selected signal emitted
=== Cursor: Unit selection complete ===

=== UnitActionsPanel: Unit selection received ===
Unit: [UnitName]
Position: [Vector3]
Unit selection accepted: [UnitName]
=== UnitActionsPanel: Unit selection processing complete ===
```

#### If GameEvents Connection is Broken:
```
=== UnitActionsPanel _ready() called ===
ERROR: GameEvents not found!
```

#### If Unit Selection is Blocked:
```
Selection rejected by PlayerManager
```
or
```
Selection rejected by turn system: [SystemName]
```

## Potential Issues to Check

### 1. GameEvents Connection
- Verify GameEvents singleton is properly loaded
- Check if UnitActionsPanel is connecting to signals correctly
- Confirm signal emission from cursor

### 2. Node Structure
- Verify UnitActionsPanel is in correct scene tree location
- Check if UI layout is properly instantiated
- Confirm cursor can find units in scene

### 3. Turn System Validation
- Check if PlayerManager.can_current_player_select_unit() is working
- Verify turn system constraints are not blocking selection
- Confirm current player owns the units being selected

### 4. Mouse vs Keyboard Selection
- Test both mouse clicks and keyboard Enter key
- Check if mouse UI detection is interfering
- Verify cursor positioning is correct

## Next Steps
1. Run the game and try the debug keys (F4, F5)
2. Check console output for the expected debug messages
3. Try both mouse and keyboard selection
4. If F4 works but normal selection doesn't, the issue is in cursor logic
5. If F4 doesn't work, the issue is in UnitActionsPanel or GameEvents connection

## Files Modified
- `game/ui/UnitActionsPanel.gd` - Enhanced debug output and manual testing
- `board/cursor/cursor.gd` - Enhanced debug output and signal testing
- `test_unit_selection.gd` - New debug script for connection verification

The debug changes will help identify exactly where the unit selection chain is breaking down.