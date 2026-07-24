extends Resource
class_name Augment

## A drafted power-up. This is the heart of the Arena's replayability, and it's cheap
## because an augment's effect is expressed through the combat systems that ALREADY
## exist: a stat modifier, a move upgrade, a granted ability, a persistent status. Most
## augments need no code at all -- they just fill in [member stat_bonuses] and are applied
## generically by the augment applier at round setup. Richer effects override the
## apply_* hooks in a small subclass.

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }
enum Target { SQUAD, SINGLE_UNIT, RUN }

@export var id: String = ""
@export var display_name: String = "Augment"
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
@export var target: Target = Target.SQUAD

## Generic per-unit stat deltas, applied by the augment applier with no bespoke code.
## Key = stat name ("max_health", "attack", "defense", "move", "evasion", ...);
## value = integer delta. A convenient shorthand for pure-stat augments; equivalent to a
## list of StatEffects. Kept for the data-only starter pool.
@export var stat_bonuses: Dictionary = {}

## The composable, expressive form (mirrors MoveResource.effects): an ordered list of
## AugmentEffects the applier runs at round setup. This is where the rich augments live --
## a move that hits twice (MoveModEffect), an extra action (ExtraActionEffect), a granted
## on-kill passive (GrantAbilityEffect), a run boon (RunEffect), or plain stats
## (StatEffect). Any combination is legal, so one data format expresses everything.
@export var effects: Array[AugmentEffect] = []


## Weight for weighted-random draft rolls, derived from rarity (commons show up most).
func draft_weight() -> float:
	match rarity:
		Rarity.COMMON: return 100.0
		Rarity.RARE: return 45.0
		Rarity.EPIC: return 18.0
		Rarity.LEGENDARY: return 6.0
	return 100.0


## Apply this augment's effect to one live [param unit] at round setup. The base handles
## nothing beyond the generic stat_bonuses path (done by the applier); override in a
## concrete subclass for move upgrades / granted abilities / passives.
func apply_to_unit(_unit) -> void:
	pass


## Apply a run-wide (non-unit) effect -- e.g. an extra squad slot or a currency boon.
## [param run] is the ArenaRun. Override in a subclass; base is a no-op.
func apply_to_run(_run) -> void:
	pass
