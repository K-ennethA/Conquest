extends PanelContainer

class_name BattleLog

## Scrolling combat log (bottom-left of the HUD). Records what happens each turn --
## moves, attacks, damage, heals, spawns, deaths -- off the GameEvents bus, so the
## player can read a running account ("Petalfang used Thorn Spit", "Torvald hit
## Blightcap for 20"). Purely additive and read-only: it never mutates game state.
##
## Mounted by UILayoutManager as a direct child of the full-screen HUD root, so its
## bottom-left anchors resolve against the whole window (no top_level needed).

const MAX_LINES: int = 60
const PANEL_WIDTH: float = 330.0
const PANEL_HEIGHT: float = 158.0
const MARGIN: float = 12.0
## Vertical band kept clear at the bottom-LEFT for the unit/terrain inspection cluster
## that shares this corner: TurnSystemIndicator (x20-320, y-120..-20 => bottom 100px) and
## the bottom-anchored TerrainInfoPanel/UnitHoverPanel readouts. The log is raised to sit
## ABOVE that band so it never overlaps them (it used to sit ~12px off the bottom, right
## on top of the turn indicator). 130 clears the 120px-tall turn indicator plus a gap.
const BOTTOM_RESERVE: float = 130.0
## Height when collapsed to just its clickable header (default). Click the header
## to expand to PANEL_HEIGHT; click again to collapse. Starts collapsed so the log
## stays out of the way until the player wants to read it.
const COLLAPSED_HEIGHT: float = 30.0

# Side tints (bbcode): the local/ally side reads cool, the AI/enemy side warm-red, so
# you can scan who did what at a glance. Neutral events use cream.
const ALLY_COLOR: String = "#cfe8ff"
const ENEMY_COLOR: String = "#ffb3a0"
const NEUTRAL_COLOR: String = "#efe2c4"
const DIM_COLOR: String = "#b9a97f"

var _log: RichTextLabel
var _lines: Array[String] = []

## Collapsed (header-only) until the player clicks the header to expand.
var _expanded: bool = false
## Clickable header that toggles expansion. It is the ONE part of the panel that
## captures the mouse; everything else stays click-through over the board.
var _header: Button
## Lines logged while collapsed, shown as a "(N)" badge on the header so the player
## knows something happened without expanding. Reset when expanded.
var _unread: int = 0


func _ready() -> void:
	name = "BattleLog"
	_build_ui()
	# Bottom-left, but RAISED above the inspection cluster that shares this corner, and
	# click-through so it never blocks the board underneath (only the header captures
	# clicks, to toggle expand/collapse). Still bottom-anchored, so the whole left stack
	# stays pinned to the window bottom and keeps its gaps as the window grows.
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = MARGIN
	offset_right = MARGIN + PANEL_WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()
	_connect_events()


## Resize to header-only or full, and show/hide the scrollback, per _expanded.
func _apply_layout() -> void:
	var h: float = PANEL_HEIGHT if _expanded else COLLAPSED_HEIGHT
	offset_top = -(BOTTOM_RESERVE + h)
	offset_bottom = -BOTTOM_RESERVE
	if _log:
		_log.visible = _expanded
	if _header:
		_header.text = _header_text()


func _header_text() -> String:
	if _expanded:
		return "BATTLE LOG  ▾"  # down triangle = open
	if _unread > 0:
		return "BATTLE LOG  ▸  (%d)" % _unread  # right triangle + unread badge
	return "BATTLE LOG  ▸"


func _toggle_expanded() -> void:
	_expanded = not _expanded
	if _expanded:
		_unread = 0
	_apply_layout()


func _build_ui() -> void:
	# Dark, semi-transparent plate so log text reads over the 3D board.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.075, 0.05, 0.72)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(8)
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.border_color = Color(0.85, 0.62, 0.30, 0.5)  # faint amber edge
	add_theme_stylebox_override("panel", box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	# Clickable header (the only mouse-capturing part) toggles expand/collapse.
	_header = Button.new()
	_header.flat = true
	_header.text = "BATTLE LOG  ▸"
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.focus_mode = Control.FOCUS_NONE
	_header.mouse_filter = Control.MOUSE_FILTER_STOP  # capture clicks even though the panel is IGNORE
	_header.add_theme_font_size_override("font_size", 12)
	_header.add_theme_color_override("font_color", Color(0.85, 0.62, 0.30))
	_header.add_theme_color_override("font_hover_color", Color(1.0, 0.82, 0.45))
	# Flat button still draws hover/pressed plates; blank them so it reads as a label.
	var clear_sb := StyleBoxEmpty.new()
	_header.add_theme_stylebox_override("normal", clear_sb)
	_header.add_theme_stylebox_override("hover", clear_sb)
	_header.add_theme_stylebox_override("pressed", clear_sb)
	_header.add_theme_stylebox_override("focus", clear_sb)
	_header.pressed.connect(_toggle_expanded)
	vb.add_child(_header)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.scroll_following = true   # keep the newest line in view
	_log.fit_content = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(PANEL_WIDTH - 16.0, PANEL_HEIGHT - 34.0)
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_log)


# --- Event wiring -----------------------------------------------------------

func _connect_events() -> void:
	var bus := get_node_or_null("/root/GameEvents")
	if bus == null:
		return
	_safe(bus, &"unit_moved", _on_unit_moved)
	_safe(bus, &"move_performed", _on_move_performed)
	_safe(bus, &"damage_dealt", _on_damage_dealt)
	_safe(bus, &"unit_healed", _on_unit_healed)
	_safe(bus, &"unit_spawned", _on_unit_spawned)
	_safe(bus, &"unit_eliminated", _on_unit_eliminated)


func _safe(obj: Object, sig: StringName, cb: Callable) -> void:
	if obj != null and obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)


# --- Handlers (all null-safe; freed units degrade to a generic name) ---------

func _on_unit_moved(unit = null, _from = null, to = null) -> void:
	if to is Vector3:
		var t: Vector3 = to
		_append("%s moved to (%d, %d)" % [_named(unit), int(round(t.x)), int(round(t.z))], _tint(unit))
	else:
		_append("%s moved" % _named(unit), _tint(unit))


func _on_move_performed(caster = null, move = null) -> void:
	var mv: String = "a move"
	if move != null and "display_name" in move and String(move.display_name) != "":
		mv = String(move.display_name)
	_append("%s used %s" % [_named(caster), mv], _tint(caster))


func _on_damage_dealt(attacker = null, defender = null, damage = null) -> void:
	var dmg: int = int(damage) if damage != null else 0
	_append("%s hit %s for %d" % [_named(attacker), _named(defender), dmg], _tint(attacker))


func _on_unit_healed(unit = null, amount = null) -> void:
	var amt: int = int(amount) if amount != null else 0
	if amt <= 0:
		return
	_append("%s healed %d" % [_named(unit), amt], ALLY_COLOR)


func _on_unit_spawned(unit = null, runtime = null) -> void:
	# Only announce runtime waves (reinforcements / endless), not the load-time flood.
	if runtime != true:
		return
	_append("%s appeared" % _named(unit), _tint(unit))


func _on_unit_eliminated(unit = null, _eliminator = null) -> void:
	_append("%s was defeated" % _named(unit), DIM_COLOR)


# --- Helpers ----------------------------------------------------------------

## Append one bbcode-tinted line and cap the scrollback.
func _append(text: String, color: String) -> void:
	if _log == null:
		return
	_lines.append("[color=%s]%s[/color]" % [color, text])
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_log.text = "\n".join(_lines)
	# Collapsed: don't pop open, just badge the header so the player sees activity.
	if not _expanded:
		_unread += 1
		if _header:
			_header.text = _header_text()


func _named(unit) -> String:
	if unit != null and is_instance_valid(unit) and unit.has_method("get_display_name"):
		return String(unit.get_display_name())
	return "A unit"


## bbcode colour for a unit by its side: enemy (AI) warm-red, ally cool, else neutral.
func _tint(unit) -> String:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("get_owner_player"):
		return NEUTRAL_COLOR
	var owner = unit.get_owner_player()
	if owner != null and "is_ai" in owner:
		return ENEMY_COLOR if bool(owner.is_ai) else ALLY_COLOR
	return NEUTRAL_COLOR
