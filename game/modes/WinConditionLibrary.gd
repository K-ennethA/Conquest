extends RefCounted
class_name WinConditionLibrary

## Compiles a map's authored [member MapResource.victory_conditions] STRINGS into
## live [WinCondition] resources + a [GameModeRules] the runtime can evaluate.
##
## This is the seam that makes win conditions PER-MAP: a map lists human-readable
## objectives ("Defeat Boss", "Eliminate All Enemies") and this turns them into the
## objects [method GameModeRules.evaluate] scores each tick.
##
## All objectives are authored for the HUMAN faction (the player's side). The lose
## side is derived: you lose when your own faction is wiped out.

const HUMAN_FACTION: int = 0


## Build the full rule set (win + lose) for [param condition_strings] scored on
## behalf of [param faction] (the friendly side).
static func build_rules(condition_strings: Array, faction: int = HUMAN_FACTION) -> GameModeRules:
	var rules := GameModeRules.new()
	rules.win_conditions = build_win_conditions(condition_strings, faction)
	rules.lose_conditions = build_lose_conditions(faction)
	# Every listed objective must be met to win (matters only for multi-objective
	# maps; a single objective behaves identically either way).
	rules.require_all_win = true
	# A BASE-ASSAULT map needs a sliver of runtime the pure, stateless conditions
	# cannot provide (registering the neutral guardian faction, and the team bounty
	# for felling one). Arm it here -- this is the one place that knows a map's
	# compiled objectives -- and disarm it for every other map, so nothing else in
	# the game changes. See [BaseAssaultRuntime]; it is a no-op when the rules carry
	# no DestroyBase objective and none has ever been armed.
	BaseAssaultRuntime.sync(rules)
	return rules


static func build_win_conditions(condition_strings: Array, faction: int) -> Array[WinCondition]:
	var out: Array[WinCondition] = []
	for s in condition_strings:
		var c := build_one(String(s), faction)
		if c != null:
			out.append(c)
	# A map that named nothing (or only unrecognised things) still needs a way to be
	# won -- fall back to the classic "kill everything".
	if out.is_empty():
		out.append(_defeat_all(faction))
	return out


## You lose when your side is gone: from the ENEMY's point of view, they have
## "defeated all enemies". Derived rather than authored, so every map gets a defeat
## condition for free.
static func build_lose_conditions(faction: int) -> Array[WinCondition]:
	var out: Array[WinCondition] = []
	out.append(_defeat_all(_enemy_of(faction)))
	return out


## Map ONE objective string to a [WinCondition]. Recognised (case-insensitive):
##   "Defeat Boss"          -> DefeatBoss
##   "Destroy Enemy Base"   -> DestroyBase
##   "Eliminate/Defeat All..." -> DefeatAllEnemies
## Anything else falls back to DefeatAllEnemies with a warning. Capture/Protect/
## Survive conditions exist as classes but need parameters (a throne cell, a
## protected unit, a turn count) that a bare string can't carry, so threading those
## from the map is deferred rather than guessed here.
static func build_one(name: String, faction: int) -> WinCondition:
	var key := name.strip_edges().to_lower()
	if key.begins_with("defeat boss") or key == "defeat the boss" or key == "kill the boss":
		var db := DefeatBoss.new()
		db.faction = faction
		return db
	# "Destroy Enemy Base" / "destroy the base" / "destroy base". Matched on both words
	# rather than an exact string so an author's phrasing does not silently fall through
	# to "kill everything" -- which on a base-assault map (endless waves) is unwinnable.
	if key.begins_with("destroy") and key.contains("base"):
		var dbase := DestroyBase.new()
		dbase.faction = faction
		return dbase
	if key.begins_with("eliminate all") or key.begins_with("defeat all"):
		return _defeat_all(faction)
	# Not push_warning: an unknown string is a soft fallback, not an engine error, and
	# GUT would flag a push_warning as a test failure.
	print("[WinConditionLibrary] Unrecognised victory condition '%s' -- falling back to Eliminate All Enemies." % name)
	return _defeat_all(faction)


static func _defeat_all(faction: int) -> DefeatAllEnemies:
	var c := DefeatAllEnemies.new()
	c.faction = faction
	return c


static func _enemy_of(faction: int) -> int:
	return 1 if faction == 0 else 0
