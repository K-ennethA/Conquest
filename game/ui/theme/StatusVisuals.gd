extends RefCounted
class_name StatusVisuals

## Single source of truth for how a [StatusCondition] LOOKS and READS, shared by
## every surface that shows one: the world-space status pips on [HealthBar], the
## effect chips in [UnitInfoPanel], and the hover card [UnitHoverPanel].
##
## Deliberately mirrors [TileEffectVisuals] (same table shape, same fallback
## contract, same "always return a fresh dictionary" rule) so the two vocabularies
## behave identically and a reader who knows one knows the other. Centralizing it
## means "Ensnared" is the same violet everywhere instead of drifting per screen.
##
## kind: "debuff" (hurts the afflicted unit), "buff" (helps it), "neutral".
## Buffs sit in the green / blue / amber family and debuffs in the violet / rose /
## ember family, so which side of the ledger a pip is on reads at a glance even
## before the name is legible.
##
## Extending it is one line: add a row to _TABLE. Any id NOT in the table still
## renders -- it just falls back to the generic neutral descriptor -- so a status
## authored later is visible immediately and can be given a colour afterwards.

const _TABLE := {
	# --- Debuffs -------------------------------------------------------------
	&"ensnared":   { "name": "Ensnared",   "color": Color("9b4bd6"), "kind": "debuff" },
	&"rubble_slowed": { "name": "Slowed",  "color": Color("8a6fd1"), "kind": "debuff" },
	&"entangled":  { "name": "Entangled",  "color": Color("c9457d"), "kind": "debuff" },
	# Blightcap's poison. TOXIC CHARTREUSE -- the most yellow of the three greens in
	# this table, so it never reads as Regeneration (mid green) or Ingrained (olive);
	# its DOT glyph separates it again (see [method glyph_for_id]). Was missing here
	# entirely, which is why a poisoned unit showed the generic tan fallback pip and
	# the player could not tell poison was on the board at all.
	&"poisoned":   { "name": "Poisoned",   "color": Color("84c318"), "kind": "debuff" },
	# Mycothrall's infection counter (STACKs toward mind control).
	&"infested":   { "name": "Infested",   "color": Color("6f3f8f"), "kind": "debuff" },
	# The hijack itself -- the loudest hue in the table, because a unit fighting for
	# the other side is the single most important thing on screen.
	&"enthralled": { "name": "Enthralled", "color": Color("e05fd0"), "kind": "debuff" },
	# Self-applied trade-off (Petalfang's Ingrained): roots the unit but extends the
	# reach of every move. Filed as a BUFF because it is chosen, not inflicted --
	# the root is the price, not the point. Earthy green so it never reads as one of
	# the violet/rose restraints an ENEMY put on you.
	&"ingrained":  { "name": "Ingrained",  "color": Color("6f8f4e"), "kind": "buff" },
	&"burn":       { "name": "Burn",       "color": Color("e0552b"), "kind": "debuff" },
	# Timberfall's flinch: the unit loses its whole next turn. Deep ember rather
	# than the violet restraints, because it is a CONCUSSIVE effect (you were hit
	# too hard) rather than something binding you in place.
	&"flinched":   { "name": "Flinched",   "color": Color("b03a3a"), "kind": "debuff" },
	# --- Buffs ---------------------------------------------------------------
	# Heartwood Guard: one turn of taking no damage at all. Pale bark-grey blue --
	# deliberately the coolest, most inert hue in the table, since the fantasy is
	# "closed up and unreachable" rather than "empowered".
	&"guarded":    { "name": "Guarded",    "color": Color("8fa8c9"), "kind": "buff" },
	&"regen":      { "name": "Regeneration", "color": Color("4fbf6a"), "kind": "buff" },
	&"fortified":  { "name": "Fortified",  "color": Color("c79a3b"), "kind": "buff" },
	&"hastened":   { "name": "Hastened",   "color": Color("3fa9e0"), "kind": "buff" },
	&"braced":     { "name": "Braced",     "color": Color("5f8f9f"), "kind": "buff" },
	&"empowered":  { "name": "Empowered",  "color": Color("ffcf4d"), "kind": "buff" },
	&"prism_guard": { "name": "Prism Guard", "color": Color("9fd8e8"), "kind": "buff" },
	&"reprisal_charge": { "name": "Reprisal Charge", "color": Color("ff8f5e"), "kind": "buff" },
}

# --- Glyphs -------------------------------------------------------------------
#
# A one-character ICON per status, so a pip on the world-space health bar says WHAT
# KIND of thing is on the unit before its colour is even resolved (and so a
# colour-blind player still gets a signal).
#
# The set is deliberately tiny and drawn only from characters this project already
# renders elsewhere (the ▲ / ▼ on the battle card's stat chips, via MoveStatVisuals).
# Anything exotic -- a skull,
# a heavy plus, a shield -- is outside Godot's default font and would draw as tofu on
# the one surface (a Label3D over the battlefield) that cannot fall back to another
# font. Category, not identity: the NAME and the COLOUR identify the status, the
# glyph says which of five things it is doing to the unit.
const GLYPH_DOT := "◆"      # damage over time (poison, burn, infestation)
const GLYPH_HOT := "▲"      # heal over time -- shares the buff arrow on purpose
const GLYPH_GUARD := "●"    # damage reduction / invulnerability
const GLYPH_BUFF := "▲"
const GLYPH_DEBUFF := "▼"
const GLYPH_NEUTRAL := "■"

## Ids whose glyph is NOT derivable from `kind` -- a damage-over-time debuff and a
## defensive buff both need to stand apart from the plain up/down arrows.
const _GLYPH_OVERRIDES := {
	&"poisoned": GLYPH_DOT,
	&"burn": GLYPH_DOT,
	&"infested": GLYPH_DOT,
	&"regen": GLYPH_HOT,
	&"guarded": GLYPH_GUARD,
	&"braced": GLYPH_GUARD,
	&"prism_guard": GLYPH_GUARD,
	&"fortified": GLYPH_GUARD,
}

const _FALLBACK := { "name": "Status", "color": Color("9a8768"), "kind": "neutral" }

## Colour for the "…and N more" overflow marker (a pip / chip that stands for the
## statuses we ran out of room for). Deliberately outside every table hue so it
## never reads as a real status.
const OVERFLOW_COLOR := Color("cfc4ae")

## How many pip slots a compact surface (the world-space health bar) may use.
## Beyond this the last slot becomes the overflow marker -- see [method shown_count].
const MAX_PIPS: int = 4

## Player-facing wording for the rule flags a status can impose. A rule flag says
## "your rules are different right now" without applying anything, so it has no
## MoveEffect.describe() of its own -- this is where it gets its words.
## Unknown keys are humanized ("cannot_act" -> "Cannot Act") rather than dropped.
const _RULE_FLAG_WORDS := {
	"immobilized": "Cannot move",
	"immobilised": "Cannot move",
	"silenced": "Cannot use moves",
	"untargetable": "Cannot be targeted",
	"cannot_act": "Cannot act",
	"invulnerable": "Takes no damage",
	"stunned": "Skips its next turn",
}


# --- Vocabulary lookup -------------------------------------------------------

## Visual descriptor for a [StatusCondition] (or anything exposing id /
## display_name). Always returns a FRESH dictionary: { name, color, kind }.
## Returning a copy matters -- callers tint and mutate these, and the table must
## stay immutable so two lookups of the same id always agree.
static func info_for(condition) -> Dictionary:
	var id: StringName = &""
	var disp: String = ""
	if condition != null and typeof(condition) == TYPE_OBJECT:
		if "id" in condition:
			id = condition.id
		if "display_name" in condition and String(condition.display_name) != "":
			disp = String(condition.display_name)
	var out: Dictionary = (_TABLE.get(id, _FALLBACK) as Dictionary).duplicate()
	if disp != "":
		out["name"] = disp  # honour an authored display_name over the table default
	return out


## Same lookup keyed directly by status id (for callers without the resource).
static func info_for_id(id: StringName) -> Dictionary:
	return (_TABLE.get(id, _FALLBACK) as Dictionary).duplicate()


## True when [param id] has an authored row (as opposed to falling back).
static func is_known_id(id: StringName) -> bool:
	return _TABLE.has(id)


## The one-character icon for [param id]: an authored override when the status needs
## to stand apart (damage-over-time, a guard), otherwise the arrow for its kind.
## An unknown id is neutral, never blank -- a pip with no glyph reads as a bug.
static func glyph_for_id(id: StringName) -> String:
	if _GLYPH_OVERRIDES.has(id):
		return String(_GLYPH_OVERRIDES[id])
	return _glyph_for_kind(String((_TABLE.get(id, _FALLBACK) as Dictionary).get("kind", "neutral")))


## [method glyph_for_id] for a live condition instance (or anything exposing `id`).
static func glyph_for(condition) -> String:
	if condition != null and typeof(condition) == TYPE_OBJECT and "id" in condition:
		return glyph_for_id(condition.id)
	return GLYPH_NEUTRAL


static func _glyph_for_kind(kind: String) -> String:
	match kind:
		"buff":
			return GLYPH_BUFF
		"debuff":
			return GLYPH_DEBUFF
		_:
			return GLYPH_NEUTRAL


# --- Formatting helpers ------------------------------------------------------

## "3 turns" / "1 turn" / "Permanent". A negative remaining count is the
## permanent sentinel used by [StatusCondition]; 0 is rendered plainly rather
## than specially, since a 0-turn condition is about to expire, not forever.
static func turns_label(turns_left: int) -> String:
	if turns_left < 0:
		return "Permanent"
	if turns_left == 1:
		return "1 turn"
	return "%d turns" % turns_left


## "+2" for an overflow marker standing in for 2 unshown statuses; "" when
## nothing is hidden (so callers can test the string and skip the marker).
static func overflow_label(hidden: int) -> String:
	if hidden <= 0:
		return ""
	return "+%d" % hidden


## " x3" for a status stacked three deep; "" for a single instance, so a caller can
## append it unconditionally. Severity is [method StatusController.stack_count] --
## three live Poisoned instances is ONE status at severity 3, not three badges.
static func stack_suffix(count: int) -> String:
	if count <= 1:
		return ""
	return " x%d" % count


## Sentinel for [method chip_text]'s [code]turns_left[/code]: "read it off the
## condition". It cannot be a plain -1, because -1 is the PERMANENT duration and a
## caller must be able to pass it deliberately.
const TURNS_FROM_CONDITION: int = -999999

## The full one-line label for a status chip / hover row:
## "◆ Poisoned x3 · 2 turns". [param count] is the live stack count (1 = unstacked,
## so the suffix disappears); [param turns_left] defaults to the condition's own
## remaining turns but may be overridden with a GROUP's longest (see
## [method group_by_id]) so a stack reports when the status actually leaves the unit.
## Everything degrades: an unknown id still gets a name, a colour, a neutral glyph,
## and its turn count.
static func chip_text(condition, count: int = 1, turns_left: int = TURNS_FROM_CONDITION) -> String:
	var info: Dictionary = info_for(condition)
	var turns: int = turns_left_of(condition) if turns_left == TURNS_FROM_CONDITION else turns_left
	return "%s %s%s · %s" % [
		glyph_for(condition),
		String(info.get("name", "Status")),
		stack_suffix(count),
		turns_label(turns),
	]


## Floating shout when a status LANDS: "POISONED". Upper-cased because it is a
## 0.6-second label over a unit competing with damage numbers -- it has to read in
## one glance or not at all.
static func applied_label(condition) -> String:
	var name_text: String = String(info_for(condition).get("name", "Status"))
	if name_text == "":
		return ""
	return name_text.to_upper()


## Floating shout when a status runs out: "Poisoned faded". Sentence case (not the
## shout above) precisely so the two are never confused at a glance.
static func expired_label(condition) -> String:
	var name_text: String = String(info_for(condition).get("name", "Status"))
	if name_text == "":
		return ""
	return "%s faded" % name_text


## The floating text for one status TICK: the status' glyph and the HP it just moved.
## Heals are signed ("▲ +5"), damage is bare ("◆ 4") -- exactly the convention the
## ordinary damage/heal popups already use, so a status tick reads as the same kind of
## event with a status marker on it. Empty for a non-positive amount (nothing happened).
static func tick_text(condition, amount: int, healed: bool) -> String:
	if amount <= 0:
		return ""
	if healed:
		return "%s +%d" % [glyph_for(condition), amount]
	return "%s %d" % [glyph_for(condition), amount]


## Collapse a raw condition list into one entry per status id, in first-applied order:
## [code][{ "condition": <first instance>, "count": int, "turns_left": int }][/code].
##
## Every compact surface (the health-bar pips, the hover chips) wants SEVERITY, not
## instances: three stacked Poisoned conditions must render as one "◆ Poisoned x3"
## chip, not as three identical pips that eat the whole 4-slot budget and hide the
## other statuses on the unit. `turns_left` is the LONGEST of the group -- that is when
## the status actually leaves the unit.
static func group_by_id(conditions: Array) -> Array:
	var order: Array = []
	var by_id: Dictionary = {}
	for condition in conditions:
		if condition == null or typeof(condition) != TYPE_OBJECT:
			continue
		var id: StringName = condition.id if "id" in condition else &""
		var turns: int = turns_left_of(condition)
		if by_id.has(id):
			var entry: Dictionary = by_id[id]
			entry["count"] = int(entry["count"]) + 1
			# -1 is the permanent sentinel and outranks any finite count.
			var best: int = int(entry["turns_left"])
			if best >= 0 and (turns < 0 or turns > best):
				entry["turns_left"] = turns
		else:
			var fresh: Dictionary = { "condition": condition, "count": 1, "turns_left": turns }
			by_id[id] = fresh
			order.append(fresh)
	return order


## How many real status pips a surface with [param cap] slots should draw.
## When everything fits, all of them; otherwise cap-1, because the final slot is
## spent on the overflow marker.
static func shown_count(total: int, cap: int = MAX_PIPS) -> int:
	if total <= cap:
		return maxi(0, total)
	return maxi(0, cap - 1)


## How many statuses the overflow marker stands for. 0 when everything fits.
static func hidden_count(total: int, cap: int = MAX_PIPS) -> int:
	if total <= cap:
		return 0
	return total - maxi(0, cap - 1)


# --- Reading the (in-flight) status API defensively --------------------------

## The live [StatusCondition]s on [param unit], or an EMPTY array for anything
## that cannot answer: a null/freed unit, a non-object, a unit with no
## StatusController (legacy units, headless tests), or a controller whose accessor
## is missing. Null entries inside the list are filtered out.
##
## Every access is duck-typed on purpose -- the status layer is actively growing
## new members, so this must never hard-depend on one having landed.
static func active_conditions(unit) -> Array:
	var out: Array = []
	if unit == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		return out

	var controller = null
	if unit.has_method("get_status_controller"):
		controller = unit.get_status_controller()
	if controller == null and unit is Node:
		controller = (unit as Node).get_node_or_null("StatusController")
	if controller == null or not is_instance_valid(controller):
		return out

	var raw = null
	if controller.has_method("get_active"):
		raw = controller.get_active()
	if raw == null and "_active" in controller:
		raw = controller.get("_active")
	if not (raw is Array):
		return out

	for condition in (raw as Array):
		if condition != null:
			out.append(condition)
	return out


## Remaining turns on a live condition instance, or 0 when it cannot say.
static func turns_left_of(condition) -> int:
	if condition == null or typeof(condition) != TYPE_OBJECT:
		return 0
	if "turns_left" in condition:
		return int(condition.turns_left)
	if "duration_turns" in condition:
		return int(condition.duration_turns)
	return 0


## One player-facing sentence for what a condition DOES: its standing rule
## changes first ("Cannot move"), then what its per-turn effects do (joined from
## each [MoveEffect.describe]). Empty string when the condition does nothing
## describable, so callers can omit the line instead of printing a blank.
##
## [code]rule_flags[/code] is read through an `in` check rather than accessed
## directly: it is being added to [StatusCondition] concurrently, and a build
## where it has not landed yet must degrade to "just the tick effects", not error.
static func describe_condition(condition) -> String:
	if condition == null or typeof(condition) != TYPE_OBJECT:
		return ""
	var parts: PackedStringArray = []

	if "rule_flags" in condition:
		var flags = condition.get("rule_flags")
		if flags is Dictionary:
			var flag_dict: Dictionary = flags as Dictionary
			for key in flag_dict:
				if not bool(flag_dict[key]):
					continue
				var word: String = String(_RULE_FLAG_WORDS.get(String(key), ""))
				if word == "":
					word = humanize(String(key))
				parts.append(word)

	if "tick_effects" in condition:
		var effects = condition.get("tick_effects")
		if effects is Array:
			for effect in (effects as Array):
				if effect == null or typeof(effect) != TYPE_OBJECT:
					continue
				if not effect.has_method("describe"):
					continue
				var text: String = String(effect.describe()).strip_edges()
				if text != "":
					parts.append(text)

	return ", ".join(parts)


## "cannot_act" -> "Cannot Act". Empty in -> empty out.
static func humanize(raw: String) -> String:
	if raw == "":
		return ""
	var words: PackedStringArray = []
	for w in raw.replace("_", " ").split(" ", false):
		if w.length() > 0:
			words.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(words)
