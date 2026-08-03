extends RefCounted

## The SHARED map-ROW model for every versus map picker: what a row says, what badge it
## carries, and when it is refused -- plus the two renderers that draw it (an [ItemList]
## row for [MatchSetup], a real button row for the [CollaborativeLobby] panel).
##
## WHY THIS FILE EXISTS. Two screens list the same maps -- the local/hot-seat picker
## ([MatchSetup]) and the networked lobby's map-vote panel -- and both must badge a
## downloaded map the same way, order the list the same way, and say the same sentence when
## a map is refused. The lobby's file is co-owned by the transport workstream, so its map
## list is built by CALLING this (three lines) rather than by growing another copy of the
## row code inside it.
##
## Preloaded BY PATH (`const MapRowBuilder := preload("res://menus/MapRowBuilder.gd")`),
## never by `class_name`: a brand new script is not in the project's global class cache until
## the project is next imported, and a screen that only parses after someone opens the editor
## is a screen that does not ship. (Same rule as `menus/ReplayWatch.gd`.)
##
## The CATALOG behind it ([code]MapCatalog.versus_maps()[/code] /
## [code]MapCatalog.network_eligible()[/code]) is owned by a parallel workstream and is
## resolved AT RUNTIME by path with a has-method guard, so every screen here parses and runs
## in a build that does not ship it yet -- see [method catalog]. Without it the list falls
## back to [method MapLoader.get_available_map_entries], which knows builtin vs custom but
## cannot tell a downloaded map from a hand-authored one (both are `user://maps/*.json`);
## the fallback therefore badges those CUSTOM, and the catalog is the authority the moment
## it lands.
##
## The row model itself is pure: [method build_rows] takes entries + a Callable for
## eligibility and returns sorted dictionaries, so the badge / ordering / refusal rules are
## unit-testable with no catalog, no disk and no scene tree.

# --- Vocabulary (mirrors the pinned MapCatalog contract) ---------------------
const SOURCE_BUILTIN := "builtin"
const SOURCE_CUSTOM := "custom"
const SOURCE_COMMUNITY := "community"

## What each source shows as a chip. Builtin is deliberately UNBADGED: it is the default
## case, and a badge on every row badges nothing.
const BADGE_CUSTOM := "CUSTOM"
const BADGE_COMMUNITY := "COMMUNITY"

## The one sentence for a map the opponent's client could not be handed. Networked lobby
## only -- a local hot-seat match sends nothing to anybody, so nothing is ever refused there.
const TOO_LARGE_TOOLTIP := "Too large to send to your opponent"

## A map file the library lists but this build cannot read (a truncated download, a map
## authored against assets that are gone). Expected data, never an engine error.
const UNREADABLE_TOOLTIP := "This map could not be read."

## Ordering, PINNED: builtin first, then the player's own creations, then downloads --
## alphabetical (case-insensitive) inside each group. The shipped maps are the ones a new
## player recognises, and grouping keeps a big download library from burying them; plain
## alphabetical across all sources would interleave the three and make the badges the only
## way to tell them apart.
const SOURCE_RANK := {
	SOURCE_BUILTIN: 0,
	SOURCE_CUSTOM: 1,
	SOURCE_COMMUNITY: 2,
}

## Where the catalog lives when this build ships it. Tried in order; the first script that
## answers to `versus_maps` wins. Loaded by PATH so nothing here names it at parse time.
const CATALOG_PATHS: Array[String] = [
	"res://game/maps/MapCatalog.gd",
	"res://game/maps/catalog/MapCatalog.gd",
	"res://game/community/MapCatalog.gd",
]

# --- Catalog resolution -------------------------------------------------------
# Static, so the (cheap but not free) lookup happens once per process. `_catalog_override`
# is the test seam: inject a stand-in, and NOTHING here touches the real library.

static var _catalog_override = null
static var _catalog_cached = null
static var _catalog_looked_up: bool = false


## Inject a stand-in catalog (tests). Pass [code]null[/code] to fall back to the real one.
## Restore this from `after_each` -- it is process-wide state.
static func set_catalog(catalog) -> void:
	_catalog_override = catalog


## Forget the resolved catalog, so the next call looks it up again.
static func reset_catalog() -> void:
	_catalog_override = null
	_catalog_cached = null
	_catalog_looked_up = false


## The live catalog, or [code]null[/code] when this build does not ship one.
static func catalog():
	if _catalog_override != null:
		return _catalog_override
	if not _catalog_looked_up:
		_catalog_looked_up = true
		_catalog_cached = _find_catalog()
	return _catalog_cached


static func _find_catalog():
	# An autoload wins if one is registered under that name (the catalog may ship either way).
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var root: Node = (loop as SceneTree).root
		if root != null:
			var node: Node = root.get_node_or_null("MapCatalog")
			if node != null and responds(node, "versus_maps"):
				return node
	for path in CATALOG_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var script: Resource = load(path)
		if script != null and responds(script, "versus_maps"):
			return script
	return null


## True when [param obj] can be called with [param method]. The catalog may be an autoload
## NODE or a static-only SCRIPT, and a script's static functions do not answer to
## [method Object.has_method] -- so its declared method list is asked as well.
static func responds(obj, method: String) -> bool:
	if obj == null:
		return false
	if obj.has_method(method):
		return true
	return _method_info(obj, method) is Dictionary


## The declared method entry for [param method], or null. Used both to probe for a method and
## to count its arguments.
static func _method_info(obj, method: String):
	if obj == null:
		return null
	var methods: Array = []
	if obj is Script:
		methods = (obj as Script).get_script_method_list()
	else:
		methods = obj.get_method_list()
	for entry in methods:
		if entry is Dictionary and String((entry as Dictionary).get("name", "")) == method:
			return entry
	return null


## How many arguments [param method] declares (0 when it is not found). The catalog's
## `versus_maps` grew an optional `include_drafts` after the contract was pinned; asking
## rather than assuming keeps this working against BOTH shapes.
static func _arg_count(obj, method: String) -> int:
	var info = _method_info(obj, method)
	if not (info is Dictionary):
		return 0
	var args = (info as Dictionary).get("args", [])
	return (args as Array).size() if args is Array else 0


# --- The row model (pure) -----------------------------------------------------

## The chip text for [param source] -- "" for builtin, which is deliberately unbadged.
static func badge_for(source: String) -> String:
	match source:
		SOURCE_CUSTOM:
			return BADGE_CUSTOM
		SOURCE_COMMUNITY:
			return BADGE_COMMUNITY
	return ""


## The chip colour. Gold for the player's own creations (the accent that means "yours"
## everywhere else in these menus), dim cream for downloads -- the same pairing
## [CommunityBrowse] already uses for its CHALLENGE / MAP chips.
static func badge_color(source: String) -> Color:
	match source:
		SOURCE_CUSTOM:
			return MenuTheme.GOLD
		SOURCE_COMMUNITY:
			return MenuTheme.CREAM_DIM
	return MenuTheme.CREAM_DIM


## The prose form, for the preview card's detail block ("Source: Downloaded").
static func source_label(source: String) -> String:
	match source:
		SOURCE_CUSTOM:
			return "Your creation"
		SOURCE_COMMUNITY:
			return "Downloaded"
	return "Built-in"


## What a text-only row (an [ItemList] item) reads as. The badge is appended in brackets
## because an ItemList row cannot hold a chip Control -- see [method apply_to_item_list].
static func list_text(name: String, badge: String) -> String:
	if badge.is_empty():
		return name
	return "%s   [%s]" % [name, badge]


## One row from one catalog entry.
##
## [param entry] is the pinned catalog shape { path, name, source }, optionally carrying a
## already-loaded [code]resource[/code] and/or an explicit [code]loadable[/code] flag (see
## [method hydrate]). [param networked] gates the eligibility rule: a LOCAL match sends
## nothing to anybody, so an oversized map is perfectly playable hot-seat and is never
## refused there. [param eligible] is the answer for this path (ignored when not networked).
##
## Returns { path, name, source, badge, badge_color, meta, disabled, tooltip, list_text,
## resource }.
static func make_row(entry: Dictionary, networked: bool, eligible: bool) -> Dictionary:
	var path: String = String(entry.get("path", ""))
	var name: String = String(entry.get("name", "")).strip_edges()
	if name.is_empty():
		name = path.get_file().get_basename()
	var source: String = String(entry.get("source", SOURCE_BUILTIN))
	if not SOURCE_RANK.has(source):
		source = SOURCE_BUILTIN
	var resource = entry.get("resource", null)
	var loadable: bool = bool(entry.get("loadable", true))

	var badge: String = badge_for(source)
	var disabled: bool = false
	var tooltip: String = ""

	# Refusals, most specific first. Unreadable beats too-large: a map we cannot even read is
	# not a size problem, and telling the player to shrink it would be a lie.
	if not loadable:
		disabled = true
		tooltip = UNREADABLE_TOOLTIP
	elif networked and not eligible:
		disabled = true
		tooltip = TOO_LARGE_TOOLTIP
	else:
		tooltip = "%s  ·  %s" % [name, source_label(source)]

	return {
		"path": path,
		"name": name,
		"source": source,
		"badge": badge,
		"badge_color": badge_color(source),
		"meta": meta_for(resource),
		"disabled": disabled,
		"tooltip": tooltip,
		"list_text": list_text(name, badge),
		"resource": resource,
	}


## "12x10" off a loaded map, or "" when there is nothing loaded to read it from. Read from
## the SAME resource the row already carries -- this is not a second metadata source.
static func meta_for(resource) -> String:
	if resource == null:
		return ""
	if not ("width" in resource and "height" in resource):
		return ""
	return "%dx%d" % [int(resource.width), int(resource.height)]


## Rows for [param entries], refused + sorted. PURE given [param eligible_fn]: pass a
## Callable taking a path and returning bool (an empty Callable means "everything is
## eligible", which is also the right answer for a local match).
static func build_rows(entries: Array, networked: bool, eligible_fn: Callable = Callable()) -> Array:
	var rows: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var path: String = String((entry as Dictionary).get("path", ""))
		if path.is_empty():
			continue
		var eligible: bool = true
		if networked and eligible_fn.is_valid():
			eligible = bool(eligible_fn.call(path))
		rows.append(make_row(entry as Dictionary, networked, eligible))
	return sort_rows(rows)


## Builtin -> custom -> community, then case-insensitive by name, then by path so the order
## is total (two maps with the same name in the same group must not swap between rebuilds).
static func sort_rows(rows: Array) -> Array:
	var sorted: Array = rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a: int = int(SOURCE_RANK.get(String(a.get("source", SOURCE_BUILTIN)), 0))
		var rank_b: int = int(SOURCE_RANK.get(String(b.get("source", SOURCE_BUILTIN)), 0))
		if rank_a != rank_b:
			return rank_a < rank_b
		var name_a: String = String(a.get("name", "")).to_lower()
		var name_b: String = String(b.get("name", "")).to_lower()
		if name_a != name_b:
			return name_a < name_b
		return String(a.get("path", "")) < String(b.get("path", ""))
	)
	return sorted


# --- Catalog-backed entries ---------------------------------------------------

## The catalog's versus maps as { path, name, source } entries, falling back to
## [method MapLoader.get_available_map_entries] when this build ships no catalog.
##
## [param include_drafts] is what the LOCAL picker wants (you must be able to play-test a map
## you just built) and what the networked lobby does not. It is only forwarded when the
## catalog actually takes it -- see [method _arg_count].
static func versus_entries(include_drafts: bool = false) -> Array:
	var cat = catalog()
	if cat != null and responds(cat, "versus_maps"):
		var listed = cat.versus_maps(include_drafts) if _arg_count(cat, "versus_maps") >= 1 \
			else cat.versus_maps()
		if listed is Array:
			var out: Array = []
			for entry in listed:
				if entry is Dictionary:
					out.append((entry as Dictionary).duplicate())
			return out
	# Fallback: MapLoader tags origin builtin/custom. `origin` is its key name, `source` is
	# the catalog's -- normalise here so every consumer only ever reads one shape. It cannot
	# tell a download from a hand-authored map (both are user://maps/*.json), so it badges
	# them CUSTOM; the catalog is the authority the moment it is present.
	var out_fallback: Array = []
	for entry in MapLoader.get_available_map_entries(include_drafts):
		out_fallback.append({
			"path": String(entry.get("path", "")),
			"name": String(entry.get("name", "")),
			"source": String(entry.get("origin", SOURCE_BUILTIN)),
		})
	return out_fallback


## Whether [param path] is small enough to hand to an opponent. True when the build ships no
## catalog -- a picker that refused every map because the size oracle is missing would be
## worse than one that lets the transport report the failure itself.
static func network_eligible(path: String) -> bool:
	var cat = catalog()
	if cat != null and responds(cat, "network_eligible"):
		return bool(cat.network_eligible(path))
	return true


## Load a map by path, .tres or .json. Community + creator maps are inert JSON under
## `user://maps/` (never .tres -- a shared .tres is an arbitrary-code-execution vector), so
## they go through the HARDENED importer. Returns null on anything unreadable, QUIETLY: an
## unimportable file in the library is expected data here, not an impossible state.
static func load_map_resource(path: String) -> MapResource:
	if path.is_empty():
		return null
	if path.get_extension().to_lower() == "json":
		if not FileAccess.file_exists(path):
			return null
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return null
		var text: String = file.get_as_text()
		file.close()
		return MapResource.import_from_json(text, true)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as MapResource


## Load every entry's map resource, stamping `resource` + `loadable` onto it. Separated from
## [method build_rows] so the row rules stay pure and testable without disk.
static func hydrate(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var copy: Dictionary = (entry as Dictionary).duplicate()
		var resource: MapResource = load_map_resource(String(copy.get("path", "")))
		copy["resource"] = resource
		copy["loadable"] = resource != null
		if String(copy.get("name", "")).strip_edges().is_empty() and resource != null:
			copy["name"] = resource.map_name
		out.append(copy)
	return out


## The whole pipeline: catalog -> resources -> rows. [param networked] is true only in the
## lobby, where a map that cannot be shipped to the opponent is refused; [param include_drafts]
## only in the local picker, which must be able to play-test a work in progress.
static func versus_rows(networked: bool, include_drafts: bool = false) -> Array:
	return build_rows(hydrate(versus_entries(include_drafts)), networked, func(path: String) -> bool:
		return network_eligible(path)
	)


# --- Renderer A: an ItemList (MatchSetup keeps its list widget) ----------------

## Fill [param list] with [param rows]. An [ItemList] item is TEXT ONLY -- it cannot hold a
## chip Control -- so the badge rides in the item text (`Ridgeline   [CUSTOM]`) and is tinted
## with the source colour; the screen's preview card carries the real
## [method MenuTheme.make_chip]. Refused rows are set disabled with their sentence as the
## item tooltip. Adds NO height: an ItemList row's height comes from the font, not the string.
static func apply_to_item_list(list: ItemList, rows: Array, suffixes: Dictionary = {}) -> void:
	if list == null:
		return
	list.clear()
	for row in rows:
		if not (row is Dictionary):
			continue
		var name: String = String(row.get("name", ""))
		var suffix: String = String(suffixes.get(String(row.get("path", "")), ""))
		var index: int = list.add_item(list_text(name + suffix, String(row.get("badge", ""))))
		list.set_item_tooltip(index, String(row.get("tooltip", "")))
		if not String(row.get("badge", "")).is_empty():
			var tint: Color = row.get("badge_color", MenuTheme.CREAM)
			list.set_item_custom_fg_color(index, tint)
		if bool(row.get("disabled", false)):
			list.set_item_disabled(index, true)


# --- Renderer B: real chip rows (the lobby's vote panel) ----------------------

## Fixed row height, so the list's height is `rows * (ROW_HEIGHT + ROW_SEPARATION)` and the
## panel's floor below is arithmetic rather than a guess.
const ROW_HEIGHT := 44.0
const ROW_SEPARATION := 6
## Chip / meta / name floors. Every one of them is explicit: a chip-sized control with no
## floor collapses to its text width the moment the row is squeezed.
const CHIP_MIN_WIDTH := 96.0
const META_MIN_WIDTH := 120.0
const NAME_MIN_WIDTH := 160.0

## The scrolling region's floor (the ONE flexible region of the list card) and the card's
## own, which adds the MenuTheme PanelContainer content margin (12 top + 12 bottom).
const SCROLL_MIN_HEIGHT := 216.0
const CARD_MIN_HEIGHT := 240.0


## A scrolling, badged map list as a self-contained card.
##
## [param on_selected] is called as [code]on_selected.call(path, map_resource)[/code] when a
## row is picked -- the same (path, MapResource) shape [code]MapSelectorPanel.map_changed[/code]
## emitted, so a caller's handler does not change. Nothing is auto-selected: a vote is an act,
## not a default.
##
## Pass [param rows] to render a prepared model (tests); omit it to read the catalog.
static func build_list(networked: bool, on_selected: Callable, rows: Array = []) -> Control:
	var used: Array = rows if not rows.is_empty() else versus_rows(networked)

	var card := PanelContainer.new()
	card.name = "MapRowList"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, CARD_MIN_HEIGHT)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(0.0, SCROLL_MIN_HEIGHT)
	card.add_child(scroll)

	var box := VBoxContainer.new()
	box.name = "Rows"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", ROW_SEPARATION)
	scroll.add_child(box)

	if used.is_empty():
		var empty := Label.new()
		empty.text = "No maps in your library yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuTheme.style_caption(empty)
		box.add_child(empty)
		return card

	# Captured BY VALUE -- an Array is a reference, so every row's lambda sees the same list
	# and the selection highlight can be cleared across all of them.
	var buttons: Array = []
	for row in used:
		if not (row is Dictionary):
			continue
		var button := build_row_button(row as Dictionary)
		var path: String = String((row as Dictionary).get("path", ""))
		var resource = (row as Dictionary).get("resource", null)
		button.pressed.connect(func() -> void:
			for other in buttons:
				other.theme_type_variation = &"Button"
			button.theme_type_variation = &"SelectedButton"
			var res: MapResource = resource if resource is MapResource else load_map_resource(path)
			if res == null:
				return  # a row whose map will not load is already disabled; belt and braces
			if on_selected.is_valid():
				on_selected.call(path, res)
		)
		buttons.append(button)
		box.add_child(button)

	return card


## One row: name (clipped + ellipsised), size, and the source chip. Refused rows come back
## disabled with their sentence as the tooltip.
static func build_row_button(row: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = String(row.get("tooltip", ""))
	button.disabled = bool(row.get("disabled", false))

	var line := HBoxContainer.new()
	# A Button is not a Container, so the row's content is anchored to it by hand, inset to
	# clear the button stylebox's own 14/9 content margins.
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 12.0
	line.offset_right = -12.0
	line.offset_top = 4.0
	line.offset_bottom = -4.0
	line.add_theme_constant_override("separation", 10)
	# The row's CONTENT must never eat the button's own click.
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)

	var name_label := Label.new()
	name_label.text = String(row.get("name", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.custom_minimum_size = Vector2(NAME_MIN_WIDTH, 0.0)
	# A player-authored title is arbitrary length: clip so it can never push the chip off the
	# right edge of the row.
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)

	var meta_label := Label.new()
	meta_label.text = String(row.get("meta", ""))
	MenuTheme.style_caption(meta_label)
	meta_label.custom_minimum_size = Vector2(META_MIN_WIDTH, 0.0)
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(meta_label)

	# The chip slot is ALWAYS present (an empty holder on builtin rows), so the name column is
	# the same width on every row and the list reads as a column rather than a ragged edge.
	var chip_slot := CenterContainer.new()
	chip_slot.name = "ChipSlot"
	chip_slot.custom_minimum_size = Vector2(CHIP_MIN_WIDTH, 0.0)
	chip_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(chip_slot)

	var badge: String = String(row.get("badge", ""))
	if not badge.is_empty():
		var tint: Color = row.get("badge_color", MenuTheme.CREAM_DIM)
		var chip: Label = MenuTheme.make_chip(badge, tint)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_slot.add_child(chip)

	return button
