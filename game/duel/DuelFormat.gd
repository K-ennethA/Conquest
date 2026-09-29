extends Resource
class_name DuelFormat

## A DUEL FORMAT: how big a side's team is and the rules around it (docs/design/DUEL_BATTLE.md
## §4.2, DECISIONS.md #3: party size is a ruleset knob). Pure data plus pure rules -- the one
## place "1v1 / 3v3 / 6v6 / custom" is decided, used alike by the hot-seat setup, the online
## lobby (it rides the match config as [method to_dict]) and story duels.
##
## A format never mutates the shared [DuelRuleset] (rule 7): [method apply_to] hands back a
## DUPLICATE with the format's knobs written onto it, and that copy is what the [DuelBattle]
## registers with ModeTuning -- so the engine still reads every duel number through ONE surface.
##
## PRESETS: Singles 1v1 (the M1 duel), Trio 3v3 and Full 6v6 (switching, KO replacement, species
## clause). [constant STORY] is the story party's shape (lead + up to 2 bench, no species clause:
## a journey may own several of one species -- DECISIONS.md #9). Anything else is CUSTOM.
##
## ACTIVE PER SIDE: 1 = singles, the only mode built. 2 (doubles) is reserved: [method validate]
## refuses it until the engine fields two stations per side.

const SINGLES := "singles"
const TRIO := "trio"
const FULL := "full"
const STORY := "story"
const CUSTOM := "custom"
## The presets a menu offers (story is the story's own, never listed).
const MENU_IDS: Array[String] = [SINGLES, TRIO, FULL]
const PRESET_IDS: Array[String] = [SINGLES, TRIO, FULL, STORY]
const MAX_TEAM := 6

@export var id: String = SINGLES
@export var display_name: String = "Singles"
## Units a side brings: the lead plus (team_size - 1) on the bench.
@export_range(1, 6) var team_size: int = 1
## Units each side has on the field at once. Only 1 (singles) is built; doubles is a follow-up.
@export_range(1, 2) var active_per_side: int = 1
## The Party action: a voluntary switch (costs the switching side's turn).
@export var allow_switch: bool = false
## A KO'd lead's owner CHOOSES the replacement (free). Off: the next healthy member in team
## order is sent in automatically. Either way a side only loses when nobody is left.
@export var ko_replacement: bool = true
## The Items action (battle consumables from the side's bag). A request with no bag has none.
@export var allow_battle_items: bool = true
## Equipment (held items) is applied to the combatants.
@export var allow_held_items: bool = true
## No two members of one team may be the same character.
@export var species_clause: bool = false
## Highest [member DuelCombatant.strength] a combatant fights at (0 = no cap).
@export_range(0.0, 10.0, 0.01) var strength_cap: float = 0.0


## A FRESH preset (never a shared instance: callers may edit their copy). Unknown ids -> null.
static func preset(p_id: String) -> DuelFormat:
	var f := DuelFormat.new()
	f.id = p_id
	match p_id:
		SINGLES:
			f.display_name = "Singles"
			f.team_size = 1
		TRIO:
			f.display_name = "Trio"
			f.team_size = 3
			f.allow_switch = true
			f.species_clause = true
		FULL:
			f.display_name = "Full Party"
			f.team_size = 6
			f.allow_switch = true
			f.species_clause = true
		STORY:
			f.display_name = "Party"
			f.team_size = 3
			f.allow_switch = true
		_:
			return null
	return f


## The menu presets, in order.
static func menu_presets() -> Array[DuelFormat]:
	var out: Array[DuelFormat] = []
	for p in MENU_IDS:
		out.append(preset(p))
	return out


## "3v3", "1v1" ...
func versus_label() -> String:
	return "%dv%d" % [team_size, team_size]


## One line for a menu: "Trio 3v3 · switching · species clause".
func summary() -> String:
	var bits: Array[String] = ["%s %s" % [display_name, versus_label()]]
	if team_size > 1:
		bits.append("switching" if allow_switch else "no switching")
		if not ko_replacement:
			bits.append("auto replacement")
	if species_clause:
		bits.append("species clause")
	if strength_cap > 0.0:
		bits.append("strength ≤ %s" % str(snappedf(strength_cap, 0.01)))
	return " · ".join(bits)


func is_party() -> bool:
	return team_size > 1


## Semantic check. {success, reason} (rule 1: never logs).
func validate() -> Dictionary:
	if team_size < 1 or team_size > MAX_TEAM:
		return {"success": false, "reason": "bad_team_size"}
	if active_per_side != 1:
		return {"success": false, "reason": "doubles_not_built"}
	if strength_cap < 0.0:
		return {"success": false, "reason": "bad_strength_cap"}
	return {"success": true, "reason": ""}


## The strength a combatant authored at [param strength] fights at under this format.
func clamp_strength(strength: float) -> float:
	if strength_cap > 0.0:
		return minf(strength, strength_cap)
	return strength


## Why [param ids] (one side's team, lead first) is not a legal team for this format, or "".
## [param exact] requires exactly [member team_size] members (hot-seat / online); otherwise
## 1..team_size (story: a young journey fields what it has).
func team_problem(ids: Array, exact: bool = true) -> String:
	if ids.is_empty() or ids.size() > team_size or (exact and ids.size() != team_size):
		return "bad_team_size"
	if species_clause:
		var seen: Dictionary = {}
		for i in ids:
			var k := String(i)
			if seen.has(k):
				return "species_clause"
			seen[k] = true
	return ""


## [param base] with this format's knobs written onto a DUPLICATE (the shared resource is never
## touched -- rule 7). Switching / KO replacement only mean something with a bench.
func apply_to(base: DuelRuleset) -> DuelRuleset:
	var rules: DuelRuleset = (base if base != null else DuelRuleset.load_default()).duplicate()
	rules.party_size = team_size
	rules.allow_switch = allow_switch and team_size > 1
	rules.ko_replacement = ko_replacement and team_size > 1
	rules.allow_items = rules.allow_items and allow_battle_items
	rules.allow_held_items = allow_held_items
	rules.species_clause = species_clause
	rules.strength_cap = strength_cap
	return rules


func to_dict() -> Dictionary:
	return {
		"id": id,
		"team_size": team_size,
		"active_per_side": active_per_side,
		"allow_switch": allow_switch,
		"ko_replacement": ko_replacement,
		"allow_battle_items": allow_battle_items,
		"allow_held_items": allow_held_items,
		"species_clause": species_clause,
		"strength_cap": strength_cap,
	}


## STRICT importer (CONQUEST.md rule 8: a match config / replay header is untrusted). Accepts a
## preset id String or a dictionary (a preset id plus overrides, or a custom format); every
## field is type-checked and [method validate]d. Returns {success, reason, format}.
static func from_dict(d) -> Dictionary:
	if d is String or d is StringName:
		var p := preset(String(d))
		return _ok(p) if p != null else _fail("unknown_format")
	if not (d is Dictionary):
		return _fail("bad_format")
	var raw_id = d.get("id", CUSTOM)
	if not (raw_id is String or raw_id is StringName):
		return _fail("bad_format")
	var f: DuelFormat = preset(String(raw_id))
	if f == null:
		f = DuelFormat.new()
		f.id = CUSTOM
		f.display_name = "Custom"
	for key in ["team_size", "active_per_side"]:
		if d.has(key):
			var v = d[key]
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				return _fail("bad_format")
			f.set(key, int(v))
	for key in ["allow_switch", "ko_replacement", "allow_battle_items", "allow_held_items", "species_clause"]:
		if d.has(key):
			if typeof(d[key]) != TYPE_BOOL:
				return _fail("bad_format")
			f.set(key, bool(d[key]))
	if d.has("strength_cap"):
		var c = d["strength_cap"]
		if typeof(c) != TYPE_INT and typeof(c) != TYPE_FLOAT:
			return _fail("bad_format")
		f.strength_cap = float(c)
	# A preset id whose numbers were changed is a custom format now.
	if f.id != CUSTOM:
		var ref := preset(f.id)
		if ref.to_dict() != f.to_dict():
			f.id = CUSTOM
			f.display_name = "Custom"
	var check := f.validate()
	if not bool(check["success"]):
		return _fail(String(check["reason"]))
	return _ok(f)


static func _ok(f: DuelFormat) -> Dictionary:
	return {"success": true, "reason": "", "format": f}


static func _fail(reason: String) -> Dictionary:
	return {"success": false, "reason": reason, "format": null}
