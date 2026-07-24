# Smart Grid Toggle System

## 🎯 **Enhanced Grid Behavior**

The map grid now has intelligent visibility that prioritizes strategic gameplay:

### **Grid Visibility Rules**
1. **Default**: Grid is visible when game starts
2. **User Toggle Off**: Player can hide grid with F1/-
3. **Unit Selection Override**: Grid automatically shows when unit is selected (even if toggled off)
4. **Unit Deselection**: Grid returns to user preference

## 🧠 **Smart Logic**

### **State Tracking**
```gdscript
var grid_visible: bool = true          # Current visibility state
var user_toggled_off: bool = false     # User manually turned off grid
var unit_selected: bool = false        # Unit currently selected
```

### **Visibility Decision**
```gdscript
should_show_grid = not user_toggled_off OR unit_selected
```

## 🎮 **User Experience Scenarios**

### **Scenario 1: Normal Usage**
1. Game starts → Grid visible ✅
2. Player toggles off (F1) → Grid hidden ❌
3. Player selects unit → Grid shows automatically ✅ (for strategy)
4. Player deselects unit → Grid hidden again ❌ (respects user preference)

### **Scenario 2: Grid Always On**
1. Game starts → Grid visible ✅
2. Player selects unit → Grid stays visible ✅
3. Player deselects unit → Grid stays visible ✅

### **Scenario 3: Strategic Override**
1. Player toggles grid off → Grid hidden ❌
2. Player selects unit → Grid shows ✅ (strategic planning needed)
3. Player moves unit → Grid stays visible ✅ (during movement)
4. Player deselects → Grid hidden ❌ (back to user preference)

## 🎛️ **Controls**

### **Grid Toggle Controls**
- **F1**: Toggle grid on/off (user preference)
- **+ (Plus)**: Force grid on
- **- (Minus)**: Set user preference to off (but shows during unit selection)

### **Automatic Behavior**
- **Select Unit**: Grid automatically appears (strategic planning)
- **Deselect Unit**: Grid returns to user preference
- **Movement Planning**: Grid stays visible during entire unit selection

## 🔧 **Technical Implementation**

### **Event Connections**
```gdscript
GameEvents.unit_selected.connect(_on_unit_selected)
GameEvents.unit_deselected.connect(_on_unit_deselected)
```

### **Smart Update Logic**
```gdscript
func _update_grid_visibility():
    var should_show = not user_toggled_off or unit_selected
    if should_show != grid_visible:
        if should_show: show_grid()
        else: hide_grid()
```

## 🎯 **Strategic Benefits**

### **For Players**
- **Flexible Control**: Can hide grid when not needed
- **Strategic Support**: Grid always available during unit selection
- **No Interruption**: Smooth gameplay without manual grid toggling
- **Visual Clarity**: Grid appears exactly when strategic planning is needed

### **For Gameplay**
- **Enhanced Planning**: Full map grid during movement decisions
- **Reduced Clutter**: Grid hidden when not strategically relevant
- **Intuitive Behavior**: Grid appears when you need it most
- **Professional Feel**: Smart UI that anticipates player needs

## 📊 **Behavior Matrix**

| User Preference | Unit Selected | Grid Visible | Reason |
|----------------|---------------|--------------|---------|
| On | No | ✅ Yes | User wants grid |
| On | Yes | ✅ Yes | User wants grid |
| Off | No | ❌ No | User preference |
| Off | Yes | ✅ Yes | Strategic override |

## 🔍 **Debug Information**

Console output shows current state:
```
MapGridVisualizer: Unit selected - ensuring grid is visible
Grid state - Visible: true, User toggled off: true, Unit selected: true
MapGridVisualizer: Unit deselected - returning to user preference
```

## 🏁 **Expected User Experience**

### **Casual Play**
- Grid visible by default for easy positioning
- Can be hidden if player finds it distracting
- Automatically appears during tactical decisions

### **Strategic Play**
- Grid always available when planning moves
- Full battlefield visibility during unit selection
- Seamless transition between grid states

### **Professional Feel**
- Smart UI that anticipates player needs
- No manual grid management during combat
- Focus on strategy, not interface management

## ✅ **Testing Scenarios**

1. **Start game** → Grid should be visible
2. **Press F1** → Grid should hide
3. **Select unit** → Grid should appear automatically
4. **Deselect unit** → Grid should hide again
5. **Press F1 again** → Grid should show and stay visible
6. **Select/deselect unit** → Grid should stay visible (user preference)

The smart grid toggle system provides the perfect balance of user control and strategic support!