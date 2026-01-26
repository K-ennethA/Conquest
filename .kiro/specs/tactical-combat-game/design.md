# Tactical Combat Game - Design Document

## Architecture Overview

### Core Design Principles
1. **Modularity**: Each system is a self-contained component with clear interfaces
2. **Event-Driven**: Systems communicate through signals, not direct references
3. **Data-Driven**: Game rules and content defined in resources, not hardcoded
4. **Composition Over Inheritance**: Build complex behavior from simple components
5. **Single Responsibility**: Each class/component has one clear purpose

### System Architecture

```
GameManager (Autoload)
├── PlayerManager (Component)
├── TurnSystemManager (Component)
│   ├── TraditionalTurnSystem
│   └── SpeedBasedTurnSystem
├── CombatManager (Component)
├── ActionManager (Component)
└── TerrainManager (Component)

Board (Scene Root)
├── Grid (Resource)
├── Units (Node3D)
│   └── Unit (Scene) + Components
├── Terrain (Node3D)
│   └── Tile (Scene) + Components
└── UI (CanvasLayer)
    ├── UnitInfoPanel
    ├── ActionMenu
    └── TurnOrderDisplay
```

## Component System Design

### Unit Component Architecture

```gdscript
# Base Unit Scene Structure
Unit (Node3D)
├── UnitStats (Component)
├── UnitHealth (Component)
├── UnitMovement (Component)
├── UnitCombat (Component)
├── UnitActions (Component)
├── UnitVisuals (Component)
└── MeshInstance3D
```

### Component Interfaces

#### UnitStats Component
```gdscript
class_name UnitStats
extends Node

@export var stats_resource: UnitStatsResource
@export var unit_type: UnitType

signal stat_changed(stat_name: String, old_value: int, new_value: int)

func get_stat(stat_name: String) -> int
func modify_stat(stat_name: String, amount: int) -> void
func get_all_stats() -> Dictionary
```

#### UnitHealth Component
```gdscript
class_name UnitHealth
extends Node

@export var max_health: int = 100
var current_health: int

signal health_changed(old_health: int, new_health: int)
signal unit_died(unit: Unit)
signal damage_taken(amount: int, source: Unit)

func take_damage(amount: int, source: Unit = null) -> void
func heal(amount: int) -> void
func is_alive() -> bool
```

#### UnitMovement Component
```gdscript
class_name UnitMovement
extends Node

@export var movement_range: int = 3
@export var movement_type: MovementType

signal movement_started(from: Vector3, to: Vector3)
signal movement_completed(from: Vector3, to: Vector3)
signal movement_blocked(target: Vector3, reason: String)

func can_move_to(target: Vector3) -> bool
func get_valid_moves() -> Array[Vector3]
func move_to(target: Vector3) -> void
```

## Resource-Based Configuration

### UnitStatsResource
```gdscript
class_name UnitStatsResource
extends Resource

@export var unit_name: String = ""
@export var unit_type: UnitType
@export var base_health: int = 100
@export var base_attack: int = 20
@export var base_defense: int = 10
@export var base_speed: int = 10
@export var base_movement: int = 3
@export var base_actions: int = 1
@export var abilities: Array[AbilityResource] = []
```

### UnitType Enum
```gdscript
class_name UnitType
extends Resource

enum Type {
    WARRIOR,
    ARCHER,
    SCOUT,
    TANK,
    MAGE
}

@export var type: Type
@export var display_name: String
@export var description: String
@export var movement_type: MovementType.Type
@export var attack_type: AttackType.Type
```

## Turn System Architecture

### Pluggable Turn System Interface
```gdscript
class_name TurnSystem
extends Node

signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal round_completed(round_number: int)
signal game_phase_changed(phase: GamePhase)

func initialize(units: Array[Unit]) -> void
func get_current_unit() -> Unit
func advance_turn() -> void
func can_unit_act(unit: Unit) -> bool
func get_turn_order() -> Array[Unit]
```

### Traditional Turn System
```gdscript
class_name TraditionalTurnSystem
extends TurnSystem

var _current_player: Player
var _player_units: Dictionary = {} # Player -> Array[Unit]
var _units_acted: Array[Unit] = []

func _advance_to_next_player() -> void
func _reset_player_actions() -> void
func _all_player_units_acted() -> bool
```

### Speed-Based Turn System
```gdscript
class_name SpeedBasedTurnSystem
extends TurnSystem

var _turn_queue: PriorityQueue
var _initiative_tracker: Dictionary = {} # Unit -> int

func _calculate_initiative(unit: Unit) -> int
func _rebuild_turn_queue() -> void
func _get_next_unit_from_queue() -> Unit
```

## Action System Design

### Action Framework
```gdscript
class_name Action
extends Resource

@export var action_name: String
@export var action_cost: int = 1
@export var target_type: TargetType
@export var range: int = 1
@export var requires_line_of_sight: bool = false

func can_execute(actor: Unit, target: Vector3) -> bool
func execute(actor: Unit, target: Vector3) -> ActionResult
func get_valid_targets(actor: Unit) -> Array[Vector3]
```

### Specific Action Types
```gdscript
# MoveAction.gd
class_name MoveAction
extends Action

# AttackAction.gd  
class_name AttackAction
extends Action

# AbilityAction.gd
class_name AbilityAction
extends Action
```

### Action Manager
```gdscript
class_name ActionManager
extends Node

var _available_actions: Dictionary = {} # String -> Action
var _action_history: Array[ActionResult] = []

signal action_executed(result: ActionResult)
signal action_failed(action: Action, reason: String)

func register_action(action: Action) -> void
func execute_action(action_name: String, actor: Unit, target: Vector3) -> ActionResult
func can_execute_action(action_name: String, actor: Unit, target: Vector3) -> bool
func get_available_actions(unit: Unit) -> Array[Action]
```

## Combat System Design

### Damage Calculation System
```gdscript
class_name DamageCalculator
extends RefCounted

static func calculate_damage(attacker: Unit, defender: Unit, base_damage: int) -> int:
    var attack_power = attacker.get_component(UnitStats).get_stat("attack")
    var defense_power = defender.get_component(UnitStats).get_stat("defense")
    
    var final_damage = base_damage + attack_power - defense_power
    return max(1, final_damage) # Minimum 1 damage

static func apply_modifiers(damage: int, modifiers: Array[DamageModifier]) -> int:
    for modifier in modifiers:
        damage = modifier.apply(damage)
    return damage
```

### Combat Events
```gdscript
# In GameEvents singleton
signal combat_initiated(attacker: Unit, defender: Unit)
signal damage_calculated(attacker: Unit, defender: Unit, damage: int)
signal damage_applied(defender: Unit, damage: int, remaining_health: int)
signal unit_eliminated(unit: Unit, killer: Unit)
signal combat_resolved(attacker: Unit, defender: Unit, result: CombatResult)
```

## UI System Architecture

### Component-Based UI
```gdscript
# UnitInfoPanel.gd
class_name UnitInfoPanel
extends Control

@onready var health_bar: ProgressBar = $HealthBar
@onready var stats_container: VBoxContainer = $StatsContainer
@onready var actions_container: HBoxContainer = $ActionsContainer

var _current_unit: Unit

func display_unit(unit: Unit) -> void
func _update_health_display() -> void
func _update_stats_display() -> void
func _update_actions_display() -> void
```

### Dynamic UI Updates
```gdscript
# UIManager.gd (Autoload)
class_name UIManager
extends Node

var _active_panels: Dictionary = {}

signal ui_panel_requested(panel_type: String, data: Dictionary)
signal ui_panel_closed(panel_type: String)

func show_panel(panel_type: String, data: Dictionary = {}) -> void
func hide_panel(panel_type: String) -> void
func update_panel(panel_type: String, data: Dictionary) -> void
```

## Terrain & Effect System Design

### Tile Effect Architecture

```gdscript
# Tile Scene Structure
Tile (Node3D)
├── TileStats (Component)
├── TileEffects (Component)
├── TileVisuals (Component)
├── MeshInstance3D
└── EffectVisuals (Node3D)
    ├── FireEffect (GPUParticles3D)
    ├── PoisonEffect (GPUParticles3D)
    └── IceEffect (GPUParticles3D)
```

### TileEffect Component
```gdscript
class_name TileEffect
extends Resource

@export var effect_type: EffectType
@export var intensity: float = 1.0
@export var duration: int = -1  # -1 = permanent
@export var damage_per_turn: int = 0
@export var movement_cost_modifier: float = 1.0
@export var can_spread: bool = false
@export var spread_chance: float = 0.0

signal effect_applied(unit: Unit, effect: TileEffect)
signal effect_expired(effect: TileEffect)
signal effect_spread(from_tile: Tile, to_tile: Tile)

func apply_to_unit(unit: Unit) -> void
func tick_duration() -> bool  # Returns true if effect should be removed
func can_spread_to(target_tile: Tile) -> bool
```

### TileEffects Component
```gdscript
class_name TileEffects
extends Node

var active_effects: Array[TileEffect] = []

signal effect_added(effect: TileEffect)
signal effect_removed(effect: TileEffect)
signal effects_updated()

func add_effect(effect: TileEffect) -> void
func remove_effect(effect_type: EffectType) -> void
func has_effect(effect_type: EffectType) -> bool
func get_effect(effect_type: EffectType) -> TileEffect
func process_turn_effects(unit: Unit) -> void
func get_movement_cost_modifier() -> float
```

### Effect Types
```gdscript
class_name EffectType
extends Resource

enum Type {
    FIRE,
    POISON,
    ICE,
    WATER,
    ELECTRIC,
    HEALING,
    SPEED_BOOST,
    DAMAGE_BOOST
}

@export var type: Type
@export var display_name: String
@export var description: String
@export var visual_color: Color
@export var particle_scene: PackedScene
@export var sound_effect: AudioStream
```

### Environmental Interaction System
```gdscript
class_name EnvironmentalManager
extends Node

var effect_interactions: Dictionary = {}

signal environmental_interaction(effect1: EffectType, effect2: EffectType, result: EffectType)

func register_interaction(effect1: EffectType, effect2: EffectType, result_effect: EffectType) -> void
func process_effect_interactions(tile: Tile) -> void
func spread_effects(from_tile: Tile) -> void
```

### Game Configuration
```gdscript
class_name GameConfig
extends Resource

@export var turn_system_type: TurnSystemType = TurnSystemType.TRADITIONAL
@export var battlefield_size: Vector2i = Vector2i(8, 8)
@export var victory_conditions: Array[VictoryCondition] = []
@export var player_configs: Array[PlayerConfig] = []
@export var terrain_config: TerrainConfig
```

### Save System Architecture
```gdscript
class_name GameState
extends Resource

@export var current_turn: int = 1
@export var current_player: int = 0
@export var unit_states: Array[UnitState] = []
@export var terrain_states: Array[TerrainState] = []
@export var game_config: GameConfig

func save_to_file(path: String) -> void
func load_from_file(path: String) -> GameState
```

## Event System Integration

### Core Game Events
```gdscript
# Extended GameEvents singleton
extends Node

# Turn Management
signal turn_system_changed(old_system: TurnSystem, new_system: TurnSystem)
signal player_turn_started(player: Player)
signal player_turn_ended(player: Player)

# Unit Management  
signal unit_spawned(unit: Unit, position: Vector3)
signal unit_stats_changed(unit: Unit, stat: String, old_value: int, new_value: int)
signal unit_action_performed(unit: Unit, action: Action, target: Vector3)

# Combat Events
signal combat_initiated(attacker: Unit, defender: Unit)
signal damage_dealt(attacker: Unit, defender: Unit, damage: int)
signal unit_eliminated(unit: Unit, eliminator: Unit)

# UI Events
signal unit_selection_changed(old_unit: Unit, new_unit: Unit)
signal action_menu_requested(unit: Unit, available_actions: Array[Action])
signal game_state_changed(new_state: GameState)
```

## Testing Strategy

### Unit Testing Approach
```gdscript
# Example: test_damage_calculator.gd
extends GutTest

func test_basic_damage_calculation():
    var attacker = create_test_unit({"attack": 20})
    var defender = create_test_unit({"defense": 5})
    
    var damage = DamageCalculator.calculate_damage(attacker, defender, 10)
    assert_eq(damage, 25, "Damage should be base + attack - defense")

func test_minimum_damage():
    var attacker = create_test_unit({"attack": 1})
    var defender = create_test_unit({"defense": 20})
    
    var damage = DamageCalculator.calculate_damage(attacker, defender, 5)
    assert_eq(damage, 1, "Minimum damage should be 1")
```

### Integration Testing
```gdscript
# Example: test_turn_system_integration.gd
extends GutTest

func test_traditional_turn_system_flow():
    var turn_system = TraditionalTurnSystem.new()
    var units = create_test_units_for_two_players()
    
    turn_system.initialize(units)
    
    # Test full turn cycle
    for i in range(units.size()):
        var current_unit = turn_system.get_current_unit()
        assert_not_null(current_unit, "Should have current unit")
        turn_system.advance_turn()
```

## Phase 1 Implementation Plan

### 1.1 Enhanced Unit Stats System
- Create UnitStatsResource and UnitStats component
- Implement stat modification and event system
- Create unit type definitions and configurations
- Add visual stat display in UI

### 1.2 Player Management System
- Create Player and PlayerManager classes
- Implement team assignment and unit ownership
- Add player turn tracking and validation
- Create player-specific UI elements

### 1.3 Traditional Turn System
- Implement TurnSystem base class and interface
- Create TraditionalTurnSystem implementation
- Integrate with existing board and unit systems
- Add turn transition animations and feedback

### 1.4 Movement Validation Enhancement
- Refactor movement system into UnitMovement component
- Add movement type support (ground, flying, etc.)
- Implement advanced pathfinding with obstacles
- Add movement preview and validation feedback

## Correctness Properties

### Property 1: Turn System Consistency
**Validates: Requirements 2.1, 2.2**
For any valid game state, exactly one unit should have an active turn, and turn advancement should always result in a valid next unit or end of round.

### Property 2: Unit Stat Integrity  
**Validates: Requirements 3.1, 3.2**
Unit stats should never exceed defined bounds, and stat modifications should always trigger appropriate events and UI updates.

### Property 3: Movement Validation
**Validates: Requirements 4.1, 4.2**
Units should only be able to move to valid positions within their movement range, and invalid moves should be consistently rejected with appropriate feedback.

### Property 4: Action Point Conservation
**Validates: Requirements 3.1, 6.2**
The total action points consumed by a unit in a turn should never exceed their maximum action points, and action availability should be correctly reflected in the UI.

### Property 5: Player Ownership Consistency
**Validates: Requirements 1.1, 1.2**
Players should only be able to control their own units, and unit ownership should remain consistent throughout the game unless explicitly transferred.

### Property 6: Tile Effect Consistency (Phase 4)
**Validates: Requirements 7.1, 7.2, 7.3**
Tile effects should be applied consistently to all units that interact with affected tiles, effect durations should be tracked accurately, and effect interactions should follow defined rules without creating invalid states.

## Implementation Notes

### Godot-Specific Considerations
- Use `@export` variables for designer-configurable values
- Leverage Godot's scene system for modular unit composition
- Utilize Resource system for data-driven configuration
- Implement proper signal cleanup in `_exit_tree()`
- Use `class_name` declarations for all major classes

### Performance Optimizations
- Object pooling for frequently created/destroyed objects
- Efficient pathfinding with A* algorithm
- Batch UI updates to avoid frame drops
- Lazy loading of unit abilities and effects

### Extensibility Hooks
- Plugin system for custom unit types
- Scriptable ability system using GDScript
- Modular terrain effect system
- Configurable victory condition framework