extends EvolutionTrigger
class_name WeatherTrigger

## Met while the current weather is one of [member weathers] (docs/design/DECISIONS.md #26
## "time-of-day or weather"). Reads ctx key [code]weather[/code]: the weather of the area the
## party stands in (its terrain's weather id -- [StoryGrowth.evolution_context]). A story
## requirement: open-mode menus have no current weather, so it is unmet there.

## Weather ids (game/weather/resources/<id>.tres): "rain", "sandstorm"...
@export var weathers: PackedStringArray = PackedStringArray()


func is_met(ctx: Dictionary) -> bool:
	var w: String = String(ctx.get("weather", ""))
	return not w.is_empty() and weathers.has(w)


func describe() -> String:
	var names: PackedStringArray = []
	for id in weathers:
		var res: WeatherResource = Weather.get_weather(StringName(id)) if Weather.has_weather(StringName(id)) else null
		names.append(res.display_name if res != null else String(id).capitalize())
	return "During %s" % (" or ".join(names) if not names.is_empty() else "?")


func needs_story() -> bool:
	return true


func responds_to(event: Dictionary) -> bool:
	return event_has(event, "area") or event_has(event, "battle")


func problem() -> String:
	return "a Weather requirement names no weather" if weathers.is_empty() else ""
