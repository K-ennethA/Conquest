extends RefCounted

class_name TerrainVisuals

## The shared vocabulary for what the GROUND under a unit is giving it -- the sibling of
## [StatusVisuals] (conditions), [ShieldVisuals] (wards) and [ElementVisuals] (elements).
## Every surface that shows a unit wears the same terrain chip: the world-space badge row
## on [HealthBar], the compact battle card ([UnitInfoPanel]) and the hover card
## ([UnitHoverPanel]) all ask THIS file, so "standing in tall grass" reads the same on the
## map as it does in the panels.
##
## WHY IT EXISTS. Terrain bonuses are computed on the fly at combat time (the Fire-Emblem
## avoid model -- see [TerrainStats]) and are never stored as a status, so nothing on the
## UNIT ever showed them: the tile panel said "+15 evasion" about the CELL and the unit
## standing in it wore nothing. Two surfaces had grown their own private half of the answer
## -- an evasion-only "+AVO N" tag on the world bar and an evasion-only green chip on the
## hover card -- which is exactly the drift this file removes. One helper, every surface,
## every stat.
##
## THE NUMBER IS NEVER RE-DERIVED HERE. Every amount comes back from
## [method TerrainStats.bonus_for], the same function [method MoveContext.hit_chance] and
## [method MoveExecutor.preview_vs] read -- so the chip quotes the bonus the unit actually
## has, element home-boost and all (a nature unit in nature tall grass wears +19, not the
## authored +15). CONQUEST.md rule 9: a panel that models a rule instead of calling it is a
## panel that advertises a number the player cannot use.

## The TERRAIN MARK -- the one character that says "this chip is about where you are
## standing", not about a condition on you.
##
## MEASURED, NOT CHOSEN, exactly like [constant ShieldVisuals.GLYPH] and the [StatusVisuals]
## set. The world-space badge row is a [Label3D] with NO font fallback, so an undrawable
## character is a literal tofu box over every unit at once. The probe in
## `tests/unit/test_status_feedback.gd` measured Godot 4.6's default font: the whole
## Geometric Shapes block is missing, and the drawable set is
## [code]◊ • † ‡ § ¤ ± « » ÷ × ° ¶ µ ¬ · ∞[/code] plus all of ASCII.
##
## "±" is picked out of that set because it is the only member that already MEANS "a
## modifier applied to a value", and because it collides with nothing: [StatusVisuals] owns
## † + O - ~ and [ShieldVisuals] owns ◊. Pinned by
## `tests/integration/test_terrain_readout_live.gd`, which asks the live HUD font whether it
## can draw it.
const MARK := "±"

## A terrain GAIN. == [constant ConquestTheme.EL_NATURE], written out rather than referenced
## so this file carries no load-order dependency on the theme (the idiom
## [constant ShieldVisuals.SILVER] uses). It is the green both retired readouts already
## used, so nothing about the colour of "standing in grass" changed.
const GAIN_COLOR := Color("5fb84e")

## A terrain LOSS (slippery ice: -10 evasion). == [constant MoveStatVisuals.NERF_COLOR], the
## HUD's one ember for "this is working against you".
const LOSS_COLOR := Color("e2604f")

## How many terrain chips a surface may draw before the rest collapse into the shared
## "+N" overflow marker. Two, deliberately: a cell stacking three DIFFERENT stat bonuses is
## authored terrain nobody has built, and the badge row / status strip budgets are already
## spoken for by conditions.
const MAX_CHIPS: int = 2

## Short stat words, so a chip can name WHICH stat the ground is moving in three characters.
## Anything unlisted falls back to the first three letters upper-cased, so a stat authored
## later is legible immediately and can be given a proper abbreviation afterwards.
const _STAT_LABELS := {
	"evasion": "AVO",   # Fire-Emblem "avoid" -- the word the rest of the HUD uses
	"attack": "ATK",
	"defense": "DEF",
	"magic": "MAG",
	"speed": "SPD",
	"movement": "MOV",
	"range": "RNG",
	"crit": "CRT",
	"health": "HP",
}

## What a cell with no authored display_name is called on a chip.
const _UNNAMED_TILE := "Terrain"


# --- Vocabulary --------------------------------------------------------------

## "AVO" for evasion, "ATK" for attack, "CRT" for an unlisted "crt"-ish stat. Never empty
## for a non-empty stat name -- a chip with no stat word is unreadable.
static func stat_label(stat_name: String) -> String:
	if stat_name == "":
		return ""
	if _STAT_LABELS.has(stat_name):
		return String(_STAT_LABELS[stat_name])
	return stat_name.substr(0, 3).to_upper()


## Every nonzero terrain stat bonus [param unit] is standing in, one entry per STAT, in the
## authored order the cell's effects list them. Each entry:
##
##   stat   -- String, the raw stat name ("evasion")
##   label  -- String, its short word ("AVO")
##   amount -- int, THE NUMBER THE UNIT ACTUALLY HAS (element home-boost included)
##   gain   -- bool, amount > 0
##   tile   -- String, the terrain granting it ("Tall Grass"), several joined with " + "
##
## [param board] is optional and passed straight through to [TerrainStats]; omitted, that
## helper resolves the live board itself. Empty array for a null/freed unit, a unit off the
## board, or plain ground -- which is every caller's "draw nothing" signal.
##
## ONE STAT, ONE ENTRY, however many effects contribute: a cell that is both tall grass and
## fortified reports AVO and DEF separately, and a cell carrying two evasion layers reports
## their SUM, because that sum is what [method TerrainStats.bonus_for] hands combat.
static func bonuses_for(unit, board = null) -> Array:
	var out: Array = []
	if unit == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		return out

	# Which stats are in play, and which terrain each one came from. The effect list is
	# TerrainStats' own -- so the UI can never enumerate a different set of effects from the
	# one the combat sum walks.
	var order: Array = []
	var tiles: Dictionary = {}
	for te in TerrainStats.passive_effects_for(unit, board):
		if te == null:
			continue
		for e in te.effects:
			if not (e is StatModifierEffect):
				continue
			var stat: String = String(e.stat_name)
			if stat == "":
				continue
			if not tiles.has(stat):
				tiles[stat] = []       # Array, not PackedStringArray: packed arrays are
				order.append(stat)     # value types and would not mutate in place here.
			var tile_name: String = _tile_name(te)
			if not (tile_name in tiles[stat]):
				(tiles[stat] as Array).append(tile_name)

	for stat in order:
		# THE authority for the magnitude, including the at-home element re-scale.
		var amount: int = TerrainStats.bonus_for(unit, String(stat), board)
		if amount == 0:
			continue  # two layers that cancel out are not news
		out.append({
			"stat": String(stat),
			"label": stat_label(String(stat)),
			"amount": amount,
			"gain": amount > 0,
			"tile": " + ".join(PackedStringArray(tiles[stat])),
		})
	return out


## True when [param unit] is standing on anything worth a chip. Cheap "should I draw the
## row at all" check for a surface that does not want the entries themselves.
static func has_bonus(unit, board = null) -> bool:
	return not bonuses_for(unit, board).is_empty()


# --- Formatting ---------------------------------------------------------------

## "±AVO+15" / "±AVO-10" -- the COMPACT chip label, for the surfaces with no room to
## explain: the world-space badge row and the battle card's status strip.
##
## Read as three parts: the terrain mark (what kind of chip this is), the stat word (which
## number is moving), and the SIGNED delta (which way, and by how much). The sign is always
## printed even for a gain -- the tint says the same thing, but a chip has to survive being
## read in greyscale.
static func chip_text(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	return "%s%s%+d" % [MARK, String(entry.get("label", "")), int(entry.get("amount", 0))]


## "±AVO+15 · Tall Grass" -- the ROOMY chip label, for the hover card, which is 240px wide
## and whose subtree is click-through (so its tooltip can never be shown -- see the note in
## [UnitHoverPanel]). Naming the terrain in the label is the only way that card can say
## WHERE the bonus is coming from.
static func full_chip_text(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	var tile: String = String(entry.get("tile", ""))
	if tile == "":
		return chip_text(entry)
	return "%s · %s" % [chip_text(entry), tile]


## "Tall Grass: +19 evasion while standing here" -- what a chip says on HOVER.
##
## Names the terrain, states the REAL number (the one [method bonuses_for] read off
## [TerrainStats], element boost included -- a nature unit is told +19, not the authored
## +15), and says the bonus is CONDITIONAL ON POSITION, which is the entire difference
## between a terrain chip and a status chip.
static func tooltip_for(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	return "%s: %+d %s while standing here" % [
		String(entry.get("tile", _UNNAMED_TILE)),
		int(entry.get("amount", 0)),
		String(entry.get("stat", "")),
	]


## The chip's tint: the terrain green for a bonus, the HUD's nerf ember for a penalty.
static func color_for(entry: Dictionary) -> Color:
	return GAIN_COLOR if bool(entry.get("gain", true)) else LOSS_COLOR


## How many terrain chips a surface with [param cap] slots draws, and how many the overflow
## marker stands for. Delegated to [StatusVisuals] so terrain and statuses overflow by ONE
## rule -- the "+N" marker means the same thing whichever kind of chip it replaced.
static func shown_count(total: int, cap: int = MAX_CHIPS) -> int:
	return StatusVisuals.shown_count(total, cap)


static func hidden_count(total: int, cap: int = MAX_CHIPS) -> int:
	return StatusVisuals.hidden_count(total, cap)


## "+2" for a marker standing in for 2 unshown terrain chips; "" when nothing is hidden.
## Same wording, same function, as the status overflow marker -- a "+N" on a chip row means
## one thing everywhere.
static func overflow_label(hidden: int) -> String:
	return StatusVisuals.overflow_label(hidden)


## The terrain's player-facing name, or [constant _UNNAMED_TILE]. Falls back to the
## humanized id so an effect authored without a display_name is still named rather than
## anonymous.
static func _tile_name(te) -> String:
	if te == null:
		return _UNNAMED_TILE
	var disp: String = String(te.display_name).strip_edges()
	if disp != "":
		return disp
	var id: String = String(te.id)
	if id != "":
		return StatusVisuals.humanize(id)
	return _UNNAMED_TILE
