extends RefCounted

class_name ChallengeScoring

## Pure, static scoring for a CHALLENGE run (format_version 2). No engine state, no I/O:
## every input is passed in, so this is trivially unit-testable headless and is the ONE
## place the points formula lives (the controller, the browse screen and the tests all go
## through here so they can never disagree).
##
## The formula rewards a fast, clean clear:
##   * A WIN starts at 1000 points.
##   * Every turn taken OVER par costs 75 points.
##   * Every challenger unit lost costs 100 points.
##   * Coming in UNDER par pays a bonus of +50 per turn under, capped at +200.
##   * A win never scores below 100 (a slow, costly clear is still worth something).
##   * A LOSS scores 0.
## A run is "perfect" when the challenger loses zero units (win or not the flag is only
## meaningful on a win; callers gate it on the win).

## A win floors here so even a grindy clear is rewarded.
const WIN_FLOOR := 100

## A fresh, on-par, no-loss clear.
const WIN_BASE := 1000

## Point cost per turn taken beyond par.
const OVER_PAR_PENALTY := 75

## Point cost per challenger unit lost.
const UNIT_LOSS_PENALTY := 100

## Bonus per turn finished under par, and its ceiling.
const UNDER_PAR_BONUS := 50
const UNDER_PAR_BONUS_CAP := 200


## Points for a run. [param won] gates everything: a loss is always 0. [param turns] is the
## challenger's turn count, [param par] the author-set target, [param units_lost] how many
## of the challenger's own units fell during the run. Pure integer maths so the result is
## identical on every platform.
static func score(won: bool, turns: int, par: int, units_lost: int) -> int:
	if not won:
		return 0
	var over: int = maxi(0, turns - par)
	var under: int = maxi(0, par - turns)
	var bonus: int = mini(UNDER_PAR_BONUS_CAP, UNDER_PAR_BONUS * under)
	var raw: int = WIN_BASE - OVER_PAR_PENALTY * over - UNIT_LOSS_PENALTY * maxi(0, units_lost) + bonus
	return maxi(WIN_FLOOR, raw)


## True when the challenger cleared the run without losing a single unit. Only meaningful on
## a win; callers should AND it with the win (a loss is never "perfect").
static func is_perfect(won: bool, units_lost: int) -> bool:
	return won and units_lost <= 0


## Convenience bundle for the callers that want both at once (the controller records both
## into results.json). Returns { "score": int, "perfect": bool }.
static func evaluate(won: bool, turns: int, par: int, units_lost: int) -> Dictionary:
	return {
		"score": score(won, turns, par, units_lost),
		"perfect": is_perfect(won, units_lost),
	}
