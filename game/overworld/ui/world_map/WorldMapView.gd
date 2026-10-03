class_name WorldMapView
extends Control

## THE WORLD MAP (Journey -> Map, docs/STORY_MODE.md "World map"): the owner's painting
## ([constant MAP_TEXTURE]) with one marker per known [WorldLocation] of a [WorldAtlas], drawn at
## its normalised [member WorldLocation.map_pos]. Presentation only -- it reads the atlas, the
## [StoryState] and a list of quest pins, and never writes anything.
##
## Markers: a glyph per kind (city = keep, town / village = house, dungeon / special = red seal,
## island = isle, route = waystone, nation = banner). VISITED places are gold, built but not yet
## visited cream, CLOSED ones dim with a lock; a SECRET place is left off until
## [method WorldLocation.is_known]. The player's place pulses, the respawn Wayshrine wears a green
## flame, quest objectives hang a "!" pennant (gold = main, green = side) over their place, and
## roads ([member show_roads]) can be overlaid by kind (main gold, secondary dashed, sea dashed blue).
## The selected place shows a CARD (name, region, kind, status, description, the quests that point
## there) in the corner away from it.
##
## Input (while focused): arrows / d-pad / left stick step to the nearest marker in that direction
## (none that way -> the key falls through to normal focus navigation), Tab / shoulders cycle the
## markers, Confirm zooms onto the selection (again: back out), the right stick / WASD pan,
## + / - / triggers / the wheel zoom, a mouse or one finger drags, two fingers pinch, a click or tap
## selects the marker under it.

signal selection_changed(location_id: String)

const MAP_TEXTURE := "res://game/overworld/ui/world_map/world_map.webp"
const MIN_ZOOM: float = 1.0
const MAX_ZOOM: float = 5.0
const WHEEL_STEP: float = 1.18
const FOCUS_ZOOM: float = 2.6
## Screen pixels: a press that moves less than this is a click, not a drag.
const DRAG_SLOP: float = 8.0
## Screen pixels: how close a click must land to a marker to pick it.
const PICK_RADIUS: float = 26.0
const MARKER_R: float = 9.0
const PAN_SPEED: float = 0.9   # view widths per second at full stick
const ZOOM_SPEED: float = 1.6  # zoom doublings per second at full trigger

const QUEST_MAIN_COLOR := MenuTheme.GOLD
const QUEST_SIDE_COLOR := MenuTheme.SUCCESS
const REST_COLOR := MenuTheme.EL_NATURE

var atlas: WorldAtlas = null
var state: StoryState = null
## [{id, title, category ("main" / "side"), location}] -- the active objectives to pin.
var quest_pins: Array = []
var show_roads: bool = false:
	set(v):
		show_roads = v
		queue_redraw()

var _tex: Texture2D = null
var _zoom: float = 1.0
## The normalised map point at the centre of the view.
var _center: Vector2 = Vector2(0.5, 0.5)
var _selected: String = ""
## id -> {id, pos, kind, name, here, rest, visited, built, closed, quests: Array}
var _markers: Dictionary = {}
var _order: Array[String] = []
var _time: float = 0.0
var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragging: bool = false
var _touches: Dictionary = {}
## The stick direction already acted on (reset when the stick returns to centre).
var _stick_latch: Vector2 = Vector2.ZERO
var _pinch_dist: float = 0.0
var _card: PanelContainer = null
var _card_box: VBoxContainer = null
## The view frames itself (cover + centred on the player) on every resize until the player or a
## caller moves it (a zoom, a pan, "Show on map").
var _auto_frame: bool = true
## The card was last built for a short view ([method _short]).
var _card_short: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = Vector2(280, 200)
	tooltip_text = ""


func _ready() -> void:
	if _tex == null and ResourceLoader.exists(MAP_TEXTURE):
		_tex = load(MAP_TEXTURE) as Texture2D
	_card = PanelContainer.new()
	_card.name = "PlaceCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 3)
	_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_box)
	resized.connect(_on_resized)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Point the map at [param p_atlas] under [param p_state] with [param pins] (see [member quest_pins]).
## Keeps the selection when its place is still on the map, else selects where the player is.
func setup(p_atlas: WorldAtlas, p_state: StoryState, pins: Array = []) -> void:
	atlas = p_atlas
	state = p_state
	quest_pins = pins
	_rebuild_markers()
	if _selected.is_empty() or not _markers.has(_selected):
		var here: String = here_id()
		_selected = here if _markers.has(here) else (_order[0] if not _order.is_empty() else "")
	_refresh_card()
	queue_redraw()


# =====================================================================================
#  Queries (tests, JourneyMenu)
# =====================================================================================

func selected_id() -> String:
	return _selected


## The ids of every place drawn on the map, in atlas order.
func marker_ids() -> Array[String]:
	return _order.duplicate()


func has_marker(location_id: String) -> bool:
	return _markers.has(location_id)


## What the map knows about [param location_id] ({} when it is not drawn).
func marker_info(location_id: String) -> Dictionary:
	return (_markers.get(location_id, {}) as Dictionary).duplicate(true)


func zoom() -> float:
	return _zoom


func view_center() -> Vector2:
	return _center


func card() -> PanelContainer:
	return _card


## The place the player stands in ("" when the area is not on the map).
func here_id() -> String:
	if atlas == null or state == null:
		return ""
	var l: WorldLocation = atlas.location_for_area(state.location_area())
	return String(l.id) if l != null else ""


## The place of the respawn Wayshrine ("" when none is set / not on the map).
func rest_id() -> String:
	if atlas == null or state == null:
		return ""
	var l: WorldLocation = atlas.location_for_area(String(state.respawn.get("area_id", "")))
	return String(l.id) if l != null else ""


# =====================================================================================
#  Selection / camera
# =====================================================================================

## Select [param location_id] (ignored when it is not on the map). [param reveal] pans so the
## marker is inside the view.
func select(location_id: String, reveal: bool = true) -> bool:
	if not _markers.has(location_id):
		return false
	var changed: bool = _selected != location_id
	_selected = location_id
	if reveal:
		_reveal(_markers[location_id]["pos"])
	_refresh_card()
	queue_redraw()
	if changed:
		selection_changed.emit(location_id)
	return true


## Select [param location_id] and zoom onto it (Journey -> Quests "Show on map").
func focus_location(location_id: String, zoom_to: float = -1.0) -> bool:
	if not select(location_id, false):
		return false
	_auto_frame = false
	set_zoom(zoom_to if zoom_to > 0.0 else focus_zoom())
	_center = _markers[location_id]["pos"]
	_clamp_center()
	_place_card()
	queue_redraw()
	return true


## The zoom at which the painting just COVERS the view (no letterbox): the opening view, so a wide
## short phone view is all map rather than map plus two dark bands. 1.0 = "contain".
func cover_zoom() -> float:
	var ts: Vector2 = _texture_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return 1.0
	return maxf(size.x / ts.x, size.y / ts.y) / _fit_scale()


## The close-up zoom Confirm / "Show on map" use.
func focus_zoom() -> float:
	return clampf(maxf(FOCUS_ZOOM, cover_zoom() * 1.8), MIN_ZOOM, max_zoom())


func max_zoom() -> float:
	return maxf(MAX_ZOOM, cover_zoom() * 3.0)


func set_zoom(z: float, anchor_view: Vector2 = Vector2(-1, -1)) -> void:
	_auto_frame = false
	var nz: float = clampf(z, MIN_ZOOM, max_zoom())
	if is_equal_approx(nz, _zoom):
		return
	var anchor: Vector2 = anchor_view if anchor_view.x >= 0.0 else size * 0.5
	var before: Vector2 = view_to_map(anchor)
	_zoom = nz
	# Keep the map point under the anchor where it was.
	var after: Vector2 = view_to_map(anchor)
	_center += before - after
	_clamp_center()
	_place_card()
	queue_redraw()


func zoom_by(factor: float, anchor_view: Vector2 = Vector2(-1, -1)) -> void:
	set_zoom(_zoom * factor, anchor_view)


## Pan by [param delta] screen pixels (drag direction: the map follows the finger).
func pan_pixels(delta: Vector2) -> void:
	_auto_frame = false
	var img: Vector2 = _image_size()
	if img.x <= 0.0 or img.y <= 0.0:
		return
	_center -= Vector2(delta.x / img.x, delta.y / img.y)
	_clamp_center()
	_place_card()
	queue_redraw()


## Back to the opening view, and keep framing it as the view resizes (until moved again).
func frame_default() -> void:
	_auto_frame = true
	reset_view()


## The opening view: the painting covering the view, centred on where the player is.
func reset_view() -> void:
	_zoom = clampf(cover_zoom(), MIN_ZOOM, max_zoom())
	var here: String = here_id()
	_center = _markers[here]["pos"] if _markers.has(here) else Vector2(0.5, 0.5)
	_clamp_center()
	_place_card()
	queue_redraw()


## Normalised map point -> view pixels.
func map_to_view(n: Vector2) -> Vector2:
	return _origin() + n * _image_size()


## View pixels -> normalised map point.
func view_to_map(p: Vector2) -> Vector2:
	var img: Vector2 = _image_size()
	if img.x <= 0.0 or img.y <= 0.0:
		return Vector2(0.5, 0.5)
	return (p - _origin()) / img


func _texture_size() -> Vector2:
	return _tex.get_size() if _tex != null else Vector2(1536, 1024)


## "Contain" fit at zoom 1: the whole painting is visible.
func _fit_scale() -> float:
	var ts: Vector2 = _texture_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return 1.0
	return minf(size.x / ts.x, size.y / ts.y)


func _image_size() -> Vector2:
	return _texture_size() * _fit_scale() * _zoom


func _origin() -> Vector2:
	return size * 0.5 - _center * _image_size()


func _clamp_center() -> void:
	var img: Vector2 = _image_size()
	for axis in [0, 1]:
		var view: float = size[axis]
		var span: float = img[axis]
		if span <= view or span <= 0.0:
			_center[axis] = 0.5
		else:
			var half: float = (view * 0.5) / span
			_center[axis] = clampf(_center[axis], half, 1.0 - half)


## Pan the least amount that brings [param n] (normalised) inside the view with a margin.
func _reveal(n: Vector2) -> void:
	var p: Vector2 = map_to_view(n)
	var margin: Vector2 = Vector2(minf(60.0, size.x * 0.2), minf(60.0, size.y * 0.2))
	var d: Vector2 = Vector2.ZERO
	if p.x < margin.x:
		d.x = margin.x - p.x
	elif p.x > size.x - margin.x:
		d.x = size.x - margin.x - p.x
	if p.y < margin.y:
		d.y = margin.y - p.y
	elif p.y > size.y - margin.y:
		d.y = size.y - margin.y - p.y
	if d != Vector2.ZERO:
		pan_pixels(d)


func _on_resized() -> void:
	if _auto_frame and size.x > 0.0 and size.y > 0.0:
		reset_view()
	_clamp_center()
	if _short() != _card_short:
		_refresh_card()   # a short view drops the description
	_place_card()
	queue_redraw()


## A SHORT view (a phone in landscape): the card keeps to name, region, status and quests.
func _short() -> bool:
	return size.y > 0.0 and size.y < 340.0


# =====================================================================================
#  Markers
# =====================================================================================

func _rebuild_markers() -> void:
	_markers.clear()
	_order.clear()
	if atlas == null:
		return
	var here: String = here_id()
	var rest: String = rest_id()
	for l in atlas.locations:
		if l == null or not l.is_known(state):
			continue
		var id: String = String(l.id)
		var visited: bool = false
		if state != null:
			for aid in l.area_ids:
				if state.visited_areas.has(String(aid)) or state.location_area() == String(aid):
					visited = true
		var quests: Array = []
		for q in quest_pins:
			if q is Dictionary and String(q.get("location", "")) == id:
				quests.append(q)
		_markers[id] = {
			"id": id,
			"name": l.display_name,
			"kind": l.kind,
			"region": String(atlas.regions.get(l.region_id, atlas.regions.get(String(l.region_id), ""))),
			"description": l.description,
			"pos": l.map_pos,
			"built": l.is_built(),
			"closed": not l.is_built(),
			"visited": visited,
			"here": id == here,
			"rest": id == rest,
			"quests": quests,
		}
		_order.append(id)


## The marker under view point [param p] (within [constant PICK_RADIUS]), or "".
func marker_at(p: Vector2) -> String:
	var best: String = ""
	var best_d: float = PICK_RADIUS
	for id in _order:
		var d: float = map_to_view(_markers[id]["pos"]).distance_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best


## The nearest marker from the selection in screen direction [param dir] ("" when none lies that
## way). Distance plus a penalty for drifting off the axis, so "right" prefers what is level.
func neighbour_in(dir: Vector2) -> String:
	if not _markers.has(_selected):
		return _order[0] if not _order.is_empty() else ""
	var ts: Vector2 = _texture_size()
	var from: Vector2 = (_markers[_selected]["pos"] as Vector2) * ts
	var best: String = ""
	var best_score: float = INF
	for id in _order:
		if id == _selected:
			continue
		var d: Vector2 = (_markers[id]["pos"] as Vector2) * ts - from
		var along: float = d.dot(dir)
		if along <= 1.0:
			continue
		var across: float = absf(d.cross(dir))
		if across > along * 2.5:
			continue
		var score: float = along + across * 2.0
		if score < best_score:
			best_score = score
			best = id
	return best


func cycle(step: int) -> void:
	if _order.is_empty():
		return
	var i: int = _order.find(_selected)
	i = (i + step + _order.size()) % _order.size() if i >= 0 else 0
	select(_order[i])


# =====================================================================================
#  The card
# =====================================================================================

func _refresh_card() -> void:
	if _card == null:
		return
	for c in _card_box.get_children():
		_card_box.remove_child(c)
		c.queue_free()
	_card_short = _short()
	if not _markers.has(_selected):
		_card.visible = false
		return
	var m: Dictionary = _markers[_selected]
	var accent: Color = MenuTheme.GOLD if bool(m["visited"]) else (MenuTheme.TEXT_MUTED if bool(m["closed"]) else MenuTheme.GOLD_DK)
	_card.add_theme_stylebox_override("panel", MenuTheme.accented_card(accent, SIDE_LEFT, MenuTheme.PANEL, 0.94))
	ConquestTheme.keep_style(_card)
	var name_l := MenuKit.label(String(m["name"]), &"SubheadingLabel")
	name_l.name = "PlaceName"
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	_card_box.add_child(name_l)
	var meta := MenuKit.label("%s  ·  %s" % [String(m["region"]), kind_name(String(m["kind"]))], &"DimLabel")
	meta.name = "PlaceMeta"
	meta.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	_card_box.add_child(meta)
	var chips := HFlowContainer.new()
	chips.name = "PlaceChips"
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_box.add_child(chips)
	for chip in status_chips(m):
		chips.add_child(ConquestTheme.chip(String(chip[0]), chip[1], MenuTheme.FS_CAPTION))
	if not String(m["description"]).is_empty() and not _short():
		var d := MenuKit.label(String(m["description"]), &"DimLabel", true)
		d.name = "PlaceDescription"
		d.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		_card_box.add_child(d)
	for q in m["quests"]:
		var main: bool = String(q.get("category", "")) == "main"
		var ql := MenuKit.label("!  %s" % String(q.get("title", "")), &"", true)
		ql.name = "PlaceQuest_" + String(q.get("id", ""))
		ql.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		ql.add_theme_color_override("font_color", QUEST_MAIN_COLOR if main else QUEST_SIDE_COLOR)
		_card_box.add_child(ql)
	MenuKit.ignore_mouse(_card)
	_card.visible = true
	_place_card.call_deferred()


## The status chips of marker [param m]: [[text, colour], ...].
static func status_chips(m: Dictionary) -> Array:
	var out: Array = []
	if bool(m.get("here", false)):
		out.append(["You are here", MenuTheme.GOLD])
	if bool(m.get("rest", false)):
		out.append(["Wayshrine", REST_COLOR])
	if bool(m.get("closed", false)):
		out.append(["Road closed", MenuTheme.TEXT_MUTED])
	elif bool(m.get("visited", false)):
		out.append(["Visited", MenuTheme.GOLD_DK])
	else:
		out.append(["Not yet visited", MenuTheme.ACCENT])
	if not (m.get("quests", []) as Array).is_empty():
		out.append(["Quest", QUEST_MAIN_COLOR])
	return out


static func kind_name(kind: String) -> String:
	match kind:
		"city":
			return "City"
		"town":
			return "Town"
		"village":
			return "Village"
		"route":
			return "Route"
		"dungeon":
			return "Dungeon"
		"special":
			return "Special encounter"
		"island":
			return "Island"
		"nation":
			return "Foreign land"
	return kind.capitalize()


## Keep the card in the bottom corner away from the selected marker, inside the view.
func _place_card() -> void:
	if _card == null or not _card.visible or not _markers.has(_selected):
		return
	var w: float = clampf(size.x * (0.42 if _short() else 0.5), 180.0, 300.0)
	_card.custom_minimum_size = Vector2(w, 0)
	_card.size = Vector2(w, 0)
	_card.reset_size()
	var h: float = _card.get_combined_minimum_size().y
	var p: Vector2 = map_to_view(_markers[_selected]["pos"])
	var pad: float = 10.0
	var x: float = pad if p.x > size.x * 0.5 else size.x - w - pad
	var y: float = size.y - h - pad
	# A marker low in the view on the card's side: lift the card to the top instead.
	if p.y > size.y * 0.55 and absf(p.x - (x + w * 0.5)) < w * 0.75:
		y = pad
	_card.position = Vector2(x, maxf(pad, y))


# =====================================================================================
#  Drawing
# =====================================================================================

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if has_focus():
		var pan := Vector2(
			Input.get_action_strength(InputActions.CAMERA_PAN_RIGHT) - Input.get_action_strength(InputActions.CAMERA_PAN_LEFT),
			Input.get_action_strength(InputActions.CAMERA_PAN_DOWN) - Input.get_action_strength(InputActions.CAMERA_PAN_UP))
		if pan.length() > 0.15:
			pan_pixels(-pan * size.x * PAN_SPEED * delta)
		var zin: float = Input.get_action_strength(InputActions.FLOOR_UP) - Input.get_action_strength(InputActions.FLOOR_DOWN)
		if absf(zin) > 0.15:
			zoom_by(pow(2.0, zin * ZOOM_SPEED * delta))
	# The "you are here" pulse.
	if _markers.has(here_id()) and _anims_on():
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MenuTheme.BG_DEEP)
	var origin: Vector2 = _origin()
	var img: Vector2 = _image_size()
	if _tex != null:
		draw_texture_rect(_tex, Rect2(origin, img), false)
	else:
		draw_rect(Rect2(origin, img), MenuTheme.PANEL_SUNK)
	if show_roads:
		_draw_roads()
	var s: float = clampf(0.75 + 0.25 * _zoom, 0.85, 1.6)
	for id in _order:
		if id != _selected:
			_draw_marker(_markers[id], s)
	if _markers.has(_selected):
		_draw_marker(_markers[_selected], s)
	# Focus frame: the gold ring every focusable control wears.
	if has_focus():
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), MenuTheme.GOLD, false, 2.0)


func _draw_roads() -> void:
	if atlas == null:
		return
	for r in atlas.roads:
		var a: String = String(r.get("a", ""))
		var b: String = String(r.get("b", ""))
		if not _markers.has(a) or not _markers.has(b):
			continue
		var pa: Vector2 = map_to_view(_markers[a]["pos"])
		var pb: Vector2 = map_to_view(_markers[b]["pos"])
		match String(r.get("kind", "")):
			"main":
				draw_line(pa, pb, Color(MenuTheme.BG_DEEP, 0.7), 5.0, true)
				draw_line(pa, pb, MenuTheme.GOLD, 2.5, true)
			"sea":
				draw_dashed_line(pa, pb, Color(MenuTheme.EL_WIND, 0.95), 2.5, 9.0, true)
			_:
				draw_dashed_line(pa, pb, Color(MenuTheme.CREAM, 0.9), 2.0, 7.0, true)


func _draw_marker(m: Dictionary, s: float) -> void:
	var p: Vector2 = map_to_view(m["pos"])
	if p.x < -40.0 or p.y < -40.0 or p.x > size.x + 40.0 or p.y > size.y + 40.0:
		return
	var selected: bool = String(m["id"]) == _selected
	var r: float = MARKER_R * s * (1.25 if selected else 1.0)
	var closed: bool = bool(m["closed"])
	var fill: Color = MenuTheme.GOLD if bool(m["visited"]) else MenuTheme.CREAM
	if closed:
		fill = MenuTheme.TEXT_MUTED.darkened(0.15)
	var kind: String = String(m["kind"])
	if kind == "dungeon" or kind == "special":
		fill = MenuTheme.DANGER.darkened(0.15) if not closed else MenuTheme.DANGER.darkened(0.5)
	var rim: Color = MenuTheme.BG_DEEP
	if bool(m["here"]):
		var t: float = fmod(_time, 1.6) / 1.6 if _anims_on() else 0.5
		draw_circle(p, r * (1.4 + 1.4 * t), Color(MenuTheme.GOLD_LITE, 0.75 * (1.0 - t)), false, 3.0, true)
		draw_circle(p, r * 1.55, Color(MenuTheme.GOLD_LITE, 0.9), false, 2.5, true)
	if selected:
		draw_circle(p, r * 1.9, Color(MenuTheme.BG_DEEP, 0.55), true)
		draw_circle(p, r * 1.9, MenuTheme.GOLD, false, 2.5, true)
	_draw_glyph(kind, p, r, fill, rim)
	if closed:
		_draw_lock(p + Vector2(r * 0.9, r * 0.75), r * 0.55)
	if bool(m["rest"]):
		_draw_flame(p + Vector2(-r * 1.15, r * 0.9), r * 0.6)
	var quests: Array = m["quests"]
	for i in range(quests.size()):
		var main: bool = String((quests[i] as Dictionary).get("category", "")) == "main"
		var qp: Vector2 = p + Vector2((i - (quests.size() - 1) * 0.5) * r * 1.6, -r * 2.3)
		_draw_pennant(qp, r * 0.8, QUEST_MAIN_COLOR if main else QUEST_SIDE_COLOR)


func _draw_glyph(kind: String, p: Vector2, r: float, fill: Color, rim: Color) -> void:
	match kind:
		"city":
			# A keep: a wide block with three merlons.
			var w: float = r * 1.15
			var body := PackedVector2Array([
				p + Vector2(-w, r * 0.9), p + Vector2(-w, -r * 0.5), p + Vector2(-w * 0.55, -r * 0.5),
				p + Vector2(-w * 0.55, -r * 0.95), p + Vector2(-w * 0.2, -r * 0.95), p + Vector2(-w * 0.2, -r * 0.5),
				p + Vector2(w * 0.2, -r * 0.5), p + Vector2(w * 0.2, -r * 0.95), p + Vector2(w * 0.55, -r * 0.95),
				p + Vector2(w * 0.55, -r * 0.5), p + Vector2(w, -r * 0.5), p + Vector2(w, r * 0.9)])
			_poly(body, fill, rim)
			draw_rect(Rect2(p + Vector2(-r * 0.25, r * 0.25), Vector2(r * 0.5, r * 0.65)), rim)
		"town", "village":
			var hw: float = r * (1.0 if kind == "town" else 0.85)
			var house := PackedVector2Array([
				p + Vector2(-hw, r * 0.85), p + Vector2(-hw, -r * 0.1), p + Vector2(0, -r * 1.05),
				p + Vector2(hw, -r * 0.1), p + Vector2(hw, r * 0.85)])
			_poly(house, fill, rim)
			if kind == "town":
				draw_line(p + Vector2(-hw, -r * 0.1), p + Vector2(hw, -r * 0.1), rim, 1.5, true)
		"dungeon", "special":
			var seal := PackedVector2Array()
			for i in range(6):
				var a: float = TAU * float(i) / 6.0 + PI / 6.0
				seal.append(p + Vector2(cos(a), sin(a)) * r)
			_poly(seal, fill, rim)
			draw_circle(p, r * 0.32, MenuTheme.CREAM if kind == "special" else rim, true)
		"island":
			draw_circle(p, r * 0.95, rim, true)
			draw_circle(p, r * 0.75, fill, true)
			draw_arc(p + Vector2(0, r * 0.15), r * 0.45, PI * 0.15, PI * 0.85, 8, rim, 1.5, true)
		"route":
			draw_circle(p, r * 0.7, rim, true)
			draw_circle(p, r * 0.5, fill, true)
		"nation":
			var flag := PackedVector2Array([
				p + Vector2(-r * 0.7, -r), p + Vector2(r, -r * 0.55), p + Vector2(-r * 0.7, -r * 0.1)])
			draw_line(p + Vector2(-r * 0.7, -r), p + Vector2(-r * 0.7, r), rim, 3.0, true)
			_poly(flag, MenuTheme.TEAM_RED if fill != MenuTheme.TEXT_MUTED.darkened(0.15) else fill, rim)
		_:
			draw_circle(p, r * 0.8, rim, true)
			draw_circle(p, r * 0.6, fill, true)


func _poly(points: PackedVector2Array, fill: Color, rim: Color) -> void:
	draw_colored_polygon(points, fill)
	var closed_pts := points.duplicate()
	closed_pts.append(points[0])
	draw_polyline(closed_pts, rim, 2.0, true)


func _draw_lock(p: Vector2, r: float) -> void:
	draw_arc(p + Vector2(0, -r * 0.3), r * 0.5, PI, TAU, 8, MenuTheme.BG_DEEP, 2.5, true)
	draw_rect(Rect2(p + Vector2(-r * 0.7, -r * 0.3), Vector2(r * 1.4, r * 1.1)), MenuTheme.BG_DEEP)
	draw_rect(Rect2(p + Vector2(-r * 0.5, -r * 0.15), Vector2(r * 1.0, r * 0.8)), MenuTheme.TEXT_DIM)


func _draw_flame(p: Vector2, r: float) -> void:
	var flame := PackedVector2Array([p + Vector2(0, -r * 1.3), p + Vector2(r * 0.75, r * 0.1),
		p + Vector2(r * 0.45, r * 0.8), p + Vector2(-r * 0.45, r * 0.8), p + Vector2(-r * 0.75, r * 0.1)])
	_poly(flame, REST_COLOR, MenuTheme.BG_DEEP)


func _draw_pennant(p: Vector2, r: float, color: Color) -> void:
	var shape := PackedVector2Array([p + Vector2(-r, -r), p + Vector2(r, -r), p + Vector2(r, r * 0.5),
		p + Vector2(0, r * 1.2), p + Vector2(-r, r * 0.5)])
	_poly(shape, color, MenuTheme.BG_DEEP)
	draw_line(p + Vector2(0, -r * 0.6), p + Vector2(0, r * 0.15), MenuTheme.INK, 2.0, true)
	draw_circle(p + Vector2(0, r * 0.5), 1.4, MenuTheme.INK, true)


# =====================================================================================
#  Input
# =====================================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(WHEEL_STEP, mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / WHEEL_STEP, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_pressing = true
				_dragging = false
				_press_pos = mb.position
				if mb.double_click:
					var hit: String = marker_at(mb.position)
					if not hit.is_empty():
						_activate(hit)
			else:
				if _pressing and not _dragging:
					var hit2: String = marker_at(mb.position)
					if not hit2.is_empty():
						select(hit2, false)
				_pressing = false
				_dragging = false
			accept_event()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressing and _touches.size() < 2:
			if not _dragging and mm.position.distance_to(_press_pos) > DRAG_SLOP:
				_dragging = true
			if _dragging:
				pan_pixels(mm.relative)
			accept_event()
		return
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		zoom_by(mg.factor, mg.position)
		accept_event()
		return
	if event is InputEventPanGesture:
		pan_pixels(-(event as InputEventPanGesture).delta * 8.0)
		accept_event()
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch_dist = _touch_spread()
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var spread: float = _touch_spread()
			if _pinch_dist > 1.0 and spread > 1.0:
				zoom_by(spread / _pinch_dist, _touch_mid())
			_pinch_dist = spread
			accept_event()
		return
	if event is InputEventJoypadMotion:
		# A stick sends a stream of motion events while held: step ONCE per push.
		var d0 := _direction_of(event) if event.is_pressed() else Vector2.ZERO
		if d0 == Vector2.ZERO:
			if absf((event as InputEventJoypadMotion).axis_value) < 0.3:
				_stick_latch = Vector2.ZERO
			return
		if d0 == _stick_latch:
			accept_event()
			return
		_stick_latch = d0
	if not event.is_pressed():
		return
	var dir := _direction_of(event)
	if dir != Vector2.ZERO:
		var next: String = neighbour_in(dir)
		if not next.is_empty():
			select(next)
			accept_event()
		# Nothing that way: let the focus move on (toolbar above, the command rows left).
		return
	if MenuNav.is_next_event(event):
		cycle(1)
		accept_event()
	elif MenuNav.is_prev_event(event):
		cycle(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(InputActions.CONFIRM):
		_activate(_selected)
		accept_event()
	elif event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_PAGEUP:
				zoom_by(1.4)
				accept_event()
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
				zoom_by(1.0 / 1.4)
				accept_event()
			KEY_HOME:
				reset_view()
				accept_event()


## Confirm on a marker: zoom onto it, or back out when already close.
func _activate(location_id: String) -> void:
	if not _markers.has(location_id):
		return
	if _zoom >= focus_zoom() - 0.05 and location_id == _selected:
		reset_view()
	else:
		focus_location(location_id)


func _direction_of(event: InputEvent) -> Vector2:
	if event.is_echo() and not (event is InputEventKey):
		return Vector2.ZERO
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(InputActions.CURSOR_LEFT):
		return Vector2.LEFT
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(InputActions.CURSOR_RIGHT):
		return Vector2.RIGHT
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(InputActions.CURSOR_UP):
		return Vector2.UP
	if event.is_action_pressed(&"ui_down") or event.is_action_pressed(InputActions.CURSOR_DOWN):
		return Vector2.DOWN
	return Vector2.ZERO


func _touch_spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var pts: Array = _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _touch_mid() -> Vector2:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return size * 0.5
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5 - global_position


func _anims_on() -> bool:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null or not gs.has_method("animations_on"):
		return true
	return bool(gs.animations_on())
