extends Resource
class_name EvolutionTrigger

## One condition that makes an [EvolutionResource] edge AVAILABLE out of battle.
##
## The same composable pattern as [AbilityCondition]: small subclasses, each a pure
## [method is_met] over a context Dictionary. The context is built OUTSIDE the simulation
## (menus, the post-battle tracker, the overworld) by [method RosterLedger.context_for], so a
## trigger can never be consulted mid-battle and never read the ledger itself -- it is handed
## the numbers. Keys a trigger may read (each subclass documents its own):
##   growth         int                 the member's cumulative Growth
##   uid            String              the RosterLedger member
##   form           StringName          the member's current form
##   owned_items    Array / Dictionary  catalysts in the bag (M3)
##   story_flags    Array / Dictionary  overworld flags (M4)
##
## The base class is never met, so an unconfigured trigger in content fails CLOSED.


## True when this trigger is satisfied by [param ctx].
func is_met(_ctx: Dictionary) -> bool:
	return false


## Short player-facing text for the Compendium and the Evolution screen ("Growth 3").
func describe() -> String:
	return ""


## The Growth this trigger asks for, or 0 when it is not Growth-based. Lets the UI draw
## growth pips without knowing trigger subclasses.
func growth_goal() -> int:
	return 0
