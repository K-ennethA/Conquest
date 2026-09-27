extends Node

# Centralized event bus for game-wide communication
# This singleton manages all game events to reduce coupling between systems
#
# Cell-carrying signals below (unit_moved, cursor_moved, movement_range_calculated,
# attack_range_calculated, aoe_preview_calculated, ...) pass GRID coords
# Vector3(col, FLOOR, row) -- y is the floor index (0 = ground), not a world height.
# Convert with Cells.from_grid() / Cells.to_grid() (game/board/Cells.gd).

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

## Fired when a unit regains HP (a heal move, lifesteal, a healing tile/status).
## `amount` is the HP actually restored (>= 0). Presentation systems listen to
## flash the unit green, play a heal cue, and frame it, so healing reads as
## clearly as damage does. The single emit point is HealEffect.
signal unit_healed(unit, amount: int)

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

# Fire-Emblem board readouts. APPENDED, never reordered. Cells are grid coords
# Vector3(col, floor, row) like the other overlay signals.
#
# attack_fringe_calculated : red cells a selected/inspected unit could ATTACK but
#                            not move to, drawn around its blue movement range.
#                            Cleared with movement_range_cleared / a recalculation.
# path_preview_updated     : the route [origin .. hovered cell] the selected unit
#                            would walk; [] hides the path arrow.
# danger_zone_changed      : the combined enemy threat overlay was toggled/refreshed
#                            (active, number of cells) -- for HUD hints.
signal attack_fringe_calculated(cells: Array)
signal path_preview_updated(cells: Array)
signal danger_zone_changed(active: bool, cell_count: int)

## Multi-floor VIEW FLOOR (APPENDED). The board cursor owns it: floors above
## `view_floor` are cut away (faded) so units under a bridge / inside a castle are
## visible. `cut_floor` is the floor actually cut to (it can sit BELOW view_floor
## when the cursor or the selected unit is under a deck -- the auto cutaway);
## `floor_count` is the board's floor total (1 on a classic flat map).
signal view_floor_changed(view_floor: int, cut_floor: int, floor_count: int)

## A move RESOLVED from [param origin_cell] at [param aim_cell] (both Vector3i board
## cells), hitting [param targets] (the units standing in its area when it was cast,
## caster excluded). APPENDED. Fired by Unit.perform_move just before move_performed,
## on every path (player, AI, network apply). Presentation only -- FacingController
## turns the caster toward the aim and the targets toward the caster. Untyped for
## the same reason as the hazard / control signals above.
signal move_aimed(caster, move, origin_cell, aim_cell, targets)

func _ready() -> void:
	# Make this a singleton
	name = "GameEvents"
