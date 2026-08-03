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

## Fired JUST BEFORE an ULTIMATE move (the signature 4th-slot ability, or any move
## flagged is_ultimate -- see [method MoveResource.is_ultimate_move]) resolves, so the
## presentation layer can sweep a full-screen cut-in banner across the display before the
## hit lands. The cast site emits this and then AWAITS the cut-in's `finished` signal, so
## the flash precedes resolution. Params are UNTYPED (mirroring move_performed) -- the
## payload is a Unit + a MoveResource in the live game but duck-typed mocks in tests, and
## leaving them untyped keeps this autoload emittable headless. See [UltimateCutIn].
signal ultimate_casting(unit, move)

## Fired ONCE for every gameplay command any actor commits -- the human FE loop, the AI
## driver, and the networked apply path all emit it through the ReplayRecorder.note_*
## statics. `cmd` is a normalised NetProtocol command dictionary and `actor_slot` is the
## player slot that issued it. APPENDED, never reordered; params are UNTYPED (mirroring
## move_performed) so a headless harness can emit it with plain dictionaries.
##
## This is the ONE seam battle replays record from: [ReplayRecorder] is the only subscriber,
## so adding a new command site costs one emit and nothing else has to know replays exist.
signal command_committed(cmd, actor_slot)

# --- Status lifecycle (presentation only) -------------------------------------
# APPENDED, never reordered. Params are UNTYPED, mirroring move_performed: the
# payloads are a Unit + a StatusCondition in the live game but duck-typed mocks in
# tests, and leaving them untyped keeps this autoload emittable headless.
#
# The status layer previously announced NOTHING, so every surface that wanted to show
# a condition had to POLL it on unrelated beats (see HealthBar's refresh-strategy
# note). These three exist so a status can be SEEN happening rather than inferred:
#
#   status_applied : a condition just landed on `unit` (the first instance only --
#                    a REFRESH of a condition already on the unit does not re-announce,
#                    so a re-applied poison does not spam a second "POISONED" shout).
#   status_ticked  : `condition` fired its per-turn effects on `unit`. `events` is the
#                    tick's own event log. Emitted immediately AFTER the tick resolved,
#                    so the damage_dealt / unit_healed the tick produced have already
#                    been announced and a listener can attribute them to this status.
#   status_expired : the condition ran out (or was cleared/consumed) and is gone.
#
# STRICTLY ADDITIVE: [StatusController] emits them and nothing in the combat layer
# reads them, so a build with no subscriber behaves exactly as it always did.
signal status_applied(unit, condition)
signal status_ticked(unit, condition, events)
signal status_expired(unit, condition)

func _ready() -> void:
	# Make this a singleton
	name = "GameEvents"
