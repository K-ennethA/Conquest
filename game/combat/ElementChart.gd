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
## Damage the ENVIRONMENT itself deals — a fire tile burning its occupant, a crawling
## hazard entering a cell — is a fourth, SEPARATE case, and it is the matrix alone
## ([method environment_scale_for]): the tile's element vs the occupant's. What a tile
## GIVES rather than deals (an evasion bonus, a heal) is modulated by
## [method home_effect_amount], the "at home" idea extended past damage.
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

## METADATA KEY marking a [MoveResource] as an ENVIRONMENTAL damage source — the
## synthetic self-move a [TileEffectResource] resolves its effects through, and nothing
## else. Carried as metadata rather than as a new exported field so no authored move
## resource's schema changes and no .tres has to be touched.
##
## Its presence is what switches [method damage_scale_for] onto the environment rule
## (matchup only). See [method mark_environment].
const ENVIRONMENT_META: StringName = &"element_environment_source"

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
##
## ONE BRANCH: when [param move] is an ENVIRONMENTAL source (a tile burning its own
## occupant — see [constant ENVIRONMENT_META]) the environment rule replaces the three
## factors with the matchup alone. Amplifying a fire tile's burn because the victim is
## standing in fire, and then discounting it again because the victim is at home in it,
## would count the same fact three times; the matrix's own self-resist already says
## everything there is to say about standing in your own element.
static func damage_scale_for(move, target, board) -> float:
	var environment: StringName = environment_element_of(move)
	if environment != &"":
		return environment_scale_for(environment, target)
	return type_scale_for(move, target) \
		* tile_scale_for(move, target, board) \
		* type_benefit_scale_for(target, board)


# --- Damage the ENVIRONMENT deals -------------------------------------------
#
# Tiles and hazards hurt the unit standing in them, and that damage is elemented too:
# fire tiles are fire, brambles are nature. It is the MATRIX and nothing else --
#
#   * a nature unit in nature brambles resists them (nature>nature 0.75);
#   * a nature unit on a fire tile is scorched (fire>nature 1.25);
#   * an unelemented tile, or an unelemented occupant, is neutral and unchanged.
#
# Deterministic and board-independent: it reads the source's element and the victim's,
# nothing else. The one function every environmental source resolves through, so a
# damage tile, a hazard and the terrain panel's readout cannot disagree.


## Multiplier for environmental damage of [param source_element] landing on
## [param target]. [constant NEUTRAL] for an elementless source or victim.
static func environment_scale_for(source_element, target) -> float:
	return multiplier(source_element, element_of(target))


## The element of [param tile_effect], read from the chart's
## [member ElementChartResource.tile_elements] — THE authority (CONQUEST.md rule 9).
## &"" for a null effect, an effect with no id, or an id nobody has elemented.
static func tile_element_of(tile_effect) -> StringName:
	if tile_effect == null or typeof(tile_effect) != TYPE_OBJECT:
		return &""
	return chart().tile_element(tile_effect.get("id"))


## Stamp [param move] as the environmental source for [param element].
##
## Sets the move's own element (so element-aware UI and VFX colour the tile's hit like
## anything else) AND the [constant ENVIRONMENT_META] marker that routes
## [method damage_scale_for] onto the environment rule. A no-op for a null move or an
## empty element, so an elementless tile behaves exactly as it did before this existed.
static func mark_environment(move, element) -> void:
	if move == null or typeof(move) != TYPE_OBJECT:
		return
	var key := ElementChartResource.key_of(element)
	if key == &"":
		return
	move.set("element", key)
	move.set_meta(ENVIRONMENT_META, key)


## The environmental element [method mark_environment] stamped on [param move], or &"".
static func environment_element_of(move) -> StringName:
	if move == null or typeof(move) != TYPE_OBJECT or not is_instance_valid(move):
		return &""
	if not move.has_meta(ENVIRONMENT_META):
		return &""
	return ElementChartResource.key_of(move.get_meta(ENVIRONMENT_META))


# --- Effects the environment applies (non-damage) ----------------------------


## The magnitude a tile effect's non-damage payload actually lands at for [param unit].
##
## AT HOME, extended from damage to everything else a tile does. An occupant standing on
## a tile of ITS OWN element gets more out of what that tile GIVES
## ([member ElementChartResource.own_tile_effect_bonus]) and less of what it TAKES
## ([member ElementChartResource.own_tile_benefit] applied to the magnitude) — a nature
## unit reads tall grass better (+15 evasion -> +19); a water unit keeps its feet on ice
## (-10 evasion -> -9). Every other pairing is returned untouched, so a tile with no
## element, a unit with no element, and a mismatch are all exactly as before.
##
## Magnitude is floored at 1, so no scale can silently erase an authored effect, and the
## SIGN is always preserved — a benefit can never be scaled into a penalty. Deterministic:
## an integer round of authored data, no RNG.
##
## Deliberately NOT applied to a STATUS a tile hands out (rubble's slow, the vine trap's
## ensnare): a status is binary, and the only knob it has is its roll CHANCE — scaling
## that would introduce an RNG draw where an authored 1.0 short-circuits one today, and
## change every replay downstream of it.
## The SCALE [method home_effect_amount] applies to a magnitude of [param amount]'s sign:
## [member ElementChartResource.own_tile_effect_bonus] for a benefit,
## [member ElementChartResource.own_tile_benefit] for a penalty, [constant NEUTRAL] for 0.
##
## Split out for the surfaces that have to SAY what the rule did ("heals ×1.25 for you").
## They print this authored knob rather than the ratio of the two integers, because
## rounding makes the ratio lie: +15 becomes +19, and 19/15 is 1.27, not the 1.25 the
## chart actually applied.
static func home_effect_scale(amount: int) -> float:
	if amount == 0:
		return NEUTRAL
	return chart().home_effect_bonus() if amount > 0 else chart().home_benefit()


static func home_effect_amount(tile_effect, amount: int, unit) -> int:
	if amount == 0:
		return amount
	var tile: StringName = tile_element_of(tile_effect)
	if tile == &"" or tile != element_of(unit):
		return amount
	var res := chart()
	var scale: float = res.home_effect_bonus() if amount > 0 else res.home_benefit()
	var magnitude: int = maxi(1, roundi(float(absi(amount)) * scale))
	return magnitude if amount > 0 else -magnitude


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
	if unit == null:
		return []
	return tile_elements_of(_effects_at(_cell_of(unit, board), board))


## Distinct elements contributed by [param effects] (a cell's
## [code]tile_effects_at[/code] list), in list order. The list-shaped half of
## [method tile_elements_under], split out so a UI holding a cell's effects can ask the
## same question without needing a unit standing on them. Nulls are skipped quietly.
static func tile_elements_of(effects) -> Array:
	var out: Array = []
	if not (effects is Array):
		return out
	for te in (effects as Array):
		var el: StringName = tile_element_of(te)
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
