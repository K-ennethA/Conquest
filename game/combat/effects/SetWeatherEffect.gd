extends MoveEffect
class_name SetWeatherEffect

## Summons a weather for [member rounds] rounds (a rain dance, a sandstorm howl, a
## bloom call). The battle's [WeatherState] holds it as an OVERRIDE through the rest
## of this round and for rounds-1 more; the map's own weather resumes after.
## Re-casting refreshes it. Deterministic (no roll), so it is network-safe.

## Weather id to summon (see game/weather/resources/).
@export var weather: StringName = &"rain"
@export_range(1, 20) var rounds: int = 3


func apply(ctx: MoveContext) -> void:
	var state := Weather.state()
	if state == null:
		return
	var previous := state.current_id()
	state.set_override(weather, rounds)
	ctx.log_event({
		"effect": "set_weather",
		"weather": weather,
		"previous": previous,
		"rounds": rounds,
	})


func describe() -> String:
	if description_override != "":
		return description_override
	return "Summon %s for %d rounds" % [Weather.get_weather(weather).display_name, rounds]
