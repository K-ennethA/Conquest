extends RefCounted
class_name TravelingHazard

## One persistent, CRAWLING lane hazard -- a vine that erupts ahead of its caster
## and advances down a cardinal lane, damaging what it enters. This is the pure
## data + math for a single vine: no scene, no autoloads, so it is fully testable
## against a mock board. The live [HazardManager] owns it and ticks it forward.
##
## GEOMETRY (shared with [TargetingPattern] on purpose, so a lane's diagonal
## behaviour matches ARC/LINE exactly):
##   * [member facing] is a cardinal unit vector from [method
##     TargetingPattern._cardinal_dir] (dominant axis; a diagonal collapses to the
##     nearer clean face).
##   * width comes from the SAME perpendicular flank ARC/LINE use --
##     [code]flank = Vector2i(-facing.y, facing.x)[/code] -- so [member half_width]
##     of 2 covers flank offsets -2..+2 (a 5-wide band).
## The band at forward depth d is every cell
## [code]origin + facing*d + flank*k[/code] for k in -half_width..half_width.
##
## ADVANCE MODEL: [member front] counts rows already ENTERED (0 at cast). Each
## [method advance] moves the front forward by [member speed] rows (clamped by
## [member remaining]) and damages the units in ONLY the newly-entered rows -- a
## unit the vine has already passed is never re-hit, and a given unit takes damage
## at most once from one vine (tracked in [member _hit_units]).
##
## DAMAGE: routed through [method DamageEffect.resolve_hazard_damage] so a guarded /
## invulnerable unit takes 0 and Grovebound-style reduction applies, exactly as a
## normal hit would. [member damage] is the raw number snapshotted at CAST time. Each
## landed hit is ANNOUNCED as [code]damage_dealt[/code] before it is applied, so a vine
## kill is attributed to [member source] (while that unit is alive and on the board)
## exactly like a swing -- see [method DamageEffect.credited_source].
##
## AFFILIATION: [member affiliation] (a [enum CombatTypes.TargetKind]) decides WHO
## in the band is damaged, evaluated relative to [member source] through the shared
## [method CombatTypes.unit_matches_target_kind]: ENEMY hits only the source's foes,
## ALLY only its friends, ANY_UNIT everyone but the source. The source is excluded
## under every affiliation.

## The caster's cell -- the row just BEHIND the vine's first band (depth 0).
var origin: Vector2i
## Cardinal unit heading the lane travels along.
var facing: Vector2i
## Half the lane width in cells; the band spans flank offsets -half_width..+half_width.
var half_width: int = 2
## Rows the front advances per tick.
var speed: int = 2
## Forward rows of travel still owed. Starts at the move's travel_range; the vine
## expires once it hits 0.
var remaining: int = 6
## Raw damage per hit, snapshotted from the caster at cast time.
var damage: int = 0
## [enum CombatTypes.DamageCategory] the hit resolves as.
var category: int = CombatTypes.DamageCategory.PHYSICAL
## Who the band damages, relative to [member source] (see class docs).
var affiliation: int = CombatTypes.TargetKind.ENEMY
## The casting unit; never damaged by its own vine.
var source

## Optional event-bus override for the [code]damage_dealt[/code] announcement, mirroring
## [member MoveContext.event_bus]: null in the live game (the [code]GameEvents[/code]
## autoload is used), injected by tests and by [SpawnHazardEffect] from the cast's context.
var event_bus = null

## Rows already entered (advances forward by [member speed] each tick).
var front: int = 0
## Units this vine has already damaged, so none is hit twice as it crawls.
var _hit_units: Dictionary = {}


func _init(p_origin: Vector2i, p_facing: Vector2i, p_half_width: int, p_speed: int,
		p_travel_range: int, p_damage: int, p_category: int, p_affiliation: int, p_source) -> void:
	origin = p_origin
	facing = p_facing
	half_width = maxi(0, p_half_width)
	speed = maxi(1, p_speed)
	remaining = maxi(0, p_travel_range)
	damage = p_damage
	category = p_category
	affiliation = p_affiliation
	source = p_source
	front = 0


## The vine has finished travelling and should be dropped.
func is_expired() -> bool:
	return remaining <= 0


## The perpendicular used for width -- the SAME 90-degree rotation ARC/LINE derive
## their flank from, so the lane's diagonal behaviour matches those shapes.
func _flank() -> Vector2i:
	return Vector2i(-facing.y, facing.x)


## Every cell in the band spanning forward depths [param from_depth]..[param to_depth]
## (inclusive) across the full width.
func _band_cells(from_depth: int, to_depth: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var flank := _flank()
	for d in range(from_depth, to_depth + 1):
		for k in range(-half_width, half_width + 1):
			cells.append(origin + facing * d + flank * k)
	return cells


## The band the NEXT [method advance] will enter (empty once expired). Emitted with
## every advance so the visual layer can telegraph where the vine is heading.
func next_band_cells() -> Array[Vector2i]:
	if remaining <= 0:
		return [] as Array[Vector2i]
	var step := mini(speed, remaining)
	return _band_cells(front + 1, front + step)


## Move the front forward one tick and damage every matching unit in the rows newly
## entered. Returns event data:
##   { "cells": Array[Vector2i], "damaged": Array[{unit, amount}],
##     "next_cells": Array[Vector2i], "expired": bool }
## Damage is applied here (via [method DamageEffect.resolve_hazard_damage]); a null
## or query-less board simply enters the rows without hitting anything.
func advance(board) -> Dictionary:
	if remaining <= 0:
		return { "cells": [] as Array[Vector2i], "damaged": [], "next_cells": [] as Array[Vector2i], "expired": true }

	var step := mini(speed, remaining)
	var from_depth := front + 1
	var to_depth := front + step
	front += step
	remaining -= step

	var cells := _band_cells(from_depth, to_depth)
	var damaged: Array = []
	if board != null and board.has_method("units_at"):
		for cell in cells:
			for unit in board.units_at(cell):
				if unit == null or unit == source:
					continue
				if _hit_units.has(unit):
					continue  # a unit already passed / already hit is never re-hit
				if not CombatTypes.unit_matches_target_kind(affiliation, source, unit, board):
					continue  # spared by this vine's per-move affiliation filter
				_hit_units[unit] = true
				var dealt := DamageEffect.resolve_hazard_damage(unit, damage, category, board)
				if dealt > 0:
					# ANNOUNCE BEFORE APPLYING, for the same reason the ordinary damage
					# pipeline does: take_damage can kill outright, and the kill is
					# attributed from this signal. A vine used to mutate HP silently, so
					# an Eldroot that killed with Forest Barrage credited nobody and no
					# ON_KILL ability ever fired off it.
					DamageEffect.announce_damage(
						event_bus, DamageEffect.credited_source(source, unit, board), unit, dealt)
					if unit.has_method("take_damage"):
						unit.take_damage(dealt)
				damaged.append({ "unit": unit, "amount": dealt })

	return {
		"cells": cells,
		"damaged": damaged,
		"next_cells": next_band_cells(),
		"expired": remaining <= 0,
	}
