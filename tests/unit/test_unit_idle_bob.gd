extends GutTest

## [UnitAnimator]'s idle bob: the slow breathe that keeps a standing unit from reading
## as a prop.
##
## The bob is the one animation in this file that LOOPS FOREVER, which makes two of its
## properties load-bearing rather than cosmetic:
##
##  * it must NEVER appear in the global busy registry. That registry is what the AI
##    driver polls before acting; a never-ending entry would make the enemy wait forever.
##  * starting and stopping must leave no live tween behind and must snap the model back
##    to its authored rest pose -- a bob still ticking (or a model left mid-breathe) is
##    what strands a model off its unit when the next real animation captures its base.

const ANIMATOR := preload("res://game/visuals/UnitAnimator.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose -- see tests/README.md, rule 3.
var _guard

var _animator: Node
var _unit: Node3D
var _model: MeshInstance3D


func before_each() -> void:
	_guard = Guard.new()
	# Assigned through the guard, never the setter (which persists to user://settings.cfg).
	_guard.set_setting("animations_enabled", true)
	_guard.set_setting("battle_speed", 1.0)
	ANIMATOR._clear_anim_registry()

	_animator = add_child_autofree(ANIMATOR.new())
	# A placeholder-capsule unit: a "MeshInstance3D" direct child is what _get_anim_root
	# resolves for a unit with no authored .glb model.
	_unit = add_child_autofree(Node3D.new())
	_model = MeshInstance3D.new()
	_model.name = "MeshInstance3D"
	_unit.add_child(_model)  # freed with its parent -- one autofree covers both


func after_each() -> void:
	if _animator != null and is_instance_valid(_animator) and is_instance_valid(_unit):
		_animator._stop_idle_bob(_unit)
	ANIMATOR._clear_anim_registry()
	_guard.restore()


func _bob_of(unit: Node3D) -> Tween:
	var entry = _animator._idle_tween.get(unit.get_instance_id(), null)
	return entry if entry is Tween else null


# --- Start / stop --------------------------------------------------------------

func test_starting_creates_one_live_tween() -> void:
	_animator._start_idle_bob(_unit)
	var bob := _bob_of(_unit)
	assert_not_null(bob, "a unit on the board breathes")
	assert_true(bob.is_valid(), "and its tween is live")


func test_stopping_leaves_no_live_tween() -> void:
	_animator._start_idle_bob(_unit)
	var bob := _bob_of(_unit)
	_animator._stop_idle_bob(_unit)
	assert_false(bob.is_valid(), "stopping kills the looping tween outright")
	assert_false(_animator._idle_tween.has(_unit.get_instance_id()),
		"and forgets it, so the dictionary is the honest answer to 'is it bobbing?'")


func test_stopping_snaps_the_model_back_to_its_rest_pose() -> void:
	var rest_position: Vector3 = _model.position
	var rest_scale: Vector3 = _model.scale
	_animator._start_idle_bob(_unit)
	# Drive the loop well past its start so the model is genuinely mid-breathe.
	var bob := _bob_of(_unit)
	bob.custom_step(0.6)
	_animator._stop_idle_bob(_unit)
	assert_eq(_model.position, rest_position,
		"the model is put back exactly where the artist placed it")
	assert_eq(_model.scale, rest_scale,
		"and at its authored scale, so the next animation captures a clean base")


func test_starting_twice_does_not_stack_a_second_tween() -> void:
	_animator._start_idle_bob(_unit)
	var first := _bob_of(_unit)
	_animator._start_idle_bob(_unit)
	assert_eq(_bob_of(_unit), first,
		"a redundant start is a no-op -- two tweens on one position property fight")


func test_stopping_a_unit_that_never_bobbed_is_safe() -> void:
	_animator._stop_idle_bob(_unit)
	assert_false(_animator._idle_tween.has(_unit.get_instance_id()),
		"stopping something that was never started must not invent an entry or error")


# --- The load-bearing invariant: the bob never stalls the AI --------------------

func test_the_bob_never_registers_as_a_playing_animation() -> void:
	_animator._start_idle_bob(_unit)
	assert_not_null(_bob_of(_unit), "the bob really is running for this assertion")
	assert_false(ANIMATOR.is_any_animation_playing(),
		"an endless cosmetic loop must never read as busy -- the AI would wait forever")


# --- Gates ---------------------------------------------------------------------

func test_animations_off_starts_no_bob() -> void:
	_guard.set_setting("animations_enabled", false)
	_animator._start_idle_bob(_unit)
	assert_null(_bob_of(_unit), "animations off means the board holds perfectly still")


func test_the_master_switch_starts_no_bob() -> void:
	_animator.idle_bob_enabled = false
	_animator._start_idle_bob(_unit)
	assert_null(_bob_of(_unit), "the designer switch turns the breathe off outright")


func test_a_detached_unit_starts_no_bob() -> void:
	var loose: Node3D = autofree(Node3D.new())
	var loose_model := MeshInstance3D.new()
	loose_model.name = "MeshInstance3D"
	loose.add_child(loose_model)
	_animator._start_idle_bob(loose)
	assert_false(_animator._idle_tween.has(loose.get_instance_id()),
		"a Tween cannot be created on a node outside the tree -- report it by not bobbing")


func test_a_unit_with_no_model_starts_no_bob() -> void:
	var bare: Node3D = add_child_autofree(Node3D.new())
	_animator._start_idle_bob(bare)
	assert_false(_animator._idle_tween.has(bare.get_instance_id()),
		"nothing to animate means no tween, not a null-deref")


# --- Real animations own the model ---------------------------------------------

func test_a_real_animation_stops_the_bob_and_restarts_it_afterwards() -> void:
	_animator._start_idle_bob(_unit)
	var bob := _bob_of(_unit)
	# _begin_motion is the single door every glide/lunge goes through.
	var motion: Tween = _animator._begin_motion(_unit, _model)
	assert_false(bob.is_valid(),
		"a real animation takes the model over -- the bob must let go of `position`")
	assert_false(_animator._idle_tween.has(_unit.get_instance_id()),
		"and the registry agrees it is no longer bobbing")

	motion.tween_property(_model, "position", _model.position, 0.01)
	await motion.finished
	assert_not_null(_bob_of(_unit),
		"once the animation finishes the unit goes back to breathing")


func test_the_bob_does_not_start_while_a_motion_tween_owns_the_model() -> void:
	var motion: Tween = _animator._begin_motion(_unit, _model)
	motion.tween_property(_model, "position", _model.position, 5.0)
	_animator._start_idle_bob(_unit)
	assert_null(_bob_of(_unit),
		"a spawn/turn event arriving mid-glide must not start a second tween on `position`")
	motion.kill()
