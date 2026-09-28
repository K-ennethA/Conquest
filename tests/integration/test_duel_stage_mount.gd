extends GutTest

## DuelStage mounts (docs/design/DUEL_BATTLE.md §10): the stage builds its world, installs
## the duel, mounts floating combat text / MoveFX / the cut-in / the HUD with zero engine
## errors, the HUD move grid shows the four compiled moves, a pick goes through the engine as
## a command and the grid then shows the right cooldown -- and an AI-vs-AI duel reaches the
## results card.

const STAGE := preload("res://game/duel/DuelStage.tscn")


func before_each() -> void:
	DuelController.reset()
	DuelController.record_profile = false
	CombatServices.clear()


func after_each() -> void:
	DuelController.reset()
	DuelController.record_profile = true
	CombatServices.clear()
	CombatServices.match_rng = null


func _stage(both_ai: bool = false) -> DuelStage:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight")
	req.seed = 2024
	req.player_is_ai = both_ai
	DuelController.start(req, false)
	var stage: DuelStage = STAGE.instantiate()
	stage.instant = true
	add_child_autofree(stage)
	return stage


func _find(root: Node, type_name: String) -> Node:
	for c in root.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == type_name:
			return c
	return null


func test_stage_mounts_every_layer() -> void:
	var stage := _stage()
	await wait_process_frames(3)
	assert_not_null(stage.battle, "the engine is set up")
	assert_eq(CombatServices.board(), stage.battle.board, "the duel board is live")
	assert_not_null(_find(stage, "FloatingCombatText"), "floating combat text")
	assert_not_null(_find(stage, "MoveFXDispatcher"), "move FX")
	assert_not_null(_find(stage, "UltimateCutIn"), "the ultimate cut-in")
	assert_not_null(_find(stage, "DuelHUD"), "the HUD")
	assert_not_null(stage.get_node_or_null("WorldLook"), "the look")
	assert_true(stage.camera.current, "the duel camera is live")
	assert_false(GameEvents.ultimate_casting.is_connected(stage._cutin._on_ultimate_casting),
		"the stage drives the cut-in itself (no double flash)")
	for side in 2:
		var u = stage.battle.unit_of(side)
		for c in u.get_children():
			if c is HealthBar:
				assert_false(c.visible, "no floating 3D HP bar: the HUD cards replace it")


func test_move_grid_shows_the_compiled_moves_and_their_cooldowns() -> void:
	var stage := _stage()
	await wait_process_frames(3)
	var vw = stage.battle.unit_of(0)
	assert_eq(stage.battle.current_actor(), vw, "the player's turn is open")
	var rows := stage.hud.rows
	assert_eq(rows.size(), 4)
	for i in 4:
		assert_true(rows[i].visible, "row %d is shown" % i)
		assert_eq(rows[i].move(), vw.get_move(i))
		assert_false(rows[i].disabled, "row %d is ready at the start" % i)
		assert_eq(rows[i]._cooldown.text, "", "no cooldown badge while ready")
	assert_string_contains(rows[0]._forecast.text, "%", "a live forecast chip")
	# Pick Splinter Volley (cooldown 2) through the HUD; the AI answers; back to us.
	stage.hud._choose(2)
	await wait_process_frames(6)
	assert_eq(stage.battle.current_actor(), vw, "the player's next turn")
	assert_true(rows[2].disabled, "Splinter Volley is recharging")
	assert_eq(rows[2]._cooldown.text, "CD 1/2", "and says so")
	assert_eq(stage.battle.result.commands.size(), 2, "one command each, through the applier")


func test_ai_vs_ai_reaches_the_results_card() -> void:
	var stage := _stage(true)
	var guard := 0
	while not stage.battle.is_over and guard < 300:
		await wait_process_frames(1)
		guard += 1
	assert_true(stage.battle.is_over, "the duel ends")
	await wait_process_frames(4)
	assert_true(stage.hud.results_visible(), "the results card is up")
	assert_not_null(DuelController.last_result(), "the controller got the result")
