class_name OverworldActor
extends Node3D

## One thing standing on the overworld: the player's hero, an NPC, a sign, a chest, the
## Wayshrine. Logic lives in cells (the controller + [OverworldGrid]); this node is the VISUAL:
## a model that tweens between cells (grid-locked with smooth interpolation, the Gen 3-5 read;
## or one continuous glide across a chained streak under the shipped feel, [OverworldFeel]),
## turns via [UnitFacing] (+Z = south, model yaw composed with the facing), plays "idle" / "walk"
## clips when the model has them, and pops an emote bubble.
##
## Animations off (Settings) -> every move / turn / bubble is instant, so headless tests run
## without wall-clock waits. Skeletal clips still play: they cost no wall-clock time, and gating
## them left the hero stepping in its idle pose whenever the (persisted) switch was off.

## Feet height over a tile (MapLoader.UNIT_GROUND_Y).
const GROUND_Y: float = 0.1
const TURN_TIME: float = 0.08
## Crossfade on a clip CHANGE (idle <-> walk <-> run). A loop wrap never blends: the locomotion
## clips loop natively (see [method _loop_locomotion]).
const CLIP_BLEND: float = 0.15

## Locomotion clips. glTF imports them LOOP_NONE (idle froze after its 4 s, walk dropped out
## mid-streak every 1.125 s); each actor wears a LOOP_LINEAR copy (see [method _loop_locomotion]).
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_RUN := "run"
const LOCOMOTION_CLIPS: Array[String] = [CLIP_IDLE, CLIP_WALK, CLIP_RUN]
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

## OVERWORLD FEEL knobs ([OverworldFeel], applied by the controller; the defaults are the
## "current" feel). continuous_glide: false = a Tween per cell (it ends on a frame boundary and
## the next cell starts a frame later from the exact centre: a per-cell hitch); true = a
## constant-speed integrator whose leftover time on the arrival frame carries into a step
## chained from [signal walk_finished] (same frame), so a held streak moves at one speed.
var continuous_glide: bool = false
## Seconds of a turn's rotation blend, and whether it eases out (snappy start) or is linear.
var turn_time: float = TURN_TIME
var turn_ease_out: bool = false
## Playback rate of the walk / run clips: the feel picks ground speed = stride / cycle x rate,
## so the clip must play at the same rate for the planted foot to hold still.
var walk_clip_rate: float = 1.0
var run_clip_rate: float = 1.0
## World velocity of the current continuous glide or free walk (zero otherwise) -- the camera's
## look-ahead.
var glide_velocity: Vector3 = Vector3.ZERO
## FREE MOVEMENT clip matching ([method free_pose]): the walk / run clips' own ground speeds at
## 1.0x (stride / cycle), and the ground speed above which the run clip replaces the walk clip.
var walk_clip_native_mps: float = 0.0
var run_clip_native_mps: float = 0.0
var run_clip_above_mps: float = INF

var _model: Node3D = null
var _anim: AnimationPlayer = null
## Source AnimationLibrary -> its copy with the locomotion clips LOOP_LINEAR. One copy per model,
## shared by every actor wearing it; the imported library itself is never touched (the battle
## UnitAnimator plays the same glbs' walk ONE-SHOT and queues idle behind it).
static var _looped_libraries: Dictionary = {}
## Bumped by every walk_to, so arrival can tell whether a listener chained another step.
var _step_serial: int = 0
var _move_tween: Tween = null
var _turn_tween: Tween = null
var _bubble: Label3D = null
## Continuous glide state (see [member continuous_glide]).
var _gliding: bool = false
var _glide_from: Vector3 = Vector3.ZERO
var _glide_to: Vector3 = Vector3.ZERO
var _glide_t: float = 0.0
var _glide_dur: float = 0.0
## Seconds of the arrival frame left over past the cell centre; only non-zero during the
## arrival's walk_finished emit, where a chained walk_to consumes it.
var _glide_carry: float = 0.0


func _ready() -> void:
	# Idle actors cost nothing per frame; walk_to switches processing on for a glide.
	set_process(_gliding)


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
	if _anim != null:
		_loop_locomotion(_anim)
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
	var tw: PropertyTweener = _turn_tween.tween_property(_model, "rotation:y", from + delta, turn_time)
	if turn_ease_out:
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
	var carry: float = _glide_carry
	_glide_carry = 0.0
	_kill_move()
	_step_serial += 1
	_reset_clip_speed()
	play_clip(locomotion_clip(seconds), CLIP_WALK)
	if not _anims_on() or seconds <= 0.0:
		position = world_of(to)
		is_walking = false
		call_deferred("_on_walk_done")
		return
	is_walking = true
	if continuous_glide:
		_glide_from = position
		_glide_to = world_of(to)
		_glide_dur = seconds
		_glide_t = minf(carry, seconds)
		glide_velocity = (_glide_to - _glide_from) / seconds
		position = _glide_from.lerp(_glide_to, _glide_t / _glide_dur)
		_gliding = true
		set_process(true)
		return
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
	_reset_clip_speed()
	play_clip(CLIP_IDLE)


## FREE MOVEMENT pose ([HeroMover], the hero under a "free" feel): the controller integrates
## the position; the actor takes it, turns the model to [param heading] (world radians,
## atan2(x, z) -- any angle, not just the four facings), records the cardinal [param facing_dir]
## for Confirm / doors / trainers, and plays idle / walk / run with the clip speed matched to
## the ground speed (rate = speed / the clip's own stride speed), so the planted foot holds at
## every speed an analog stick or the ease-in passes through.
func free_pose(pos: Vector3, heading: float, velocity: Vector3, facing_dir: Vector2i) -> void:
	if _move_tween != null or _gliding:
		_kill_move()
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_tween = null
	position = pos
	glide_velocity = velocity
	if facing_dir != Vector2i.ZERO:
		facing = facing_dir
	if _model != null:
		_model.rotation.y = deg_to_rad(model_yaw_deg) + heading
	var s: float = Vector2(velocity.x, velocity.z).length()
	if s < HeroMover.REST_SPEED:
		settle()
		return
	var base: String = CLIP_RUN if s > run_clip_above_mps else CLIP_WALK
	if not play_clip(base, CLIP_WALK) or _anim == null:
		return
	var resolved: String = base if not _find_clip(base).is_empty() else CLIP_WALK
	var native: float = run_clip_native_mps if resolved == CLIP_RUN else walk_clip_native_mps
	if native <= 0.0:
		return
	# play_clip started the clip at clip_rate(resolved); speed_scale scales that to this speed.
	var started: float = clip_rate(resolved)
	_anim.speed_scale = (s / native) / started if started > 0.0 else 1.0


func _reset_clip_speed() -> void:
	if _anim != null:
		_anim.speed_scale = 1.0


func _kill_move() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
	is_walking = false
	_gliding = false
	glide_velocity = Vector3.ZERO


## The continuous glide: constant speed from cell to cell. On the arrival frame the time past
## the centre is kept in [member _glide_carry] while walk_finished fires; a step chained from
## that signal (the controller's held key / tap path) starts already that far along, so the
## streak's speed never dips at a cell boundary.
func _process(delta: float) -> void:
	if not _gliding:
		set_process(false)
		return
	_glide_t += delta
	if _glide_t < _glide_dur:
		position = _glide_from.lerp(_glide_to, _glide_t / _glide_dur)
		return
	var carry: float = _glide_t - _glide_dur
	position = _glide_to
	_gliding = false
	glide_velocity = Vector3.ZERO
	_glide_carry = carry
	_on_walk_done()
	_glide_carry = 0.0
	if not _gliding:
		set_process(false)


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
## Returns true when a clip resolved. Re-asking for the clip already playing is a no-op, so a
## per-cell walk_to never restarts or re-blends the cycle. Not gated on the animations switch
## (see the class doc).
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
	if _anim.current_animation == clip and _anim.is_playing():
		return true
	_anim.play(clip, CLIP_BLEND, clip_rate(resolved))
	return true


## Jump the clip now playing to [param fraction] (0..1) of its length -- so a crowd wearing the
## same model does not idle in lockstep. No-op without a playing clip.
func offset_clip(fraction: float) -> void:
	if _anim == null or not _anim.is_playing():
		return
	var length: float = _anim.current_animation_length
	if length > 0.0:
		_anim.seek(fposmod(fraction, 1.0) * length, true)


## Playback rate for locomotion clip [param base] (the feel's stride-matched walk / run rate).
func clip_rate(base: String) -> float:
	if base == CLIP_WALK:
		return walk_clip_rate
	if base == CLIP_RUN:
		return run_clip_rate
	return 1.0


## Swap [param anim]'s libraries for copies whose idle / walk / run clips loop natively
## (LOOP_LINEAR: the wrap is seamless inside the AnimationPlayer -- no animation_finished,
## no replay, no dead frames at the seam). Copies are cached per source library.
func _loop_locomotion(anim: AnimationPlayer) -> void:
	var want: Dictionary = {}  # library name -> clip names in it to loop
	for base in LOCOMOTION_CLIPS:
		var full: String = _find_clip_in(anim, base)
		if full.is_empty():
			continue
		var lib_name: String = full.get_slice("/", 0) if full.contains("/") else ""
		var clip_name: String = full.get_slice("/", 1) if full.contains("/") else full
		if not want.has(lib_name):
			want[lib_name] = []
		(want[lib_name] as Array).append(clip_name)
	for lib_name in want:
		var src: AnimationLibrary = anim.get_animation_library(lib_name)
		if src == null:
			continue
		var looped: AnimationLibrary = _looped_libraries.get(src, null)
		if looped == null:
			looped = _looped_copy(src, want[lib_name])
			_looped_libraries[src] = looped
		if looped != src:
			anim.remove_animation_library(lib_name)
			anim.add_animation_library(lib_name, looped)


## [param src] with [param clips] replaced by LOOP_LINEAR duplicates (the others shared), or
## [param src] itself when every one of them already loops.
static func _looped_copy(src: AnimationLibrary, clips: Array) -> AnimationLibrary:
	var needs: bool = false
	for n in clips:
		if src.get_animation(n).loop_mode == Animation.LOOP_NONE:
			needs = true
	if not needs:
		return src
	var out := AnimationLibrary.new()
	for n in src.get_animation_list():
		var a: Animation = src.get_animation(n)
		if String(n) in clips and a.loop_mode == Animation.LOOP_NONE:
			a = a.duplicate() as Animation
			a.loop_mode = Animation.LOOP_LINEAR
		out.add_animation(n, a)
	return out


func _find_clip(base: String) -> String:
	return _find_clip_in(_anim, base)


static func _find_clip_in(anim: AnimationPlayer, base: String) -> String:
	if anim == null:
		return ""
	var names: PackedStringArray = anim.get_animation_list()
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
