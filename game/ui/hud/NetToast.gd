extends CanvasLayer

class_name NetToast

## Brief, non-blocking NETWORK NOTICE banner -- "Attack rejected — not your turn".
##
## The problem it solves: in a networked match the client never mutates the board itself; it
## submits an intent and the server decides. When the server REFUSES one ([signal
## NetSession.intent_rejected]) the command simply never happens, and until now that was
## completely silent -- the player clicked, nothing moved, and nothing said why. This overlay
## is the answer: a small amber HUD toast that names the refused command and the reason, then
## dismisses itself.
##
## Deliberately NOT a dialog. A rejection is information, not a decision: the toast is fully
## click-through (mouse_filter IGNORE), never pauses, never steals focus, and never blocks the
## board underneath. It is purely presentational and mutates no game state.
##
## Mounted by [UILayoutManager] on its own CanvasLayer, ABOVE the action banner
## ([ActionAnnouncer], 120) so a rejection is not buried under a move announcement, and BELOW
## the ultimate cut-in (124) / turn wipe (128), which are cinematic and own the screen while
## they run.
##
## Styling comes from [ConquestTheme] (warm amber plate + cream text), so it reads as part of
## the same HUD as the panels rather than as a system error box.
##
## Honours GameSettings.animations_on / scaled_time when present; with animations OFF it snaps
## on and off and still holds the full readable beat. Null-safe headless (no GameSettings, no
## NetSession) -- every hook is guarded, so a test can mount it bare.

## Emitted whenever a toast is put on screen, carrying the exact line shown. Tests assert on
## this rather than scraping the label, and a future telemetry/log hook can ride it.
signal toast_shown(text: String)

# --- Layer / placement ------------------------------------------------------
# Above ActionAnnouncer (120), below UltimateCutIn (124) and TurnTransition (128).
const OVERLAY_LAYER: int = 122
## Pushed below the action banner's own top offset (104) so the two never overlap when a
## rejection lands while a move announcement is still on screen.
const TOP_OFFSET: float = 178.0
const TOAST_MAX_WIDTH: float = 560.0

# --- Timing (seconds, base before Battle-Speed scaling) ---------------------
## How long the line stays fully readable. The whole toast lives ~HOLD + the fades, i.e. the
## ~2.5s auto-dismiss this overlay promises.
const HOLD: float = 2.3
const FADE_IN: float = 0.12
const FADE_OUT: float = 0.3
## Floor on the hold so a fast Battle Speed can never blink a rejection away unread.
const MIN_HOLD: float = 1.2

# --- Palette (ConquestTheme, so the toast matches the amber HUD panels) -----
## Slightly translucent version of the theme's panel plate -- the toast floats over the board,
## so it wants to be a shade lighter than an opaque HUD card.
const PLATE_BG: Color = Color(0.173, 0.129, 0.078, 0.92)  # ConquestTheme.PLATE_BG + alpha

var _root: Control = null
var _plate: PanelContainer = null
var _label: Label = null
var _tween: Tween = null


func _ready() -> void:
	layer = OVERLAY_LAYER
	_build_ui()
	_wire_net_session()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ToastRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_plate = PanelContainer.new()
	_plate.name = "ToastPlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Top-centre, hugging its text (SHRINK via GROW_DIRECTION_BOTH) rather than stretching.
	_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_plate.offset_top = TOP_OFFSET
	_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plate.grow_vertical = Control.GROW_DIRECTION_END
	_plate.add_theme_stylebox_override("panel", _plate_box())
	_root.add_child(_plate)

	_label = Label.new()
	_label.name = "ToastLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(TOAST_MAX_WIDTH, 0.0)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_label)

	_set_idle()


func _plate_box() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PLATE_BG
	box.set_corner_radius_all(8)
	box.set_content_margin_all(12)
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.border_color = ConquestTheme.AMBER
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	box.shadow_size = 6
	return box


# --- Session wiring ---------------------------------------------------------

func _wire_net_session() -> void:
	var net: Object = _net_session()
	if net == null:
		return
	if net.has_signal(&"intent_rejected") and not net.is_connected(&"intent_rejected", _on_intent_rejected):
		net.connect(&"intent_rejected", _on_intent_rejected)


func _exit_tree() -> void:
	# NetSession is an autoload and outlives this battle HUD, so drop the hook rather than
	# leaving it holding a reference to a node that is going away.
	var net: Object = _net_session()
	if net == null:
		return
	if net.has_signal(&"intent_rejected") and net.is_connected(&"intent_rejected", _on_intent_rejected):
		net.disconnect(&"intent_rejected", _on_intent_rejected)


## The live NetSession autoload, or null when it is unavailable (bare test harness / headless
## runs with no autoloads). Looked up by node path rather than by the global identifier so a
## test can mount this overlay with no session at all.
func _net_session() -> Object:
	return get_node_or_null("/root/NetSession")


## The server refused a command this peer submitted. [param action] is our own outgoing
## envelope (used only to name the command) and [param reason] is the NetProtocol.INTENT_*
## wire string; the player-facing wording is NetProtocol's, so this handler is a thin renderer.
func _on_intent_rejected(action: Dictionary, reason: String) -> void:
	show_notice(NetProtocol.describe_intent_rejection(reason, action))


# --- Public API -------------------------------------------------------------

## Put [param text] on screen and dismiss it automatically. A second call REPLACES whatever is
## showing (rather than queueing): a rejection is about what the player just did, so the newest
## one is always the relevant one and a stale line must never outlive it.
func show_notice(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	if _label != null:
		_label.text = text
	if _root != null:
		_root.visible = true
	_kill_tween()

	var fade_in: float = _fade_time(FADE_IN)
	var fade_out: float = _fade_time(FADE_OUT)
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, fade_in)
	_tween.tween_interval(_hold_time())
	_tween.tween_property(_root, "modulate:a", 0.0, fade_out)
	_tween.tween_callback(_set_idle)

	toast_shown.emit(text)


## Take any toast off screen immediately (used when a battle ends / the overlay is reused).
func dismiss() -> void:
	_kill_tween()
	_set_idle()


## True while a toast is on screen.
func is_showing() -> bool:
	return _root != null and _root.visible


## The line currently displayed ("" when idle) -- the toast's readable state, for tests.
func current_text() -> String:
	if _label == null or not is_showing():
		return ""
	return _label.text


# --- Idle / timing ----------------------------------------------------------

func _set_idle() -> void:
	if _root != null:
		_root.modulate.a = 0.0
		_root.visible = false


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _hold_time() -> float:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null:
		if GameSettings.has_method("animations_on") and not GameSettings.animations_on():
			# Animations off: no fades, but the text still has to be readable, so hold the
			# full base beat rather than scaling it away.
			return HOLD
		if GameSettings.has_method("scaled_time"):
			return maxf(GameSettings.scaled_time(HOLD), MIN_HOLD)
	return HOLD


func _fade_time(base: float) -> float:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null:
		if GameSettings.has_method("animations_on") and not GameSettings.animations_on():
			return 0.01  # snap (a zero-length tweener would stall the chain)
		if GameSettings.has_method("scaled_time"):
			return maxf(GameSettings.scaled_time(base), 0.01)
	return base
