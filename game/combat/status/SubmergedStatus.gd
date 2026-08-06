extends StatusCondition
class_name SubmergedStatus

## The SUBMERGED status (Monster's Voidwalk): while it is live the unit is untouchable,
## and it is not on the board to look at either.
##
## THE MECHANIC IS AUTHORED DATA, NOT CODE. Immunity is the existing
## [code]invulnerable[/code] RULE FLAG, declared in `voidwalk.tres` exactly as Eldroot's
## Heartwood Guard declares it in `guarded.tres`. [method DamageMath.is_invulnerable]
## reads that flag, and it is checked ahead of mitigation and every scaling step on ALL
## THREE damage roads:
##   * a move / ability / status tick -- [method DamageEffect.apply] short-circuits to a
##     hard, logged 0;
##   * a tile effect -- same road, since tile damage rides the ordinary damage pipeline;
##   * a crawling or erupting hazard -- [method DamageMath.environment_damage] returns 0
##     before it mitigates anything.
## The FORECAST honours it too, from the same function, so the panel reports 0 rather
## than a mitigated number the blow will never deal. None of that needed writing.
##
## WHAT THIS SCRIPT OWNS is only the LOOK: the unit's model is hidden while it is under,
## and shown again when it surfaces. That lives here, on the status, rather than in a
## visual system, because it is one property toggled on two hooks that already exist and
## it must be impossible for the model to stay hidden after the immunity has gone -- tying
## both to the same instance's lifetime is what guarantees that. [method on_expire] fires
## however the status ends (timing out, being cleansed, the controller being cleared), so
## there is no path that leaves an invisible unit behind.
##
## IT TOGGLES `visible`, NOT MATERIALS, on purpose. [UnitVisualManager] drives the
## spent-turn wash and the team outline through `material_overlay` + `transparency` on
## each mesh, and [UnitAnimator] flashes `material_override`; writing to any of those
## would fight them and leave a unit stuck grey. `visible` on the model root is a channel
## nothing else touches, and restoring it restores the unit's exact look.
##
## EXPIRES AT THE CASTER'S NEXT TURN START, from the ordinary 1-turn status tick both
## turn systems drive (CONQUEST.md rule 2) -- so it covers exactly the round trip through
## the enemy's turn and no longer.
##
## STILL TARGETABLE, DELIBERATELY. Nothing removes a submerged unit from
## [method MoveContext.gather_targets]: the gather path is shared by every move, ability
## and tile in the game, and teaching it to skip flagged units would also make a submerged
## unit unhealable and unbuffable by its own side, and would silently change what Eldroot's
## Guarded does. The AI is stopped from wasting turns on it one layer up instead --
## [method BotController._estimate_damage] scores an invulnerable target at 0, which both
## ranked-attack paths already drop -- so the bot simply never proposes the attack.

## The model root's `visible` flag as it was before we hid it, so surfacing restores what
## was actually there rather than assuming true. Runtime state, never exported.
var _was_visible: bool = true
## Weak handle on the node we hid, so a unit freed while submerged can never be touched
## through a dangling reference on the way out.
var _model_ref: WeakRef = null


## Went under: hide the model. Null-safe and duck-typed -- a mock target, or a unit with
## no model yet, simply stays as it was and the immunity works regardless.
func on_apply(target, _board) -> void:
	var model := _model_root(target)
	if model == null:
		return
	_model_ref = weakref(model)
	_was_visible = bool(model.visible)
	model.visible = false


## Surfaced: put the model back exactly as it was.
func on_expire(_target, _board) -> void:
	if _model_ref == null:
		return
	var model = _model_ref.get_ref()
	_model_ref = null
	if model == null or not is_instance_valid(model):
		return
	model.visible = _was_visible


## [param unit]'s visible model root, resolved the way [UnitVisualManager] and
## [UnitAnimator] resolve it: the "CharacterModel" glb root, else the placeholder
## "MeshInstance3D", else nothing. Null for anything that is not a live scene-tree unit,
## which is every mock in the unit suites.
func _model_root(unit) -> Node3D:
	if unit == null or not (unit is Node) or not is_instance_valid(unit):
		return null
	var model: Node = (unit as Node).get_node_or_null("CharacterModel")
	if model is Node3D:
		return model as Node3D
	var direct: Node = (unit as Node).get_node_or_null("MeshInstance3D")
	if direct is Node3D:
		return direct as Node3D
	return null
