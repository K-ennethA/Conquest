extends RefCounted
class_name ElementChart

## Static façade over the ONE editable element resource,
## [code]res://game/combat/resources/element_chart.tres[/code] ([ElementChartResource]).
##
## A move carries an [member MoveResource.element]; a unit carries a
## [member CharacterResource.element]; a tile contributes an element through the effect
## standing on it. Damage is scaled by three coherent, independent factors, all resolved
## HERE so tuning lives in one place — and all of them read their numbers from the .tres,
## never from a constant in this file:
##
##   1. MATCHUP — the matrix. Attacker element vs defender element (fire into nature).
##   2. TILE amplifier — a target standing on a tile whose element MATCHES the move's
##      element takes more (a fire move into a target standing in flames).
##   3. HOME benefit — a unit standing on a tile of ITS OWN element is "at home" and
##      takes slightly less.
##
## UNKNOWN PAIRS ARE NEUTRAL, ALWAYS. An empty move element, an empty unit element, an
## element the chart has never heard of, a null, or outright garbage all resolve to
## [constant NEUTRAL] (1.0). Nothing here can push an error or fail a lookup — a move or
## character authored before this system, or authored during the content phase with a
## brand-new element, behaves exactly as if the chart did not exist.
##
## Deterministic: no RNG, no time, no mutable global state. Lockstep peers and replays
## resolve identical damage from identical inputs, and the replay format is untouched.

## The single resource every number is read from.
const CHART_PATH: String = "res://game/combat/resources/element_chart.tres"

const FIRE: StringName = &"fire"
const WATER: StringName = &"water"
const NATURE: StringName = &"nature"
const WIND: StringName = &"wind"
const EARTH: StringName = &"earth"
const HOLY: StringName = &"holy"
const DARK: StringName = &"dark"

## The only multiplier that is a code constant, because it is the IDENTITY — "nothing
## applies". Every real number (how strong is strong, how much a tile adds) is data.
const NEUTRAL: float = 1.0

## Verdict a multiplier reads as, for UI and logs. THE vocabulary — panels label a
## matchup with exactly these three.
const LABEL_STRONG: StringName = &"strong"
const LABEL_RESISTED: StringName = &"resisted"
const LABEL_NEUTRAL: StringName = &"neutral"

## Cached chart. Loaded once on first use; [method set_chart] swaps it for a test.
static var _chart: ElementChartResource = null


## The live chart resource. Never null: if the .tres is missing or fails to load, this
## hands back an EMPTY chart, so every lookup answers [constant NEUTRAL] and the game
## keeps running unscaled rather than erroring. Quiet failure, per the project rule.
static func chart() -> ElementChartResource:
	if _chart == null:
		var loaded: Resource = null
		if ResourceLoader.exists(CHART_PATH):
			loaded = load(CHART_PATH)
		if loaded is ElementChartResource:
			_chart = loaded
		else:
			_chart = ElementChartResource.new()
	return _chart


## Swap the chart (tests: pin an exact matrix without touching the shipped .tres).
## Pass null to go back to the authored resource.
static func set_chart(resource) -> void:
	_chart = resource if resource is ElementChartResource else null


## Drop the cache so the next lookup re-reads the .tres. Pair with [method set_chart]
## in a test's `after_each`.
static func reset_chart() -> void:
	_chart = null


# --- THE pinned lookup -------------------------------------------------------


## Multiplier for [param attacker_element] striking [param defender_element].
##
## THE matchup question, and the one a UI asks. Unknown or absent pairs — either side
## empty, an element with no row, a row with no such column, a null, a garbage type —
## return [constant NEUTRAL]. It cannot crash and it cannot log.
static func multiplier(attacker_element, defender_element) -> float:
	return chart().multiplier(attacker_element, defender_element)


## The verdict [param mult] reads as: [constant LABEL_STRONG] above 1.0,
## [constant LABEL_RESISTED] below it, [constant LABEL_NEUTRAL] at it.
static func label_for(mult: float) -> StringName:
	if not is_finite(mult) or is_equal_approx(mult, NEUTRAL):
		return LABEL_NEUTRAL
	return LABEL_STRONG if mult > NEUTRAL else LABEL_RESISTED


## The elements the chart authors ([member ElementChartResource.elements]).
static func vocabulary() -> Array[StringName]:
	return chart().elements


# --- Applied to a hit --------------------------------------------------------


## Legacy alias for [method multiplier]. Kept because it names the concept the damage
## pipeline talks about ("how effective is this?"), and because call sites predate the
## pinned name.
static func effectiveness(attacker_element, defender_element) -> float:
	return multiplier(attacker_element, defender_element)


## Matchup multiplier for [param move] landing on [param target].
static func type_scale_for(move, target) -> float:
	return multiplier(move_element(move), element_of(target))


## Environment amplifier: [member ElementChartResource.tile_match_bonus] when the move's
## element matches an element of the tile under [param target], else [constant NEUTRAL].
static func tile_scale_for(move, target, board) -> float:
	var me: StringName = move_element(move)
	if me == &"":
		return NEUTRAL
	for el in tile_elements_under(target, board):
		if StringName(el) == me:
			return chart().tile_bonus()
	return NEUTRAL


## Home benefit: [member ElementChartResource.own_tile_benefit] when [param target]
## stands on a tile of its OWN element, else [constant NEUTRAL].
static func type_benefit_scale_for(target, board) -> float:
	var te: StringName = element_of(target)
	if te == &"":
		return NEUTRAL
	for el in tile_elements_under(target, board):
		if StringName(el) == te:
			return chart().home_benefit()
	return NEUTRAL


## The FULL element multiplier applied to one hit: matchup, folded with the tile
## amplifier and the defender's own-element tile benefit.
##
## THE single entry point the resolved hit and the forecast both resolve through (see
## [DamageMath]), so preview and reality can never disagree. Every factor is
## deterministic — it depends only on the move's element and the target's current state
## — so previewing it is honest information, not an exploit. Returns [constant NEUTRAL]
## when nothing applies, which is the missing-element no-op path.
static func damage_scale_for(move, target, board) -> float:
	return type_scale_for(move, target) \
		* tile_scale_for(move, target, board) \
		* type_benefit_scale_for(target, board)


# --- Reading elements off duck-typed things ----------------------------------


## Duck-typed element of [param move] (its [member MoveResource.element]), or &"".
static func move_element(move) -> StringName:
	if move == null:
		return &""
	return ElementChartResource.key_of(move.get("element"))


## Duck-typed element of [param unit]: prefer a [code]get_element()[/code] method (a
## live [Unit] reads its backing character), else an [code]element[/code] property
## (mocks), else &"" (neutral).
static func element_of(unit) -> StringName:
	if unit == null:
		return &""
	if unit.has_method("get_element"):
		return ElementChartResource.key_of(unit.get_element())
	return ElementChartResource.key_of(unit.get("element"))


## Distinct elements contributed by the tile effects under [param unit]. Reads the
## cell's effects through [param board]'s [code]tile_effects_at[/code] (falling back to
## the live [code]CombatServices[/code], mirroring [TerrainStats]), maps each effect id
## through [member ElementChartResource.tile_elements], and dedupes. Null-safe: no
## board, no cell lookup, or a mock exposing neither simply yields an empty list.
static func tile_elements_under(unit, board) -> Array:
	var out: Array = []
	if unit == null:
		return out
	var res := chart()
	var cell: Vector2i = _cell_of(unit, board)
	for te in _effects_at(cell, board):
		if te == null:
			continue
		var el: StringName = res.tile_element(te.get("id"))
		if el != &"" and el not in out:
			out.append(el)
	return out


static func _cell_of(unit, board) -> Vector2i:
	if board != null and board.has_method("cell_of"):
		return board.cell_of(unit)
	var svc = _services()
	if svc != null and svc.has_method("board") and svc.board() != null \
		and svc.board().has_method("cell_of"):
		return svc.board().cell_of(unit)
	return Vector2i(-9999, -9999)  # off-board sentinel => no tile => no element


static func _effects_at(cell: Vector2i, board) -> Array:
	if board != null and board.has_method("tile_effects_at"):
		var arr = board.tile_effects_at(cell)
		if arr is Array:
			return arr
	var svc = _services()
	if svc != null and svc.has_method("tile_effects_at"):
		return svc.tile_effects_at(cell)
	return []


## Resolve the CombatServices autoload without a hard compile-time dependency, so
## isolated unit tests (or a mock board) never crash. Mirrors [TerrainStats].
static func _services():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("CombatServices")
	return null
