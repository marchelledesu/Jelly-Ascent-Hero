extends CanvasLayer

@export var player_path: NodePath

@onready var player: CharacterBody2D = get_node(player_path)
@onready var readout: Label = $Readout

var spawn_height := 0.0
const PIXELS_PER_METER := 10.0


func _ready() -> void:
	spawn_height = player.global_position.y


func _process(_delta: float) -> void:
	var height_meters := maxi(0, roundi((spawn_height - player.global_position.y) / PIXELS_PER_METER))
	var combo := 0
	if player.has_method("get_combo_count"):
		combo = player.get_combo_count()
	var score := height_meters * 100 + combo * 25
	readout.text = "ALTITUDE %d m     SCORE %d     COMBO x%d\nA/D or arrows: move    S/down: fast drop    P/Esc: pause" % [height_meters, score, combo]
