extends GutTest

## Guards for the cosmetic-skin system: the CONTENT catalog ([SkinLibrary] /
## [SkinResource] .tres files), the PURE gacha math (weighted pick + duplicate
## refund), the ECONOMY layer ([SkinShop]) against an injected mock profile, and the
## material-duplication rule that keeps a tint from ever mutating a shared material.
##
## Every test here is data-only or uses the mock below -- no scene is built, and the
## PlayerProfile autoload is never required, so these run headless and never flake.

## Points a COMMON / RARE skin must cost, and the gacha-only marker price.
const PRICE_COMMON: int = 300
const PRICE_RARE: int = 800
const PRICE_GACHA_ONLY: int = 0

## Minimum content bar: at least this many characters carry at least this many skins.
const MIN_SKINNED_CHARACTERS: int = 5
const MIN_SKINS_PER_CHARACTER: int = 2


## Stand-in for the PlayerProfile autoload, implementing exactly its public
## points/skin contract. Injected into [SkinShop] so the economy is testable without
## the autoload, the save file, or the scene tree.
class MockProfile extends RefCounted:
	var points: int = 0
	var owned: Array = []
	var equipped: Dictionary = {}
	## Every spend that went through, for asserting the NET gacha charge.
	var spends: Array = []

	func get_points() -> int:
		return points

	func spend_points(amount: int, reason: String) -> bool:
		if amount <= 0:
			return false
		if points < amount:
			return false
		points -= amount
		spends.append({ "amount": amount, "reason": reason })
		return true

	func owns_skin(skin_id: String) -> bool:
		return skin_id in owned

	func add_skin(skin_id: String) -> void:
		if skin_id.is_empty() or skin_id in owned:
			return
		owned.append(skin_id)

	func equip_skin(character_id: String, skin_id: String) -> void:
		if character_id.is_empty():
			return
		if skin_id.is_empty():
			equipped.erase(character_id)
		else:
			equipped[character_id] = skin_id

	func get_equipped_skin(character_id: String) -> String:
		return String(equipped.get(character_id, ""))

	func get_owned_skins() -> Array:
		return owned.duplicate()


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _all_skin_ids() -> Array:
	var ids: Array = []
	for skin in SkinLibrary.all_skins():
		ids.append(String(skin.id))
	return ids


# ===========================================================================
#  Catalog: scan, uniqueness, resolvable characters
# ===========================================================================

func test_library_scans_the_content_folder() -> void:
	var skins: Array[SkinResource] = SkinLibrary.all_skins()
	assert_gt(skins.size(), 0, "the skin library finds authored skins")
	assert_eq(skins.size(), SkinLibrary.all_paths().size(), "every scanned path loads as a SkinResource")


func test_catalog_validates() -> void:
	var report: Dictionary = SkinLibrary.validate_catalog()
	assert_true(bool(report.get("valid", false)),
		"skin catalog issues: %s" % str(report.get("issues", [])))


func test_skin_ids_are_unique_and_resolve() -> void:
	var seen: Dictionary = {}
	for skin in SkinLibrary.all_skins():
		var id: String = String(skin.id)
		assert_false(id.is_empty(), "every skin has an id")
		assert_false(seen.has(id), "skin id '%s' is unique" % id)
		seen[id] = true
		var found: SkinResource = SkinLibrary.find(id)
		assert_not_null(found, "find() resolves skin '%s'" % id)
		if found != null:
			assert_eq(String(found.id), id, "find() round-trips skin '%s'" % id)


func test_find_reads_unknown_and_empty_ids_as_default() -> void:
	assert_null(SkinLibrary.find(""), "an empty id has no skin (default look)")
	assert_null(SkinLibrary.find("not_a_real_skin"), "an unknown id has no skin (default look)")


func test_every_skin_belongs_to_a_real_roster_character() -> void:
	for skin in SkinLibrary.all_skins():
		var character: CharacterResource = CharacterLibrary.get_character(skin.character_id)
		assert_not_null(character,
			"skin '%s' points at roster character '%s'" % [String(skin.id), String(skin.character_id)])


func test_enough_characters_carry_enough_skins() -> void:
	var by_character: Dictionary = {}
	for skin in SkinLibrary.all_skins():
		var key: String = String(skin.character_id)
		by_character[key] = int(by_character.get(key, 0)) + 1

	var qualifying: int = 0
	for key in by_character.keys():
		if int(by_character[key]) >= MIN_SKINS_PER_CHARACTER:
			qualifying += 1
	assert_gte(qualifying, MIN_SKINNED_CHARACTERS,
		"at least %d characters have %d+ skins (have: %s)" % [
			MIN_SKINNED_CHARACTERS, MIN_SKINS_PER_CHARACTER, str(by_character)])


func test_all_for_character_groups_correctly() -> void:
	for skin in SkinLibrary.all_skins():
		var group: Array[SkinResource] = SkinLibrary.all_for_character(skin.character_id)
		assert_true(group.has(skin), "'%s' is listed under its own character" % String(skin.id))
		for other in group:
			assert_eq(other.character_id, skin.character_id, "the group holds only that character's skins")
	assert_eq(SkinLibrary.all_for_character("").size(), 0, "an empty character id groups nothing")


# ===========================================================================
#  Economy authoring rules: price per rarity, and a visible difference
# ===========================================================================

func test_price_matches_rarity() -> void:
	for skin in SkinLibrary.all_skins():
		var where: String = String(skin.id)
		match skin.rarity:
			SkinResource.Rarity.COMMON:
				assert_eq(skin.price, PRICE_COMMON, "%s is a COMMON priced at %d" % [where, PRICE_COMMON])
			SkinResource.Rarity.RARE:
				assert_eq(skin.price, PRICE_RARE, "%s is a RARE priced at %d" % [where, PRICE_RARE])
			SkinResource.Rarity.EPIC:
				assert_eq(skin.price, PRICE_GACHA_ONLY, "%s is an EPIC and is gacha-only" % where)
				assert_false(skin.is_buyable(), "%s cannot be bought outright" % where)


func test_every_skin_actually_looks_different() -> void:
	for skin in SkinLibrary.all_skins():
		assert_true(skin.model_scene != null or skin.has_tint(),
			"'%s' changes the look (model override or non-white tint)" % String(skin.id))


func test_rarity_weights_are_the_documented_table() -> void:
	assert_eq(SkinResource.WEIGHT_COMMON, 70, "COMMON weight")
	assert_eq(SkinResource.WEIGHT_RARE, 25, "RARE weight")
	assert_eq(SkinResource.WEIGHT_EPIC, 5, "EPIC weight")
	for skin in SkinLibrary.all_skins():
		assert_gt(skin.rarity_weight(), 0, "'%s' has a positive draw weight" % String(skin.id))


# ===========================================================================
#  Gacha math (pure, RNG-injected)
# ===========================================================================

func test_weighted_pick_is_deterministic_for_a_seed() -> void:
	var first: Array = []
	var rng_a := _seeded(20260801)
	for i in range(8):
		first.append(String(SkinLibrary.weighted_pick(rng_a).id))

	var second: Array = []
	var rng_b := _seeded(20260801)
	for i in range(8):
		second.append(String(SkinLibrary.weighted_pick(rng_b).id))

	assert_eq(first, second, "the same seed draws the same sequence")


func test_weighted_pick_needs_an_rng() -> void:
	assert_null(SkinLibrary.weighted_pick(null), "a null rng picks nothing rather than crashing")


func test_weighted_pick_respects_the_rarity_table() -> void:
	# COMMON dominates the pool and EPIC is the jackpot; assert the ORDERING plus a
	# generous band, so re-balancing the content does not break this, but inverting
	# the weights would.
	var counts: Dictionary = { 0: 0, 1: 0, 2: 0 }
	var rng := _seeded(4242)
	var draws: int = 4000
	for i in range(draws):
		var skin: SkinResource = SkinLibrary.weighted_pick(rng)
		counts[skin.rarity] = int(counts[skin.rarity]) + 1

	assert_gt(int(counts[SkinResource.Rarity.COMMON]), int(counts[SkinResource.Rarity.RARE]),
		"COMMON out-draws RARE")
	assert_gt(int(counts[SkinResource.Rarity.RARE]), int(counts[SkinResource.Rarity.EPIC]),
		"RARE out-draws EPIC")
	assert_gt(float(counts[SkinResource.Rarity.COMMON]) / float(draws), 0.6,
		"COMMON is the bulk of the pool")
	assert_lt(float(counts[SkinResource.Rarity.EPIC]) / float(draws), 0.05,
		"EPIC stays rare")


func test_roll_with_rng_reports_a_new_skin() -> void:
	var result: Dictionary = SkinLibrary.roll_with_rng(_seeded(7), [])
	assert_false(String(result.get("skin_id", "")).is_empty(), "a roll lands on a skin")
	assert_false(bool(result.get("is_duplicate", true)), "nothing owned means nothing is a duplicate")
	assert_eq(int(result.get("refund", -1)), 0, "a new skin refunds nothing")


func test_roll_with_rng_refunds_a_duplicate() -> void:
	# Same seed, so the SAME skin is drawn -- only ownership differs.
	var fresh: Dictionary = SkinLibrary.roll_with_rng(_seeded(7), [])
	var picked: String = String(fresh.get("skin_id", ""))

	var dupe: Dictionary = SkinLibrary.roll_with_rng(_seeded(7), [picked])
	assert_eq(String(dupe.get("skin_id", "")), picked, "the seed draws the same skin either way")
	assert_true(bool(dupe.get("is_duplicate", false)), "an owned skin reads as a duplicate")
	assert_eq(int(dupe.get("refund", 0)), SkinLibrary.DUPLICATE_REFUND, "a duplicate refunds points")


func test_roll_with_rng_accepts_stringname_ownership() -> void:
	var fresh: Dictionary = SkinLibrary.roll_with_rng(_seeded(99), [])
	var picked: String = String(fresh.get("skin_id", ""))
	var dupe: Dictionary = SkinLibrary.roll_with_rng(_seeded(99), [StringName(picked)])
	assert_true(bool(dupe.get("is_duplicate", false)), "StringName ids count as owned too")


# ===========================================================================
#  Material duplication (a tint must never mutate a shared material)
# ===========================================================================

func test_tinted_material_duplicates_and_never_mutates_the_base() -> void:
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

	var tinted: Material = SkinLibrary.tinted_material(base, Color(0.5, 0.25, 0.5, 1.0))
	assert_not_null(tinted, "a tint produces a material")
	assert_true(tinted != base, "the tinted material is a NEW instance, not the shared base")
	assert_eq(base.albedo_color, Color(1.0, 1.0, 1.0, 1.0), "the shared base material is untouched")

	var sm := tinted as StandardMaterial3D
	assert_not_null(sm, "the duplicate keeps its type")
	assert_almost_eq(sm.albedo_color.r, 0.5, 0.001, "albedo is multiplied by the tint (r)")
	assert_almost_eq(sm.albedo_color.g, 0.25, 0.001, "albedo is multiplied by the tint (g)")


func test_tinted_material_handles_a_missing_base() -> void:
	assert_null(SkinLibrary.tinted_material(null, Color.RED), "no base material, no tint")


# ===========================================================================
#  SkinShop: equip round-trip, buying, and the gacha charge
# ===========================================================================

func _shop_with(points: int, owned: Array = []) -> Array:
	var profile := MockProfile.new()
	profile.points = points
	profile.owned = owned.duplicate()
	return [SkinShop.new(profile), profile]


func test_equip_round_trip_against_a_mock_profile() -> void:
	var pair: Array = _shop_with(1000)
	var shop: SkinShop = pair[0]
	var profile: MockProfile = pair[1]

	var skin: SkinResource = SkinLibrary.all_skins()[0]
	var skin_id: String = String(skin.id)
	var character_id: String = String(skin.character_id)

	assert_eq(shop.equipped_for(character_id), "", "nothing is equipped to begin with")
	assert_false(shop.equip(character_id, skin_id), "an UNOWNED skin cannot be equipped")

	profile.add_skin(skin_id)
	assert_true(shop.equip(character_id, skin_id), "an owned skin equips")
	assert_eq(shop.equipped_for(character_id), skin_id, "the equipped skin reads back")

	assert_true(shop.equip(character_id, ""), "the default look always equips")
	assert_eq(shop.equipped_for(character_id), "", "clearing returns to the default look")


func test_buy_spends_points_and_grants_ownership() -> void:
	var pair: Array = _shop_with(1000)
	var shop: SkinShop = pair[0]
	var profile: MockProfile = pair[1]

	var skin: SkinResource = _first_buyable()
	assert_not_null(skin, "the catalog has a buyable skin")

	var result: Dictionary = shop.buy(skin)
	assert_true(bool(result.get("ok", false)), "the purchase goes through")
	assert_eq(int(result.get("spent", 0)), skin.price, "it charges the listed price")
	assert_eq(profile.points, 1000 - skin.price, "the balance drops by the price")
	assert_true(shop.owns(String(skin.id)), "the skin is now owned")

	var again: Dictionary = shop.buy(skin)
	assert_false(bool(again.get("ok", true)), "buying it twice is refused")
	assert_eq(String(again.get("reason", "")), SkinShop.REASON_ALREADY_OWNED, "and says why")
	assert_eq(profile.points, 1000 - skin.price, "the refused purchase charges nothing")


func test_buy_refuses_an_unaffordable_skin() -> void:
	var skin: SkinResource = _first_buyable()
	var pair: Array = _shop_with(skin.price - 1)
	var shop: SkinShop = pair[0]
	var profile: MockProfile = pair[1]

	var result: Dictionary = shop.buy(skin)
	assert_false(bool(result.get("ok", true)), "one point short is still short")
	assert_eq(String(result.get("reason", "")), SkinShop.REASON_INSUFFICIENT, "and says why")
	assert_eq(profile.points, skin.price - 1, "no points are taken")
	assert_false(shop.owns(String(skin.id)), "and nothing is granted")


func test_buy_refuses_a_gacha_only_skin() -> void:
	var skin: SkinResource = _first_gacha_only()
	if skin == null:
		pass_test("no gacha-only skin authored")
		return
	var pair: Array = _shop_with(100000)
	var shop: SkinShop = pair[0]
	var profile: MockProfile = pair[1]

	var result: Dictionary = shop.buy(skin)
	assert_false(bool(result.get("ok", true)), "a gacha-only skin cannot be bought at any price")
	assert_eq(String(result.get("reason", "")), SkinShop.REASON_NOT_BUYABLE, "and says why")
	assert_eq(profile.points, 100000, "no points are taken")


func test_roll_charges_full_cost_for_a_new_skin() -> void:
	var pair: Array = _shop_with(SkinShop.GACHA_COST)
	var shop: SkinShop = pair[0]
	var profile: MockProfile = pair[1]

	var result: Dictionary = shop.roll(_seeded(11))
	assert_true(bool(result.get("ok", false)), "the roll goes through")
	assert_false(bool(result.get("is_duplicate", true)), "an empty collection cannot duplicate")
	assert_eq(int(result.get("spent", 0)), SkinShop.GACHA_COST, "a new skin costs the full roll")
	assert_eq(profile.points, 0, "the balance is spent")
	assert_true(shop.owns(String(result.get("skin_id", ""))), "the rolled skin is granted")


func test_roll_charges_the_net_cost_for_a_duplicate() -> void:
	# Owning EVERYTHING makes any draw a duplicate, so this is deterministic.
	var pair: Array = _shop_with(SkinShop.GACHA_COST, _all_skin_ids())
	var shop: SkinShop = pair[0]
	var profile: MockProfile = pair[1]
	var owned_before: int = profile.owned.size()

	var result: Dictionary = shop.roll(_seeded(11))
	assert_true(bool(result.get("ok", false)), "the roll goes through")
	assert_true(bool(result.get("is_duplicate", false)), "owning everything guarantees a duplicate")
	assert_eq(int(result.get("refund", 0)), SkinLibrary.DUPLICATE_REFUND, "the duplicate refunds")
	assert_eq(int(result.get("spent", 0)), SkinShop.GACHA_COST - SkinLibrary.DUPLICATE_REFUND,
		"only the NET cost is charged")
	assert_eq(profile.points, SkinLibrary.DUPLICATE_REFUND, "the refund is left in the balance")
	assert_eq(profile.owned.size(), owned_before, "a duplicate grants nothing new")


func test_roll_refuses_below_the_full_cost() -> void:
	# Affordability is checked against the FULL cost -- a near-miss balance must not
	# sneak through on the chance the result would have been a discounted duplicate.
	var pair: Array = _shop_with(SkinShop.GACHA_COST - 1, _all_skin_ids())
	var shop: SkinShop = pair[0]
	var profile: MockProfile = pair[1]

	var result: Dictionary = shop.roll(_seeded(3))
	assert_false(bool(result.get("ok", true)), "the roll is refused")
	assert_eq(String(result.get("reason", "")), SkinShop.REASON_INSUFFICIENT, "and says why")
	assert_eq(profile.points, SkinShop.GACHA_COST - 1, "no points are taken")
	assert_false(shop.can_roll(), "can_roll() agrees")


func test_shop_degrades_safely_without_a_profile() -> void:
	var shop := SkinShop.new(null)
	assert_false(shop.has_profile(), "there is no profile")
	assert_eq(shop.points(), 0, "the balance reads as zero")
	assert_eq(shop.owned_ids().size(), 0, "nothing is owned")
	assert_eq(shop.equipped_for("vineweave"), "", "nothing is equipped")
	assert_false(shop.equip("vineweave", "vineweave_emberroot"), "equipping is a no-op")
	assert_false(shop.can_roll(), "rolling is unavailable")

	var bought: Dictionary = shop.buy(_first_buyable())
	assert_eq(String(bought.get("reason", "")), SkinShop.REASON_NO_PROFILE, "buying reports no profile")
	var rolled: Dictionary = shop.roll(_seeded(1))
	assert_false(bool(rolled.get("ok", true)), "rolling reports no profile")


# ===========================================================================
#  Collection screen: the rarity colour mapping (static, no scene needed)
# ===========================================================================

func test_rarity_colors_are_distinct_and_total() -> void:
	var common: Color = CollectionScreen.rarity_color(SkinResource.Rarity.COMMON)
	var rare: Color = CollectionScreen.rarity_color(SkinResource.Rarity.RARE)
	var epic: Color = CollectionScreen.rarity_color(SkinResource.Rarity.EPIC)
	assert_true(common != rare and rare != epic and common != epic, "each rarity reads differently")
	assert_eq(CollectionScreen.rarity_color(-1), common, "an out-of-range rarity falls back to COMMON")
	assert_eq(CollectionScreen.rarity_color(99), common, "an unknown rarity falls back to COMMON")


# --- helpers ---------------------------------------------------------------

func _first_buyable() -> SkinResource:
	for skin in SkinLibrary.all_skins():
		if skin.is_buyable():
			return skin
	return null


func _first_gacha_only() -> SkinResource:
	for skin in SkinLibrary.all_skins():
		if not skin.is_buyable():
			return skin
	return null
