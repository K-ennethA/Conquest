extends EvolutionTrigger
class_name StoryFlagTrigger

## Met once a STORY FLAG is set (docs/design/EVOLUTION.md §7 "Story flag / event"): an edge that
## opens after a quest beat ("the shrine has been cleansed"). Reads ctx key
## [code]story_flags[/code], which only the overworld supplies (StoryState.story_flags() via
## [StoryGrowth]) -- a Dictionary {flag: bool/int} or an Array of set flag names. Outside story
## the key is absent and the requirement is never met (a story requirement, see
## [EvolutionTrigger]), so a story-only edge never unlocks in open modes by accident.

## The flag that must be set.
@export var flag: String = ""
## Minimum numeric value (a quest stage: "quest.blight_road >= 2"); true counts as 1.
@export var min_value: int = 1
## Player-facing checklist text ("Cleanse the Heartwood shrine"); "" = "Story: <flag>".
@export var label: String = ""


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
	if not label.strip_edges().is_empty():
		return label
	return "Story: %s" % flag


func needs_story() -> bool:
	return true


## A flag event: any flag change when the event names none, else only this flag.
func responds_to(event: Dictionary) -> bool:
	if not event_has(event, "flag"):
		return false
	var flags = event.get("flags", [])
	if not (flags is Array) or (flags as Array).is_empty():
		return true
	return (flags as Array).has(flag)


func problem() -> String:
	return "a StoryFlag requirement names no flag" if flag.strip_edges().is_empty() else ""
