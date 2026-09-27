extends AbilityCondition
class_name WeatherCondition

## Met while the battle's active weather is one of [member weathers] -- the gate for
## weather-reactive abilities ("Rain Bath: heal while it rains", "Sand Veil: evasion
## in a Desert Storm"). Reads the live [WeatherState] through [Weather]; with no live
## battle (headless) the weather is Clear, so a condition naming &"clear" holds and
## every other one fails closed.

## Weather ids ([member WeatherResource.id]) that satisfy this condition.
@export var weathers: Array[StringName] = []


func is_met(_unit, _board) -> bool:
	var now := Weather.current_id()
	for w in weathers:
		if StringName(w) == now:
			return true
	return false


func describe() -> String:
	var names: Array[String] = []
	for w in weathers:
		names.append(Weather.get_weather(w).display_name)
	return "in %s" % " / ".join(names) if not names.is_empty() else "never"
