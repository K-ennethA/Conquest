extends AbilityCondition
class_name UnitElementCondition

## Met when the unit's element ([member CharacterResource.element]) is one of
## [member elements], OR its character carries one of [member tags]
## ([member CharacterResource.tags]). Wrap it in a [NotCondition] for "everyone
## except ..." -- Desert Storm's chip damage spares earth units and anything tagged
## &"sand_proof" that way.
##
## Duck-typed: reads get_element() / an element property and the unit's
## character_resource.tags (or a tags property on a mock). A unit exposing neither
## simply never matches.

@export var elements: Array[StringName] = []
@export var tags: Array[StringName] = []


func is_met(unit, _board) -> bool:
	if unit == null:
		return false
	var elem := ElementChart.element_of(unit)
	if elem != &"":
		for e in elements:
			if StringName(e) == elem:
				return true
	if not tags.is_empty():
		for t in _tags_of(unit):
			for want in tags:
				if StringName(t) == StringName(want):
					return true
	return false


func describe() -> String:
	var parts: Array[String] = []
	for e in elements:
		parts.append(String(e))
	for t in tags:
		parts.append(String(t))
	return "is %s" % " / ".join(parts)


static func _tags_of(unit) -> Array:
	var cr = unit.get("character_resource")
	if cr != null:
		var t = cr.get("tags")
		if t is Array:
			return t
	var own = unit.get("tags")
	if own is Array:
		return own
	return []
