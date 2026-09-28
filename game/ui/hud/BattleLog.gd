extends PanelContainer

class_name BattleLog

## Scrolling combat log (top-left of the HUD, collapsible). Records what happens each turn --
## moves, attacks, damage, heals, spawns, deaths -- off the GameEvents bus, so the
## player can read a running account ("Petalfang used Thorn Spit", "Torvald hit
## Blightcap for 20"). Purely additive and read-only: it never mutates game state.
##
## Mounted by UILayoutManager as the FIRST child of the HUD's LeftSidebar VBox, so it
## owns the top row of the left column and the UnitInfoPanel stacks underneath it with
## the column's 10px separation -- the two can no longer overlap (the reported "BATTLE LOG
## chip sits on top of the Unit Information title" bug). It still works as a free-floating
## top-left panel when mounted under a non-Container parent (tests, other scenes).

const MAX_LINES: int = 60
## Width when FREE-FLOATING (docked in the HUD's left column, the column owns the width).
const PANEL_WIDTH: float = 360.0
## Full expanded height. Pinned by the left-column budget (UILayoutManager
## _rebudget_left_column / test_turn_banner_and_hud_budget): 81 column top + 158 + 10
## separation puts the unit card at y249, clear of the terrain card's band at 720p.
const PANEL_HEIGHT: float = 158.0
## Width of the collapsed header chip when free-floating, so it never runs under the
## phase banner at the top-centre.
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
## 38px: the Cinzel header at FS_CAPTION plus the plate's 4/6px content margins.
const COLLAPSED_HEIGHT: float = 38.0
## Vertical space the header + panel margins + the VBox separation take, i.e. everything
## that is NOT scrollback.
const HEADER_ALLOWANCE: float = 42.0
## Shortest an EXPANDED log is still worth the rows it costs the unit card (header + ~5
## lines of scrollback). While a unit is selected the left column can only spare ~95px
## (463 usable - the card's 358px of fixed rows - 10px separation), which is under this, so
## the log shows its collapsed chip rather than pushing the card's ability / effect lists
## to zero. With no unit selected the whole column is the log's and it expands in full.
## Same idiom as the existing auto-collapse while a move is being aimed.
const MIN_EXPANDED_HEIGHT: float = 120.0

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
## Units whose NON-attack damage was just logged WITH its source by
## _on_combat_text_annotated, so the self-attributed damage_dealt that follows is not
## logged a second time. A self-hit nobody annotated still gets a plain line.
var _sourced_damage: Dictionary = {}

## True while the player is aiming a move. The CombatForecastPanel shows in THIS
## same top-left corner (~y70) while aiming, which the expanded log (grows to ~166px)
## would overlap. So we auto-collapse the log for the duration of the aim and restore
## the player's prior expand state when it ends. Aim-start fires repeatedly (per
## reticle move); only the first entry saves state, so continuous aiming never flickers.
var _aiming: bool = false
var _expanded_before_aim: bool = false

## True when this log is laid out BY a Container (the HUD's LeftSidebar VBox), in which
## case the container owns position/width and the log declares its height through
## custom_minimum_size. False when it is a free-floating top-left panel driving its own
## anchors/offsets, which is how it behaves outside GameUILayout.
var _docked: bool = false

## Tallest this log may render, handed down by UILayoutManager from the left column's
## budget (see UILayoutManager._rebudget_left_column). INF until somebody budgets it, so
## a standalone log keeps its authored PANEL_HEIGHT.
var _height_budget: float = INF


func _ready() -> void:
	name = "BattleLog"
	add_to_group("battle_log")
	# The combat forecast stacks below every "hud_top_left" panel (CombatForecastPanel).
	add_to_group("hud_top_left")
	_docked = get_parent() is Container
	_build_ui()
	if _docked:
		# The column owns x and width; only the height is ours to declare.
		size_flags_horizontal = Control.SIZE_FILL
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		# TOP-left corner (see TOP_MARGIN note): out of the contested bottom-left
		# inspection cluster. Grows downward.
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = MARGIN
		offset_right = MARGIN + PANEL_WIDTH
	# Click-through except the header, which captures clicks to toggle expand/collapse.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()
	_connect_events()


## The height an [param expanded] log actually renders at inside [param budget].
##
## Pure, and the whole left-column contract in one place: a collapsed log is always its
## header chip (COLLAPSED_HEIGHT); an expanded one takes PANEL_HEIGHT unless the column
## cannot spare it, and anything under MIN_EXPANDED_HEIGHT is not a readable log -- it
## falls back to the chip rather than stealing rows from the UnitInfoPanel underneath.
static func resolved_height(expanded: bool, budget: float) -> float:
	if not expanded:
		return COLLAPSED_HEIGHT
	var allowed: float = minf(PANEL_HEIGHT, budget)
	return allowed if allowed >= MIN_EXPANDED_HEIGHT else COLLAPSED_HEIGHT


## Tell the log how much vertical room the left column can spare for it. Re-applies the
## layout immediately, so expanding into a column that has no room silently keeps the chip.
func set_height_budget(px: float) -> void:
	var next: float = maxf(COLLAPSED_HEIGHT, px)
	if is_equal_approx(next, _height_budget):
		return
	_height_budget = next
	_apply_layout()


## True when the scrollback is actually on screen (expanded AND the column had room).
func is_showing_scrollback() -> bool:
	return resolved_height(_expanded, _height_budget) > COLLAPSED_HEIGHT


## Resize to header-only or full, and show/hide the scrollback, per _expanded and the
## column budget. Docked: declares a minimum height to the column. Floating: grows
## downward from TOP_MARGIN.
func _apply_layout() -> void:
	var h: float = resolved_height(_expanded, _height_budget)
	var showing: bool = h > COLLAPSED_HEIGHT
	if _docked:
		custom_minimum_size.y = h
	else:
		offset_top = TOP_MARGIN
		offset_bottom = TOP_MARGIN + h
		# Collapsed, the floating log is a compact chip so it never runs under the phase
		# banner.
		offset_right = MARGIN + (PANEL_WIDTH if showing else COLLAPSED_WIDTH)
	if _log:
		_log.visible = showing
		# The scrollback is the elastic part; the header + panel margins are not.
		_log.custom_minimum_size.y = maxf(0.0, h - HEADER_ALLOWANCE) if showing else 0.0
	if _header:
		_header.text = _header_text()


func _header_text() -> String:
	if is_showing_scrollback():
		return "BATTLE LOG  ▾"  # down triangle = open
	if _unread > 0:
		return "BATTLE LOG  ▸  (%d)" % _unread  # right triangle + unread badge
	return "BATTLE LOG  ▸"


func _toggle_expanded() -> void:
	_expanded = not _expanded
	# If the player toggles mid-aim, honour that as their new intent so the
	# aim-ended restore doesn't undo it.
	if _aiming:
		_expanded_before_aim = _expanded
	_apply_layout()
	# Only a log that actually came on screen has been "read" -- a budget-denied expand
	# must keep its unread badge.
	if is_showing_scrollback():
		_unread = 0
		if _header:
			_header.text = _header_text()


# --- Targeting-driven auto-collapse (keeps the log clear of the forecast) -----

func _on_aim_started(_cells = null) -> void:
	"""Aiming began (attack range / AoE preview). Collapse the log so it doesn't
	overlap the CombatForecastPanel in this corner. Re-fires per reticle move; only
	the first entry saves the pre-aim state, so there is no collapse/expand flicker."""
	if _aiming:
		return
	_aiming = true
	_expanded_before_aim = _expanded
	if _expanded:
		_expanded = false
		_apply_layout()


func _on_aim_ended() -> void:
	"""Aiming ended (move resolved or cancelled). Restore the pre-aim expand state."""
	if not _aiming:
		return
	_aiming = false
	if _expanded_before_aim and not _expanded:
		_expanded = true
		_apply_layout()


func _build_ui() -> void:
	# Dark, semi-transparent plate so log text reads over the 3D board:
	# the navy HUD plate (same tokens as every other panel), a touch more translucent.
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
	_log.size_flags_horizontal = Control.SIZE_FILL
	# Docked, the COLUMN sets the width -- declaring one here would widen the whole left
	# column and eat board. Floating, PANEL_WIDTH less the plate's 12px side margins.
	# Height is set by _apply_layout.
	_log.custom_minimum_size = Vector2(0.0 if _docked else PANEL_WIDTH - 24.0, 0.0)
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
	# Crits, misses and non-attack damage sources (tiles, statuses, weather, hazards).
	_safe(bus, &"combat_text_annotated", _on_combat_text_annotated)
	# Auto-collapse while a move is being aimed (forecast shares this corner).
	_safe(bus, &"attack_range_calculated", _on_aim_started)
	_safe(bus, &"aoe_preview_calculated", _on_aim_started)
	_safe(bus, &"targeting_cleared", _on_aim_ended)


func _safe(obj: Object, sig: StringName, cb: Callable) -> void:
	if obj != null and obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)


# --- Handlers (all null-safe; freed units degrade to a generic name) ---------

func _on_unit_moved(unit = null, _from = null, to = null) -> void:
	# FOG: a move line is a POSITION. There is no masked wording that survives -- "??? moved
	# to (7, 3)" hands over the very coordinate the mist was hiding -- so the line goes.
	if _unseen(unit):
		return
	if to is Vector3:
		var t: Vector3 = to
		_append("%s moved to (%d, %d)" % [_named(unit), int(round(t.x)), int(round(t.z))], _tint(unit))
	else:
		_append("%s moved" % _named(unit), _tint(unit))


func _on_move_performed(caster = null, move = null) -> void:
	# FOG: naming the MOVE names the unit ("used Forest Barrage" is Eldroot, in this roster).
	# A cast by someone you cannot see is not reported at all; if it hurt one of yours, the
	# damage line below still lands.
	if _unseen(caster):
		return
	var mv: String = "a move"
	if move != null and "display_name" in move and String(move.display_name) != "":
		mv = String(move.display_name)
	_append("%s used %s" % [_named(caster), mv], _tint(caster))


func _on_damage_dealt(attacker = null, defender = null, damage = null) -> void:
	var dmg: int = int(damage) if damage != null else 0
	# A tile / status tick resolves with the unit as its own "caster"; those are logged
	# with their SOURCE by _on_combat_text_annotated instead ("Barkling burned for 15").
	# A self-hit nobody annotated still gets a plain line rather than "X hit X".
	if attacker != null and attacker == defender:
		_last_crit.erase(defender)
		if _sourced_damage.has(defender):
			_sourced_damage.erase(defender)
			return
		if _unseen(defender) or dmg <= 0:
			return
		_append("%s took %d damage" % [_named(defender), dmg], _tint(defender))
		return
	# A sourced line that was raised with a real attacker (e.g. a hazard's owner) has now
	# been matched; do not let its flag swallow a later self-hit.
	_sourced_damage.erase(defender)
	# FOG: this is the ONE line that survives with a mask, and it must. Your unit taking a
	# hit from nowhere is information you are entitled to -- you can see your own soldier
	# bleed -- so it reads "??? hit Vineweave for 12". Only a blow struck entirely out of
	# sight (both parties unseen) is dropped: you would have no way of knowing it happened.
	if _unseen(attacker) and _unseen(defender):
		_last_crit.erase(defender)
		return
	var crit: bool = bool(_last_crit.get(defender, false))
	_last_crit.erase(defender)
	_append("%s hit %s for %d%s" % [_named(attacker), _named(defender), dmg,
		" (critical!)" if crit else ""], _tint(attacker))


func _on_unit_healed(unit = null, amount = null) -> void:
	if _unseen(unit):
		return
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
	# FOG: the same two rules as every other line (see FOG_MASK) -- a line whose every
	# named unit is unseen is dropped; the context stashes below are harmless either way
	# (the damage / heal line they feed applies its own fog check).
	match kind:
		CombatText.KIND_MISS:
			var attacker = info.get("attacker")
			if src_kind == CombatText.SRC_ATTACK and attacker != null and attacker != unit:
				if not (_unseen(attacker) and _unseen(unit)):
					_append("%s missed %s" % [_named(attacker), _named(unit)], DIM_COLOR)
			elif source != "" and not _unseen(unit):
				_append("%s avoided %s" % [_named(unit), source], DIM_COLOR)
		CombatText.KIND_NEGATED:
			if not _unseen(unit):
				_append("%s is unharmed (immune)" % _named(unit), DIM_COLOR)
		CombatText.KIND_HEAL:
			if src_kind == CombatText.SRC_LIFESTEAL:
				# Lifesteal heals the caster directly (no unit_healed): log it here.
				if not _unseen(unit):
					_append("%s drained %d HP" % [_named(unit), amount], _tint(unit))
			else:
				_heal_source[unit] = source  # "" clears a stale source
		CombatText.KIND_DAMAGE:
			if src_kind == CombatText.SRC_ATTACK:
				_last_crit[unit] = bool(info.get("crit", false))
			elif src_kind in [CombatText.SRC_TILE, CombatText.SRC_STATUS,
					CombatText.SRC_WEATHER, CombatText.SRC_HAZARD]:
				# The self-attributed damage_dealt that follows must not log it again.
				_sourced_damage[unit] = true
				if not _unseen(unit):
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
	if _unseen(unit):
		return
	_append("%s appeared" % _named(unit), _tint(unit))


func _on_unit_eliminated(unit = null, _eliminator = null) -> void:
	# A death in the dark is not news. (The unit is unhidden the moment it comes into view,
	# so this only ever drops kills you genuinely could not have witnessed.)
	if _unseen(unit):
		return
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
	if not is_showing_scrollback():
		_unread += 1
		if _header:
			_header.text = _header_text()


## FOG DISCRETION, in two rules (chosen over blanket suppression so the player is never left
## wondering why their unit lost 12 HP):
##   1. A unit this screen cannot see is never NAMED -- it renders as [constant FOG_MASK].
##   2. A line whose every named unit is unseen is SUPPRESSED outright, because a masked
##      version of it would still leak the fact (and often the position) of the event.
## Both read visibility LIVE at event time, so a unit the vision core reveals by attacking
## is named normally in the very line that reports its attack.
const FOG_MASK := "???"


## True when [param unit] exists but is hidden by fog. A null / freed unit is NOT unseen --
## it is simply unknown, and already degrades to the generic name below.
func _unseen(unit) -> bool:
	return FogOfWarOverlay.unit_hidden(unit)


func _named(unit) -> String:
	if _unseen(unit):
		return FOG_MASK
	if unit != null and is_instance_valid(unit) and unit.has_method("get_display_name"):
		return String(unit.get_display_name())
	return "A unit"


## bbcode colour for a unit by its side: enemy (AI) warm-red, ally cool, else neutral --
## except a CREEP, which is dimmed whichever side it fights for.
##
## WHY CREEPS ARE DIMMED. In Siege a wave arrives every few rounds down every lane, and
## nothing else in the game distinguishes a lane creep from a squad hero: they get the same
## world-space [HealthBar], the same portrait entitlement, the same turn-queue entry. Left at
## full side tint, a wave's spawn-and-die lines are indistinguishable from "one of YOUR units
## just died" -- the two events this log most has to keep apart. Dimming is the cheapest
## marker that reads and the only one that lives entirely in a readout: it costs no extra
## row, no glyph, and no per-unit state.
##
## The mark is read as METADATA rather than through the mode's class ([CaptureBase] stamps
## `siege_creep`), for the same reason the HUD resolves the mode controller by path: a
## battle-log line must never depend on a mode script being present. Every non-Siege battle
## has no unit carrying the mark, so this branch is never taken there.
const CREEP_META: StringName = &"siege_creep"


func _tint(unit) -> String:
	# An unseen unit is dimmed as well as masked: the side tint would say "an ENEMY did
	# that", which is one more fact than "???" is meant to give away.
	if _unseen(unit):
		return DIM_COLOR
	if unit == null or not is_instance_valid(unit) or not unit.has_method("get_owner_player"):
		return NEUTRAL_COLOR
	if unit.has_method("has_meta") and unit.has_meta(CREEP_META) and bool(unit.get_meta(CREEP_META)):
		return DIM_COLOR
	var owner = unit.get_owner_player()
	if owner != null and "is_ai" in owner:
		return ENEMY_COLOR if bool(owner.is_ai) else ALLY_COLOR
	return NEUTRAL_COLOR
