extends HBoxContainer
class_name DuelPartyStrip

## A side's TEAM at a glance on its [DuelUnitCard] (party duels): one pip per member, lead first
## -- a small element crest over a thin HP bar. The fielded member's crest is ringed in gold, a
## fainted member's is dimmed and marked with a cross, and each pip's tooltip names the member
## and its HP. Hidden for a team of one (Singles). Built only from the theme factories
## (docs/UI_STYLE.md); rebuilt only when the team's state changes.

const PIP_PX := 26.0
const BAR_W := 24.0

var _sig: String = ""


func _ready() -> void:
	name = "PartyStrip"
	add_theme_constant_override("separation", 5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Show [param rows] ([method DuelBattle.team_view]) for team colour [param team].
func set_rows(rows: Array, team: Color) -> void:
	var sig := str(team)
	for r in rows:
		sig += "|%s:%d/%d:%s:%s" % [String(r.get("name", "")), int(r.get("hp", 0)), int(r.get("max_hp", 1)),
			str(r.get("fainted", false)), str(r.get("active", false))]
	if sig == _sig:
		return
	_sig = sig
	for c in get_children():
		remove_child(c)
		c.queue_free()
	visible = rows.size() > 1
	for r in rows:
		add_child(_pip(r, team))


func _pip(r: Dictionary, team: Color) -> Control:
	var col := VBoxContainer.new()
	col.name = "Pip%d" % int(r.get("index", 0))
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var fainted := bool(r.get("fainted", false))
	var active := bool(r.get("active", false))
	var fill: Color = ConquestTheme.element_color(String(r.get("element", "")))
	var ring: Color = ConquestTheme.GOLD if active else team
	var crest := ConquestTheme.portrait("✕" if fainted else String(r.get("name", "?")), fill, ring, PIP_PX)
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(crest)
	var bar := ConquestTheme.hp_bar(4.0)
	bar.name = "Hp"
	bar.custom_minimum_size = Vector2(BAR_W, 4.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frac: float = 0.0 if fainted else clampf(float(r.get("hp", 0)) / maxf(1.0, float(r.get("max_hp", 1))), 0.0, 1.0)
	bar.value = frac
	ConquestTheme.tint_hp_bar(bar, frac)
	col.add_child(bar)
	if fainted:
		col.modulate = Color(1, 1, 1, 0.4)
	var who := String(r.get("name", ""))
	col.tooltip_text = "%s · Fainted" % who if fainted else "%s · HP %d/%d%s" % [who, int(r.get("hp", 0)),
		int(r.get("max_hp", 1)), "  (in battle)" if active else ""]
	col.set_meta(&"fainted", fainted)
	col.set_meta(&"active", active)
	return col


## Test helper: the pips' (fainted, active) flags in team order.
func pip_states() -> Array:
	var out: Array = []
	for c in get_children():
		out.append({"fainted": bool(c.get_meta(&"fainted", false)), "active": bool(c.get_meta(&"active", false))})
	return out
