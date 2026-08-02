extends GutTest

## The shipped item CONTENT has to be trustworthy, because every failure mode here is silent
## at runtime: a duplicate id makes two items fight over one save entry, an empty id makes an
## item unequippable and unsaveable, and a stat key [UnitStats] does not know applies exactly
## nothing while still reading as a real buff on the card.
##
## These tests pin the scan itself (recursive, cached, id-addressed), the uniqueness +
## stat-name audit [method ItemLibrary.validate] performs, and the specific authored numbers
## the design leans on (the +5 Max HP charm, the regen poultice, the team-wide epics).


func before_all() -> void:
	# The library caches its scan process-wide; force a fresh read so this suite never
	# inherits an index another test built.
	ItemLibrary.rescan()


# --- Scan -------------------------------------------------------------------

func test_library_finds_the_shipped_items():
	var items: Array[ItemResource] = ItemLibrary.all_items()
	assert_gt(items.size(), 0, "the content folder ships at least one item")
	assert_gt(items.size(), 8, "the launch set is roughly a dozen items, not a token one or two")


func test_every_item_resolves_by_id():
	for item in ItemLibrary.all_items():
		var resolved: ItemResource = ItemLibrary.get_item(item.id)
		assert_eq(resolved, item, "'%s' resolves back to itself by id" % String(item.id))


func test_unknown_and_empty_ids_resolve_to_null():
	assert_null(ItemLibrary.get_item(&"no_such_item"), "an unknown id is null, not an error")
	assert_null(ItemLibrary.get_item(""), "an empty id is null")
	assert_false(ItemLibrary.has_item(&"no_such_item"), "has_item agrees")


func test_all_ids_is_sorted_and_matches_all_items():
	var ids: Array[StringName] = ItemLibrary.all_ids()
	assert_eq(ids.size(), ItemLibrary.all_items().size(), "one id per item")
	var sorted_copy: Array[StringName] = ids.duplicate()
	sorted_copy.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	assert_eq(ids, sorted_copy, "all_ids() is sorted, so UI ordering is stable across runs")


# --- Content audit ----------------------------------------------------------

func test_content_validates_clean():
	var problems: Array[String] = ItemLibrary.validate()
	assert_eq(problems.size(), 0, "shipped item content has no problems: %s" % str(problems))


func test_every_item_id_is_unique():
	var seen: Dictionary = {}
	for item in ItemLibrary.all_items():
		var key: String = String(item.id)
		assert_false(key.is_empty(), "'%s' declares a non-empty id" % item.display_name)
		assert_false(seen.has(key), "item id '%s' is used exactly once" % key)
		seen[key] = true


func test_every_stat_modifier_names_a_real_unit_stat():
	# The whole point of VALID_STATS: a key outside it (a typo like "hp" or "max_health")
	# routes to nothing at all in UnitStats, so the item would read as a buff and do zero.
	for item in ItemLibrary.all_items():
		for raw_stat in item.stat_modifiers.keys():
			var stat_name: String = String(raw_stat)
			assert_true(
				stat_name in ItemResource.VALID_STATS,
				"item '%s' modifies '%s', which is a stat UnitStats can carry" % [String(item.id), stat_name]
			)


func test_every_item_actually_does_something():
	for item in ItemLibrary.all_items():
		var has_stats: bool = false
		for raw_stat in item.stat_modifiers.keys():
			if int(item.stat_modifiers[raw_stat]) != 0:
				has_stats = true
		var does_something: bool = has_stats or item.regen_per_turn > 0 or item.damage_reduction_percent > 0
		assert_true(does_something, "'%s' carries at least one live effect" % String(item.id))


func test_damage_reduction_never_reaches_invulnerability():
	for item in ItemLibrary.all_items():
		assert_lt(item.damage_reduction_percent, 100,
			"'%s' cannot reduce damage to zero" % String(item.id))


# --- Rarity / scope pools ---------------------------------------------------

func test_each_rarity_tier_ships_content():
	# Every tier must be non-empty or a drop roll that lands on it silently pays nothing.
	assert_gt(ItemLibrary.items_of_rarity(ItemResource.Rarity.COMMON).size(), 0, "commons exist")
	assert_gt(ItemLibrary.items_of_rarity(ItemResource.Rarity.RARE).size(), 0, "rares exist")
	assert_gt(ItemLibrary.items_of_rarity(ItemResource.Rarity.EPIC).size(), 0, "epics exist")


func test_commons_are_the_broadest_tier():
	var commons: int = ItemLibrary.items_of_rarity(ItemResource.Rarity.COMMON).size()
	var epics: int = ItemLibrary.items_of_rarity(ItemResource.Rarity.EPIC).size()
	assert_gt(commons, epics, "the collection is mostly commons -- epics are the payoff")


func test_both_scopes_ship_content():
	assert_gt(ItemLibrary.items_with_scope(ItemResource.Scope.UNIT).size(), 0, "per-unit items exist")
	assert_gt(ItemLibrary.items_with_scope(ItemResource.Scope.TEAM).size(), 0, "team-wide items exist")


func test_scope_filter_is_exclusive():
	for item in ItemLibrary.items_with_scope(ItemResource.Scope.TEAM):
		assert_true(item.is_team_item(), "'%s' really is team-scoped" % String(item.id))
	for item in ItemLibrary.items_with_scope(ItemResource.Scope.UNIT):
		assert_false(item.is_team_item(), "'%s' really is unit-scoped" % String(item.id))


# --- The specific authored numbers the design leans on ----------------------

func test_heartwood_charm_is_the_plus_five_max_hp_common():
	var item: ItemResource = ItemLibrary.get_item(&"heartwood_charm")
	assert_not_null(item, "heartwood_charm ships")
	assert_eq(int(item.rarity), int(ItemResource.Rarity.COMMON), "it is a common")
	assert_eq(int(item.scope), int(ItemResource.Scope.UNIT), "it buffs one unit")
	assert_eq(int(item.stat_modifiers.get("health", 0)), 5, "+5 Max HP")


func test_sagebloom_poultice_is_the_regen_rare():
	var item: ItemResource = ItemLibrary.get_item(&"sagebloom_poultice")
	assert_not_null(item, "sagebloom_poultice ships")
	assert_eq(int(item.rarity), int(ItemResource.Rarity.RARE), "it is a rare")
	assert_eq(item.regen_per_turn, 5, "heals 5 per turn")


func test_team_epics_are_the_squad_wide_payoff():
	var standard: ItemResource = ItemLibrary.get_item(&"elderroot_standard")
	assert_not_null(standard, "elderroot_standard ships")
	assert_eq(int(standard.scope), int(ItemResource.Scope.TEAM), "it is team-wide")
	assert_eq(int(standard.rarity), int(ItemResource.Rarity.EPIC), "and epic")
	assert_eq(int(standard.stat_modifiers.get("defense", 0)), 2, "+2 Defense to the squad")

	var banner: ItemResource = ItemLibrary.get_item(&"verdant_banner")
	assert_not_null(banner, "verdant_banner ships")
	assert_eq(int(banner.scope), int(ItemResource.Scope.TEAM), "it is team-wide")
	assert_eq(banner.regen_per_turn, 2, "heals the whole squad 2 per turn")


func test_effect_summary_reads_as_a_sentence_fragment():
	var charm: ItemResource = ItemLibrary.get_item(&"heartwood_charm")
	assert_eq(charm.effect_summary(), "+5 Max HP", "stat items summarise with the friendly stat name")
	var poultice: ItemResource = ItemLibrary.get_item(&"sagebloom_poultice")
	assert_eq(poultice.effect_summary(), "Heal 5 / turn", "regen items summarise as a per-turn heal")
	var ward: ItemResource = ItemLibrary.get_item(&"hollowbark_ward")
	assert_eq(ward.effect_summary(), "-15% damage taken", "reduction items summarise as a damage band")
