extends Node

# Centralized event bus for game-wide communication
# This singleton manages all game events to reduce coupling between systems

signal unit_selected(unit: Unit, position: Vector3)
signal unit_deselected(unit: Unit)
signal unit_hover_started(unit: Unit)
signal unit_hover_ended(unit: Unit)
signal unit_moved(unit: Unit, from_position: Vector3, to_position: Vector3)
signal tile_highlighted(position: Vector3)
signal tile_unhighlighted(position: Vector3)
signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal cursor_moved(position: Vector3)
signal cursor_selected(position: Vector3)

# Movement and validation events
signal movement_range_calculated(positions: Array[Vector3])
signal movement_range_cleared()
signal movement_validated(from_position: Vector3, to_position: Vector3, is_valid: bool)

# Targeting and attack range events
signal attack_range_calculated(cells: Array)
signal aoe_preview_calculated(cells: Array)
signal targeting_cleared()

# UI events
signal ui_unit_info_requested(unit: Unit)
signal ui_action_menu_requested(unit: Unit, actions: Array)

# Combat events
signal combat_initiated(attacker: Unit, defender: Unit)
signal damage_dealt(attacker: Unit, defender: Unit, damage: int)
signal unit_eliminated(unit: Unit, eliminator: Unit)

## Fired when a unit is materialised onto the board at runtime -- pre-placed units
## at load, reinforcements, and endless/respawn waves all emit this once the node
## is in the tree at its cell. Presentation systems (camera auto-focus) listen so
## a fresh spawn can be framed for the player. `runtime` is false for the initial
## load pass and true for later waves, so the camera can skip the opening flood.
signal unit_spawned(unit, runtime: bool)

# Player management events
signal player_turn_started(player: Player)
signal player_turn_ended(player: Player)
signal player_eliminated(player: Player)
signal game_started()
signal game_ended(winner: Player)
signal unit_action_completed(unit: Unit, action_type: String)

# Traveling-hazard events (Forest Barrage and any future crawling lane hazard).
# APPENDED, never reordered -- existing signals above keep their positions. Params
# are deliberately untyped: the payloads are a TravelingHazard (a RefCounted script
# class) plus plain Arrays/int, and leaving them untyped keeps this autoload free of
# any load-order dependency on that class while letting the emitter pass it freely.
#
# hazard_spawn_requested : an effect asks the live HazardManager to adopt a freshly
#                          cast vine (the loose effect->manager seam).
# hazard_advanced        : the vine entered a new band this tick. Carries the band
#                          just entered AND the band the NEXT tick will enter, so the
#                          visual layer can TELEGRAPH where it goes -- the counterplay
#                          that makes a 5-wide undodgeable lane fair.
# hazard_expired         : the vine finished its travel and was dropped.
signal hazard_spawn_requested(hazard)
signal hazard_advanced(hazard, cells, next_cells, damage)
signal hazard_expired(hazard)

# Mind-control events (Mycothrall's infection -> control). APPENDED, never reordered.
# Params are deliberately UNTYPED (mirroring the hazard signals above): the payloads
# are Units in the live game but duck-typed mocks in tests, and leaving them untyped
# keeps this autoload emittable from a headless harness.
#
# unit_controlled          : a unit has just been hijacked (Enthralled applied) by
#                            `source` -- the UI/log can announce the betrayal begins.
# unit_acted_under_control : the hijacked `unit` was forced to strike its own ally
#                            `victim` on its turn.
signal unit_controlled(unit, source)
signal unit_acted_under_control(unit, victim)

## Fired once whenever a unit successfully performs a move (any move -- attack,
## buff, heal, status), so the visual layer can give EVERY move feedback, not just
## damaging ones. Carries the caster and the MoveResource. See UnitAnimator.
signal move_performed(caster, move)

func _ready() -> void:
	# Make this a singleton
	name = "GameEvents"
