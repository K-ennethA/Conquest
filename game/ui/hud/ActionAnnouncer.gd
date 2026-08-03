extends CanvasLayer

class_name ActionAnnouncer

## Big, brief on-screen ACTION BANNER -- "Eldroot used Forest Barrage!" -- that flashes
## whenever a unit acts, so the enemy/AI turn is legible even before per-move VFX exist.
##
## The problem it solves: turns can flick past ("my turn, their turn, almost instantly
## back") and the small board animation isn't enough emphasis to notice the bot actually
## DID something. This overlay listens to the GameEvents bus and pops a large, centred-ish
## banner for EVERY move (ally and enemy), tinted by side (enemy warm-red, ally cool), with
## a compact hit result underneath ("hit Torvald for 12") folded in from damage_dealt.
##
## Mounted by UILayoutManager on its own high CanvasLayer (like TurnTransition/BattleLog),
## so it draws above the HUD panels but just under the full-screen turn wipe. Fully
## click-through (mouse_filter IGNORE) and purely presentational -- it never mutates state.
##
## Queueing: a flurry of moves (AoE, multi-unit AI phase) is shown one banner at a time,
## each honouring a short minimum display so nothing is overwritten before it can be read.
## Honors GameSettings.animations_on / scaled_time when present; degrades to sensible real
## timings (and no crash) when GameSettings or the signals are absent (headless/tests).

# --- Layer / placement ------------------------------------------------------
# High enough to sit above every HUD panel, but BELOW the turn-transition wipe (128) so a
# turn hand-off still covers it cleanly.
const OVERLAY_LAYER: int = 120
# Pushed DOWN from the very top so it clears the top-centre turn chip / "YOUR TURN" banner.
# Upper-centre, below the turn banner -- clear of the left SELECT-MOVE popup, the right
# action panel, and the corners (battle log / terrain card / turn indicator).
#
# This is a FLOOR, not the final position. The HUD's TopBar is 56px tall for the compact
# Traditional turn chip but 180px for the Speed First turn QUEUE, and a fixed 104 put the
# banner straight through the middle of the taller one -- the reported "toast renders half
# under the top turn banner". _banner_top() measures the live top bar and parks the banner
# BANNER_GAP below whichever it is, falling back to this constant when there is no HUD to
# measure (tests, other scenes).
const TOP_OFFSET: float = 104.0
## Clear air between the bottom of the turn banner and the top of this plate.
const BANNER_GAP: float = 16.0
## Where the HUD's top bar lives, relative to the current scene.
const TOP_BAR_PATH: String = "UI/GameUILayout/MarginContainer/MainContainer/TopBar"
const BANNER_MAX_WIDTH: float = 720.0

# --- Timing (seconds, base before Battle-Speed scaling) ---------------------
const FADE_IN: float = 0.14
const HOLD: float = 0.9
const FADE_OUT: float = 0.28
# Floor on the hold so a fast Battle Speed can't blink a banner away unreadably; and the
# real-time hold used when animations are OFF (we still want the text to linger, since the
# whole point of this overlay is legibility).
const MIN_HOLD: float = 0.55
# Damage buffered longer ago than this (seconds) is considered stale and ignored when
# building a banner's hit subtitle. Damage for a move is emitted just BEFORE its
# move_performed (MoveExecutor runs, then unit.perform_move emits), so a short window fits.
const DAMAGE_WINDOW: float = 1.5

# --- Side tints (hardcoded warm/cool fallbacks; no ConquestTheme dependency) -
# Matches the amber/cream theme and BattleLog's side scheme: enemy (AI) warm-red, ally cool.
const ALLY_COLOR: Color = Color(0.76, 0.88, 1.0)     # cool blue-white
const ENEMY_COLOR: Color = Color(1.0, 0.55, 0.42)    # warm red-orange
const NEUTRAL_COLOR: Color = Color(0.988, 0.937, 0.839)  # cream (ConquestTheme.CREAM)
const CREAM_DIM: Color = Color(0.906, 0.827, 0.678)  # subtitle (ConquestTheme.CREAM_DIM)
const OUTLINE_COLOR: Color = Color(0.216, 0.133, 0.059)  # BROWN_DK, for text readability
# Near-opaque: at 0.78 the amber turn chip and the 3D board read straight through the
# plate, which is what made the banner text look "semi-transparent and colliding".
const PLATE_BG: Color = Color(0.06, 0.045, 0.03, 0.94)   # dark warm plate

var _root: Control = null
var _plate: PanelContainer = null
var _main_label: Label = null
var _sub_label: Label = null
var _tween: Tween = null

# Pending banners, shown one at a time. Each entry: {"text": String, "sub": String,
# "color": Color}.
var _queue: Array[Dictionary] = []
var _busy: bool = false

# Recent damage_dealt events, buffered so a move's banner can show its hit result even
# though the damage arrives just before move_performed. Each entry:
# {"attacker": Object, "defender_name": String, "amount": int, "t": float}.
var _damage_buffer: Array[Dictionary] = []


func _ready() -> void:
	layer = OVERLAY_LAYER
	_build_ui()
	_connect_events()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	# Full-rect click-through root; we position the plate near the top-centre inside it.
	_root = Control.new()
	_root.name = "AnnouncerRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Dark rounded plate so the text reads over the 3D board regardless of what's behind it.
	_plate = PanelContainer.new()
	_plate.name = "Banner"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor top-centre, offset down past the turn banner. SHRINK_CENTER keeps it hugging
	# its text width (up to BANNER_MAX_WIDTH) instead of stretching across the screen.
	_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_plate.offset_top = TOP_OFFSET
	_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plate.grow_vertical = Control.GROW_DIRECTION_END
	_plate.custom_minimum_size = Vector2(0.0, 0.0)
	_apply_plate_style(NEUTRAL_COLOR)
	_root.add_child(_plate)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(vbox)

	# Big action line: "<Unit> used <Move>!"
	_main_label = Label.new()
	_main_label.name = "MainLabel"
	_main_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_label.custom_minimum_size = Vector2(BANNER_MAX_WIDTH, 0.0)
	_main_label.add_theme_font_size_override("font_size", 40)
	_main_label.add_theme_color_override("font_color", NEUTRAL_COLOR)
	_main_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_main_label.add_theme_constant_override("outline_size", 8)
	_main_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_main_label)

	# Compact hit result: "hit Torvald for 12".
	_sub_label = Label.new()
	_sub_label.name = "SubLabel"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_font_size_override("font_size", 22)
	_sub_label.add_theme_color_override("font_color", CREAM_DIM)
	_sub_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_sub_label.add_theme_constant_override("outline_size", 6)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_sub_label)

	# Start hidden; a banner only appears when something acts.
	_root.modulate.a = 0.0
	_root.visible = false

	# The HUD may not be laid out yet on the frame this is built, so take a first
	# measurement once the tree has settled.
	call_deferred("_reposition")


# --- Placement --------------------------------------------------------------

## The y this plate's top edge should sit at: below the live HUD top bar (turn chip or
## turn queue) plus BANNER_GAP, never above TOP_OFFSET. Pure enough to pin in a test via
## [method banner_top].
static func banner_top(top_bar_bottom: float) -> float:
	return maxf(TOP_OFFSET, top_bar_bottom + BANNER_GAP)


## Bottom edge (in viewport space) of the HUD's top bar, or -INF when there is no HUD to
## measure -- in which case banner_top() falls back to TOP_OFFSET.
func _top_bar_bottom() -> float:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return -INF
	var bar := tree.current_scene.get_node_or_null(TOP_BAR_PATH) as Control
	if bar == null or not bar.is_visible_in_tree():
		return -INF
	return bar.global_position.y + bar.size.y


## Re-park the plate under whatever the top bar currently is. Cheap (two property reads),
## so it is re-run before every banner rather than cached -- the bar's height changes with
## the active turn system.
func _reposition() -> void:
	if _plate == null or not is_instance_valid(_plate):
		return
	_plate.offset_top = banner_top(_top_bar_bottom())


func _apply_plate_style(side: Color) -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PLATE_BG
	box.set_corner_radius_all(10)
	box.set_content_margin_all(14)
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	var edge: Color = side
	edge.a = 0.85
	box.border_color = edge
	# A soft shadow lifts the plate off the busy board.
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	box.shadow_size = 6
	_plate.add_theme_stylebox_override("panel", box)


# --- Event wiring -----------------------------------------------------------

func _connect_events() -> void:
	var bus: Object = get_node_or_null("/root/GameEvents")
	if bus == null:
		return
	_safe(bus, &"move_performed", _on_move_performed)
	_safe(bus, &"damage_dealt", _on_damage_dealt)


func _safe(obj: Object, sig: StringName, cb: Callable) -> void:
	if obj != null and obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)


# --- Handlers (all null-safe; freed units degrade to a generic name) ---------

func _on_move_performed(caster = null, move = null) -> void:
	var move_name: String = "a move"
	if move != null and "display_name" in move and String(move.display_name) != "":
		move_name = String(move.display_name)
	var text: String = "%s used %s!" % [_named(caster), move_name]
	var sub: String = _consume_damage_for(caster)
	var entry: Dictionary = {
		"text": text,
		"sub": sub,
		"color": _side_color(caster),
		"attacker": caster,
	}
	_queue.append(entry)
	# Never let the announcer fall more than ONE banner behind the action. A fast enemy
	# turn used to pile up banners that then drained one-per-hold long after the fact --
	# spilling the enemy's moves into the PLAYER's turn. Keeping only the newest pending
	# entry drops that stale backlog so the banner tracks what just happened, not history.
	if _queue.size() > 1:
		_queue = [_queue[_queue.size() - 1]]
	if not _busy:
		_next()


func _on_damage_dealt(attacker = null, defender = null, damage = null) -> void:
	var amount: int = int(damage) if damage != null else 0
	if amount <= 0:
		return
	# Buffer it so the imminent move_performed banner can fold in the hit result. We keep
	# only the attacker + a resolved defender name (units may be freed by the time we read).
	var entry: Dictionary = {
		"attacker": attacker,
		"defender_name": _named(defender),
		"amount": amount,
		"t": _now(),
	}
	_damage_buffer.append(entry)
	_prune_damage()
	# If a banner for THIS attacker is already on screen (e.g. a lingering multi-hit),
	# update its subtitle live so late damage still shows.
	if _busy and _current_attacker != null and _current_attacker == attacker and _sub_label != null:
		var running: String = _consume_damage_for(attacker)
		if running != "":
			_sub_label.text = running
			_sub_label.visible = true


# --- Damage folding ---------------------------------------------------------

# The attacker whose banner is currently displayed (for live subtitle updates).
var _current_attacker = null


## Build the compact hit subtitle for [param attacker] from buffered damage, consuming the
## matched entries. "" when no fresh damage is attributable (heals, buffs, whiffs).
func _consume_damage_for(attacker) -> String:
	_prune_damage()
	if attacker == null:
		return ""
	var total: int = 0
	var last_defender: String = ""
	var defenders: Dictionary = {}
	var remaining: Array[Dictionary] = []
	for entry in _damage_buffer:
		if entry.get("attacker") == attacker:
			total += int(entry.get("amount", 0))
			last_defender = String(entry.get("defender_name", ""))
			defenders[last_defender] = true
		else:
			remaining.append(entry)
	_damage_buffer = remaining
	if total <= 0:
		return ""
	# One target -> name it; several -> keep it compact.
	if defenders.size() == 1 and last_defender != "" and last_defender != "A unit":
		return "hit %s for %d" % [last_defender, total]
	return "hit for %d" % total


func _prune_damage() -> void:
	var now: float = _now()
	var kept: Array[Dictionary] = []
	for entry in _damage_buffer:
		if now - float(entry.get("t", 0.0)) <= DAMAGE_WINDOW:
			kept.append(entry)
	_damage_buffer = kept


# --- Queue playback ---------------------------------------------------------

func _next() -> void:
	if _queue.is_empty():
		_busy = false
		_current_attacker = null
		_set_idle()
		return
	_busy = true
	var entry: Dictionary = _queue.pop_front()
	_show(entry)


func _show(entry: Dictionary) -> void:
	var text: String = String(entry.get("text", ""))
	var sub: String = String(entry.get("sub", ""))
	var color: Color = entry.get("color", NEUTRAL_COLOR)
	_current_attacker = entry.get("attacker")  # for live subtitle updates from late damage

	if _main_label != null:
		_main_label.text = text
		_main_label.add_theme_color_override("font_color", color)
	if _sub_label != null:
		_sub_label.text = sub
		_sub_label.visible = sub != ""
	_apply_plate_style(color)
	# The top bar's height changes with the active turn system, so re-measure per banner.
	_reposition()

	if _root != null:
		_root.visible = true

	# Kill any in-flight tween so the new banner starts clean.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

	var fade_in: float = _fade_time(FADE_IN)
	var fade_out: float = _fade_time(FADE_OUT)
	var hold: float = _hold_time()

	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, fade_in)
	_tween.tween_interval(hold)
	_tween.tween_property(_root, "modulate:a", 0.0, fade_out)
	_tween.tween_callback(_next)


func _set_idle() -> void:
	if _root != null:
		_root.modulate.a = 0.0
		_root.visible = false


# --- Timing helpers (null-safe GameSettings) --------------------------------

func _hold_time() -> float:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null:
		if GameSettings.has_method("animations_on") and not GameSettings.animations_on():
			# Animations off: no fades, but still linger the full base so it's readable.
			return HOLD
		if GameSettings.has_method("scaled_time"):
			return maxf(GameSettings.scaled_time(HOLD), MIN_HOLD)
	return HOLD


func _fade_time(base: float) -> float:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null:
		if GameSettings.has_method("animations_on") and not GameSettings.animations_on():
			return 0.0  # snap on/off when animations are disabled
		if GameSettings.has_method("scaled_time"):
			return maxf(GameSettings.scaled_time(base), 0.01)
	return base


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# --- Naming / side helpers (mirror BattleLog) -------------------------------

func _named(unit) -> String:
	if unit != null and is_instance_valid(unit) and unit.has_method("get_display_name"):
		return String(unit.get_display_name())
	return "A unit"


## Side colour for a unit: enemy (AI) warm-red, ally cool, else neutral cream.
func _side_color(unit) -> Color:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("get_owner_player"):
		return NEUTRAL_COLOR
	var owner = unit.get_owner_player()
	if owner != null and "is_ai" in owner:
		return ENEMY_COLOR if bool(owner.is_ai) else ALLY_COLOR
	return NEUTRAL_COLOR
