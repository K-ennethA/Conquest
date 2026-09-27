extends RefCounted
class_name WeatherState

## The live weather of ONE battle: which [WeatherResource] is active this round,
## how the map schedules it, and any temporary override a move summoned.
##
## Owned by [CombatServices] ([member CombatServices.weather]) and advanced by the
## turn systems' shared per-unit turn-start tick ([method TurnSystemBase._tick_unit_turn_start])
## with the CURRENT ROUND NUMBER -- which every peer derives identically from the
## applied actions, so the weather never needs to be sent over the network.
##
## DETERMINISM: the base weather of round r is a PURE function of
## (map weather settings, [member seed], r) -- see [method base_id_for_round].
## Dynamic weather rolls a generator seeded from hash([seed, period]); it never
## touches the combat RNG stream. A network match seeds this from the match's
## public setup seed (identical on every peer); single-player uses a random seed.

## Emitted whenever the active weather changes (map schedule, dynamic roll, or a
## [SetWeatherEffect] override starting / expiring). Not emitted for re-affirming
## the same weather.
signal changed(weather: WeatherResource, previous: WeatherResource)

const MODE_FIXED := "fixed"
const MODE_SCHEDULE := "schedule"
const MODE_DYNAMIC := "dynamic"

## How far ahead [method rounds_until_change] looks before answering "never".
const FORECAST_HORIZON := 60

## Normalised map settings (see [method normalize_settings]).
var settings: Dictionary = {}
var seed: int = 0
## Current round (1-based). Only ever moves forward within a battle.
var round: int = 1
var current: WeatherResource = null

## Temporary override from a move ([SetWeatherEffect]); active while round < _override_until.
var _override_id: StringName = &""
var _override_until: int = 0


func _init() -> void:
	configure({}, 0, false)


## Start a battle's weather from [param map_settings] (a [method MapResource.get_weather_settings]
## dictionary; {} = always Clear) with [param p_seed]. Emits [signal changed] when
## [param notify] and the weather differs from the previous battle's.
func configure(map_settings: Dictionary, p_seed: int, notify: bool = true) -> void:
	settings = normalize_settings(map_settings)
	seed = p_seed
	round = 1
	_override_id = &""
	_override_until = 0
	var previous := current
	current = Weather.get_weather(id_for_round(1))
	if notify and previous != current:
		changed.emit(current, previous)


## Back to permanent Clear (map teardown / tests).
func reset() -> void:
	configure({}, 0)


## The active weather's id (&"clear" when none).
func current_id() -> StringName:
	return current.id if current != null else Weather.CLEAR


## Move to round [param r] (no-op unless it is later than the current round).
## Expires a finished override and applies the map's weather for that round.
## Returns true when the weather changed.
func advance_to_round(r: int) -> bool:
	if r <= round:
		return false
	round = r
	if _override_id != &"" and round >= _override_until:
		_override_id = &""
		_override_until = 0
	return _refresh()


## Force [param weather_id] for [param rounds] round starts (a summoned weather,
## [SetWeatherEffect]). It stays through the rest of this round and ends at the
## start of round (current + rounds), when the map's own weather resumes.
func set_override(weather_id: StringName, rounds: int) -> bool:
	_override_id = StringName(weather_id)
	_override_until = round + maxi(1, rounds)
	return _refresh()


## Weather id in force during round [param r], override included.
func id_for_round(r: int) -> StringName:
	if _override_id != &"" and r < _override_until and r >= 1:
		return _override_id
	return base_id_for_round(settings, seed, r)


## Rounds until the weather next changes (1 = next round), or -1 if it will not
## change within [constant FORECAST_HORIZON] rounds.
func rounds_until_change() -> int:
	var now := id_for_round(round)
	for k in range(1, FORECAST_HORIZON + 1):
		if id_for_round(round + k) != now:
			return k
	return -1


## The weather that follows the current one (&"" when it never changes).
func next_id() -> StringName:
	var k := rounds_until_change()
	return id_for_round(round + k) if k > 0 else &""


## Rounds left on a summoned override (0 = none).
func override_rounds_left() -> int:
	if _override_id == &"":
		return 0
	return maxi(0, _override_until - round)


## Stable, network-comparable summary folded into [method NetGameRules.state_digest].
func digest() -> Array:
	return [String(current_id()), round, String(_override_id), _override_until]


func _refresh() -> bool:
	var next := Weather.get_weather(id_for_round(round))
	if next == current:
		return false
	var previous := current
	current = next
	changed.emit(current, previous)
	return true


# --- Pure schedule maths ------------------------------------------------------

## Canonical settings dictionary: {mode, weather, schedule, pool, change_every}.
## Accepts partial input ({} -> fixed Clear) and JSON-ish values.
static func normalize_settings(raw: Dictionary) -> Dictionary:
	var mode := String(raw.get("mode", MODE_FIXED)).to_lower()
	if mode not in [MODE_FIXED, MODE_SCHEDULE, MODE_DYNAMIC]:
		mode = MODE_FIXED
	var schedule: Array = []
	for e in raw.get("schedule", []):
		if e is Dictionary and String(e.get("weather", "")) != "":
			schedule.append({ "weather": StringName(String(e["weather"])), "rounds": maxi(1, int(e.get("rounds", 1))) })
	var pool: Dictionary = {}
	var raw_pool = raw.get("pool", {})
	if raw_pool is Dictionary:
		for k in raw_pool:
			var w := float(raw_pool[k])
			if w > 0.0:
				pool[StringName(String(k))] = w
	return {
		"mode": mode,
		"weather": StringName(String(raw.get("weather", "clear"))) if String(raw.get("weather", "")) != "" else Weather.CLEAR,
		"schedule": schedule,
		"pool": pool,
		"change_every": maxi(1, int(raw.get("change_every", 3))),
	}


## The map's weather for round [param r] (1-based). PURE: same inputs -> same id on
## every peer, every run.
static func base_id_for_round(p_settings: Dictionary, p_seed: int, r: int) -> StringName:
	var s := p_settings if p_settings.has("mode") else normalize_settings(p_settings)
	var fallback: StringName = s.get("weather", Weather.CLEAR)
	match String(s["mode"]):
		MODE_SCHEDULE:
			var schedule: Array = s["schedule"]
			if schedule.is_empty():
				return fallback
			var total := 0
			for e in schedule:
				total += int(e["rounds"])
			var t := posmod(maxi(r, 1) - 1, total)
			for e in schedule:
				if t < int(e["rounds"]):
					return e["weather"]
				t -= int(e["rounds"])
			return fallback
		MODE_DYNAMIC:
			var pool: Dictionary = s["pool"]
			var period := (maxi(r, 1) - 1) / int(s["change_every"])
			if period == 0 or pool.is_empty():
				return fallback
			return _weighted_pick(pool, hash([p_seed, period, 7919]))
	return fallback


static func _weighted_pick(pool: Dictionary, roll_seed: int) -> StringName:
	var keys: Array = pool.keys()
	keys.sort_custom(func(a, b): return String(a) < String(b))
	var total := 0.0
	for k in keys:
		total += float(pool[k])
	var rng := RandomNumberGenerator.new()
	rng.seed = roll_seed
	var x := rng.randf() * total
	for k in keys:
		x -= float(pool[k])
		if x < 0.0:
			return StringName(k)
	return StringName(keys[keys.size() - 1])
