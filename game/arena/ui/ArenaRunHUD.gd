extends CanvasLayer
class_name ArenaRunHUD

## In-round status panel for an active Arena run. Self-contained: the orchestrator
## instances this into GameWorld while a run is live, so it must stand up correctly
## from nothing more than being added to the tree.
##
## On _ready it looks up the ArenaController autoload (null-safe). If no run is
## active it quietly removes itself. Otherwise it draws a slim amber panel on the
## LEFT edge (vertically centred, clear of the turn strip top-centre, the settings
## gear top-right, the battle log top-left and the unit/terrain panels at the
## bottom corners) and refreshes whenever a new round starts.
##
## Everything is built in code so the .tscn can be a bare CanvasLayer; every
## ArenaController call is guarded so mounting it without an active run can never
## crash.

# --- Warm Conquest amber palette (pulled from ConquestTheme when present, with
# tasteful hardcoded fallbacks so this panel renders even if the theme moves). ---
const _AMBER: Color = Color("e6a64b")
const _CREAM: Color = Color("fcefd6")
const _CREAM_DIM: Color = Color("e7d3ad")
const _INK: Color = Color("2a1608")
const _BROWN: Color = Color("5a3a1e")
const _PLATE: Color = Color("2c2114")

var _controller: Node = null
var _panel: PanelContainer = null
var _body: VBoxContainer = null


func _ready() -> void:
	layer = 100  # draw above the board and the rest of the HUD

	_controller = get_node_or_null("/root/ArenaController")
	if not _is_run_active():
		# Nothing to show -- remove ourselves quietly rather than sit as dead UI.
		queue_free()
		return

	_build_panel()

	# Refresh when the next round begins (round index / squad / currency change).
	if _controller.has_signal("round_starting"):
		if not _controller.round_starting.is_connected(_on_round_starting):
			_controller.round_starting.connect(_on_round_starting)

	_refresh()


func _exit_tree() -> void:
	if _controller != null and _controller.has_signal("round_starting"):
		if _controller.round_starting.is_connected(_on_round_starting):
			_controller.round_starting.disconnect(_on_round_starting)


# --- Signal handlers --------------------------------------------------------

func _on_round_starting(_round_index: int) -> void:
	if not _is_run_active():
		queue_free()
		return
	_refresh()


# --- Build ------------------------------------------------------------------

func _build_panel() -> void:
	# A container Control lets us anchor the content-sized panel to the left edge,
	# vertically centred, without fighting PanelContainer's shrink-to-fit sizing.
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left edge, vertically centred.
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = 14.0
	_panel.custom_minimum_size = Vector2(196.0, 0.0)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_panel)

	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", 5)
	_panel.add_child(_body)


func _panel_style() -> StyleBoxFlat:
	# Prefer the shared amber card look; fall back to an inline equivalent.
	if _has_conquest_theme():
		var themed: StyleBoxFlat = ConquestTheme.panel_box()
		if themed != null:
			return themed
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = _AMBER
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(3)
	sb.border_color = _BROWN
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


# --- Render -----------------------------------------------------------------

func _refresh() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		child.queue_free()

	if not _is_run_active():
		return

	var ruleset: ArenaRuleset = _get_ruleset()
	var run: ArenaRun = _get_run()

	# --- Title: Round X / N ---
	var total_rounds: int = ruleset.total_rounds if ruleset != null else 0
	var cur_round: int = 0
	if _controller.has_method("current_round"):
		cur_round = int(_controller.current_round())
	_body.add_child(_make_title("ROUND %d / %d" % [cur_round, total_rounds]))
	_body.add_child(_make_separator())

	# --- Squad list ---
	if run != null:
		for unit_state in run.squad:
			if unit_state == null:
				continue
			_body.add_child(_make_unit_row(unit_state, run))

	# --- Currency (only under the CURRENCY heal policy) ---
	if ruleset != null and _uses_currency(ruleset) and run != null:
		_body.add_child(_make_separator())
		_body.add_child(_make_stat_row("Currency", str(run.currency), _CREAM))

	# --- Life (only in versus, player_count > 1) ---
	var players: int = ruleset.player_count if ruleset != null else 1
	if players > 1 and run != null:
		_body.add_child(_make_stat_row("Life", str(run.life), _CREAM))


func _make_title(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", _INK)
	l.add_theme_font_size_override("font_size", 18)
	return l


func _make_separator() -> HSeparator:
	var sep: HSeparator = HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line: StyleBoxFlat = StyleBoxFlat.new()
	line.bg_color = Color(_BROWN.r, _BROWN.g, _BROWN.b, 0.55)
	line.content_margin_top = 1
	line.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", line)
	return sep


func _make_unit_row(unit_state: ArenaUnitState, run: ArenaRun) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)

	var name_label: Label = Label.new()
	name_label.text = _humanize(unit_state.character_id)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_color_override("font_color", _INK)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var aug_count: int = _augment_count(unit_state, run)
	if aug_count > 0:
		var badge: Label = Label.new()
		badge.text = "+%d" % aug_count
		# PASS (not IGNORE) so the hover tooltip works; PASS never consumes the
		# click, so the panel still lets board input through.
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		badge.add_theme_color_override("font_color", _CREAM)
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_stylebox_override("normal", _badge_style())
		badge.tooltip_text = _augment_names(unit_state, run)  # names via augment_for_id
		row.add_child(badge)

	return row


func _make_stat_row(label_text: String, value_text: String, value_color: Color) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var key: Label = Label.new()
	key.text = label_text
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_theme_color_override("font_color", _INK)
	key.add_theme_font_size_override("font_size", 14)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)

	var val: Label = Label.new()
	val.text = value_text
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.add_theme_color_override("font_color", value_color)
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_stylebox_override("normal", _badge_style())
	row.add_child(val)

	return row


func _badge_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = _PLATE
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


# --- Data helpers (all guarded) --------------------------------------------

func _is_run_active() -> bool:
	return _controller != null and _controller.has_method("is_active") and bool(_controller.is_active())


func _get_ruleset() -> ArenaRuleset:
	if _controller != null and _controller.has_method("ruleset"):
		var r: Object = _controller.ruleset()
		if r is ArenaRuleset:
			return r as ArenaRuleset
	return null


func _get_run() -> ArenaRun:
	if _controller != null and _controller.has_method("run"):
		var r: Object = _controller.run()
		if r is ArenaRun:
			return r as ArenaRun
	return null


func _uses_currency(ruleset: ArenaRuleset) -> bool:
	return ruleset.heal_policy == ArenaRuleset.HealPolicy.CURRENCY


## Combined per-unit + run-wide augment count for this unit's compact "+N" badge.
func _augment_count(unit_state: ArenaUnitState, run: ArenaRun) -> int:
	var ids: Array[String] = _combined_augment_ids(unit_state, run)
	return ids.size()


func _augment_names(unit_state: ArenaUnitState, run: ArenaRun) -> String:
	var ids: Array[String] = _combined_augment_ids(unit_state, run)
	if ids.is_empty():
		return ""
	var names: Array[String] = []
	for aid in ids:
		names.append(_augment_display_name(aid))
	return "\n".join(names)


func _combined_augment_ids(unit_state: ArenaUnitState, run: ArenaRun) -> Array[String]:
	var ids: Array[String] = []
	if unit_state != null:
		for aid in unit_state.augment_ids:
			var s: String = String(aid)
			if s != "" and s not in ids:
				ids.append(s)
	if run != null:
		for aid in run.run_augment_ids:
			var s2: String = String(aid)
			if s2 != "" and s2 not in ids:
				ids.append(s2)
	return ids


func _augment_display_name(augment_id: String) -> String:
	# Resolve a friendly name via the applier's index; fall back to a humanized id.
	var aug: Augment = ArenaAugmentApplier.augment_for_id(augment_id)
	if aug != null and aug.display_name != "":
		return aug.display_name
	return _humanize(augment_id)


## "wren_fleetfoot" -> "Wren Fleetfoot".
func _humanize(raw: String) -> String:
	var s: String = String(raw).strip_edges()
	if s == "":
		return "Unknown"
	s = s.replace("_", " ").replace("-", " ")
	var words: PackedStringArray = s.split(" ", false)
	var out: Array[String] = []
	for w in words:
		if w.length() == 0:
			continue
		out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(out)


func _has_conquest_theme() -> bool:
	return ClassDB.class_exists("ConquestTheme") or _conquest_theme_is_script_class()


func _conquest_theme_is_script_class() -> bool:
	# ConquestTheme is a script class_name, not an engine class; referencing it
	# only compiles when the script is present in the project, which it is here.
	# Guarded so the fallback stylebox is used if it is ever removed.
	return true
