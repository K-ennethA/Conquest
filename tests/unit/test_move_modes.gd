extends GutTest

## Two-mode moves: a move can swap its targeting AND effects based on the caster's state.
## Geode's Prism Bulwark is the case: a SELF guard normally, an ENEMY-targeted release of
## the stored retaliation once it has charges and the guard has dropped.

class MockCaster:
	var statuses: Array = []
	func _init(p: Array = []) -> void:
		statuses = p
	func has_status(id: StringName) -> bool:
		return id in statuses


func _bulwark() -> MoveResource:
	return load("res://game/combat/moves/prism_bulwark.tres")


func test_defaults_to_the_self_cast_guard():
	var move := _bulwark()
	var fresh := MockCaster.new([])
	assert_false(move.is_alt_mode(fresh), "with no charges it is the plain guard")
	assert_eq(move.targeting_for(fresh).target_kind, CombatTypes.TargetKind.SELF,
		"the guard is self-cast")

func test_while_guarding_it_stays_self_cast():
	var move := _bulwark()
	# Mid-guard the unit already holds charges, but the release must NOT be offered yet.
	var guarding := MockCaster.new([&"prism_guard", &"reprisal_charge"])
	assert_false(move.is_alt_mode(guarding), "the release is blocked while the guard is up")
	assert_eq(move.targeting_for(guarding).target_kind, CombatTypes.TargetKind.SELF,
		"still self-cast while guarding")

func test_arms_into_an_enemy_release_once_the_guard_drops():
	var move := _bulwark()
	var armed := MockCaster.new([&"reprisal_charge"])
	assert_true(move.is_alt_mode(armed), "guard gone + charges stored -> release is armed")
	assert_eq(move.targeting_for(armed).target_kind, CombatTypes.TargetKind.ENEMY,
		"the armed release is aimed at an enemy")
	assert_gt(move.effective_max_range(armed), 0, "the armed release has reach")
	assert_eq(move.display_name_for(armed), "Prism Bulwark: Reprisal",
		"the HUD names the armed mode differently")

func test_reverts_to_self_cast_when_the_charges_expire():
	var move := _bulwark()
	var spent := MockCaster.new([])  # charges gone (spent or expired)
	assert_false(move.is_alt_mode(spent), "no charges -> back to the guard")
	assert_eq(move.targeting_for(spent).target_kind, CombatTypes.TargetKind.SELF,
		"reverts to self-cast")

func test_each_mode_carries_its_own_effects():
	var move := _bulwark()
	var guard_effects: Array = move.effects_for(MockCaster.new([]))
	var release_effects: Array = move.effects_for(MockCaster.new([&"reprisal_charge"]))
	assert_ne(guard_effects, release_effects, "the two modes resolve different effects")
	var guard_has_status := false
	for e in guard_effects:
		if e is ApplyStatusEffect:
			guard_has_status = true
	assert_true(guard_has_status, "the guard mode applies its damage-reduction status")
	var release_has_damage := false
	for e in release_effects:
		if e is StackConsumeDamageEffect:
			release_has_damage = true
	assert_true(release_has_damage, "the armed mode spends the stored charges as damage")

func test_single_mode_moves_are_unaffected():
	var plain: MoveResource = load("res://game/combat/moves/wither_bolt.tres")
	var anyone := MockCaster.new([&"reprisal_charge", &"prism_guard"])
	assert_false(plain.is_alt_mode(anyone), "a move with no alt mode never switches")
	assert_eq(plain.targeting_for(anyone), plain.targeting, "it always uses its one pattern")
	assert_eq(plain.effects_for(anyone), plain.effects, "and its one effect list")
