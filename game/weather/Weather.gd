extends RefCounted
class_name Weather

## Static entry points for the weather system: the catalog of authored weathers
## (game/weather/resources/<id>.tres) and the combat hooks every damage / hit /
## turn-start path reads. See docs/WEATHER.md.
##
## All hooks read the LIVE battle weather ([member CombatServices.weather]) and are
## NEUTRAL (1.0 / 0 / no-op) when there is no autoload, no state, or Clear -- so
## headless unit tests and content authored before weather behave exactly as before.
##
## PREVIEW == HIT: [DamageEffect.apply] and [MoveExecutor.preview_vs] resolve the
## damage multiplier through [method damage_scale_for] at the same step, and
## [MoveContext.hit_chance] / preview_vs both add [method hit_modifier_for], so the
## forecast (and every AI that scores off it) can never disagree with the roll.

const RESOURCE_DIR := "res://game/weather/resources/"
const CLEAR: StringName = &"clear"

static var _cache: Dictionary = {}
static var _clear_fallback: WeatherResource = null


# --- Catalog -----------------------------------------------------------------

## The authored weather with [param id] (cached), or Clear when unknown/empty.
static func get_weather(id) -> WeatherResource:
	var key := StringName(String(id)) if id != null else CLEAR
	if key == &"":
		key = CLEAR
	if _cache.has(key):
		return _cache[key]
	var path := RESOURCE_DIR + String(key) + ".tres"
	var res: WeatherResource = null
	if ResourceLoader.exists(path):
		res = load(path) as WeatherResource
	if res == null:
		if key != CLEAR:
			print_verbose("[Weather] unknown weather '%s', using Clear" % key)
			return get_weather(CLEAR)
		res = _clear()
	_cache[key] = res
	return res


## True when [param id] names an authored weather.
static func has_weather(id) -> bool:
	return ResourceLoader.exists(RESOURCE_DIR + String(id) + ".tres")


## Every authored weather id, Clear first then alphabetical. Scans the folder so a
## new .tres shows up in the Map Maker without code.
static func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open(RESOURCE_DIR)
	if dir != null:
		for f in dir.get_files():
			var name := f.trim_suffix(".remap")
			if name.ends_with(".tres"):
				var id := StringName(name.trim_suffix(".tres"))
				if id not in out:
					out.append(id)
	out.sort_custom(func(a, b): return String(a) < String(b))
	out.erase(CLEAR)
	out.push_front(CLEAR)
	return out


static func _clear() -> WeatherResource:
	if _clear_fallback == null:
		_clear_fallback = WeatherResource.new()
		_clear_fallback.id = CLEAR
		_clear_fallback.display_name = "Clear"
		_clear_fallback.icon = "◌"
	return _clear_fallback


# --- Live state ----------------------------------------------------------------

## The battle's [WeatherState] (null without the CombatServices autoload).
static func state() -> WeatherState:
	var svc = _services()
	if svc != null and "weather" in svc:
		return svc.weather
	return null


## The active weather (Clear when none).
static func current() -> WeatherResource:
	var s := state()
	if s != null and s.current != null:
		return s.current
	return get_weather(CLEAR)


static func current_id() -> StringName:
	return current().id


# --- Combat hooks ----------------------------------------------------------------

## Weather damage multiplier for [param move] (by its element). 1.0 = no effect.
static func damage_scale_for(move) -> float:
	var w := current()
	if w == null or w.element_damage_scale.is_empty():
		return 1.0
	return w.damage_scale_for_element(ElementChart.move_element(move))


## Hit-chance points the weather adds to [param move] from [param caster] against
## [param target]: the ranged penalty plus the target's weather EVASION bonus
## (subtracted). 0 on Clear.
static func hit_modifier_for(move, _caster, target, board = null) -> float:
	var w := current()
	if w == null:
		return 0.0
	var mod := 0.0
	if w.ranged_hit_modifier != 0 and is_ranged(move, w):
		mod += float(w.ranged_hit_modifier)
	mod -= float(stat_bonus_for(target, "evasion", board))
	return mod


## True when [param move] counts as ranged under [param w] (targeting reaches
## [member WeatherResource.ranged_min_range] or more).
static func is_ranged(move, w: WeatherResource = null) -> bool:
	if move == null:
		return false
	if w == null:
		w = current()
	var pattern = move.get("targeting")
	if pattern == null:
		return false
	return int(pattern.get("max_range")) >= w.ranged_min_range


## Sum of the active weather's [member WeatherResource.stat_rules] bonuses to
## [param stat_name] ("defense", "evasion", ...) that apply to [param unit].
static func stat_bonus_for(unit, stat_name: String, board = null) -> int:
	if unit == null:
		return 0
	var w := current()
	if w == null or w.stat_rules.is_empty():
		return 0
	var key := "stat_" + stat_name
	var total := 0
	for rule in w.stat_rules:
		if rule == null or not rule.rule_modifiers.has(key):
			continue
		if rule.is_condition_met(unit, _board_or_live(board)):
			total += int(rule.rule_modifiers[key])
	return total


## True when the tile effect [param te] is inert under the active weather (Rain
## douses fire). Duck-typed on its id.
static func suppresses_tile_effect(te) -> bool:
	if te == null:
		return false
	var id = te.get("id")
	if id == null:
		return false
	return current().suppresses(StringName(id))


## Run the active weather's turn-start rules on [param unit] (chip damage,
## healing). Returns the merged event log. Called once per unit per turn by
## [method TurnSystemBase._tick_unit_turn_start].
static func run_turn_start(unit, board) -> Array:
	var events: Array = []
	var w := current()
	if w == null or unit == null or board == null or w.turn_start_rules.is_empty():
		return events
	for rule in w.turn_start_rules:
		if rule == null:
			continue
		if unit.has_method("is_alive") and not unit.is_alive():
			break
		if not rule.is_condition_met(unit, board):
			continue
		var src := CombatText.make_source(CombatText.SRC_WEATHER, rule.display_name, rule.id, w.color)
		src["weather"] = w.display_name
		src["weather_fx"] = w.fx_kind
		for e in rule.run_effects(unit, board, null, src):
			e["weather"] = w.id
			events.append(e)
	return events


# --- Helpers -------------------------------------------------------------------

static func _board_or_live(board):
	if board != null:
		return board
	var svc = _services()
	if svc != null and svc.has_method("board"):
		return svc.board()
	return null


static func _services():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("CombatServices")
	return null
