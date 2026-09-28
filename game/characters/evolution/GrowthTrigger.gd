extends EvolutionTrigger
class_name GrowthTrigger

## Met once the member's CUMULATIVE Growth reaches [member growth_required].
##
## Growth is earned after battles ([GrowthTracker]) and never reset by evolving, so a
## second-stage edge simply asks for a larger number than the first. Reads ctx key
## [code]growth[/code] (int).

## Cumulative Growth the member needs. 0 or less = met immediately (a free evolution).
@export var growth_required: int = 3


func is_met(ctx: Dictionary) -> bool:
	return int(ctx.get("growth", 0)) >= growth_required


func describe() -> String:
	return "Growth %d" % maxi(0, growth_required)


func growth_goal() -> int:
	return maxi(0, growth_required)
