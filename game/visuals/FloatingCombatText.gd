extends CanvasLayer
class_name FloatingCombatText

## FLOATING COMBAT TEXT: a number over the unit for EVERY HP change -- attacks, crits,
## misses, heals, shields, burning tiles, status ticks, weather chip damage and
## healing, hazards, lifesteal. Presentation only (it never writes game state).
##
## Mechanism (see [CombatText] and [CombatTextPairer]):
##   * listens to every unit's [signal UnitStats.health_changed] (connected on
##     board_ready / unit_spawned, and lazily on the first annotation), the universal
##     HP chokepoint -- so nothing that changes HP can be missed;
##   * listens to [signal GameEvents.combat_text_annotated], which sources emit just
##     BEFORE changing HP, to learn the context (crit, effectiveness, source name);
##   * unclaimed annotations are shown at the end of the frame (MISS, IMMUNE,
##     "Blocked N" for a hit a shield soaked completely).
##
## Drawn as a 2D overlay projected from 3D, so the text is the same readable size at
## every zoom. Hidden while its unit's floor is cut away ([FloorCutaway]); timing
## follows battle speed and fast-forward ([method GameSettings.anim_duration_scale]).
## Several hits on one unit stack upward instead of overlapping.

## Base lifetime (seconds at 1x battle speed) and rise distance (px).
const LIFETIME := 1.25
const RISE_PX := 46.0
## Vertical gap between stacked popups on the same unit.
const STACK_PX := 34.0
## World-space height above the unit's origin when it has no HealthBar to anchor to.
const FALLBACK_HEAD := 2.4
## Extra lift above the HealthBar.
const ABOVE_BAR := 0.55

const COL_DAMAGE := Color("fff6e6")
const COL_ENV_DAMAGE := Color("ff9a7a")
const COL_HEAL := Color("7ff09a")
const COL_MISS := Color("b8bccb")
const COL_BLOCK := Color("8cc8ff")
const COL_OUTLINE := Color(0.05, 0.04, 0.08, 0.95)

var pairer := CombatTextPairer.new()
## Live popups: Array of { node, unit, anchor, floor, t, life, slot, crit }.
var _popups: Array = []
var _flush_queued: bool = false
## unit -> Callable connected to its UnitStats.health_changed.
var _connected: Dictionary = {}
var _board = null
## Screen rects already placed this frame (declutter).
var _placed: Array[Rect2] = []


func _ready() -> void:
	name = "FloatingCombatText"
	layer = 0  # above the 3D world, below the HUD's "UI" layer (1) and overlays
	add_to_group("floating_combat_text")
	var bus := get_node_or_null("/root/GameEvents")
	if bus != null:
		if bus.has_signal(CombatText.SIGNAL):
			bus.connect(CombatText.SIGNAL, _on_annotated)
		if bus.has_signal(&"unit_spawned"):
			bus.unit_spawned.connect(func(u, _rt): track_unit(u))
	var services := get_node_or_null("/root/CombatServices")
	if services != null and services.has_signal(&"board_ready"):
		services.board_ready.connect(_on_board_ready)
	if services != null and services.has_method("board") and services.board() != null:
		_on_board_ready()


func _on_board_ready() -> void:
	var services := get_node_or_null("/root/CombatServices")
	_board = services.board() if services != null and services.has_method("board") else null
	if _board != null and _board.has_method("all_units"):
		for u in _board.all_units():
			track_unit(u)


## Start listening to [param unit]'s HP (idempotent).
func track_unit(unit) -> void:
	if unit == null or not is_instance_valid(unit) or _connected.has(unit):
		return
	var stats = unit.get("unit_stats") if unit is Object else null
	if stats == null or not stats.has_signal(&"health_changed"):
		return
	var cb := _on_health_changed.bind(unit)
	stats.health_changed.connect(cb)
	_connected[unit] = cb
	if unit is Node:
		(unit as Node).tree_exiting.connect(func(): _connected.erase(unit), CONNECT_ONE_SHOT)


# --- Events -------------------------------------------------------------------------

func _on_annotated(unit, info) -> void:
	if unit == null or not (info is Dictionary):
		return
	track_unit(unit)
	pairer.annotate(unit, info, _shield_of(unit))
	_queue_flush()


func _on_health_changed(old_hp: int, new_hp: int, unit) -> void:
	var entry := pairer.on_health_changed(unit, old_hp, new_hp, _shield_of(unit))
	if not entry.is_empty():
		show_entry(entry)


func _queue_flush() -> void:
	if _flush_queued:
		return
	_flush_queued = true
	call_deferred("_flush")


func _flush() -> void:
	_flush_queued = false
	for entry in pairer.flush(_shield_of):
		show_entry(entry)


func _shield_of(unit) -> int:
	if unit != null and is_instance_valid(unit) and unit.has_method("get_shield"):
		return int(unit.get_shield())
	return 0


# --- Popups -------------------------------------------------------------------------

## Build and launch the popup for one pairer entry.
func show_entry(entry: Dictionary) -> void:
	var unit = entry.get("unit")
	if unit == null or not is_instance_valid(unit) or not (unit is Node3D):
		return
	var box := _build_popup(entry)
	if box == null:
		return
	add_child(box)
	var crit := bool(entry.get("crit", false))
	var slot := _free_slot(unit)
	_popups.append({
		"node": box, "unit": unit, "anchor": _anchor_of(unit), "floor": _floor_of(unit),
		"t": 0.0, "life": LIFETIME * (1.2 if crit else 1.0), "slot": slot, "crit": crit,
	})
	_place(_popups[-1], 0.0)


func _process(delta: float) -> void:
	if _popups.is_empty():
		return
	var speed := _speed_factor()
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	_placed.clear()
	for i in range(_popups.size() - 1, -1, -1):
		var p: Dictionary = _popups[i]
		p["t"] = float(p["t"]) + delta * speed
		var node: Control = p["node"]
		if not is_instance_valid(node) or float(p["t"]) >= float(p["life"]):
			if is_instance_valid(node):
				node.queue_free()
			_popups.remove_at(i)
			continue
		var unit = p["unit"]
		if unit != null and is_instance_valid(unit):
			p["anchor"] = _anchor_of(unit)  # follow a unit that is still moving
	# Place oldest first so the declutter pushes NEWER text up, never the reverse.
	for p in _popups:
		_place(p, float(p["t"]) / float(p["life"]), cam)


func _place(p: Dictionary, k: float, cam: Camera3D = null) -> void:
	var node: Control = p["node"]
	if cam == null:
		cam = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null or cam.is_position_behind(p["anchor"]) or _floor_hidden(int(p["floor"])):
		node.visible = false
		return
	node.visible = true
	var screen: Vector2 = cam.unproject_position(p["anchor"])
	# Ease-out rise; stacked popups sit one row higher per slot.
	var rise := RISE_PX * (1.0 - pow(1.0 - k, 3.0))
	screen.y -= rise + STACK_PX * float(p["slot"])
	node.reset_size()
	node.pivot_offset = node.size * 0.5
	node.position = screen - Vector2(node.size.x * 0.5, node.size.y)
	# Declutter: neighbouring units' text must not overlap -- nudge this popup up
	# above anything already placed this frame that it would cover.
	var rect := Rect2(node.position, node.size).grow(-2.0)
	var moved := true
	var guard := 0
	while moved and guard < 12:
		moved = false
		guard += 1
		for other in _placed:
			if rect.intersects(other):
				rect.position.y = other.position.y - rect.size.y - 3.0
				moved = true
	node.position.y = rect.position.y - 2.0
	_placed.append(rect)
	# Punch-in: crits land big and settle; everything pops slightly.
	var punch := 0.0
	if k < 0.18:
		punch = (1.0 - k / 0.18) * (0.75 if bool(p["crit"]) else 0.35)
	node.scale = Vector2.ONE * (1.0 + punch)
	# Fade the last third.
	node.modulate.a = 1.0 if k < 0.66 else clampf((1.0 - k) / 0.34, 0.0, 1.0)


func _free_slot(unit) -> int:
	var used := {}
	for p in _popups:
		if p["unit"] == unit and float(p["t"]) < float(p["life"]) * 0.8:
			used[int(p["slot"])] = true
	var s := 0
	while used.has(s):
		s += 1
	return s


## Seconds of popup time per real second: faster battle speed / fast-forward = faster.
func _speed_factor() -> float:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("anim_duration_scale"):
		var scale := float(gs.anim_duration_scale())
		if scale <= 0.0:
			return 2.0  # animations off: still show the number, briefly
		return clampf(1.0 / scale, 0.5, 4.0)
	return 1.0


func _anchor_of(unit: Node3D) -> Vector3:
	for c in unit.get_children():
		if c is HealthBar and (c as Node3D).is_inside_tree():
			return (c as Node3D).global_position + Vector3(0, ABOVE_BAR, 0)
	return unit.global_position + Vector3(0, FALLBACK_HEAD, 0)


func _floor_of(unit) -> int:
	if _board == null:
		var services := get_node_or_null("/root/CombatServices")
		_board = services.board() if services != null and services.has_method("board") else null
	if _board != null and _board.has_method("cell_of"):
		return int(_board.cell_of(unit).z)
	return 0


## True while [param f] is cut away by the multi-floor cutaway (text hidden with it).
func _floor_hidden(f: int) -> bool:
	if f <= 0 or not is_inside_tree():
		return false
	var cut := get_tree().get_first_node_in_group("floor_cutaway")
	return cut != null and cut.has_method("is_floor_cut") and bool(cut.is_floor_cut(f))


# --- Popup construction ---------------------------------------------------------------

## The label texts one entry shows: { main, main_color, main_size, tag, tag_color,
## tag_font ("display" / "heading" / "body"), source, source_color }. Static so the
## wording is unit-testable without a scene.
static func texts_for(entry: Dictionary) -> Dictionary:
	var out := {
		"main": "", "main_color": COL_DAMAGE, "main_size": 30,
		"tag": "", "tag_color": MenuTheme.GOLD_LITE, "tag_font": "heading",
		"source": String(entry.get("source", "")), "source_color": _source_color(entry),
	}
	var amount := int(entry.get("amount", 0))
	var src_kind := StringName(entry.get("source_kind", CombatText.SRC_ATTACK))
	var environmental: bool = src_kind != CombatText.SRC_ATTACK and src_kind != &""
	match StringName(entry.get("kind", &"")):
		CombatTextPairer.ENTRY_HEAL:
			out["main"] = "+%d" % amount
			out["main_color"] = COL_HEAL
			out["main_size"] = 28
		CombatTextPairer.ENTRY_MISS:
			out["main"] = "MISS"
			out["main_color"] = COL_MISS
			out["main_size"] = 24
		CombatTextPairer.ENTRY_IMMUNE:
			out["main"] = "IMMUNE"
			out["main_color"] = COL_BLOCK
			out["main_size"] = 22
		CombatTextPairer.ENTRY_BLOCKED:
			out["main"] = "Blocked %d" % int(entry.get("blocked", 0))
			out["main_color"] = COL_BLOCK
			out["main_size"] = 22
		_:
			out["main"] = str(amount)
			out["main_color"] = COL_ENV_DAMAGE if environmental else COL_DAMAGE
			out["main_size"] = 26 if environmental else 32
			if bool(entry.get("crit", false)):
				out["main_color"] = ConquestTheme.CRIT_COLOR
				out["main_size"] = 42
				out["tag"] = "CRIT!"
				out["tag_color"] = ConquestTheme.CRIT_COLOR
				out["tag_font"] = "display"
			if int(entry.get("blocked", 0)) > 0:
				out["source"] = ("%s  " % out["source"] if out["source"] != "" else "") \
					+ "Blocked %d" % int(entry["blocked"])
	var eff := float(entry.get("effectiveness", 1.0))
	if out["tag"] == "" and StringName(entry.get("kind", &"")) == CombatTextPairer.ENTRY_DAMAGE:
		if eff > 1.01:
			out["tag"] = "▲ Effective"
			out["tag_color"] = Color("ffcf6b")
			out["tag_font"] = "body"
		elif eff < 0.99:
			out["tag"] = "▼ Resisted"
			out["tag_color"] = Color("a9b4d6")
			out["tag_font"] = "body"
	elif out["tag"] == "CRIT!" and out["source"] == "":
		# The tag slot holds CRIT!, so a crit's matchup rides the line below.
		if eff > 1.01:
			out["source"] = "▲ Effective"
			out["source_color"] = Color("ffcf6b")
		elif eff < 0.99:
			out["source"] = "▼ Resisted"
			out["source_color"] = Color("a9b4d6")
	return out


static func _source_color(entry: Dictionary) -> Color:
	if entry.get("color") is Color:
		return entry["color"]
	var id := StringName(entry.get("source_id", &""))
	match StringName(entry.get("source_kind", &"")):
		CombatText.SRC_TILE:
			return TileEffectVisuals.info_for_id(id).get("color", MenuTheme.GOLD)
		CombatText.SRC_STATUS:
			return StatusVisuals.info_for_id(id).get("color", MenuTheme.GOLD)
		CombatText.SRC_HAZARD:
			return Color("7fbf5a")
		CombatText.SRC_LIFESTEAL:
			return Color("d0607a")
	return MenuTheme.GOLD_LITE


func _build_popup(entry: Dictionary) -> Control:
	var t := texts_for(entry)
	if String(t["main"]) == "":
		return null
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if String(t["tag"]) != "":
		var font: Font = MenuTheme.display_font() if t["tag_font"] == "display" \
			else (MenuTheme.heading_font() if t["tag_font"] == "heading" else MenuTheme.bold_font())
		box.add_child(_label(String(t["tag"]), t["tag_color"], 20 if t["tag_font"] == "display" else 15, font, 6))
	var main_font: Font = MenuTheme.bold_font(0.8)
	if StringName(entry.get("kind", &"")) in [CombatTextPairer.ENTRY_MISS, CombatTextPairer.ENTRY_IMMUNE]:
		main_font = MenuTheme.heading_font(2)
	box.add_child(_label(String(t["main"]), t["main_color"], int(t["main_size"]), main_font, 9))
	if String(t["source"]) != "":
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var src_col: Color = t["source_color"]
		if StringName(entry.get("weather_fx", &"")) != &"":
			var icon := WeatherIcon.new(StringName(entry["weather_fx"]), src_col, 16.0)
			row.add_child(icon)
		elif String(entry.get("source", "")) != "":
			var gem := GroveGem.new()
			gem.color = src_col
			gem.custom_minimum_size = Vector2(11, 11)
			gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gem)
		row.add_child(_label(String(t["source"]), src_col.lerp(Color.WHITE, 0.35), 15, MenuTheme.bold_font(), 5))
		box.add_child(row)
	return box


static func _label(text: String, color: Color, size: int, font: Font, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", COL_OUTLINE)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l
