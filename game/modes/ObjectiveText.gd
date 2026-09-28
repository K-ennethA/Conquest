extends RefCounted
class_name ObjectiveText

## Player-facing wording for a map's objectives ([GameModeRules]): the short HUD
## chip ("Rout the enemy", "Survive 3/8 turns", "Seize the throne") and the longer
## lines of the map menu's Objective page. Pure + static so it is unit-testable.

## Short chip text for [param rules]; [param rounds_done] feeds survive progress
## (see [method WinConditionLibrary.completed_rounds]). "" with no rules.
static func chip_text(rules: GameModeRules, rounds_done: int = 0) -> String:
	if rules == null or rules.win_conditions.is_empty():
		return ""
	var parts: PackedStringArray = []
	for c in rules.win_conditions:
		var t := short_for(c, rounds_done)
		if t != "" and not parts.has(t):
			parts.append(t)
	var joiner := " & " if rules.require_all_win else " or "
	return joiner.join(parts)


## Short phrase for one [WinCondition].
static func short_for(c: WinCondition, rounds_done: int = 0) -> String:
	if c == null:
		return ""
	if c is SurviveTurns:
		var st := c as SurviveTurns
		return "Survive %d/%d turns" % [clampi(rounds_done, 0, st.turns), st.turns]
	if c is CaptureThrone:
		return "Seize the throne"
	if c is DefeatBoss:
		return "Defeat the boss"
	if c is DefeatAllEnemies:
		return "Rout the enemy"
	if c is ProtectUnit:
		return c.describe()
	return c.describe()


## Full lines for the Objective page: "Victory: ..." per win condition (with the
## throne's cell / survive progress), then "Defeat: ..." lines.
static func detail_lines(rules: GameModeRules, rounds_done: int = 0) -> PackedStringArray:
	var out: PackedStringArray = []
	if rules == null:
		out.append("Victory: Rout the enemy")
		out.append("Defeat: Lose all of your units")
		return out
	var wins := rules.win_conditions
	for i in range(wins.size()):
		var c: WinCondition = wins[i]
		if c == null:
			continue
		var line := short_for(c, rounds_done)
		if c is CaptureThrone:
			var cell: Vector3i = (c as CaptureThrone).target_cell
			line += " at (%d, %d)" % [cell.x, cell.y]
		elif c is DefeatAllEnemies:
			line += " -- defeat every enemy unit"
		var prefix := "Victory: "
		if i > 0:
			prefix = "  and " if rules.require_all_win else "  or "
		out.append(prefix + line)
	if wins.is_empty():
		out.append("Victory: Rout the enemy")
	out.append("Defeat: Lose all of your units")
	for c in wins + rules.lose_conditions:
		if c is ProtectUnit:
			out.append("Defeat: %s falls" % (c as ProtectUnit).label())
	return out
