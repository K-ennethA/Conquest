extends RefCounted

## EVOLUTION TEST FIXTURE: a test-only Barkling -> Mycothrall edge with the old Growth + wins
## triggers (Growth 3 AND 2 won battles, EVOLUTION.md §3.2a), so the evolution MECHANICS suites
## (ledger, offers, the evolution screen, story wiring) do not depend on whichever lines the
## shipped content happens to hold. It is never on disk under game/characters/evolutions/ --
## it is served beside the shipped edges through [method EvolutionLibrary.add_extra_edges].
##
## Mycothrall: an existing, battle-ready, pickable roster unit (model + moves) in no shipped line
## and used by none of the evolution suites for anything else (Petalfang, the obvious pick, is
## already the example Sunstone edge's target and a common wild foe / party member there).
## Barkling's SHIPPED edge (tree_grunt__ember_stump, the Sunstone) stays in the graph beside it,
## so Barkling branches; it needs a USED item, so it is never offered by Growth / wins alone.
##
## EvolutionLibrary is static, global state: ALWAYS pair [method install] with [method uninstall]
## (before_each / after_each, or before_all / after_all) so the edge cannot leak into other suites.
##
##   const EvoFixture := preload("res://tests/helpers/evolution_fixture.gd")
##   func before_each() -> void: _edge = EvoFixture.install()
##   func after_each() -> void: EvoFixture.uninstall()

const EDGE_ID: StringName = &"tree_grunt__mycothrall_test"
const FROM_ID: StringName = &"tree_grunt"
const TO_ID: StringName = &"mycothrall"
const FROM_NAME: String = "Barkling"
const TO_NAME: String = "Mycothrall"
const FLAVOR: String = "The sapling finally takes root."
const GROWTH_REQUIRED: int = 3
const WINS_REQUIRED: int = 2


## A fresh copy of the fixture edge (not registered anywhere).
static func build() -> EvolutionResource:
	var growth := GrowthTrigger.new()
	growth.growth_required = GROWTH_REQUIRED
	var wins := BattleFeatTrigger.new()
	wins.feat = 0   # BattleFeatTrigger feat 0 == won battles
	wins.count = WINS_REQUIRED
	var e := EvolutionResource.new()
	e.id = EDGE_ID
	e.from_id = FROM_ID
	e.to_id = TO_ID
	e.flavor = FLAVOR
	var trigs: Array[EvolutionTrigger] = [growth, wins]
	e.triggers = trigs
	return e


## Register a fresh fixture edge with [EvolutionLibrary] (rebuilds its graph) and return it.
static func install() -> EvolutionResource:
	var e := build()
	EvolutionLibrary.add_extra_edges([e])
	return e


## Drop every extra edge (this fixture's and any example edge) and rebuild from content.
static func uninstall() -> void:
	EvolutionLibrary.clear_extra_edges()


## The installed fixture edge, or null when it is not installed.
static func edge() -> EvolutionResource:
	return EvolutionLibrary.get_edge(EDGE_ID)
