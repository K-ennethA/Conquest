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
	# A SIEGE map needs rather more runtime than base-assault does -- a round clock, creep
	# waves, squad respawns and the capture state machine -- but it is armed from exactly the
	# same place and on exactly the same terms: on when the compiled rules carry a
	# [CaptureBase] objective, off (and inert) for every other map. See [SiegeController].
	SiegeController.sync(rules)
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
	# "Capture Enemy Base" / "capture the base" -- the SIEGE objective. Matched on both words
	# for the same reason the line above is: falling through to "kill everything" on a Siege
	# map (which spawns creeps forever) would be unwinnable. Selecting Siege IS selecting a
	# map that authors this string plus the lanes/base_cells schema -- the same map-driven
	# route base-assault takes -- so no separate mode enum is needed; see
	# [method SiegeController.is_active] for the runtime's own identity check.
	if key.begins_with("capture") and key.contains("base"):
		var cbase := CaptureBase.new()
		cbase.faction = faction
		return cbase
	if key.begins_with("eliminate all") or key.begins_with("defeat all"):
		return _defeat_all(faction)
	# Not push_warning: an unknown string is a soft fallback, not an engine error, and
	# GUT would flag a push_warning as a test failure.
	print("[WinConditionLibrary] Unrecognised victory condition '%s' -- falling back to Eliminate All Enemies." % name)
	return _defeat_all(faction)


# --- What a compiled rule set MEANS ------------------------------------------
#
# These two live here, next to the fallback they are about, because this file is the one
# place that knows a rule set can contain an objective the map never asked for. They are pure
# statics so the decision is testable exhaustively without standing up a battle.

## True when [param rules] carry an objective a MAP really asked for -- anything other than
## the bare "eliminate all enemies" [method build_win_conditions] supplies when a map named
## nothing (or nothing recognised). Lose conditions are ignored: one is DERIVED for every map
## by [method build_lose_conditions], so it says nothing about what the author wanted.
static func rules_are_map_authored(rules: GameModeRules) -> bool:
	if rules == null:
		return false
	for c in rules.win_conditions:
		if c != null and not (c is DefeatAllEnemies):
			return true
	return false


## Should a battle be decided by the MAP's compiled objectives, or by the neutral
## last-side-standing fallback? (The gate in
## [code]GameWorldManager._evaluate_game_end[/code].)
##
## SOLO: always the map's, exactly as it always was.
##
## VERSUS / hot-seat: the map's too, but ONLY when the map actually authored one. Scoring the
## bare fallback in versus would reroute every skirmish on every map through a different path
## for an identical outcome -- a behaviour change for no gain -- so a rule set that is only
## the fallback is left to the fallback.
##
## What the widening unlocks is the OBJECTIVE modes. A versus Siege is won by CAPTURING the
## enemy base: [CaptureBase] resolves on a turn boundary, which last-side-standing can never
## observe, and on a push map fielding endless creeps nobody is ever wiped out -- so without
## this a versus push map could not end at all.
static func should_score_map_objectives(solo: bool, rules: GameModeRules) -> bool:
	if rules == null:
		return false
	if solo:
		return true
	return rules_are_map_authored(rules)


static func _defeat_all(faction: int) -> DefeatAllEnemies:
	var c := DefeatAllEnemies.new()
	c.faction = faction
	return c


static func _enemy_of(faction: int) -> int:
	return 1 if faction == 0 else 0
