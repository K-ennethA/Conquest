extends GutTest

## The global animation-busy registry on UnitAnimator: the poll-based "is the
## screen still animating?" signal the AI driver waits on so the enemy never acts
## on top of the player's still-playing attack/hit/death animation.
##
## The registry is STATIC (statics can't emit signals, so the consumer polls) and
## its whole safety story is that it can never wedge the game: every entry carries
## an EXPIRY, so a lost finish callback simply expires instead of freezing the AI.
## These tests pin count-up/count-down, expiry, and the trivial empty case, plus the
## real tween `finished` callback clearing an entry.

const ANIMATOR = preload("res://game/visuals/UnitAnimator.gd")


func before_each() -> void:
	# Statics persist across instances/tests, so start each test from a clean slate.
	ANIMATOR._clear_anim_registry()


func after_each() -> void:
	ANIMATOR._clear_anim_registry()


# --- empty / count up / count down --------------------------------------------

func test_empty_registry_is_quiet() -> void:
	assert_false(ANIMATOR.is_any_animation_playing(),
		"an empty registry must report no animation playing")


func test_begin_marks_busy_and_end_clears() -> void:
	var token: int = ANIMATOR._anim_begin(1.0)
	assert_true(ANIMATOR.is_any_animation_playing(),
		"a registered animation must read as busy")
	ANIMATOR._anim_end(token)
	assert_false(ANIMATOR.is_any_animation_playing(),
		"ending the only animation must go quiet again")


func test_two_animations_one_end_still_busy() -> void:
	var a: int = ANIMATOR._anim_begin(1.0)
	var b: int = ANIMATOR._anim_begin(1.0)
	assert_true(ANIMATOR.is_any_animation_playing())
	ANIMATOR._anim_end(a)
	assert_true(ANIMATOR.is_any_animation_playing(),
		"still busy while the second animation is in flight")
	ANIMATOR._anim_end(b)
	assert_false(ANIMATOR.is_any_animation_playing(),
		"quiet only once every animation has ended")


func test_unknown_end_token_is_safe() -> void:
	ANIMATOR._anim_end(999999)  # never registered -> must not crash or corrupt
	assert_false(ANIMATOR.is_any_animation_playing())


# --- expiry: a lost callback can never wedge the registry ---------------------

func test_expired_entry_is_not_busy() -> void:
	# Simulate a leaked finish callback: an entry whose expiry is already in the past.
	# is_any_animation_playing() must prune it and report quiet -- this is the property
	# that guarantees the AI can never freeze forever waiting on a stuck flag.
	ANIMATOR._anim_entries[424242] = Time.get_ticks_msec() - 5000
	assert_false(ANIMATOR.is_any_animation_playing(),
		"an entry past its expiry must be treated as finished, not busy")
	assert_true(ANIMATOR._anim_entries.is_empty(),
		"polling must have pruned the stale entry")


func test_begin_clamps_to_max_age() -> void:
	# A runaway duration is capped so even a never-ended entry cannot outlive the ceiling.
	var token: int = ANIMATOR._anim_begin(9999.0)
	var expiry: int = int(ANIMATOR._anim_entries[token])
	assert_lte(expiry - Time.get_ticks_msec(), ANIMATOR.ANIM_MAX_AGE_MS,
		"no entry may claim to run longer than the hard age ceiling")


# --- real tween finish clears the entry (common-case path) --------------------

func test_track_clears_on_tween_finished() -> void:
	var animator = ANIMATOR.new()
	add_child_autofree(animator)
	var node := Node3D.new()
	add_child_autofree(node)
	var tw := node.create_tween()
	tw.tween_property(node, "position", Vector3(0, 1, 0), 0.05)
	animator._track(tw, 0.05)
	assert_true(ANIMATOR.is_any_animation_playing(),
		"a tracked tween reads as busy while it runs")
	await tw.finished
	assert_false(ANIMATOR.is_any_animation_playing(),
		"the tween's finished callback must clear the entry")
