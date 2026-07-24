# TurnQueue Click Fix Summary

## Issue Identified
The TurnQueue portrait clicking was not working because the cursor's mouse input handling was consuming mouse events before they could reach the UI elements.

## Root Cause
The cursor was using `_input()` method with `get_viewport().set_input_as_handled()`, which has higher priority than UI elements and was consuming all mouse clicks before the TurnQueue buttons could receive them.

## Solution Applied

### 1. Fixed Input Priority Order
**Before:**
- Cursor used `_input()` (high priority) for mouse events
- UI elements couldn't receive mouse events because cursor consumed them
- `get_viewport().set_input_as_handled()` prevented event propagation

**After:**
- Cursor uses `_unhandled_input()` (low priority) for mouse events
- UI elements get first chance to handle mouse events
- Cursor only handles mouse events that UI doesn't consume

### 2. Enhanced Debug Output
**TurnQueue Debug:**
- Added detailed logging for portrait button creation
- Added debug output for button signal connections
- Added `_on_portrait_button_input()` method to track button input events
- Enhanced click handler logging

**Cursor Debug:**
- Added high-priority input logging to show event flow
- Maintained unhandled input logging for cursor processing
- Clear indication of when events are passed to UI vs cursor

## Technical Details

### Input Event Flow (Fixed):
1. **Mouse Click Occurs**
2. **UI Elements Process First** (`_input()` and `_gui_input()`)
   - TurnQueue buttons can receive and handle clicks
   - UnitActionsPanel buttons can receive clicks
   - Other UI elements get priority
3. **Cursor Processes Last** (`_unhandled_input()`)
   - Only handles clicks that UI didn't consume
   - Game area clicks still work for unit selection

### Code Changes:

#### cursor.gd:
```gdscript
# OLD: High priority mouse handling
func _input(event: InputEvent) -> void:
    # Consumed all mouse events
    get_viewport().set_input_as_handled()

# NEW: Low priority mouse handling  
func _unhandled_input(event: InputEvent) -> void:
    # Only handles events UI didn't consume
    # No set_input_as_handled() call
```

#### TurnQueue.gd:
```gdscript
# Enhanced debug output
func _on_portrait_clicked(unit: Unit) -> void:
    print("=== TurnQueue: Portrait clicked for " + unit.get_display_name() + " ===")
    
# Added button input debugging
func _on_portrait_button_input(event: InputEvent, unit: Unit) -> void:
    # Tracks all button input events for debugging
```

## Expected Behavior After Fix

### ✅ **TurnQueue Clicking:**
- Portrait clicks should now work correctly
- Debug output will show button creation and signal connections
- Click events will be logged with detailed information
- Unit selection will trigger from portrait clicks

### ✅ **Preserved Functionality:**
- Cursor movement and selection still works in game area
- Keyboard input (arrow keys, Enter) still works
- Mouse movement for cursor positioning still works
- All other UI elements (UnitActionsPanel, etc.) still work

### ✅ **Debug Information:**
- Console will show when buttons are created and connected
- Mouse clicks on portraits will be logged
- Event flow will be visible (UI first, then cursor)
- Easy to identify any remaining issues

## Testing Instructions

### 1. **Test TurnQueue Clicking:**
- Switch to Speed First mode
- Look for "Button signals connected" messages in console
- Click on unit portraits in the turn queue
- Should see "Portrait clicked" messages
- UnitActionsPanel should appear with unit details

### 2. **Test Cursor Still Works:**
- Click in game area (not on UI)
- Should see cursor mouse handling messages
- Unit selection should still work
- Keyboard movement should still work

### 3. **Debug Output to Look For:**
```
TurnQueue: Connecting button signals for [UnitName]
TurnQueue: Button signals connected for [UnitName]
=== TurnQueue: Portrait clicked for [UnitName] ===
TurnQueue: Emitting GameEvents.unit_selected for [UnitName]
```

## Files Modified
- `board/cursor/cursor.gd` - Fixed input priority and added debug output
- `game/ui/TurnQueue.gd` - Enhanced debug output for button interactions

## Benefits of Fix
1. **Proper Input Hierarchy**: UI elements get priority over game world input
2. **Maintained Functionality**: All existing features still work
3. **Better Debugging**: Comprehensive logging for troubleshooting
4. **Standard Godot Pattern**: Follows recommended input handling practices
5. **Future-Proof**: Won't interfere with additional UI elements

The TurnQueue portrait clicking should now work correctly while maintaining all existing cursor and game functionality!