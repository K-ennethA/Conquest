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
##
## The same machinery serves a creature EVOLUTION and a human CLASS PROMOTION
## (docs/design/DECISIONS.md #8, #16): [member kind_label] only changes the words the screens use.

@export var id: StringName = &""                 ## stable, e.g. &"tree_grunt__oakheart"
@export var from_id: StringName = &""            ## roster character_id
@export var to_id: StringName = &""              ## roster character_id (new form OR an existing unit)
@export_multiline var flavor: String = ""        ## "The sapling finally takes root."
## "Evolve" (a creature) or "Promote" (a human class change, Squire -> Knight): the verb every
## screen shows (EVOLVE button, "is evolving..." / "is being promoted...").
@export_enum("Evolve", "Promote") var kind_label: String = "Evolve"

@export_group("Requirements")
## REQUIREMENTS (DECISIONS.md #26): the edge is AVAILABLE out of battle only when EVERY listed
## requirement is met (ALL / AND). Empty = never available out of battle (an in-battle-only
## edge, M2). The property keeps its historical name so saved content loads unchanged.
@export var triggers: Array[EvolutionTrigger] = []
## Open modes have no story context. By default a story requirement (Location, StoryFlag,
## PartyHas, Weather, UseItem -- [method EvolutionTrigger.needs_story]) is UNMET there, so a
## story-gated edge never unlocks in Skirmish. true = IGNORE those requirements outside story
## (the edge is then judged on its other requirements alone).
@export var skip_story_requirements_outside_story: bool = false
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


## True when EVERY requirement is met by [param ctx] (see [EvolutionTrigger] for the keys). An
## edge with no requirements is never available; an empty slot fails closed; a story
## requirement is skipped outside story only when [member skip_story_requirements_outside_story].
func is_available(ctx: Dictionary) -> bool:
	if triggers.is_empty():
		return false
	for trigger in triggers:
		if trigger == null:
			return false
		if is_skipped(trigger, ctx):
			continue
		if not trigger.is_met(ctx):
			return false
	return true


## True when [param ctx] comes from story mode (StoryGrowth sets ctx "mode" = "story").
static func is_story_context(ctx: Dictionary) -> bool:
	return String(ctx.get("mode", "")) == "story"


## True when [param trigger] does not count in [param ctx] (a story requirement outside story on
## an edge that opted to skip them).
func is_skipped(trigger: EvolutionTrigger, ctx: Dictionary) -> bool:
	return trigger != null and skip_story_requirements_outside_story and trigger.needs_story() \
		and not is_story_context(ctx)


## The CHECKLIST (DECISIONS.md #27): one row per requirement, in authored order:
## {text, met, progress, skipped, story_only, outside_story}. A skipped row -- and a story
## requirement judged outside story (outside_story: it cannot be met here) -- reads "story only".
func requirement_rows(ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for trigger in triggers:
		if trigger == null:
			continue
		var skipped: bool = is_skipped(trigger, ctx)
		out.append({
			"text": trigger.describe(),
			"met": not skipped and trigger.is_met(ctx),
			"progress": trigger.progress(ctx),
			"skipped": skipped,
			"story_only": trigger.needs_story(),
			"outside_story": trigger.needs_story() and not is_story_context(ctx),
		})
	return out


## How many requirements [param ctx] still misses (skipped ones never count).
func unmet_count(ctx: Dictionary) -> int:
	var n: int = 0
	for trigger in triggers:
		if trigger == null:
			n += 1
		elif not is_skipped(trigger, ctx) and not trigger.is_met(ctx):
			n += 1
	return n


## The bag items this edge USES on the member ([UseItemTrigger]), in authored order.
func use_item_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for trigger in triggers:
		if trigger != null and not trigger.used_item_id().is_empty() and not out.has(trigger.used_item_id()):
			out.append(trigger.used_item_id())
	return out


## The items a confirmed evolution SPENDS when [param used_item] was the one used.
func consumed_items(used_item: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for trigger in triggers:
		if trigger is UseItemTrigger and (trigger as UseItemTrigger).item_id == used_item \
				and (trigger as UseItemTrigger).consume and not out.has(used_item):
			out.append(used_item)
	return out


## True when an auto-offer [param event] could have changed one of this edge's requirements
## ([method EvolutionTrigger.responds_to]) -- the "offer it again" test (no nag loop).
func responds_to(event: Dictionary) -> bool:
	for trigger in triggers:
		if trigger != null and trigger.responds_to(event):
			return true
	return false


## The Growth goal of this edge: the LARGEST Growth requirement (all must be met), or 0 when
## none is Growth-based.
func growth_goal() -> int:
	var goal: int = 0
	for trigger in triggers:
		if trigger != null:
			goal = maxi(goal, trigger.growth_goal())
	return goal


## Player-facing requirement text: "Growth 3", "Growth 3 + Win 2 battles with it", "" when none.
func describe_triggers() -> String:
	var parts: PackedStringArray = []
	for trigger in triggers:
		if trigger == null:
			continue
		var text: String = trigger.describe()
		if not text.is_empty():
			parts.append(text)
	return " + ".join(parts)


# --- Words (evolution vs promotion) --------------------------------------------------

func is_promotion() -> bool:
	return kind_label == "Promote"


## "Evolve" / "Promote" (buttons).
func verb() -> String:
	return "Promote" if is_promotion() else "Evolve"


## "is evolving..." / "is being promoted..." (the Evolution screen ribbon).
func progressive_text() -> String:
	return "is being promoted..." if is_promotion() else "is evolving..."


## "evolved into" / "was promoted to" (the reveal ribbon).
func past_text() -> String:
	return "was promoted to" if is_promotion() else "evolved into"


## "evolution" / "promotion".
func noun() -> String:
	return "promotion" if is_promotion() else "evolution"
