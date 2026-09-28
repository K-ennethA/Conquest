extends Resource
class_name EvolutionResource

## ONE EDGE of the evolution graph: "[member from_id] can become [member to_id]".
##
## An evolved form is just another roster [CharacterResource] with its own character_id
## (docs/design/EVOLUTION.md §3.1), so this resource carries no stats, moves or model -- only
## the link between two roster ids, what makes it available, and what carries over. Content
## lives under res://game/characters/evolutions/*.tres and is indexed by [EvolutionLibrary].
##
## Branching = several edges sharing a [member from_id]. Each form has at most ONE parent, so
## a line always has a single root ([method EvolutionLibrary.line_root]).

@export var id: StringName = &""                 ## stable, e.g. &"tree_grunt__oakheart"
@export var from_id: StringName = &""            ## roster character_id
@export var to_id: StringName = &""              ## roster character_id (new form OR an existing unit)
@export_multiline var flavor: String = ""        ## "The sapling finally takes root."

@export_group("Triggers")
## ANY listed trigger being satisfied makes the evolution AVAILABLE (OR). Empty = never
## available out of battle (an in-battle-only edge, M2).
@export var triggers: Array[EvolutionTrigger] = []
## Out-of-battle evolutions wait for the player to confirm on the Evolution screen (Pokemon
## style). false = automatic (story beats, M4).
@export var requires_confirmation: bool = true

@export_group("In battle")
## Opt-in: this edge may ALSO fire mid-battle through EvolveEffect (M2).
@export var allowed_in_battle: bool = false
## 0 = BATTLE (reverts after the battle), 1 = PERMANENT (committed after a STORY battle).
@export_enum("BATTLE", "PERMANENT") var in_battle_persistence: int = 0

@export_group("Carry-over")
## 0 = KEEP_RATIO, 1 = KEEP_DAMAGE, 2 = FULL_HEAL (mid-battle swap, M2).
@export_enum("KEEP_RATIO", "KEEP_DAMAGE", "FULL_HEAL") var hp_policy: int = 0
@export var carry_statuses: bool = true    ## mid-battle only (M2)
@export var carry_cooldowns: bool = true   ## shared move_ids keep their timers (M2)
## On a permanent evolve, move the parent's equipped UNIT item to the new form when the new
## form wears nothing ([method ItemInventory.rekey_character]).
@export var carry_item: bool = true
@export var carry_tint_skin: bool = true   ## tint-only skins follow the line (M3)


## True when ANY trigger is met by [param ctx] (see [EvolutionTrigger] for the keys).
func is_available(ctx: Dictionary) -> bool:
	for trigger in triggers:
		if trigger != null and trigger.is_met(ctx):
			return true
	return false


## The smallest Growth goal among this edge's triggers, or 0 when none is Growth-based.
func growth_goal() -> int:
	var goal: int = 0
	for trigger in triggers:
		if trigger == null:
			continue
		var g: int = trigger.growth_goal()
		if g > 0 and (goal == 0 or g < goal):
			goal = g
	return goal


## Player-facing trigger text: "Growth 3", "Growth 3 or Ember Seed", "" when none.
func describe_triggers() -> String:
	var parts: PackedStringArray = []
	for trigger in triggers:
		if trigger == null:
			continue
		var text: String = trigger.describe()
		if not text.is_empty():
			parts.append(text)
	return " or ".join(parts)
