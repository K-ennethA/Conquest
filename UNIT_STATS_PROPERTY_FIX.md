# Unit Stats Property Mismatch Fix

## Error
```
Invalid access to property or key 'base_health' on a base object of type 'Resource (UnitStatsResource)'
```

## Root Cause
The `UnitStatsResource` was refactored to use new property names, but the `UnitStats` component was still trying to access the old property names:

### Old Properties (No Longer Exist):
- `base_health` → Changed to `max_health`
- `base_movement` → Changed to `movement_range`
- `base_actions` → Removed (not stored in resource)

### Missing Methods:
- `get_stat()` - Not implemented in UnitStatsResource
- `get_all_stats()` - Not implemented in UnitStatsResource
- `get_display_name()` - Not implemented in UnitStatsResource

## Solution Applied

### File: `game/units/components/UnitStats.gd`

**1. Fixed `_initialize_current_stats()` method:**
```gdscript
// OLD (BROKEN):
current_health = stats_resource.base_health
current_movement = stats_resource.base_movement
current_actions = stats_resource.base_actions

// NEW (FIXED):
current_health = stats_resource.max_health
current_movement = stats_resource.movement_range
current_actions = 1  // Default value, not stored in resource
```

**2. Fixed `_set_base_stat()` method:**
```gdscript
// OLD (BROKEN):
"health", "hp":
    stats_resource.base_health = value
"movement", "move":
    stats_resource.base_movement = value
"actions", "act":
    stats_resource.base_actions = value

// NEW (FIXED):
"health", "hp":
    stats_resource.max_health = value
"movement", "move":
    stats_resource.movement_range = value
"actions", "act":
    pass  // Not stored in resource
```

**3. Fixed `_to_string()` method:**
```gdscript
// OLD (BROKEN):
stats_resource.get_display_name()
stats_resource.base_health

// NEW (FIXED):
stats_resource.unit_name
stats_resource.max_health
```

**4. Fixed `get_debug_info()` method:**
```gdscript
// OLD (BROKEN):
"resource_name": stats_resource.get_display_name() if stats_resource else "None"

// NEW (FIXED):
"resource_name": stats_resource.unit_name if stats_resource else "None"
```

### File: `game/units/resources/UnitStatsResource.gd`

**Added missing methods:**

```gdscript
func get_stat(stat_name: String) -> int:
    """Get a specific stat value by name"""
    match stat_name.to_lower():
        "health", "hp":
            return max_health
        "attack", "atk":
            return base_attack
        "defense", "def":
            return base_defense
        "magic", "mag":
            return base_magic
        "speed", "spd":
            return base_speed
        "movement", "move":
            return movement_range
        "range":
            return attack_range
        _:
            push_warning("Unknown stat requested: " + stat_name)
            return 0

func get_all_stats() -> Dictionary:
    """Get all stats as a dictionary"""
    return {
        "health": max_health,
        "attack": base_attack,
        "defense": base_defense,
        "magic": base_magic,
        "speed": base_speed,
        "movement": movement_range,
        "range": attack_range
    }
```

## Property Mapping Reference

| Old Property | New Property | Notes |
|-------------|--------------|-------|
| `base_health` | `max_health` | Renamed for clarity |
| `base_movement` | `movement_range` | Renamed for consistency |
| `base_actions` | *(removed)* | Not stored in resource, defaults to 1 |
| `base_attack` | `base_attack` | Unchanged |
| `base_defense` | `base_defense` | Unchanged |
| `base_speed` | `base_speed` | Unchanged |
| `attack_range` | `attack_range` | Unchanged |

## Verification
All files compile without errors (verified with getDiagnostics):
- ✅ `game/units/components/UnitStats.gd`
- ✅ `game/units/resources/UnitStatsResource.gd`

## Impact
This fix resolves the runtime error when starting the game. Units can now properly initialize their stats from the UnitStatsResource.

## Testing
1. Start the game
2. Verify no "Invalid access to property" errors
3. Check that units load with correct stats
4. Verify unit stat display in UI shows correct values

## Files Modified
- `game/units/components/UnitStats.gd` - Fixed property access
- `game/units/resources/UnitStatsResource.gd` - Added missing methods
- `tile_objects/units/unit.gd` - Fixed get_display_name() call

## Additional Fix: get_display_name() Method

### File: `tile_objects/units/unit.gd`

**Fixed unit display name retrieval:**
```gdscript
// OLD (BROKEN):
return unit_stats.stats_resource.get_display_name()

// NEW (FIXED):
return unit_stats.stats_resource.unit_name
```

### File: `game/units/resources/UnitStatsResource.gd`

**Added get_display_name() method for backward compatibility:**
```gdscript
func get_display_name() -> String:
    """Get the display name for this unit (for backward compatibility)"""
    return unit_name if not unit_name.is_empty() else "Unnamed Unit"
```

This ensures any remaining code that calls `get_display_name()` on UnitStatsResource will work correctly.
