extends EvolutionTrigger
class_name LocationTrigger

## Met while the party stands in one of [member area_ids], or anywhere in region
## [member region_id] (docs/design/DECISIONS.md #16 / #26: a class promotion at a trainer's
## order, an evolution in a sacred grove). Either may be empty; the requirement is met when ANY
## given place matches. Reads ctx keys [code]area_id[/code] / [code]region_id[/code] (story only
## -- [StoryGrowth.evolution_context]). Entering an area raises an "area" auto-offer event, so a
## "visit the Proving Grounds" promotion is offered on arrival.

@export var area_ids: PackedStringArray = PackedStringArray()
## An [member OverworldAreaResource.region_id] ("greenwold").
@export var region_id: String = ""
## Checklist text for the place ("the Proving Grounds"); "" = the area / region name.
@export var place_label: String = ""


func is_met(ctx: Dictionary) -> bool:
	var area: String = String(ctx.get("area_id", ""))
	if not area.is_empty() and area_ids.has(area):
		return true
	var region: String = String(ctx.get("region_id", ""))
	return not region_id.is_empty() and region == region_id


func describe() -> String:
	return "Be at %s" % place_text()


func place_text() -> String:
	if not place_label.strip_edges().is_empty():
		return place_label
	var names: PackedStringArray = []
	for id in area_ids:
		var a: OverworldAreaResource = OverworldAreaResource.load_by_id(String(id))
		names.append(a.display_name if a != null and not a.display_name.is_empty() else String(id).capitalize())
	if not region_id.is_empty():
		names.append("the %s region" % region_id.capitalize())
	return " or ".join(names) if not names.is_empty() else "?"


func progress(ctx: Dictionary) -> String:
	if not ctx.has("area_id"):
		return ""
	return "here now" if is_met(ctx) else ""


func needs_story() -> bool:
	return true


func responds_to(event: Dictionary) -> bool:
	return event_has(event, "area")


func problem() -> String:
	if area_ids.is_empty() and region_id.strip_edges().is_empty():
		return "a Location requirement names no area and no region"
	return ""
