extends Resource
class_name AbilityCondition

## Optional gate on an [AbilityResource]: decides whether the ability is currently
## eligible to fire (for event triggers) or currently in force (for PASSIVE
## abilities). Pure data + a single predicate, so conditions are inspector-authored
## and unit-testable in isolation.
##
## Subclasses override [method is_met]. They query the world through the same
## duck-typed [param board] interface used across the effect pipeline (see
## [MoveContext]) — chiefly [code]board.cell_of(unit)[/code] plus optional terrain
## accessors — and degrade gracefully when an accessor is absent.
##
## The base class is permissive (always met) so a bare or null condition never
## blocks an ability; use [AlwaysCondition] when you want that intent to be explicit.


## True if the ability may act on [param unit] given the current [param board].
## Overridden by subclasses; the base is always-true.
func is_met(_unit, _board) -> bool:
	return true


## One-line summary for tooltips / ability descriptions.
func describe() -> String:
	return "always"
