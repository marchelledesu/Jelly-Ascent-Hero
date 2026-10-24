extends TileMapLayer


const WALL_TILE_SIZE := Vector2i(64, 128)
const FIRST_WALL_ROW := -80
const LAST_WALL_ROW := 80
const VARIANTS_PER_BIOME := 4
const WALL_ATLAS: Texture2D = preload("res://Assets/biome_wall_atlas.png")

@export_range(0, 1) var wall_side := 0

var current_biome := -1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale.x = -1.0 if wall_side == 0 else 1.0
	tile_set = create_wall_tileset()
	set_biome(0)


func create_wall_tileset() -> TileSet:
	var wall_tileset := TileSet.new()
	wall_tileset.tile_size = WALL_TILE_SIZE
	var atlas := TileSetAtlasSource.new()
	atlas.texture = WALL_ATLAS
	atlas.texture_region_size = WALL_TILE_SIZE
	for row in VARIANTS_PER_BIOME * 4:
		atlas.create_tile(Vector2i(0, row))
	wall_tileset.add_source(atlas, 0)
	return wall_tileset


func set_biome(biome_index: int) -> void:
	if current_biome == biome_index:
		return
	current_biome = biome_index
	clear()
	for row in range(FIRST_WALL_ROW, LAST_WALL_ROW + 1):
		var variant := posmod(row + wall_side * 2, VARIANTS_PER_BIOME)
		var atlas_row := current_biome * VARIANTS_PER_BIOME + variant
		set_cell(Vector2i(0, row), 0, Vector2i(0, atlas_row))
