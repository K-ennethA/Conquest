# Transparent Tile Grid System

## 🎯 **New Grid Approach**

Completely redesigned the grid system to use **transparent tiles with border lines** instead of just lines, exactly as requested:

### **Full Map Grid (MapGridVisualizer)**
- **Transparent tiles** covering entire 5×5 map
- **White border lines** around each tile
- **Always visible** (toggleable with F1)
- **Smart visibility** - shows when unit selected even if toggled off

### **Movement Range Highlighting**
- **Same transparent tiles** for entire map when unit selected
- **Blue tiles** for movement range positions
- **White tiles** for non-movement positions
- **Border lines** around all tiles for clear separation

## 🏗️ **System Architecture**

### **MapGridVisualizer.gd (NEW)**
```gdscript
# Creates 25 transparent tiles (5×5 grid)
# Each tile has 4 border lines (top, bottom, left, right)
# Total: 25 tiles + 100 border lines = 125 mesh instances

# Materials:
- normal_tile_material: Very transparent white (10% opacity)
- movement_tile_material: Blue transparent (40% opacity)
```

### **MovementVisualizer.gd (SIMPLIFIED)**
```gdscript
# Now only handles blue overlay meshes
# Grid system moved to MapGridVisualizer
# Cleaner, focused responsibility
```

## 🎨 **Visual Layers**

```
Height Levels (from bottom to top):
0.00 - Ground/Original Tiles
0.30 - Transparent Grid Tiles (white/blue)
0.31 - Grid Border Lines (white)
1.00 - Blue Movement Overlays (from MovementVisualizer)
```

## 🎮 **User Experience**

### **Normal State**
- **Transparent white tiles** with white borders across entire map
- **Subtle but visible** grid for strategic planning
- **Can be toggled off** with F1 key

### **Unit Selection**
- **Entire map** shows transparent tiles with borders
- **Blue tiles** highlight movement range
- **White tiles** show non-reachable positions
- **Clear visual distinction** between reachable/non-reachable

### **Smart Visibility**
- **Always shows** when unit is selected (even if toggled off)
- **Returns to user preference** when unit deselected
- **Strategic override** ensures grid available for planning

## 🔧 **Technical Implementation**

### **Tile Creation**
```gdscript
# For each grid position (5×5 = 25 tiles):
1. Create PlaneMesh (2×2 units to match actual tiles)
2. Apply transparent material
3. Position at grid center + 0.3 height
4. Create 4 border lines around tile edges
5. Add all to scene
```

### **Material Switching**
```gdscript
# When movement range calculated:
for each tile:
    if position in movement_range:
        tile.material = movement_tile_material  # Blue
    else:
        tile.material = normal_tile_material    # White
```

### **Event Integration**
```gdscript
# Connected to GameEvents:
- unit_selected → ensure grid visible
- unit_deselected → return to user preference  
- movement_range_calculated → highlight blue tiles
- movement_range_cleared → return to white tiles
```

## 🎛️ **Controls**

- **F1**: Toggle grid on/off (user preference)
- **+ (Plus)**: Force grid on
- **- (Minus)**: Set preference to off (still shows during unit selection)

## 📊 **Performance**

### **Mesh Count**
- **25 transparent tiles** (one per grid position)
- **100 border lines** (4 per tile)
- **Total: 125 mesh instances** for full map grid
- **Additional: Blue overlays** from MovementVisualizer

### **Memory Usage**
- **Lightweight**: Simple PlaneMesh and BoxMesh instances
- **Efficient**: Reuses materials across all tiles
- **Optimized**: No shadows, unshaded materials

## 🎯 **Visual Result**

### **Full Map Grid**
- **Transparent white tiles** with white borders
- **Complete grid coverage** of battlefield
- **Strategic planning** enhanced with full visibility
- **Professional appearance** matching tactical RPGs

### **Movement Range**
- **Blue transparent tiles** for reachable positions
- **White transparent tiles** for non-reachable positions
- **Complete map context** during movement planning
- **Clear distinction** between movement options

## ✅ **Testing**

1. **Start game** → Transparent white grid appears across map
2. **Press F1** → Grid toggles off/on
3. **Select unit** → Grid shows (even if toggled off), blue tiles for movement
4. **Deselect unit** → Grid returns to user preference
5. **Movement planning** → Full map context with blue highlights

## 🏁 **Achievement**

Successfully implemented the exact system requested:
- ✅ **Full map grid** with transparent tiles and lines
- ✅ **Toggleable visibility** with smart override
- ✅ **Unit selection** shows entire map with blue movement tiles
- ✅ **Professional Fire Emblem appearance**
- ✅ **Strategic planning** enhanced with complete battlefield visibility

The transparent tile grid system provides the perfect balance of strategic information and visual clarity!