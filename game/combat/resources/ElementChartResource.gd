extends Resource
class_name ElementChartResource

## THE element-matchup data, as ONE editable resource.
##
## Every number the element system multiplies damage by lives here, in
## [code]res://game/combat/resources/element_chart.tres[/code] — never as a code
## constant — so retuning a matchup is CONTENT work (open the .tres, change a float)
## rather than a code change. [ElementChart] is the static façade that reads this;
## nothing else should load it directly.
##
## THE FRAMEWORK NEVER CRASHES ON A NEW ELEMENT. An element name that appears in no
## row, a row that lists no such defender, a null, or an outright garbage value all
## resolve to [member default_multiplier] (1.0 = neutral). That is deliberate: the
## CONTENT phase fills the matrix in, and a move or character authored with an element
## the chart has never heard of must simply play neutral, quietly.
##
## Deterministic and side-effect free — no RNG, no time, no global state — so lockstep
## peers and replays resolve identical damage from identical inputs.

## The authored element VOCABULARY. Documentation and validation only: a lookup for an
## element that is NOT listed here still resolves (to neutral), it is not rejected.
@export var elements: Array[StringName] = []

## What an UNAUTHORED pairing multiplies by. 1.0 = neutral, i.e. "no matchup".
## Values <= 0 are ignored and read back as 1.0, so a mis-authored 0 can never erase
## damage outright.
@export var default_multiplier: float = 1.0

## THE MATRIX: attacker element -> { defender element -> multiplier }.
##
## Both directions are authored EXPLICITLY. There is no implied symmetry and no implied
## inverse — if fire hits nature for 1.25, nature hitting fire for 1.25 is its own entry.
## Reading the row tells you the whole story of what that element does.
@export var matrix: Dictionary = {}

## Human-readable record of what is seeded and why. Kept as resource DATA rather than a
## `;` comment in the .tres because the Godot editor rewrites the file on save and would
## strip a comment; this survives.
@export_multiline var notes: String = ""

@export_group("Environment")
## Multiplier when the move's element matches an element of the tile the target stands
## on (a fire move into a target standing in flames). Independent of the matrix.
@export var tile_match_bonus: float = 1.25

## Multiplier when the target stands on a tile of ITS OWN element — "at home", so it
## takes slightly less. Independent of the matrix. < 1.0 is a benefit.
@export var own_tile_benefit: float = 0.9

## Tile-effect id -> element. Keyed on [member TileEffectResource.id], which is what a
## cell exposes at combat time through [code]board.tile_effects_at[/code], so a burning
## tile reads as fire without touching the tile resources. Extend to give new terrain an
## element.
@export var tile_elements: Dictionary = {}


## Multiplier for [param attacker_element] striking [param defender_element].
## Returns [member default_multiplier] for an empty side, an unauthored pairing, or any
## value that is not a usable positive number. Never errors, never warns.
func multiplier(attacker_element, defender_element) -> float:
	var atk := key_of(attacker_element)
	var def := key_of(defender_element)
	if atk == &"" or def == &"":
		return neutral()
	var row: Variant = matrix.get(atk, null)
	if not (row is Dictionary):
		return neutral()
	return _sane((row as Dictionary).get(def, null), neutral())


## The value an unauthored pairing resolves to, guarded so a mis-authored
## [member default_multiplier] can never make every hit deal nothing.
func neutral() -> float:
	return _positive(default_multiplier)


## Element of the tile effect [param tile_effect_id], or &"" when it carries none.
func tile_element(tile_effect_id) -> StringName:
	var id := key_of(tile_effect_id)
	if id == &"":
		return &""
	return key_of(tile_elements.get(id, null))


## [member tile_match_bonus], guarded.
func tile_bonus() -> float:
	return _positive(tile_match_bonus)


## [member own_tile_benefit], guarded.
func home_benefit() -> float:
	return _positive(own_tile_benefit)


## Is [param element] part of the authored vocabulary? Informational — an unlisted
## element is still a legal lookup (it simply has no matchups).
func has_element(element) -> bool:
	return key_of(element) in elements


## Every authored non-neutral pairing as `{ attacker, defender, multiplier }` records,
## in matrix order. For content tooling and for tests that pin the seeded chart.
func authored_pairs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base := neutral()
	for atk in matrix:
		var row: Variant = matrix[atk]
		if not (row is Dictionary):
			continue
		for def in (row as Dictionary):
			var mult := _sane((row as Dictionary)[def], base)
			if not is_equal_approx(mult, base):
				out.append({
					"attacker": key_of(atk),
					"defender": key_of(def),
					"multiplier": mult,
				})
	return out


## Coerce anything at all to a lookup key. A String or StringName becomes itself; a
## null, an int, an Object or any other garbage becomes &"" — which every lookup above
## treats as "no element", i.e. neutral. This is the quiet-failure seam: bad input is a
## RETURNED value, never an engine error (see tests/README.md rule 1).
static func key_of(value) -> StringName:
	match typeof(value):
		TYPE_STRING_NAME:
			return value
		TYPE_STRING:
			return StringName(value)
	return &""


## A multiplier that is a real, non-negative, finite number, or [param fallback].
## 0.0 is deliberately LEGAL as a matrix entry — "this element does nothing to that
## one" is a matchup a designer may want — but not as a global scalar (see
## [method _positive]).
static func _sane(value, fallback: float) -> float:
	if not (value is float or value is int):
		return fallback
	var f := float(value)
	if not is_finite(f) or f < 0.0:
		return fallback
	return f


## A global tuning scalar: must be a real number strictly above 0, else 1.0. Guards the
## knobs that multiply EVERY hit, where a mis-authored 0 would zero out the whole game.
static func _positive(value) -> float:
	var f := _sane(value, 1.0)
	return f if f > 0.0 else 1.0
