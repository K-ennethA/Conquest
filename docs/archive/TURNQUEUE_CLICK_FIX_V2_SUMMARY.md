# TurnQueue Click Fix V2 Summary

## Issue Identified
The TurnQueue portrait clicking was still not working despite fixing the input priority. The root cause was that the `pressed` signal was not being emitted reliably, likely due to buttons being recreated during the click process or other interference.

## Root Cause Analysis
From the logs, we could see:
1. ✅ Mouse events were being detected
2. ✅ Hover events were working (mouse_entered/mouse_exited)
3. ✅ Buttons were being created and signals connected
4. ❌ `pressed` signal was never being emitted
5. ❌ Portrait click handlers were never called

The issue was that the `pressed` signal requires a complete mouse press + release cycle on the same button, but something was interfering with this process.

## Solution Applied

### 1. Direct Input Handling
**Changed from `pressed` signal to `gui_input` signal:**
- `pressed` signal: Requires complete press+release cycle, can be interrupted
- `gui_input` signal: Receives raw input events directly, more reliable

**Before:**
```gdscript
button.pressed.connect(_on_portrait_clicked.bind(unit))
```

**After:**
```gdscript
button.gui_input.connect(_on_portrait_button_input.bind(unit))
```

### 2. Enhanced Input Processing
**Added direct mouse button handling:**
```gdscript
func _on_portrait_button_input(event: InputEvent, unit: Unit) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _on_portrait_clicked(unit)
            get_viewport().set_input_as_handled()
```

### 3. Improved Debug Output
**Enhanced logging to track the fix:**
- Clear indication when button input is received
- Detailed mouse button event information
- Confirmation when click handler is called

## Technical Details

### Input Event Flow (Fixed):
1. **Mouse Click on Portrait**
2. **Button receives `gui_input` event**
3. **`_on_portrait_button_input()` processes event**
4. **Checks for left mouse button press**
5. **Calls `_on_portrait_clicked()` directly**
6. **Consumes event with `set_input_as_handled()`**

### Benefits of `gui_input` over `pressed`:
- **More Direct**: Receives raw input events immediately
- **More Reliable**: Not dependent on press+release cycle completion
- **Better Control**: Can handle different mouse buttons or modifiers
- **Immediate Response**: Triggers on press, not release

## Expected Behavior After Fix

### ✅ **Portrait Clicking Should Work:**
```
TurnQueue: Button input for [UnitName] - Button: 1 Pressed: true
TurnQueue: Left mouse button pressed on [UnitName]
=== TurnQueue: Portrait clicked for [UnitName] ===
TurnQueue: Emitting GameEvents.unit_selected for [UnitName]
```

### ✅ **Preserved Functionality:**
- Hover effects still work (mouse_entered/mouse_exited)
- Scroll buttons still work
- All other UI functionality preserved
- Cursor input still works in game area

## Debugging Information

### Success Indicators:
1. **Button Creation**: "Button signals connected for [UnitName]"
2. **Input Detection**: "Button input for [UnitName] - Button: 1 Pressed: true"
3. **Click Processing**: "Left mouse button pressed on [UnitName]"
4. **Handler Execution**: "=== TurnQueue: Portrait clicked for [UnitName] ==="
5. **Event Emission**: "TurnQueue: Emitting GameEvents.unit_selected for [UnitName]"

### If Still Not Working:
- Check if button input events are being received
- Verify mouse position is within button bounds
- Ensure no other UI elements are blocking the button
- Check if button is properly added to scene tree

## Alternative Approaches Considered

### 1. **Button Recreation Prevention**
- Tried throttling updates to prevent button destruction
- Would have added complexity without addressing root cause

### 2. **Mouse Filter Adjustments**
- Could adjust mouse_filter settings on various elements
- `gui_input` approach is more direct and reliable

### 3. **Custom Button Implementation**
- Could create custom clickable areas
- `gui_input` on existing buttons is simpler and more maintainable

## Files Modified
- `game/ui/TurnQueue.gd` - Changed from `pressed` to `gui_input` signal handling

## Testing Instructions
1. **Run Speed First mode**
2. **Click on unit portraits in turn queue**
3. **Look for debug output confirming button input**
4. **Verify UnitActionsPanel appears with unit details**
5. **Test that hover effects still work**
6. **Confirm scroll buttons still function**

The portrait clicking should now work reliably using direct input event handling instead of relying on the `pressed` signal mechanism.