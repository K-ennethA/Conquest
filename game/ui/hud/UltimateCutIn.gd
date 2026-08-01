extends CanvasLayer

class_name UltimateCutIn

## League / Fire-Emblem-style ULTIMATE cut-in. When a unit casts its signature move --
## the 4th moveset slot, or any move flagged [member MoveResource.is_ultimate] (see
## [method MoveResource.is_ultimate_move]) -- a dramatic full-width diagonal band SWEEPS
## across the screen, names the caster and its move HUGE, chromatic-double-flashes at the
## midpoint, and slides out. This plays BEFORE the move resolves so the drama lands first.
##
## Wiring: the cast site emits [signal GameEvents.ultimate_casting] and then AWAITS this
## overlay's [signal finished]; this overlay also LISTENS to that same signal and plays
## itself, so the emit both starts the flash and (because emit is synchronous) guarantees
## the flash is already running by the time the caster awaits. Tests can drive [method play]
## directly.
##
## Layer: its own CanvasLayer at [constant OVERLAY_LAYER] -- ABOVE the ActionAnnouncer
## banner (120) so the cut-in reads over it, but BELOW the TurnTransition wipe (128) so a
## turn hand-off still covers it. Mounted once by [GameWorldManager]. Fully click-through
## and purely presentational -- it never mutates game state.
##
## GameSettings: every duration is scaled by GameSettings.anim_duration_scale() /
## scaled_time(); when animations are OFF the whole sweep is replaced by a single short
## STATIC flash (the player asked for readable drama, but animations-off must stay fast) --
## it is never skipped entirely, because a cast site is awaiting [signal finished] and must
## always be released. Null-safe end to end (headless / absent GameSettings behaves as
## animations-on at 1x).

## Emitted when a cut-in finishes (or the static flash ends, or a re-entrant play is
## dropped). The cast site awaits this so the move resolves only after the flash. ALWAYS
## fires exactly once per [method play] call so an awaiting caster can never hang.
signal finished

# --- Layer / placement ------------------------------------------------------
# Above ActionAnnouncer (120), below TurnTransition (128).
const OVERLAY_LAYER: int = 124
# Discoverable by cast sites (UnitActionsPanel / BotTurnDriver) via group lookup.
const GROUP_NAME: StringName = &"ultimate_cutin"

# --- Timing (seconds, base before Battle-Speed scaling; ~0.8s total) --------
const SWEEP_IN: float = 0.24
const HOLD: float = 0.32
const SWEEP_OUT: float = 0.22
const FADE_IN: float = 0.12
const FADE_OUT: float = 0.16
# The single flat flash shown when animations are OFF (kept short so it never stalls play).
const STATIC_FLASH: float = 0.15
# One chromatic aberration pulse (played twice at the midpoint).
const CHROMA_PULSE: float = 0.06

# --- Geometry ---------------------------------------------------------------
const BAND_ANGLE_DEG: float = -9.0
const INK_BAND_HEIGHT: float = 168.0
const COLOR_BAND_HEIGHT: float = 26.0
const COLOR_BAND_OFFSET: float = 96.0   # accent stripe sits below the ink band's centre
const CHROMA_SHIFT: float = 7.0         # px the red/cyan copies split at peak

# --- Palette ----------------------------------------------------------------
# Text/accent colours come straight from ConquestTheme (like TurnTransition). Only the dark
# band plate is local, since it wants a slightly translucent near-black the theme lacks.
const INK: Color = Color(0.043, 0.035, 0.027, 0.94)  # dark band plate

var _root: Control = null
var _sweep: Control = null
var _ink_band: ColorRect = null
var _color_band: ColorRect = null
var _flash_warm: ColorRect = null   # red-ish chromatic copy
var _flash_cool: ColorRect = null   # cyan-ish chromatic copy
var _name_label: Label = null
var _move_label: Label = null

var _tween: Tween = null
var _chroma_tween: Tween = null
# Guards re-entrancy: a second play() while one is running is DROPPED (never stacked, and no
# stray `finished` raised -- see play()). Safe because the turn-based flow never has two
# ultimate casts in flight at once.
var _busy: bool = false


func _ready() -> void:
	layer = OVERLAY_LAYER
	add_to_group(GROUP_NAME)
	_build_ui()
	_set_idle()
	_connect_events()


# --- Event wiring -----------------------------------------------------------

func _connect_events() -> void:
	var bus: Object = get_node_or_null("/root/GameEvents")
	if bus != null and bus.has_signal(&"ultimate_casting") \
			and not bus.is_connected(&"ultimate_casting", _on_ultimate_casting):
		bus.connect(&"ultimate_casting", _on_ultimate_casting)


func _on_ultimate_casting(unit = null, move = null) -> void:
	play(unit, move)


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "CutInRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Chromatic-aberration flash copies (additive), full-rect, hidden until the midpoint.
	_flash_warm = _make_flash(Color(1.0, 0.28, 0.24))
	_flash_cool = _make_flash(Color(0.32, 0.86, 1.0))
	_root.add_child(_flash_warm)
	_root.add_child(_flash_cool)

	# The band + text group -- this is what SLIDES horizontally for the sweep.
	_sweep = Control.new()
	_sweep.name = "Sweep"
	_sweep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sweep)

	# Dark diagonal plate the text reads over.
	_ink_band = ColorRect.new()
	_ink_band.name = "InkBand"
	_ink_band.color = _ink_color()
	_ink_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.add_child(_ink_band)

	# Thin element-colour accent stripe under the plate.
	_color_band = ColorRect.new()
	_color_band.name = "ColorBand"
	_color_band.color = ConquestTheme.AMBER_LITE
	_color_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.add_child(_color_band)

	# Centred caster name (small) + MOVE NAME (huge), gold on dark.
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	_name_label = Label.new()
	_name_label.name = "CasterName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 26)
	_name_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_name_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_label)

	_move_label = Label.new()
	_move_label.name = "MoveName"
	_move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_move_label.add_theme_font_size_override("font_size", 66)
	_move_label.add_theme_color_override("font_color", ConquestTheme.AMBER_LITE)
	_move_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_move_label.add_theme_constant_override("outline_size", 10)
	_move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_move_label)


func _make_flash(tint: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = tint
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rect.material = mat
	return rect


# --- Public API -------------------------------------------------------------

## Play the cut-in for [param unit] casting [param move]. Ignores a re-entrant call while a
## cut-in is already running (drops it cleanly, never stacks). Honours GameSettings: a normal
## sweep when animations are on, a single short static flash when they are off. Drives exactly
## one [signal finished] per accepted play, so an awaiting cast site is never left hanging.
func play(unit = null, move = null) -> void:
	if _busy:
		# Re-entrant: drop it. We deliberately do NOT emit `finished` here -- that shared signal
		# is what the ALREADY-running cast's site is awaiting, so emitting it would release that
		# caller early and resolve its move mid-flash. A dropped call raises no `finished` of its
		# own, which is safe because the turn-based flow can never have two ultimate casts in
		# flight at once: each cast fully awaits its cut-in before any other cast can begin.
		return

	_busy = true
	_apply_content(unit, move)
	_play_sfx()

	if not _animations_on():
		_play_static_flash()
		return

	_play_sweep()


# --- Content ----------------------------------------------------------------

func _apply_content(unit, move) -> void:
	var caster_name: String = "A unit"
	if unit != null and is_instance_valid(unit) and unit.has_method("get_display_name"):
		caster_name = String(unit.get_display_name())
	var move_name: String = "ULTIMATE"
	if move != null and ("display_name" in move) and String(move.display_name) != "":
		move_name = String(move.display_name)

	if _name_label != null:
		_name_label.text = caster_name.to_upper()
	if _move_label != null:
		_move_label.text = move_name.to_upper()

	# Tint the accent stripe by the move's element, so a fire ult reads warm, a frost ult cool.
	var accent: Color = ConquestTheme.AMBER_LITE
	if move != null and ("element" in move):
		accent = ConquestTheme.element_color(String(move.element))
	if _color_band != null:
		_color_band.color = accent


# --- Layout (sized to the live viewport each play) --------------------------

func _layout_bands() -> void:
	var screen: Vector2 = _screen_size()
	var cx: float = screen.x * 0.5
	var cy: float = screen.y * 0.5
	var band_w: float = screen.x * 2.6  # overshoot so the rotated stripe covers corner-to-corner
	var angle: float = deg_to_rad(BAND_ANGLE_DEG)

	if _ink_band != null:
		_ink_band.size = Vector2(band_w, INK_BAND_HEIGHT)
		_ink_band.pivot_offset = _ink_band.size * 0.5
		_ink_band.position = Vector2(cx - band_w * 0.5, cy - INK_BAND_HEIGHT * 0.5)
		_ink_band.rotation = angle

	if _color_band != null:
		_color_band.size = Vector2(band_w, COLOR_BAND_HEIGHT)
		_color_band.pivot_offset = _color_band.size * 0.5
		_color_band.position = Vector2(cx - band_w * 0.5, cy + COLOR_BAND_OFFSET - COLOR_BAND_HEIGHT * 0.5)
		_color_band.rotation = angle


# --- Sweep playback ---------------------------------------------------------

func _play_sweep() -> void:
	_layout_bands()
	var screen: Vector2 = _screen_size()
	var off: float = screen.x * 1.15  # start / end the band group fully off-screen

	_kill_tweens()

	if _root != null:
		_root.visible = true
		_root.modulate.a = 0.0
	if _sweep != null:
		_sweep.position = Vector2(-off, 0.0)
	_reset_flashes()

	# Each stage's FIRST tweener is plain (auto-chains after the previous stage); its second is
	# .parallel() (runs alongside the first). This keeps the sweep-out strictly AFTER the hold,
	# rather than racing it -- a .parallel() first tweener would run parallel to the hold interval.
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	# Sweep IN (band slides to centre) while the whole overlay fades up.
	_tween.tween_property(_sweep, "position:x", 0.0, _scaled(SWEEP_IN))
	_tween.parallel().tween_property(_root, "modulate:a", 1.0, _scaled(FADE_IN))
	# Midpoint chromatic double-flash, then the readable hold.
	_tween.tween_callback(_chroma_double_flash)
	_tween.tween_interval(_scaled(HOLD))
	# Sweep OUT (band continues off the right) while fading down.
	_tween.set_ease(Tween.EASE_IN)
	_tween.tween_property(_sweep, "position:x", off, _scaled(SWEEP_OUT))
	_tween.parallel().tween_property(_root, "modulate:a", 0.0, _scaled(FADE_OUT))
	_tween.tween_callback(_end)


func _chroma_double_flash() -> void:
	# Two quick red/cyan splits: alpha pulses up and the copies shift apart, reading as a
	# camera-shock chromatic aberration on the strike.
	if _flash_warm == null or _flash_cool == null:
		return
	if _chroma_tween != null and _chroma_tween.is_valid():
		_chroma_tween.kill()
	_reset_flashes()

	var pulse: float = _scaled(CHROMA_PULSE)
	# Each of the two pulses is a RISE group (alpha up, copies split apart) followed by a FALL
	# group (alpha down, copies recentre). A plain (non-.parallel) tweener auto-chains after
	# the preceding parallel group, so the FALL waits for the RISE and pulse 2 waits for pulse 1.
	_chroma_tween = create_tween()
	for _i in 2:
		_chroma_tween.tween_property(_flash_warm, "modulate:a", 0.45, pulse)
		_chroma_tween.parallel().tween_property(_flash_cool, "modulate:a", 0.45, pulse)
		_chroma_tween.parallel().tween_property(_flash_warm, "position:x", -CHROMA_SHIFT, pulse)
		_chroma_tween.parallel().tween_property(_flash_cool, "position:x", CHROMA_SHIFT, pulse)
		_chroma_tween.tween_property(_flash_warm, "modulate:a", 0.0, pulse)
		_chroma_tween.parallel().tween_property(_flash_cool, "modulate:a", 0.0, pulse)
		_chroma_tween.parallel().tween_property(_flash_warm, "position:x", 0.0, pulse)
		_chroma_tween.parallel().tween_property(_flash_cool, "position:x", 0.0, pulse)


func _reset_flashes() -> void:
	if _flash_warm != null:
		_flash_warm.modulate.a = 0.0
		_flash_warm.position.x = 0.0
	if _flash_cool != null:
		_flash_cool.modulate.a = 0.0
		_flash_cool.position.x = 0.0


# --- Static (animations-off) path -------------------------------------------

func _play_static_flash() -> void:
	# No sweep: snap the band on, hold flat and brief, then end. Still names the move so the
	# player reads WHAT fired, just without the motion.
	_layout_bands()
	_kill_tweens()
	if _sweep != null:
		_sweep.position = Vector2.ZERO
	_reset_flashes()
	if _root != null:
		_root.visible = true
		_root.modulate.a = 1.0
	# A SceneTreeTimer (not a tween) so it holds a fixed real-time beat regardless of scaling.
	var timer: SceneTreeTimer = get_tree().create_timer(STATIC_FLASH)
	timer.timeout.connect(_end)


# --- End / idle -------------------------------------------------------------

func _end() -> void:
	_set_idle()
	_busy = false
	finished.emit()


func _set_idle() -> void:
	_kill_tweens()
	_reset_flashes()
	if _root != null:
		_root.modulate.a = 0.0
		_root.visible = false


func _kill_tweens() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _chroma_tween != null and _chroma_tween.is_valid():
		_chroma_tween.kill()
	_chroma_tween = null


# --- Helpers (null-safe GameSettings / theme / audio / viewport) ------------

func _animations_on() -> bool:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and GameSettings.has_method("animations_on"):
		return GameSettings.animations_on()
	return true  # headless / absent -> behave as animations-on


func _scaled(base_seconds: float) -> float:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and GameSettings.has_method("scaled_time"):
		# scaled_time returns 0 when animations are off; that path is handled separately, but
		# clamp to a small floor so a zero can never stall the tween chain.
		return maxf(GameSettings.scaled_time(base_seconds), 0.01)
	return base_seconds


func _play_sfx() -> void:
	if typeof(AudioManager) == TYPE_OBJECT and AudioManager != null \
			and AudioManager.has_method("play_sfx"):
		# Reuse the existing punchy attack cue -- no new audio files.
		AudioManager.play_sfx(&"sfx_attack")


func _screen_size() -> Vector2:
	var vp: Viewport = get_viewport()
	if vp != null:
		var s: Vector2 = vp.get_visible_rect().size
		if s.x > 0.0 and s.y > 0.0:
			return s
	return Vector2(1280.0, 720.0)  # sane default (headless / not yet sized)


func _ink_color() -> Color:
	return INK
