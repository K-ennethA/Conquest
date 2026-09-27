extends PanelContainer

class_name BattleLog

## Scrolling combat log (top-left of the HUD, collapsible). Records what happens each turn --
## moves, attacks, damage, heals, spawns, deaths -- off the GameEvents bus, so the
## player can read a running account ("Petalfang used Thorn Spit", "Torvald hit
## Blightcap for 20"). Purely additive and read-only: it never mutates game state.
##
## Mounted by UILayoutManager as a direct child of the full-screen HUD root, so its
## bottom-left anchors resolve against the whole window (no top_level needed).

const MAX_LINES: int = 60
const PANEL_WIDTH: float = 360.0
const PANEL_HEIGHT: float = 190.0
## Width of the collapsed header chip.
const COLLAPSED_WIDTH: float = 250.0
const MARGIN: float = 16.0
## The log lives in the TOP-LEFT corner, not the bottom-left. The bottom-left corner is
## already shared by the TerrainInfoPanel (hover) and TurnSystemIndicator, and the log
## kept overlapping / rendering behind the terrain card there (different CanvasLayers, so
## raising it in-corner never reliably won the draw order). The top-left corner has no
## persistent panel -- only the CombatForecastPanel appears there, and only briefly while
## aiming a move -- so parking the log here keeps it clear of the inspection cluster. It
## grows DOWNWARD from TOP_MARGIN.
const TOP_MARGIN: float = 12.0
## Height when collapsed to just its clickable header (default). Click the header
## to expand to PANEL_HEIGHT; click again to collapse. Starts collapsed so the log
## stays out of the way (a tiny header) until the player wants to read it.
const COLLAPSED_HEIGHT: float = 38.0

# Side tints (bbcode): the local/ally side reads cool, the AI/enemy side warm-red, so
# you can scan who did what at a glance. Neutral events use cream.
const ALLY_COLOR: String = "#8cc4ff"
const ENEMY_COLOR: String = "#ff8f80"
const NEUTRAL_COLOR: String = "#f5eedc"
const DIM_COLOR: String = "#9ba5c8"

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
## Annotation context waiting for the matching damage_dealt / unit_healed line.
var _last_crit: Dictionary = {}
var _heal_source: Dictionary = {}


func _ready() -> void:
	name = "BattleLog"
	add_to_group("battle_log")
	add_to_group("hud_top_left")
	_build_ui()
	# TOP-left corner (see TOP_MARGIN note): out of the contested bottom-left inspection
	# cluster, so it no longer overlaps / hides behind the terrain card. Grows downward.
	# Click-through except the header, which captures clicks to toggle expand/collapse.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = MARGIN
	offset_right = MARGIN + PANEL_WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()
	_connect_events()


## Resize to header-only or full, and show/hide the scrollback, per _expanded.
## Top-anchored: grows downward from TOP_MARGIN.
func _apply_layout() -> void:
	var h: float = PANEL_HEIGHT if _expanded else COLLAPSED_HEIGHT
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN + h
	# Collapsed, the log is a compact chip so it never runs under the phase banner.
	offset_right = MARGIN + (PANEL_WIDTH if _expanded else COLLAPSED_WIDTH)
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
	# Navy HUD plate (same tokens as every other panel), a touch more translucent.
	var box := ConquestTheme.chip_box(ConquestTheme.BORDER_SOFT, 0.86)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 6
	add_theme_stylebox_override("panel", box)
	ConquestTheme.keep_style(self)

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
	_header.add_theme_font_override("font", MenuTheme.heading_font(2))
	_header.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
	_header.add_theme_color_override("font_color", ConquestTheme.GOLD)
	_header.add_theme_color_override("font_hover_color", ConquestTheme.GOLD_LITE)
	_header.add_theme_color_override("font_pressed_color", ConquestTheme.GOLD_LITE)
	_header.add_theme_color_override("font_focus_color", ConquestTheme.GOLD_LITE)
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
	_log.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, PANEL_HEIGHT - 46.0)
	_log.add_theme_font_size_override("normal_font_size", ConquestTheme.FS_SMALL)
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
	_safe(bus, &"combat_text_annotated", _on_combat_text_annotated)


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
	# A tile / status tick resolves with the unit as its own "caster"; those are logged
	# with their SOURCE by _on_combat_text_annotated instead ("Barkling burned for 15").
	if attacker != null and attacker == defender:
		_last_crit.erase(defender)
		return
	var dmg: int = int(damage) if damage != null else 0
	var crit: bool = bool(_last_crit.get(defender, false))
	_last_crit.erase(defender)
	_append("%s hit %s for %d%s" % [_named(attacker), _named(defender), dmg,
		" (critical!)" if crit else ""], _tint(attacker))


func _on_unit_healed(unit = null, amount = null) -> void:
	var amt: int = int(amount) if amount != null else 0
	var src: String = String(_heal_source.get(unit, ""))
	_heal_source.erase(unit)
	if amt <= 0:
		return
	if src != "":
		_append("%s restored %d from %s" % [_named(unit), amt, src], ALLY_COLOR)
	else:
		_append("%s healed %d" % [_named(unit), amt], ALLY_COLOR)


## Context for the next damage / heal line: crits, misses, and every NON-attack damage
## source (tiles, status ticks, weather, hazards), which never raise damage_dealt with
## a real attacker. Emitted just before the HP change (see CombatText).
func _on_combat_text_annotated(unit = null, info = null) -> void:
	if not (info is Dictionary):
		return
	var kind := StringName(info.get("kind", &""))
	var src_kind := StringName(info.get("source_kind", CombatText.SRC_ATTACK))
	var amount: int = int(info.get("amount", 0))
	var source := source_text(info)
	match kind:
		CombatText.KIND_MISS:
			var attacker = info.get("attacker")
			if src_kind == CombatText.SRC_ATTACK and attacker != null and attacker != unit:
				_append("%s missed %s" % [_named(attacker), _named(unit)], DIM_COLOR)
			elif source != "":
				_append("%s avoided %s" % [_named(unit), source], DIM_COLOR)
		CombatText.KIND_NEGATED:
			_append("%s is unharmed (immune)" % _named(unit), DIM_COLOR)
		CombatText.KIND_HEAL:
			if src_kind == CombatText.SRC_LIFESTEAL:
				# Lifesteal heals the caster directly (no unit_healed): log it here.
				_append("%s drained %d HP" % [_named(unit), amount], _tint(unit))
			else:
				_heal_source[unit] = source  # "" clears a stale source
		CombatText.KIND_DAMAGE:
			if src_kind == CombatText.SRC_ATTACK:
				_last_crit[unit] = bool(info.get("crit", false))
			elif src_kind in [CombatText.SRC_TILE, CombatText.SRC_STATUS,
					CombatText.SRC_WEATHER, CombatText.SRC_HAZARD]:
				_append(damage_line(_named(unit), amount, info), _tint(unit))


## "Vineweave took 7 from Scouring Sand (Desert Storm)", "Barkling burned for 15".
## Static so the wording is unit-testable.
static func damage_line(who: String, amount: int, info: Dictionary) -> String:
	var id := StringName(info.get("source_id", &""))
	if id in [&"fire", &"scorching_vent", &"burn"]:
		return "%s burned for %d" % [who, amount]
	if StringName(info.get("source_kind", &"")) == CombatText.SRC_HAZARD:
		return "%s was struck by %s for %d" % [who, source_text(info), amount]
	return "%s took %d from %s" % [who, amount, source_text(info)]


## The player-facing source name, with the weather in brackets for a weather rule.
static func source_text(info: Dictionary) -> String:
	var src := String(info.get("source", ""))
	var weather := String(info.get("weather", ""))
	if weather != "" and src != "" and src != weather:
		return "%s (%s)" % [src, weather]
	return src if src != "" else weather


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
