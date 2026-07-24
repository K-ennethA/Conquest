extends RefCounted
class_name ElementChart

## Data-driven TYPE-MATCHUP chart (Fire-Emblem / Pokemon style).
##
## A move carries an [member MoveResource.element]; a unit carries a
## [member CharacterResource.element] TYPE; a tile contributes an element via the
## effect standing on it (see [constant TILE_ELEMENT]). Damage is scaled by three
## coherent, independent factors, all resolved HERE so tuning lives in one place:
##
##   1. MOVE vs TYPE effectiveness -- FIRE is super-effective into a NATURE unit
##      (Ember Storm vs the tree boss), water douses fire, and so on.
##   2. TILE amplifier -- a target standing on a tile whose element MATCHES the
##      move's element takes more (a fire move into a target on a burning tile).
##   3. TYPE BENEFIT -- a unit standing on a tile of ITS OWN element is "at home"
##      and takes slightly less damage.
##
## MISSING-ELEMENT DEGRADES TO NEUTRAL: an empty move element or an empty unit
## type never matches any chart row / tile, so every helper returns [constant
## NEUTRAL] (1.0). A move or unit authored before this system behaves exactly as
## it did before -- nothing is scaled.
##
## Element StringNames match the values existing moves already use and the tags
## [method ConquestTheme.element_color] colours by, so authoring stays one
## vocabulary end to end.

const FIRE: StringName = &"fire"
const WATER: StringName = &"water"
const NATURE: StringName = &"nature"
const WIND: StringName = &"wind"
const EARTH: StringName = &"earth"
const HOLY: StringName = &"holy"
const DARK: StringName = &"dark"

const SUPER_EFFECTIVE: float = 1.5
const RESISTED: float = 0.75
const NEUTRAL: float = 1.0

## Modest environment amplifier when a move's element matches the tile under the
## target (fire move + burning tile). Kept light and separate from effectiveness.
const TILE_MATCH_BONUS: float = 1.25
## The "type benefit": a unit on a tile of its OWN element takes this fraction of
## incoming damage (a small, tunable defensive perk). 0.9 = 10% less.
const TYPE_BENEFIT_SCALE: float = 0.9

## ATTACKER element -> { DEFENDER type -> multiplier }. Any pairing NOT listed is
## [constant NEUTRAL]. A coherent ring (FIRE->NATURE->EARTH... plus WATER, WIND and
## a HOLY/DARK opposition) authored so it is easy to read and retune in one spot.
const CHART: Dictionary = {
	FIRE:   { NATURE: SUPER_EFFECTIVE, WATER: RESISTED, EARTH: RESISTED },
	WATER:  { FIRE: SUPER_EFFECTIVE, EARTH: SUPER_EFFECTIVE, NATURE: RESISTED, WATER: RESISTED },
	NATURE: { WATER: SUPER_EFFECTIVE, EARTH: SUPER_EFFECTIVE, FIRE: RESISTED, WIND: RESISTED },
	WIND:   { NATURE: SUPER_EFFECTIVE, EARTH: SUPER_EFFECTIVE, WIND: RESISTED },
	EARTH:  { FIRE: SUPER_EFFECTIVE, WATER: RESISTED, WIND: RESISTED, NATURE: RESISTED },
	HOLY:   { DARK: SUPER_EFFECTIVE, HOLY: RESISTED },
	DARK:   { HOLY: SUPER_EFFECTIVE, DARK: RESISTED },
}

## Light TILE-EFFECT-id -> element mapping. Keyed on [member TileEffectResource.id]
## (what a cell exposes at combat time through [code]board.tile_effects_at[/code]),
## so a burning tile reads as FIRE without any refactor of the tile resources. A
## couple of raw tile ids are included too, harmlessly, in case a board ever
## surfaces them. Extend this dictionary to give new terrain an element.
const TILE_ELEMENT: Dictionary = {
	&"fire": FIRE,
	&"scorching_vent": FIRE,
	&"scorched": FIRE,
	&"molten_lava": FIRE,
	&"magma_vent": FIRE,
	&"empowering_water": WATER,
	&"deep_water": WATER,
	&"slippery_ice": WATER,
	&"tall_grass": NATURE,
	&"vine_trap": NATURE,
	&"sacred_meadow": HOLY,
	&"fortify": EARTH,
}


## Multiplier for [param attacker_element] striking [param defender_type].
## Returns [constant NEUTRAL] whenever either side is empty or the pairing is not
## authored, so a missing element is always a no-op.
static func effectiveness(attacker_element, defender_type) -> float:
	var atk: StringName = StringName(attacker_element)
	var def: StringName = StringName(defender_type)
	if atk == &"" or def == &"":
		return NEUTRAL
	if not CHART.has(atk):
		return NEUTRAL
	var row: Dictionary = CHART[atk]
	return float(row.get(def, NEUTRAL))


## Move-vs-type effectiveness for [param move] landing on [param target].
static func type_scale_for(move, target) -> float:
	return effectiveness(move_element(move), element_of(target))


## Environment amplifier: [constant TILE_MATCH_BONUS] when the move's element
## matches an element of the tile under [param target] (e.g. a fire move hitting a
## target that stands on a burning tile), else [constant NEUTRAL].
static func tile_scale_for(move, target, board) -> float:
	var me: StringName = move_element(move)
	if me == &"":
		return NEUTRAL
	for el in tile_elements_under(target, board):
		if StringName(el) == me:
			return TILE_MATCH_BONUS
	return NEUTRAL


## Type benefit: [constant TYPE_BENEFIT_SCALE] when [param target] stands on a tile
## of its OWN element ("at home"), else [constant NEUTRAL]. A light, tunable hook.
static func type_benefit_scale_for(target, board) -> float:
	var te: StringName = element_of(target)
	if te == &"":
		return NEUTRAL
	for el in tile_elements_under(target, board):
		if StringName(el) == te:
			return TYPE_BENEFIT_SCALE
	return NEUTRAL


## The FULL element multiplier applied to one hit: move-vs-type effectiveness,
## folded with the tile amplifier and the defender's own-element tile benefit.
##
## THE single entry point both [method DamageEffect.apply] and
## [method MoveExecutor.preview_vs] resolve through, so the combat forecast can
## never disagree with the resolved hit. Every factor is deterministic (it depends
## only on the move's element and the target's current state), so previewing it is
## honest information, not an exploit. Returns [constant NEUTRAL] when nothing
## applies -- the missing-element no-op path.
static func damage_scale_for(move, target, board) -> float:
	return type_scale_for(move, target) \
		* tile_scale_for(move, target, board) \
		* type_benefit_scale_for(target, board)


## Duck-typed element of [param move] (its [member MoveResource.element]), or &"".
static func move_element(move) -> StringName:
	if move == null:
		return &""
	var e = move.get("element")
	return StringName(e) if e != null else &""


## Duck-typed TYPE of [param unit]: prefer a [code]get_element()[/code] method
## (a live [Unit] reads its backing character), else an [code]element[/code]
## property (mocks), else &"" (neutral).
static func element_of(unit) -> StringName:
	if unit == null:
		return &""
	if unit.has_method("get_element"):
		return StringName(unit.get_element())
	var e = unit.get("element")
	return StringName(e) if e != null else &""


## Distinct elements contributed by the tile effects under [param unit]. Reads the
## cell's effects through [param board]'s [code]tile_effects_at[/code] (falling back
## to the live [code]CombatServices[/code], mirroring [TerrainStats]), maps each
## effect id through [constant TILE_ELEMENT], and dedupes. Null-safe: no board, no
## cell lookup, or a mock exposing neither simply yields an empty list.
static func tile_elements_under(unit, board) -> Array:
	var out: Array = []
	if unit == null:
		return out
	var cell: Vector2i = _cell_of(unit, board)
	for te in _effects_at(cell, board):
		if te == null:
			continue
		var id: StringName = _effect_id(te)
		if id != &"" and TILE_ELEMENT.has(id):
			var el: StringName = TILE_ELEMENT[id]
			if el not in out:
				out.append(el)
	return out


static func _effect_id(te) -> StringName:
	var v = te.get("id")
	return StringName(v) if v != null else &""


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
