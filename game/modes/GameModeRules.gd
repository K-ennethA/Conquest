extends Resource
class_name GameModeRules

## Data-driven bundle that defines a game mode: its win objectives, its lose
## objectives, and a few feature flags. Authoring a new mode is creating a new
## .tres and dropping in the [WinCondition] resources it needs -- no code.
##
## Evaluation contract (see [WinCondition] for the shared state schema):
##   - Any win condition reporting FAILED, or any lose condition reporting MET,
##     is a [constant Outcome.DEFEAT].
##   - Victory requires the win conditions to be satisfied: ALL of them when
##     [member require_all_win] is true, otherwise ANY one.
##   - Defeat is checked before victory.

## Overall result of evaluating the whole rule set.
enum Outcome {
	ONGOING,  ## battle continues
	VICTORY,  ## the player has won
	DEFEAT,   ## the player has lost
}

@export var display_name: String = "Custom Mode"
@export_multiline var description: String = ""

## Objectives that win the battle. FAILED here forces a defeat.
@export var win_conditions: Array[WinCondition] = []
## Objectives that, when MET, mean the player has lost.
@export var lose_conditions: Array[WinCondition] = []
## If true, every win condition must be MET simultaneously; otherwise any one wins.
@export var require_all_win: bool = false

@export_group("Feature Flags")
## Whether AI-controlled bot units are permitted in this mode.
@export var allow_bots: bool = false
## Whether a boss unit participates in this mode.
@export var boss_enabled: bool = false


## Score the whole rule set against [param state]; returns an [enum Outcome].
func evaluate(state: Dictionary) -> int:
	var all_met := not win_conditions.is_empty()
	var any_met := false

	for c in win_conditions:
		if c == null:
			all_met = false
			continue
		var s := c.evaluate(state)
		if s == WinCondition.Status.FAILED:
			return Outcome.DEFEAT
		if s == WinCondition.Status.MET:
			any_met = true
		else:
			all_met = false

	for c in lose_conditions:
		if c != null and c.evaluate(state) == WinCondition.Status.MET:
			return Outcome.DEFEAT

	if require_all_win:
		if all_met:
			return Outcome.VICTORY
	elif any_met:
		return Outcome.VICTORY
	return Outcome.ONGOING
