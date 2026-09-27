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
## [param special_rules] is the map's [member MapResource.special_rules]; it is scanned
## for objective markers ("objective:THRONE:<player>:<x>:<y>", written by the Map
## Maker) so a bare "Seize Throne" string can find its cell. [param turn_limit] is the
## map's [member MapResource.turn_limit], used as the count for a bare "Survive Turns".
static func build_rules(condition_strings: Array, faction: int = HUMAN_FACTION,
		special_rules: Array = [], turn_limit: int = 0) -> GameModeRules:
	var rules := GameModeRules.new()
	rules.win_conditions = build_win_conditions(condition_strings, faction, special_rules, turn_limit)
	rules.lose_conditions = build_lose_conditions(faction)
	# Every listed objective must be met to win (matters only for multi-objective
	# maps; a single objective behaves identically either way).
	rules.require_all_win = true
	return rules


## Convenience: compile the rules straight off a [MapResource] (victory strings +
## objective markers + turn limit).
static func build_rules_for_map(map: MapResource, faction: int = HUMAN_FACTION) -> GameModeRules:
	if map == null:
		return build_rules([], faction)
	return build_rules(map.victory_conditions, faction, map.special_rules, map.turn_limit)


static func build_win_conditions(condition_strings: Array, faction: int,
		special_rules: Array = [], turn_limit: int = 0) -> Array[WinCondition]:
	var out: Array[WinCondition] = []
	for s in condition_strings:
		var c := build_one(String(s), faction, special_rules, turn_limit)
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
##   "Defeat Boss"                     -> DefeatBoss
##   "Eliminate/Defeat All..."         -> DefeatAllEnemies
##   "Survive 8 Turns" / "Survive: 8"  -> SurviveTurns(8). With no number the map's
##                                        turn_limit is used (else DEFAULT_SURVIVE_TURNS).
##   "Seize Throne" / "Capture ..."    -> CaptureThrone. The cell comes from an inline
##     "Seize 7,5" / "Seize (7, 5)"       "x,y" pair, else from the map's THRONE
##                                        objective marker in special_rules. With no
##                                        cell at all it falls back to DefeatAllEnemies.
## Anything else falls back to DefeatAllEnemies with a log line. ProtectUnit needs a
## unit reference a bare string can't carry, so it is still not string-parsed.
static func build_one(name: String, faction: int, special_rules: Array = [], turn_limit: int = 0) -> WinCondition:
	var key := name.strip_edges().to_lower()
	if key.begins_with("defeat boss") or key == "defeat the boss" or key == "kill the boss":
		var db := DefeatBoss.new()
		db.faction = faction
		return db
	if key.begins_with("eliminate all") or key.begins_with("defeat all"):
		return _defeat_all(faction)
	if key.begins_with("survive"):
		var st := SurviveTurns.new()
		st.faction = faction
		var n := _first_int(key)
		if n <= 0:
			n = turn_limit if turn_limit > 0 else DEFAULT_SURVIVE_TURNS
		st.turns = n
		return st
	if key.begins_with("seize") or key.begins_with("capture"):
		var cell = _parse_cell(key)
		if cell == null:
			cell = find_objective_cell(special_rules, "THRONE")
		if cell != null:
			var ct := CaptureThrone.new()
			ct.faction = faction
			ct.target_cell = cell if cell is Vector3i else Cells.lift(cell)
			return ct
		print("[WinConditionLibrary] '%s' has no objective cell -- falling back to Eliminate All Enemies." % name)
		return _defeat_all(faction)
	# Not push_warning: an unknown string is a soft fallback, not an engine error, and
	# GUT would flag a push_warning as a test failure.
	print("[WinConditionLibrary] Unrecognised victory condition '%s' -- falling back to Eliminate All Enemies." % name)
	return _defeat_all(faction)


## Turns a bare "Survive Turns" objective lasts when neither the string nor the map's
## turn_limit names a count.
const DEFAULT_SURVIVE_TURNS: int = 5


## Cell of the first "objective:<marker_type>:<player>:<x>:<y>" entry in
## [param special_rules] (the Map Maker's encoding, see MapMakerModel), else null.
static func find_objective_cell(special_rules: Array, marker_type: String = "THRONE"):
	for rule in special_rules:
		var parts := String(rule).split(":")
		if parts.size() != 5 or parts[0] != "objective":
			continue
		if parts[1].to_upper() != marker_type.to_upper():
			continue
		if not parts[3].is_valid_int() or not parts[4].is_valid_int():
			continue
		return Vector2i(int(parts[3]), int(parts[4]))
	return null


## Full rounds completed on [param turn_system] -- the "turn" a [SurviveTurns] counts.
## Duck-typed so it works with both shipped systems (and mocks):
##   SpeedFirst  : round_number starts at 1 -> rounds done = round_number - 1
##   Traditional : current_turn is a running per-player-phase counter starting at 1,
##                 so rounds done = (current_turn - 1) / player_count.
## Returns 0 with no system.
static func completed_rounds(turn_system) -> int:
	if turn_system == null:
		return 0
	if "round_number" in turn_system:
		return maxi(0, int(turn_system.round_number) - 1)
	if "current_turn" in turn_system:
		var players := 1
		if "registered_players" in turn_system:
			players = maxi(1, (turn_system.registered_players as Array).size())
		return maxi(0, (int(turn_system.current_turn) - 1) / players)
	return 0


static func _first_int(text: String) -> int:
	var rx := RegEx.new()
	rx.compile("\\d+")
	var m := rx.search(text)
	return int(m.get_string()) if m != null else 0


static func _parse_cell(text: String):
	var rx := RegEx.new()
	rx.compile("(-?\\d+)\\s*,\\s*(-?\\d+)")
	var m := rx.search(text)
	if m == null:
		return null
	return Vector2i(int(m.get_string(1)), int(m.get_string(2)))


static func _defeat_all(faction: int) -> DefeatAllEnemies:
	var c := DefeatAllEnemies.new()
	c.faction = faction
	return c


static func _enemy_of(faction: int) -> int:
	return 1 if faction == 0 else 0
