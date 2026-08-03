extends RefCounted
class_name MoveStatVisuals

## Single source of truth for how a move's LIVE numbers read in the UI: how far a
## cooldown has recharged, and whether a stat the player is looking at is currently
## BOOSTED (or cut) relative to what the move was authored with.
##
## Deliberately shaped like [StatusVisuals] -- all statics, no state, every entry point
## null-safe and duck-typed -- so the two vocabularies behave identically and the move
## buttons ([MoveSelectionPanel], [UnitActionMenu]) and the [CombatForecastPanel] cannot
## drift apart about what "range 3 → 5" means.
##
## THE ONE RULE THIS FILE EXISTS TO ENFORCE: an effective value is READ THROUGH THE
## FUNCTION GAMEPLAY USES, never re-derived here. Reach comes from
## [method MoveResource.effective_max_range] -- the same helper the executor validates
## with, the targeting highlight draws with, and the AI plans with -- and the base it is
## compared against is the authored [member TargetingPattern.max_range] of the pattern in
## force for that caster (so a two-mode move reports the mode it is actually in). Unit
## stats come from the unit's own [code]get_stat[/code] / [code]get_base_stat[/code] pair.
## Recomputing "what the bonus probably is" in the UI is how a panel ends up lying about a
## reach the player then cannot actually use.

# --- Colours ------------------------------------------------------------------

## A value currently ABOVE its authored base. Green, and NOT one of the element hues,
## so a buffed stat never reads as a nature-element move.
const BUFF_COLOR := Color("6ddc63")
## A value currently BELOW its authored base.
const NERF_COLOR := Color("e2604f")
## The recharge bar's fill while a move is still charging (amber, so it belongs to the
## HUD rather than reading as a health/damage bar).
const RECHARGE_COLOR := Color("d9962f")
## The recharge bar's fill on the frame a move comes back up.
const READY_COLOR := Color("6ddc63")

const UP_ARROW := "▲"
const DOWN_ARROW := "▼"


# --- Cooldown -----------------------------------------------------------------

## How far a move has RECHARGED, 0.0 (just spent) .. 1.0 (ready), for a bar fill.
##
## A move with no authored cooldown is always fully charged, and so is one whose
## remaining count has reached 0 -- so a caller can render the bar unconditionally and a
## ready move simply shows a full one. Out-of-range inputs (a remaining count larger than
## the total, a negative) are clamped rather than rejected: this drives a visual, and a
## restored mid-battle save can legitimately hand it a count from an older cooldown value.
static func recharge_fraction(remaining: int, total: int) -> float:
	if total <= 0:
		return 1.0
	if remaining <= 0:
		return 1.0
	return clampf(float(total - remaining) / float(total), 0.0, 1.0)


## "2 turns" / "1 turn" while charging; "" when the move is ready, so a caller can test
## the string and omit the whole readout rather than printing a blank badge.
static func cooldown_label(remaining: int) -> String:
	if remaining <= 0:
		return ""
	if remaining == 1:
		return "1 turn"
	return "%d turns" % remaining


## The compact form for a button label: "CD 2/3" while charging, "" when ready. Shows
## BOTH numbers on purpose -- "2" alone says how long the wait is but not how long the
## wait WAS, which is the thing a player needs to plan a rotation.
static func cooldown_badge(remaining: int, total: int) -> String:
	if remaining <= 0:
		return ""
	if total <= 0:
		return "CD %d" % remaining
	return "CD %d/%d" % [remaining, total]


## Did this move just come back up? True only on the transition from charging to ready,
## which is what a one-shot "ready" flash must fire on -- a move that was ALREADY ready
## last time we looked must not flash again every time the panel repopulates.
static func became_ready(previous_remaining: int, remaining: int) -> bool:
	return previous_remaining > 0 and remaining <= 0


# --- Boosted stats -------------------------------------------------------------

## Is [param effective] different from [param base]? The single predicate every
## "should this be decorated?" question routes through, so "no boost -> no decoration"
## is one rule rather than an inequality re-typed at five call sites.
static func is_modified(base: int, effective: int) -> bool:
	return effective != base


## " ▲+2" / " ▼-1" / "" -- a suffix to append to an existing label. EMPTY when the value
## is unmodified, so an unbuffed move renders exactly as it always did.
static func delta_suffix(base: int, effective: int) -> String:
	if not is_modified(base, effective):
		return ""
	var delta: int = effective - base
	if delta > 0:
		return " %s+%d" % [UP_ARROW, delta]
	return " %s%d" % [DOWN_ARROW, delta]


## "Range 3 → 5" when modified, "Range 3" when not. The arrow form is used rather than
## a bare "5" because the player's question is not "what is my reach" but "did something
## change my reach", and only the before/after answers that.
static func stat_text(label: String, base: int, effective: int) -> String:
	if not is_modified(base, effective):
		return "%s %d" % [label, base]
	return "%s %d → %d" % [label, base, effective]


## The colour a modified value should be drawn in: green up, red down. Unmodified values
## get [param neutral] (default white) so a caller can pass its own theme ink and use the
## return unconditionally.
static func delta_color(base: int, effective: int, neutral: Color = Color.WHITE) -> Color:
	if effective > base:
		return BUFF_COLOR
	if effective < base:
		return NERF_COLOR
	return neutral


# --- Reading the live values ---------------------------------------------------

## Reach readout for [param move] as cast by [param caster]:
## [code]{ base, effective, modified, text, color }[/code].
##
## `effective` is [method MoveResource.effective_max_range] -- the gameplay helper, not a
## reimplementation of it -- and `base` is the authored max_range of the pattern in force
## for that caster. A null move, a move with no targeting pattern, or a caster that cannot
## answer all resolve to an unmodified 0, never to an error.
static func range_info(move, caster = null) -> Dictionary:
	var base: int = 0
	var effective: int = 0
	if move != null and typeof(move) == TYPE_OBJECT:
		var pattern = move.targeting_for(caster) if move.has_method("targeting_for") else null
		if pattern == null and "targeting" in move:
			pattern = move.targeting
		if pattern != null and "max_range" in pattern:
			base = int(pattern.max_range)
		effective = base
		if move.has_method("effective_max_range"):
			effective = int(move.effective_max_range(caster))
	return _info("Range", base, effective)


## The same readout for a plain unit stat, comparing the unit's EFFECTIVE
## [code]get_stat[/code] against its [code]get_base_stat[/code] -- the pair the stat
## modifier pipeline is built on, so every timed buff, item and status shows up here with
## no per-source knowledge. A unit missing either accessor reports unmodified.
static func stat_info(unit, stat_name: String, label: String = "") -> Dictionary:
	var base: int = 0
	var effective: int = 0
	if unit != null and typeof(unit) == TYPE_OBJECT and is_instance_valid(unit):
		if unit.has_method("get_stat"):
			effective = int(unit.get_stat(stat_name))
			base = effective
		if unit.has_method("get_base_stat"):
			base = int(unit.get_base_stat(stat_name))
	return _info(label if label != "" else stat_name.capitalize(), base, effective)


## The range phrase for a move BUTTON: the same wording
## [method TargetingPattern.describe_range] produces, but with the caster's live reach
## substituted for the authored one, so a button can never advertise a reach the player
## does not actually have. "range 5" / "range 1-5". Empty when there is no pattern.
static func range_phrase(move, caster = null) -> String:
	if move == null or typeof(move) != TYPE_OBJECT:
		return ""
	var pattern = move.targeting_for(caster) if move.has_method("targeting_for") else null
	if pattern == null and "targeting" in move:
		pattern = move.targeting
	if pattern == null:
		return ""
	var info: Dictionary = range_info(move, caster)
	var effective: int = int(info.get("effective", 0))
	var min_range: int = int(pattern.min_range) if "min_range" in pattern else 0
	if min_range == effective:
		return "range %d" % effective
	return "range %d-%d" % [min_range, effective]


# --- Widgets ------------------------------------------------------------------
#
# Built here rather than in each panel so the recharge bar looks and behaves identically
# on the contextual action menu and in the SELECT MOVE card. Construction only -- the
# panels own the nodes they get back.

## A thin horizontal recharge bar, sized for a move row. Starts full/ready; drive it with
## [method update_recharge_bar].
static func make_recharge_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = "RechargeBar"
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.custom_minimum_size = Vector2(0, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


## Point [param bar] at a move's live cooldown. Hidden entirely for a move with no
## authored cooldown (nothing to recharge, so nothing to draw); amber while charging,
## green on the turn it comes back up.
static func update_recharge_bar(bar: ProgressBar, remaining: int, total: int) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	if total <= 0:
		bar.visible = false
		return
	bar.visible = true
	bar.value = recharge_fraction(remaining, total)
	var fill := StyleBoxFlat.new()
	fill.bg_color = READY_COLOR if remaining <= 0 else RECHARGE_COLOR
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)


## One-shot "it's back" pulse on a move row that just came off cooldown. Honours the
## global animations toggle (with animations off it simply leaves the row untinted, so
## nothing is stuck mid-tween). Safe on a detached control -- a Tween cannot be created
## off-tree, so it no-ops there exactly like the floating numbers do.
static func flash_ready(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		return
	var settings := control.get_node_or_null("/root/GameSettings")
	if settings != null and settings.has_method("animations_on") and not settings.animations_on():
		control.modulate = Color.WHITE
		return
	control.modulate = READY_COLOR
	var tween := control.create_tween()
	tween.tween_property(control, "modulate", Color.WHITE, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func _info(label: String, base: int, effective: int) -> Dictionary:
	return {
		"base": base,
		"effective": effective,
		"modified": is_modified(base, effective),
		"text": stat_text(label, base, effective),
		"suffix": delta_suffix(base, effective),
		"color": delta_color(base, effective),
	}
