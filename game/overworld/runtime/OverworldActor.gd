class_name OverworldActor
extends Node3D

## One thing standing on the overworld: the player's hero, an NPC, a sign, a chest, the
## Wayshrine. Logic lives in cells (the controller + [OverworldGrid]); this node is the VISUAL:
## a model that tweens between cells (grid-locked with smooth interpolation, the Gen 3-5 read),
## turns via [UnitFacing] (+Z = south, model yaw composed with the facing), plays "idle" / "walk"
## clips when the model has them, and pops an emote bubble.
##
## Animations off (Settings) -> every move / turn / bubble is instant, so headless tests run
## without wall-clock waits. Skeletal clips still play: they cost no wall-clock time, and gating
## them left the hero stepping in its idle pose whenever the (persisted) switch was off.

## Feet height over a tile (MapLoader.UNIT_GROUND_Y).
const GROUND_Y: float = 0.1
const TURN_TIME: float = 0.08
const CLIP_BLEND: float = 0.15

## Locomotion clips (looped by this node: glTF imports them LOOP_NONE, which froze idle after its
## 4 s and dropped walk out mid-streak every 1.125 s).
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_RUN := "run"
## Walk pace the run threshold derives from: StoryRuleset.walk_step_seconds (shipped 0.22 s/cell
## = 4.55 cells/s). The controller copies the live ruleset value into [member walk_step_seconds].
const DEFAULT_WALK_STEP_SECONDS: float = 0.22
## "Run speed" knob: a step at least this many times faster than walk pace asks for "run"
## (falling back to "walk" when the model has no run clip). Shipped run_step_seconds 0.12 is
## 1.83x walk pace; 1.3x sits between, so a small walk retune never flips a walk into a run.
const RUN_SPEED_FACTOR: float = 1.3

signal walk_finished

var entity_id: String = ""
var cell: Vector3i = Vector3i.ZERO
var facing: Vector2i = Vector2i(0, 1)
## The model's authored yaw correction (CharacterResource / HeroResource model_yaw_deg).
var model_yaw_deg: float = 0.0
var is_walking: bool = false
## Seconds per cell at walk pace (the run threshold's reference, see [constant RUN_SPEED_FACTOR]).
var walk_step_seconds: float = DEFAULT_WALK_STEP_SECONDS
## Return to idle when a walk ends and no further step was chained from walk_finished. Off for the
## hero: the controller settles it when the walk STREAK ends (no idle flicker between steps).
var settle_on_arrival: bool = true

var _model: Node3D = null
var _anim: AnimationPlayer = null
## The looped locomotion clip currently wanted ("" = none); replayed on animation_finished.
var _loop_clip: String = ""
## Bumped by every walk_to, so arrival can tell whether a listener chained another step.
var _step_serial: int = 0
var _move_tween: Tween = null
var _turn_tween: Tween = null
var _bubble: Label3D = null


## Put [param model] (feet at origin, facing +Z after [param yaw_deg]) in this actor.
func set_model(model: Node3D, yaw_deg: float = 0.0, model_scale: float = 1.0) -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = model
	model_yaw_deg = yaw_deg
	if model == null:
		return
	model.name = "Model"
	if model_scale != 1.0:
		model.scale = Vector3.ONE * model_scale
	add_child(model)
	_anim = _find_anim_player(model)
	_loop_clip = ""
	if _anim != null:
		_anim.animation_finished.connect(_on_clip_finished)
	_apply_facing_now()
	play_clip(CLIP_IDLE)


## A roster model (CharacterResource) as this actor's body.
func set_character_model(character: CharacterResource) -> bool:
	if character == null or character.model_scene == null:
		return false
	var inst := character.model_scene.instantiate() as Node3D
	if inst == null:
		return false
	set_model(inst, character.model_yaw_deg, character.model_scale)
	return true


func model() -> Node3D:
	return _model


func place(c: Vector3i) -> void:
	cell = c
	_kill_move()
	position = world_of(c)


static func world_of(c: Vector3i) -> Vector3:
	return Cells.cell_to_world(c) + Vector3(0, GROUND_Y, 0)


func set_facing(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	facing = dir
	_apply_facing_now()


## Turn smoothly (instant with animations off).
func turn_to(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO or dir == facing:
		return
	facing = dir
	if _model == null:
		return
	if not _anims_on():
		_apply_facing_now()
		return
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	var target: float = UnitFacing.model_yaw(model_yaw_deg, dir)
	var from: float = _model.rotation.y
	var delta: float = wrapf(target - from, -PI, PI)
	_turn_tween = create_tween()
	_turn_tween.tween_property(_model, "rotation:y", from + delta, TURN_TIME)


func face_cell(target: Vector3i) -> void:
	var d := Vector2i(target.x - cell.x, target.y - cell.y)
	if d == Vector2i.ZERO:
		return
	if absi(d.x) >= absi(d.y):
		turn_to(Vector2i(signi(d.x), 0))
	else:
		turn_to(Vector2i(0, signi(d.y)))


func _apply_facing_now() -> void:
	if _model != null:
		_model.rotation.y = UnitFacing.model_yaw(model_yaw_deg, facing)


## Walk one cell to [param to] over [param seconds]; emits [signal walk_finished]. Turns first.
func walk_to(to: Vector3i, seconds: float) -> void:
	var dir := Vector2i(signi(to.x - cell.x), signi(to.y - cell.y))
	if dir != Vector2i.ZERO:
		turn_to(dir)
	cell = to
	_kill_move()
	_step_serial += 1
	play_clip(locomotion_clip(seconds), CLIP_WALK)
	if not _anims_on() or seconds <= 0.0:
		position = world_of(to)
		is_walking = false
		call_deferred("_on_walk_done")
		return
	is_walking = true
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", world_of(to), seconds)
	_move_tween.finished.connect(_on_walk_done, CONNECT_ONE_SHOT)


## "run" when a step of [param seconds] per cell beats walk pace by [constant RUN_SPEED_FACTOR],
## else "walk" (play_clip falls back to "walk" when the model has no run clip).
func locomotion_clip(seconds: float) -> String:
	if seconds > 0.0 and walk_step_seconds > 0.0 \
			and (1.0 / seconds) > RUN_SPEED_FACTOR / walk_step_seconds:
		return CLIP_RUN
	return CLIP_WALK


func _on_walk_done() -> void:
	is_walking = false
	var serial: int = _step_serial
	walk_finished.emit()
	# A listener that chains the next step does so synchronously inside the emit.
	if settle_on_arrival and serial == _step_serial:
		settle()


## Called by the controller when a walk streak ends (no key held) so the model settles.
func settle() -> void:
	play_clip(CLIP_IDLE)


func _kill_move() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
	is_walking = false


## Pop [param glyph] ("!", "?", "...") above the actor for a moment. Awaitable: returns once
## the bubble has been read (instant with animations off).
func emote(glyph: String) -> void:
	if _bubble == null or not is_instance_valid(_bubble):
		_bubble = Label3D.new()
		_bubble.name = "Emote"
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.no_depth_test = true
		_bubble.font = MenuTheme.display_font(0)
		_bubble.font_size = 96
		_bubble.outline_size = 22
		_bubble.modulate = MenuTheme.GOLD_LITE
		_bubble.outline_modulate = Color(0.1, 0.07, 0.03)
		_bubble.pixel_size = 0.011
		_bubble.position = Vector3(0, 2.55, 0)
		add_child(_bubble)
	_bubble.text = glyph
	_bubble.visible = true
	if not _anims_on() or not is_inside_tree():
		_bubble.visible = false
		return
	_bubble.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(_bubble, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55)
	await tw.finished
	if is_instance_valid(_bubble):
		_bubble.visible = false


## True while an emote bubble is up (screenshots / tests).
func bubble_visible() -> bool:
	return _bubble != null and is_instance_valid(_bubble) and _bubble.visible


# --- Clips ------------------------------------------------------------------------

## Play the model's clip for [param base] (else [param fallback]); idle / walk / run loop.
## Returns true when a clip resolved. Not gated on the animations switch (see the class doc).
func play_clip(base: String, fallback: String = "") -> bool:
	if _anim == null:
		return false
	var clip: String = _find_clip(base)
	var resolved: String = base
	if clip.is_empty() and not fallback.is_empty():
		clip = _find_clip(fallback)
		resolved = fallback
	if clip.is_empty():
		return false
	_loop_clip = clip if resolved in [CLIP_IDLE, CLIP_WALK, CLIP_RUN] else ""
	if _anim.current_animation == clip and _anim.is_playing():
		return true
	_anim.play(clip, CLIP_BLEND)
	return true


func _on_clip_finished(anim_name: StringName) -> void:
	if _anim != null and not _loop_clip.is_empty() and String(anim_name) == _loop_clip:
		_anim.play(_loop_clip)


func _find_clip(base: String) -> String:
	if _anim == null:
		return ""
	var names: PackedStringArray = _anim.get_animation_list()
	for n in names:
		if String(n).to_lower() == base:
			return String(n)
	for n in names:
		if String(n).to_lower().contains(base):
			return String(n)
	return ""


static func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found != null:
			return found
	return null


func _anims_on() -> bool:
	var gs := get_node_or_null("/root/GameSettings") if is_inside_tree() else null
	if gs == null or not gs.has_method("animations_on"):
		return true
	return bool(gs.animations_on())
