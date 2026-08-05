extends RefCounted

class_name ShieldVisuals

## The shared vocabulary for the damage-soak SHIELD ([member Unit.shield_hp]), the way
## [StatusVisuals] is the shared vocabulary for conditions and [ElementVisuals] is for
## elements. Every HP surface in the game -- the world-space [HealthBar], the battle card
## ([UnitInfoPanel]), the hover card ([UnitHoverPanel]), the detail page
## ([UnitPageContent]), the [CombatForecastPanel] and the floating [DamageNumbers] --
## asks THIS file how a shield is drawn, so a shield reads the same everywhere.
##
## WHY IT EXISTS AT ALL. [signal Unit.shield_changed] documented itself as "drives any
## shield HUD" and nothing anywhere subscribed: a 15-point Crystalline Ward was completely
## invisible, so the player watched a hit land for zero HP with no explanation.
##
## THE DESIGN, in one sentence: a shield is drawn as an EXTENSION OF THE HEALTH BAR -- a
## silver segment appended after the green HP fill -- plus a number beside the HP numbers.
##
## THE BAR IDIOM (see [method bar_fractions]). Every HP surface in this project is a
## FIXED-WIDTH slot: the world bar is a 1.5x0.32 quad, the card's bar is a ProgressBar in a
## 240px column, the hover bar is one in a 240px card. A bar that literally grew wider
## would overflow its slot (and, in the world bar's case, desynchronise the status-pip row
## and the damage-preview band, both of which map fractions onto FILL_MAX_WIDTH). So the
## segment is an appended TAIL inside the fixed track, and the two segments share ONE
## points-per-pixel scale:
##
##     denominator = max(max_hp, current + shield)
##
## which has the properties the design wants and the fixed slot needs:
##
##   * shield == 0            -> denominator == max_hp, i.e. EXACTLY today's bar. Not
##                              "almost": the same float, so a unit with no shield renders
##                              byte-identically to before this file existed.
##   * current + shield <= max -> the HP fill does not move at all; the silver tail simply
##                              claims part of the DEPLETED track ("the ward is standing in
##                              for the health you are missing"), at the same points-per-
##                              pixel as HP.
##   * current + shield > max  -> both segments rescale together so the tail still fits.
##                              The bar never overflows its slot, and HP-vs-shield stays
##                              readable as a ratio.

## The shield glyph, and a MEASURED choice rather than a taste one.
##
## The design called for ◈ (U+25C8, a diamond inside a diamond). The theme font cannot draw
## it, so shipping it would have put a tofu box on every HP surface in the game at once --
## exactly the failure this project has already had (a ⚔ that rendered as an empty box).
##
## `unit/test_shield_readout.gd` probes the real font and PRINTS the table. Measured on
## Godot 4.6's default font, the whole Geometric Shapes block is missing:
##
##     ◈ U+25C8 no    ◇ U+25C7 no    ◊ U+25CA YES   ● U+25CF no
##     ○ U+25CB no    ◆ U+25C6 no    ▲ U+25B2 no    ▼ U+25BC no    ■ U+25A0 no
##
## So the glyph is ◊ (U+25CA LOZENGE) -- the one shape in that family the font actually
## has, and a diamond outline, which is the closest drawable thing to the ◈ the design
## asked for.
##
## It also collides with nothing. The note that used to stand here -- that [StatusVisuals]'s
## own ◆▲●▼■ were all tofu in this font, i.e. every status chip and world-space badge in the
## game was drawing a box -- was true and has since been ACTED ON: that vocabulary now reads
## † + O - ~, all measured drawable, and none of them is ◊. The wider probe table lives in
## `unit/test_status_feedback.gd`; this file's is still the authority for the diamonds.
const GLYPH := "◊"

## Silver/steel. == [constant ConquestTheme.EL_STEEL], written out rather than referenced
## so this file has no load-order dependency on the theme (the same idiom
## [constant TerrainVisuals.GAIN_COLOR] uses).
const SILVER := Color("c9cbd6")

## The world-space bar's segment, a touch deeper so it reads as METAL over the dark track
## rather than as a wash-out at map distance.
const SILVER_WORLD := Color("aeb2c2")

## Fractions below this are not drawn at all: a sub-pixel sliver is noise, and skipping it
## is what guarantees "no shield == no artifacts" on every surface.
const MIN_FRACTION := 0.0005


## [param unit]'s current shield, or 0. Null-safe and duck-typed all the way down: a freed
## unit, a mock with no shield concept, or a plain Node all answer 0, so every caller can
## ask unconditionally.
static func shield_of(unit) -> int:
	if unit == null or typeof(unit) != TYPE_OBJECT:
		return 0
	if unit is Object and not is_instance_valid(unit):
		return 0
	if unit.has_method("get_shield"):
		return maxi(0, int(unit.get_shield()))
	if "shield_hp" in unit:
		return maxi(0, int(unit.get("shield_hp")))
	return 0


## The shared points-per-pixel denominator both segments are measured against. See the
## class doc for why it is this and not `current + shield`.
static func denominator(current: int, maximum: int, shield: int) -> int:
	return maxi(1, maxi(maxi(0, maximum), maxi(0, current) + maxi(0, shield)))


## `{ "hp": float, "shield": float }` -- the two segments as fractions of the WHOLE bar,
## in draw order (HP from the left edge, shield immediately after it). Their sum never
## exceeds 1.0, so no surface can ever overflow its slot.
##
## With [param shield] 0 this returns `hp == current / maximum` exactly, which is the
## number every one of these bars already drew.
static func bar_fractions(current: int, maximum: int, shield: int) -> Dictionary:
	var cur: int = clampi(current, 0, maxi(0, current))
	var sh: int = maxi(0, shield)
	var denom: float = float(denominator(cur, maximum, sh))
	var hp: float = clampf(float(cur) / denom, 0.0, 1.0)
	var shield_fraction: float = clampf(float(sh) / denom, 0.0, 1.0 - hp)
	return {"hp": hp, "shield": shield_fraction}


## "◊15" for a live shield, "" for none. The empty string is the contract every surface
## branches on: no shield means no label, no chip, no row -- not a "◊0".
static func number_text(shield: int) -> String:
	if shield <= 0:
		return ""
	return "%s%d" % [GLYPH, shield]


## "◊ 15" -- the spaced form, for the roomier surfaces (the detail page's stat table and
## the floating combat number).
static func spaced_number_text(shield: int) -> String:
	if shield <= 0:
		return ""
	return "%s %d" % [GLYPH, shield]


## "58/108" with no shield, "58/108 ◊15" with one. The single formatter for every HP
## numbers line, so the card and the hover card cannot drift.
static func hp_text(current: int, maximum: int, shield: int) -> String:
	var head: String = "%d/%d" % [current, maximum]
	var tail: String = number_text(shield)
	return head if tail == "" else "%s %s" % [head, tail]


## What the forecast says when the target is shielded: "absorbs 12 (3 left)".
##
## The SPLIT is not computed here -- it comes from [method Unit.absorb_split], the same
## function [method Unit.take_damage] burns the shield with, so the forecast can never
## advertise an absorption the hit would not perform (CONQUEST.md rule 9: preview and the
## live hit share one function, never two copies of one rule). Empty string when there is
## no shield or no damage, which is the caller's "hide the row" signal.
static func absorb_text(shield: int, damage: int) -> String:
	if shield <= 0 or damage <= 0:
		return ""
	var split: Dictionary = Unit.absorb_split(shield, damage)
	return "absorbs %d (%d left)" % [
		int(split.get("absorbed", 0)), int(split.get("shield_left", 0))]


## The floating number a soaked hit draws: "◊ 12", silver, in place of the white number
## that HP loss would have drawn. Empty when nothing was absorbed.
static func absorbed_popup_text(absorbed: int) -> String:
	return spaced_number_text(absorbed)
