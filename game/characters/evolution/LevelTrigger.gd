extends EvolutionTrigger
class_name LevelTrigger

## Met once the member's STORY LEVEL reaches [member level_required] (docs/design/PROGRESSION.md §6,
## DECISIONS.md #82: level is ONE MORE trigger kind beside Growth, feats, items, places and flags --
## no existing edge is migrated off Growth). Reads ctx key [code]level[/code] (int), which only
## story supplies ([method StoryGrowth.member_context]): levels exist only in story, so in open
## modes a LevelTrigger is simply UNMET ([method needs_story]) and an edge may opt out with
## [member EvolutionResource.skip_story_requirements_outside_story].

## The level the member needs. 1 or less = met by any story member.
@export var level_required: int = 16


func is_met(ctx: Dictionary) -> bool:
	if not ctx.has("level"):
		return false
	return int(ctx.get("level", 0)) >= level_required


func describe() -> String:
	return "Reach Lv %d" % maxi(1, level_required)


func progress(ctx: Dictionary) -> String:
	if not ctx.has("level"):
		return ""
	return "Lv %d/%d" % [mini(maxi(1, int(ctx.get("level", 1))), maxi(1, level_required)), maxi(1, level_required)]


func needs_story() -> bool:
	return true


## A battle is what raises a level.
func responds_to(event: Dictionary) -> bool:
	return event_has(event, "battle")


func problem() -> String:
	var cap: int = ProgressionRules.current().max_level
	if level_required > cap:
		return "a Level requirement asks for Lv %d, above the level cap %d" % [level_required, cap]
	return ""
