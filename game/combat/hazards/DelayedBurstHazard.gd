extends RefCounted
class_name DelayedBurstHazard

## One STATIONARY, fused hazard -- a marked patch of ground that sits telegraphed for a
## turn and then ERUPTS once, damaging whatever is standing in it (Monster's Abyssal
## Maw). The sibling of [TravelingHazard]: same pure data + math, no scene and no
## autoloads, so it is fully testable against a mock board.
##
## HOW IT DIFFERS FROM A VINE, and why it is its own class rather than a mode on that
## one. A [TravelingHazard] is defined by MOTION -- an origin, a facing, a width, a
## front that crawls -- and every one of those fields is meaningless here. More
## importantly the two answer to different CLOCKS: a vine advances on the active turn
## system's every turn_started (any side's), while a maw must erupt at the start of the
## CASTER's next turn specifically. So the fuse does not live here at all; it lives on a
## [DelayedBurstStatus] planted on the caster, which the shared per-unit turn-start tick
## ([method TurnSystemBase._tick_unit_turn_start]) expires at exactly that moment in
## BOTH turn systems (CONQUEST.md rule 2). This class owns only the geometry and the
## blast.
##
## DAMAGE is [method DamageEffect.resolve_hazard_damage] -- i.e.
## [method DamageMath.environment_damage], the shared environmental chain -- exactly as
## a vine's band hit is. So a guarded/invulnerable occupant takes a hard 0, the
## defender's own damage_taken_scale applies (a BRANDED unit eats the maw harder), and
## the maw's own [member element] is matched against the victim's through the same chart
## a direct hit would use. [member damage] is the raw number SNAPSHOTTED at cast time, so
## a buff landing on the caster while the fuse burns cannot retune an already-marked maw
## -- the same freeze rule a vine's damage follows, and what keeps it lockstep-safe.
##
## IT ALWAYS LANDS: no accuracy roll, no evasion term, no crit, and NOTHING drawn from
## any generator. Erupting is not a swing -- it is the ground opening under you -- which
## is the same rule tile damage and status ticks follow, and it is what makes a replay
## resolve the eruption identically to the live match.
##
## AFFILIATION works exactly as a vine's: [member affiliation] (a
## [enum CombatTypes.TargetKind]) is evaluated relative to [member source] through the
## shared [method CombatTypes.unit_matches_target_kind], and the source is excluded under
## every affiliation -- you never bite yourself.
##
## OCCUPANTS ONLY, AT DETONATION TIME. The cells are frozen at cast; who is standing in
## them is read when it goes off. Stepping out of the telegraph is the counterplay, and
## stepping IN is a mistake the player is allowed to make.

## Every cell the marked patch covers, frozen at cast time (the move's resolved area).
var cells: Array[Vector2i] = []
## Raw damage per occupant, snapshotted from the caster at cast time.
var damage: int = 0
## [enum CombatTypes.DamageCategory] the eruption resolves as.
var category: int = CombatTypes.DamageCategory.MAGICAL
## Who the eruption damages, relative to [member source].
var affiliation: int = CombatTypes.TargetKind.ENEMY
## The maw's own ELEMENT, snapshotted from the casting move. &"" is elementless and
## resolves neutral, exactly as an unelemented vine does.
var element: StringName = &""
## The casting unit; never damaged by its own maw, and credited for what it kills.
var source

## Optional event-bus override for the [code]damage_dealt[/code] announcements and the
## telegraph, mirroring [member TravelingHazard.event_bus]: null in the live game (the
## GameEvents autoload), injected by tests and by the casting effect.
var event_bus = null

## True once it has gone off. A maw fires exactly once and is then finished.
var _detonated: bool = false


func _init(p_cells: Array[Vector2i], p_damage: int, p_category: int, p_affiliation: int,
		p_source) -> void:
	cells = p_cells.duplicate()
	damage = p_damage
	category = p_category
	affiliation = p_affiliation
	source = p_source


## The patch this maw will erupt on -- what a visual layer telegraphs. Empty once spent.
func telegraph_cells() -> Array[Vector2i]:
	if _detonated:
		return [] as Array[Vector2i]
	return cells.duplicate()


## Spent (already erupted), so a manager holding it should drop it. Mirrors
## [method TravelingHazard.is_expired] so both hazards answer the same question.
func is_expired() -> bool:
	return _detonated


## ERUPT. Damage every matching occupant of [member cells] once and mark the maw spent.
## Returns event data in the same shape [method TravelingHazard.advance] returns, so a
## caller (and a visual layer) can read either hazard identically:
##   { "cells": Array[Vector2i], "damaged": Array[{unit, amount}],
##     "next_cells": Array[Vector2i], "expired": bool }
##
## A null or query-less board simply spends the maw without hitting anything -- an
## eruption with nothing to ask about occupancy is a no-op, never an error.
func detonate(board) -> Dictionary:
	var blast := cells.duplicate()
	if _detonated:
		return {
			"cells": [] as Array[Vector2i],
			"damaged": [],
			"next_cells": [] as Array[Vector2i],
			"expired": true,
		}
	_detonated = true

	var damaged: Array = []
	if board != null and board.has_method("units_at"):
		# A unit standing across two of the patch's cells (a 2x2 boss) must be bitten
		# ONCE, so victims are de-duplicated the way a vine de-duplicates across its band.
		var hit: Dictionary = {}
		for cell in blast:
			for unit in board.units_at(cell):
				if unit == null or unit == source or hit.has(unit):
					continue
				if not CombatTypes.unit_matches_target_kind(affiliation, source, unit, board):
					continue  # spared by this maw's affiliation filter
				hit[unit] = true
				var dealt := DamageEffect.resolve_hazard_damage(
					unit, damage, category, board, element)
				if dealt > 0:
					# ANNOUNCE BEFORE APPLYING, for the reason the whole damage layer does:
					# take_damage can kill outright and the kill is attributed from this
					# signal, so a maw that kills must announce first or it credits nobody
					# and no ON_KILL fires.
					DamageEffect.announce_damage(
						event_bus, DamageEffect.credited_source(source, unit, board), unit, dealt)
					if unit.has_method("take_damage"):
						unit.take_damage(dealt)
				damaged.append({ "unit": unit, "amount": dealt })

	return {
		"cells": blast,
		"damaged": damaged,
		"next_cells": [] as Array[Vector2i],
		"expired": true,
	}
