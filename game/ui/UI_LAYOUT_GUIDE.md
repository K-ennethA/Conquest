# Battle HUD Layout Guide

The in-battle HUD targets a **1280x720** window and is **container-driven** — panels
are placed by `VBoxContainer` / `HBoxContainer` / anchors, not hard-coded pixel rects.
The root is `game/ui/layout/GameUILayout.tscn` (script `UILayoutManager.gd`), instanced
under the `UI` CanvasLayer of `GameWorld.tscn`. It has a 15px outer margin.

## Structure

```
GameUILayout (Control, full-rect, mouse-ignore)
└─ MarginContainer (15px)
   └─ MainContainer (VBox)
      ├─ TopBar (HBox)
      │  ├─ CenterTopContainer: TurnQueue (Speed First) OR TurnIndicator chip (Traditional)
      │  └─ SettingsButton (gear, top-right — built in code)
      └─ MiddleArea (HBox, expands)
         ├─ LeftSidebar (VBox, 260px): BattleLog chip, then UnitInfoPanel
         ├─ GameArea    (spacer over the 3D board)
         └─ RightSidebar (VBox): UnitActionsPanel (contextual command menu)
```

### Left-column budget (1280x720)

The left column is a real VBox stack with **one** flexible region, and the claims add up
to the column height exactly:

| Row | px | Notes |
|---|---:|---|
| top of the column | 81 | 15 HUD margin + 56 TopBar + 10 separation |
| BattleLog chip | 30 | owns the column's first row |
| separation | 10 | `UILayoutManager.COLUMN_SEPARATION` |
| **UnitInfoPanel** | **423** | budget; measured fixed-content floor is 358 — only the ability / effect lists flex |
| terrain reserve | 176 | `UnitInfoPanel.BOTTOM_RESERVE` = 16 margin + `TerrainInfoPanel.MAX_HEIGHT` 152 + 8 gap |

`UILayoutManager._rebudget_left_column()` re-splits this whenever the card shows/hides or
the window resizes. An expanded log (158px) does not fit beside the card's floor, so while
a unit is selected the log renders its chip; with nothing selected it gets the whole
column. Two rules keep the card honest: it is **never** given less height than
`fixed_content_height()` (a BoxContainer under its minimum overlaps its own children), and
nothing inside it may declare a minimum wider than the column (`discipline_label`).

Panels mounted in code by `UILayoutManager` (after theming):
- **BattleLog** — first child of the LeftSidebar, collapsible scrolling combat log. Also
  auto-collapses while a move is being aimed (the CombatForecastPanel shares that corner).
- **TurnTransition** — full-screen turn-change wipe, own high CanvasLayer.
- **ActionAnnouncer** — upper-centre "X used Y!" banner, own CanvasLayer. Parks itself
  below the *live* TopBar (56px Traditional chip / 180px Speed First queue), never at a
  fixed offset.
- **SettingsPanel** — full-screen options overlay (opened by the gear button).

Mounted separately by `GameWorldManager` on the `UI` CanvasLayer:
- **TerrainInfoPanel** — bottom-left hover card for the tile under the cursor.
- **CombatForecastPanel** — top-left damage forecast, shown only while aiming a move.

## Theme

Everything pulls the warm-amber Fire-Emblem look from `ConquestTheme` (built in code,
applied via `ConquestTheme.apply_to(root)`):
- **Command-button roles** — a button's weight is set with
  `set_meta("style_role", "secondary" | "destructive")`; absent/unknown = **primary**.
  `ConquestTheme.apply_button_role()` maps each to a warm-palette variant
  (primary = bright amber, secondary = muted amber-grey, destructive = ember red-brown),
  each with normal/hover/pressed/disabled + readable font colours.
- **Type scale** — `FONT_TITLE 18 / FONT_HEADER 15 / FONT_BODY 13 / FONT_CAPTION 11`,
  applied as the theme's default Label/Button font sizes so panels rarely need
  per-widget overrides (any explicit override still wins).
- **Element colours** — `ConquestTheme.element_color(name)` (used e.g. by the
  UnitInfoPanel monogram plate and status/ability chips).

## Feedback

`UIFeedback.attach_sfx(root)` wires themed buttons' `pressed` to the shared
`sfx_ui_click` at low volume (idempotent; TurnQueue excluded). `UILayoutManager`
calls it once at `_ready`; panels that rebuild buttons dynamically can call it again.

## Debug keys (GameWorldManager)

- **I** — print whether the command surfaces resolve at their real paths.
- **L** — dump `UILayoutManager.get_layout_info()`.
