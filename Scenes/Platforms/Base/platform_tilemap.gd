extends TileMapLayer


@export var atlas_texture: Texture2D

const TILE_SIZE := 32
const ATLAS_TILE_COUNT := 4


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func build_tiles(tile_count: int) -> void:
	if atlas_texture == null:
		push_error("Platform tilemap is missing its atlas texture.")
		return

	var atlas_columns := atlas_texture.get_width() / TILE_SIZE
	var atlas_rows := atlas_texture.get_height() / TILE_SIZE
	if atlas_columns < ATLAS_TILE_COUNT or atlas_rows < 1:
		push_error("Platform atlas must contain at least four 32x32 tiles.")
		return

	var platform_tileset := TileSet.new()
	platform_tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = atlas_texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for index in ATLAS_TILE_COUNT:
		atlas.create_tile(Vector2i(index, 0))
	platform_tileset.add_source(atlas, 0)
	tile_set = platform_tileset

	clear()
	var variation_offset := randi_range(0, ATLAS_TILE_COUNT - 1)
	for index in tile_count:
		var tile_index: int
		if tile_count == 1 or index == 0 or index == tile_count - 1:
			tile_index = 0
		else:
			tile_index = (index + variation_offset) % ATLAS_TILE_COUNT
			if tile_index == 0:
				tile_index = 3
		set_cell(Vector2i(index, 0), 0, Vector2i(tile_index, 0))
