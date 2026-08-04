class_name StoryDialogue
extends CanvasLayer

## FIRE-EMBLEM-STYLE STORY OVERLAY: two portrait panels that slide in from their own side of
## the screen, an amber text box across the bottom with a speaker name plate, and a
## typewriter reveal you can tap through. Plays a [StoryScene] and emits [signal finished].
##
## DELIBERATELY CONTEXT-FREE -- it does not care what is behind it. It is a [CanvasLayer] at
## [constant LAYER_INDEX] with a full-rect input-blocking root, so the same node plays a
## campaign intro over the Character Select screen, an outro over the battle board (and over
## the paused game-over screen -- see PAUSE below), or, later, a mid-battle beat over live
## gameplay, with NO change here. Mid-battle triggers are intentionally NOT wired yet.
##
## LAYER: 135. Above the battle HUD (ActionAnnouncer's 120) and the achievement toast (128),
## below [SceneFade]'s 200 so a scene transition still wipes over the top of a story. The
## battle's own "UI" CanvasLayer is layer 0, so this draws over [GameOverScreen] too --
## which is exactly what makes the chapter outro land BEFORE the results card is readable,
## without editing GameWorldManager or the end screen.
##
## PAUSE: [constant Node.PROCESS_MODE_ALWAYS]. The outro plays while [GameOverScreen] has
## paused the tree, so both the clock and the input handlers have to keep running.
##
## INTERACTION MODEL (all of it routed through [StorySequencer.advance], which owns the
## branch -- see that class):
## [codeblock]
## click / tap / SPACE / ENTER / ui_accept  -> first press completes the typewriter,
##                                             the next press advances to the next beat
## SKIP button, or HOLD ESC for 0.6s        -> abandon the whole scene, no confirmation
## [/codeblock]
## A tap on the SKIP button is a button press, not an advance: the button is added last so
## it sits in front of the click-catching root.
##
## THE CLOCK IS INJECTABLE. [method _process] only forwards its delta when [member auto_tick]
## is true; a test sets it false and calls [method advance_clock] at exact positions, so the
## typewriter can be driven to completion with no wall-clock waiting (tests/README.md rule 7).
## The ESC hold-to-skip timer rides the same clock, so it is testable the same way.
##
## PORTRAITS: resolved through [PortraitCache.get_portrait] (async by callback). Until -- or
## if -- a texture lands, the panel shows a monogram badge built from the speaker's initial,
## so a headless run, a missing model or a not-yet-captured portrait all render a real,
## correctly-sized panel rather than an empty hole. The callback is guarded on the panel
## still being valid AND still showing the same speaker, so a fast skip cannot paint a stale
## face into the next scene.
##
## TEARDOWN: finishing (read to the end OR skipped) hides the root, clears both portraits and
## emits [signal finished]. It does NOT free itself -- whoever mounted it owns its lifetime
## (see [CampaignController]), which is also what lets a test mount it under
## [code]add_child_autofree[/code] without a double disposal.

# --- Identity ----------------------------------------------------------------

## See the LAYER note in the class doc.
const LAYER_INDEX: int = 135

# --- Layout tunables (720p budget) -------------------------------------------

## Gap from the viewport edges to the portrait panels and the text box.
const EDGE_MARGIN: float = 18.0
const PORTRAIT_WIDTH: float = 168.0
const PORTRAIT_HEIGHT: float = 208.0
## Fixed text-box height. Fixed rather than content-sized so the box never jumps between a
## one-line and a three-line beat.
const TEXTBOX_HEIGHT: float = 132.0
## The ACTIVE speaker's panel sits this many pixels higher than the dimmed one -- the
## "slightly forward" read, done with position rather than scale so nothing resamples.
const ACTIVE_LIFT_PX: float = 10.0

# --- Presentation tunables ----------------------------------------------------

## Portrait slide-in duration. Skipped entirely (positions snapped) when animations are off.
const SLIDE_TIME: float = 0.25
## How long ESC must be held before the scene is abandoned.
const SKIP_HOLD_SECONDS: float = 0.6

## Full-bright active speaker; the beat's own [member StoryBeat.tint] multiplies over this.
const PORTRAIT_ACTIVE_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
## The listening speaker: pushed dark and slightly transparent so the active one reads first.
const PORTRAIT_DIM_MODULATE := Color(0.46, 0.42, 0.40, 0.92)

signal finished(skipped: bool)

# --- Clock injection ----------------------------------------------------------

## When false, [method _process] does not tick the sequencer -- the host (or a test) drives
## time with [method advance_clock]. See the class doc's clock note.
var auto_tick: bool = true

# --- State --------------------------------------------------------------------

var _sequencer: StorySequencer = StorySequencer.new()
var _scene: StoryScene = null
## Speaker id currently painted into each side ("" when the side is empty), so an async
## portrait callback can tell whether it is still wanted.
var _side_speaker: Dictionary = { StoryBeat.SIDE_LEFT: "", StoryBeat.SIDE_RIGHT: "" }
## The side the CURRENT beat speaks from, or "" on a narrator/portrait-less beat.
var _active_side: StringName = &""
var _esc_down: bool = false
var _esc_hold: float = 0.0
var _slide_tween: Tween = null
## Index of the last opened beat, kept only so a host can read where playback got to after
## a skip (see [method current_index]). Nothing in this file branches on it.
var _last_index: int = -1

# --- Nodes (built in _ready) --------------------------------------------------

var _root: Control = null
var _backdrop: ColorRect = null
## side -> PanelContainer. Names are suffixed Left/Right so no two siblings collide.
var _panels: Dictionary = {}
var _images: Dictionary = {}
var _monograms: Dictionary = {}
var _textbox: PanelContainer = null
var _name_plate: PanelContainer = null
var _name_label: Label = null
var _body_label: Label = null
var _advance_hint: Label = null
var _skip_button: Button = null


func _ready() -> void:
	name = "StoryDialogue"
	layer = LAYER_INDEX
	# The outro plays over a PAUSED tree (GameOverScreen pauses on reveal) -- keep ticking.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_ui()
	_connect_sequencer()
	_root.visible = false
	set_process(true)


# =============================================================================
#  Construction
# =============================================================================

func _build_ui() -> void:
	# Full-rect root. MOUSE_FILTER_STOP is what BLOCKS INPUT TO THE WORLD behind the
	# overlay -- a click anywhere that no child handled lands in _gui_input and advances,
	# and nothing falls through to the board or the menu underneath.
	_root = Control.new()
	_root.name = "StoryRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_gui_input)
	_root.resized.connect(_layout_portraits)
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "StoryBackdrop"
	_backdrop.color = Color(0.03, 0.02, 0.0, 0.55)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE, not STOP: the root above is the single click catcher, so the backdrop must
	# not swallow the event before _gui_input sees it.
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)

	_build_portrait(StoryBeat.SIDE_LEFT, "Left")
	_build_portrait(StoryBeat.SIDE_RIGHT, "Right")
	_build_textbox()
	_build_skip_button()

	_layout_portraits()


## One portrait panel. Anchors are left at TOP-LEFT and the panel is positioned/sized by
## [method _layout_portraits] instead: the slide-in tweens [code]position:x[/code], and a
## panel whose offsets are also being tracked by a bottom/right anchor is a fight between
## the tween and the anchor. Explicit placement keeps the animation authoritative.
func _build_portrait(side: StringName, suffix: String) -> void:
	var panel := PanelContainer.new()
	# Suffixed so the two siblings never collide (Godot silently mangles a duplicate name,
	# and a mangled name breaks every get_node path a test writes).
	panel.name = "PortraitPanel%s" % suffix
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(PORTRAIT_WIDTH, PORTRAIT_HEIGHT)
	panel.size = Vector2(PORTRAIT_WIDTH, PORTRAIT_HEIGHT)
	panel.add_theme_stylebox_override("panel", ConquestTheme.panel_box())
	panel.visible = false
	_root.add_child(panel)

	# The image and the monogram occupy the SAME slot; exactly one is visible. The monogram
	# is the standing fallback (headless, no model, capture still in flight) so the panel
	# always has rendered content -- see the class doc.
	var slot := Control.new()
	slot.name = "PortraitSlot%s" % suffix
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(PORTRAIT_WIDTH - 28.0, PORTRAIT_HEIGHT - 28.0)
	panel.add_child(slot)

	var image := TextureRect.new()
	image.name = "PortraitImage%s" % suffix
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.clip_contents = true
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.visible = false
	slot.add_child(image)

	var mono := Label.new()
	mono.name = "PortraitMonogram%s" % suffix
	mono.set_anchors_preset(Control.PRESET_FULL_RECT)
	mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mono.add_theme_font_size_override("font_size", 64)
	mono.add_theme_color_override("font_color", ConquestTheme.BROWN_DK)
	mono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mono.text = "?"
	slot.add_child(mono)

	_panels[side] = panel
	_images[side] = image
	_monograms[side] = mono


## The bottom text box: name plate over the body line, on the amber card.
##
## Anchored BOTTOM-WIDE with a FIXED height rather than sized to its content -- a box that
## grew and shrank between a one-line and a three-line beat would make the whole stage jump
## every advance. The body Label word-wraps inside it and is EXPAND_FILL, never clip_text
## (a clip_text Label reports a 1px minimum width, which collapses in any flow container).
func _build_textbox() -> void:
	_textbox = PanelContainer.new()
	_textbox.name = "StoryTextBox"
	_textbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_textbox.anchor_left = 0.0
	_textbox.anchor_right = 1.0
	_textbox.anchor_top = 1.0
	_textbox.anchor_bottom = 1.0
	_textbox.offset_left = EDGE_MARGIN
	_textbox.offset_right = -EDGE_MARGIN
	_textbox.offset_top = -(TEXTBOX_HEIGHT + EDGE_MARGIN)
	_textbox.offset_bottom = -EDGE_MARGIN
	_textbox.add_theme_stylebox_override("panel", ConquestTheme.panel_box())
	_root.add_child(_textbox)

	var column := VBoxContainer.new()
	column.name = "StoryTextColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	_textbox.add_child(column)

	# Name plate: a dark inset chip that hugs its text (SHRINK_BEGIN), so it is left-aligned
	# and only as wide as the name -- not stretched across the box by the VBox.
	_name_plate = PanelContainer.new()
	_name_plate.name = "StoryNamePlate"
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name_plate.add_theme_stylebox_override("panel", ConquestTheme.plate_box())
	column.add_child(_name_plate)

	_name_label = Label.new()
	_name_label.name = "StoryNameLabel"
	_name_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_HEADER)
	_name_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_plate.add_child(_name_label)

	_body_label = Label.new()
	_body_label.name = "StoryBodyLabel"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# EXPAND_FILL, so the label takes the box's remaining height instead of collapsing to
	# its own (line-height) minimum inside the VBox.
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_HEADER)
	_body_label.add_theme_color_override("font_color", ConquestTheme.INK)
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body_label)

	_advance_hint = Label.new()
	_advance_hint.name = "StoryAdvanceHint"
	_advance_hint.text = "▼  Click or press Space"
	_advance_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_advance_hint.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
	_advance_hint.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)
	_advance_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_advance_hint.visible = false
	column.add_child(_advance_hint)


## SKIP, top-right. Added LAST so it sits in front of the click-catching root and its press
## is a press rather than an advance.
func _build_skip_button() -> void:
	_skip_button = Button.new()
	_skip_button.name = "StorySkipButton"
	_skip_button.text = "SKIP"
	_skip_button.tooltip_text = "Skip this scene (or hold ESC)"
	_skip_button.set_meta("style_role", "secondary")
	_skip_button.anchor_left = 1.0
	_skip_button.anchor_right = 1.0
	_skip_button.anchor_top = 0.0
	_skip_button.anchor_bottom = 0.0
	_skip_button.offset_left = -110.0
	_skip_button.offset_right = -EDGE_MARGIN
	_skip_button.offset_top = EDGE_MARGIN
	_skip_button.offset_bottom = EDGE_MARGIN + 34.0
	ConquestTheme.apply_button_role(_skip_button)
	_skip_button.pressed.connect(_on_skip_pressed)
	_root.add_child(_skip_button)


func _connect_sequencer() -> void:
	_sequencer.beat_changed.connect(_on_beat_changed)
	_sequencer.reveal_completed.connect(_on_reveal_completed)
	_sequencer.finished.connect(_on_sequencer_finished)


# =============================================================================
#  Public API
# =============================================================================

## Play [param scene]. Returns false -- showing nothing, emitting nothing -- when there is
## nothing to play (null scene, or no non-null beats), so a caller can treat "no story
## authored" and "story finished" as the same branch without special-casing.
func play(scene: StoryScene) -> bool:
	_scene = scene
	_esc_down = false
	_esc_hold = 0.0

	if not _sequencer.start(scene):
		return false

	_root.visible = true
	_fire_cue(scene.music_cue)
	return true


## The beat state machine, exposed for a host that wants to read progress. Input should go
## through [method advance] / [method skip] rather than driving this directly.
func sequencer() -> StorySequencer:
	return _sequencer


## The one input entry point (see the class doc): completes the typewriter, else advances.
func advance() -> void:
	_sequencer.advance()
	_refresh_text()


## Abandon the scene. No confirmation by design.
func skip() -> void:
	_sequencer.skip()


## Drive the clock by [param delta] seconds: the typewriter and the ESC hold-to-skip timer.
## The injection point -- see the class doc. Also called by [method _process] when
## [member auto_tick] is on.
func advance_clock(delta: float) -> void:
	if _sequencer.is_finished():
		return
	if _esc_down:
		_esc_hold += delta
		if _esc_hold >= SKIP_HOLD_SECONDS:
			_esc_down = false
			_esc_hold = 0.0
			skip()
			return
	_sequencer.tick(delta)
	_refresh_text()


## Start / stop the ESC hold-to-skip timer. Split out of [method _unhandled_input] so the
## HOLD is a plain state change that [method advance_clock] runs down -- which means it is
## driveable from a test (and from a future gamepad binding) without synthesising input
## events, and the hold duration is measured on the injected clock like everything else.
func set_cancel_held(held: bool) -> void:
	_esc_down = held
	_esc_hold = 0.0


func _process(delta: float) -> void:
	if auto_tick:
		advance_clock(delta)


# --- Rendered-node accessors (the integration tests assert on these) ----------

## The portrait PanelContainer for [param side], or null for an unknown side.
func portrait_panel(side: StringName) -> PanelContainer:
	return _panels.get(side, null)


## True when [param side]'s portrait panel is currently on stage.
func is_side_visible(side: StringName) -> bool:
	var panel: PanelContainer = portrait_panel(side)
	return panel != null and panel.visible


## True when [param side] holds the speaker of the CURRENT beat (full-bright + lifted).
## False for the listening side, for a hidden side, and for every side on a narrator beat.
func is_side_active(side: StringName) -> bool:
	return is_side_visible(side) and _active_side == side


## True when [param side]'s panel is actually SHOWING something -- a resolved portrait
## texture, or the monogram badge that stands in for one. Exactly one of the two is up at a
## time, and which one depends on whether a capture has landed (never on the caller), so
## this is the honest "is that panel populated" question a test can ask.
func portrait_content_visible(side: StringName) -> bool:
	var image: TextureRect = _images.get(side, null)
	var mono: Label = _monograms.get(side, null)
	if image != null and image.visible and image.texture != null:
		return true
	return mono != null and mono.visible


func text_label() -> Label:
	return _body_label


func name_label() -> Label:
	return _name_label


func text_box() -> PanelContainer:
	return _textbox


func skip_button() -> Button:
	return _skip_button


## The full-rect input blocker. Hidden before the first [method play] and again on finish.
func root_control() -> Control:
	return _root


# =============================================================================
#  Sequencer reactions
# =============================================================================

func _on_beat_changed(index: int) -> void:
	var beat: StoryBeat = _sequencer.current_beat()
	if beat == null:
		return

	_fire_cue(beat.music_cue)

	if beat.hides_portraits():
		_active_side = &""
		_clear_portraits()
	else:
		_active_side = beat.resolved_side()
		_show_speaker(beat)

	_apply_portrait_states(beat)

	_name_label.text = beat.resolved_speaker_name()
	# A narrator beat has no plate at all -- an empty amber chip would read as a bug.
	_name_plate.visible = not _name_label.text.is_empty()
	_advance_hint.visible = false
	_refresh_text()
	# index is carried by the signal for hosts that log progress; nothing here needs it.
	_last_index = index


func _on_reveal_completed(_index: int) -> void:
	_refresh_text()
	_advance_hint.visible = true


func _on_sequencer_finished(skipped: bool) -> void:
	_teardown()
	finished.emit(skipped)


## Clear the stage: portraits released, text blanked, root hidden, tween killed. Called on
## every finish (read-through OR skip). Does NOT free this node -- see the class doc.
func _teardown() -> void:
	_kill_tween()
	_clear_portraits()
	_active_side = &""
	_esc_down = false
	_esc_hold = 0.0
	_body_label.text = ""
	_name_label.text = ""
	_name_plate.visible = false
	_advance_hint.visible = false
	_root.visible = false


func _refresh_text() -> void:
	_body_label.text = _sequencer.visible_text()


# =============================================================================
#  Portrait staging
# =============================================================================

## Bring [param beat]'s speaker onto their side, sliding the panel in when it was not
## already there. The OPPOSITE side is left exactly as it is -- that persistence is what
## makes a two-hander read as a conversation rather than a slideshow.
func _show_speaker(beat: StoryBeat) -> void:
	var side: StringName = beat.resolved_side()
	var speaker: String = String(beat.speaker_id)
	var panel: PanelContainer = _panels.get(side, null)
	if panel == null:
		return

	var was_on_stage: bool = panel.visible and String(_side_speaker.get(side, "")) == speaker

	if String(_side_speaker.get(side, "")) != speaker:
		_side_speaker[side] = speaker
		_set_monogram(side, beat.resolved_speaker_name())
		_request_portrait(side, speaker)

	panel.visible = true
	if not was_on_stage:
		_slide_in(side)


## Request [param speaker]'s portrait. The callback is guarded twice -- the node must still
## be valid, and that side must still be showing the SAME speaker -- so a fast skip or a
## quick two-beat swap can never paint a stale face. A null texture (headless, no model,
## capture failed) simply leaves the monogram badge up.
func _request_portrait(side: StringName, speaker: String) -> void:
	var image: TextureRect = _images.get(side, null)
	if image == null:
		return
	image.texture = null
	image.visible = false
	if speaker.is_empty():
		return

	PortraitCache.get_portrait(speaker, func(tex: Texture2D) -> void:
		if not is_instance_valid(self) or tex == null:
			return
		if String(_side_speaker.get(side, "")) != speaker:
			return
		var target: TextureRect = _images.get(side, null)
		if target == null or not is_instance_valid(target):
			return
		target.texture = tex
		target.visible = true
		var mono: Label = _monograms.get(side, null)
		if mono != null and is_instance_valid(mono):
			mono.visible = false
	)


func _set_monogram(side: StringName, display_name: String) -> void:
	var mono: Label = _monograms.get(side, null)
	if mono == null:
		return
	mono.text = display_name.substr(0, 1).to_upper() if not display_name.is_empty() else "?"
	mono.visible = true


## Full-bright + lifted for the speaker, dimmed + settled for the listener. The beat's
## [member StoryBeat.tint] multiplies over the ACTIVE modulate only -- a tint on a dimmed
## listener would just muddy it.
func _apply_portrait_states(beat: StoryBeat) -> void:
	for side in [StoryBeat.SIDE_LEFT, StoryBeat.SIDE_RIGHT]:
		var panel: PanelContainer = _panels.get(side, null)
		if panel == null or not panel.visible:
			continue
		var active: bool = (side == _active_side)
		panel.modulate = (PORTRAIT_ACTIVE_MODULATE * beat.tint) if active else PORTRAIT_DIM_MODULATE
		panel.position.y = _panel_rest_y() - (ACTIVE_LIFT_PX if active else 0.0)


func _clear_portraits() -> void:
	for side in [StoryBeat.SIDE_LEFT, StoryBeat.SIDE_RIGHT]:
		var panel: PanelContainer = _panels.get(side, null)
		if panel != null:
			panel.visible = false
		var image: TextureRect = _images.get(side, null)
		if image != null:
			image.texture = null
			image.visible = false
		_side_speaker[side] = ""


# =============================================================================
#  Layout + slide-in
# =============================================================================

## Place both panels at their resting positions. Called at build time and on every root
## resize, so a window/orientation change re-lands them instead of leaving them mid-slide.
func _layout_portraits() -> void:
	if _root == null:
		return
	for side in [StoryBeat.SIDE_LEFT, StoryBeat.SIDE_RIGHT]:
		var panel: PanelContainer = _panels.get(side, null)
		if panel == null:
			continue
		panel.size = Vector2(PORTRAIT_WIDTH, PORTRAIT_HEIGHT)
		panel.position = Vector2(_panel_rest_x(side), _panel_rest_y())


## Resting X: hard against the left edge, or the mirror of that on the right.
func _panel_rest_x(side: StringName) -> float:
	if side == StoryBeat.SIDE_RIGHT:
		return maxf(EDGE_MARGIN, _root.size.x - EDGE_MARGIN - PORTRAIT_WIDTH)
	return EDGE_MARGIN


## Offstage X: fully outside its own edge, so the slide starts from beyond the frame.
func _panel_offstage_x(side: StringName) -> float:
	if side == StoryBeat.SIDE_RIGHT:
		return _root.size.x + EDGE_MARGIN
	return -(PORTRAIT_WIDTH + EDGE_MARGIN)


## Resting Y: sitting directly on top of the text box.
func _panel_rest_y() -> float:
	return maxf(0.0, _root.size.y - TEXTBOX_HEIGHT - EDGE_MARGIN - PORTRAIT_HEIGHT - 6.0)


## Slide [param side]'s panel in from its own edge. ANIMATIONS OFF snaps it into place with
## NO tween created at all -- the rule every animating system here follows (see
## [code]GameOverScreen._reveal_summary_card[/code], [code]ItemToast._animations_on[/code]).
func _slide_in(side: StringName) -> void:
	var panel: PanelContainer = _panels.get(side, null)
	if panel == null:
		return
	var rest_x: float = _panel_rest_x(side)
	if not _animations_on():
		panel.position.x = rest_x
		return

	panel.position.x = _panel_offstage_x(side)
	_kill_tween()
	_slide_tween = create_tween()
	# The outro plays over a paused tree -- the tween has to keep running through it.
	_slide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_slide_tween.tween_property(panel, "position:x", rest_x, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _kill_tween() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = null


## True when the player has animations enabled (defaults to on when GameSettings is absent,
## e.g. a bare test harness) -- mirrors [code]GameOverScreen._animations_on[/code].
func _animations_on() -> bool:
	if typeof(GameSettings) != TYPE_OBJECT or GameSettings == null:
		return true
	if not GameSettings.has_method("animations_on"):
		return true
	return bool(GameSettings.animations_on())


# =============================================================================
#  Input
# =============================================================================

## A click anywhere no child handled = advance. The SKIP button is a child added after this
## root's other children, so its press is consumed there and never reaches here.
func _on_root_gui_input(event: InputEvent) -> void:
	if _sequencer.is_finished():
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_root.accept_event()
		advance()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_root.accept_event()
		advance()


## Keyboard/controller: ui_accept (Space/Enter/A) advances; ui_cancel (ESC) starts the
## hold-to-skip timer, which [method advance_clock] runs down. Consuming the events keeps
## them off the screen behind the overlay -- the input-blocking half that _gui_input's STOP
## filter does not cover.
func _unhandled_input(event: InputEvent) -> void:
	if _sequencer.is_finished() or not _root.visible:
		return

	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		advance()
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		set_cancel_held(true)
		return

	if event.is_action_released("ui_cancel"):
		get_viewport().set_input_as_handled()
		set_cancel_held(false)


func _on_skip_pressed() -> void:
	skip()


# =============================================================================
#  Audio
# =============================================================================

## Fire one authored cue through [AudioManager]. An unmapped event no-ops inside the
## manager, so an authored-but-unassigned cue is safe; a bare harness with no autoload
## simply plays nothing.
func _fire_cue(cue: StringName) -> void:
	if String(cue).is_empty():
		return
	if typeof(AudioManager) != TYPE_OBJECT or AudioManager == null:
		return
	if not AudioManager.has_method("play_sfx"):
		return
	AudioManager.play_sfx(cue)


## The beat index currently (or last) on screen.
func current_index() -> int:
	return _last_index
