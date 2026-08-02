extends Node
class_name ItemSystem

## The BATTLE-SIDE half of the item feature: it stamps the player's equipped [ItemResource]s
## onto their units at the start of a battle, and rolls the post-battle drop that grows the
## collection.
##
## MOUNTED PER BATTLE by [GameWorldManager], exactly like [SpawnManager] and [HazardManager]:
## created fresh after the board is rebuilt and freed on the next map load, so no per-battle
## latch (applied units, drop-rolled) can ever leak into the following battle. The durable
## half of the feature -- what you own and what you have equipped -- lives in [ItemInventory],
## which is process-wide static state and survives every scene change.
##
## WHEN EQUIPS ARE APPLIED. Not at map load: the Arena spawns its squad AFTER the map is
## loaded, and no unit has an owner until PlayerManager's assign pass runs, so an "apply on
## map_loaded" sweep would see either no units or ownerless ones. Instead the sweep rides the
## ACTIVE TURN SYSTEM's [signal TurnSystemBase.turn_started] (re-bound through
## [signal TurnSystemManager.turn_system_activated]) -- the one per-turn signal that fires for
## human AND AI turns, which PlayerManager's does not. By the time any turn begins, every unit
## exists and is owned. Application is IDEMPOTENT per unit (a meta latch), so the repeat
## sweeps every subsequent turn cost a dictionary lookup and nothing else, and mid-battle
## reinforcements are picked up on the next turn boundary.
##
## WHOSE ITEMS APPLY TO WHOM. Two regimes, chosen by [method MatchLoadouts.is_active]:
##   * SOLO (Skirmish / Campaign / Challenge / Arena / hotseat): items are read off the LOCAL
##     player's [ItemInventory] and applied to player-slot 0, the human, exactly as they
##     always were. Replication is inactive, so this path is untouched.
##   * NETWORKED: each side announced its loadout in the lobby (see [MatchLoadouts]), so every
##     human slot is equipped -- the LOCAL slot from the local inventory, a REMOTE slot from
##     its announced (and library-whitelisted) card. Both peers therefore run the SAME
##     application through [method apply_loadout_items], which is the only way the two
##     simulations agree on a unit's stats. Before that replication existed a networked match
##     mounted no equips at all.

# --- Tuning -----------------------------------------------------------------

## Post-battle drop odds, as cumulative bands over a single [0,1) roll: EPIC 2%, then RARE
## 8%, then COMMON 25% -- 35% chance of something, 65% of nothing. One roll rather than three
## independent ones so the tiers are mutually exclusive and the maths is exactly the quoted
## numbers.
const DROP_EPIC_CHANCE: float = 0.02
const DROP_RARE_CHANCE: float = 0.08
const DROP_COMMON_CHANCE: float = 0.25

## Arena run-end payout is GUARANTEED (a whole run is a far bigger ask than one battle); only
## the RARITY is rolled, weighted by how deep the run got. Weights are [common, rare, epic].
const ARENA_WEIGHTS_SHALLOW: Array[float] = [1.0, 0.0, 0.0]   ## rounds cleared <= 2
const ARENA_WEIGHTS_MID: Array[float] = [0.35, 0.55, 0.10]    ## rounds cleared 3-5
const ARENA_WEIGHTS_DEEP: Array[float] = [0.15, 0.45, 0.40]   ## rounds cleared 6+

## Status ids the item channels install on a unit. Stable names so the HUD can label them and
## so a re-application matches (and therefore REFRESHES) the live instance.
const REGEN_STATUS_ID: StringName = &"item_regen"
const WARD_STATUS_ID: StringName = &"item_ward"

## Meta key latched on a unit once its items have been applied. On the unit rather than in a
## Dictionary here so a freed unit can never keep a stale entry alive.
const APPLIED_META: StringName = &"item_loadout_applied"

# --- Per-battle state -------------------------------------------------------

## The turn system this sweep is currently bound to (re-wired when one is activated).
var _watched_turn_system = null
## Latch: the post-battle drop is rolled exactly once, no matter how many elimination
## signals the deciding kill fires (the same guard every mode controller uses).
var _drop_rolled: bool = false


## Wire the system into this battle. Mirrors [method HazardManager.setup]: everything is
## connected here rather than in _ready so the node can be constructed, parented, and armed
## in one explicit step by [GameWorldManager].
func setup() -> void:
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())

	# Result capture rides the SAME elimination signals GameWorldManager and the mode
	# controllers trust. PlayerManager's is the reliable one; GameEvents' is a fallback that
	# does not always fire, and the per-unit one catches an objective decided by a single
	# death. All three funnel into one latched evaluation, so a triple-fire drops once.
	if PlayerManager != null and PlayerManager.has_signal("player_eliminated") \
			and not PlayerManager.player_eliminated.is_connected(_on_player_eliminated):
		PlayerManager.player_eliminated.connect(_on_player_eliminated)
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if GameEvents.has_signal("player_eliminated") \
				and not GameEvents.player_eliminated.is_connected(_on_player_eliminated):
			GameEvents.player_eliminated.connect(_on_player_eliminated)
		if GameEvents.has_signal("unit_eliminated") \
				and not GameEvents.unit_eliminated.is_connected(_on_unit_eliminated):
			GameEvents.unit_eliminated.connect(_on_unit_eliminated)

	# Best-effort early sweep for a board that is already populated and owned (a second battle
	# in the same run). Deferred so it never runs mid-setup; the turn-start sweep is the
	# guarantee, this is just an optimisation.
	call_deferred("apply_to_board")


# --- Applying equipped items ------------------------------------------------

## Stamp the player's loadout onto every player-owned unit currently on the board. Idempotent
## per unit, so calling it every turn is cheap. Returns how many units were newly equipped.
func apply_to_board() -> int:
	var board = CombatServices.board() if CombatServices != null else null
	if board == null or not board.has_method("all_units"):
		return 0
	var applied: int = 0
	for unit in board.all_units():
		if not _should_equip(unit):
			continue
		if apply_to_unit(unit):
			applied += 1
	return applied


## Apply the loadout for one unit. Returns true when this call did the work, false when the
## unit was already equipped (or could not be resolved).
##
## The ITEMS come from whichever side owns the unit: the local inventory in a solo match (and
## for the local slot of a networked one), the owner's replicated card otherwise. The
## APPLICATION is the one shared static either way, so a remote unit's buffs are computed by
## exactly the code that computes a local unit's.
func apply_to_unit(unit) -> bool:
	if not is_instance_valid(unit):
		return false
	return ItemSystem.apply_loadout_items(unit, loadout_for_slot(_slot_of(unit), _character_id_of(unit)))


## The items in force for [param character_id] as played by roster slot [param slot].
##
## Outside a networked match (or for our OWN slot inside one) this is just the local
## inventory's answer -- [method loadout_for]. For a REMOTE slot it is that peer's announced
## card, already whitelisted against the local libraries by [MatchLoadouts].
static func loadout_for_slot(slot: int, character_id: String) -> Array[ItemResource]:
	if not MatchLoadouts.is_active() or slot == MatchLoadouts.local_slot():
		return loadout_for(character_id)
	return MatchLoadouts.items_for(slot, character_id)


## Apply the UNIT item equipped to [param character_id] plus every TEAM item onto [param unit].
##
## Static and engine-agnostic so tests can drive it with a mock unit and so any future caller
## (a replay, a preview panel) can reuse the exact same application. Returns true when items
## were applied, false when the unit was already stamped.
##
## The three channels, and why each is applied the way it is:
##   * STATS go through [method ArenaAugmentApplier.apply_stat] -- the project's one engine
##     path for a flat stat delta. It uses modify_stat(permanent) for engine-writable stats,
##     which is what makes "+5 max health" raise the CEILING (Unit.max_health reads the base
##     stat) instead of merely overfilling the bar the way a temporary modifier would, and it
##     falls back to a direct current_<stat> write for evasion/crit/magic, which UnitStats has
##     no setter branch for. Permanent is safe because every unit builds a FRESH
##     UnitStatsResource from its CharacterResource at spawn, so nothing bleeds between
##     battles.
##   * REGEN is SUMMED across items and installed as ONE [RegenStatus] carrying the total. One
##     status, not one per item, so the REFRESH rule stays meaningful (see RegenStatus).
##   * DAMAGE REDUCTION takes the STRONGEST item only -- never a sum, never a product. This is
##     the project's reductions-refresh-never-stack rule, and it matches what
##     [method StatusController.status_damage_taken_scale] does downstream anyway (it returns
##     the single most-protective scale in force).
static func apply_loadout(unit, character_id: String) -> bool:
	return apply_loadout_items(unit, loadout_for(character_id))


## The application half of [method apply_loadout], taking the resolved [param items] directly.
##
## THE ONE PLACE ITEMS BECOME BUFFS. Splitting the "which items" question out of the "what do
## they do" answer is what lets a networked match equip a REMOTE player's units from their
## replicated card (see [MatchLoadouts]) without a second copy of the three channels -- the
## two peers run byte-identical maths on the same item list, which is the only way their
## simulations stay in step. The latch, the ordering and every aggregation rule live here.
static func apply_loadout_items(unit, items: Array[ItemResource]) -> bool:
	if unit == null:
		return false
	if unit.has_method("has_meta") and unit.has_meta(APPLIED_META):
		return false
	# Latch FIRST, so an item that somehow re-enters this path cannot double-apply.
	if unit.has_method("set_meta"):
		unit.set_meta(APPLIED_META, true)

	if items.is_empty():
		return false

	var regen_total: int = 0
	var best_reduction: int = 0
	for item in items:
		for raw_stat in item.stat_modifiers.keys():
			var amount: int = int(item.stat_modifiers[raw_stat])
			if amount != 0:
				ArenaAugmentApplier.apply_stat(unit, String(raw_stat), amount)
		regen_total += maxi(0, item.regen_per_turn)
		best_reduction = maxi(best_reduction, item.damage_reduction_percent)

	var controller = unit.get_status_controller() if unit.has_method("get_status_controller") else null
	if controller != null and controller.has_method("add_status"):
		if regen_total > 0:
			controller.add_status(build_regen_status(regen_total))
		if best_reduction > 0:
			controller.add_status(build_ward_status(best_reduction))
	return true


## The items that apply to [param character_id]: its equipped UNIT item (when it has one)
## followed by every filled TEAM slot. Pure read over [ItemInventory]; used by the battle
## application and by any UI that wants to preview a unit's loadout.
static func loadout_for(character_id: String) -> Array[ItemResource]:
	var items: Array[ItemResource] = []
	if not character_id.strip_edges().is_empty():
		var worn: ItemResource = ItemInventory.equipped_resource(character_id)
		if worn != null:
			items.append(worn)
	for team_item in ItemInventory.team_resources():
		items.append(team_item)
	return items


## A battle-long regen status carrying [param amount] HP/turn. REFRESH semantics come from
## [RegenStatus] itself.
static func build_regen_status(amount: int) -> RegenStatus:
	var status := RegenStatus.new()
	status.id = REGEN_STATUS_ID
	status.display_name = "Regenerating"
	status.duration_turns = -1
	status.stacking = StatusCondition.Stacking.REFRESH
	status.heal_per_turn = amount
	return status


## A battle-long damage-reduction status for [param percent]% less damage taken, expressed on
## the engine's existing [member StatusCondition.damage_taken_scale] channel. Clamped to
## 0..90% so an item can never make a unit invulnerable.
static func build_ward_status(percent: int) -> StatusCondition:
	var status := StatusCondition.new()
	status.id = WARD_STATUS_ID
	status.display_name = "Warded"
	status.duration_turns = -1
	status.stacking = StatusCondition.Stacking.REFRESH
	status.damage_taken_scale = 1.0 - (clampi(percent, 0, 90) / 100.0)
	return status


# --- Earning: post-battle drops ---------------------------------------------

## Decide the battle outcome from the live players and, on a win, roll the drop once.
##
## Re-derives win/loss exactly the way [method GameWorldManager._evaluate_game_end] and
## [ChallengeController] do -- no enemy left standing is a win, no human left is a loss --
## rather than depending on the end screen, so it works identically in every solo mode.
func _evaluate_outcome() -> void:
	if _drop_rolled:
		return
	if PlayerManager == null:
		return

	var human_alive: bool = false
	var enemy_alive: bool = false
	for player in PlayerManager.players:
		if player == null or not player.has_units_remaining():
			continue
		# NEUTRAL camps decide nothing: a battle is won when the real enemy is routed even if
		# a dormant wild camp is still standing.
		if "is_neutral" in player and bool(player.is_neutral):
			continue
		if "is_ai" in player and bool(player.is_ai):
			enemy_alive = true
		else:
			human_alive = true

	if enemy_alive or not human_alive:
		return

	_drop_rolled = true

	# ARENA rounds do NOT pay out per battle -- the run pays once at the end, weighted by how
	# far it got (ArenaController._finish_run). Rolling here too would make a 6-round run
	# worth seven drops.
	var arena = get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("is_active") and arena.is_active():
		return

	var reward: ItemResource = roll_drop()
	if reward != null:
		award(reward, self)


func _on_player_eliminated(_player) -> void:
	_evaluate_outcome()


func _on_unit_eliminated(_unit, _eliminator) -> void:
	_evaluate_outcome()


## Roll the post-battle drop with the LOCAL ECONOMY RNG. Returns the item won, or null for
## the (common) no-drop case.
##
## Deliberately its own randomized stream, NOT [member NetSession.match_rng]: the match RNG is
## the lockstep-replicated simulation stream, and consuming from it for a purely local,
## cosmetic-to-the-simulation reward would desync every peer. Drops are personal loot, not
## part of the battle.
static func roll_drop() -> ItemResource:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	return roll_drop_with_rng(rng)


## The pure, seedable form of [method roll_drop] -- the same odds, driven by a caller-supplied
## generator so a test can pin the distribution. One roll over cumulative bands:
## [0, 2%) epic, [2%, 10%) rare, [10%, 35%) common, else nothing.
static func roll_drop_with_rng(rng: RandomNumberGenerator) -> ItemResource:
	if rng == null:
		return null
	var roll: float = rng.randf()
	var rarity: int = -1
	if roll < DROP_EPIC_CHANCE:
		rarity = ItemResource.Rarity.EPIC
	elif roll < DROP_EPIC_CHANCE + DROP_RARE_CHANCE:
		rarity = ItemResource.Rarity.RARE
	elif roll < DROP_EPIC_CHANCE + DROP_RARE_CHANCE + DROP_COMMON_CHANCE:
		rarity = ItemResource.Rarity.COMMON
	if rarity < 0:
		return null
	return _pick_of_rarity(rarity, rng)


## The GUARANTEED end-of-run Arena payout for a run that cleared [param rounds_cleared]
## rounds. Local economy RNG, same reasoning as [method roll_drop].
static func roll_arena_reward(rounds_cleared: int) -> ItemResource:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	return roll_arena_reward_with_rng(rounds_cleared, rng)


## Seedable form of [method roll_arena_reward]. Always returns an item while the library has
## any content: only the rarity is at stake. A shallow run pays a Common; a mid run leans
## Rare; a deep run has a real shot at an Epic. Falls back down the rarity ladder when a tier
## happens to be empty, so an unlucky content edit still pays out something.
static func roll_arena_reward_with_rng(rounds_cleared: int, rng: RandomNumberGenerator) -> ItemResource:
	if rng == null:
		return null
	var weights: Array[float] = ARENA_WEIGHTS_SHALLOW
	if rounds_cleared >= 6:
		weights = ARENA_WEIGHTS_DEEP
	elif rounds_cleared >= 3:
		weights = ARENA_WEIGHTS_MID

	var total: float = weights[0] + weights[1] + weights[2]
	var roll: float = rng.randf() * total
	var rarity: int = ItemResource.Rarity.COMMON
	if roll >= weights[0] + weights[1]:
		rarity = ItemResource.Rarity.EPIC
	elif roll >= weights[0]:
		rarity = ItemResource.Rarity.RARE

	# Walk DOWN the ladder if the chosen tier has no content, then up, so a payout promised as
	# guaranteed really is.
	for candidate in [rarity, ItemResource.Rarity.RARE, ItemResource.Rarity.COMMON, ItemResource.Rarity.EPIC]:
		var item: ItemResource = _pick_of_rarity(int(candidate), rng)
		if item != null:
			return item
	return null


## Add [param item] to the collection, persist it, and toast it. The single "the player just
## won an item" entry point, so the grant and the announcement can never drift apart.
## [param host] is any node in the tree (used only to mount the banner); null / headless is
## fine and simply skips the visual.
static func award(item: ItemResource, host: Node) -> void:
	if item == null:
		return
	ItemInventory.grant(item.id)
	ItemInventory.save()
	ItemToast.present(item, host)


# --- internals --------------------------------------------------------------

## A uniformly-random item of [param rarity], or null when that tier ships nothing.
static func _pick_of_rarity(rarity: int, rng: RandomNumberGenerator) -> ItemResource:
	var pool: Array[ItemResource] = ItemLibrary.items_of_rarity(rarity)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## (Re)bind the per-turn sweep to the ACTIVE turn system. Mirrors GameWorldManager's
## tile-effect wiring: PlayerManager's turn signals do not fire on AI turns, so per-turn work
## must ride the turn system's own.
func _on_turn_system_activated(turn_system) -> void:
	if _watched_turn_system == turn_system:
		return
	if _watched_turn_system != null and is_instance_valid(_watched_turn_system) \
			and _watched_turn_system.turn_started.is_connected(_on_turn_started):
		_watched_turn_system.turn_started.disconnect(_on_turn_started)
	_watched_turn_system = turn_system
	if turn_system != null and not turn_system.turn_started.is_connected(_on_turn_started):
		turn_system.turn_started.connect(_on_turn_started)


func _on_turn_started(_player) -> void:
	apply_to_board()


## Should [param unit] be equipped at all? The two regimes described in the class note:
##
##   * Replication ACTIVE (a networked lobby seated us): every HUMAN slot is equipped -- our
##     own, plus any slot that announced a card. A slot that announced NOTHING is skipped
##     rather than falling back to the local inventory, because equipping a peer with OUR
##     items is precisely the desync this feature exists to remove.
##   * Replication INACTIVE (every solo / hotseat / arena path): unchanged -- the local human
##     in slot 0 and nobody else.
func _should_equip(unit) -> bool:
	if not is_instance_valid(unit):
		return false
	if not MatchLoadouts.is_active():
		return _is_player_unit(unit)
	var slot: int = _slot_of(unit)
	if slot < 0:
		return false
	return slot == MatchLoadouts.local_slot() or MatchLoadouts.has_peer_loadout(slot)


## True when [param unit] belongs to the LOCAL human (player slot 0) in a SOLO match. A
## networked match that never got a replicated loadout (the legacy lobby transport, or a peer
## that never announced) is still excluded outright: without both sides' cards the two peers
## would simulate different stats, so nobody is equipped at all.
func _is_player_unit(unit) -> bool:
	if not is_instance_valid(unit):
		return false
	if typeof(NetSession) == TYPE_OBJECT and NetSession != null \
			and NetSession.has_method("is_networked_match") and NetSession.is_networked_match():
		return false
	var owner_player = null
	if unit.has_method("get_owner_player"):
		owner_player = unit.get_owner_player()
	elif "owner_player" in unit:
		owner_player = unit.owner_player
	if owner_player == null or not ("player_id" in owner_player):
		return false
	if "is_ai" in owner_player and bool(owner_player.is_ai):
		return false
	return int(owner_player.player_id) == 0


## The roster slot of [param unit]'s owner, or -1 when it has none, is AI, or is a neutral
## camp. Slot IS player_id: NetSession seats participants into the same numbering
## PlayerManager assigns (see [method NetSession.local_slot] and its readers).
func _slot_of(unit) -> int:
	if not is_instance_valid(unit):
		return -1
	var owner_player = null
	if unit.has_method("get_owner_player"):
		owner_player = unit.get_owner_player()
	elif "owner_player" in unit:
		owner_player = unit.owner_player
	if owner_player == null or not ("player_id" in owner_player):
		return -1
	if "is_ai" in owner_player and bool(owner_player.is_ai):
		return -1
	if "is_neutral" in owner_player and bool(owner_player.is_neutral):
		return -1
	return int(owner_player.player_id)


## The character id backing [param unit] ("" for a unit with no CharacterResource, e.g. a
## legacy scene-authored unit -- it simply gets the team items and no personal one).
func _character_id_of(unit) -> String:
	if "character_resource" in unit and unit.character_resource != null:
		return String(unit.character_resource.character_id)
	return ""
