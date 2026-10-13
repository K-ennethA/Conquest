extends RefCounted

const CATEGORY := ["Physical", "Magical", "True"]
const SKIP := ["bastion"]  # the Destroy Base structure is not a creature
## The owner's "how it evolves" text per edge: page-only design notes the game has no field for.
const EVOLUTION_NOTES := "res://dev_scripts/roster_page_evolution_notes.json"


func run(out_path: String) -> void:
	var chars: Array = []
	for id in CharacterLibrary.all_ids():
		if String(id) in SKIP:
			continue
		var c: CharacterResource = CharacterLibrary.get_character(id)
		if c == null:
			continue
		var moves: Array = []
		for m in c.moveset:
			if m != null:
				moves.append(_move(m))
		var abilities: Array = []
		for a in c.abilities:
			if a != null:
				abilities.append(_ability(a))
		chars.append({
			"id": String(c.character_id), "name": c.display_name, "kind": "human" if c.is_human() else "creature",
			"element": String(c.element), "element2": String(c.element2), "description": c.description,
			"tags": c.tags.map(func(t): return String(t)), "catch_rate": c.catch_rate, "xp_yield": c.xp_yield,
			"is_boss": c.is_boss, "has_model": c.model_scene != null, "path": c.resource_path,
			"stats": {"health": c.base_health, "attack": c.base_attack, "defense": c.base_defense,
				"magic": c.base_magic, "magic_defense": c.base_magic_defense, "speed": c.base_speed,
				"movement": c.base_movement, "range": c.attack_range},
			"moves": moves, "abilities": abilities,
			"weapon": _weapon(c.weapon) if c.is_human() and c.weapon != null else null,
			# The page publishes one portrait per character beside itself (portraits/<id>.png).
			"art": "portraits/%s.png" % String(c.character_id),
		})
	var all_moves: Array = []
	for f in DirAccess.get_files_at("res://game/combat/moves/"):
		if f.ends_with(".tres"):
			var m = load("res://game/combat/moves/" + f)
			if m is MoveResource:
				all_moves.append(_move(m))
	var all_abilities: Array = []
	for f in DirAccess.get_files_at("res://game/abilities/"):
		if f.ends_with(".tres"):
			var a = load("res://game/abilities/" + f)
			if a is AbilityResource:
				all_abilities.append(_ability(a))
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"characters": chars, "moves": all_moves, "abilities": all_abilities,
		"evolutions": _evolutions()}))
	fa.close()
	print("[export] %d characters, %d moves, %d abilities -> %s" % [chars.size(), all_moves.size(), all_abilities.size(), out_path])


func _move(m: MoveResource) -> Dictionary:
	var power := 0
	var effects: Array = []
	for e in m.effects:
		if e == null:
			continue
		var script: Script = e.get_script()
		effects.append(script.get_global_name() if script != null else "Effect")
		if power == 0 and "power" in e:
			power = int(e.get("power"))
	return {"id": String(m.move_id), "name": m.display_name, "description": m.description,
		"element": String(m.element), "category": CATEGORY[clampi(int(m.category), 0, 2)], "power": power,
		"accuracy": m.accuracy, "crit": m.crit_chance, "energy": m.energy_cost, "uses": m.max_uses,
		"cooldown": m.cooldown, "ultimate": m.is_ultimate, "effects": effects, "path": m.resource_path}


func _ability(a: AbilityResource) -> Dictionary:
	return {"id": String(a.id), "name": a.display_name, "description": a.description,
		"trigger": int(a.trigger), "cooldown": a.cooldown, "path": a.resource_path}


func _weapon(w: WeaponResource) -> Dictionary:
	return {"id": String(w.weapon_id), "name": w.display_name, "description": w.description,
		"type": String(w.weapon_type), "might": w.might, "hit": w.hit, "crit": w.crit,
		"min_range": w.min_range, "max_range": w.max_range, "path": w.resource_path}


func _evolutions() -> Array:
	var notes: Dictionary = {}
	if FileAccess.file_exists(EVOLUTION_NOTES):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EVOLUTION_NOTES))
		if parsed is Dictionary:
			notes = parsed
	var out: Array = []
	for e in EvolutionLibrary.all():
		if e == null:
			continue
		var reqs: Array = []
		for trig in e.triggers:
			if trig != null:
				reqs.append(_req(trig))
		var row := {"id": String(e.id), "from": String(e.from_id), "to": String(e.to_id), "kind": e.kind_label,
			"flavor": e.flavor, "reqs": reqs}
		if notes.has(String(e.id)):
			row["how"] = String(notes[String(e.id)])
		out.append(row)
	return out


## One requirement in the page's vocabulary ({kind, value}); anything unrecognised is "other".
func _req(t) -> Dictionary:
	if t is LevelTrigger:
		return {"kind": "level", "value": t.level_required}
	if t is GrowthTrigger:
		return {"kind": "growth", "value": t.growth_required}
	if t is BattleFeatTrigger:
		return {"kind": "kos" if int(t.feat) == 1 else "wins", "value": t.count}
	if t is UseItemTrigger:
		return {"kind": "use_item", "value": t.item_id}
	if t is HeldItemTrigger:
		return {"kind": "hold_item", "value": t.item_id}
	if t is KnowsMoveTrigger:
		return {"kind": "knows_move", "value": String(t.move_id)}
	if t is LocationTrigger:
		return {"kind": "location", "value": t.place_label if t.place_label != "" else (t.region_id if t.region_id != "" else ", ".join(t.area_ids))}
	if t is WeatherTrigger:
		return {"kind": "weather", "value": ", ".join(t.weathers)}
	if t is StoryFlagTrigger:
		return {"kind": "story_flag", "value": t.flag}
	if t is PartyHasTrigger:
		return {"kind": "party_has", "value": t.character_id}
	return {"kind": "other", "value": t.describe()}
