class_name PlaceAnnouncer
extends RefCounted

## WHEN TO NAME A PLACE: the classic-Pokemon location popup rule. A small, non-blocking name chip
## ([method OverworldHUD.show_area_name]) appears when the hero enters a DIFFERENT named place --
## never inside a building (interiors are rooms, not places), never again for the place he is
## already standing in (leaving a building, a script's own warp back), and never for a place that
## was named a moment ago (hopping back and forth over an area edge). Pure logic on a clock the
## caller passes in, so it is unit-testable; StoryController owns the live instance for a journey.

## A place named within this many milliseconds is not named again.
const REPEAT_COOLDOWN_MSEC := 20000

var _last_name: String = ""
## place name -> msec it was last named.
var _named_at: Dictionary = {}


## True when [param place_name] should get its popup now (and records that it did).
func announce(place_name: String, is_interior: bool, now_msec: int) -> bool:
	if is_interior or place_name.is_empty():
		return false
	if place_name == _last_name:
		return false
	if _named_at.has(place_name) and now_msec - int(_named_at[place_name]) < REPEAT_COOLDOWN_MSEC:
		# Remember we are standing here now, so the hop back is not "different" either.
		_last_name = place_name
		return false
	_last_name = place_name
	_named_at[place_name] = now_msec
	return true


## Forget everything (a new / loaded journey names its first place).
func reset() -> void:
	_last_name = ""
	_named_at.clear()
