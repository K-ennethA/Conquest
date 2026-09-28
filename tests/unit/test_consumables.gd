extends GutTest

## CONSUMABLES (docs/design/DECISIONS.md #28): the heal / cure / revive rules of
## [ConsumableEffect], out of battle on a story member ([method StoryState.use_consumable], the
## Journey -> Bag path) and in battle on a live unit (the duel's USE_ITEM), plus the shipped
## consumable content. Pure: members are plain records, the battle side uses small doubles.


## A battle target: HP + a status list (just the methods ConsumableEffect duck-types).
class _Statuses extends RefCounted:
	var active: Array = []

	func get_active() -> Array:
		return active

	func remove_status(id: StringName, _board = null) -> int:
		var before: int = active.size()
		active = active.filter(func(c) -> bool: return c.id != id)
		return before - active.size()


class _Target extends RefCounted:
	var hp: int = 0
	var max_hp: int = 100
	var alive: bool = true
	var statuses := _Statuses.new()

	func get_stat(_n: String) -> int:
		return hp

	func get_base_stat(_n: String) -> int:
		return max_hp

	func heal(n: int) -> void:
		hp = mini(max_hp, hp + n)

	func is_alive() -> bool:
		return alive

	func get_status_controller():
		return statuses


func _effect(props: Dictionary) -> ConsumableEffect:
	var e := ConsumableEffect.new()
	for k in props:
		e.set(k, props[k])
	return e


## A member of [param cid] at [param hp] (-1 = full), optionally knocked out.
func _member(hp: int, wounded: bool = false, cid: String = "tree_grunt") -> StoryPartyMember:
	var m := StoryPartyMember.create(cid, cid)
	m.current_hp = hp
	m.wounded = wounded
	return m


func _status(id: StringName, from_environment: bool) -> StatusCondition:
	var c := StatusCondition.new()
	c.id = id
	c.inflicted_by_environment = from_environment
	return c


# --- Out of battle: a story member ----------------------------------------------------

func test_a_heal_clamps_at_max_hp() -> void:
	var m := _member(50)   # a Barkling has 55 max HP
	var r: Dictionary = _effect({"heal_amount": 25}).apply_to_member(m)
	assert_true(bool(r["ok"]), "a hurt member can be healed")
	assert_eq(int(r["healed"]), 5, "only the missing 5 HP are restored")
	assert_eq(m.current_hp, StoryPartyMember.HP_FULL, "and a member topped up stores the full-HP sentinel")


func test_a_partial_heal_adds_its_amount() -> void:
	var m := _member(10)
	var r: Dictionary = _effect({"heal_amount": 25}).apply_to_member(m)
	assert_eq(int(r["healed"]), 25, "a 25 HP tonic restores 25")
	assert_eq(m.current_hp, 35, "10 -> 35")


func test_a_percent_heal_reads_the_members_max_hp() -> void:
	var m := _member(1)
	var e := _effect({"heal_percent": 60})
	assert_eq(e.heal_for(55), 33, "60% of 55 is 33 (rounded up)")
	e.apply_to_member(m)
	assert_eq(m.current_hp, 34, "1 + 33")


func test_a_heal_is_never_wasted_on_a_full_member() -> void:
	var m := _member(StoryPartyMember.HP_FULL)
	var r: Dictionary = _effect({"heal_amount": 25}).apply_to_member(m)
	assert_false(bool(r["ok"]), "no heal on a full-HP member")
	assert_eq(String(r["reason"]), "full_hp", "and it says why")


func test_a_heal_does_not_raise_the_knocked_out() -> void:
	var m := _member(0, true)
	var r: Dictionary = _effect({"heal_amount": 25}).apply_to_member(m)
	assert_false(bool(r["ok"]), "a tonic cannot revive")
	assert_eq(String(r["reason"]), "knocked_out", "a knocked-out member needs a revive")
	assert_true(m.wounded, "and stays knocked out")


func test_a_revive_only_works_on_the_knocked_out() -> void:
	var e := _effect({"revive": true, "revive_percent": 50})
	var healthy := _member(20)
	var r: Dictionary = e.apply_to_member(healthy)
	assert_false(bool(r["ok"]), "no revive on a member who is standing")
	assert_eq(String(r["reason"]), "not_knocked_out", "and it says why")
	assert_eq(healthy.current_hp, 20, "nothing changed")

	var down := _member(0, true)
	r = e.apply_to_member(down)
	assert_true(bool(r["ok"]), "a knocked-out member is revived")
	assert_true(bool(r["revived"]), "reported as a revive")
	assert_false(down.wounded, "the knocked-out / wounded state is cleared")
	assert_eq(down.current_hp, 28, "back at 50% of 55 (rounded up)")
	assert_true(down.is_fieldable(), "and can be fielded again")


func test_a_cure_only_item_has_nothing_to_cure_out_of_battle() -> void:
	var field_cure := _effect({"cure_all_afflictions": true})
	var r: Dictionary = field_cure.apply_to_member(_member(20))
	assert_eq(String(r["reason"]), "nothing_to_cure", "a story member carries no statuses between battles")
	var battle_cure := _effect({"cure_all_afflictions": true, "usable_in_field": false})
	assert_eq(String(battle_cure.check_member(_member(20))["reason"]), "not_in_field",
		"a battle-only cure is refused from the bag")


func test_preview_matches_apply_and_changes_nothing() -> void:
	var m := _member(30)
	var e := _effect({"heal_amount": 25})
	var p: Dictionary = e.preview_member(m)
	assert_eq(m.current_hp, 30, "a preview writes nothing")
	var r: Dictionary = e.apply_to_member(m)
	assert_eq(p, r, "the shop's party preview shows exactly what the bag's Use does")


func test_the_story_bag_spends_one_only_when_it_helps() -> void:
	var s := StoryState.new()
	var m: StoryPartyMember = s.add_member("tree_grunt")
	s.add_item("mossleaf_tonic", 2)
	var r: Dictionary = s.use_consumable("mossleaf_tonic", m.member_id)
	assert_false(bool(r["ok"]), "a full member: refused")
	assert_eq(s.item_count("mossleaf_tonic"), 2, "and the tonic is kept")
	m.current_hp = 5
	r = s.use_consumable("mossleaf_tonic", m.member_id)
	assert_true(bool(r["ok"]), "a hurt member: used")
	assert_eq(m.current_hp, 30, "5 + 25")
	assert_eq(s.item_count("mossleaf_tonic"), 1, "one tonic spent")
	assert_eq(String(s.use_consumable("heartwood_charm", m.member_id)["reason"]), "no_item", "nothing to use")
	s.add_item("heartwood_charm")
	assert_eq(String(s.use_consumable("heartwood_charm", m.member_id)["reason"]), "not_consumable",
		"equipment is worn, not used")


# --- In battle: a live unit --------------------------------------------------------------

func test_a_battle_heal_clamps_and_refuses_a_full_unit() -> void:
	var t := _Target.new()
	t.hp = 90
	var e := _effect({"heal_amount": 25})
	var r: Dictionary = e.apply_to_unit(t)
	assert_true(bool(r["ok"]), "a hurt unit is healed")
	assert_eq(int(r["healed"]), 10, "clamped at max HP")
	assert_eq(t.hp, 100, "full")
	assert_eq(String(e.check_unit(t)["reason"]), "full_hp", "a second tonic would be wasted")


func test_a_cure_removes_the_named_status() -> void:
	var t := _Target.new()
	t.hp = 100
	t.statuses.active = [_status(&"poisoned", false), _status(&"braced", false)]
	var e := _effect({"cure_status_ids": [&"poisoned"] as Array[StringName]})
	assert_true(bool(e.check_unit(t)["ok"]), "a poisoned unit can be cured")
	var r: Dictionary = e.apply_to_unit(t)
	assert_eq(r["cured"], ["poisoned"], "poison removed")
	assert_eq(t.statuses.active.size(), 1, "the unit's own buff stays")
	assert_eq(String(e.check_unit(t)["reason"]), "nothing_to_cure", "nothing left to cure")


func test_cure_all_removes_afflictions_but_not_buffs() -> void:
	var t := _Target.new()
	t.hp = 100
	t.statuses.active = [_status(&"ensnared", true), _status(&"guarded", false)]
	var r: Dictionary = _effect({"cure_all_afflictions": true}).apply_to_unit(t)
	assert_eq(r["cured"], ["ensnared"], "an affliction (forced on the unit) is cured")
	assert_eq(t.statuses.active.size(), 1, "a protective status is never touched")


func test_a_revive_cannot_be_used_mid_duel() -> void:
	var t := _Target.new()
	t.hp = 10
	var e := _effect({"revive": true})
	assert_eq(String(e.check_unit(t)["reason"]), "not_knocked_out", "a standing unit is not revived")
	t.alive = false
	assert_eq(String(e.check_unit(t)["reason"]), "knocked_out", "and a KO ends a 1v1 anyway")


# --- Content -----------------------------------------------------------------------------

func test_the_shipped_consumables() -> void:
	ItemLibrary.rescan()
	var ids: Array = ItemLibrary.consumables().map(func(i: ItemResource) -> String: return String(i.id))
	for id in ["mossleaf_tonic", "heartwood_tonic", "bitterroot_salve", "clearwater_draught", "dawnpetal_draught"]:
		assert_true(ids.has(id), "%s ships as a consumable" % id)
	for item in ItemLibrary.consumables():
		assert_gt(item.price, 0, "%s has a price" % String(item.id))
		assert_true(item.consumable.has_effect(), "%s does something" % String(item.id))
		assert_false(item.is_equipment(), "%s is never worn" % String(item.id))
		assert_false(ItemLibrary.items_of_rarity(int(item.rarity)).has(item), "%s never drops after a battle" % String(item.id))
	var tonic: ItemResource = ItemLibrary.get_item("mossleaf_tonic")
	assert_eq(tonic.consumable.heal_amount, 25, "the small tonic restores 25 HP")
	assert_eq(tonic.effect_summary(), "Restores 25 HP", "and says so")
	var revive: ItemResource = ItemLibrary.get_item("dawnpetal_draught")
	assert_true(revive.consumable.revive, "the Dawnpetal Draught is a revive")
	var salve: ItemResource = ItemLibrary.get_item("bitterroot_salve")
	assert_true(salve.consumable.cure_status_ids.has(&"poisoned"), "the salve cures poison")
	assert_eq(ConsumableEffect.status_label(&"poisoned"), "Poisoned", "by its catalog name")
	assert_eq(ItemLibrary.validate().size(), 0, "item content validates: %s" % str(ItemLibrary.validate()))
