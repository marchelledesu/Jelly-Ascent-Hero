extends CanvasLayer

const LEADERBOARD_STORE = preload("res://Scenes/UI/Leaderboard/leaderboard_store.gd")
const TUNING = preload("res://Scenes/Gameplay/game_tuning.gd")

@export var player_path: NodePath

@onready var player: CharacterBody2D = get_node(player_path)
@onready var readout: Label = $Readout

var spawn_height := 0.0
var combo_timer_bar: ProgressBar
var bonus_timer_bar: ProgressBar
var timer_panel: PanelContainer
const PIXELS_PER_METER := TUNING.PIXELS_PER_METER


func _ready() -> void:
	spawn_height = player.global_position.y
	create_timer_panel()


func _process(_delta: float) -> void:
	var height_meters := maxi(0, roundi((spawn_height - player.global_position.y) / PIXELS_PER_METER))
	var combo := 0
	if player.has_method("get_combo_count"):
		combo = player.get_combo_count()
	var score := LEADERBOARD_STORE.calculate_score(height_meters, combo)
	readout.text = "ALTITUDE %d m     SCORE %d     COMBO x%d\nA/D or arrows: move    S/down: fast drop    P/Esc: pause" % [height_meters, score, combo]
	update_timer_bar(combo_timer_bar, "get_combo_time_remaining", "get_combo_timeout")
	update_timer_bar(bonus_timer_bar, "get_stored_jump_bonus_time_remaining", "get_stored_jump_bonus_timeout")


func create_timer_panel() -> void:
	timer_panel = PanelContainer.new()
	timer_panel.name = "MomentumTimers"
	timer_panel.position = Vector2(18.0, 78.0)
	timer_panel.custom_minimum_size = Vector2(230.0, 0.0)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.07, 0.075, 0.72)
	panel_style.border_color = Color(0.85, 0.8, 0.95, 0.35)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_bottom = 6.0
	timer_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(timer_panel)

	var timer_rows := VBoxContainer.new()
	timer_rows.add_theme_constant_override("separation", 4)
	timer_panel.add_child(timer_rows)

	combo_timer_bar = create_timer_row(timer_rows, "Combo", Color(0.85, 0.8, 0.95))
	bonus_timer_bar = create_timer_row(timer_rows, "Stored jump", Color(0.95, 0.9, 1.0))


func create_timer_row(container: VBoxContainer, label_text: String, bar_color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	container.add_child(row)

	var sprite_slot := TextureRect.new()
	sprite_slot.name = label_text.replace(" ", "") + "SpriteSlot"
	sprite_slot.custom_minimum_size = Vector2(16.0, 16.0)
	sprite_slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite_slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(sprite_slot)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 78.0
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.95, 0.9))
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(105.0, 10.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.18, 0.12, 0.25, 0.8)
	background.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = bar_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return bar


func update_timer_bar(bar: ProgressBar, remaining_method: String, duration_method: String) -> void:
	var remaining := float(player.call(remaining_method))
	var duration := maxf(0.01, float(player.call(duration_method)))
	bar.value = clampf(remaining / duration, 0.0, 1.0)
