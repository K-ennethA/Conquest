extends Resource
class_name WinCondition

## Base class for a single, modular win / lose objective.
##
## Objectives are pure data + a pure [method evaluate] check, so a game mode is
## assembled by listing a few of these (see [GameModeRules]) instead of writing
## bespoke mode scripts. The same object works in the live game and against mock
## state in tests.
##
## [method evaluate] receives a neutral [param state] dictionary. Recognized keys
## (all optional; each subclass reads only what it needs):
##   "units": Array   -- every unit currently in play
##   "board": Object  -- board-query adapter (cell_of / units_at / are_enemies)
##   "turn":  int     -- turns elapsed since the battle started
## Units are duck-typed: a unit exposes `team` (or `faction`), `hp`, and
## optionally `unit_id` / `character_id` / `id`.

## Result of a single objective check.
enum Status {
	ONGOING,  ## not yet decided
	MET,      ## objective achieved
	FAILED,   ## objective can no longer be achieved / was violated
}


## Evaluate this objective against the current [param state]. Override in subclasses.
func evaluate(_state: Dictionary) -> int:
	return Status.ONGOING


## One-line human-readable summary (for briefings / UI).
func describe() -> String:
	return "Objective"


## The LIVE one-line summary: [method describe], refined by [param state] wherever the
## objective can say something more useful about the battle in front of the player than
## its static phrasing can -- naming the boss still standing, counting down the turns
## still to hold.
##
## Additive on purpose. It defaults to [method describe], so a condition with nothing
## live to add needs no override and an unknown or future condition still produces
## sensible text; and it reads the SAME neutral [param state] [method evaluate] scores,
## so the line on screen can never describe a different battle than the rules do.
func describe_progress(_state: Dictionary) -> String:
	return describe()


## Display name of [param unit] (via get_display_name(), or a `display_name` property),
## or "" when it has neither. Shared by the subclasses that name a unit in their
## [method describe_progress].
static func _display_name_of(unit) -> String:
	if unit == null:
		return ""
	if unit.has_method("get_display_name"):
		return String(unit.get_display_name()).strip_edges()
	var dn = unit.get("display_name")
	if dn != null:
		return String(dn).strip_edges()
	return ""


# --- Shared duck-typed unit accessors --------------------------------------

## Faction id of [param unit] (via get_team(), or a `team` / `faction` property).
static func _team_of(unit) -> int:
	if unit == null:
		return -1
	if unit.has_method("get_team"):
		return int(unit.get_team())
	var t = unit.get("team")
	if t != null:
		return int(t)
	var f = unit.get("faction")
	if f != null:
		return int(f)
	return -1


## True while [param unit] is still on the board and above 0 HP.
static func _is_alive(unit) -> bool:
	if unit == null:
		return false
	if unit.has_method("is_alive"):
		return bool(unit.is_alive())
	var hp = unit.get("hp")
	if hp != null:
		return int(hp) > 0
	return true


## Stable identifier of [param unit] (get_id(), or a `unit_id`/`character_id`/`id`).
static func _unit_id(unit) -> StringName:
	if unit == null:
		return &""
	if unit.has_method("get_id"):
		return StringName(unit.get_id())
	for prop in ["unit_id", "character_id", "id"]:
		var v = unit.get(prop)
		if v != null:
			return StringName(v)
	return &""
