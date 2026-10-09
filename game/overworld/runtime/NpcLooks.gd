class_name NpcLooks
extends RefCounted

## WHAT A PERSON ON THE OVERWORLD LOOKS LIKE (owner, 2026-10-08: "update the chonky NPC models with
## a clone of Wren for now as defaults, and a clone of the Lyra model as the female default").
##
## A PERSON is an [NpcEntity] (villager, trainer, merchant) with no
## [member OverworldEntity.visual_character]. Instead of the procedural "chonky" figure
## ([method OverworldProps.figure]) it wears a PLACEHOLDER HUMAN MODEL: a clone of a roster
## character's model, chosen by the story ruleset's "NPC looks" knobs
## ([member StoryRuleset.npc_default_model], [member StoryRuleset.npc_female_model] for an NPC whose
## [member NpcEntity.body] is "female"). A real model later is a data change: a roster id there,
## or a visual_character on that NPC.
##
## Unchanged: an NPC WITH a visual_character (General Varden, Professor Elias, every creature), the
## hero's own actor, and every prop. The figure stays the fallback -- the knob off
## ([member StoryRuleset.npc_models_enabled]) or a roster id with no model.
##
## Every clone instances the roster's one PackedScene (CharacterLibrary caches the resource; the
## hero's model is the same PackedScene) -- nothing is reloaded per NPC.

const BODY_FEMALE := "female"

## Overlay materials by tint (one per colour, shared by every tinted NPC).
static var _tint_materials: Dictionary = {}


## True for an entity that is a person wearing a placeholder look (an NPC with no roster model).
static func is_person(e: OverworldEntity) -> bool:
	return e is NpcEntity and String(e.visual_character).is_empty()


## The roster id whose model [param e] wears under [param rs], or &"" for the procedural figure
## (not a person, the knob off, or no ruleset).
static func model_id(e: OverworldEntity, rs: StoryRuleset) -> StringName:
	if rs == null or not rs.npc_models_enabled or not is_person(e):
		return &""
	if (e as NpcEntity).body == BODY_FEMALE and not String(rs.npc_female_model).is_empty():
		return rs.npc_female_model
	return rs.npc_default_model


## Scale on top of the roster model's own: [member StoryRuleset.npc_child_scale] for a "child"
## figure, else 1.
static func scale_for(figure_kind: String, rs: StoryRuleset) -> float:
	if rs != null and figure_kind == "child":
		return rs.npc_child_scale
	return 1.0


## The overlay tint for a [param figure_kind] NPC with cloak [param cloak], or Color.WHITE (none):
## only the kinds listed in [member StoryRuleset.npc_tinted_figures] (the raiders), the cloak
## blended toward white by 1 - [member StoryRuleset.npc_tint_strength].
static func tint_for(figure_kind: String, cloak: Color, rs: StoryRuleset) -> Color:
	if rs == null or rs.npc_tint_strength <= 0.0 or not rs.npc_tinted_figures.has(figure_kind):
		return Color.WHITE
	var c: Color = Color.WHITE.lerp(cloak, clampf(rs.npc_tint_strength, 0.0, 1.0))
	c.a = 1.0
	return c


## Dress [param actor] as person [param e] (figure kind [param figure_kind]): its placeholder
## model, child-scaled and tinted. Falls back from the female model to the default one. Returns
## the roster CharacterResource worn, or null when the caller should build the figure instead.
static func dress(actor: OverworldActor, e: OverworldEntity, figure_kind: String, rs: StoryRuleset) -> CharacterResource:
	var id: StringName = model_id(e, rs)
	if String(id).is_empty():
		return null
	var ch: CharacterResource = _model_character(id)
	if ch == null and id != rs.npc_default_model:
		ch = _model_character(rs.npc_default_model)
	if ch == null:
		return null
	var inst := ch.model_scene.instantiate() as Node3D
	if inst == null:
		return null
	actor.set_model(inst, ch.model_yaw_deg, ch.model_scale * scale_for(figure_kind, rs))
	var tint: Color = tint_for(figure_kind, e.tint, rs)
	if tint != Color.WHITE:
		apply_tint(inst, tint)
	# Not every NPC on the same beat of the idle: start each one's loop somewhere of its own.
	actor.offset_clip(float(absi(String(e.id).hash()) % 1000) / 1000.0)
	return ch


static func _model_character(id: StringName) -> CharacterResource:
	if String(id).is_empty():
		return null
	var ch: CharacterResource = CharacterLibrary.get_character(id)
	if ch == null or ch.model_scene == null:
		return null
	return ch


## Lay [param tint] over every mesh under [param root] (a multiply overlay: the model's own
## texture, dyed). One extra unshaded pass per mesh; the material is shared per colour.
static func apply_tint(root: Node, tint: Color) -> void:
	var mat: StandardMaterial3D = _tint_materials.get(tint, null)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		mat.albedo_color = tint
		_tint_materials[tint] = mat
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).material_overlay = mat
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).material_overlay = mat
