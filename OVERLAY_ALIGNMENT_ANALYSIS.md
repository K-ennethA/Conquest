# Overlay Alignment Analysis

## 🔍 **Coordinate System Analysis**

### Tile System (from GameWorld.tscn)
```
Tile_0_0: Transform3D(2, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0)  -> World pos (0, 0, 0)
Tile_1_0: Transform3D(2, 0, 0, 0, 1, 0, 0, 0, 2, 2, 0, 0)  -> World pos (2, 0, 0)
Tile_2_0: Transform3D(2, 0, 0, 0, 1, 0, 0, 0, 2, 4, 0, 0)  -> World pos (4, 0, 0)
Tile_0_1: Transform3D(2, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 2)  -> World pos (0, 0, 2)
Tile_1_1: Transform3D(2, 0, 0, 0, 1, 0, 0, 0, 2, 2, 0, 2)  -> World pos (2, 0, 2)
```

**Key Observations:**
- Tiles are **scaled 2x2** (first and third values in transform)
- Tiles are **positioned at even world coordinates** (0, 2, 4, 6, 8)
- Each tile is **2 units wide by 2 units deep**

### Grid System (from grid.gd)
```gdscript
size = Vector3(5, 0, 5)        # 5x5 grid
cell_size = Vector3(2, 0, 2)   # Each cell is 2x2 units
_half_cell_size = Vector3(1, 0, 1)  # Half cell = 1x1 units

calculate_map_position(grid_pos) = grid_pos * cell_size + _half_cell_size
```

**Grid to World Conversion:**
- Grid (0,0,0) -> World (0*2+1, 0, 0*2+1) = **(1, 0, 1)**
- Grid (1,0,0) -> World (1*2+1, 0, 0*2+1) = **(3, 0, 1)**
- Grid (0,0,1) -> World (0*2+1, 0, 1*2+1) = **(1, 0, 3)**

## ❌ **The Problem**

**Tile Centers vs Grid Calculation:**
- **Tile_0_0** is at world position **(0, 0, 0)** but its **center** is at **(1, 0, 1)**
- **Grid calculation** puts overlays at **(1, 0, 1)** - the tile center
- **This is actually CORRECT** - overlays should be at tile centers

**Size Mismatch (FIXED):**
- ✅ **Tiles**: 2x2 units (scaled by transform)
- ✅ **Overlays**: Now 2x2 units (updated overlay_size to 2.0)

## 🎯 **Expected Behavior**

The overlays **should** be positioned at tile centers, not tile origins:

| Grid Position | Tile Name | Tile Origin | Tile Center | Overlay Position |
|---------------|-----------|-------------|-------------|------------------|
| (0,0,0)       | Tile_0_0  | (0,0,0)     | (1,0,1)     | (1,0,1) ✅       |
| (1,0,0)       | Tile_1_0  | (2,0,0)     | (3,0,1)     | (3,0,1) ✅       |
| (0,0,1)       | Tile_0_1  | (0,0,2)     | (1,0,3)     | (1,0,3) ✅       |

## 🧪 **Testing Tools**

### Press `A` Key - Tile Alignment Test
Creates colored overlays at known positions:
- **Red overlay** at grid (0,0,0) -> should center on Tile_0_0
- **Green overlay** at grid (1,0,0) -> should center on Tile_1_0  
- **Blue overlay** at grid (2,0,1) -> should center on Tile_2_1

### Debug Output
Enhanced MovementVisualizer now shows:
```
DEBUG: Grid->World conversion: (0, 0, 0) -> (1, 0, 1)
DEBUG: Grid cell_size: (2, 0, 2)
DEBUG: Grid _half_cell_size: (1, 0, 1)
DEBUG: Overlay size: (2, 2)
```

## 🔧 **Changes Made**

1. **Fixed Overlay Size**: Changed from 1.2x1.2 to 2.0x2.0 to match tile size
2. **Added Debug Output**: Shows grid-to-world conversion details
3. **Added Alignment Test**: Press `A` to test overlay positioning
4. **Enhanced Logging**: More detailed coordinate conversion info

## 🎮 **Testing Instructions**

1. **Run the game** and select a unit to see movement overlays
2. **Press `A`** to create alignment test overlays
3. **Check console** for coordinate conversion details
4. **Verify alignment**: Overlays should be centered on tiles, not at tile corners

## 💡 **If Overlays Still Don't Align**

The issue might be:

1. **Unit position calculation** - Units might be reporting wrong grid positions
2. **BFS pathfinding** - Movement range calculation might use wrong coordinates
3. **Grid coordinate system** - Mismatch between unit positions and grid system

**Next debugging step**: Check what grid positions the BFS algorithm is calculating and compare with actual unit positions.

## 🏁 **Expected Result**

After these fixes:
- ✅ Overlays should be **2x2 units** (same size as tiles)
- ✅ Overlays should be **centered on tiles**
- ✅ Blue overlays should appear exactly over reachable tiles
- ✅ Fire Emblem movement should work perfectly

The coordinate system is actually working correctly - overlays at tile centers is the right behavior!