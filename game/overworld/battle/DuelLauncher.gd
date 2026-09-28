class_name DuelLauncher
extends RefCounted

## THE DUEL SEAM (docs/design/OVERWORLD.md §7.2, DUEL_BATTLE.md §8.1). The overworld never
## renders a duel: StoryController hands a [BattleRequest] (kind "duel") to [method launch] and
## waits for StoryController.report_battle_result.
##
## The DUEL feature registers its real launcher at startup --
##   DuelController.register_story_launcher() -> DuelLauncher.register(launch_from_story)
## -- which REPLACES the debug [DuelStub] with no overworld change. A stub never replaces a real
## launcher (registration order between autoloads does not matter), so the stub is only the
## fallback when no real duel is present.
##
## A launcher is a Callable taking the request; it may return {success, reason} (anything else
## counts as success). It stages the request and changes scene (the real duel) or mounts an
## overlay (the stub). Static, process-wide state: tests restore it with [method reset].

static var _launcher: Callable = Callable()
static var _is_stub: bool = false


## Register [param launcher]. A stub ([param is_stub] true) only fills an EMPTY seam or replaces
## another stub; a real launcher always wins.
static func register(launcher: Callable, is_stub: bool = false) -> void:
	if not launcher.is_valid():
		return
	if is_stub and _launcher.is_valid() and not _is_stub:
		return
	_launcher = launcher
	_is_stub = is_stub


static func has_launcher() -> bool:
	return _launcher.is_valid()


static func is_stub() -> bool:
	return _launcher.is_valid() and _is_stub


## True when [param launcher] is the one registered (its owner unregisters on shutdown).
static func is_registered(launcher: Callable) -> bool:
	return _launcher.is_valid() and launcher.is_valid() and _launcher == launcher


## Hand [param request] to the registered launcher. {success, reason}; never logs.
static func launch(request: BattleRequest) -> Dictionary:
	if request == null:
		return {"success": false, "reason": "no_request"}
	if not request.is_duel():
		return {"success": false, "reason": "not_a_duel"}
	if not _launcher.is_valid():
		return {"success": false, "reason": "no_duel_launcher"}
	var r = _launcher.call(request)
	if r is Dictionary:
		return {"success": bool(r.get("success", true)), "reason": String(r.get("reason", ""))}
	return {"success": true, "reason": ""}


## Forget the registered launcher (tests).
static func reset() -> void:
	_launcher = Callable()
	_is_stub = false
