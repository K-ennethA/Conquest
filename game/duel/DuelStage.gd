extends Node3D
class_name DuelStage

## The duel's scene (docs/design/DUEL_BATTLE.md §6.1): a small 3D stage, the two combatants
## on their stations face to face, a fixed camera, the shared presentation layers
## (MoveFX + impact sparks, floating combat text, the ultimate cut-in, weather, WorldLook)
## and the [DuelHUD]. It wraps a headless [DuelBattle] and DIRECTS it: whose turn, ask the
## HUD or the brain for a slot, play the cut-in, apply the command, wait for the
## animations, narrate, repeat -- until the result card.
##
## Presentation only: nothing here reads a gameplay RNG or writes combat state -- every
## action is a command the battle applies -- so replays and network play are unaffected.
##
## Opened with no staged request (the editor's "run scene", a screenshot pass) it stages a
## default Vineweave vs Geode duel so the scene always shows something real.

## Seconds of the pacing beats at 1x speed (scaled by GameSettings battle speed /
## fast-forward; 0 with animations off).
const BEAT_INTRO := 1.6
const BEAT_THINK := 0.6
const BEAT_AFTER := 0.55
const BEAT_PASS := 0.9
## The team preview before a party duel's intro line.
const BEAT_PREVIEW := 1.8
const SETTLE_TIMEOUT := 6.0
## Model scale on the stage (presentation only; the board reads positions, never scale).
const UNIT_SCALE := 1.35

## Hot-seat versus: what the two sides are called (HUD prompts, the results' winner).
const HOTSEAT_NAMES: Array[String] = ["Player 1", "Player 2"]

## Skip every wait (tests / headless auto-play).
@export var instant: bool = false

var battle: DuelBattle = null
var hud: DuelHUD = null
var camera: DuelCamera = null
var request: DuelRequest = null
var _cutin: UltimateCutIn = null
var _map: Node3D = null
var _driving: bool = false
var _pause: PauseMenu = null


func _ready() -> void:
	request = _staged_request()
	_build_world()
	_map = Node3D.new()
	_map.name = "Map"
	add_child(_map)
	battle = DuelBattle.new()
	battle.name = "DuelBattle"
	add_child(battle)
	# The live scene makes the duel's turn system the ACTIVE one (HUD widgets follow it);
	# a stage mounted under something else (a test) stays self-contained.
	var ok := battle.setup(request, _map, get_tree().current_scene == self)
	if not bool(ok["success"]):
		# A request the controller already validated cannot fail here; stay inert if one does.
		print_verbose("DuelStage: setup refused (%s)" % String(ok["reason"]))
		return
	_mount_presentation()
	_present_units()
	camera.frame(battle.board.station_world(0), battle.board.station_world(1))
	if is_hotseat():
		hud.side_names = HOTSEAT_NAMES
	_configure_hud()
	hud.bind(battle)
	hud.rematch_requested.connect(_on_rematch)
	battle.combatant_entered.connect(_on_combatant_entered)
	hud.setup_requested.connect(_on_setup)
	hud.menu_requested.connect(_on_menu)
	battle.finished.connect(_on_finished)
	_run.call_deferred()


func _exit_tree() -> void:
	if battle != null and is_instance_valid(battle):
		battle.teardown()


## "Vineweave and Gem Knight square off!" -- the intro of a VERSUS duel (hot-seat / online).
static func versus_intro(p_battle: DuelBattle) -> String:
	var names: Array[String] = []
	for side in 2:
		var u = p_battle.unit_of(side) if p_battle != null else null
		names.append(u.get_display_name() if u != null else "Player %d" % (side + 1))
	return "%s and %s square off!" % names


## Subclass hook, run just before the HUD binds the battle (the online stage sets its seat's
## perspective here). Nothing by default.
func _configure_hud() -> void:
	pass


## HOT-SEAT VERSUS (Online > Versus > Duel > Same device): a versus duel with a human on each
## side, sharing this screen. The HUD prompts name whose turn it is and the results name the
## winner (DuelSetup builds these requests).
func is_hotseat() -> bool:
	return request != null and request.kind == DuelRequest.KIND_VERSUS \
		and not request.player_is_ai and not request.foe_is_ai


## The request the controller staged, or a default standalone duel.
func _staged_request() -> DuelRequest:
	var ctrl := get_node_or_null("/root/DuelController")
	if ctrl != null and ctrl.has_method("active_request") and ctrl.active_request() != null:
		return ctrl.active_request()
	return DuelRequest.standalone(&"vineweave", &"gem_knight")


# --- World ---------------------------------------------------------------------------

func _build_world() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	we.environment.sky = sky
	we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(we)
	var look := WorldLook.new()
	look.name = "WorldLook"
	add_child(look)
	look.setup(self)
	look.apply_preset("Day")

	var stage_set := Node3D.new()
	stage_set.name = "StageSet"
	add_child(stage_set)
	var gap := DuelRuleset.load_default().station_gap
	var centre := Vector3(1.0 + float(gap), 0.0, 1.0)
	# The clearing: one painterly ground disc (the tactical grass shader, world-space seamless).
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var disc := CylinderMesh.new()
	disc.top_radius = 22.0
	disc.bottom_radius = 22.5
	disc.height = 0.4
	disc.radial_segments = 48
	ground.mesh = disc
	ground.position = centre + Vector3(0, -0.2, -2.0)
	var mat_path := "res://tile_objects/tiles/materials/stylized_grass_material.tres"
	if request.resolved_station_tile_id() == &"forest_dirt":
		mat_path = "res://tile_objects/tiles/materials/stylized_dirt_material.tres"
	if ResourceLoader.exists(mat_path):
		ground.material_override = load(mat_path)
	stage_set.add_child(ground)
	# A ring of trees framing the clearing (behind and to the sides, never between the
	# camera and the stations).
	var ring := [
		Vector3(-5, 0, -5), Vector3(-1, 0, -8), Vector3(4, 0, -9), Vector3(8, 0, -9.5),
		Vector3(12, 0, -8), Vector3(16, 0, -6), Vector3(19, 0, -2), Vector3(20, 0, 3),
		Vector3(-8, 0, -1), Vector3(14, 0, -11), Vector3(0, 0, -12), Vector3(9, 0, -13),
	]
	for i in ring.size():
		var tree := TreeBuilder.new()
		tree.name = "Tree%d" % i
		tree.position = ring[i] + Vector3(0, 0, -1)
		tree.scale = Vector3.ONE * (1.6 + 0.25 * float(i % 3))
		stage_set.add_child(tree)
	if request.resolved_station_tile_id() == &"tall_grass":
		for station_x in [1.0, 1.0 + float(gap)]:
			var tuft := MeshInstance3D.new()
			tuft.name = "Tuft"
			var q := CylinderMesh.new()
			q.top_radius = 1.2
			q.bottom_radius = 1.3
			q.height = 0.06
			tuft.mesh = q
			tuft.position = Vector3(station_x, 0.03, 1.0)
			if ResourceLoader.exists("res://tile_objects/tiles/materials/stylized_foliage_material.tres"):
				tuft.material_override = load("res://tile_objects/tiles/materials/stylized_foliage_material.tres")
			stage_set.add_child(tuft)

	camera = DuelCamera.new()
	camera.name = "DuelCamera"
	add_child(camera)
	if DisplayServer.get_name() != "headless":
		var fx := WeatherFX.new()
		fx.name = "WeatherFX"
		add_child(fx)


func _mount_presentation() -> void:
	add_child(load("res://game/visuals/ImpactFX.gd").new())
	add_child(load("res://game/visuals/MoveFXDispatcher.gd").new())
	add_child(FloatingCombatText.new())
	_cutin = UltimateCutIn.new()
	_cutin.name = "UltimateCutIn"
	add_child(_cutin)
	# The stage plays the cut-in itself, BEFORE the command resolves (the applier still
	# announces ultimate_casting for replays / other listeners): unhook the auto-play so it
	# never flashes twice.
	if GameEvents.ultimate_casting.is_connected(_cutin._on_ultimate_casting):
		GameEvents.ultimate_casting.disconnect(_cutin._on_ultimate_casting)
	hud = DuelHUD.new()
	add_child(hud)
	_pause = PauseMenu.new()
	add_child(_pause)


## Face to face, idle bob on, and no floating 3D HP bars (the HUD cards replace them). Every
## team member is dressed now (scale, no bar); a benched one is introduced when it comes in.
func _present_units() -> void:
	for side in 2:
		for rec in battle.team(side):
			var u = rec["unit"]
			if u == null or not is_instance_valid(u):
				continue
			_dress_unit(u)
			if u == battle.unit_of(side):
				GameEvents.unit_spawned.emit(u, false)


func _dress_unit(u) -> void:
	var vm := get_node_or_null("UnitVisualManager")
	if vm != null and vm.has_method("cleanup_unit_visuals"):
		vm.cleanup_unit_visuals(u)
	for c in u.get_children():
		if c is HealthBar:
			c.visible = false
	# The stage scales the model (a duel reads at a closer, JRPG distance).
	u.scale = Vector3.ONE * UNIT_SCALE


## A team member took the station (a switch or a KO replacement): idle bob on, bar off.
func _on_combatant_entered(_side: int, unit, _previous) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_dress_unit(unit)
	GameEvents.unit_spawned.emit(unit, false)


## What the HUD calls side [param side] ("Player 2" on a shared screen, "You" / "The foe").
func side_name(side: int) -> String:
	if is_hotseat():
		return HOTSEAT_NAMES[clampi(side, 0, 1)]
	var me: int = hud.perspective_side if hud != null else 0
	return "You" if side == me else "The foe"


## "Go, Petalfang!" / "The foe sends out Petalfang!" / "Vineweave, come back! Go, Geode!" --
## the narration of an applied SWITCH record ([member DuelBattle] record's switch event).
func switch_line(rec: Dictionary) -> String:
	var ev: Dictionary = rec.get("switch", {})
	if ev.is_empty():
		return ""
	var side: int = int(ev.get("side", 0))
	var incoming = ev.get("unit")
	var in_name: String = incoming.get_display_name() if incoming != null and is_instance_valid(incoming) else "a partner"
	var outgoing = ev.get("from")
	var out_name: String = outgoing.get_display_name() if outgoing != null and is_instance_valid(outgoing) else ""
	var mine: bool = side == hud.perspective_side or is_hotseat()
	var who := side_name(side)
	if bool(ev.get("replacement", false)) or out_name == "":
		if is_hotseat():
			return "%s sends out %s!" % [who, in_name]
		return "Go, %s!" % in_name if mine else "%s sends out %s!" % [who, in_name]
	if is_hotseat():
		return "%s withdraws %s and sends out %s!" % [who, out_name, in_name]
	return "%s, come back! Go, %s!" % [out_name, in_name] if mine \
		else "%s withdraws %s and sends out %s!" % [who, out_name, in_name]


# --- The director ------------------------------------------------------------------------

func _run() -> void:
	if _driving:
		return
	_driving = true
	var foe = battle.unit_of(1)
	var foe_name: String = foe.get_display_name() if foe != null else "The foe"
	var intro: String = "A wild %s blocks the path!" if request.is_wild() else "%s challenges you!"
	if request.is_spar():
		intro = "Friendly spar: %s squares up!"
	hud.show_intro(intro % foe_name)
	if request.kind == DuelRequest.KIND_VERSUS:
		hud.show_intro(versus_intro(battle))
	hud.set_command_panel_visible(false)
	if _party_duel():
		hud.show_team_preview([side_name(0), side_name(1)] if is_hotseat() else [])
		await _beat(BEAT_PREVIEW)
		hud.hide_team_preview()
	await _beat(BEAT_INTRO)
	hud.show_intro("")
	hud.set_command_panel_visible(true)
	battle.start()
	while is_inside_tree() and not battle.is_over:
		var pending := battle.pending_replacements()
		if not pending.is_empty():
			await _replace(pending[0])
			continue
		var actor = battle.current_actor()
		if actor == null:
			break
		hud.refresh()
		if battle.must_pass(actor):
			hud.show_waiting("")
			hud.narrate("%s can't move!" % actor.get_display_name())
			await _beat(BEAT_PASS)
			battle.pass_turn()
			continue
		var slot: int
		var decision: Dictionary = {}
		if battle.is_ai_unit(actor):
			hud.show_waiting("%s is thinking…" % actor.get_display_name())
			await _beat(BEAT_THINK)
			decision = battle.decide_for(actor)
			hud.show_waiting("")
			slot = int(decision["slot"])
		else:
			var prompt := "What will %s do?" % actor.get_display_name()
			if is_hotseat():
				prompt = "%s: %s" % [HOTSEAT_NAMES[clampi(battle.side_of(actor), 0, 1)], prompt]
			hud.narrate(prompt)
			hud.show_commands(actor)
			slot = await hud.slot_chosen
			hud.show_waiting("")
		if not is_inside_tree() or battle.is_over:
			break
		if slot == DuelHUD.FLEE_SLOT:
			await _flee(actor)
			continue
		if slot == DuelHUD.ITEM_SLOT:
			await _use_item(actor, hud.chosen_item_id)
			continue
		if slot == DuelHUD.SWITCH_SLOT:
			await _switch(actor, hud.chosen_member)
			continue
		if decision.has("switch"):
			await _switch(actor, int(decision["switch"]))
			continue
		await _cast(actor, slot, decision)
	_driving = false


## True when either side brings a bench (the team preview, the party strips).
func _party_duel() -> bool:
	return battle != null and (battle.team_size(0) > 1 or battle.team_size(1) > 1)


## A voluntary switch (the Party action / the brain's): the recorded SWITCH, then narration.
func _switch(actor, index: int) -> void:
	var rec: Dictionary = battle.submit_switch(index)
	if not bool(rec.get("ok", false)):
		hud.narrate(NetProtocol.describe_intent_rejection(String(rec.get("reason", "")), NetProtocol.switch_to("")))
		await _beat(BEAT_AFTER)
		return
	hud.narrate(switch_line(rec))
	hud.refresh()
	await _settle()


## A KO REPLACEMENT for [param side]: the brain picks for an AI side, the owner's picker for a
## human one (on a shared screen the prompt names the player).
func _replace(side: int) -> void:
	var rec: Dictionary
	if battle.is_ai_side(side):
		hud.show_waiting("%s is choosing…" % side_name(side))
		await _beat(BEAT_THINK)
		rec = battle.play_ai_replacement(side)
	else:
		hud.narrate("%s: choose who fights next." % side_name(side) if is_hotseat() else "Choose who fights next.")
		hud.show_replacement(side, side_name(side) if is_hotseat() else "")
		var index: int = await hud.replacement_chosen
		if not is_inside_tree() or battle.is_over:
			return
		rec = battle.choose_replacement(side, index)
	hud.show_waiting("")
	if bool(rec.get("ok", false)):
		hud.narrate(switch_line(rec))
		hud.refresh()
		await _beat(BEAT_AFTER)


## The player tries to run (DuelBattle.attempt_flee): away (the duel ends as FLED) or the turn
## is spent.
func _flee(actor) -> void:
	var res: Dictionary = battle.attempt_flee()
	if not bool(res.get("ok", false)):
		return
	if bool(res.get("fled", false)):
		hud.narrate("Got away safely!")
	else:
		hud.narrate("%s couldn't get away!" % actor.get_display_name())
		hud.refresh()
		await _beat(BEAT_AFTER)


## The player uses a battle item (DuelBattle.use_item: the recorded USE_ITEM command, which spends
## the turn), then the result is narrated. A refused use spends nothing and the turn stays open.
func _use_item(actor, item_id: String) -> void:
	var item: ItemResource = ItemLibrary.get_item(item_id)
	var item_name: String = item.display_name if item != null else item_id
	var who: String = actor.get_display_name()
	var rec: Dictionary = battle.use_item(item_id)
	if not bool(rec.get("ok", false)):
		hud.narrate(ConsumableEffect.reason_text(String(rec.get("reason", "")), who))
		await _beat(BEAT_AFTER)
		return
	hud.narrate("You used a %s on %s!" % [item_name, who])
	hud.refresh()
	await _settle()
	var line := _item_line(rec, who)
	if line != "":
		hud.narrate(line)
		await _beat(BEAT_AFTER)


## "Barkling recovered 25 HP." / "Barkling was cured of Poisoned." -- read off the USE_ITEM event.
static func _item_line(rec: Dictionary, who: String) -> String:
	var res: Dictionary = rec.get("result", {})
	for e in res.get("events", []):
		if not (e is Dictionary) or String(e.get("effect", "")) != "use_item":
			continue
		var bits: Array[String] = []
		var cured: Array = e.get("cured", [])
		if not cured.is_empty():
			var names: Array[String] = []
			for id in cured:
				names.append(ConsumableEffect.status_label(StringName(String(id))))
			bits.append("%s was cured of %s." % [who, ", ".join(names)])
		if int(e.get("healed", 0)) > 0:
			bits.append("%s recovered %d HP." % [who, int(e.get("healed", 0))])
		return " ".join(bits)
	return ""


## Play one action: cut-in for an ultimate, the command, then wait for the show to settle.
func _cast(actor, slot: int, decision: Dictionary) -> void:
	var move: MoveResource = actor.get_move(slot) if slot >= 0 else null
	if move == null:
		hud.narrate("%s waits." % actor.get_display_name())
		battle.pass_turn()
		await _beat(BEAT_AFTER)
		return
	var foe = battle.foe_of(actor)
	var forecast: Dictionary = MoveExecutor.preview_vs(move, actor, foe, battle.board) if foe != null else {}
	hud.narrate("%s used %s!" % [actor.get_display_name(), move.display_name_for(actor)])
	if MoveResource.is_ultimate_move(move, slot) and not instant and _cutin != null:
		_cutin.play(actor, move)
		await _cutin.finished
	if camera != null:
		camera.punch(0.0 if instant else 0.35 * _scale())
	var rec: Dictionary
	if decision.is_empty():
		rec = battle.submit_slot(slot)
	else:
		rec = battle.apply_decision(actor, decision)
	hud.refresh()
	await _settle()
	var line := _outcome_line(rec, forecast)
	if line != "":
		hud.narrate(line)
		await _beat(BEAT_AFTER)


## "It's strong!", "A critical hit!", "It missed!" -- read off the resolved events.
func _outcome_line(rec: Dictionary, forecast: Dictionary) -> String:
	var res: Dictionary = rec.get("result", {})
	var missed := false
	var crit := false
	var landed := false
	for e in res.get("events", []):
		if not (e is Dictionary) or String(e.get("effect", "")) != "damage":
			continue
		if bool(e.get("missed", false)):
			missed = true
		elif int(e.get("amount", 0)) > 0 or bool(e.get("negated", false)):
			landed = true
		if bool(e.get("crit", false)):
			crit = true
	if missed and not landed:
		return "It missed!"
	var bits: Array[String] = []
	if crit:
		bits.append("A critical hit!")
	if landed:
		var word := ElementVisuals.effectiveness_word(forecast.get("element_label", &""))
		if word == "Strong":
			bits.append("It's strong!")
		elif word == "Resisted":
			bits.append("It's resisted...")
	return " ".join(bits)


## Wait until every unit animation has finished (bounded), plus a beat.
func _settle() -> void:
	if instant:
		return
	var waited := 0.0
	while is_inside_tree() and UnitAnimator.is_any_animation_playing() and waited < SETTLE_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await _beat(BEAT_AFTER)


func _beat(seconds: float) -> void:
	if instant or not is_inside_tree():
		return
	var t := seconds * _scale()
	if t <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(t).timeout


func _scale() -> float:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("anim_duration_scale"):
		return float(gs.anim_duration_scale())
	return 1.0


func _process(_delta: float) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and "fast_forward_active" in gs:
		gs.fast_forward_active = Input.is_action_pressed(InputActions.FAST_FORWARD)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.MAP_MENU) and _pause != null and not hud.results_visible():
		get_viewport().set_input_as_handled()
		_pause.toggle()


# --- End -------------------------------------------------------------------------------

## STANDALONE: the controller finishes at once (profile stat, growth) and the card offers
## Rematch / Change Units / Menu. STORY: the card shows first and its Continue finishes -- the
## report makes StoryController walk back to the overworld, so it must wait for the player.
func _on_finished(result: DuelResult) -> void:
	if camera != null:
		camera.impulse_shake(0.5)
	var standalone := request.origin == DuelRequest.ORIGIN_STANDALONE
	if standalone:
		_finish_with_controller(result)
	else:
		hud.continue_requested.connect(_finish_with_controller.bind(result), CONNECT_ONE_SHOT)
	_show_results.call_deferred(result, standalone)


func _finish_with_controller(result: DuelResult) -> void:
	var ctrl := get_node_or_null("/root/DuelController")
	if ctrl != null and ctrl.has_method("finish"):
		ctrl.finish(result)


func _show_results(result: DuelResult, standalone: bool) -> void:
	await _beat(BEAT_AFTER * 2.0)
	if not is_inside_tree():
		return
	hud.show_results(result, standalone)
	if standalone:
		await _offer_standalone_evolutions(result)


## Standalone (DUEL_BATTLE.md §8.4): a member the duel's growth made ready is offered the
## Evolution screen from the results card (story evolutions are the overworld's, never here) --
## unless the member is on HOLD (DECISIONS.md #27: no automatic prompts; Character Select's
## EVOLVE still works).
func _offer_standalone_evolutions(result: DuelResult) -> void:
	for row in result.growth:
		if not (row is Dictionary) or not bool(row.get("ready", false)):
			continue
		var uid: String = String(row.get("uid", ""))
		if RosterLedger.is_held(uid):
			continue
		var edges: Array[EvolutionResource] = RosterLedger.available_evolutions(uid)
		if edges.is_empty() or not is_inside_tree():
			continue
		var screen := EvolutionScreen.open(self, uid, edges)
		await screen.finished


func _on_rematch() -> void:
	var ctrl := get_node_or_null("/root/DuelController")
	if ctrl != null and ctrl.active_request() != null:
		ctrl.rematch()
	else:
		get_tree().reload_current_scene()


func _on_setup() -> void:
	var ctrl := get_node_or_null("/root/DuelController")
	if ctrl != null:
		ctrl.open_setup()


func _on_menu() -> void:
	var ctrl := get_node_or_null("/root/DuelController")
	if ctrl != null:
		ctrl.open_menu()
