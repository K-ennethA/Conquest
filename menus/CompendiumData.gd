extends RefCounted
class_name CompendiumData

## The Compendium's DATA MODEL: every entry of every data-driven section, derived
## from the authored resources (never hand-written), so new content shows up on its
## own -- a new WeatherResource, TileEffectResource, StatusCondition, roster unit,
## move or ability appears in the encyclopedia without touching this file.
##
## Also the single source for the in-battle TOOLTIPS (weather chip, status chips,
## terrain card): [method weather_tooltip], [method status_tooltip] and
## [method tile_effect_tooltip] word things exactly like the Compendium does.
##
## An ENTRY is a Dictionary:
##   section  : SECTION_* id
##   id       : String (unique within the section)
##   title    : String
##   subtitle : String (one line)
##   color    : Color (accent)
##   icon     : StringName (WeatherIcon kind for weather entries, else &"")
##   blocks   : Array of blocks, rendered in order by the Compendium:
##       { type: "text",    text }                     -- BBCode allowed
##       { type: "heading", text }
##       { type: "bullets", items: Array[String] }     -- BBCode allowed
##       { type: "fields",  rows: [[key, value], ...] }
##       { type: "table",   columns: [...], rows: [[...], ...], colors: [[Color|null]] }
##   keywords : String (lower-case search haystack)
##
## Cross-links are BBCode [url=<section>:<id>]..[/url] -- e.g.
## [code][url=weather:rain]Rain[/url][/code] -- which the Compendium follows.
##
## ELEMENTS. Every element number comes from the ONE element-matchup source the damage
## pipeline reads -- [ElementChart] over [code]element_chart.tres[/code] -- through the
## same derivations the Compendium's type chart page draws with ([ElementChartGallery]).
## This file never holds a matchup of its own, so the Rules text, the element entries,
## the tile-effect element lines and the chart grid cannot disagree.

const SECTION_UNITS := "units"
const SECTION_WEATHER := "weather"
const SECTION_TILES := "tiles"
const SECTION_STATUSES := "statuses"
const SECTION_ELEMENTS := "elements"
const SECTION_RULES := "rules"

const TILE_EFFECT_DIR := "res://game/tiles/effects/resources/"
const MOVES_DIR := "res://game/combat/moves/"
const MAPS_DIR := "res://game/maps/resources/"

const TRIGGER_TEXT := {
	TileEffectResource.Trigger.ON_ENTER: "On enter",
	TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING: "Turn start",
	TileEffectResource.Trigger.ON_EXIT: "On exit",
	TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING: "Passive",
}
const TRIGGER_LONG := {
	TileEffectResource.Trigger.ON_ENTER: "When a unit steps onto the tile",
	TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING: "At the start of each turn a unit spends on the tile",
	TileEffectResource.Trigger.ON_EXIT: "When a unit leaves the tile",
	TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING: "Constantly, while a unit stands on the tile",
}

static var _cache: Dictionary = {}


## Drop every cached section (content reloaded / tests).
static func clear_cache() -> void:
	_cache.clear()


## Every entry of [param section] (cached).
static func entries(section: String) -> Array:
	if _cache.has(section):
		return _cache[section]
	var out: Array = []
	match section:
		SECTION_UNITS: out = unit_entries()
		SECTION_WEATHER: out = weather_entries()
		SECTION_TILES: out = tile_effect_entries()
		SECTION_STATUSES: out = status_entries()
		SECTION_ELEMENTS: out = element_entries()
		SECTION_RULES: out = rules_entries()
	_cache[section] = out
	return out


## Every entry of every section, for the global search.
static func all_entries() -> Array:
	var out: Array = []
	for s in [SECTION_UNITS, SECTION_WEATHER, SECTION_TILES, SECTION_STATUSES, SECTION_ELEMENTS, SECTION_RULES]:
		out.append_array(entries(s))
	return out


## The entry [param id] of [param section], or {}.
static func find(section: String, id: String) -> Dictionary:
	for e in entries(section):
		if String(e["id"]) == id:
			return e
	return {}


## Case-insensitive filter over title + keywords.
static func search(list: Array, text: String) -> Array:
	var q := text.strip_edges().to_lower()
	if q == "":
		return list
	# Rank: exact title, title prefix, title contains, a keyword word starting with
	# the query, then any keyword substring (so "rain" lists Rain before Soul Drain).
	var scored: Array = []
	var word := RegEx.new()
	word.compile("(^|[^a-z])" + _regex_escape(q))
	for i in list.size():
		var e: Dictionary = list[i]
		var t := String(e.get("title", "")).to_lower()
		var kw := String(e.get("keywords", ""))
		var score := -1
		if t == q:
			score = 0
		elif t.begins_with(q):
			score = 1
		elif t.contains(q):
			score = 2
		elif word.search(kw) != null:
			score = 3
		elif kw.contains(q):
			score = 4
		if score >= 0:
			scored.append([score, i, e])
	scored.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return scored.map(func(x): return x[2])


static func _regex_escape(t: String) -> String:
	var out := ""
	for ch in t:
		out += ("\\" + ch) if ch in ".^$*+?()[]{}|\\/" else ch
	return out


# =============================================================================
# Content scans
# =============================================================================

## Roster characters, sorted by name.
static func roster() -> Array:
	var out: Array = []
	for id in CharacterLibrary.all_ids():
		var c := CharacterLibrary.get_character(id)
		if c != null:
			out.append(c)
	out.sort_custom(func(a, b): return _char_name(a).naturalnocasecmp_to(_char_name(b)) < 0)
	return out


## Paths of every authored TileEffectResource (cheap: no loading).
static func tile_effect_paths() -> Array:
	return _tres_in(TILE_EFFECT_DIR)


## Every authored TileEffectResource (scan of [constant TILE_EFFECT_DIR]).
static func tile_effects() -> Array:
	var out: Array = []
	for path in _tres_in(TILE_EFFECT_DIR):
		var r = load(path)
		if r is TileEffectResource:
			out.append(r)
	return out


## Every authored WeatherResource, Clear first.
static func weathers() -> Array:
	var out: Array = []
	for id in Weather.all_ids():
		out.append(Weather.get_weather(id))
	return out


## Every MapResource in the maps folder (named ones only).
static func maps() -> Array:
	var out: Array = []
	for path in _tres_in(MAPS_DIR):
		var r = load(path)
		if r is MapResource and String(r.map_name) != "":
			out.append(r)
	out.sort_custom(func(a, b): return String(a.map_name).naturalnocasecmp_to(String(b.map_name)) < 0)
	return out


## Every move: the roster movesets plus the shared moves folder, deduped.
static func all_moves() -> Array:
	var out: Array = []
	for c in roster():
		for m in c.moveset:
			if m != null and m not in out:
				out.append(m)
	for path in _tres_in(MOVES_DIR):
		var r = load(path)
		if r is MoveResource and r not in out:
			out.append(r)
	return out


static func _tres_in(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var p := dir_path + name
			if p not in out:
				out.append(p)
	out.sort()
	return out


# =============================================================================
# Weather
# =============================================================================

static func weather_entries() -> Array:
	var out: Array = []
	for w in weathers():
		out.append(weather_entry(w))
	return out


static func weather_entry(w: WeatherResource) -> Dictionary:
	var blocks: Array = []
	blocks.append({ "type": "text", "text": w.description if w.description != "" else "No special rules." })
	blocks.append({ "type": "heading", "text": "Effects" })
	var rows := weather_effect_rows(w)
	if rows.is_empty():
		blocks.append({ "type": "text", "text": "[color=#9ba5c8]No combat effects.[/color]" })
	else:
		blocks.append({ "type": "table", "columns": ["Rule", "Effect", "Who"], "rows": rows })
	var map_lines := weather_map_lines(w.id)
	blocks.append({ "type": "heading", "text": "Maps" })
	blocks.append({ "type": "bullets", "items": map_lines if not map_lines.is_empty() else ["Not scheduled on any map (it can still be summoned)."] })
	var unit_lines := weather_unit_lines(w.id)
	if not unit_lines.is_empty():
		blocks.append({ "type": "heading", "text": "Units that react to it" })
		blocks.append({ "type": "bullets", "items": unit_lines })
	var kw := "%s %s %s" % [w.display_name, w.id, w.description]
	for r in rows:
		kw += " " + " ".join(PackedStringArray(r))
	return _entry(SECTION_WEATHER, String(w.id), w.display_name, _first_sentence(w.description),
		w.color, blocks, kw, w.fx_kind)


## One [rule, effect, who] row per gameplay rule of [param w], derived from its data.
static func weather_effect_rows(w: WeatherResource) -> Array:
	var rows: Array = []
	var keys := w.element_damage_scale.keys()
	keys.sort()
	for el in keys:
		var mult := float(w.element_damage_scale[el])
		rows.append(["Damage", "%s moves x%s damage" % [String(el).capitalize(), _num(mult)], "Everyone"])
	if w.ranged_hit_modifier != 0:
		rows.append(["Accuracy", "Ranged moves (range %d+) %s hit" % [w.ranged_min_range, _signed(w.ranged_hit_modifier)], "Everyone"])
	for rule in w.stat_rules:
		if rule == null:
			continue
		var mods: Array[String] = []
		for k in rule.rule_modifiers:
			var key := String(k)
			if key.begins_with("stat_"):
				mods.append("%s %s" % [_signed(int(rule.rule_modifiers[k])), key.trim_prefix("stat_").replace("_", " ")])
		rows.append([rule.display_name, ", ".join(mods) if not mods.is_empty() else rule.description,
			_condition_who(rule.condition)])
	for rule in w.turn_start_rules:
		if rule == null:
			continue
		rows.append([rule.display_name, "Each turn start: " + _effects_text(rule.effects),
			_condition_who(rule.condition)])
	for te_id in w.suppressed_tile_effects:
		rows.append(["Suppresses", "[url=tiles:%s]%s[/url] tiles are inert (runtime ones are removed)" % [String(te_id), _tile_effect_name(te_id)], "Tiles"])
	return rows


## "Skirmish Arena -- dynamic: starts here, pool weight 2/5".
static func weather_map_lines(id: StringName) -> Array:
	var lines: Array = []
	for m in maps():
		var s: Dictionary = m.get_weather_settings()
		var mode := String(s.get("mode", "fixed"))
		var start := StringName(String(s.get("weather", "clear")))
		var parts: Array[String] = []
		match mode:
			"fixed":
				if start == id:
					parts.append("fixed, all battle")
			"schedule":
				var total := 0
				var mine := 0
				for e in s.get("schedule", []):
					total += int(e.get("rounds", 1))
					if StringName(String(e.get("weather", ""))) == id:
						mine += int(e.get("rounds", 1))
				if mine > 0:
					parts.append("schedule, %d of every %d rounds" % [mine, total])
			"dynamic":
				if start == id:
					parts.append("starts here")
				var pool: Dictionary = s.get("pool", {})
				var total_w := 0.0
				for k in pool:
					total_w += float(pool[k])
				for k in pool:
					if StringName(String(k)) == id:
						parts.append("changes every %d rounds, chance %d%%" % [int(s.get("change_every", 3)), roundi(100.0 * float(pool[k]) / maxf(total_w, 0.001))])
				if not parts.is_empty():
					parts[0] = "dynamic, " + parts[0]
		if not parts.is_empty():
			lines.append("%s -- %s" % [m.map_name, "; ".join(parts)])
	return lines


## Roster units with abilities gated on this weather, or moves that summon it.
static func weather_unit_lines(id: StringName) -> Array:
	var lines: Array = []
	for c in roster():
		for a in c.abilities:
			if a != null and id in weathers_in_condition(a.condition):
				lines.append("[url=units:%s]%s[/url] -- %s: %s" % [c.character_id, _char_name(c), a.display_name, a.description])
		for m in c.moveset:
			if m == null:
				continue
			for e in m.effects:
				if e is SetWeatherEffect and StringName(e.weather) == id:
					lines.append("[url=units:%s]%s[/url] -- %s (move): %s" % [c.character_id, _char_name(c), m.display_name, e.describe()])
	return lines


## Weather ids a condition tree waits for (WeatherCondition anywhere inside).
static func weathers_in_condition(cond) -> Array:
	var out: Array = []
	if cond == null:
		return out
	if cond is WeatherCondition:
		for w in cond.weathers:
			out.append(StringName(w))
	var inner = cond.get("condition")
	if inner != null:
		out.append_array(weathers_in_condition(inner))
	var many = cond.get("conditions")
	if many is Array:
		for c in many:
			out.append_array(weathers_in_condition(c))
	return out


## Tooltip text for the battle HUD's weather chip -- the Compendium's wording.
static func weather_tooltip(w: WeatherResource) -> String:
	if w == null:
		return ""
	var lines: Array[String] = ["%s" % w.display_name]
	if w.description != "":
		lines.append(w.description)
	for r in weather_effect_rows(w):
		lines.append("• %s: %s (%s)" % [r[0], _strip_bb(String(r[1])), r[2]])
	lines.append("See Map Menu > Encyclopedia > Weather.")
	return "\n".join(lines)


# =============================================================================
# Tile effects
# =============================================================================

static func tile_effect_entries() -> Array:
	var out: Array = []
	for te in tile_effects():
		out.append(tile_effect_entry(te))
	out.sort_custom(func(a, b): return String(a["title"]).naturalnocasecmp_to(String(b["title"])) < 0)
	return out


static func tile_effect_entry(te: TileEffectResource) -> Dictionary:
	var blocks: Array = []
	var fields: Array = [
		["Trigger", String(TRIGGER_LONG.get(te.trigger, "?"))],
		["Affects", _factions_text(te)],
	]
	if te.consume_on_trigger:
		fields.append(["Uses", "Single use -- consumed when it triggers"])
	var trap_line := String(te.trap_descriptor()) if te.has_method("trap_descriptor") else ""
	if trap_line != "":
		fields.append(["Trap", trap_line])
	# The element is read from element_chart.tres (its tile_elements map) -- the same
	# authority the board resolves tile damage with.
	var elem := ElementChart.tile_element_of(te)
	if elem != &"":
		var chart := ElementChart.chart()
		fields.append(["Element", "%s -- matching moves hit a unit standing here x%s; %s units are at home here (take x%s damage, its boons land x%s)" % [
			element_link(elem), _num(chart.tile_bonus()), String(elem).capitalize(),
			_num(chart.home_benefit()), _num(chart.home_effect_bonus())]])
	blocks.append({ "type": "fields", "rows": fields })
	blocks.append({ "type": "heading", "text": "What it does" })
	blocks.append({ "type": "bullets", "items": tile_effect_lines(te) })
	var rules := tile_effect_rule_lines(te)
	if not rules.is_empty():
		blocks.append({ "type": "heading", "text": "Rules" })
		blocks.append({ "type": "bullets", "items": rules })
	var weather_lines: Array = []
	for w in weathers():
		if w.suppresses(te.id):
			weather_lines.append("Doused by [url=weather:%s]%s[/url] -- inert while it lasts; placed copies are removed" % [String(w.id), w.display_name])
		var scale: float = w.damage_scale_for_element(elem)
		if elem != &"" and not is_equal_approx(scale, 1.0) and not w.suppresses(te.id):
			weather_lines.append("[url=weather:%s]%s[/url]: %s moves x%s (this tile's element)" % [String(w.id), w.display_name, String(elem).capitalize(), _num(scale)])
	if not weather_lines.is_empty():
		blocks.append({ "type": "heading", "text": "Weather" })
		blocks.append({ "type": "bullets", "items": weather_lines })
	var sources := tile_effect_sources(te.id)
	blocks.append({ "type": "heading", "text": "Found on / created by" })
	blocks.append({ "type": "bullets", "items": sources if not sources.is_empty() else ["No tile or move currently creates it."] })
	var title := te.display_name if te.display_name != "" else StatusVisuals.humanize(String(te.id))
	var col: Color = TileEffectVisuals.info_for_id(te.id).get("color", MenuTheme.GOLD)
	return _entry(SECTION_TILES, String(te.id), title,
		"%s · %s" % [TRIGGER_TEXT.get(te.trigger, "?"), _first_line(tile_effect_lines(te))],
		col, blocks, "%s %s %s %s %s" % [title, te.id, elem, trap_line,
			" ".join(PackedStringArray(tile_effect_lines(te)))])


## What a tile effect does, one line per effect / rule flag.
static func tile_effect_lines(te: TileEffectResource) -> Array:
	var lines: Array = []
	for e in te.effects:
		if e != null and e.has_method("describe"):
			var d := String(e.describe()).strip_edges()
			if d != "":
				lines.append(d)
	for k in te.rule_flags:
		var v = te.rule_flags[k]
		if v is bool:
			if v:
				lines.append(_flag_text(String(k)))
		else:
			lines.append("%s %s" % [StatusVisuals.humanize(String(k).trim_prefix("stat_")), _signed(int(v)) if (v is int or v is float) else str(v)])
	if lines.is_empty():
		lines.append("No direct effect")
	return lines


## The authored rule flags of a tile effect (traps, concealment, lifetime), phrased for
## a player. Only flags that are ON are listed. Read defensively ([code]in[/code]) so an
## older TileEffectResource without a flag simply says nothing about it.
static func tile_effect_rule_lines(te: TileEffectResource) -> Array:
	var lines: Array = []
	if _flag_on(te, "springs_on_pass"):
		lines.append("Springs on a unit that merely walks across it -- not only on one that stops here.")
	if _flag_on(te, "halts_movement"):
		lines.append("Halts movement: a unit that triggers it ends its move on this cell.")
	if _flag_on(te, "conceals_occupants"):
		lines.append("Conceals the occupant: only enemies right next to it can see it (see [url=rules:fog]Fog of War[/url]).")
	if _flag_on(te, "destroyed_by_hostile_entry"):
		lines.append("Destroyed when a hostile unit steps onto it.")
	if "move_cost_bonus" in te and int(te.get("move_cost_bonus")) != 0:
		lines.append("Movement cost %s to enter." % _signed(int(te.get("move_cost_bonus"))))
	if "expiry_rounds" in te and int(te.get("expiry_rounds")) > 0:
		lines.append("When placed during battle it lasts %d round%s." % [int(te.get("expiry_rounds")),
			"" if int(te.get("expiry_rounds")) == 1 else "s"])
	return lines


static func _flag_on(obj: Object, prop: String) -> bool:
	return obj != null and prop in obj and bool(obj.get(prop))


## Tiles (TileCatalog) whose base effects include [param id], and moves that place it.
static func tile_effect_sources(id: StringName) -> Array:
	var lines: Array = []
	var svc = _services()
	var tile_names: Array[String] = []
	for path in TileCatalog.all_paths():
		var res = TileCatalog.find(path)
		if res == null:
			continue
		var effs: Array = []
		if svc != null and svc.has_method("_base_effects_for_tile"):
			effs = svc._base_effects_for_tile(res)
		for e in effs:
			if e != null and StringName(e.id) == id:
				var n := String(res.tile_name) if String(res.tile_name) != "" else String(res.id)
				if n not in tile_names:
					tile_names.append(n)
	tile_names.sort()
	if not tile_names.is_empty():
		lines.append("Tiles: " + ", ".join(tile_names))
	for m in all_moves():
		for e in m.effects:
			if e is ApplyTileEffect and e.effect != null and StringName(e.effect.id) == id:
				lines.append("Move: %s%s" % [m.display_name, _move_owner_suffix(m)])
	return lines


## Tooltip for the terrain card -- the Compendium's wording.
static func tile_effect_tooltip(te) -> String:
	if te == null or not (te is TileEffectResource):
		return ""
	var t := te as TileEffectResource
	var lines: Array[String] = ["%s (%s)" % [t.display_name if t.display_name != "" else String(t.id), TRIGGER_TEXT.get(t.trigger, "?")]]
	for l in tile_effect_lines(t):
		lines.append("• " + String(l))
	var trap_line := String(t.trap_descriptor()) if t.has_method("trap_descriptor") else ""
	if trap_line != "":
		lines.append(trap_line)
	lines.append("Affects: " + _factions_text(t))
	for w in weathers():
		if w.suppresses(t.id):
			lines.append("Doused by %s." % w.display_name)
	return "\n".join(lines)


static func _factions_text(te: TileEffectResource) -> String:
	var who := "Any unit"
	match te.affected_factions:
		TileEffectResource.AffectedFactions.OCCUPANT_ENEMIES:
			who = "Enemies of whoever placed it" if te.consume_on_trigger else "Enemy units"
		TileEffectResource.AffectedFactions.OCCUPANT_ALLIES:
			who = "Allied units"
	if te.required_unit_tag != &"":
		who += " with the '%s' tag" % String(te.required_unit_tag)
	return who


static func _tile_effect_name(id) -> String:
	for te in tile_effects():
		if StringName(te.id) == StringName(id):
			return te.display_name if te.display_name != "" else String(id)
	return StatusVisuals.humanize(String(id))


# =============================================================================
# Statuses
# =============================================================================

static func status_entries() -> Array:
	var out: Array = []
	for s in StatusCatalog.all_statuses():
		if s != null:
			out.append(status_entry(s))
	out.sort_custom(func(a, b): return String(a["title"]).naturalnocasecmp_to(String(b["title"])) < 0)
	return out


static func status_entry(s: StatusCondition) -> Dictionary:
	var info := StatusVisuals.info_for(s)
	var title := s.display_name if s.display_name != "" else StatusVisuals.humanize(String(s.id))
	var blocks: Array = []
	blocks.append({ "type": "text", "text": status_description(s) })
	var fields: Array = [
		["Kind", String(info.get("kind", "neutral")).capitalize()],
		["Duration", "Permanent (never expires on its own)" if s.duration_turns <= 0 else ("%d turn%s" % [s.duration_turns, "" if s.duration_turns == 1 else "s"])],
		["Stacking", _stacking_text(s)],
	]
	blocks.append({ "type": "fields", "rows": fields })
	# What it does, split the way a player asks: every turn, and while it lasts.
	var ticks: Array = []
	for e in s.tick_effects:
		if e != null and e.has_method("describe"):
			var d := String(e.describe()).strip_edges()
			if d != "":
				ticks.append(d)
	if not ticks.is_empty():
		blocks.append({ "type": "heading", "text": "Each turn" })
		blocks.append({ "type": "bullets", "items": ticks })
	var active: Array = []
	var flags = s.get("rule_flags") if "rule_flags" in s else null
	if flags is Dictionary:
		for k in flags:
			if bool(flags[k]):
				active.append(_status_flag_text(String(k)))
	active.sort()
	if not active.is_empty():
		blocks.append({ "type": "heading", "text": "While active" })
		blocks.append({ "type": "bullets", "items": active })
	var sources: Array = []
	for m in all_moves():
		for e in m.effects:
			if e is ApplyStatusEffect and e.condition != null and StringName(e.condition.id) == s.id:
				sources.append("%s%s" % [m.display_name, _move_owner_suffix(m)])
	for c in roster():
		for a in c.abilities:
			if a == null:
				continue
			for e in a.effects:
				if e is ApplyStatusEffect and e.condition != null and StringName(e.condition.id) == s.id:
					sources.append("%s (ability of [url=units:%s]%s[/url])" % [a.display_name, c.character_id, _char_name(c)])
	if not sources.is_empty():
		blocks.append({ "type": "heading", "text": "Inflicted by" })
		blocks.append({ "type": "bullets", "items": sources })
	return _entry(SECTION_STATUSES, String(s.id), title, status_description(s),
		info.get("color", MenuTheme.GOLD), blocks, "%s %s %s" % [title, s.id, status_description(s)])


## Player-readable stacking rule. An explicit match (not an index into the enum keys)
## so reordering StatusCondition.Stacking can never relabel every status.
static func _stacking_text(s: StatusCondition) -> String:
	match s.stacking:
		StatusCondition.Stacking.REFRESH:
			return "Refreshes -- reapplying resets the timer"
		StatusCondition.Stacking.STACK:
			var cap := " (max %d)" % s.max_stacks if s.max_stacks > 0 else ""
			return "Stacks -- reapplying adds another instance" + cap
		StatusCondition.Stacking.IGNORE:
			return "Ignored -- reapplying does nothing while it is active"
	return "Unknown"


## A status rule flag as a sentence ("Cannot move"); unknown flags are humanised so a
## flag added by content authoring still reads as words.
static func _status_flag_text(flag: String) -> String:
	var word := String(StatusVisuals._RULE_FLAG_WORDS.get(flag, ""))
	if word != "":
		return word
	match flag:
		"immobilized": return "Cannot move"
		"untargetable": return "Cannot be targeted by moves"
		"fortified": return "Takes reduced damage"
	return StatusVisuals.humanize(flag)


## "Deal 4 true damage each turn, Cannot move" -- one sentence, shared with the
## status-chip tooltips.
static func status_description(s) -> String:
	if s == null or typeof(s) != TYPE_OBJECT:
		return ""
	var parts: Array[String] = []
	var flags = s.get("rule_flags") if "rule_flags" in s else null
	if flags is Dictionary:
		for k in flags:
			if bool(flags[k]):
				var word := String(StatusVisuals._RULE_FLAG_WORDS.get(String(k), ""))
				parts.append(word if word != "" else StatusVisuals.humanize(String(k)))
	# Scripted statuses carry their effect as data on the resource rather than as a tick
	# effect: a stat modifier (StatModifierStatus: "Movement -2") and a damage-taken scale.
	if "stat_name" in s and "amount" in s and int(s.get("amount")) != 0:
		parts.append("%s %s" % [StatusVisuals.humanize(String(s.get("stat_name"))), _signed(int(s.get("amount")))])
	if "damage_taken_scale" in s and not is_equal_approx(float(s.get("damage_taken_scale")), 1.0):
		parts.append("Takes x%s damage" % _num(float(s.get("damage_taken_scale"))))
	var ticks = s.get("tick_effects") if "tick_effects" in s else null
	if ticks is Array:
		var fx := _effects_text(ticks)
		if fx != "":
			parts.append("Each turn: " + fx)
	if parts.is_empty():
		return "No direct effect (a marker other rules read)."
	return ". ".join(parts) + "."


## Tooltip for a status chip / pip -- the Compendium's wording.
static func status_tooltip(s, turns_left: int = -99) -> String:
	if s == null:
		return ""
	var title := String(s.get("display_name")) if String(s.get("display_name")) != "" else StatusVisuals.humanize(String(s.get("id")))
	var line := "%s: %s" % [title, status_description(s)]
	if turns_left != -99:
		line += "\n" + StatusVisuals.turns_label(turns_left)
	return line


# =============================================================================
# Units
# =============================================================================

static func unit_entries() -> Array:
	var out: Array = []
	for c in roster():
		out.append(unit_entry(c))
	return out


static func unit_entry(c: CharacterResource) -> Dictionary:
	var blocks: Array = []
	var profile = c.get_movement_profile()
	var fields: Array = [
		["Element", element_link(c.element) if c.element != &"" else "None"],
		["Movement", movement_text(c)],
		["Tags", ", ".join(PackedStringArray(c.tags.map(func(t): return String(t)))) if not c.tags.is_empty() else "None"],
		["Stats", "HP %d · ATK %d · DEF %d · MAG %d · MDEF %d · SPD %d · MOV %d" % [
			c.base_health, c.base_attack, c.base_defense, c.base_magic, c.base_magic_defense,
			c.base_speed, c.base_movement]],
	]
	blocks.append({ "type": "fields", "rows": fields })
	var move_items: Array = []
	for m in c.moveset:
		if m != null:
			move_items.append(move_line(m))
	blocks.append({ "type": "heading", "text": "Moves" })
	blocks.append({ "type": "bullets", "items": move_items if not move_items.is_empty() else ["No moves"] })
	var ab_items: Array = []
	for a in c.abilities:
		if a != null:
			ab_items.append(ability_line(a))
	blocks.append({ "type": "heading", "text": "Abilities" })
	blocks.append({ "type": "bullets", "items": ab_items if not ab_items.is_empty() else ["No abilities"] })
	var kw := "%s %s %s %s" % [_char_name(c), c.character_id, c.element, " ".join(PackedStringArray(c.tags.map(func(t): return String(t))))]
	for m in c.moveset:
		if m != null:
			kw += " " + m.display_name
	for a in c.abilities:
		if a != null:
			kw += " " + a.display_name
	return _entry(SECTION_UNITS, String(c.character_id), _char_name(c), c.description,
		MenuKit.element_color(String(c.element)), blocks, kw)


## "Ground, orthogonal, 5 tiles" -- movement kind, pattern and range.
static func movement_text(c: CharacterResource) -> String:
	var p = c.get_movement_profile()
	if p == null:
		return "Ground"
	var kind := StatusVisuals.humanize(String(CombatTypes.MovementKind.keys()[clampi(p.kind, 0, CombatTypes.MovementKind.size() - 1)]).to_lower())
	var shape := String(["orthogonal steps", "diagonal steps", "8-way steps", "knight jumps", "teleport"][clampi(p.shape, 0, 4)])
	var txt := "%s · %s · %d tile%s" % [kind, shape, p.range, "" if p.range == 1 else "s"]
	if not p.terrain_cost_overrides.is_empty():
		var parts: Array[String] = []
		for k in p.terrain_cost_overrides:
			parts.append("%s %s" % [StatusVisuals.humanize(String(k)), str(p.terrain_cost_overrides[k])])
		txt += " (terrain cost: %s)" % ", ".join(parts)
	return txt


## "[b]Thorn Spit[/b] (nature, physical) -- Range 1-3 · Power 12 · CD 2: <describe()>".
static func move_line(m: MoveResource) -> String:
	var meta: Array[String] = []
	if m.targeting != null:
		meta.append(m.targeting.describe_range())
	var power := _move_power(m)
	if power > 0:
		meta.append("Power %d" % power)
	meta.append("Acc %d%%" % roundi(m.accuracy * 100.0))
	if m.crit_chance > 0.0:
		meta.append("Crit %d%%" % roundi(m.crit_chance * 100.0))
	meta.append("CD %d" % m.cooldown if m.cooldown > 0 else "No cooldown")
	if m.max_uses > 0:
		meta.append("%d use%s" % [m.max_uses, "" if m.max_uses == 1 else "s"])
	var tag := String(m.element).capitalize() if m.element != &"" else "Neutral"
	tag += ", " + String(CombatTypes.DamageCategory.keys()[clampi(m.category, 0, CombatTypes.DamageCategory.size() - 1)]).capitalize()
	var desc := m.full_description().replace("\n", " -- ")
	for e in m.effects:
		if e is SetWeatherEffect:
			desc += "  " + _weather_link(StringName(e.weather))
	return "[b]%s[/b] [color=#9ba5c8](%s)[/color] -- %s\n%s" % [m.display_name, tag, " · ".join(meta), desc]


static func ability_line(a: AbilityResource) -> String:
	var trig := StatusVisuals.humanize(String(AbilityTrigger.Trigger.keys()[clampi(a.trigger, 0, AbilityTrigger.Trigger.size() - 1)]).to_lower())
	var cond := ""
	if a.condition != null and a.condition.describe() != "always":
		cond = " -- when %s" % a.condition.describe()
	var fx := _effects_text(a.effects)
	var desc := a.description if a.description != "" else fx
	var line := "[b]%s[/b] [color=#9ba5c8](%s%s)[/color]\n%s" % [a.display_name, trig, cond, desc]
	if fx != "" and a.description != "":
		line += " [color=#9ba5c8](%s)[/color]" % fx
	for wid in weathers_in_condition(a.condition):
		line += "  " + _weather_link(wid)
	return line


## "[url=elements:fire]Fire[/url]" -- a cross-link to an element on the type chart page.
static func element_link(element) -> String:
	var key := ElementChartResource.key_of(element)
	if key == &"":
		return ""
	return "[url=%s:%s]%s[/url]" % [SECTION_ELEMENTS, String(key), String(key).capitalize()]


## "[url=weather:rain]See Rain[/url]" -- a cross-link to a weather entry.
static func _weather_link(id: StringName) -> String:
	return "[url=weather:%s]» %s[/url]" % [String(id), Weather.get_weather(id).display_name]


static func _move_power(m: MoveResource) -> int:
	for e in m.effects:
		if e is DamageEffect:
			return int(e.power)
	return 0


static func _move_owner_suffix(m: MoveResource) -> String:
	var owners: Array[String] = []
	for c in roster():
		if m in c.moveset:
			owners.append(_char_name(c))
	return " (%s)" % ", ".join(owners) if not owners.is_empty() else ""


static func _char_name(c) -> String:
	if c == null:
		return ""
	return c.display_name if String(c.display_name) != "" else String(c.character_id).capitalize()


# =============================================================================
# Elements (one entry per charted element; the Compendium shows them on the
# Elements page -- the type chart -- and the global search finds them)
# =============================================================================

static func element_entries() -> Array:
	var out: Array = []
	for el in ElementChartGallery.elements():
		out.append(element_entry(el))
	return out


static func element_entry(element: StringName) -> Dictionary:
	var el_name := String(element).capitalize()
	var blocks: Array = []
	var fields: Array = []
	var strong := ElementChartGallery.strong_against(element)
	var weak := ElementChartGallery.weak_to(element)
	if not strong.is_empty():
		fields.append(["Strong against", _element_links(strong)])
	if not weak.is_empty():
		fields.append(["Weak to", _element_links(weak)])
	var self_text := ElementChartGallery.self_resist_text(element)
	if self_text != "":
		fields.append(["Itself", self_text])
	if strong.is_empty() and weak.is_empty():
		fields.append(["Matchups", ElementChartGallery.NO_MATCHUPS_TEXT])
	blocks.append({ "type": "fields", "rows": fields })
	var units := units_of_element(element)
	if not units.is_empty():
		var links: Array[String] = []
		for c in units:
			links.append("[url=%s:%s]%s[/url]" % [SECTION_UNITS, String(c.character_id), _char_name(c)])
		blocks.append({ "type": "heading", "text": "Units" })
		blocks.append({ "type": "text", "text": ", ".join(links) })
	var tiles: Array[String] = []
	for te in tile_effects():
		if ElementChart.tile_element_of(te) == element:
			var te_name: String = te.display_name if te.display_name != "" else StatusVisuals.humanize(String(te.id))
			tiles.append("[url=%s:%s]%s[/url]" % [SECTION_TILES, String(te.id), te_name])
	if not tiles.is_empty():
		blocks.append({ "type": "heading", "text": "Tile effects" })
		blocks.append({ "type": "text", "text": ", ".join(tiles) })
	var skies: Array = []
	for w in weathers():
		var scale: float = w.damage_scale_for_element(element)
		if not is_equal_approx(scale, 1.0):
			skies.append("[url=%s:%s]%s[/url]: %s moves x%s" % [SECTION_WEATHER, String(w.id), w.display_name, el_name, _num(scale)])
	if not skies.is_empty():
		blocks.append({ "type": "heading", "text": "Weather" })
		blocks.append({ "type": "bullets", "items": skies })
	var kw := "%s element type %s" % [el_name, element_matchup_text(element)]
	for c in units:
		kw += " " + _char_name(c)
	return _entry(SECTION_ELEMENTS, String(element), el_name, element_matchup_text(element),
		ElementVisuals.color_for(element), blocks, kw)


## Roster units whose type is [param element], sorted by name.
static func units_of_element(element) -> Array:
	var key := ElementChartResource.key_of(element)
	var out: Array = []
	if key == &"":
		return out
	for c in roster():
		if ElementChartResource.key_of(c.element) == key:
			out.append(c)
	return out


static func _element_links(list: Array) -> String:
	var parts: Array[String] = []
	for e in list:
		parts.append(element_link(e))
	return ", ".join(parts)


# =============================================================================
# Rules / mechanics
# =============================================================================

static func rules_entries() -> Array:
	var out: Array = []
	out.append(_rules_elements())
	out.append(_rules_hit())
	out.append(_rules_height())
	out.append(_rules_floors())
	out.append(_rules_tiles())
	out.append(_rules_fog())
	out.append(_rules_weather())
	out.append(_rules_turns())
	out.append(_rules_facing())
	out.append(_rules_controls())
	return out


## How elements work. The full attacker x defender grid lives on the Elements page
## (ElementChartGallery); this entry explains the rules around it and summarises every
## element's matchups, all read from the same chart resource.
static func _rules_elements() -> Dictionary:
	var chart := ElementChart.chart()
	var summary: Array = []
	for el in ElementChartGallery.elements():
		summary.append("%s -- %s" % [element_link(el), element_matchup_text(el)])
	var blocks: Array = [
		{ "type": "text", "text": "Every move, unit and some tiles carry an element. The move's element against the target's element sets a damage multiplier; moves or units without an element are always neutral. [url=%s:]Open the full type chart[/url]." % SECTION_ELEMENTS },
		{ "type": "bullets", "items": summary if not summary.is_empty() else ["No elements are authored in the element chart yet."] },
		{ "type": "heading", "text": "Tiles and elements" },
		{ "type": "bullets", "items": [
			"Tile match: a target standing on a tile of the move's element takes x%s (a fire move into a burning tile)." % _num(chart.tile_bonus()),
			"Home ground: a unit on a tile of its OWN element takes x%s damage, and what that tile gives it (evasion, healing) lands x%s." % [_num(chart.home_benefit()), _num(chart.home_effect_bonus())],
			"Damage a tile or hazard deals itself uses the matchup alone (a nature unit resists nature brambles).",
			"Weather then scales the move's element (see [url=rules:weather]Weather[/url]).",
		] },
	]
	var kw := "element chart type matchup effective strong resisted weak"
	for el in ElementChartGallery.elements():
		kw += " " + String(el)
	return _entry(SECTION_RULES, "elements", "Elements & Matchups", "How element matchups scale damage.",
		MenuTheme.GOLD, blocks, kw)


## "Strong vs Nature; weak to Water; resists itself x0.75" -- one line per element, read
## from the chart in both directions (the chart has no implied symmetry).
static func element_matchup_text(element) -> String:
	var parts: Array[String] = []
	var strong := ElementChartGallery.strong_against(element)
	if not strong.is_empty():
		parts.append("strong vs " + _element_names(strong))
	var weak := ElementChartGallery.weak_to(element)
	if not weak.is_empty():
		parts.append("weak to " + _element_names(weak))
	var self_text := ElementChartGallery.self_resist_text(element)
	if self_text != "":
		parts.append(self_text.to_lower())
	if strong.is_empty() and weak.is_empty():
		parts.push_front(ElementChartGallery.NO_MATCHUPS_TEXT.to_lower())
	return _sentence("; ".join(parts))


static func _element_names(list: Array) -> String:
	var names: Array[String] = []
	for e in list:
		names.append(String(e).capitalize())
	return ", ".join(names)


static func _sentence(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else t


static func _rules_tiles() -> Dictionary:
	var traps: Array[String] = []
	var veils: Array[String] = []
	for te in tile_effects():
		var nm: String = te.display_name if te.display_name != "" else StatusVisuals.humanize(String(te.id))
		if _flag_on(te, "springs_on_pass"):
			traps.append("[url=tiles:%s]%s[/url]" % [String(te.id), nm])
		if _flag_on(te, "conceals_occupants"):
			veils.append("[url=tiles:%s]%s[/url]" % [String(te.id), nm])
	var items: Array = [
		"A glowing tile hurts where you STAND: its effect fires on the cell a unit stops on (or starts its turn on). Walking across is free.",
		"A TRAP springs where you STEP: it fires on a unit merely crossing the cell, and may halt that unit's move on the trap.%s" % (" Traps: " + ", ".join(traps) + "." if not traps.is_empty() else ""),
		"Damage from tiles and hazards is guaranteed -- it never rolls to hit and cannot be dodged.",
		"Some effects are single use, some are placed by moves and expire after a few rounds; each [url=tiles:fire]tile effect[/url] entry lists its rules.",
	]
	if not veils.is_empty():
		items.append("Concealing effects hide their occupant (see [url=rules:fog]Fog of War[/url]): " + ", ".join(veils) + ".")
	var blocks: Array = [ { "type": "bullets", "items": items } ]
	return _entry(SECTION_RULES, "tiles", "Tiles & Traps", "Glowing tiles hurt where you stand; traps spring where you step.",
		TileEffectVisuals.BASE_TINT, blocks, "tile trap hazard spring step stand guaranteed damage vine expire")


static func _rules_fog() -> Dictionary:
	var fogged: Array[String] = []
	for m in maps():
		if "fog_of_war" in m and bool(m.get("fog_of_war")):
			fogged.append(String(m.map_name))
	var items: Array = [
		"On fogged maps each side only sees what its units can see: %d cells in every direction unless a unit's own sight says otherwise." % VisionSystem.DEFAULT_SIGHT_RANGE,
		"Hidden enemies cannot be targeted and do not appear in forecasts; area and ground-targeted moves can still be aimed anywhere in range.",
		"Attacking gives a hidden unit away: it stays revealed for %d turn changes. Moving, healing and placing effects never reveal." % VisionSystem.REVEAL_TURNS,
		"A concealed unit (for example inside a smoke veil) can only be seen from %d cell%s away." % [VisionSystem.CONCEAL_ADJACENCY, "" if VisionSystem.CONCEAL_ADJACENCY == 1 else "s"],
	]
	items.append("Fogged maps: " + (", ".join(fogged) if not fogged.is_empty() else "none yet") + ".")
	var blocks: Array = [ { "type": "bullets", "items": items } ]
	return _entry(SECTION_RULES, "fog", "Fog of War", "Per-side vision, reveal on attack, concealment.",
		MenuTheme.TEXT_MUTED, blocks, "fog of war vision sight hidden reveal conceal smoke veil")


static func _rules_hit() -> Dictionary:
	var blocks: Array = [
		{ "type": "bullets", "items": [
			"Hit chance = move accuracy - target evasion - terrain avoid (e.g. Tall Grass) + height and weather modifiers, clamped 0-100%.",
			"Crit chance = move crit + the attacker's crit stat. A crit deals x%s damage." % _num(CombatTypes.CRIT_MULTIPLIER),
			"Damage = power + scaling stat - defense (magic defense for magical moves; true damage ignores defense), then: bonuses vs restricted / element-hunted targets, the defender's own reductions, element chart, weather, height, crit.",
			"The combat forecast shows exactly what a hit will do -- it uses the same rules.",
			"Shields soak damage before HP. Invulnerable (Guarded) units take none.",
		] },
	]
	return _entry(SECTION_RULES, "hit", "Hit, Crit & Evasion", "How accuracy, evasion, crits and damage resolve.",
		MenuTheme.ACCENT, blocks, "hit crit evasion avoid accuracy damage defense terrain shield")


static func _rules_height() -> Dictionary:
	var rows: Array = [
		["Attacker higher", "+%d max range (ranged moves)" % Elevation.HIGH_GROUND_RANGE_BONUS,
			"x%s" % _num(Elevation.HIGH_GROUND_DAMAGE_SCALE), "+%d%%" % int(Elevation.HIGH_GROUND_HIT_BONUS)],
		["Same floor", "--", "x1", "--"],
		["Attacker lower", "--", "x%s" % _num(Elevation.LOW_GROUND_DAMAGE_SCALE), "-%d%%" % int(Elevation.LOW_GROUND_HIT_PENALTY)],
	]
	var blocks: Array = [
		{ "type": "text", "text": "Fighting across floors: any height difference counts the same (one floor up is as good as three)." },
		{ "type": "table", "columns": ["Position", "Range", "Damage", "Hit"], "rows": rows },
	]
	return _entry(SECTION_RULES, "height", "Height Advantage", "High ground: more reach, damage and accuracy.",
		MenuTheme.WARNING, blocks, "height advantage high ground elevation floor range")


static func _rules_floors() -> Dictionary:
	var blocks: Array = [
		{ "type": "bullets", "items": [
			"Range counts floors: distance = steps across + floors up or down.",
			"Melee (range 1) only reaches its own floor, or the far end of a stair / ladder. A unit directly above or below cannot be hit in melee.",
			"Line of sight is checked across floors: a solid ceiling between two units blocks the shot, and a unit under a roof or deck is in cover from above.",
			"Area moves stay on the floor they are aimed at.",
			"Stairs, ladders and ramps link floors; moving along one may cost extra.",
			"Floors above the one you are looking at fade away (cutaway) so units underneath stay visible.",
		] },
	]
	return _entry(SECTION_RULES, "floors", "Multi-floor Battles", "Bridges, castles and decks: reach, sight and cover.",
		MenuTheme.TEAM_BLUE, blocks, "multi floor bridge melee reach line of sight cover stairs ladder cutaway")


static func _rules_weather() -> Dictionary:
	var items: Array = []
	for w in weathers():
		items.append("[url=weather:%s]%s[/url] -- %s" % [String(w.id), w.display_name, w.description if w.description != "" else "no effects"])
	var blocks: Array = [
		{ "type": "text", "text": "Every battle has weather. Maps fix it, cycle it on a schedule, or roll it every few rounds; some moves summon it. The banner shows the current weather and when it changes." },
		{ "type": "bullets", "items": items },
		{ "type": "text", "text": "Weather applies to the forecast too, so the numbers you see are the numbers you get." },
	]
	return _entry(SECTION_RULES, "weather", "Weather", "How battlefield weather works.",
		Color("6cc4ff"), blocks, "weather rain sun storm bloom schedule")


static func _rules_turns() -> Dictionary:
	var blocks: Array = [
		{ "type": "fields", "rows": [
			["Traditional", "Each side moves ALL of its units, then the other side goes (Fire Emblem style)."],
			["Speed First", "Units act one at a time in initiative order, fastest first, regardless of side."],
		] },
		{ "type": "text", "text": "Turn-start effects (status ticks, tile effects, weather rules, abilities) happen on each unit's own turn start in both systems." },
	]
	return _entry(SECTION_RULES, "turns", "Turn Systems", "Traditional phases or Speed First initiative.",
		MenuTheme.SUCCESS, blocks, "turn system traditional speed first initiative phase")


static func _rules_facing() -> Dictionary:
	var blocks: Array = [
		{ "type": "text", "text": "Units turn to face their target when they act and settle facing the nearest enemy. Facing is purely visual: there are no back-attack or flank bonuses." },
	]
	return _entry(SECTION_RULES, "facing", "Unit Facing", "Visual only -- no flanking.",
		MenuTheme.TEXT_DIM, blocks, "facing flank back attack direction")


static func _rules_controls() -> Dictionary:
	var rows: Array = []
	for d in InputActions.REBINDABLE:
		var a := StringName(d["action"])
		rows.append([String(d["label"]), InputActions.describe_keys(a), InputActions.describe(a, true)])
	rows.append(["Map Menu", InputActions.describe_keys(InputActions.MAP_MENU), InputActions.describe(InputActions.MAP_MENU, true)])
	rows.append(["Fast-forward (hold)", InputActions.describe_keys(InputActions.FAST_FORWARD), InputActions.describe(InputActions.FAST_FORWARD, true)])
	var blocks: Array = [
		{ "type": "text", "text": "Current bindings (rebind them in Settings > Controls)." },
		{ "type": "table", "columns": ["Action", "Keyboard", "Gamepad"], "rows": rows },
		{ "type": "bullets", "items": [
			"Danger Zone shows every tile an enemy could attack next turn.",
			"Next / Previous Unit cycles through units that can still act.",
			"Floor Up / Down changes the viewed floor on multi-floor maps.",
			"Hold Fast-forward to speed up animations and the enemy phase.",
			"The Map Menu (with nothing selected) has Units, Objective, Encyclopedia, Settings and End Turn.",
		] },
	]
	return _entry(SECTION_RULES, "controls", "Controls", "Keyboard and gamepad bindings.",
		MenuTheme.GOLD_LITE, blocks, "controls keys bindings gamepad keyboard danger zone cycle floor fast forward map menu")


# =============================================================================
# Helpers
# =============================================================================

static func _entry(section: String, id: String, title: String, subtitle: String, color: Color,
		blocks: Array, keywords: String, icon: StringName = &"") -> Dictionary:
	return {
		"section": section, "id": id, "title": title, "subtitle": subtitle,
		"color": color, "icon": icon, "blocks": blocks,
		"keywords": _strip_bb(keywords).to_lower(),
	}


static func _effects_text(effects: Array) -> String:
	var parts: Array[String] = []
	for e in effects:
		if e != null and e.has_method("describe"):
			var d := String(e.describe()).strip_edges()
			if d != "":
				parts.append(d)
	return "; ".join(parts)


## Which roster units a rule's condition covers ("Nature units: Vineweave, ...").
static func _condition_who(cond) -> String:
	if cond == null:
		return "Everyone"
	var names: Array[String] = []
	for c in roster():
		var probe := _Probe.new(c)
		if cond.is_met(probe, null):
			names.append(_char_name(c))
	var d: String = String(cond.describe()).replace(" / ", " or ")
	if d.begins_with("not is "):
		d = "Units not " + d.trim_prefix("not is ")
	elif d.begins_with("is "):
		d = d.trim_prefix("is ").capitalize() + " units"
	else:
		d = "Units " + d
	if names.is_empty():
		return d
	return "%s (%s)" % [d, ", ".join(names)]


static func _flag_text(flag: String) -> String:
	match flag:
		"concealed": return "Conceals the occupant (harder to spot / target)"
		"fortified": return "Fortifies the occupant (takes reduced damage)"
		"untargetable": return "The occupant cannot be targeted"
		"immobilized": return "The occupant cannot move"
	return StatusVisuals.humanize(flag)


static func _num(f: float) -> String:
	var s := "%.2f" % f
	s = s.rstrip("0").rstrip(".")
	return s


static func _signed(v: int) -> String:
	return ("+%d" % v) if v >= 0 else str(v)


static func _first_sentence(t: String) -> String:
	var i := t.find(". ")
	return t.substr(0, i + 1) if i >= 0 else t


static func _first_line(lines: Array) -> String:
	return String(lines[0]) if not lines.is_empty() else ""


static func _strip_bb(t: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(t, "", true)


static func _services():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("CombatServices")
	return null


## Minimal stand-in unit so a rule's condition can be asked "would it apply to
## this roster unit?" (element / tag conditions) without a battle.
class _Probe:
	extends RefCounted
	var character_resource
	var element: StringName
	var tags: Array
	func _init(c) -> void:
		character_resource = c
		element = c.element
		tags = c.tags
	func get_element() -> StringName:
		return element
	func has_tag(t) -> bool:
		return StringName(t) in tags
