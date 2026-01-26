# UI Layout Guide

## Current UI Element Positions (Clean & Minimal)

### TOP ROW
- **UnitInfoPanel**: (20, 20) to (320, 300) - 300x280 pixels
  - Shows ONLY unit statistics (name, type, health, attack, defense, speed, movement, range)
  - Clean, stats-focused display with unit portrait
  - Always visible on top-left

- **TurnIndicator**: (1670, 20) to (1900, 100) - 230x80 pixels  
  - Shows current player and turn transitions
  - Top-right corner

### MIDDLE ROW
- **UnitActionsPanel**: (1700, 120) to (1900, 300) - 200x180 pixels
  - Unit-specific actions (Move, End Unit Turn, Cancel)
  - Clean button layout with no help text
  - Only visible when unit is selected
  - Right side, below TurnIndicator

### BOTTOM ROW
- **PlayerTurnPanel**: (340, 960) to (620, 1060) - 280x100 pixels
  - Player turn management (End Player Turn)
  - Bottom-center

## Removed Elements
- ❌ **TurnSystemIndicator**: Removed entirely (was showing debug info like "Traditional Turn System", "Current Player", etc.)
- ❌ **Help text**: Removed from UnitActionsPanel
- ❌ **Instructions**: Removed from UnitInfoPanel

## Key Features
- **Ultra Clean**: No metadata, debug info, or instructional text
- **Pure Functionality**: Each panel shows only essential information
- **No Overlapping**: All elements have dedicated, non-overlapping spaces
- **Minimal UI**: Focus on gameplay, not UI clutter
- **Contextual**: UnitActionsPanel only appears when needed

## Debug Keys
- L: Check UI layout and positions
- I: Test UI separation