class_name StoryBattleBridge
extends RefCounted

## THE TACTICAL HALF of the story battle round trip (docs/design/OVERWORLD.md §4.6). The battle
## itself is the ordinary GameWorld: StoryController stages GameSettings exactly the way a
## campaign chapter does (SINGLE_PLAYER, the map, the AI difficulty, selected_squad = the
## fielded members' character ids), MapLoader fills player 0's Start slots in squad order, and
## then:
##
##   * [method prepare_board] (from GameWorldManager._setup_local_game, one guarded call) TAGS
##     each player-0 unit with meta "story_member_id" and sets its CARRIED HP (after spawn --
##     BattleSnapshot's "HP last" rule); ItemSystem then equips it from the story bag
##     (StoryController.loadout_for_unit) at the first turn boundary;
##   * [method build_result] (on GameEvents.battle_resolved) reads the board back into the SAME
##     [BattleResult] a duel reports: member HP by meta, KO'd members wounded, defeated foes.

const MEMBER_META := &"story_member_id"
## Meta on the unit that is the MAIN CHARACTER (a party entry flagged hero): its fall is always a
## game over ([StoryPermadeath]).
const HERO_META := &"story_hero"


## The members sent into a TACTICAL battle: healthy, in party order, up to [param squad_size].
static func fielded_members(state: StoryState, squad_size: int) -> Array[StoryPartyMember]:
	var out: Array[StoryPartyMember] = []
	for m in state.healthy_members():
		if out.size() >= maxi(1, squad_size):
			break
		out.append(m)
	return out


## The request.party snapshot for [param members].
static func party_snapshot(members: Array) -> Array:
	var out: Array = []
	for m in members:
		var sm := m as StoryPartyMember
		if sm == null:
			continue
		out.append({
			"member_id": sm.member_id,
			"character_id": sm.character_id,
			"current_hp": sm.current_hp,
			"item_id": sm.item_id,
			"growth": sm.growth.duplicate(true),
			"hero": sm.is_hero,
		})
	return out


## Tag the fielded units and set their carried HP. Returns the tracking record
## {members: {member_id: Unit}, enemies: [{unit, character_id}]} that [method build_result] reads.
static func prepare_board(map_loader, request: BattleRequest) -> Dictionary:
	var tracking: Dictionary = {"members": {}, "enemies": []}
	if map_loader == null or request == null or map_loader.map_root == null:
		return tracking
	var root: Node = map_loader.map_root
	var mine: Array = []
	var p1 := root.get_node_or_null("Player1")
	if p1 != null:
		for u in p1.get_children():
			if u is Unit:
				mine.append(u)
	for container_name in ["Player2", "Player3", "Player4"]:
		var c := root.get_node_or_null(container_name)
		if c == null:
			continue
		for u in c.get_children():
			if u is Unit:
				var ecid: String = String(u.character_resource.character_id) if u.character_resource != null else ""
				tracking["enemies"].append({"unit": u, "character_id": ecid})

	var claimed: Array = []
	for p in request.party:
		if not (p is Dictionary):
			continue
		var mid: String = String(p.get("member_id", ""))
		var cid: String = String(p.get("character_id", ""))
		for u in mine:
			if claimed.has(u):
				continue
			var ucid: String = String(u.character_resource.character_id) if u.character_resource != null else ""
			if ucid != cid:
				continue
			claimed.append(u)
			u.set_meta(MEMBER_META, mid)
			if bool(p.get("hero", false)):
				u.set_meta(HERO_META, true)
			var hp: int = int(p.get("current_hp", StoryPartyMember.HP_FULL))
			if hp != StoryPartyMember.HP_FULL and hp > 0 and u.unit_stats != null:
				u.unit_stats.set_stat("health", mini(hp, u.max_health))
			tracking["members"][mid] = u
			break
	return tracking


## Read the finished board into a [BattleResult] for [param outcome] ("victory"/"defeat").
static func build_result(outcome: String, request: BattleRequest, tracking: Dictionary,
		turns: int = 0) -> BattleResult:
	var result := BattleResult.make(request.encounter_id if request != null else "", outcome)
	result.turns = turns
	result.spar = request != null and request.is_spar()
	var members: Dictionary = tracking.get("members", {})
	if request != null:
		for p in request.party:
			var mid: String = String(p.get("member_id", ""))
			if not members.has(mid):
				# Never placed (the map had no start slot left for it): it sat the battle out --
				# carried HP, no Growth, and never counted as knocked out (let alone fallen).
				result.party_after.append({"member_id": mid,
					"current_hp": int(p.get("current_hp", StoryPartyMember.HP_FULL)), "wounded": false,
					"fought": false, "kos": 0, "ko_elements": {}})
				continue
			var u = members[mid]
			var alive: bool = u != null and is_instance_valid(u) and u.is_alive()
			var hp: int = int(u.current_health) if alive else 0
			# Every fielded member fought; its KOs (tracking["kos"], from the battle's
			# GrowthTracker roll call) feed EVOLUTION's growth maths.
			result.party_after.append({"member_id": mid, "current_hp": hp, "wounded": not alive,
				"fought": true, "kos": int((tracking.get("kos", {}) as Dictionary).get(mid, 0)),
				"ko_elements": ((tracking.get("ko_elements", {}) as Dictionary).get(mid, {}) as Dictionary).duplicate()})
	for rec in tracking.get("enemies", []):
		var e = rec.get("unit", null)
		if e == null or not is_instance_valid(e) or not e.is_alive():
			var cid: String = String(rec.get("character_id", ""))
			if not cid.is_empty():
				result.defeated.append(cid)
	return result


## The board GUARDS a story battle adds to the map's rules ([ProtectUnit] lose conditions for
## player 0's units): one per [method BattleRequest.protect_targets] entry ("Protect Linnea" --
## a guest ally, a party member), and one for the HERO (a party entry flagged hero; not in a
## spar). Each carries meta "story_reason" -- "protect:<name>" / "hero" -- which becomes the
## result's game-over reason when it fails. [param names] ({member_id: display name}) labels
## the hero's guard.
static func guards_for(request: BattleRequest, names: Dictionary = {}) -> Array[ProtectUnit]:
	var out: Array[ProtectUnit] = []
	if request == null:
		return out
	for t in request.protect_targets():
		# A character id reads as its name on the banner ("gem_knight" -> "Geode").
		var ch: CharacterResource = CharacterLibrary.get_character(StringName(t))
		var shown: String = ch.display_name if ch != null and not ch.display_name.is_empty() else t
		var g := ProtectUnit.make(t, shown, 0)
		g.set_meta(&"story_reason", "%s:%s" % [StoryPermadeath.REASON_PROTECT, shown])
		out.append(g)
	if not request.is_spar():
		for mid in request.hero_member_ids():
			var h := ProtectUnit.make(mid, String(names.get(mid, mid)), 0)
			h.set_meta(&"story_reason", StoryPermadeath.REASON_HERO)
			out.append(h)
	return out


## The game-over reason of the first of [param guards] that FAILED against [param units] (the
## board as the battle ended), or "".
static func failed_guard_reason(guards: Array, units: Array) -> String:
	for g in guards:
		if g is ProtectUnit and (g as ProtectUnit).evaluate({"units": units}) == WinCondition.Status.FAILED:
			return String((g as ProtectUnit).get_meta(&"story_reason", StoryPermadeath.REASON_PROTECT))
	return ""
