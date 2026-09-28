extends EvolutionTrigger
class_name StoryFlagTrigger

## Met once a STORY FLAG is set (docs/design/EVOLUTION.md §7 "Story flag / event"): an edge that
## opens after a quest beat ("the shrine has been cleansed"). Reads ctx key
## [code]story_flags[/code], which only the overworld supplies (StoryState.story_flags() via
## [StoryGrowth]) -- a Dictionary {flag: bool/int} or an Array of set flag names. Outside story
## the key is absent and the trigger is never met, so a story-only edge never unlocks in open
## modes by accident.

## The flag that must be set.
@export var flag: String = ""
## Minimum numeric value (a quest stage: "quest.blight_road >= 2"); true counts as 1.
@export var min_value: int = 1


func is_met(ctx: Dictionary) -> bool:
	if flag.strip_edges().is_empty():
		return false
	var flags = ctx.get("story_flags", null)
	if flags is Array:
		return (flags as Array).has(flag)
	if not (flags is Dictionary):
		return false
	var v = (flags as Dictionary).get(flag, 0)
	var n: int = 0
	if v is bool:
		n = 1 if v else 0
	elif v is int or v is float:
		n = int(v)
	return n >= min_value


func describe() -> String:
	return "Story: %s" % flag
