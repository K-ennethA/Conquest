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
	&"entangled":  { "name": "Entangled",  "color": Color("c9457d"), "kind": "debuff" },
	# Self-applied trade-off (Petalfang's Ingrained): roots the unit but extends the
	# reach of every move. Filed as a BUFF because it is chosen, not inflicted --
	# the root is the price, not the point. Earthy green so it never reads as one of
	# the violet/rose restraints an ENEMY put on you.
	&"ingrained":  { "name": "Ingrained",  "color": Color("6f8f4e"), "kind": "buff" },
	&"burn":       { "name": "Burn",       "color": Color("e0552b"), "kind": "debuff" },
	# --- Buffs ---------------------------------------------------------------
	&"regen":      { "name": "Regeneration", "color": Color("4fbf6a"), "kind": "buff" },
	&"fortified":  { "name": "Fortified",  "color": Color("c79a3b"), "kind": "buff" },
	&"hastened":   { "name": "Hastened",   "color": Color("3fa9e0"), "kind": "buff" },
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
