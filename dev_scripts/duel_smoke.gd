extends SceneTree

## Headless DUEL smoke run: AI vs AI to completion, printing every action and the winner.
##   godot --headless --path . --script dev_scripts/duel_smoke.gd -- [player_id] [foe_id] [seed] [difficulty]
## Defaults: vineweave vs gem_knight (Geode), seed 1234, NORMAL (1). Seed 0 = fresh entropy.
##
## Everything is loaded by path after the first frame so the autoloads are registered
## before the gameplay scripts compile (see check_uid_warnings.gd).


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var player_id := String(args[0]) if args.size() > 0 else "vineweave"
	var foe_id := String(args[1]) if args.size() > 1 else "gem_knight"
	var seed_value := int(args[2]) if args.size() > 2 else 1234
	var difficulty := int(args[3]) if args.size() > 3 else 1

	var request_script: GDScript = load("res://game/duel/DuelRequest.gd")
	var request = request_script.standalone(StringName(player_id), StringName(foe_id), difficulty)
	request.seed = seed_value
	request.player_is_ai = true
	request.player_ai_difficulty = difficulty

	var battle: Node = load("res://game/duel/DuelBattle.gd").new()
	root.add_child(battle)
	var ok: Dictionary = battle.setup(request)
	if not bool(ok["success"]):
		print("DUEL_SETUP_FAILED %s" % ok["reason"])
		quit(1)
		return
	battle.action_resolved.connect(func(rec: Dictionary) -> void:
		var move = rec.get("move")
		var who: String = rec["actor"].get_display_name() if rec.get("actor") != null and is_instance_valid(rec["actor"]) else "?"
		var what: String = move.display_name if move != null else "passes"
		var events: Array = rec["result"].get("events", [])
		var dealt := 0
		for e in events:
			if e is Dictionary and String(e.get("effect", "")) == "damage":
				dealt += int(e.get("amount", 0))
		print("  #%d r%d %s -> %s (dealt %d)  HP %s" % [int(rec["cmd"]["seq"]), battle.round_number(),
			who, what, dealt, str(rec["hp"])]))
	print("DUEL %s vs %s  seed=%d" % [player_id, foe_id, int(battle.result.seed)])
	var res = battle.run_to_end()
	if res == null:
		print("DUEL_DID_NOT_FINISH")
		quit(1)
		return
	print("DUEL_RESULT outcome=%s winner_side=%d rounds=%d turns=%d" % [res.outcome, res.winner_side, res.rounds, res.turns])
	battle.teardown()
	root.remove_child(battle)
	battle.free()
	quit(0)
