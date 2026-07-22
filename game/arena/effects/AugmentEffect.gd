extends Resource
class_name AugmentEffect

## One composable piece of an Augment's effect -- the exact mirror of how a MoveResource
## is built from an Array[MoveEffect]. An Augment holds an Array[AugmentEffect]; the
## ArenaAugmentApplier runs each one when a squad unit is (re)built at round setup. Each
## subtype hooks into a REAL system that already exists:
##
##   StatEffect          -> the unit's stat API (flat stat deltas)
##   MoveModEffect       -> the unit's moves (extra hits, wider AoE, +range, -cooldown, ...)
##   GrantAbilityEffect  -> the AbilitySystem (attach a triggered passive)
##   ExtraActionEffect   -> the turn system (act again this turn -- "move twice")
##   RunEffect           -> the ArenaRun itself (extra squad slot, currency, draft size)
##
## Base methods are no-ops so a subtype overrides only what it touches (a unit-scoped
## effect overrides apply_to_unit; a run-scoped one overrides apply_to_run). describe()
## feeds the draft card and the (upcoming) Augment Creator preview.

## Apply to a live [param unit] at round setup. [param run] is the owning ArenaRun, passed
## so an effect can read run state (round number, life, ...). Override in a unit subtype.
func apply_to_unit(_unit, _run) -> void:
	pass


## Apply to the [param run] itself (extra squad slot, currency boon, bigger draft).
## Override in a run-scoped subtype.
func apply_to_run(_run) -> void:
	pass


## One-line human description for the draft card and the creator preview. Override.
func describe() -> String:
	return ""
