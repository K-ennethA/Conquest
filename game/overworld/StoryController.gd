extends Node

## STORY MODE'S AUTOLOAD (docs/design/OVERWORLD.md §4.6) -- the same shape as
## CampaignController / ArenaController: it owns everything that must outlive a scene change.
##
##   * the SESSION: the live [StoryState], its save slot (user://story/slot_<n>.json via
##     [StorySaveManager]), the [StoryRuleset] and the [HeroResource];
##   * the SCRIPT RUNNER: one [StoryScriptRunner] whose scripts survive the battle round trip
##     (a StartBattle awaits [method run_battle] on THIS node, and the script resumes on the new
##     overworld's host once it re-attaches -- [method overworld_ready]);
##   * the BATTLE ROUND TRIP, battle-kind agnostic:
##
##       run_battle(request) -> begin_battle: fill party / seed / return point, autosave,
##           tactical -> stage GameSettings like a campaign chapter -> GameWorld
##           duel     -> DuelLauncher.launch (DuelController.launch_from_story -> DuelStage;
##                       the debug DuelStub only when no real launcher is registered)
##       ...battle...
##       report_battle_result(result)   <- EXACTLY ONCE per battle (the duel on its results
##                                          card's Continue, or the tactical bridge on
##                                          GameEvents.battle_resolved)
##       tactical: GameOverScreen shows [method end_actions] (Continue / Return to Wayshrine /
##                 Try Again) and calls [method on_end_action]
##       _conclude: StoryResultApplier.apply (HP, rewards, GROWTH) -> whiteout? -> autosave
##                  -> overworld
##       overworld_ready(host) -> EVOLUTION offers (an EvolutionScreen per member with one
##           pending, [method offer_pending_evolutions]) -> battle_concluded(result) -> the
##           paused script continues (e.g. the befriend prompt)
##
##   * EVOLUTION AUTO-OFFERS (docs/design/DECISIONS.md #27, docs/STORY_MODE.md "Evolution in
##     story"): whenever requirements MAY have become met, the Evolution screen is offered for
##     eligible members -- never for a member on HOLD. The events: after a battle (every available
##     edge), entering a new area ("area": warp_to), a story flag set / a member joining ("flag" /
##     "party": StoryState.drain_changes, flushed once the script that set them ends), using an
##     item from the bag ([method use_item_on_member]). A non-battle event only offers the edges
##     it could have changed ([method EvolutionResource.responds_to]), so "Not now" never turns
##     into a nag on every step or area change -- the offer returns at the next NEW relevant
##     event, and the member's EVOLVE button in Journey -> Party is always there
##     ([method evolve_from_menu]).
##
## GameOverScreen finds this node through the "battle_mode_controller" group and only while
## [method is_active] (a story tactical battle is live); every other battle sees nothing.

const OVERWORLD_SCENE := "res://game/overworld/OverworldScene.tscn"
const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const STORY_START_SCENE := "res://game/overworld/ui/StoryStartScreen.tscn"
const AREAS_DIR := "res://game/overworld/content/areas/"
## GameOverScreen's mode-action lookup group.
const MODE_GROUP := &"battle_mode_controller"

const ACTION_CONTINUE := "continue"
const ACTION_RETRY := "retry"
const ACTION_WAYSHRINE := "wayshrine"
## GAME OVER (DECISIONS.md #29 refinements): back to the last save / to the title screen.
const ACTION_LOAD_SAVE := "load_save"
const ACTION_TITLE := "title"

## Emitted (deferred, once the overworld is back) with the concluded [BattleResult]: this is
## what a paused StartBattle resumes on.
signal battle_concluded(result)
signal session_changed()
## An [EvolutionScreen] was opened for a party member (tests / tools drive it from here).
signal evolution_offered(screen)
## A battle ended the journey: the [BattleResult] (its game_over_reason says why). A duel shows
## the [StoryGameOverScreen]; a tactical battle's end screen offers the same two choices.
signal game_over(result)

var _state: StoryState = null
var _slot: int = 0
var _ruleset: StoryRuleset = null
var _hero: HeroResource = null
var _runner: StoryScriptRunner = StoryScriptRunner.new()
var _host = null
var _area_cache: Dictionary = {}
## Prepares the areas the current one's warps lead to in the background (AreaPrewarmer).
var _prewarmer: AreaPrewarmer = AreaPrewarmer.new()

# --- The battle in flight -------------------------------------------------------
var _active_request: BattleRequest = null
var _reported: bool = false
var _last_result: BattleResult = null
var _tracking: Dictionary = {}
## The journey as it stood before the battle (Try Again restores it).
var _pre_battle: Dictionary = {}
var _resume_pending: bool = false
var _resume_result: BattleResult = null
## A line shown on the next overworld boot ("You retreat to the Wayshrine...").
var _pending_message: String = ""
## Offer pending evolutions once the overworld is back (set by _conclude, not after a whiteout).
var _offer_after_battle: bool = false
## Evolution auto-offer events not offered yet: {kinds: Array[String], flags: Array[String]}
## ([method note_evolution_event] / [method flush_evolution_events]).
var _pending_event: Dictionary = {}
## An offer chain is on screen (never stack a second one on top).
var _offering: bool = false

## Tests switch scene changes off and drive the round trip by hand.
var scene_changes_enabled: bool = true


func _ready() -> void:
	name = "StoryController"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(MODE_GROUP)
	_ruleset = StoryRuleset.load_default()
	_hero = HeroResource.load_default()
	# The debug duel stub is only a FALLBACK: DuelController registers the real launcher, and a
	# stub never replaces a real one (DuelLauncher.register), so the stub fills the seam only
	# when no real duel is present.
	if OS.is_debug_build():
		register_debug_duel_stub()
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and GameEvents.has_signal("battle_resolved"):
		GameEvents.battle_resolved.connect(_on_battle_resolved)


## Put the debug DuelStub in the duel seam (never over a real launcher). Public so tests that
## swapped in a fake launcher can restore the shipped state.
func register_debug_duel_stub() -> void:
	DuelLauncher.register(func(r: BattleRequest) -> Dictionary: return DuelStub.launch(r), true)


func _exit_tree() -> void:
	# Worker tasks must be waited for before the engine tears down.
	_prewarmer.finish(self)
	# The stub launcher is a Callable bound to this node; a static holding it past shutdown
	# crashes the engine on exit. A real launcher (another autoload) is left alone.
	if DuelLauncher.is_stub():
		DuelLauncher.reset()


func _process(delta: float) -> void:
	if _state != null and not get_tree().paused:
		_state.play_seconds += delta
	_prewarmer.poll(self)


func _notification(what: int) -> void:
	# A closed window / a phone app killed in the background must not lose the walk since the
	# last Wayshrine. Never mid-battle: the pre-battle autosave already stands for that.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _state != null and _slot > 0 and _active_request == null:
			save_game()


# =====================================================================================
#  Session
# =====================================================================================

func has_session() -> bool:
	return _state != null


func state() -> StoryState:
	return _state


func slot() -> int:
	return _slot


func ruleset() -> StoryRuleset:
	return _ruleset


func hero() -> HeroResource:
	return _hero


func hero_name() -> String:
	return _hero.display_name if _hero != null else "Wren"


func hero_speaker_id() -> String:
	return String(_hero.speaker_id) if _hero != null else "hero"


func party_cap() -> int:
	return _ruleset.party_cap if _ruleset != null else 6


## A brand-new journey in [param slot] (0 = in-memory only, never saved: tools / tests / running
## the overworld scene directly) at difficulty [param tier] ("classic" / "casual"; "" = the
## ruleset's default_tier -- the New Journey screen always passes the player's pick). Returns
## {success, reason}; reason "unknown_tier" for a tier that does not exist.
func new_journey(slot: int = 0, tier: String = "") -> Dictionary:
	var s := StoryState.new()
	var rs: StoryRuleset = _ruleset if _ruleset != null else StoryRuleset.new()
	var t: String = tier if not tier.is_empty() else rs.default_tier
	if not StoryState.is_tier(t):
		return {"success": false, "reason": "unknown_tier"}
	s.tier = t
	s.rng_seed = _fresh_seed()
	s.gold = rs.starting_gold
	for cid in rs.starting_party:
		s.add_member(String(cid), "", rs.party_cap)
	var area: OverworldAreaResource = load_area(String(rs.start_area))
	if area == null:
		return {"success": false, "reason": "no_start_area"}
	var e: Dictionary = area.entry(String(rs.start_entry))
	if e.is_empty():
		return {"success": false, "reason": "no_start_entry"}
	s.set_location(String(rs.start_area), e["cell"], String(e["facing"]))
	# A whiteout before any shrine is touched wakes you at the start town's Wayshrine.
	var resp_entry: String = "wayshrine" if not area.entry("wayshrine").is_empty() else String(rs.start_entry)
	s.respawn = {"area_id": String(rs.start_area), "entry": resp_entry}
	s.mark_visited(String(rs.start_area))
	s.grace_steps = rs.grace_steps
	_begin_session(s, slot)
	if slot > 0:
		save_game()
	return {"success": true, "reason": ""}


## Load [param slot]. {success, reason}.
func continue_journey(slot: int) -> Dictionary:
	var loaded: Dictionary = StorySaveManager.load_state(slot)
	if not bool(loaded.get("success", false)):
		return {"success": false, "reason": String(loaded.get("reason", "load_failed"))}
	var s: StoryState = loaded["state"]
	if load_area(s.location_area()) == null:
		return {"success": false, "reason": "unknown_area"}
	_begin_session(s, slot)
	return {"success": true, "reason": ""}


## Adopt an externally built state (tests, tools).
func begin_session_with(s: StoryState, slot: int = 0) -> void:
	_begin_session(s, slot)


func _begin_session(s: StoryState, slot: int) -> void:
	_disarm_battle()
	_state = s
	_slot = slot
	_resume_pending = false
	_resume_result = null
	_pending_message = ""
	_offer_after_battle = false
	_pending_event = {}
	_offering = false
	if s != null:
		s.drain_changes()   # loading a save "sets" every flag: not news
	_runner = StoryScriptRunner.new()
	session_changed.emit()


## Drop the session (Title). Saves first when it has a slot.
func end_session() -> void:
	if _state != null and _slot > 0 and _active_request == null:
		save_game()
	_disarm_battle()
	_prewarmer.release_held()
	_state = null
	_slot = 0
	_host = null
	_runner = StoryScriptRunner.new()
	session_changed.emit()


## The journey's difficulty tier ("" without a session).
func tier() -> String:
	return _state.tier if _state != null else ""


## Journey -> Difficulty: move the journey DOWN a tier (Classic -> Casual; never back up) and
## save. {success, reason} -- reasons as [method StoryState.lower_tier], or "no_session".
func lower_tier(to: String = StoryState.TIER_CASUAL) -> Dictionary:
	if _state == null:
		return {"success": false, "reason": "no_session"}
	var r: Dictionary = _state.lower_tier(to)
	if bool(r["ok"]):
		save_game()
	return {"success": bool(r["ok"]), "reason": String(r["reason"])}


func save_game() -> Dictionary:
	if _state == null:
		return {"success": false, "reason": "no_session"}
	if _slot <= 0:
		return {"success": false, "reason": "no_slot"}
	return StorySaveManager.save(_slot, _state)


## Change to the overworld scene (after new_journey / continue_journey).
func enter_overworld() -> void:
	_change_scene(OVERWORLD_SCENE)


## Save, end the session and go to the title screen.
func return_to_title() -> void:
	end_session()
	_change_scene(MAIN_MENU_SCENE)


# =====================================================================================
#  Areas + moving between them
# =====================================================================================

static func area_path(area_id: String) -> String:
	return "%s%s/area.tres" % [AREAS_DIR, area_id]


## Load a shipped area by id (trusted content), or null.
func load_area(area_id: String) -> OverworldAreaResource:
	if area_id.is_empty():
		return null
	if _area_cache.has(area_id):
		return _area_cache[area_id]
	var path: String = area_path(area_id)
	if not ResourceLoader.exists(path):
		return null
	var a := load(path) as OverworldAreaResource
	if a != null:
		_area_cache[area_id] = a
	return a


## True when area [param area_id] is already loaded (no disk read needed).
func has_area_cached(area_id: String) -> bool:
	return _area_cache.has(area_id)


## Take an area resource loaded elsewhere (AreaPrewarmer's background load) into the cache.
func adopt_area(area_id: String, a: OverworldAreaResource) -> void:
	if a != null and not _area_cache.has(area_id):
		_area_cache[area_id] = a


## Start preparing, in the background, every area [param area]'s warps lead to (the overworld
## calls this once it has booted an area). See [AreaPrewarmer].
func prewarm_neighbours(area: OverworldAreaResource) -> void:
	_prewarmer.request_neighbours(area, _state)


## The background area prewarmer (tests / perf tools).
func prewarmer() -> AreaPrewarmer:
	return _prewarmer


func current_area() -> OverworldAreaResource:
	return load_area(_state.location_area()) if _state != null else null


## Every shipped area id (content validation, menus).
static func all_area_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(AREAS_DIR)
	if dir == null:
		return out
	for d in dir.get_directories():
		if ResourceLoader.exists(area_path(d)):
			out.append(d)
	out.sort()
	return out


func area_display_name(area_id: String) -> String:
	var a: OverworldAreaResource = load_area(area_id)
	return a.display_name if a != null else area_id.capitalize()


## The host reports every completed step / turn so saves and battle return points are exact.
func note_player_position(cell: Vector3i, facing: String) -> void:
	if _state != null:
		_state.set_location(_state.location_area(), cell, facing)


## Move to [param area_id] at [param entry_id] (a warp or a WarpCommand): location, visited,
## grace steps, autosave, scene change. [param warp] + [param from_cell] keep the row/column
## on an edge exit. {success, reason}.
func warp_to(area_id: String, entry_id: String, from_cell: Vector3i = Cells.INVALID,
		warp: WarpEntity = null) -> Dictionary:
	if _state == null:
		return {"success": false, "reason": "no_session"}
	var target: OverworldAreaResource = load_area(area_id)
	if target == null:
		return {"success": false, "reason": "unknown_area"}
	var e: Dictionary = target.entry(entry_id)
	if e.is_empty():
		return {"success": false, "reason": "unknown_entry"}
	var cell: Vector3i = e["cell"]
	if warp != null and from_cell != Cells.INVALID:
		var c2: Vector3i = warp.arrival_cell(from_cell, cell)
		if target.in_bounds(c2):
			var g := OverworldGrid.build(target, _state)
			if g.is_walkable(c2):
				cell = c2
	if area_id != _state.location_area():
		_state.on_area_changed()
		# A new place may meet a Location / Weather requirement: offered once the area is up.
		note_evolution_event("area")
	_state.set_location(area_id, cell, String(e["facing"]))
	_state.mark_visited(area_id)
	_state.grace_steps = _ruleset.grace_steps if _ruleset != null else 3
	save_game()
	_change_scene(OVERWORLD_SCENE)
	return {"success": true, "reason": ""}


# =====================================================================================
#  Scripts
# =====================================================================================

func is_script_running() -> bool:
	return _runner.is_running()


func runner() -> StoryScriptRunner:
	return _runner


## Run [param commands] for the area's owner entity. Fire-and-forget from the host's point of
## view (the runner lives here, so the script outlives the host). Returns false when another
## script holds the lock or there is no session.
func run_script(commands: Array, owner_id: String = "", speaker_id: String = "",
		speaker_name: String = "") -> bool:
	if _state == null or _runner.is_running() or commands.is_empty():
		return false
	var ctx := ScriptContext.new(_state, _host, self, _state.location_area())
	ctx.owner_id = owner_id
	ctx.vars["owner_speaker_id"] = speaker_id
	ctx.vars["owner_speaker_name"] = speaker_name
	_runner.run(commands, ctx)
	return true


## The overworld scene finished booting: retarget the paused script at the new host, and resume
## a script that was waiting on a battle. Returns the one-off message to show (whiteout), or "".
func overworld_ready(host) -> String:
	_host = host
	var ctx: ScriptContext = _runner.context()
	if ctx != null:
		ctx.host = host
		ctx.area_id = _state.location_area() if _state != null else ctx.area_id
	var msg: String = _pending_message
	_pending_message = ""
	if _resume_pending:
		_resume_pending = false
		call_deferred("_emit_concluded", _resume_result)
	return msg


func _emit_concluded(result) -> void:
	# "After the battle, X is evolving!" -- before the paused script resumes (EVOLUTION.md §6).
	if _offer_after_battle:
		_offer_after_battle = false
		# The battle's rewards may have set flags: every available edge is offered anyway.
		if _state != null:
			_state.drain_changes()
		await offer_pending_evolutions({"trigger": "after_battle"})
	battle_concluded.emit(result)


## Chain an [EvolutionScreen] for every party member with an evolution available (party order),
## each awaited before the next -- members on HOLD are skipped (DECISIONS.md #27). With an
## [param event] ({kinds, flags}) only the edges it could have changed are offered (no nag
## loop); empty = every available edge (after a battle). Evolve = the member BECOMES the form
## ([StoryGrowth.evolve], which also unlocks it for open modes); Not now = nothing written: the
## member's EVOLVE in Journey -> Party stays, and the offer returns at the next relevant event.
## Saves when anything evolved. Returns how many members evolved.
func offer_pending_evolutions(extra: Dictionary = {}, event: Dictionary = {}) -> int:
	if _state == null or not is_inside_tree():
		return 0
	if _offering:
		# One chain at a time: fold this one into the next flush.
		for k in event.get("kinds", ["battle"]):
			note_evolution_event(String(k), event.get("flags", []))
		return 0
	_offering = true
	var evolved: int = 0
	for mid in StoryGrowth.pending(_state, StoryGrowth.evolution_context(_state, extra), true, event):
		var m: StoryPartyMember = _state.member(mid) if _state != null else null
		if m == null:
			continue
		# Fresh per member: an earlier evolution changed the party the context describes.
		var ctx: Dictionary = StoryGrowth.evolution_context(_state, extra)
		var edges: Array[EvolutionResource] = StoryGrowth.offerable_for(m, ctx, event)
		if edges.is_empty():
			continue
		if await offer_evolution(mid, edges, ctx, false, false):
			evolved += 1
	_offering = false
	if evolved > 0:
		save_game()
	return evolved


## Record an auto-offer event of [param kind] ("area", "flag", "party", "item", "battle"; flag
## events name their [param flags]) to offer at the next [method flush_evolution_events].
func note_evolution_event(kind: String, flags: Array = []) -> void:
	var kinds: Array = _pending_event.get("kinds", [])
	if not kinds.has(kind):
		kinds.append(kind)
	_pending_event["kinds"] = kinds
	var fl: Array = _pending_event.get("flags", [])
	for f in flags:
		if not fl.has(String(f)):
			fl.append(String(f))
	_pending_event["flags"] = fl


## The events waiting to be offered (a copy; {} when none).
func pending_evolution_event() -> Dictionary:
	return _pending_event.duplicate(true)


## Offer what the pending events (plus flags set / members joined since the last flush) made due.
## Called by the overworld once an area is up and whenever a script ends; waits (keeps the
## events) while a script runs or another offer chain is on screen. Returns how many evolved.
func flush_evolution_events() -> int:
	if _state == null or not is_inside_tree() or _offering or _runner.is_running():
		return 0
	var changes: Dictionary = _state.drain_changes()
	if not (changes["flags"] as Array).is_empty():
		note_evolution_event("flag", changes["flags"])
	if bool(changes["party"]):
		note_evolution_event("party")
	if _pending_event.is_empty():
		return 0
	var event: Dictionary = _pending_event
	_pending_event = {}
	return await offer_pending_evolutions({"trigger": "event"}, event)


## EVOLVE LATER (Journey -> Party, DECISIONS.md #27): open the Evolution screen for
## [param member_id] over every edge it can take now -- or by USING an item the bag holds
## ([StoryGrowth.menu_edges]) -- whatever its Hold. {success, reason, evolved}; reason
## "not_available" when nothing is due.
func evolve_from_menu(member_id: String) -> Dictionary:
	var m: StoryPartyMember = _state.member(member_id) if _state != null else null
	if m == null:
		return {"success": false, "reason": "no_member", "evolved": false}
	var ctx: Dictionary = StoryGrowth.evolution_context(_state, {"trigger": "menu"})
	var menu: Dictionary = StoryGrowth.menu_edges(m, ctx)
	if (menu["edges"] as Array).is_empty():
		return {"success": false, "reason": "not_available", "evolved": false}
	var evolved: bool = await offer_evolution(member_id, menu["edges"], ctx, false, true, menu["use_items"])
	return {"success": true, "reason": "", "evolved": evolved}


## USE an item from the bag on a member (Journey -> Bag -> Use) -- THE one "use an item on a party
## member" flow (DECISIONS.md #26, #28):
##   * a CONSUMABLE (heal / cure / revive, [ConsumableEffect]) applies at once by
##     [method StoryState.use_consumable]: a use that helps spends one and saves the journey; a
##     use that would be wasted (full HP, a healthy member for a revive...) is refused and spends
##     nothing -- reason = the [ConsumableEffect] refusal ("full_hp", "not_knocked_out", ...).
##     The result also carries {used, healed, revived}.
##   * an EVOLUTION item: when it makes one of the member's evolutions available ([UseItemTrigger])
##     its Evolution screen is offered (Hold does not apply: the player asked); a confirmed
##     evolution SPENDS the item, Not now keeps it.
## {success, reason, evolved}; reason "no_item" / "no_member" / "no_effect" (or a consumable's).
func use_item_on_member(item_id: String, member_id: String) -> Dictionary:
	if _state == null:
		return {"success": false, "reason": "no_session", "evolved": false}
	if _state.item_count(item_id) <= 0:
		return {"success": false, "reason": "no_item", "evolved": false}
	var m: StoryPartyMember = _state.member(member_id)
	if m == null:
		# A FALLEN member (Classic) is out of the party: no item -- revive or evolution -- helps.
		var why: String = "fallen" if _state.fallen_member(member_id) != null else "no_member"
		return {"success": false, "reason": why, "evolved": false}
	var item: ItemResource = ItemLibrary.get_item(item_id)
	if item != null and item.is_consumable():
		var used: Dictionary = _state.use_consumable(item_id, member_id)
		var ok: bool = bool(used.get("ok", false))
		if ok:
			save_game()
		return {"success": ok, "reason": String(used.get("reason", "")), "evolved": false, "used": ok,
			"healed": int(used.get("healed", 0)), "revived": bool(used.get("revived", false))}
	var ctx: Dictionary = StoryGrowth.evolution_context(_state, {"trigger": "use_item", "used_item": item_id})
	var edges: Array[EvolutionResource] = StoryGrowth.edges_for_item(m, item_id, ctx)
	if edges.is_empty():
		return {"success": false, "reason": "no_effect", "evolved": false}
	var evolved: bool = await offer_evolution(member_id, edges, ctx)
	return {"success": true, "reason": "", "evolved": evolved}


## Put party member [param member_id] on / off HOLD (no automatic evolution prompts) and save.
func set_member_hold(member_id: String, on: bool) -> bool:
	var m: StoryPartyMember = _state.member(member_id) if _state != null else null
	if m == null:
		return false
	m.hold = on
	save_game()
	return true


## Open ONE [EvolutionScreen] for party member [param member_id] over [param edges] and await it.
## [param scripted] evolves past the edges' triggers (a story beat -- [EvolveMemberCommand]).
## [param use_items] ({edge id: item_id}): an edge taken by USING a bag item (the menu's EVOLVE);
## that item joins the commit's context and is spent on a confirmed evolution.
## True when the member evolved. [param save] saves the journey after an evolution.
func offer_evolution(member_id: String, edges: Array, ctx: Dictionary = {}, scripted: bool = false,
		save: bool = true, use_items: Dictionary = {}) -> bool:
	var m: StoryPartyMember = _state.member(member_id) if _state != null else null
	if m == null or edges.is_empty() or not is_inside_tree():
		return false
	var parent: Node = _host if _host != null and is_instance_valid(_host) and _host is Node \
		and (_host as Node).is_inside_tree() else get_tree().root
	var state_ref: StoryState = _state
	var commit := func(edge: EvolutionResource) -> Dictionary:
		var c: Dictionary = ctx
		if use_items.has(edge.id):
			c = ctx.duplicate()
			c["used_item"] = String(use_items[edge.id])
		return StoryGrowth.evolve(state_ref, member_id, edge, c, scripted)
	# The screen names the item an edge spends (the bag's Use, or the menu's EVOLVE-by-item).
	var shown_items: Dictionary = use_items.duplicate()
	var used: String = String(ctx.get("used_item", ""))
	if not used.is_empty():
		for e in edges:
			if e is EvolutionResource and (e as EvolutionResource).use_item_ids().has(used):
				shown_items[(e as EvolutionResource).id] = used
	var screen: EvolutionScreen = EvolutionScreen.open(parent, member_id, edges, commit, m.item_id, m.nickname,
		shown_items)
	evolution_offered.emit(screen)
	# An edge that needs no confirmation (a story beat) evolves at once; the screen only shows it.
	if edges.size() == 1 and not (edges[0] as EvolutionResource).requires_confirmation:
		screen.confirm()
	var outcome: Array = await screen.finished
	var evolved: bool = not outcome.is_empty() and bool(outcome[0])
	if evolved and save:
		save_game()
	return evolved


func detach_host(host) -> void:
	if _host == host:
		_host = null


# =====================================================================================
#  Battles
# =====================================================================================

## Coroutine for StartBattle / StartDuel: begin the battle and wait for its concluded result.
func run_battle(request: BattleRequest) -> BattleResult:
	var began: Dictionary = begin_battle(request)
	if not bool(began.get("success", false)):
		var r := BattleResult.make(request.encounter_id if request != null else "", BattleResult.OUTCOME_ABORTED)
		return r
	var result = await battle_concluded
	return result


## Arm and launch [param request]. {success, reason}. [param launch] false stages everything
## but changes no scene (tests boot GameWorld themselves).
func begin_battle(request: BattleRequest, launch: bool = true) -> Dictionary:
	if _state == null:
		return {"success": false, "reason": "no_session"}
	if request == null:
		return {"success": false, "reason": "no_request"}
	if _active_request != null:
		return {"success": false, "reason": "battle_in_progress"}
	var members: Array = []
	if request.is_duel():
		members = _state.healthy_members()
	else:
		members = StoryBattleBridge.fielded_members(_state, request.squad_size)
	if members.is_empty():
		return {"success": false, "reason": "no_fieldable_members"}
	if not request.is_duel():
		if request.map_path.is_empty() or not ResourceLoader.exists(request.map_path):
			return {"success": false, "reason": "no_battle_map"}

	request.party = StoryBattleBridge.party_snapshot(members)
	# The duel's Items action draws on the story bag's battle consumables (tactical battles have no
	# item action yet).
	request.items = battle_items() if request.is_duel() else {}
	request.seed = _fresh_seed()
	request.return_to = {
		"area_id": _state.location_area(),
		"cell": Cells.to_array(_state.location_cell()),
		"facing": _state.location_facing(),
	}
	var area: OverworldAreaResource = current_area()
	request.backdrop = {
		"area_id": _state.location_area(),
		"tile_id": _tile_under_player(),
		"lighting_preset": area.lighting_preset() if area != null else "Day",
		"environment_preset": String(area.terrain.environment_preset) if area != null and area.terrain != null else "Forest",
		"weather": String(area.terrain.weather) if area != null and area.terrain != null else "clear",
	}

	# Autosave BEFORE the battle: quitting mid-battle resumes in front of the trainer.
	_pre_battle = StorySnapshot.to_dict(_state)
	save_game()

	_active_request = request
	_reported = false
	_last_result = null
	_tracking = {}

	if request.is_duel():
		var r: Dictionary = DuelLauncher.launch(request)
		if not bool(r.get("success", false)):
			_disarm_battle()
			return {"success": false, "reason": String(r.get("reason", "duel_launch_failed"))}
		return {"success": true, "reason": ""}

	_stage_tactical(request)
	if launch:
		_change_scene(GAME_WORLD_SCENE)
	return {"success": true, "reason": ""}


func _stage_tactical(request: BattleRequest) -> void:
	# Defensive (the CampaignController.begin precedent): no other mode's staged run may
	# mistake this launch for its own.
	var campaign := get_node_or_null("/root/CampaignController")
	if campaign != null and campaign.has_method("has_pending_chapter") and campaign.has_pending_chapter() \
			and campaign.has_method("cancel"):
		campaign.cancel()
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run() \
			and arena.has_method("abort_run"):
		arena.abort_run()
	var challenge := get_node_or_null("/root/ChallengeController")
	if challenge != null and challenge.has_method("has_pending_challenge") \
			and challenge.has_pending_challenge() and challenge.has_method("cancel"):
		challenge.cancel()
	if GameSettings == null:
		return
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_ai_difficulty(request.ai_difficulty)
	var map := load(request.map_path) as MapResource
	GameSettings.set_player_count(_team_count(map))
	GameSettings.set_selected_squad(request.party_character_ids())
	GameSettings.set_selected_map(request.map_path)


## The story bag's BATTLE ITEMS ({item_id: count}: consumables usable in battle) -- what a duel's
## Items action may use.
func battle_items() -> Dictionary:
	var out: Dictionary = {}
	if _state == null:
		return out
	for id in _state.bag.keys():
		var item: ItemResource = ItemLibrary.get_item(String(id))
		if item != null and item.consumable != null and item.consumable.usable_in_battle \
				and _state.item_count(String(id)) > 0:
			out[String(id)] = _state.item_count(String(id))
	return out


func _disarm_battle() -> void:
	_active_request = null
	_reported = false
	_tracking = {}


## The live story battle request (null when none).
func active_request() -> BattleRequest:
	return _active_request


func last_result() -> BattleResult:
	return _last_result


## True while a STORY TACTICAL battle is live on the board (armed AND GameSettings still points
## at its map AND this is not a replay). The GameOverScreen / ItemSystem / save-gate question.
func is_battle_active() -> bool:
	if _active_request == null or _active_request.is_duel():
		return false
	if ReplayPlayback.is_playing():
		return false
	if GameSettings == null or GameSettings.game_mode != GameSettings.GameMode.SINGLE_PLAYER:
		return false
	return String(GameSettings.selected_map_path) == _active_request.map_path


## GameOverScreen's mode-controller contract.
func is_active() -> bool:
	return is_battle_active()


## GrowthTracker.detect_mode's probe: a live story tactical battle is mode "story" (the tracker
## then leaves growth to [StoryGrowth]).
func is_capturing() -> bool:
	return is_battle_active()


func mode_id() -> String:
	return "story"


func mode_name() -> String:
	return "Story"


## GameWorldManager._setup_local_game's one hook: tag the fielded members + carried HP.
func prepare_battle_board(map_loader) -> void:
	if not is_battle_active():
		return
	_tracking = StoryBattleBridge.prepare_board(map_loader, _active_request)
	_install_guards()


## The battle's GUARDS ("Protect Linnea", the hero -- [method StoryBattleBridge.guards_for]) join
## the map's compiled rules as lose conditions, so the ordinary end check turns a guarded unit's
## fall into a defeat (and the objective banner shows them). The rules object is rebuilt per map
## load, so nothing leaks into the next battle.
func _install_guards() -> void:
	var names: Dictionary = {}
	for mid in _active_request.hero_member_ids():
		var m: StoryPartyMember = _state.member(mid) if _state != null else null
		names[mid] = m.display_name() if m != null else hero_name()
	var guards: Array[ProtectUnit] = StoryBattleBridge.guards_for(_active_request, names)
	_tracking["guards"] = guards
	if guards.is_empty() or not is_inside_tree():
		return
	var gwm := get_tree().get_first_node_in_group("game_world_manager")
	if gwm == null or not gwm.has_method("get_game_mode_rules"):
		return
	var rules = gwm.get_game_mode_rules()
	if rules is GameModeRules:
		for g in guards:
			(rules as GameModeRules).lose_conditions.append(g)


## True while a live story battle is a friendly SPAR (the objective banner's tag).
func is_spar_battle() -> bool:
	return _active_request != null and _active_request.is_spar() and (is_battle_active() or _active_request.is_duel())


## ItemSystem's story branch: the items a party unit wears in a story battle (from the story
## bag's equip, never the profile ItemInventory). null = not a story party unit (use the
## normal loadout); an empty array = a party unit with nothing equipped.
func loadout_for_unit(unit):
	if not is_battle_active() or _state == null or unit == null or not is_instance_valid(unit):
		return null
	if not unit.has_meta(StoryBattleBridge.MEMBER_META):
		return null
	var items: Array[ItemResource] = []
	var m: StoryPartyMember = _state.member(String(unit.get_meta(StoryBattleBridge.MEMBER_META)))
	if m != null and not m.item_id.is_empty():
		var item: ItemResource = ItemLibrary.get_item(m.item_id)
		if item != null:
			items.append(item)
	return items


func _on_battle_resolved(outcome, _context = {}) -> void:
	if not is_battle_active() or _reported:
		return
	var turns: int = 0
	if TurnSystemManager != null and TurnSystemManager.has_active_turn_system():
		turns = WinConditionLibrary.completed_rounds(TurnSystemManager.get_active_turn_system())
	_tracking["kos"] = _member_kos()
	_tracking["ko_elements"] = _member_ko_elements()
	var result: BattleResult = StoryBattleBridge.build_result(String(outcome), _active_request, _tracking, turns)
	# A guard that fell (the protected unit, the hero) ends the journey: read off the board as the
	# battle ended (a dead unit has already left it -- that too is "fell").
	if String(outcome) != BattleResult.OUTCOME_VICTORY:
		var units: Array = []
		var board = CombatServices.board() if CombatServices != null else null
		if board != null and board.has_method("all_units"):
			units = board.all_units()
		result.game_over_reason = StoryBattleBridge.failed_guard_reason(_tracking.get("guards", []), units)
	report_battle_result(result)
	# The end screen (revealed right after this signal) shows the Growth that Continue will
	# award -- the story party's own records, not the global ledger GrowthTracker writes.
	var awards: Dictionary = StoryGrowth.awards_for(result, EvolutionRules.current(), _growth_context())
	var feats: Dictionary = StoryGrowth.feats_for(_state, result, EvolutionRules.current(), _growth_context())
	GrowthTracker.seed_growth_this_battle(StoryGrowth.preview_rows(_state, awards, {}, feats))


## Enemy KOs per member this battle, from the battle's GrowthTracker roll call ({} without one).
func _member_kos() -> Dictionary:
	var out: Dictionary = {}
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(GrowthTracker.GROUP):
		if n is GrowthTracker:
			for row in (n as GrowthTracker).collect_rows():
				var uid: String = String(row.get("uid", ""))
				out[uid] = maxi(int(out.get(uid, 0)), int(row.get("kos", 0)))
	return out


## {member_id: {element: KOs}} this battle, from the battle's GrowthTracker (battle feats).
func _member_ko_elements() -> Dictionary:
	var out: Dictionary = {}
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(GrowthTracker.GROUP):
		if n is GrowthTracker:
			for row in (n as GrowthTracker).collect_rows():
				var uid: String = String(row.get("uid", ""))
				var by = row.get("element_kos", {})
				if uid.is_empty() or not (by is Dictionary) or (by as Dictionary).is_empty():
					continue
				out[uid] = (by as Dictionary).duplicate()
	return out


## The growth gate for story battles (StoryGrowth / GrowthTracker.gate_reason keys).
func _growth_context() -> Dictionary:
	return StoryGrowth.gate_context(ReplayPlayback.is_playing())


## THE ONE RETURN DOOR for every battle (DUEL_BATTLE.md §8.1): call EXACTLY ONCE with the
## result. A second call, or a call with no battle armed, is refused ({success: false}); the
## caller never changes scene -- this controller does.
func report_battle_result(result: BattleResult) -> Dictionary:
	if _active_request == null:
		return {"success": false, "reason": "no_battle"}
	if _reported:
		return {"success": false, "reason": "already_reported"}
	if result == null:
		return {"success": false, "reason": "no_result"}
	_reported = true
	if result.encounter_id.is_empty():
		result.encounter_id = _active_request.encounter_id
	# The tier rules read these off the result: a friendly spar, and whether the journey is over
	# (the hero / a protected unit fell, or -- Classic -- nobody would be left).
	result.spar = result.spar or _active_request.is_spar()
	result.game_over_reason = StoryPermadeath.game_over_reason(_state, _active_request, result, _ruleset)
	_last_result = result
	# A duel has no end screen of its own in story: conclude straight away (deferred, so the
	# duel's own call stack unwinds first). A tactical battle waits for the end screen action.
	if _active_request.is_duel():
		call_deferred("_conclude")
	return {"success": true, "reason": ""}


## The buttons GameOverScreen shows for a story battle ([] = the normal end screen).
func end_actions(outcome) -> Array:
	if not is_battle_active():
		return []
	if _last_result != null and _last_result.is_game_over():
		return game_over_actions()
	if String(outcome) == BattleResult.OUTCOME_VICTORY:
		return [{"id": ACTION_CONTINUE, "label": "Continue Journey"}]
	match _active_request.defeat_policy():
		BattleRequest.DEFEAT_RETRY:
			return [{"id": ACTION_RETRY, "label": "Try Again"},
				{"id": ACTION_WAYSHRINE, "label": "Return to Wayshrine"}]
		BattleRequest.DEFEAT_CONTINUE:
			return [{"id": ACTION_CONTINUE, "label": "Continue"}]
	return [{"id": ACTION_WAYSHRINE, "label": "Return to Wayshrine"}]


func on_end_action(action_id) -> void:
	if get_tree() != null:
		get_tree().paused = false
	match String(action_id):
		ACTION_RETRY:
			_retry()
		ACTION_WAYSHRINE:
			_conclude(true)
		ACTION_LOAD_SAVE:
			load_last_save()
		ACTION_TITLE:
			abandon_to_title()
		_:
			_conclude()


## The two choices a GAME OVER offers (the tactical end screen and [StoryGameOverScreen]).
func game_over_actions() -> Array:
	return [{"id": ACTION_LOAD_SAVE, "label": "Load Last Save"},
		{"id": ACTION_TITLE, "label": "Return to Title"}]


## GameOverScreen's optional retitle: a game over reads "GAME OVER" with why; {} otherwise.
func end_banner(_outcome) -> Dictionary:
	if _last_result == null or not _last_result.is_game_over():
		return {}
	return {"title": "GAME OVER", "subtitle": game_over_text(_last_result)}


## The line saying why [param result] ended the journey.
func game_over_text(result: BattleResult) -> String:
	return StoryPermadeath.game_over_text(result.game_over_reason if result != null else "", hero_name())


## GAME OVER -> "Load Last Save": the journey as the slot last saved it (the pre-battle autosave,
## written as every battle began); a slot-less journey rewinds to its in-memory pre-battle copy.
## Nothing of the lost battle is applied. {success, reason}.
func load_last_save() -> Dictionary:
	var slot: int = _slot
	var pre: Dictionary = _pre_battle.duplicate(true)
	_stop_running_script("game_over")
	_close_game_over_screen()
	_disarm_battle()
	var loaded: bool = false
	if slot > 0 and StorySaveManager.has_save(slot):
		loaded = bool(continue_journey(slot).get("success", false))
	if not loaded and not pre.is_empty():
		var restored: Dictionary = StorySnapshot.from_dict(pre)
		if bool(restored.get("success", false)):
			_begin_session(restored["state"], slot)
			loaded = true
	if not loaded:
		return {"success": false, "reason": "no_save"}
	_pending_message = "The journey resumes from your last save."
	enter_overworld()
	return {"success": true, "reason": ""}


## GAME OVER -> "Return to Title": leave WITHOUT saving the lost battle (the slot keeps its last
## save, the pre-battle autosave).
func abandon_to_title() -> void:
	_stop_running_script("game_over")
	_close_game_over_screen()
	_disarm_battle()
	_state = null
	_slot = 0
	_host = null
	_runner = StoryScriptRunner.new()
	session_changed.emit()
	_change_scene(MAIN_MENU_SCENE)


## Stop the script waiting on this battle and let its coroutine unwind (a StartBattle awaits
## battle_concluded): the context is stopped first, so nothing after the battle runs.
func _stop_running_script(reason: String) -> void:
	var ctx: ScriptContext = _runner.context()
	if ctx != null and _runner.is_running():
		ctx.stop(reason)
		battle_concluded.emit(_last_result)


## Show the grove GAME OVER card (a duel ended the journey: the duel has no end screen of its
## own in story).
func _show_game_over(result: BattleResult) -> void:
	game_over.emit(result)
	if not is_inside_tree():
		return
	_close_game_over_screen()
	var screen := StoryGameOverScreen.open(get_tree().root, game_over_text(result))
	screen.action_chosen.connect(on_end_action)


func _close_game_over_screen() -> void:
	if not is_inside_tree():
		return
	var old := get_tree().root.get_node_or_null(StoryGameOverScreen.NODE_NAME)
	if old != null:
		old.get_parent().remove_child(old)
		old.queue_free()


## The GAME OVER card on screen (null when none).
func game_over_screen() -> StoryGameOverScreen:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(StoryGameOverScreen.NODE_NAME) as StoryGameOverScreen


## Apply the reported result and walk back into the overworld.
func _conclude(force_whiteout: bool = false) -> void:
	var request: BattleRequest = _active_request
	var result: BattleResult = _last_result
	if request == null or result == null or _state == null:
		return
	# A battle that ENDED THE JOURNEY is never applied: the GAME OVER card offers the last save.
	if result.is_game_over():
		_show_game_over(result)
		return
	var applied: Dictionary = StoryResultApplier.apply(_state, request, result, _ruleset, _growth_context())
	var whiteout: bool = bool(applied.get("whiteout", false))
	if force_whiteout and not whiteout and result.is_defeat():
		_state.heal_party(_ruleset == null or _ruleset.whiteout_revives)
		whiteout = true
	if result.is_victory() and not request.campaign_chapter.is_empty():
		var campaign := get_node_or_null("/root/CampaignController")
		if campaign != null and campaign.has_method("mark_cleared"):
			campaign.mark_cleared(request.campaign_chapter, result.turns)
	if whiteout:
		_apply_whiteout_location()
		_pending_message = "You retreat to the %s Wayshrine, and your party is healed." \
			% area_display_name(String(_state.respawn.get("area_id", "")))
		var ctx: ScriptContext = _runner.context()
		if ctx != null and _runner.is_running():
			ctx.stop("whiteout")
	else:
		var ret: Dictionary = request.return_to
		var cell: Vector3i = Cells.from_variant(ret.get("cell", null))
		if cell != Cells.INVALID and String(ret.get("area_id", "")) == _state.location_area():
			_state.set_location(_state.location_area(), cell, String(ret.get("facing", "south")))
	# CLASSIC: say who fell (they are in Journey -> Party -> Fallen from now on).
	var fell: Array = applied.get("fallen", [])
	if not fell.is_empty():
		var names: Array[String] = []
		for mid in fell:
			var f: StoryPartyMember = _state.fallen_member(String(mid))
			names.append(f.display_name() if f != null else String(mid))
		var line: String = "%s fell in battle, and will not return." % " and ".join(names)
		_pending_message = line if _pending_message.is_empty() else "%s %s" % [line, _pending_message]
	_disarm_battle()
	_last_result = result
	_resume_result = result
	# Evolution is offered once the overworld is back -- never after a whiteout (you wake at the
	# Wayshrine; the offer stays open for the next battle).
	_offer_after_battle = not whiteout
	save_game()
	_resume_pending = true
	_change_scene(OVERWORLD_SCENE)


func _apply_whiteout_location() -> void:
	var area_id: String = String(_state.respawn.get("area_id", ""))
	var entry_id: String = String(_state.respawn.get("entry", ""))
	var area: OverworldAreaResource = load_area(area_id)
	if area == null:
		return
	var e: Dictionary = area.entry(entry_id)
	if e.is_empty():
		return
	if area_id != _state.location_area():
		_state.on_area_changed()
	_state.set_location(area_id, e["cell"], String(e["facing"]))


## Try Again: the journey exactly as before the battle, a fresh battle seed, the same fight.
func _retry() -> void:
	var request: BattleRequest = _active_request
	if request == null or _pre_battle.is_empty():
		_conclude(true)
		return
	var restored: Dictionary = StorySnapshot.from_dict(_pre_battle)
	if bool(restored.get("success", false)):
		var s: StoryState = restored["state"]
		s.transient_positions = _state.transient_positions.duplicate(true)
		s.play_seconds = _state.play_seconds
		_state = s
		var ctx: ScriptContext = _runner.context()
		if ctx != null:
			ctx.state = s
		s.drain_changes()
	request.seed = _fresh_seed()
	_reported = false
	_last_result = null
	_tracking = {}
	_stage_tactical(request)
	_change_scene(GAME_WORLD_SCENE)


# =====================================================================================
#  Helpers
# =====================================================================================

func _tile_under_player() -> String:
	if _host != null and is_instance_valid(_host) and _host.has_method("tile_under_player"):
		return String(_host.tile_under_player())
	return ""


## FRESH ENTROPY for a battle / a journey seed. A local generator -- never the process RNG
## (randomize() would reseed every other system; tests/README rule 3).
static func _fresh_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi() & 0x7FFFFFFF)


static func _team_count(map: MapResource) -> int:
	var max_pid: int = 1
	if map != null:
		for spawn in map.unit_spawns:
			if spawn is Dictionary:
				max_pid = maxi(max_pid, int(spawn.get("player_id", 0)))
	return clampi(max_pid + 1, 2, 4)


func _change_scene(path: String) -> void:
	if not scene_changes_enabled:
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	var fade := tree.root.get_node_or_null(^"SceneFade")
	if fade != null and fade.has_method(&"change_scene"):
		fade.call(&"change_scene", path)
	else:
		tree.change_scene_to_file(path)
