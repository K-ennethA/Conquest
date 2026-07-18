# Overlay Visibility Debug Guide

## 🔍 **Issue Identified**

The Fire Emblem movement system is creating overlay meshes successfully (confirmed by console output), but they are not visible in the game. The debug messages show:

```
DEBUG: Creating overlay mesh at position: (0.0, 0.0, 1.0)
DEBUG: World position for overlay: (1.0, 0.1, 3.0)
DEBUG: Overlay mesh created and added to scene at (1.0, 0.1, 3.0)
```

## 🛠️ **Debug Tools Implemented**

### 1. Enhanced MovementVisualizer
- **Increased overlay height**: From 0.1 to 1.0 units above tiles
- **Solid materials**: Removed transparency to eliminate rendering issues
- **Stronger emission**: Brighter colors with emission for visibility
- **No depth test**: `no_depth_test = true` to ensure overlays appear on top
- **Additional debug output**: More detailed logging of mesh creation

### 2. Test Scripts Created

#### `test_overlay_visibility.gd`
- Creates a large, bright magenta test overlay
- Positioned high above the center of the grid
- Uses maximum visibility settings (no transparency, bright emission)
- **Test**: Press `T` key to create test overlay

#### `debug_overlay_system.gd`
- Comprehensive scene structure analysis
- Camera position and setup debugging
- Lighting environment analysis
- Material property verification
- **Tests**: Press `F10-F12` for various debug functions

### 3. Manual Test Overlays
- **F10**: Create bright yellow manual test overlay
- **F11**: List all scene nodes with positions
- **F12**: Check for existing overlay meshes

## 🎯 **Debugging Steps**

### Step 1: Verify Basic Overlay Creation
1. Run the game and select a unit
2. Check console for overlay creation messages
3. Press `F12` to verify overlays exist in scene tree

### Step 2: Test Visibility with Obvious Overlay
1. Press `T` to create bright magenta test overlay
2. If visible: Material/positioning issue with movement overlays
3. If not visible: Camera/rendering pipeline issue

### Step 3: Camera and Environment Check
1. Press `F11` to check scene structure
2. Verify camera position and angle
3. Check lighting setup

### Step 4: Manual Test Overlay
1. Press `F10` to create bright yellow overlay
2. Should be impossible to miss if rendering works

## 🔧 **Potential Issues and Solutions**

### Issue 1: Camera Angle
**Problem**: Camera looking down at tiles, overlays floating above not in view
**Solution**: Adjust camera angle or overlay height

### Issue 2: Material Transparency
**Problem**: Transparent materials not rendering correctly
**Solution**: ✅ **FIXED** - Now using solid materials with emission

### Issue 3: Overlay Height Too Low
**Problem**: Overlays too close to tiles, hidden by tile geometry
**Solution**: ✅ **FIXED** - Increased height from 0.1 to 1.0 units

### Issue 4: Depth Testing
**Problem**: Overlays hidden behind other geometry
**Solution**: ✅ **FIXED** - Set `no_depth_test = true`

### Issue 5: Scene Tree Issues
**Problem**: Overlays not properly added to scene
**Solution**: Enhanced debug logging to verify scene addition

## 📊 **Current Material Settings**

```gdscript
# Movement Range Material (Solid Blue)
albedo_color = Color(0.3, 0.7, 1.0, 1.0)  # Solid bright blue
flags_transparent = false                   # No transparency
flags_unshaded = true                      # Consistent brightness
emission_enabled = true                    # Glowing effect
emission = Color(0.5, 0.8, 1.0, 1.0)     # Bright blue glow
no_depth_test = true                       # Always on top
cull_mode = CULL_DISABLED                  # Visible from both sides
```

## 🎮 **Testing Instructions**

1. **Start the game** and wait for initialization
2. **Select a unit** - should create movement overlays
3. **Check console** for overlay creation messages
4. **Press T** - should show bright magenta test overlay
5. **Press F10** - should show bright yellow manual overlay
6. **Press F12** - lists all existing overlays in scene

## 🏁 **Expected Results**

If the system is working correctly:
- Blue overlay meshes should appear above reachable tiles when unit is selected
- Test overlays (T and F10) should be clearly visible
- Console should show successful overlay creation and positioning

## 🔍 **Next Steps Based on Results**

### If Test Overlays Are Visible
- Issue is specific to movement overlay positioning or materials
- Check grid coordinate conversion
- Verify movement overlay positions match tile locations

### If Test Overlays Are Not Visible
- Camera angle issue (overlays above camera view)
- Rendering pipeline problem
- Scene tree addition issue

### If Console Shows Errors
- Material creation problems
- Mesh instantiation issues
- Scene tree access problems

## 💡 **Quick Fixes to Try**

1. **Increase overlay height further**: Change to 2.0 or 3.0 units
2. **Make overlays larger**: Increase size from 1.2 to 2.0 or 3.0
3. **Use different colors**: Try bright red or green instead of blue
4. **Disable emission**: Test with just solid colors
5. **Change camera angle**: Look more horizontally instead of down

The debug tools should help identify exactly where the visibility issue lies and provide a clear path to resolution.