# UI style: "illuminated grove heraldry"

Every Conquest screen -- menus, lobby, Compendium, Arena, and the battle HUD --
shares one look: deep navy cards framed like an illuminated manuscript (notched
corners, an inset gold filigree line, gold clasps), heraldic crests for units,
element-coloured gems, swallow-tailed ribbons for banners, and Cinzel capitals for
titles and commands. Everything is drawn procedurally; there are no texture assets.

All of it lives in `game/ui/theme/`. New screens get it for free by using the theme
and the factories below -- never hand-roll a `StyleBoxFlat`.

## Tokens (`MenuTheme.gd`, the single source)

| Group | Tokens |
|---|---|
| Ground / panels | `BG_DEEP`, `BG`, `PANEL`, `PANEL_HI`, `PANEL_SUNK`, `BORDER`, `BORDER_SOFT` |
| Accent | `GOLD` (focus, selection, filigree), `GOLD_LITE`, `GOLD_DK` |
| Text | `CREAM` (primary), `TEXT_DIM`, `TEXT_MUTED`, `INK` (on gold) |
| States | `ACCENT` (info), `SUCCESS`, `DANGER`, `WARNING` |
| Teams | `TEAM_BLUE`, `TEAM_RED` (+ `ConquestTheme.TEAM_GREEN/GOLD`, `*_TEXT` variants) |
| Elements | `EL_FIRE` ember, `EL_WATER` tide teal, `EL_NATURE` grove green, `EL_WIND` sky, `EL_EARTH` amber/geode, `EL_HOLY` sun gold, `EL_DARK` blight violet |
| Type (1280x720 base units) | `FS_DISPLAY 72`, `FS_TITLE 40`, `FS_HEADING 26`, `FS_SUBHEADING 21`, `FS_BODY 18`, `FS_SMALL 16`, `FS_CAPTION 15` |
| Spacing | `SP_XS 4` ... `SP_XXL 32`, `SP_PAGE 48` |

`ConquestTheme.gd` (battle HUD) re-exports these and adds HUD sizes, HP tiers and
helpers. `ConquestTheme.element_color(name)` / `MenuKit.element_color(name)` map an
element name to its colour.

## Fonts

- **Cinzel** (SIL OFL 1.1, `fonts/Cinzel-OFL.txt`): `MenuTheme.display_font()`
  (Black -- screen titles, the game title, phase banners, crest initials) and
  `MenuTheme.heading_font()` (Bold -- headings, section tags, buttons, command rows,
  unit names). Glyphs Cinzel lacks (arrows, symbols) fall back to the engine font.
  Cinzel's lowercase are small capitals, so titles read as engraved capitals.
- **Body**: the engine sans (`bold_font()` for emphasis). Keep body >= `FS_SMALL`.

## The frame: `OrnateStyleBox`

A `StyleBox` subclass, so it works in any theme slot. Layers, in order: soft shadow,
focus glow, gradient fill, fine diagonal grain (`hatch_alpha`), inner vignette,
team / element accent stripe(s), outer border, inset filigree line, corner ornaments
(`CLASP` diamonds or `LEAF`), top `crest` (diamond + leaf sprig), left `marker` leaf.

Shapes: `CHAMFER` (cards, buttons; `cut_corners` picks corners), `TAG` (chips,
primary buttons), `BANNER` (swallow-tailed ribbons), `SHIELD` (portraits).
Property names mirror `StyleBoxFlat` (`bg_color`, `border_color`, `shadow_*`,
`set_border_width_all`, `set_corner_radius_all`) so older code keeps working.
It only redraws when its control does (commands are cached by the canvas item).

## Presets (use these)

| Need | Call | Theme variation |
|---|---|---|
| Card / panel | `MenuTheme.card_box(fill, border, alpha)` | `Card` (default `PanelContainer`) |
| Hero card with crest | set `.crest = true` | `CrestCard` |
| Card with team / element edge | `MenuTheme.accented_card(color, side)` | -- |
| Sunken well | `MenuTheme.inset_box()` | `InsetPanel` |
| Tag chip / badge | `MenuTheme.pill_box(fill, border)`, `MenuKit.badge()`, `ConquestTheme.chip()` | `Pill` |
| Ribbon / banner | `MenuTheme.ribbon_box(fill, border, notch)`, `ConquestTheme.title_ribbon(text)` | `Ribbon` |
| Unit crest | `ConquestTheme.portrait(letter, element_col, team_col, px)` / `MenuKit.crest()` | -- |
| Button plate | `MenuTheme.plate_box(fill, border, corner)` | default `Button` |
| Gold call to action | -- | `PrimaryButton` (gold tag) |
| Quiet action | -- | `GhostButton` |
| Command / menu row | `MenuTheme.row_box(wash, marker, underline)` | `MenuItem`, `HudCommand` |
| Selectable card | `MenuKit.option_card()`, `MenuKit.accent_card(btn, color)` | `OptionCard` |
| Focus ring | `MenuTheme.focus_box(corner, color)` | every focusable type |
| HUD card | `ConquestTheme.panel_box()`, `ConquestTheme.unit_card_box(unit)` | -- |
| Divider | `GroveRule` (`centered` for dialogs), `ConquestTheme.accent_rule()` | -- |
| Element swatch | `GroveGem` (`color`) | -- |
| Page corners | `GroveFlourish` (added by `MenuBackdrop`) | -- |

## Rules of the system

- **Team = edge, element = crest.** A unit card's accent stripe and crest rim carry
  the owner's team colour; the crest's field (and gems next to moves) carry the
  element. Menus without teams use the element for the edge and a gold rim.
- **Gold means focus / selection.** Focused controls get the gold notched ring with
  glow and clasps; rows get the gold ribbon wash and leaf marker; a selected card gets
  a gold frame and its crest. Disabled = sunk fill, muted text, dim ornaments.
- **Crests only on hero surfaces** (dialogs, detail cards, selected cards, banners) so
  the ornament stays special.
- **HUD layout** comes from `game/ui/hud/HudSafeArea.gd`: the top strip
  (`TOP_RESERVE`, phase banner with the objective inline) and the bottom-corner cards
  (`CORNER_CARD`, `CORNER_CARD_WIDTH`). The camera's board fit keeps the board out of
  those regions; a new persistent HUD card should fit inside them or extend them.
- A HUD panel that styles its own card after `ConquestTheme.apply_to()` should mark
  the card with `ConquestTheme.keep_style()` so the HUD-wide sweep leaves it alone.

## Floating combat text

Every HP change shows a number over the unit (`game/visuals/FloatingCombatText.gd`, a
CanvasLayer under the HUD added by `GameWorldManager`). It listens to each unit's
`UnitStats.health_changed` (the universal HP chokepoint) and pairs it with the context
event `GameEvents.combat_text_annotated(unit, info)` that every damage / heal source
emits just before changing HP (`game/combat/CombatText.gd`; pairing logic in
`game/visuals/CombatTextPairer.gd`). Unannotated changes still show a plain number;
unclaimed annotations become MISS / IMMUNE / "Blocked N" at the end of the frame.

| Case | Look |
|---|---|
| Attack damage | cream number, bold, dark outline |
| Environmental damage (tile, status, weather, hazard) | salmon number + small source tag (gem in the tile / status colour, or the weather glyph) |
| Crit | gold, larger, Cinzel "CRIT!" above, punch-in scale |
| Effectiveness | "▲ Effective" / "▼ Resisted" above the number |
| Heal | green "+N" (+ source tag for Regrowth, Rain Bath, Lifesteal...) |
| Shield | blue "Blocked N" (full soak) or a "Blocked N" source tag (partial) |
| Miss / invulnerable | grey Cinzel "MISS" / blue "IMMUNE" |

Fixed screen size (2D overlay projected from 3D), stacked upward per unit and
decluttered against neighbours, timed by battle speed / fast-forward, hidden while
the unit's floor is cut away. Presentation only (no RNG, no state): network-safe.
The BattleLog names the non-attack sources ("Vineweave took 7 from Scouring Sand
(Desert Storm)", "Barkling burned for 15"). Screenshots: `docs/screenshots/combat_text/`.

## Compendium

`menus/Compendium.gd` hosts the Unit / Tile / Map galleries and four entry browsers
(Weather, Tile Effects, Statuses, Rules) rendered from `menus/CompendiumData.gd`, which
derives every entry from the authored resources (weather rules, tile-effect numbers and
triggers, map schedules, weather-reactive units, the element chart, Elevation constants,
live key bindings) -- new content appears without code. A global search spans every
section; `[url=<section>:<id>]` cross-links jump between entries. In battle, Map Menu >
Encyclopedia opens it as an overlay (`Compendium.open_overlay`, input-blocking). The
weather chip, status chips and terrain-card chips use `CompendiumData.*_tooltip` so the
HUD words things exactly like the Compendium. Screenshots: `docs/screenshots/compendium/`.

## Screenshots

`docs/screenshots/menus/after_*` and `docs/screenshots/battle_ui/after_*` (the
`before_*` files show the previous flat navy look).
