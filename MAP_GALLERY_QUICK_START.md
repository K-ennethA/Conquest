# Map Selection Gallery - Quick Start Guide

## What Was Built

A visual map selection gallery that displays maps with image previews and names, making map selection intuitive and visually appealing.

## Quick Setup (3 Steps)

### Step 1: Generate Previews for Existing Maps
```
1. Open Godot Editor
2. File → Run
3. Select: game/maps/generate_map_previews.gd
4. Wait for "Preview Generation Complete" message
```

**Result**: Preview images created in `game/maps/previews/`

### Step 2: Test the Gallery
```
1. Create a test scene
2. Add Node → User Interface → VBoxContainer
3. Attach script: game/ui/MapSelectorPanel.gd
4. In Inspector, set:
   - gallery_mode = true
   - preview_size = (200, 150)
   - columns = 3
5. Run scene
```

**Result**: Visual gallery showing all maps with previews

### Step 3: Integrate into Multiplayer Lobby
```
See: game/ui/MapSelectorPanel_Integration_Example.gd
```

## Display Modes

### Gallery Mode (Visual)
```gdscript
var map_selector = MapSelectorPanel.new()
map_selector.gallery_mode = true
map_selector.preview_size = Vector2(200, 150)
map_selector.columns = 3
```

**Shows**: Grid of map cards with images and names

### Dropdown Mode (Compact)
```gdscript
var map_selector = MapSelectorPanel.new()
var map_selector.compact_mode = true
```

**Shows**: Traditional dropdown list

## Key Features

✅ **Visual Previews**: See map layout before selecting
✅ **Interactive Cards**: Click to select
✅ **Auto-Generated**: Script creates previews automatically
✅ **Dual Modes**: Gallery or dropdown
✅ **Modular**: Works anywhere in your UI
✅ **Configurable**: Many customization options

## File Locations

**Component:**
- `game/ui/MapSelectorPanel.gd` - Main component
- `game/ui/MapSelectorPanel.tscn` - Scene file

**Preview System:**
- `game/maps/MapPreviewGenerator.gd` - Preview generator
- `game/maps/generate_map_previews.gd` - Batch script
- `game/maps/previews/` - Generated preview images

**Documentation:**
- `MAP_SELECTION_GALLERY_IMPLEMENTATION.md` - Full details
- `game/ui/MapSelectorPanel_Integration_Example.gd` - Integration guide

## Usage in Code

### Basic Usage:
```gdscript
# Load and add to scene
var map_selector = preload("res://game/ui/MapSelectorPanel.tscn").instantiate()
map_selector.map_changed.connect(_on_map_selected)
add_child(map_selector)

func _on_map_selected(map_path: String, map_resource: MapResource) -> void:
	print("Selected: " + map_resource.map_name)
	GameSettings.set_selected_map(map_path)
```

### For Multiplayer Lobby:
```gdscript
# Compact dropdown mode
var map_selector = preload("res://game/ui/MapSelectorPanel.tscn").instantiate()
map_selector.compact_mode = true
map_selector.show_title = false
map_selector.map_changed.connect(_on_lobby_map_selected)
lobby_container.add_child(map_selector)
```

## Preview Generation

### For All Maps:
```
Run: game/maps/generate_map_previews.gd in editor
```

### For Single Map:
```gdscript
var preview_path = MapPreviewGenerator.generate_and_save_preview(map_resource)
map_resource.preview_image_path = preview_path
ResourceSaver.save(map_resource, map_path)
```

## Customization

### Change Preview Size:
```gdscript
map_selector.preview_size = Vector2(150, 100)  # Smaller
map_selector.preview_size = Vector2(300, 225)  # Larger
```

### Change Grid Columns:
```gdscript
map_selector.columns = 2  # Fewer columns
map_selector.columns = 4  # More columns
```

### Toggle Elements:
```gdscript
map_selector.show_title = false
map_selector.show_description = false
map_selector.show_details = false
```

## Visual Preview

### Gallery Mode:
```
┌──────────────────────────────────┐
│      Map Selection:              │
├──────────────────────────────────┤
│  ┌────────┐  ┌────────┐         │
│  │[Image] │  │[Image] │         │
│  │ Map 1  │  │ Map 2  │         │
│  │  5x5   │  │  7x7   │         │
│  └────────┘  └────────┘         │
├──────────────────────────────────┤
│  Description: A basic 5x5 map... │
└──────────────────────────────────┘
```

### Dropdown Mode:
```
┌──────────────────────────────────┐
│      Map Selection:              │
│  ┌────────────────────────────┐ │
│  │ Default Skirmish (5x5)  ▼ │ │
│  └────────────────────────────┘ │
└──────────────────────────────────┘
```

## Status: ✅ READY TO USE

Everything is implemented and ready:
- ✅ Gallery component created
- ✅ Preview generator working
- ✅ Batch generation script ready
- ✅ Integration examples provided
- ✅ Full documentation available

**Next**: Run preview generation script and integrate into your UI!
