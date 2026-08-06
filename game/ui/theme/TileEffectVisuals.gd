extends RefCounted
class_name TileEffectVisuals

## Single source of truth for how a tile effect looks, shared by every surface
## that shows one: the in-battle TerrainInfoPanel chips, the 3D map overlay
## markers, and the Map Gallery legend. Centralizing it here keeps the colour and
## label of "Fire" (etc.) identical everywhere instead of drifting per screen.
##
## kind: "hazard" (harms the occupant), "buff" (helps it), "neutral".

const _TABLE := {
	&"fire":             { "name": "Fire",             "color": Color("e0552b"), "kind": "hazard" },
	&"empowering_water": { "name": "Empowering Water", "color": Color("3b82c4"), "kind": "buff" },
	&"fortify":          { "name": "Fortify",          "color": Color("c79a3b"), "kind": "buff" },
	&"tall_grass":       { "name": "Tall Grass",       "color": Color("4e9e4a"), "kind": "buff" },
	# Duskmaw's teleport anchor. "neutral", deliberately: it neither harms nor helps
	# whoever stands on it, so it must not pulse like a hazard or read as a buff -- it is a
	# steady dark mark that says only "something can arrive here".
	&"void_spot":        { "name": "Void Spot",        "color": Color("5c2b8a"), "kind": "neutral" },
}

const _FALLBACK := { "name": "Effect", "color": Color("9a8768"), "kind": "neutral" }

## Colours for the base/temporary distinction (a thin frame or label), so a
## runtime-applied effect (e.g. a move ignited the floor) reads differently from
## an inherent terrain effect (e.g. the grass itself).
const BASE_TINT := Color("c8a24b")      # amber -- inherent terrain
const TEMPORARY_TINT := Color("d98038")  # brighter -- applied this battle


## Visual descriptor for a [TileEffectResource] (or any object exposing id /
## display_name). Always returns a fresh dictionary: { name, color, kind }.
static func info_for(effect) -> Dictionary:
	var id: StringName = &""
	var disp := ""
	if effect != null:
		if "id" in effect:
			id = effect.id
		if "display_name" in effect and String(effect.display_name) != "":
			disp = String(effect.display_name)
	var out: Dictionary = (_TABLE.get(id, _FALLBACK) as Dictionary).duplicate()
	if disp != "":
		out["name"] = disp  # honour an authored display_name over the table default
	return out


## Same lookup keyed directly by effect id (for callers without the resource).
static func info_for_id(id: StringName) -> Dictionary:
	return (_TABLE.get(id, _FALLBACK) as Dictionary).duplicate()
