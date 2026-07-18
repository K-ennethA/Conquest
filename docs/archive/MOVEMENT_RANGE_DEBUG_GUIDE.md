# Movement Range Debug Guide

## Issue
The Fire Emblem style movement range is not displaying immediately when units are selected.

## Debug Tools Added

### 1. Enhanced Logging
**Files Modified:**
- `game/visuals/MovementVisualizer.gd` - Added detailed connection and material setup logging
- `game/ui/UnitActionsPanel.gd` - Added comprehensive movement range calculation logging
- `tile_objects/units/unit.gd` - Added movement range retrieval logging

### 2. Debug Keys Available

#### In MovementSystemTest (F9-F12)
- **F9**: Run full movement system component test
- **F10**: Test movement range calculation with BFS algorithm
- **F11**: Test Fire Emblem style unit selection (auto-select unit, show range)
- **F12**: Test MovementVisualizer directly with hardcoded positions

#### In UnitActionsPanel (F4-F5)
- **F4**: Test manual unit selection
- **F5**: Test movement range calculation directly (bypasses selection)

#### In DebugMovementRange (T-Y)
- **T**: Test movement range display directly (bypasses all systems)
- **Y**: Test unit selection and automatic movement range display

### 3. Debug Script: `debug_movement_range.gd`
**Purpose**: Bypass all complex systems and test core functionality
**Features**:
- Direct MovementVisualizer testing
- Unit finding and selection simulation
- Movement range validation
- Signal emission testing

## Debugging Steps

### Step 1: Test MovementVisualizer Directly
1. Run the game
2. Press **T** key
3. **Expected**: Blue tiles should appear around position (1,0,1)
4. **If fails**: MovementVisualizer not working

### Step 2: Test Unit Selection Signal
1. Press **Y** key
2. **Expected**: Unit gets selected, movement range appears
3. **If fails**: Unit selection or signal chain broken

### Step 3: Test Movement Range Calculation
1. Press **F10** key
2. **Expected**: Console shows calculated reachable tiles
3. **If fails**: BFS algorithm or unit stats issue

### Step 4: Test Fire Emblem Style Selection
1. Press **F11** key
2. **Expected**: Unit auto-selected, blue tiles appear
3. **If fails**: UnitActionsPanel integration issue

## Common Issues and Solutions

### Issue 1: MovementVisualizer Not Found
**Symptoms**: Console shows "MovementVisualizer not found"
**Solution**: Check GameWorld.tscn has MovementVisualizer node with correct script

### Issue 2: No Movement Range on Unit
**Symptoms**: Console shows "Unit movement range: 0"
**Solution**: Check unit resource files have `base_movement` values set

### Issue 3: GameEvents Not Connected
**Symptoms**: Console shows "GameEvents not found"
**Solution**: Ensure GameEvents singleton is properly loaded

### Issue 4: Tiles Not Highlighting
**Symptoms**: Movement range calculated but no visual change
**Solution**: Check tile detection in MovementVisualizer._find_tile_at_position()

### Issue 5: Unit Selection Not Triggering
**Symptoms**: Clicking units doesn't show movement range
**Solution**: Check PlayerManager.can_current_player_select_unit() validation

## Expected Console Output

### Successful Movement Range Display:
```
=== MovementVisualizer _ready() called ===
Setting up movement visualization materials...
Materials created successfully
Connecting MovementVisualizer to GameEvents...
✓ MovementVisualizer connected to GameEvents
=== UnitActionsPanel: Unit selection received ===
Unit: Warrior1
Selected unit set to: Warrior1
About to call _show_movement_range_on_selection()...
=== Showing Movement Range on Selection ===
Selected unit: Warrior
=== Calculating Movement Range ===
Unit world position: (1, 1.5, 1)
Unit grid position: (0, 0, 0)
Unit Warrior movement range: 3
Unit movement range: 3
Calculated 8 reachable tiles
Emitting movement_range_calculated signal...
Signal emitted successfully
=== MovementVisualizer: Showing movement range ===
Highlighting 8 tiles
Found tile at (1, 0, 0) (node: Tile_1_0 at world: (2, 0, 2) grid: (1, 0, 1))
Movement range visualization complete
```

## Files Modified for Debugging

### Enhanced Files:
- `game/visuals/MovementVisualizer.gd` - Added comprehensive logging
- `game/ui/UnitActionsPanel.gd` - Added debug methods and detailed logging
- `tile_objects/units/unit.gd` - Added movement range logging
- `game/visuals/test_movement_system.gd` - Added F12 test
- `game/world/GameWorld.tscn` - Fixed ExtResource references

### New Files:
- `game/visuals/debug_movement_range.gd` - Standalone debug script
- `MOVEMENT_RANGE_DEBUG_GUIDE.md` - This guide

## Next Steps

1. **Run Debug Tests**: Use the debug keys to isolate the issue
2. **Check Console Output**: Look for error messages or missing components
3. **Verify Scene Setup**: Ensure all nodes are properly instantiated
4. **Test Signal Chain**: Verify GameEvents signals are being emitted and received
5. **Validate Unit Stats**: Ensure units have proper movement values

The debug tools will help identify exactly where the movement range display is failing in the chain from unit selection to tile highlighting.