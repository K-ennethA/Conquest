class_name StoryScriptHost
extends RefCounted

## THE HOST INTERFACE a story script talks to (docs/design/OVERWORLD.md §4.4 "ScriptHost"),
## written out as a no-op base class. The live host (the overworld's OverworldController node)
## implements the same method names; tests extend this class and record calls. Every method may
## be awaited -- this base completes instantly, which is exactly what a headless test wants.
##
##   show_dialogue(scene: StoryScene)                            -> void (await)
##   show_choice(prompt: StoryBeat, options: PackedStringArray,
##               cancel_index: int)                              -> int  (await; chosen index)
##   move_actor(actor_id: String, to: Vector3i, persist: bool)   -> void (await)
##   face_actor(actor_id: String, facing: String)                -> void
##   emote(actor_id: String, glyph: String)                      -> void (await)
##   wait(seconds: float)                                        -> void (await)
##   toast(text: String, kind: String)                           -> void
##   play_clash(request: BattleRequest)                          -> void (await; VS intro)
##   open_shop(shop: ShopResource)                               -> void (await; the shop screen)
##   open_ladder(tournament: TournamentResource, state)          -> String (await; the ladder pick)
##   refresh_world()                                             -> void
##
## Battles, saves and warps are NOT host calls: they outlive the scene, so they go through the
## session (StoryController) -- see [ScriptContext].


func show_dialogue(_scene: StoryScene) -> void:
	pass


func show_choice(_prompt: StoryBeat, _options: PackedStringArray, cancel_index: int = -1) -> int:
	return maxi(0, cancel_index)


func move_actor(_actor_id: String, _to: Vector3i, _persist: bool = false) -> void:
	pass


func face_actor(_actor_id: String, _facing: String) -> void:
	pass


func emote(_actor_id: String, _glyph: String) -> void:
	pass


func wait(_seconds: float) -> void:
	pass


func toast(_text: String, _kind: String = "") -> void:
	pass


func play_clash(_request) -> void:
	pass


func open_shop(_shop) -> void:
	pass


## The tournament ladder ([RunTournamentCommand]): the player's pick -- "enter" / "fight" /
## "withdraw" / "leave". The base leaves at once.
func open_ladder(_tournament, _state) -> String:
	return "leave"


func refresh_world() -> void:
	pass


## A beaten / befriended VISIBLE wild creature leaves the map ([WildOutcomeCommand]; the save
## record is already updated when this is called).
func despawn_wild(_creature_key: String) -> void:
	pass
