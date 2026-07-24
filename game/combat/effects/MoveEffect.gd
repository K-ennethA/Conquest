extends Resource
class_name MoveEffect

## Base class for one composable piece of a move's behaviour.
##
## A [MoveResource] owns an ordered list of these. Standardizing on "targeting +
## a list of effects" is what lets moves scale: new content is authored as data
## (new .tres), and new *kinds* of behaviour are small subclasses reused across
## many moves — no bespoke per-move scripting.
##
## Subclasses override [method apply]; they read/mutate the world through
## [param ctx] (see [MoveContext]) and append descriptions to [member ctx.results].

## Optional human-readable override for tooltips/logs.
@export var description_override: String = ""


## Carry out this effect. Override in subclasses.
func apply(_ctx: MoveContext) -> void:
	push_warning("MoveEffect.apply() not overridden by %s" % get_class())


## One-line summary for tooltips / move descriptions.
func describe() -> String:
	return description_override
