class_name HudSafeArea
extends RefCounted

## Where the battle HUD sits, in the project's base units (1280x720 logical viewport,
## canvas_items stretch -- the same space [method Viewport.get_visible_rect] and
## [method Camera3D.unproject_position] report). ONE source shared by the HUD panels
## that size themselves to it and by [CameraController]'s initial board fit, which
## keeps the whole board -- including the HP bars floating over the back row -- out
## from under the HUD.
##
##   +--------------------------------------------------------------+
##   | log chip        [====  PHASE BANNER  (+ objective)  ====]   ⚙ |  <- TOP_RESERVE
##   |                                                              |
##   |                        board frame                           |
##   |                                                              |
##   | [terrain card]                                 [unit card]   |  <- CORNER_CARD
##   +--------------------------------------------------------------+

## Height of the top strip: HUD margin (15) + phase banner (~62, objective inline)
## + the crest / shadow overhang and a little air.
const TOP_RESERVE := 92.0
## Air kept at the bottom / sides of the frame.
const EDGE_RESERVE := 14.0
## The persistent bottom-corner cards (terrain card bottom-left, unit hover card
## bottom-right) -- width x height of the region the board should stay out of. The
## cards are designed to stay within this (see TerrainInfoPanel / UnitHoverPanel).
const CORNER_CARD := Vector2(292.0, 180.0)
## Width of those corner cards themselves (the reserve adds the HUD margin + shadow).
const CORNER_CARD_WIDTH := 270.0


## The rect the board should fill on a viewport of [param vp] logical size.
static func board_frame(vp: Vector2) -> Rect2:
	return Rect2(Vector2(EDGE_RESERVE, TOP_RESERVE),
		Vector2(maxf(1.0, vp.x - EDGE_RESERVE * 2.0), maxf(1.0, vp.y - TOP_RESERVE - EDGE_RESERVE)))


## Regions inside [method board_frame] the board must not enter (the corner cards).
## Skipped on a narrow viewport where they would leave no room.
static func board_avoid(vp: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if vp.x < CORNER_CARD.x * 3.0 or vp.y < CORNER_CARD.y * 3.0:
		return out
	out.append(Rect2(Vector2(0.0, vp.y - CORNER_CARD.y), CORNER_CARD))
	out.append(Rect2(Vector2(vp.x - CORNER_CARD.x, vp.y - CORNER_CARD.y), CORNER_CARD))
	return out
