extends Node
class_name GrowthTracker

## The BATTLE-SIDE half of evolution: after a solo battle is decided, the squad units that
## fought (and survived a win) earn GROWTH in the [RosterLedger]. docs/design/EVOLUTION.md §4.1.
##
## MOUNTED PER BATTLE by [GameWorldManager] beside [ItemSystem] (same free-and-recreate
## discipline), so its once-per-battle latch can never leak into the next battle.
##
## WHO FOUGHT. The human squad units are ROLL-CALLED while they are alive -- at mount, on every
## turn start of the ACTIVE turn system (CONQUEST.md rule 2, the same sweep ItemSystem rides)
## and again at settle -- because a unit that dies is dropped by its Player (owner cleared)
## before GameEvents.unit_eliminated fires, so it could not be identified afterwards. A
## roll-called unit that is gone or dead at settle is FALLEN.
##
## WHEN IT SETTLES. Exactly once per battle, from whichever comes first:
##   * the elimination signals, re-deriving the outcome exactly like
##     [method ItemSystem._evaluate_outcome] (no enemy side left = win, no human left = loss);
##   * the end screen's reveal ([method settle_live], called by [GameOverScreen]), which also
##     covers battles decided by a map OBJECTIVE (seize, survive, slay the boss) with enemies
##     still standing.
##
## POST-SIMULATION ONLY. It reads live units and writes the ledger; nothing it does feeds back
## into the battle, so it is lockstep- and replay-neutral. It is GATED OFF where growth must not
## exist: replay playback, a networked match, an arena run, and any mode not in
## [member EvolutionRules.growth_modes].
##
## The award maths is the pure static [method compute_awards], shared with the duel.
##
## BATTLE FEATS ([BattleFeatTrigger]): the same settle also records each member's feat counters
## -- a win it fought in, the enemy KOs it landed (and the KO'd foes' elements), a clutch win at
## low HP -- from exactly what this roll call already sees ([method compute_feats]). Same gates,
## same post-simulation discipline.

const GROUP: StringName = &"growth_tracker"

## What THIS battle awarded, for the end screen: [{uid, character_id, name, gained, total,
## goal, ready}]. Static for the same reason ItemSystem's drop latch is: the summary reads it
## without holding this node. Cleared in [method setup] (= battle start).
static var _growth_this_battle: Array[Dictionary] = []

## Test seams. Empty = the live sources (PlayerManager.players / GameSettings.selected_squad).
var players_override: Array = []
var squad_override: Array = []
## Test seam: a fixed context for [method gate_reason] instead of [method live_context].
var context_override: Dictionary = {}

var _settled: bool = false
## instance_id -> { unit: WeakRef, uid: String, character_id: String } for every human squad
## unit seen alive this battle.
var _roll: Dictionary = {}
## uid -> enemy KOs credited this battle.
var _kos: Dictionary = {}
## uid -> {element: KOs} of the foes it felled (BattleFeatTrigger ELEMENT_KOS).
var _element_kos: Dictionary = {}
var _watched_turn_system = null


func setup() -> void:
	begin_battle_log()
	add_to_group(GROUP)
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())
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
	call_deferred(&"roll_call")


func _exit_tree() -> void:
	if TurnSystemManager != null and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	_unwatch_turn_system()
	if PlayerManager != null and PlayerManager.player_eliminated.is_connected(_on_player_eliminated):
		PlayerManager.player_eliminated.disconnect(_on_player_eliminated)
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if GameEvents.player_eliminated.is_connected(_on_player_eliminated):
			GameEvents.player_eliminated.disconnect(_on_player_eliminated)
		if GameEvents.unit_eliminated.is_connected(_on_unit_eliminated):
			GameEvents.unit_eliminated.disconnect(_on_unit_eliminated)


# --- The per-battle latch ----------------------------------------------------

static func begin_battle_log() -> void:
	_growth_this_battle.clear()


## A COPY of what this battle awarded (empty when nothing / not settled / gated).
static func growth_this_battle() -> Array[Dictionary]:
	return _growth_this_battle.duplicate(true)


## Replace the latch (tests and screenshot tooling seed the end screen with it).
static func seed_growth_this_battle(rows: Array) -> void:
	_growth_this_battle.clear()
	for r in rows:
		if r is Dictionary:
			_growth_this_battle.append((r as Dictionary).duplicate(true))


## The end screen's hook: settle the live tracker (if this battle mounted one) with the
## outcome the screen is about to show. No tracker = nothing happens.
static func settle_live(any_node: Node, won: bool) -> void:
	if any_node == null or not any_node.is_inside_tree():
		return
	for n in any_node.get_tree().get_nodes_in_group(GROUP):
		if n is GrowthTracker:
			(n as GrowthTracker).settle(won)


# --- Pure maths --------------------------------------------------------------

## Growth each member earns from one battle.
##
## [param rows]: [{uid: String, alive: bool, kos: int}], one per fielded squad unit (several
## rows for one uid collapse to the best one). [param won]: the human side won.
## Win: a SURVIVOR earns growth_per_win + growth_per_ko x min(kos, growth_ko_cap); a fallen unit
## earns nothing. Loss: every fielded unit earns growth_on_loss. Returns {uid: gained} with
## only positive entries.
static func compute_awards(rows: Array, won: bool, rules: EvolutionRules) -> Dictionary:
	var out: Dictionary = {}
	if rules == null:
		return out
	for row in rows:
		if not (row is Dictionary):
			continue
		var uid: String = String(row.get("uid", ""))
		if uid.is_empty():
			continue
		var gained: int = 0
		if won:
			if bool(row.get("alive", false)):
				gained = rules.growth_per_win \
					+ rules.growth_per_ko * mini(maxi(0, int(row.get("kos", 0))), maxi(0, rules.growth_ko_cap))
		else:
			gained = rules.growth_on_loss
		if gained > 0 and gained > int(out.get(uid, 0)):
			out[uid] = gained
	return out


## Why growth is OFF for a battle described by [param ctx] ("" = it is on). Keys:
## replay, networked, arena (bools), mode (String). Pure.
static func gate_reason(ctx: Dictionary, rules: EvolutionRules) -> String:
	if bool(ctx.get("replay", false)):
		return "replay"
	if bool(ctx.get("networked", false)):
		return "networked"
	if bool(ctx.get("arena", false)):
		return "arena"
	if rules == null or not rules.earns_growth_in(String(ctx.get("mode", ""))):
		return "mode"
	return ""


## The feat-counter DELTAS each member earns from one battle ([BattleFeatTrigger]).
##
## [param rows]: [{uid, alive, kos, element_kos: {element: n}, hp_ratio: float}], one per
## fielded squad unit that FOUGHT (rows sharing a uid -- two forms of one line -- merge: KO
## counts are per member already, so the largest is taken). Returns {uid: {wins, kos,
## clutch_wins, element_kos}} for every uid with something to add:
##   wins        +1 on a won battle (fallen or not: it fought in the win)
##   kos         its enemy KOs (won or lost)
##   clutch_wins +1 on a won battle it finished ALIVE at or under
##               [member EvolutionRules.clutch_hp_ratio] of its max HP
static func compute_feats(rows: Array, won: bool, rules: EvolutionRules) -> Dictionary:
	var out: Dictionary = {}
	var clutch_at: float = rules.clutch_hp_ratio if rules != null else 0.25
	for row in rows:
		if not (row is Dictionary):
			continue
		var uid: String = String(row.get("uid", ""))
		if uid.is_empty():
			continue
		var d: Dictionary = out.get(uid, RosterLedger.blank_feats())
		if won:
			d["wins"] = 1
			var ratio: float = float(row.get("hp_ratio", 1.0))
			if bool(row.get("alive", false)) and ratio > 0.0 and ratio <= clutch_at + 0.0001:
				d["clutch_wins"] = 1
		d["kos"] = maxi(int(d["kos"]), maxi(0, int(row.get("kos", 0))))
		var by = row.get("element_kos", {})
		if by is Dictionary:
			for el in by.keys():
				var n: int = maxi(0, int(by[el]))
				if n > int((d["element_kos"] as Dictionary).get(String(el), 0)):
					d["element_kos"][String(el)] = n
		out[uid] = d
	for uid in out.keys():
		var d: Dictionary = out[uid]
		if int(d["wins"]) == 0 and int(d["kos"]) == 0 and int(d["clutch_wins"]) == 0 \
				and (d["element_kos"] as Dictionary).is_empty():
			out.erase(uid)
	return out


# --- Live battle state -------------------------------------------------------

## The gate context for the battle running under [param any_node]'s tree.
static func live_context(any_node: Node) -> Dictionary:
	var arena := false
	var networked: bool = MatchLoadouts.is_active()
	if any_node != null and any_node.is_inside_tree():
		var a: Node = any_node.get_node_or_null("/root/ArenaController")
		arena = a != null and a.has_method("is_active") and bool(a.is_active())
		var ns: Node = any_node.get_node_or_null("/root/NetSession")
		if ns != null and ns.has_method("is_networked_match") and bool(ns.is_networked_match()):
			networked = true
	return {
		"replay": ReplayPlayback.is_playing(),
		"networked": networked,
		"arena": arena,
		"mode": detect_mode(any_node),
	}


## Which mode this battle is, as the ids [member EvolutionRules.growth_modes] lists:
## "arena", "story", "campaign", "challenge", "versus" (hotseat or network) or "skirmish"
## (every other solo battle, Siege included).
static func detect_mode(any_node: Node) -> String:
	if any_node == null or not any_node.is_inside_tree():
		return "skirmish"
	var arena: Node = any_node.get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("is_active") and bool(arena.is_active()):
		return "arena"
	var story: Node = any_node.get_node_or_null("/root/StoryController")
	if story != null and story.has_method("is_capturing") and bool(story.is_capturing()):
		return "story"
	var campaign: Node = any_node.get_node_or_null("/root/CampaignController")
	if campaign != null and campaign.has_method("is_capturing") and bool(campaign.is_capturing()):
		return "campaign"
	var challenge: Node = any_node.get_node_or_null("/root/ChallengeController")
	if challenge != null and challenge.has_method("is_capturing") and bool(challenge.is_capturing()):
		return "challenge"
	var settings: Node = any_node.get_node_or_null("/root/GameSettings")
	if settings != null and "game_mode" in settings \
			and int(settings.game_mode) != int(GameSettings.GameMode.SINGLE_PLAYER):
		return "versus"
	return "skirmish"


## Roll-call every live human squad unit (idempotent). Called at mount, every turn start and
## at settle; public so a test can drive it.
func roll_call() -> void:
	for player in _players():
		if player == null or not ("owned_units" in player):
			continue
		for unit in player.owned_units:
			if not is_instance_valid(unit) or _roll.has(unit.get_instance_id()):
				continue
			if not _is_human_squad_unit(unit):
				continue
			var uid: String = _uid_of(unit)
			if uid.is_empty():
				continue
			_roll[unit.get_instance_id()] = {
				"unit": weakref(unit), "uid": uid, "character_id": _character_id_of(unit),
			}


func _on_player_eliminated(_player) -> void:
	_evaluate_outcome()


func _on_unit_eliminated(unit, eliminator) -> void:
	# KO credit: a roll-called human unit felled a unit that is not one of ours.
	if is_instance_valid(eliminator) and is_instance_valid(unit) \
			and _roll.has(eliminator.get_instance_id()) and not _roll.has(unit.get_instance_id()):
		var killer: String = String(_roll[eliminator.get_instance_id()]["uid"])
		_kos[killer] = int(_kos.get(killer, 0)) + 1
		var el: String = ""
		if "character_resource" in unit and unit.character_resource != null:
			el = String(unit.character_resource.element)
		if not el.is_empty():
			if not _element_kos.has(killer):
				_element_kos[killer] = {}
			_element_kos[killer][el] = int((_element_kos[killer] as Dictionary).get(el, 0)) + 1
	_evaluate_outcome()


## Re-derive the outcome from the live players, like ItemSystem. Settles on a decided battle.
func _evaluate_outcome() -> void:
	if _settled:
		return
	roll_call()
	if _roll.is_empty():
		return   # nobody from the squad has been seen yet: not a battle this tracker judges
	var human_alive := false
	var enemy_alive := false
	for player in _players():
		if player == null or not player.has_units_remaining():
			continue
		if "is_neutral" in player and bool(player.is_neutral):
			continue
		if "is_ai" in player and bool(player.is_ai):
			enemy_alive = true
		else:
			human_alive = true
	if not enemy_alive and human_alive:
		settle(true)
	elif not human_alive:
		settle(false)


## Award this battle's growth for outcome [param won], once. Returns true when growth was
## written (false when already settled, gated off, or nobody earned anything).
func settle(won: bool) -> bool:
	if _settled:
		return false
	_settled = true
	var rules: EvolutionRules = EvolutionRules.current()
	var ctx: Dictionary = context_override if not context_override.is_empty() else live_context(self)
	if gate_reason(ctx, rules) != "":
		return false
	# A STORY battle's growth belongs to the journey's own member records (story save slot), not
	# this global store: StoryController awards it through StoryGrowth from the BattleResult
	# (fed by this tracker's roll call, see [method collect_rows]) and seeds the end-screen rows.
	if String(ctx.get("mode", "")) == "story":
		return false
	roll_call()
	var rows: Array = collect_rows()
	# Battle feats first: a battle can add to a feat counter without awarding any Growth (a KO in
	# a lost battle).
	var feats: Dictionary = compute_feats(rows, won, rules)
	for uid in feats.keys():
		RosterLedger.add_feats(uid, feats[uid])
	var awards: Dictionary = compute_awards(rows, won, rules)
	if awards.is_empty():
		if not feats.is_empty():
			RosterLedger.save()
		return false
	var shown: Dictionary = {}
	for row in rows:
		if bool(row["alive"]) or not shown.has(row["uid"]):
			shown[String(row["uid"])] = String(row.get("character_id", ""))
	var uids: Array = awards.keys()
	uids.sort()
	for uid in uids:
		var total: int = RosterLedger.add_growth(uid, int(awards[uid]))
		var cid: String = shown.get(uid, String(RosterLedger.form_of(uid)))
		var chr: CharacterResource = CharacterLibrary.get_character(cid)
		_growth_this_battle.append({
			"uid": String(uid),
			"character_id": cid,
			"name": chr.display_name if chr != null else cid,
			"gained": int(awards[uid]),
			"total": total,
			"goal": RosterLedger.next_growth_goal(RosterLedger.form_of(uid)),
			"ready": not RosterLedger.available_evolutions(uid).is_empty(),
		})
	RosterLedger.save()
	return true


## One row per roll-called squad unit: alive when it is still valid, alive and owned.
func collect_rows() -> Array:
	var rows: Array = []
	var ids: Array = _roll.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = _roll[id]
		var unit = (entry["unit"] as WeakRef).get_ref()
		var alive: bool = unit != null and is_instance_valid(unit) \
			and (not unit.has_method("is_alive") or unit.is_alive()) and _is_human_owned(unit)
		var ratio: float = 0.0
		if alive and "current_health" in unit and "max_health" in unit and int(unit.max_health) > 0:
			ratio = float(unit.current_health) / float(unit.max_health)
		rows.append({ "uid": String(entry["uid"]), "character_id": String(entry["character_id"]),
			"alive": alive, "kos": int(_kos.get(entry["uid"], 0)),
			"element_kos": (_element_kos.get(entry["uid"], {}) as Dictionary).duplicate(),
			"hp_ratio": ratio })
	return rows


# --- helpers -----------------------------------------------------------------

func _on_turn_system_activated(turn_system) -> void:
	if _watched_turn_system == turn_system:
		return
	_unwatch_turn_system()
	_watched_turn_system = turn_system
	if turn_system != null and turn_system.has_signal("turn_started") \
			and not turn_system.turn_started.is_connected(_on_turn_started):
		turn_system.turn_started.connect(_on_turn_started)


func _unwatch_turn_system() -> void:
	if _watched_turn_system != null and is_instance_valid(_watched_turn_system) \
			and _watched_turn_system.turn_started.is_connected(_on_turn_started):
		_watched_turn_system.turn_started.disconnect(_on_turn_started)
	_watched_turn_system = null


func _on_turn_started(_player) -> void:
	roll_call()


func _players() -> Array:
	if not players_override.is_empty():
		return players_override
	if PlayerManager != null and "players" in PlayerManager:
		return PlayerManager.players
	return []


func _squad() -> Array:
	if not squad_override.is_empty():
		return squad_override
	if GameSettings != null and GameSettings.has_method("get_selected_squad"):
		return GameSettings.get_selected_squad()
	return []


## Owned by the local human (slot 0, not AI, not neutral).
func _is_human_owned(unit) -> bool:
	var owner_player = unit.get_owner_player() if unit.has_method("get_owner_player") else null
	if owner_player == null or not ("player_id" in owner_player):
		return false
	if "is_ai" in owner_player and bool(owner_player.is_ai):
		return false
	if "is_neutral" in owner_player and bool(owner_player.is_neutral):
		return false
	return int(owner_player.player_id) == 0


## A human unit that was FIELDED FROM THE SQUAD: its character is one of the squad picks (a
## summon such as an undead body never is). An empty squad -- the map's authored roster, which
## no player-facing launch produces (Character Select needs at least one pick) -- earns nothing.
func _is_human_squad_unit(unit) -> bool:
	if not _is_human_owned(unit):
		return false
	var cid: String = _character_id_of(unit)
	if cid.is_empty():
		return false
	for id in _squad():
		if String(id) == cid:
			return true
	return false


## The ledger member a unit plays: a story battle tags units with story_member_id; otherwise
## the open-mode member of its line.
func _uid_of(unit) -> String:
	if unit.has_method("has_meta") and unit.has_meta(&"story_member_id"):
		return String(unit.get_meta(&"story_member_id"))
	return RosterLedger.member_for_character(_character_id_of(unit))


func _character_id_of(unit) -> String:
	if "character_resource" in unit and unit.character_resource != null:
		return String(unit.character_resource.character_id)
	return ""
