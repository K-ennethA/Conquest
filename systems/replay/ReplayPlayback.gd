extends RefCounted
class_name ReplayPlayback

## THE HAND-OFF between "here is a replay log" and "the battle scene is now replaying it".
##
## Pure static holder, no autoload -- exactly the shape [BattleSaveManager]'s resume staging
## uses ([method BattleSaveManager.stage_resume] / [method BattleSaveManager.has_pending_resume]
## / [method BattleSaveManager.take_pending_resume]), because it solves the identical problem:
## something outside the battle scene decides what the next battle IS, parks it in process-wide
## static state, and changes scene; [GameWorldManager] picks it up on the other side. Static
## state is what survives the scene change.
##
## THE WHOLE CONTRACT with the replay-picker UI is two calls:
## [codeblock]
## var log: Dictionary = ReplayLog.load_from_file(path)   # {} when the file is not a replay
## var res: Dictionary = ReplayPlayback.launch(log)       # { ok: true } | { ok: false, error }
## [/codeblock]
## [method launch] answers, it never talks to the player: a menu shows the error, and a
## [constant ERROR_VERSION_MISMATCH] refusal leaves the caller's screen exactly as it was.
##
## WHAT LAUNCHING STAGES. The header alone has to be able to rebuild the battle, so staging
## points the SAME setters a real launch does:
##   * [GameSettings] -- map, turn system, difficulty, player count, slot 0's squad. The
##     ordinary boot reads these; nothing bespoke.
##   * [MatchLoadouts] -- one card per recorded participant (squad + items + skins), with the
##     local slot set to [constant SPECTATOR_SLOT], a slot no participant occupies. That single
##     fact is what makes every recorded side field ITS OWN roster, items and skins through the
##     exact code path a NETWORKED match uses, instead of the viewer's local inventory being
##     applied to slot 0 (see [method MatchLoadouts.skin_for] / [method ItemSystem.loadout_for_slot]).
##     The viewer is a spectator, so "none of these slots are mine" is literally true.
##
## THE LOADOUT ROUND TRIP IS EXACT. A participant is recorded in the [MatchLoadouts] card
## shape itself ([code]equipped[/code] keyed by character, [code]team[/code], [code]skins[/code]
## -- see [method ReplayRecorder.participant_loadout]), so staging republishes those three
## fields VERBATIM and the spawn path reads them back through the same
## [method MatchLoadouts.items_for] / [method MatchLoadouts.skin_for] calls that answered when
## the battle was recorded. A worn UNIT item stays on the one character who wore it, which is
## what keeps the per-turn checksum quiet for the headline case: a challenge attacker carrying
## per-unit items, watched back by the defender.
##
## SPECTATOR MODE, and where each half of it lives:
##   * INPUT -- [method is_playing] is read by the battle command loop's one human-control
##     predicate, so no unit can be commanded. Camera pan/zoom, the cursor and every inspection
##     panel stay live: watching a replay is watching, not being locked out of the screen.
##   * AI -- [method disable_ai_drivers] frees the [BotTurnDriver], and [GameWorldManager] does
##     not mount one. Every AI action is already IN the log; a live driver would act twice.
##   * RECORDING -- [method begin_playback] switches [member ReplayRecorder.recording_enabled]
##     off (restoring it in [method end_playback]) so a replay being watched cannot record
##     itself into a second file.

# --- Scenes ------------------------------------------------------------------

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

# --- The result / error vocabulary (pinned: the picker UI codes against these) ----

## [method launch] could not make sense of the log at all -- [method ReplayLog.validate]
## refused it (not a replay, wrong format_version, a protocol this build cannot apply).
const ERROR_INVALID_REPLAY := "invalid_replay"
## The log is well-formed but was recorded by a DIFFERENT BUILD. Refused rather than played:
## re-simulating it would drift, and a drifting replay is a lie told convincingly.
const ERROR_VERSION_MISMATCH := "version_mismatch"
## No live [SceneTree] to change scene with (headless harness). The log is NOT staged.
const ERROR_NO_SCENE_TREE := "no_scene_tree"

## The roster slot the VIEWER occupies -- deliberately one no participant can have
## ([constant ReplayLog.MAX_PARTICIPANTS] is 8), so "is this slot mine?" is false for every
## recorded side and each one is rebuilt from its own recorded card.
const SPECTATOR_SLOT: int = 99

# --- Staged state (survives the scene change) --------------------------------

## The validated log waiting for the battle scene, consumed by [GameWorldManager].
static var _pending: Dictionary = {}
## A custom map materialised from the header's embedded payload, or null when the map is a
## plain path. Held as a resource rather than written to disk -- a replay's map is inert data
## we imported through the hardened importer, not a file the player owns.
static var _pending_map: MapResource = null
## True from the moment a replay is staged until the battle that played it is torn down.
static var _playing: bool = false
## What [member ReplayRecorder.recording_enabled] was before playback switched it off.
static var _recording_was_enabled: bool = true


# --- Launching ---------------------------------------------------------------

## Validate [param log], stage it, and change to the battle scene.
##
## Returns [code]{ "ok": true }[/code], or [code]{ "ok": false, "error": <one of the ERROR_*
## constants> }[/code]. A refusal changes NOTHING -- no scene change, no staged state, no
## engine log line -- so the caller can show the error and stay where it is.
static func launch(log: Dictionary) -> Dictionary:
	var clean: Dictionary = ReplayLog.validate(log)
	if clean.is_empty():
		return { "ok": false, "error": ERROR_INVALID_REPLAY }
	# The SOFT version gate, and the reason playback is the one that enforces it: format and
	# protocol mismatches are already hard-refused by validate, but a build whose GAMEPLAY
	# changed re-simulates the same commands into a different battle. Refuse the file instead.
	if not ReplayLog.matches_this_build(clean):
		return { "ok": false, "error": ERROR_VERSION_MISMATCH }

	var tree: SceneTree = _tree()
	if tree == null:
		return { "ok": false, "error": ERROR_NO_SCENE_TREE }

	stage(clean)
	tree.change_scene_to_file(GAME_WORLD_SCENE)
	return { "ok": true }


## Stage an ALREADY VALIDATED [param log] without touching the scene: park it, point every
## mode setter at its header, and arm spectator mode. Split out of [method launch] so the
## staging half is drivable headless (and so a test can prove what launching mutates).
static func stage(log: Dictionary) -> void:
	_pending = log
	_pending_map = _import_embedded_map(log)
	_stage_game_settings(log)
	_stage_loadouts(log)
	begin_playback()


## True while a staged replay is waiting for the battle scene to pick it up.
static func has_pending() -> bool:
	return not _pending.is_empty()


## Consume the staged replay (single-use, exactly like a staged resume): returns it and clears
## the slot, so a battle started later can never re-enter playback by accident.
static func take_pending() -> Dictionary:
	var log: Dictionary = _pending
	_pending = {}
	return log


## The custom map materialised from the staged header's embedded payload, or null when the
## header names a plain map path. Read (and cleared) by the battle boot.
static func take_pending_map() -> MapResource:
	var map: MapResource = _pending_map
	_pending_map = null
	return map


# --- Spectator mode ----------------------------------------------------------

## True while a replay is being watched. THE flag: the battle command loop reads it to refuse
## every human command, and the boot reads it to keep the AI and the recorder out.
static func is_playing() -> bool:
	return _playing


## Arm spectator mode: latch playback on and switch recording OFF, so a replay being watched
## cannot record itself. Idempotent -- the previous [member ReplayRecorder.recording_enabled]
## is only captured on the first call, so a second one cannot overwrite the value to restore.
static func begin_playback() -> void:
	if _playing:
		return
	_playing = true
	_recording_was_enabled = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = false


## Disarm spectator mode and put every process-wide switch back. Called from the driver's
## teardown, so ANY exit from the replay battle -- the exit button, the pause menu, a crash
## into the main menu -- restores recording for the next real battle. Idempotent and safe to
## call when nothing was ever staged, which is how the ordinary battle boot clears a flag
## left behind by a launch that never reached a battle.
static func end_playback() -> void:
	_pending = {}
	_pending_map = null
	if not _playing:
		return
	_playing = false
	ReplayRecorder.recording_enabled = _recording_was_enabled
	# The staged cards named a match that is over. Dropping them here means the next battle
	# resolves squads/items/skins from its own sources rather than the replay's.
	MatchLoadouts.clear()


## Free every AI driver under [param scene_root] and report how many went. Playback must NOT
## run the AI: every action it took is already in the log, so a live [BotTurnDriver] would act
## a second time on top of the replayed one. Node-name based (the driver is mounted as
## "BotTurnDriver") plus a script-class check, so a driver mounted under any name still goes.
static func disable_ai_drivers(scene_root: Node) -> int:
	if scene_root == null or not is_instance_valid(scene_root):
		return 0
	var removed: int = 0
	for child in scene_root.get_children():
		if child == null or not is_instance_valid(child):
			continue
		if not (child is BotTurnDriver) and String(child.name) != "BotTurnDriver":
			continue
		scene_root.remove_child(child)
		child.free()
		removed += 1
	return removed


## Leave the replay for the main menu -- the same plain exit [method PauseMenu._quit_to_menu]
## makes, minus the challenge-forfeit step (watching a replay spends nothing). Unpauses first:
## [member SceneTree.paused] survives a scene change, so an exit taken while paused would
## otherwise land on a frozen menu.
static func quit_to_menu() -> bool:
	var tree: SceneTree = _tree()
	if tree == null:
		return false
	tree.paused = false
	tree.change_scene_to_file(MAIN_MENU_SCENE)
	return true


# --- Header -> live setup ----------------------------------------------------

## Point the ordinary battle setters at [param log]'s header. Everything the boot reads about
## WHAT battle to build comes from here, so replay boot reuses the normal map/turn-system path
## rather than a parallel one.
static func _stage_game_settings(log: Dictionary) -> void:
	if typeof(GameSettings) != TYPE_OBJECT or GameSettings == null:
		return
	var participants: Array = log.get("participants", [])
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_turn_system(int(log.get("turn_system", 0)))
	GameSettings.set_ai_difficulty(int(log.get("difficulty", 0)))
	GameSettings.set_player_count(maxi(2, participants.size()))
	GameSettings.set_selected_map(String((log.get("map", {}) as Dictionary).get("path", "")))
	# Slot 0's own recorded pick, as the fallback the spawn path uses if the card below is
	# somehow unreadable. The cards are what actually fill the START points.
	GameSettings.set_selected_squad(_squad_of_slot(log, 0))
	# A host squad left over from a real networked match would OUTRANK slot 0's card in the
	# spawn path (see MapLoader._replicated_squad_for) -- so clear it.
	if GameSettings.has_method("set_host_squad"):
		GameSettings.set_host_squad([])


## Publish one [MatchLoadouts] card per recorded participant and seat the viewer in
## [constant SPECTATOR_SLOT]. See the class docs for why this is the right mechanism.
##
## The four fields are handed over UNTOUCHED: the recorder wrote them in this exact shape, so
## there is no translation step here to get wrong. [method MatchLoadouts.set_peer_loadout]
## still normalises them (the library whitelist), which is what makes a replay's cards no more
## trusted than a peer's -- an id that no longer resolves is dropped rather than fielded.
static func _stage_loadouts(log: Dictionary) -> void:
	MatchLoadouts.clear()
	for entry in (log.get("participants", []) as Array):
		if not (entry is Dictionary):
			continue
		var p: Dictionary = entry
		MatchLoadouts.set_peer_loadout(int(p.get("slot", 0)), {
			"equipped": p.get("equipped", {}),
			"team": p.get("team", []),
			"skins": p.get("skins", {}),
			"squad": p.get("squad", []),
		})
	# Set LAST: it is what makes the holder active, and every card has to be in place first.
	MatchLoadouts.set_local_slot(SPECTATOR_SLOT)


## The recorded squad for [param slot], as a plain Array of ids.
static func _squad_of_slot(log: Dictionary, slot: int) -> Array:
	for entry in (log.get("participants", []) as Array):
		if entry is Dictionary and int((entry as Dictionary).get("slot", -1)) == slot:
			var squad: Variant = (entry as Dictionary).get("squad", [])
			return (squad as Array).duplicate() if squad is Array else []
	return []


## Materialise the header's embedded custom-map payload through the HARDENED importer
## ([method MapResource.import_from_json], quiet), or null when there is no payload. Never
## [code]load()[/code]: a replay's map is untrusted JSON that travelled with the file.
static func _import_embedded_map(log: Dictionary) -> MapResource:
	var map: Dictionary = log.get("map", {})
	var payload: Variant = map.get("payload", {})
	if not (payload is Dictionary) or (payload as Dictionary).is_empty():
		return null
	return MapResource.import_from_json(JSON.stringify(payload), true)


static func _tree() -> SceneTree:
	var loop: MainLoop = Engine.get_main_loop()
	return loop as SceneTree
