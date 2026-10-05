extends Resource
class_name EvolutionTrigger

## One REQUIREMENT of an [EvolutionResource] edge (docs/design/DECISIONS.md #26): the edge is
## available out of battle only when EVERY listed requirement is met ([method
## EvolutionResource.is_available] -- ALL semantics).
##
## The same composable pattern as [AbilityCondition]: small subclasses, each a pure
## [method is_met] over a context Dictionary. The context is built OUTSIDE the simulation
## (menus, the post-battle tracker, the overworld) by [method RosterLedger.record_context] (+
## [StoryGrowth.evolution_context] in story), so a requirement can never be consulted mid-battle
## and never reads the ledger itself -- it is handed the numbers. Keys a requirement may read
## (each subclass documents its own):
##   growth         int          the member's cumulative Growth              (every mode)
##   uid            String       the member                                  (every mode)
##   form           StringName   the member's current form                   (every mode)
##   feats          Dictionary   battle-feat counters {wins, kos, clutch_wins,
##                               element_kos: {element: n}}                 (every mode)
##   held_item      String       the item the member wears ("" = none)       (every mode)
##   mode           String       "story" inside story mode; absent elsewhere
##   story_flags    Dictionary   the journey's flags                         (story)
##   area_id        String       the area the party stands in                (story)
##   region_id      String       that area's region                          (story)
##   weather        String       that area's weather id                      (story)
##   party_members  Array        [{member_id, character_id, line}]           (story)
##   bag            Dictionary   item_id -> count, the story bag             (story)
##   used_item      String       the bag item being used on the member NOW   (story)
##   level          int          the member's story level                    (story)
##
## OPEN MODES (no story context): a requirement whose [method needs_story] is true (Location,
## StoryFlag, PartyHas, Weather, UseItem, Level) reads a key only story supplies, so it is simply
## UNMET there -- a story-gated promotion can never be farmed in Skirmish. An edge may opt out
## with [member EvolutionResource.skip_story_requirements_outside_story]: those requirements
## are then IGNORED (neither met nor unmet) outside story.
##
## The base class is never met, so an unconfigured requirement in content fails CLOSED.


## True when this requirement is satisfied by [param ctx].
func is_met(_ctx: Dictionary) -> bool:
	return false


## Short player-facing text for the checklist, the Compendium and the Evolution screen
## ("Growth 3", "Win 2 battles with it").
func describe() -> String:
	return ""


## Progress toward the requirement for the checklist ("2/3", "1 in bag"), "" when it is a plain
## yes / no.
func progress(_ctx: Dictionary) -> String:
	return ""


## True when the requirement reads keys only STORY supplies (see the class docs).
func needs_story() -> bool:
	return false


## True when an AUTO-OFFER event ([StoryController], docs/STORY_MODE.md "Evolution in story")
## could have changed this requirement, so the edge is worth offering again. [param event]:
## {kinds: Array ("battle", "area", "flag", "item", "party"), flags: Array of flag keys}.
func responds_to(_event: Dictionary) -> bool:
	return false


## The bag item this requirement USES (consumes) on the member, "" when it uses none.
func used_item_id() -> String:
	return ""


## The Growth this requirement asks for, or 0 when it is not Growth-based. Lets the UI draw
## growth pips without knowing requirement subclasses.
func growth_goal() -> int:
	return 0


## A content problem with this requirement ("" = fine), reported by [method
## EvolutionGraph.validate].
func problem() -> String:
	return ""


## True when [param event] lists [param kind] in its kinds.
static func event_has(event: Dictionary, kind: String) -> bool:
	var kinds = event.get("kinds", [])
	if kinds is Array or kinds is PackedStringArray:
		for k in kinds:
			if String(k) == kind:
				return true
	return false
