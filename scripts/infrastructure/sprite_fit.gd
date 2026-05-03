extends Object
## SpriteFit — stateless utility for scaling Sprite2D to fit a given tile width
## while preserving aspect ratio.
##
## Pattern: same as GameLogger (infrastructure/game_logger.gd) — no class_name
## (avoids registry collisions, see CLAUDE.md traps), no autoload, used via
## explicit preload by consumers:
##
##   const SpriteFit = preload("res://scripts/infrastructure/sprite_fit.gd")
##   SpriteFit.fit_to_tile_width(body)
##
## Tile width default is 128 — matches hex_terrain.tres tile_size (CLAUDE.md
## hard rule #7). Consumers that have a HexGrid in scope can pass a runtime
## value via the second arg if the tileset ever changes (don't, but the API
## supports it for free).
##
## Spec 050.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const TILE_WIDTH_DEFAULT := 128


## Sets sprite.scale so the sprite's displayed width == tile_width * base_scale,
## preserving aspect ratio. base_scale lets callers stack a per-overlay
## multiplier (e.g. ObjectsOverlay keeps its export var sprite_scale as a
## tuning knob layered on top of tile-fit).
##
## No-op (with warn) on:
##   - null sprite
##   - null texture
##   - texture with zero width (malformed image / not yet imported)
##
## Idempotent: calling twice in a row yields the same scale.
static func fit_to_tile_width(sprite: Sprite2D, tile_width: int = TILE_WIDTH_DEFAULT, base_scale: float = 1.0) -> void:
	if sprite == null:
		return
	if sprite.texture == null:
		return
	var w: int = sprite.texture.get_width()
	if w <= 0:
		GameLogger.warn("SpriteFit", "texture has zero width on sprite '%s' — scale unchanged" % sprite.name)
		return
	var s: float = base_scale * float(tile_width) / float(w)
	sprite.scale = Vector2(s, s)
