# Mouse Input Fix Summary

## Problem Identified
After implementing the TurnQueue portrait clicking functionality, unit selection via mouse clicks stopped working. The issue was that UI container elements were consuming mouse events that should reach the game area.

## Root Cause
1. **UI Container Mouse Filtering**: The main `GameUILayout` Control node and its container hierarchy had default `mouse_filter = Control.MOUSE_FILTER_STOP` settings
2. **Event Consumption**: Container elements were consuming mouse events before they could reach `_unhandled_input()` in the cursor
3. **Coupling Issue**: TurnQueue fixes inadvertently affected unrelated unit selection functionality

## Solution Implemented

### 1. UI Container Mouse Filter Fix
**File**: `game/ui/UILayoutManager.gd`
- Set `mouse_filter = Control.MOUSE_FILTER_IGNORE` for the main UILayoutManager
- Set `mouse_filter = Control.MOUSE_FILTER_IGNORE` for all container elements:
  - MarginContainer
  - MainContainer (VBoxContainer)
  - TopBar (HBoxContainer)
  - CenterTopContainer (VBoxContainer)
  - MiddleArea (HBoxContainer)
  - LeftSidebar, RightSidebar (VBoxContainer)
  - GameArea (Control)

### 2. TurnQueue Mouse Filter Fix
**File**: `game/ui/TurnQueue.gd`
- Set `mouse_filter = Control.MOUSE_FILTER_IGNORE` for the TurnQueue container
- This allows clicks to pass through empty areas while buttons still capture their events

### 3. Enhanced Cursor Input Handling
**File**: `board/cursor/cursor.gd`
- Improved UILayoutManager integration for mouse-over-UI detection
- Added fallback detection for when UILayoutManager is not available
- Added right-click debug bypass for testing unit selection
- Enhanced debugging output for troubleshooting

### 4. Improved UI Detection Logic
**File**: `game/ui/UILayoutManager.gd`
- Enhanced `is_mouse_over_ui()` method with detailed debugging
- Proper panel rectangle calculation using `global_position` and `size`
- Clear logging of which UI elements are being checked

## Technical Details

### Mouse Filter Hierarchy
```
GameUILayout (IGNORE) 
├── MarginContainer (IGNORE)
    ├── MainContainer (IGNORE)
        ├── TopBar (IGNORE)
        │   ├── TurnQueue (IGNORE) - but buttons inside use STOP
        │   └── TurnIndicator (IGNORE)
        └── MiddleArea (IGNORE)
            ├── GameArea (IGNORE) - allows clicks to reach 3D scene
            └── RightSidebar (IGNORE)
                └── UnitActionsPanel (STOP) - captures its own events
```

### Event Flow
1. Mouse click occurs
2. UI containers with IGNORE filter let event pass through
3. Specific UI elements (buttons, panels) with STOP filter capture relevant events
4. Uncaptured events reach `_unhandled_input()` in cursor for unit selection

## Prevention of Future Issues
- **Decoupled Design**: UI container mouse filtering is now independent of specific UI component implementations
- **Clear Separation**: Container elements handle layout, specific components handle interaction
- **Debugging Tools**: Enhanced logging and right-click bypass for testing
- **Fallback Systems**: Multiple detection methods ensure robustness

## Result
- Unit selection via mouse clicks now works correctly
- TurnQueue portrait clicking continues to function
- UI interactions are properly isolated from game area interactions
- System is more robust against future changes

This fix ensures that UI improvements don't break unrelated game functionality by maintaining proper event flow separation.