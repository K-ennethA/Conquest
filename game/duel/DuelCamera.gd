extends Camera3D
class_name DuelCamera

## The duel's fixed camera rig (docs/design/DUEL_BATTLE.md §6.1). M1 ships the NEUTRAL shot
## -- behind and left of station A, looking across to B, so the player's unit sits near-left
## and the foe far-right (the genre's framing) -- plus a short punch-in on the acting unit
## and [method impulse_shake] (FloatingCombatText kicks it on a crit). The full shot list
## (establishing orbit, ultimate dolly, KO push) is M2.
##
## Presentation only: nothing here reads a gameplay RNG or writes state (the shake is a
## deterministic wobble), so replays and network play never see it.

## Neutral framing, relative to station A (world) and the A->B axis.
@export var back_offset: float = 5.0        ## behind A along the A->B axis
@export var side_offset: float = 9.0        ## toward the viewer (+Z)
@export var height: float = 4.0
@export var look_bias: float = 0.5         ## where on A->B the camera looks (0 = A, 1 = B)
@export var look_height: float = -0.3
@export var neutral_fov: float = 36.0

var _base: Transform3D = Transform3D.IDENTITY
var _shake: float = 0.0
var _shake_t: float = 0.0
var _punch_tween: Tween = null


func _ready() -> void:
	fov = neutral_fov
	current = true


## Put the camera on its neutral shot for stations at [param a] and [param b] (world).
func frame(a: Vector3, b: Vector3) -> void:
	var axis := (b - a)
	axis.y = 0.0
	var dir := axis.normalized() if axis.length() > 0.001 else Vector3.RIGHT
	var side := Vector3(-dir.z, 0.0, dir.x)  # 90 degrees toward +Z for an A->B along +X
	var eye := a - dir * back_offset + side * side_offset + Vector3.UP * height
	var target := a.lerp(b, look_bias) + Vector3.UP * look_height
	_base = Transform3D(Basis.IDENTITY, eye).looking_at(target, Vector3.UP)
	transform = _base
	fov = neutral_fov


## A short punch-in (narrower FOV) for a cast; [param seconds] scaled by the caller.
func punch(seconds: float = 0.35, amount: float = 5.0) -> void:
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	if seconds <= 0.0:
		fov = neutral_fov
		return
	_punch_tween = create_tween()
	_punch_tween.tween_property(self, "fov", neutral_fov - amount, seconds * 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(self, "fov", neutral_fov, seconds * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The hook FloatingCombatText (and the stage, on a KO) kicks: a short decaying wobble.
func impulse_shake(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))
	_shake_t = 0.0


func _process(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake_t += delta
	_shake = maxf(0.0, _shake - delta * 2.5)
	var amp := _shake * 0.18
	var offset := Vector3(sin(_shake_t * 47.0), sin(_shake_t * 61.0 + 1.3) * 0.6, 0.0) * amp
	transform = Transform3D(_base.basis, _base.origin + _base.basis * offset)
	if _shake <= 0.0:
		transform = _base
