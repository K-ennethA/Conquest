# Full Map Grid Enhancement

## 🎯 **Enhancement Goal**

Extend the grid lines to cover the entire map permanently, making it easier for players to think about strategic positioning and plan future moves beyond just the current movement range.

## 🏗️ **Two-Layer Grid System**

### Layer 1: Permanent Map Grid (NEW)
- **MapGridVisualizer.gd** - New dedicated system
- **Covers entire 5x5 map** with subtle grid lines
- **Always visible** for strategic planning
- **Low opacity (30%)** to not interfere with gameplay
- **Ground level positioning** (0.05 units high)

### Layer 2: Movement Range Grid (ENHANCED)
- **MovementVisualizer.gd** - Enhanced existing system
- **Covers highlighted movement tiles** only
- **Appears with unit selection** 
- **High opacity (90%)** for clear movement indication
- **Above overlay positioning** (1.1 units high)

## 🎨 **Visual Hierarchy**

```
Height Levels (from bottom to top):
0.00 - Ground/Tiles
0.05 - Permanent Map Grid (subtle white lines)
1.00 - Blue Movement Overlays
1.10 - Movement Range Grid (bright white lines)
```

## 🔧 **Technical Implementation**

### MapGridVisualizer Features
```gdscript
# Permanent grid settings
grid_line_height: 0.05      # Just above ground
grid_line_width: 0.03       # Thin, subtle lines
grid_line_opacity: 0.3      # Low opacity (30%)

# Full map coverage
Creates (grid_width + 1) × (grid_height + 1) lines
For 5×5 grid: 6 horizontal + 6 vertical = 12 total lines
```

### Enhanced MovementVisualizer
```gdscript
# Movement range grid settings  
grid_line_height: 1.1       # Above blue overlays
grid_line_width: 0.08       # Slightly thicker
movement_grid_opacity: 0.9  # High opacity (90%)

# Bright white with strong emission for visibility
```

## 🎮 **User Experience**

### Permanent Strategic Grid
- **Always visible** subtle white grid across entire map
- **Helps with positioning** units and planning moves
- **Non-intrusive** - low opacity doesn't distract
- **Strategic planning** - see all possible positions at a glance

### Enhanced Movement Range
- **Bright white grid** around movement tiles
- **Clear distinction** from permanent grid
- **Easy identification** of reachable spaces
- **Professional appearance** with layered grid system

## 🧪 **Testing & Controls**

### Automatic Features
- **Map grid** appears automatically when scene loads
- **Movement grid** appears when unit is selected
- **Both systems** work independently

### Manual Controls
- **Press `M`** - Toggle permanent map grid on/off
- **Press `G`** - Test movement range grid
- **Press `T`** - Basic overlay visibility test

### Debug Output
```
MapGridVisualizer: Initializing full map grid
MapGridVisualizer: Created 12 grid lines for full map
MovementVisualizer: Created 6 overlay meshes with grid lines
```

## 📊 **Grid Specifications**

### Permanent Map Grid
- **Coverage**: Entire 5×5 map (10×10 world units)
- **Lines**: 6 horizontal + 6 vertical = 12 total
- **Material**: White, 30% opacity, subtle glow
- **Position**: Ground level (0.05 units)
- **Purpose**: Strategic planning and positioning

### Movement Range Grid  
- **Coverage**: Only highlighted movement tiles
- **Lines**: Dynamic based on movement range
- **Material**: White, 90% opacity, strong glow
- **Position**: Above overlays (1.1 units)
- **Purpose**: Clear movement indication

## 🎯 **Strategic Benefits**

### For Players
- **Better planning** - see entire battlefield grid
- **Easier positioning** - understand unit placement options
- **Strategic thinking** - visualize future move possibilities
- **Professional feel** - polished tactical game appearance

### For Gameplay
- **Clearer movement** - bright grid around reachable tiles
- **Better visibility** - layered system prevents confusion
- **Enhanced UX** - Fire Emblem-style grid system
- **Tactical depth** - easier to plan multi-turn strategies

## 🔄 **System Integration**

### Scene Structure
```
GameWorld
├── MapGridVisualizer (permanent grid)
├── MovementVisualizer (movement range grid)
├── Units (positioned on grid)
└── Tiles (aligned with grid)
```

### Coordinate Alignment
- **Map grid** aligns perfectly with tile boundaries
- **Movement grid** aligns with movement overlays
- **Both systems** use same Grid resource for consistency
- **No conflicts** between permanent and temporary grids

## 🏁 **Expected Result**

When the game runs:

1. **Permanent grid** appears across entire map (subtle)
2. **Select unit** → Blue overlays + bright movement grid appear
3. **Strategic planning** enhanced with full map visibility
4. **Clear movement indication** with layered grid system
5. **Professional appearance** matching tactical RPG standards

## 💡 **Future Enhancements**

The dual-grid system enables:
- **Different grid colors** for different game modes
- **Animated grids** for special effects
- **Grid opacity controls** in game settings
- **Terrain-based grid styling** 
- **Multi-layer tactical overlays**

## ✅ **Testing Checklist**

- [ ] Permanent grid appears on game start
- [ ] Grid covers entire 5×5 map
- [ ] Grid lines are subtle but visible
- [ ] Movement range grid appears on unit selection
- [ ] Movement grid is brighter than permanent grid
- [ ] Press `M` toggles permanent grid
- [ ] Both grids align perfectly with tiles
- [ ] No performance issues with dual grid system

The full map grid enhancement significantly improves strategic gameplay and visual polish!