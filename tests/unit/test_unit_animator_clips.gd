extends GutTest

# The authored-clip bridge: when a character's model ships an AnimationPlayer,
# game events play its clips; when it does not, the procedural tweens still run.
#
# The fiddly part is NAME MATCHING. Exporters rarely emit the bare word: glTF
# commonly writes "Armature|Idle", and casing varies by artist. If matching were
# strict, every rigged model would silently fall back to capsule tweens.

const Guard := preload("res://tests/helpers/global_state_guard.gd")

var animator: Node
## Pins animations ON for the suite: play_clip is a no-op with animations disabled,
## and the machine's REAL user://settings.cfg may carry animations_enabled=false
## (a player preference) -- tests must never inherit that. Restored in after_each.
var _guard


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", true)
	animator = load("res://game/visuals/UnitAnimator.gd").new()
	add_child_autofree(animator)


func after_each() -> void:
	_guard.restore()


func _player_with(clip_names: Array) -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for n in clip_names:
		lib.add_animation(String(n), Animation.new())
	ap.add_animation_library("", lib)
	add_child_autofree(ap)
	return ap


# --- clip name resolution ------------------------------------------------------

func test_matches_an_exact_clip_name() -> void:
	var ap := _player_with(["idle", "walk"])
	assert_eq(animator._find_clip(ap, "idle"), "idle")


func test_matches_regardless_of_case() -> void:
	var ap := _player_with(["Idle", "Walk"])
	assert_eq(animator._find_clip(ap, "idle"), "Idle", "artists capitalise inconsistently")


func test_matches_gltf_armature_prefixed_names() -> void:
	# This is what a Blender glTF export actually produces.
	var ap := _player_with(["Armature|Idle", "Armature|Attack"])
	assert_eq(animator._find_clip(ap, "idle"), "Armature|Idle")
	assert_eq(animator._find_clip(ap, "attack"), "Armature|Attack")


func test_returns_empty_when_the_clip_is_absent() -> void:
	var ap := _player_with(["idle"])
	assert_eq(animator._find_clip(ap, "death"), "", "missing clip must report absence, not guess")


func test_null_player_is_safe() -> void:
	assert_eq(animator._find_clip(null, "idle"), "")


# --- playing -------------------------------------------------------------------

func test_play_clip_reports_false_without_a_player() -> void:
	var bare := Node3D.new()
	add_child_autofree(bare)
	assert_false(animator.play_clip(bare, animator.CLIP_IDLE),
		"a capsule unit must report no clip so the tween fallback runs")


func test_play_clip_plays_and_reports_true() -> void:
	var unit := Node3D.new()
	add_child_autofree(unit)
	var ap := _player_with(["Armature|Walk", "Armature|Idle"])
	ap.reparent(unit)
	assert_true(animator.play_clip(unit, animator.CLIP_WALK))
	# current_animation is a StringName; compare as String.
	assert_string_contains(String(ap.current_animation), "Walk")


func test_missing_clip_falls_back_rather_than_playing_something_else() -> void:
	var unit := Node3D.new()
	add_child_autofree(unit)
	var ap := _player_with(["Armature|Idle"])
	ap.reparent(unit)
	assert_false(animator.play_clip(unit, animator.CLIP_DEATH),
		"no death clip => report false so the shrink tween still happens")


func test_disabling_authored_clips_forces_the_procedural_path() -> void:
	var unit := Node3D.new()
	add_child_autofree(unit)
	var ap := _player_with(["idle", "walk"])
	ap.reparent(unit)
	animator.use_authored_clips = false
	assert_false(animator.play_clip(unit, animator.CLIP_WALK))


func test_anim_player_lookup_is_cached_including_the_miss() -> void:
	var bare := Node3D.new()
	add_child_autofree(bare)
	assert_null(animator._anim_player_for(bare))
	assert_true(animator._anim_players.has(bare.get_instance_id()),
		"a MISS must be cached too, or every event re-walks the subtree")
