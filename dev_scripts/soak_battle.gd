extends SceneTree

## HEADLESS SOAK HARNESS -- plays a whole battle by itself so every engine error,
## push_error and push_warning raised DURING PLAY lands on stderr where CI can grep it.
##
## A clean headless BOOT proves nothing: the errors the editor debugger reports during a
## real match come from INTERACTION -- moves, AI turns, animations, unit deaths, overlays
## reacting to freed units, scene teardown. This harness reproduces that interaction with
## no renderer and no human: it configures a SINGLE_PLAYER match, loads GameWorld.tscn,
## then flips PLAYER 0 to [member Player.is_ai] so [BotTurnDriver] -- which is already
## mounted for single-player and re-reads is_ai on every beat -- drives BOTH sides. The
## battle plays itself to victory/defeat or a round cap.
##
## USAGE
##   godot --headless -s dev_scripts/soak_battle.gd
##   godot --headless -s dev_scripts/soak_battle.gd -- --map=forgotten_forest --turns=40 --ts=speed
##
## ARGS (everything after `--`, parsed from OS.get_cmdline_user_args())
##   --map=<name|res://path.tres>  Map to fight on. A bare name resolves to
##                                 res://game/maps/resources/<name>.tres. Default: proving_grounds
##   --turns=<int>                 Round cap before the soak stops itself. Default: 60
##   --ts=<traditional|speed>      Turn system (aliases: trad/0, initiative/1). Default: traditional
##   --difficulty=<0..3>           AI difficulty (EASY..BRUTAL). Default: 1 (NORMAL)
##   --timescale=<float>           Engine.time_scale; the AI's dwell timers and every tween
##                                 are real-time, so this is what makes a 60-round soak finish
##                                 in seconds. Default: 10.0
##   --timeout=<seconds>           Hard wall-clock cap for the whole run. Default: 300
##   --stall=<seconds>             Abort if the battle state stops changing this long. Default: 45
##   --no-anim                     Disable unit animations (faster, but SKIPS the animation
##                                 code paths -- which is where a lot of the errors live).
##   --no-ui                       Skip the per-round HUD probe (see _probe_ui).
##   --verbose                     Per-round progress lines.
##
## EXIT CODES
##   0  The battle reached a conclusion (victory/defeat) or the round cap. Errors, if any,
##      are on stderr -- grep there, not here.
##   1  The soak could not run or could not finish: autoloads missing, the scene never
##      reached IN_PROGRESS, the wall-clock timeout expired, or the battle stalled.
##
## The summary line is machine-greppable:
##   [SOAK] RESULT outcome=<victory|defeat|turn_cap|stall|timeout|setup_failed> rounds=<n> ...


func _initialize() -> void:
	var runner := SoakRunner.new()
	runner.name = "SoakRunner"
	# The GameOverScreen pauses the tree the instant a battle is decided, so the runner
	# must keep processing to observe that and shut down cleanly.
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	runner.configure(_parse_args())
	root.add_child(runner)


## Parse `--key=value` / `--flag` pairs out of the post-`--` user args into a Dictionary.
## Unknown keys are simply ignored rather than aborting, so a stray CI argument cannot kill
## a run that would otherwise have produced useful error output.
func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for raw in OS.get_cmdline_user_args():
		var arg: String = String(raw)
		if not arg.begins_with("--"):
			continue
		arg = arg.substr(2)
		var key: String = arg
		var value: String = ""
		var eq: int = arg.find("=")
		if eq >= 0:
			key = arg.substr(0, eq)
			value = arg.substr(eq + 1)
		out[key] = value
	return out


# =============================================================================
# SoakRunner -- the state machine. A Node (not the SceneTree itself) so it can be
# PROCESS_MODE_ALWAYS across the game-over pause and be reasoned about like any other
# scene-tree citizen.
# =============================================================================
class SoakRunner extends Node:

	const MAPS_DIR := "res://game/maps/resources/"
	const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"

	## Frames to let the autoloads settle before touching them.
	const BOOT_FRAMES: int = 3

	## Wall-clock budget (seconds) for "scene loaded and the turn system is live". Generous:
	## a cold import of the map + unit scenes is the slowest part of the whole soak.
	const LOAD_BUDGET_S: float = 90.0

	## Autoloads the soak cannot run without. Checked up front so a missing one reports
	## itself instead of surfacing as a confusing null-instance error 200 lines later.
	const REQUIRED_AUTOLOADS: Array[String] = [
		"GameSettings", "PlayerManager", "TurnSystemManager", "GameEvents", "CombatServices",
	]

	enum Phase { BOOT, LOADING, RUNNING, DONE }

	# --- autoload access -------------------------------------------------------
	# Under `godot -s`, THIS script is the main loop and compiles BEFORE the
	# project's autoload singletons register their global identifiers - a bare
	# `GameSettings` is a compile error here (normal game scripts load later and
	# never hit this). All autoload access therefore goes through these runtime
	# lookups. Constants/enums still resolve through the instance (GDScript
	# allows constant access via instances), e.g. _gs().GameMode.SINGLE_PLAYER.
	func _gs() -> Node: return get_node("/root/GameSettings")
	func _pm() -> Node: return get_node("/root/PlayerManager")
	func _tsm() -> Node: return get_node("/root/TurnSystemManager")
	func _ge() -> Node: return get_node("/root/GameEvents")

	# --- configuration (set by configure()) ---
	var map_path: String = MAPS_DIR + "proving_grounds.tres"
	var round_cap: int = 60
	var ts_type: int = 0  # 0=TRADITIONAL, 1=INITIATIVE (raw values: no game class_name may be referenced at compile time under -s)
	var difficulty: int = 1
	var time_scale: float = 10.0
	var timeout_s: float = 300.0
	var stall_s: float = 45.0
	var animations: bool = true
	var ui_probe: bool = true
	var verbose: bool = false

	# --- state ---
	var _phase: int = Phase.BOOT
	var _frames: int = 0
	var _start_msec: int = 0
	var _phase_msec: int = 0
	var _last_change_msec: int = 0
	var _last_fingerprint: String = ""
	var _last_round: int = -1
	var _start_counts: Dictionary = {}
	var _probe_cursor: int = 0
	var _flipped: bool = false
	## True once the battle actually started. Gates the summary's board reads so a failure
	## during BOOT (where the autoloads may be the very thing that is missing) still prints
	## a clean result line instead of erroring inside its own reporter.
	var _ran: bool = false

	func configure(args: Dictionary) -> void:
		if args.has("map"):
			map_path = _resolve_map(String(args["map"]))
		if args.has("turns"):
			round_cap = maxi(1, int(String(args["turns"])))
		if args.has("ts"):
			ts_type = _resolve_turn_system(String(args["ts"]))
		if args.has("difficulty"):
			difficulty = clampi(int(String(args["difficulty"])), 0, 3)
		if args.has("timescale"):
			time_scale = clampf(float(String(args["timescale"])), 0.1, 50.0)
		if args.has("timeout"):
			timeout_s = maxf(10.0, float(String(args["timeout"])))
		if args.has("stall"):
			stall_s = maxf(5.0, float(String(args["stall"])))
		if args.has("no-anim"):
			animations = false
		if args.has("no-ui"):
			ui_probe = false
		if args.has("verbose"):
			verbose = true

	## A bare name resolves under the map resource dir; anything with a slash or a
	## res:// prefix is taken literally. A `.tres` suffix is optional either way.
	func _resolve_map(raw: String) -> String:
		var v: String = raw.strip_edges()
		if v.is_empty():
			return MAPS_DIR + "proving_grounds.tres"
		if not v.ends_with(".tres"):
			v += ".tres"
		if v.begins_with("res://") or v.contains("/"):
			return v
		return MAPS_DIR + v

	func _resolve_turn_system(raw: String) -> int:
		match raw.strip_edges().to_lower():
			"speed", "speedfirst", "speed_first", "initiative", "1":
				return 1
			_:
				return 0

	# --- lifecycle -----------------------------------------------------------

	func _ready() -> void:
		_start_msec = Time.get_ticks_msec()
		_phase_msec = _start_msec
		print("[SOAK] map=%s turns=%d ts=%s difficulty=%d timescale=%.1f anim=%s ui=%s"
			% [map_path, round_cap, ("TRADITIONAL" if ts_type == 0 else "INITIATIVE"),
				difficulty, time_scale, str(animations), str(ui_probe)])

	func _process(_delta: float) -> void:
		_frames += 1
		match _phase:
			Phase.BOOT:
				_tick_boot()
			Phase.LOADING:
				_tick_loading()
			Phase.RUNNING:
				_tick_running()
			_:
				pass

	# --- BOOT ----------------------------------------------------------------

	func _tick_boot() -> void:
		if _frames < BOOT_FRAMES:
			return
		var missing: Array[String] = []
		for n in REQUIRED_AUTOLOADS:
			if get_node_or_null("/root/" + n) == null:
				missing.append(n)
		if not missing.is_empty():
			_finish("setup_failed", "autoloads missing: %s" % ", ".join(missing), 1)
			return

		if not ResourceLoader.exists(map_path):
			_finish("setup_failed", "map not found: %s" % map_path, 1)
			return

		_apply_settings()
		_phase = Phase.LOADING
		_phase_msec = Time.get_ticks_msec()
		var err: int = get_tree().change_scene_to_file(GAME_WORLD_SCENE)
		if err != OK:
			_finish("setup_failed", "change_scene_to_file(%s) failed: %d" % [GAME_WORLD_SCENE, err], 1)

	## Configure the match exactly as the menus would, minus anything that writes to
	## user://. The presentation fields are set DIRECTLY rather than through their setters
	## because the setters persist to settings.cfg -- a soak must not mutate the developer's
	## saved preferences.
	func _apply_settings() -> void:
		_gs().set_game_mode(_gs().GameMode.SINGLE_PLAYER)
		_gs().set_selected_map(map_path)
		_gs().set_turn_system(ts_type)
		_gs().set_ai_difficulty(difficulty)
		# Field the map's OWN authored player-0 roster: no Character Select ran, and a stale
		# squad from a previous run's settings would spawn units this map never authored.
		_gs().clear_selected_squad()
		_gs().set_host_squad([])
		_gs().set_custom_map_json("")
		_gs().animations_enabled = animations
		# Author speed, not player speed: leave battle_speed at 1.0 so animation durations
		# stay authored, and compress wall-clock with Engine.time_scale instead. That way
		# every tween/timer still runs its full authored shape (which is where the errors
		# hide) -- just faster.
		_gs().battle_speed = 1.0
		# No human is at the keyboard, so the Speed First move clock has nothing to protect
		# and would only inject auto-end-turns that mask a real stall.
		_gs().speed_turn_timer_seconds = 0
		# Autoloads outlive scenes; make sure nothing from a prior run in this process leaks in.
		_pm().reset_for_new_game()
		_tsm().reset_for_new_game()
		Engine.time_scale = time_scale

	# --- LOADING -------------------------------------------------------------

	func _tick_loading() -> void:
		if _elapsed(_phase_msec) > LOAD_BUDGET_S:
			_finish("timeout", "scene never reached IN_PROGRESS within %.0fs" % LOAD_BUDGET_S, 1)
			return
		var scene: Node = get_tree().current_scene
		if scene == null or not is_instance_valid(scene):
			return
		if _pm().current_game_state != _pm().GameState.IN_PROGRESS:
			return
		if not _tsm().has_active_turn_system():
			return
		if _pm().players.is_empty():
			return
		_enter_running()

	func _enter_running() -> void:
		_phase = Phase.RUNNING
		_ran = true
		_phase_msec = Time.get_ticks_msec()
		_last_change_msec = _phase_msec
		_start_counts = _unit_counts()
		_flip_player_zero_to_ai()
		print("[SOAK] battle started: %s" % _describe_sides(_start_counts))

	# --- RUNNING -------------------------------------------------------------

	func _tick_running() -> void:
		# Re-assert every frame. It is idempotent, and it survives anything that rebuilds
		# the player list mid-battle (an Arena round, a rematch) without needing to know
		# about those flows.
		_flip_player_zero_to_ai()

		var rounds: int = _rounds()
		if rounds != _last_round:
			_last_round = rounds
			_on_round_advanced(rounds)

		if _battle_decided():
			_finish(_read_outcome(), "battle decided on round %d" % rounds, 0)
			return

		if rounds > round_cap:
			_finish("turn_cap", "reached the %d-round cap without a decision" % round_cap, 0)
			return

		if _elapsed(_start_msec) > timeout_s:
			_finish("timeout", "wall-clock budget of %.0fs expired on round %d" % [timeout_s, rounds], 1)
			return

		# STALL DETECTION. A soak whose whole point is surfacing errors must not sit
		# silently forever when the AI wedges -- that IS a bug, and a hang reports it as
		# nothing at all. The fingerprint covers everything a live battle changes.
		var fp: String = _fingerprint(rounds)
		if fp != _last_fingerprint:
			_last_fingerprint = fp
			_last_change_msec = Time.get_ticks_msec()
		elif _elapsed(_last_change_msec) > stall_s:
			_finish("stall", "no state change for %.0fs on round %d (state=%s)" % [stall_s, rounds, fp], 1)

	func _on_round_advanced(rounds: int) -> void:
		if verbose:
			print("[SOAK] round %d  %s" % [rounds, _describe_sides(_unit_counts())])
		if ui_probe:
			_probe_ui()

	## Flip player 0 to AI so BotTurnDriver drives BOTH sides.
	##
	## This is the cleanest lever available: the driver re-reads
	## [method TurnSystemBase.get_current_active_player]().is_ai on every beat, so nothing
	## has to be re-registered or restarted -- the very next beat picks player 0 up. The
	## driver itself is already mounted, because GameWorldManager._setup_players calls
	## _ensure_bot_driver() for every SINGLE_PLAYER match.
	##
	## UnitActionsPanel._human_may_command / cursor.gd both return `not player.is_ai`, so
	## flipping also CLOSES the human command path rather than blocking the bot -- the two
	## never contend. The known cost is that a few is_ai-keyed cosmetics (enemy tint, the
	## "ENEMY TURN" banner) now read player 0 as hostile; harmless headless, but it means
	## the soak does not exercise the ALLY branch of those specific cosmetics.
	func _flip_player_zero_to_ai() -> void:
		if _pm().players.is_empty():
			return
		var p = _pm().players[0]
		if p == null or p.is_ai:
			return
		p.is_ai = true
		if not _flipped:
			_flipped = true
			print("[SOAK] player 0 (%s) is now bot-driven" % p.get_display_name())

	# --- state reads ---------------------------------------------------------

	## Rounds elapsed, normalised across turn systems. Traditional counts one
	## `current_turn` per PLAYER turn, so a round is that divided by the player count;
	## Speed First already counts rounds.
	func _rounds() -> int:
		if not _tsm().has_active_turn_system():
			return maxi(0, _last_round)
		var ts = _tsm().get_active_turn_system()
		if ts == null:
			return maxi(0, _last_round)
		if int(ts.system_type) == 0:
			var n: int = maxi(1, ts.registered_players.size())
			return int((maxi(1, ts.current_turn) - 1) / n) + 1
		return maxi(1, ts.current_turn)

	## Living unit count per player index. Also the basis of the "units lost" summary.
	func _unit_counts() -> Dictionary:
		var out: Dictionary = {}
		for i in range(_pm().players.size()):
			var p = _pm().players[i]
			var n: int = 0
			if p != null:
				for u in p.owned_units:
					if u != null and is_instance_valid(u) and u.is_alive():
						n += 1
			out[i] = n
		return out

	func _describe_sides(counts: Dictionary) -> String:
		var parts: Array[String] = []
		for i in counts:
			var idx: int = int(i)
			var p = _pm().players[idx] if idx < _pm().players.size() else null
			var label: String = p.get_display_name() if p != null else "p%d" % idx
			parts.append("%s=%d" % [label, int(counts[i])])
		return " ".join(parts)

	## Everything a live battle mutates, in one comparable string. If this is unchanged for
	## `stall_s` the battle is genuinely wedged, not merely slow.
	func _fingerprint(rounds: int) -> String:
		var alive: int = 0
		var hp: int = 0
		for p in _pm().players:
			if p == null:
				continue
			for u in p.owned_units:
				if u == null or not is_instance_valid(u) or not u.is_alive():
					continue
				alive += 1
				hp += u.get_hp()
		var acting: String = ""
		if _tsm().has_active_turn_system():
			var ts = _tsm().get_active_turn_system()
			if ts != null:
				acting = "t%d/a%d" % [ts.current_turn, ts.get_active_units().size()]
		return "r%d/u%d/h%d/%s" % [rounds, alive, hp, acting]

	func _game_over_screen() -> Node:
		var scene: Node = get_tree().current_scene
		if scene == null or not is_instance_valid(scene):
			return null
		var n: Node = scene.get_node_or_null("UI/GameOverScreen")
		if n == null:
			n = scene.find_child("GameOverScreen", true, false)
		return n

	func _battle_decided() -> bool:
		var screen: Node = _game_over_screen()
		if screen != null and screen.has_method("is_shown") and bool(screen.call("is_shown")):
			return true
		# Fallback for any path that ends a battle without the overlay (and the belt to the
		# overlay's braces): PlayerManager itself declaring the game finished.
		return _pm().current_game_state == _pm().GameState.FINISHED

	## Read the outcome off the revealed end screen. The banner text is the authoritative
	## record of what the game decided; fall back to counting sides when the screen is
	## absent (the FINISHED-without-overlay path).
	func _read_outcome() -> String:
		var screen: Node = _game_over_screen()
		if screen != null:
			var label = screen.get("_banner_label")
			if label != null and is_instance_valid(label):
				var text: String = String(label.get("text")).to_lower()
				if text.contains("victory") or text.contains("wins"):
					return "victory"
				if text.contains("defeat"):
					return "defeat"
		var counts: Dictionary = _unit_counts()
		return "victory" if int(counts.get(0, 0)) > 0 else "defeat"

	# --- HUD probe -----------------------------------------------------------

	## Exercise the hover/selection HUD once per round.
	##
	## The bot drives the BOARD, but it never touches the panels a human's cursor drives --
	## TerrainInfoPanel, UnitHoverPanel, UnitInfoPanel, BattleLog highlighting -- and those
	## panels hold unit references across turns, which is exactly the shape of bug that
	## spams the debugger when a hovered unit dies. So walk one unit per round through the
	## same GameEvents sequence board/cursor/cursor.gd emits (cursor_moved ->
	## unit_hover_started -> unit_selected, later unit_deselected -> unit_hover_ended), with
	## the same payload types, so the panels see nothing they would not see in real play.
	func _probe_ui() -> void:
		var units: Array = _living_units()
		if units.is_empty():
			return
		_probe_cursor = (_probe_cursor + 1) % units.size()
		var unit = units[_probe_cursor]
		if unit == null or not is_instance_valid(unit):
			return
		var pos: Vector3 = unit.global_position
		_ge().cursor_moved.emit(pos)
		_ge().unit_hover_started.emit(unit)
		_ge().unit_selected.emit(unit, pos)
		# Deliberately NOT deselected in the same frame: leaving the selection live across
		# the round is what makes the panels still be holding this unit if it dies next
		# turn -- the freed-reference case worth catching. Released on the wrap-around.
		if _probe_cursor == 0:
			_ge().unit_deselected.emit(unit)
			_ge().unit_hover_ended.emit(unit)

	func _living_units() -> Array:
		var out: Array = []
		for p in _pm().players:
			if p == null:
				continue
			for u in p.owned_units:
				if u != null and is_instance_valid(u) and u.is_alive():
					out.append(u)
		return out

	# --- shutdown ------------------------------------------------------------

	func _elapsed(since_msec: int) -> float:
		return float(Time.get_ticks_msec() - since_msec) / 1000.0

	## Print the machine-greppable summary and quit. Unpauses first: the GameOverScreen
	## pauses the tree when it reveals, and quitting a paused tree leaves the teardown
	## handlers unrun -- which would hide exactly the scene-teardown errors this harness
	## exists to surface.
	func _finish(outcome: String, detail: String, code: int) -> void:
		if _phase == Phase.DONE:
			return
		_phase = Phase.DONE
		get_tree().paused = false
		Engine.time_scale = 1.0

		var rounds: int = maxi(0, _last_round)
		var alive_desc: String = "-"
		var lost_desc: String = "-"
		if _ran:
			var end_counts: Dictionary = _unit_counts()
			alive_desc = _describe_sides(end_counts)
			var lost: Array[String] = []
			for i in _start_counts:
				var idx: int = int(i)
				var before: int = int(_start_counts[i])
				var after: int = int(end_counts.get(i, 0))
				lost.append("p%d=%d" % [idx, maxi(0, before - after)])
			lost_desc = " ".join(lost)

		print("[SOAK] %s" % detail)
		print("[SOAK] RESULT outcome=%s rounds=%d elapsed=%.1fs alive=[%s] lost=[%s] exit=%d"
			% [outcome, rounds, _elapsed(_start_msec), alive_desc, lost_desc, code])
		get_tree().quit(code)
