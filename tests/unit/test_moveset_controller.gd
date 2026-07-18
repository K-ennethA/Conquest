extends GutTest

# Tests for MovesetController: per-move cooldown-remaining and uses-left tracking
# built on the new MoveResource.cooldown / existing MoveResource.max_uses fields.

func _move(id: StringName, cooldown: int, max_uses: int) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id
	m.cooldown = cooldown
	m.max_uses = max_uses
	# Give it a minimal valid shape (not required by the controller, but realistic).
	m.targeting = TargetingPattern.new()
	m.effects = [DamageEffect.new()]
	return m

# --- Cooldowns -------------------------------------------------------------

func test_move_with_cooldown_two_is_unusable_for_two_ticks():
	var mc := MovesetController.new()
	var move := _move(&"blast", 2, -1)
	assert_true(mc.can_use(move), "usable before first use")
	mc.on_used(move)
	assert_false(mc.can_use(move), "unusable immediately after use")
	assert_eq(mc.remaining(move), 2, "cooldown starts at 2")
	mc.tick_cooldowns()
	assert_false(mc.can_use(move), "still on cooldown after 1 tick")
	assert_eq(mc.remaining(move), 1, "1 turn left")
	mc.tick_cooldowns()
	assert_true(mc.can_use(move), "usable again after 2 ticks")
	assert_eq(mc.remaining(move), 0, "cooldown cleared")

func test_zero_cooldown_move_is_always_ready():
	var mc := MovesetController.new()
	var move := _move(&"jab", 0, -1)
	mc.on_used(move)
	assert_true(mc.can_use(move), "no cooldown means usable next turn immediately")
	assert_eq(mc.remaining(move), 0, "no cooldown tracked")

# --- Uses ------------------------------------------------------------------

func test_max_uses_is_enforced():
	var mc := MovesetController.new()
	var move := _move(&"ultimate", 0, 2)
	assert_eq(mc.uses_left(move), 2, "starts with 2 charges")
	mc.on_used(move)
	assert_true(mc.can_use(move), "one charge left")
	assert_eq(mc.uses_left(move), 1, "one charge remaining")
	mc.on_used(move)
	assert_false(mc.can_use(move), "no charges left")
	assert_eq(mc.uses_left(move), 0, "exhausted")

func test_unlimited_uses_always_available():
	var mc := MovesetController.new()
	var move := _move(&"strike", 0, -1)
	for i in range(20):
		mc.on_used(move)
	assert_true(mc.can_use(move), "unlimited move never runs out of charges")
	assert_eq(mc.uses_left(move), -1, "unlimited reported as -1")

# --- Cooldown + uses interaction -------------------------------------------

func test_cooldown_and_uses_combined():
	var mc := MovesetController.new()
	var move := _move(&"nova", 3, 2)
	mc.on_used(move)                 # spend charge 1, cooldown 3
	assert_false(mc.can_use(move), "blocked by cooldown even with charges left")
	mc.tick_cooldowns()
	mc.tick_cooldowns()
	mc.tick_cooldowns()
	assert_true(mc.can_use(move), "off cooldown with 1 charge left")
	mc.on_used(move)                 # spend charge 2
	for i in range(3):
		mc.tick_cooldowns()
	assert_false(mc.can_use(move), "off cooldown but out of charges")

func test_null_move_is_never_usable():
	var mc := MovesetController.new()
	assert_false(mc.can_use(null), "null move is not usable")
	assert_eq(mc.remaining(null), 0, "null move has no cooldown")
	assert_eq(mc.uses_left(null), -1, "null move uses_left reported as unlimited/none")

func test_reset_clears_tracking():
	var mc := MovesetController.new()
	var move := _move(&"blast", 2, 1)
	mc.on_used(move)
	mc.reset()
	assert_true(mc.can_use(move), "reset restores availability")
	assert_eq(mc.remaining(move), 0, "reset clears cooldown")
	assert_eq(mc.uses_left(move), 1, "reset restores charges")
