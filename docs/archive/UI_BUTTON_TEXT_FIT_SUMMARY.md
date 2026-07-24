# UI Button Text Fit Summary

## Problem Identified
After implementing the Speed First selection improvement, button text became longer with restriction reasons, causing buttons to overflow their containers and stick out of the UnitActionsPanel.

## Root Cause
- Button text like "Move (M) - not this unit's turn" was too long for the 200px panel width
- Fixed button heights (36px) couldn't accommodate multi-line text
- No text wrapping or overflow handling for disabled button states

## Solution Implemented

### 1. Increased Button Heights
**File**: `game/ui/UnitActionsPanel.tscn`
- Move Button: 36px → 48px height
- End Unit Turn Button: 36px → 48px height  
- End Player Turn Button: 36px → 40px height
- Panel minimum height: 180px → 220px

### 2. Reduced Font Sizes
**File**: `game/ui/UnitActionsPanel.tscn`
- Action buttons: 14px → 12px font size
- Maintains readability while allowing more text to fit

### 3. Shortened and Multi-line Text
**File**: `game/ui/UnitActionsPanel.gd`

**Before (too long):**
```
"Move (M) - not this unit's turn"
"End Unit Turn (E) - already acted this round"
```

**After (concise with newlines):**
```
"Move (M)\n[Not Turn]"
"End Turn (E)\n[Used]"
```

### 4. Consistent Abbreviations
- "Not Your Unit" → "Not Yours"
- "Not Unit's Turn" → "Not Turn"  
- "Already Acted" → "Used"
- "Unavailable" → "N/A"
- "End Unit Turn" → "End Turn" (when disabled)

## Text Mapping

### Move Button States:
- ✅ Available: `"Move (M)"`
- 🚫 Not owned: `"Move (M)\n[Not Yours]"`
- 🚫 Wrong turn: `"Move (M)\n[Not Turn]"`
- 🚫 Already used: `"Move (M)\n[Used]"`
- 🚫 Other: `"Move (M)\n[N/A]"`

### End Unit Turn Button States:
- ✅ Available: `"End Turn (E)"`
- 🚫 Not owned: `"End Turn (E)\n[Not Yours]"`
- 🚫 Wrong turn: `"End Turn (E)\n[Not Turn]"`
- 🚫 Already used: `"End Turn (E)\n[Used]"`
- 🚫 Other: `"End Turn (E)\n[N/A]"`

### End Player Turn Button States:
- ✅ Available: `"End Player Turn (P)"`
- 🚫 Not owned: `"End Player Turn (P)\n[Not Yours]"`
- 🚫 Other: `"End Player Turn (P)\n[N/A]"`

## Layout Improvements

### Container Sizing:
- Panel width: 200px (maintained)
- Panel height: 180px → 220px (increased)
- Button margins: 12px (maintained)
- Proper spacing between elements

### Visual Hierarchy:
- Main action text on first line (larger, clear)
- Restriction reason on second line (in brackets, smaller)
- Consistent formatting across all button states

## Benefits

1. **No Overflow**: All text fits within button boundaries
2. **Clear Hierarchy**: Action name prominent, restriction subtle
3. **Consistent Layout**: Same button sizes regardless of state
4. **Better UX**: Users can still see what action would do
5. **Compact Design**: Efficient use of limited panel space

## Technical Details

### Button Height Calculation:
- Line 1: Action name (12px font + padding)
- Line 2: Restriction (12px font + padding)  
- Total: ~48px height accommodates both lines comfortably

### Text Wrapping:
- Uses `\n` for explicit line breaks
- Ensures consistent formatting across all states
- Avoids reliance on automatic text wrapping

This fix ensures the UnitActionsPanel maintains a professional appearance while providing clear feedback about action availability, regardless of the turn system or unit state.