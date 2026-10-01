extends Node2D


const PLATFORM_SCENE: PackedScene = preload("res://Scenes/platform.tscn")
const MAIN_MENU_SCENE := "res://Scenes/MainMenu.tscn"
const LEADERBOARD_STORE = preload("res://Scenes/local_leaderboard.gd")
const PAUSE_INPUT_SCRIPT = preload("res://Scenes/pause_input.gd")

const WORLD_WIDTH := 700.0
const WORLD_CENTER_X := WORLD_WIDTH / 2.0
const PLATFORM_X_MIN := 150.0
const PLATFORM_X_MAX := WORLD_WIDTH - PLATFORM_X_MIN
const FULL_PLATFORM_WIDTH := WORLD_WIDTH - 32.0
const STICKY_FOLLOWUP_GAP := 45.0
const CHUNK_COUNT := 3
const SPAWN_AHEAD_DISTANCE := 750.0
const CLEANUP_BELOW_PLAYER := 1200.0
const PIXELS_PER_METER := 10.0
const BIOME_HEIGHT_METERS := 500.0

const BIOME_NAMES: Array[String] = [
	"STANDARD TOWER",
	"GALE-FORCE WINDS",
	"FROSTED PEAKS",
	"CRUSHING ABYSS",
]
const BIOME_TINTS: Array[Color] = [
	Color.WHITE,
	Color(0.92, 0.98, 1.0),
	Color(0.82, 0.94, 1.0),
	Color(0.82, 0.84, 0.92),
]

enum PlatformType {
	STANDARD,
	SUPER_TRAMPOLINE,
	SLINGSHOT_RAMP,
	FRAGILE,
	STICKY_DOUGH,
}

enum ChunkPattern {
	STANDARD,
	LADDER,
	ZIG_ZAG,
	SLINGSHOT_GAP,
	FRAGILE_SPRINT,
}

@onready var player: CharacterBody2D = $CharacterBody2D

var rng := RandomNumberGenerator.new()
var start_y := 0.0
var highest_platform_y := 0.0
var acid_floor: Area2D
var acid_speed := 18.0
var acid_acceleration := 0.25
var game_over := false
var chunk_index := 0
var platforms_since_special := 0
var game_over_label: Label
var current_biome := -1
var run_time := 0.0
var biome_tint: CanvasModulate
var biome_banner: Label
var biome_banner_timer: Timer
var pause_overlay: CanvasLayer
var game_over_overlay: CanvasLayer
var game_over_details: Label
var is_paused := false


func _ready() -> void:
	rng.randomize()
	start_y = player.global_position.y
	highest_platform_y = start_y
	for existing_platform in get_tree().get_nodes_in_group("platform"):
		highest_platform_y = minf(highest_platform_y, existing_platform.global_position.y)

	create_acid_floor()
	create_game_over_overlay()
	create_pause_overlay()
	create_biome_ui()
	update_biome()
	spawn_chunks_ahead()


func _physics_process(delta: float) -> void:
	if game_over or get_tree().paused:
		return

	run_time += delta
	update_biome()
	apply_biome_effects(delta)
	acid_speed += acid_acceleration * delta
	acid_floor.global_position.y -= acid_speed * delta
	spawn_chunks_ahead()
	remove_distant_platforms()


func spawn_chunks_ahead() -> void:
	var chunks_spawned := 0
	while player.global_position.y < highest_platform_y + SPAWN_AHEAD_DISTANCE and chunks_spawned < 8:
		spawn_chunk()
		chunks_spawned += 1


func spawn_chunk() -> void:
	var altitude := maxf(0.0, start_y - highest_platform_y)
	var altitude_progress := clampf(altitude / (BIOME_HEIGHT_METERS * PIXELS_PER_METER * 3.0), 0.0, 1.0)
	var biome_index := get_biome_index(altitude / PIXELS_PER_METER)
	var min_gap := lerpf(90.0, 115.0, altitude_progress)
	var max_gap := lerpf(110.0, 135.0, altitude_progress)
	if biome_index == 2:
		min_gap += 5.0
		max_gap += 10.0
	var pattern := rng.randi_range(0, ChunkPattern.size() - 1)
	var previous_platform_type := PlatformType.STANDARD
	var previous_platform_x := WORLD_CENTER_X

	for platform_index in CHUNK_COUNT:
		var vertical_gap := rng.randf_range(min_gap, max_gap)
		if previous_platform_type == PlatformType.STICKY_DOUGH:
			vertical_gap = STICKY_FOLLOWUP_GAP
		highest_platform_y -= vertical_gap
		var platform_type := choose_platform_type(pattern, platform_index, altitude_progress, biome_index)
		if platform_index == CHUNK_COUNT - 1 and platform_type == PlatformType.STICKY_DOUGH:
			platform_type = PlatformType.STANDARD
			platforms_since_special += 1
		var platform_x := choose_platform_x(pattern, platform_index, altitude_progress)
		var wall_attach_side := 0
		if platform_type == PlatformType.STANDARD and rng.randf() < lerpf(0.2, 0.35, altitude_progress):
			wall_attach_side = 1 if rng.randf() < 0.5 else 2
		if previous_platform_type == PlatformType.STICKY_DOUGH:
			platform_x = clampf(previous_platform_x + rng.randf_range(-100.0, 100.0), PLATFORM_X_MIN, PLATFORM_X_MAX)
		var platform := PLATFORM_SCENE.instantiate() as Node2D
		platform.set("platform_type", platform_type)
		platform.set("wall_attach_side", wall_attach_side)
		platform.set("world_width", WORLD_WIDTH)
		if platform_type == PlatformType.SLINGSHOT_RAMP:
			platform.set("slingshot_rotation_degrees", rng.randf_range(-26.0, -12.0))
		platform.position = Vector2(platform_x, highest_platform_y)
		platform.add_to_group("platform")
		add_child(platform)
		previous_platform_type = platform_type
		previous_platform_x = platform_x

	chunk_index += 1



func choose_platform_x(pattern: int, platform_index: int, altitude_progress: float) -> float:
	var horizontal_offset := lerpf(80.0, 170.0, altitude_progress)
	var wall_spawn_chance := lerpf(0.2, 0.35, altitude_progress)
	if rng.randf() < wall_spawn_chance:
		return PLATFORM_X_MIN if rng.randf() < 0.5 else PLATFORM_X_MAX

	match pattern:
		ChunkPattern.LADDER:
			return WORLD_CENTER_X - horizontal_offset if platform_index % 2 == 0 else WORLD_CENTER_X + horizontal_offset
		ChunkPattern.ZIG_ZAG:
			return WORLD_CENTER_X - horizontal_offset if (platform_index + chunk_index) % 2 == 0 else WORLD_CENTER_X + horizontal_offset
		ChunkPattern.SLINGSHOT_GAP:
			return WORLD_CENTER_X + horizontal_offset if platform_index % 2 == 0 else WORLD_CENTER_X - horizontal_offset
		ChunkPattern.FRAGILE_SPRINT:
			return [WORLD_CENTER_X - horizontal_offset, WORLD_CENTER_X, WORLD_CENTER_X + horizontal_offset][platform_index]
		_:
			return clampf(rng.randf_range(WORLD_CENTER_X - horizontal_offset, WORLD_CENTER_X + horizontal_offset), PLATFORM_X_MIN, PLATFORM_X_MAX)


func choose_platform_type(pattern: int, platform_index: int, altitude_progress: float, biome_index: int) -> int:
	platforms_since_special += 1
	var standard_streak := roundi(lerpf(8.0, 3.0, altitude_progress))
	if platforms_since_special <= standard_streak:
		return PlatformType.STANDARD

	var preferred_type := -1
	if pattern == ChunkPattern.SLINGSHOT_GAP and platform_index == 1:
		preferred_type = PlatformType.SLINGSHOT_RAMP
	elif pattern == ChunkPattern.FRAGILE_SPRINT and platform_index == 1:
		preferred_type = PlatformType.FRAGILE
	elif pattern == ChunkPattern.LADDER and platform_index == 1:
		preferred_type = PlatformType.SUPER_TRAMPOLINE

	var special_chance := lerpf(0.0, 0.36, altitude_progress)
	match biome_index:
		1:
			special_chance += 0.04
		2:
			special_chance += 0.02
		3:
			special_chance += 0.06
	if preferred_type != -1:
		special_chance = minf(special_chance * 1.5, 0.5)
	special_chance = minf(special_chance, 0.5)
	if rng.randf() >= special_chance:
		return PlatformType.STANDARD

	platforms_since_special = 0
	var type_roll := rng.randf()
	if preferred_type != -1 and type_roll < 0.55:
		return preferred_type
	match biome_index:
		1:
			if type_roll < 0.22:
				return PlatformType.SUPER_TRAMPOLINE
			if type_roll < 0.72:
				return PlatformType.SLINGSHOT_RAMP
			if type_roll < 0.86:
				return PlatformType.FRAGILE
		2:
			if type_roll < 0.2:
				return PlatformType.SUPER_TRAMPOLINE
			if type_roll < 0.36:
				return PlatformType.SLINGSHOT_RAMP
			if type_roll < 0.78:
				return PlatformType.FRAGILE
		3:
			if type_roll < 0.58:
				return PlatformType.SUPER_TRAMPOLINE
			if type_roll < 0.76:
				return PlatformType.SLINGSHOT_RAMP
			if type_roll < 0.88:
				return PlatformType.FRAGILE
		_:
			if type_roll < 0.32:
				return PlatformType.SUPER_TRAMPOLINE
			if type_roll < 0.58:
				return PlatformType.SLINGSHOT_RAMP
			if type_roll < 0.8:
				return PlatformType.FRAGILE
	return PlatformType.STICKY_DOUGH


func get_biome_index(altitude_meters: float) -> int:
	return mini(floori(altitude_meters / BIOME_HEIGHT_METERS), BIOME_NAMES.size() - 1)


func update_biome() -> void:
	var altitude_meters := maxf(0.0, (start_y - player.global_position.y) / PIXELS_PER_METER)
	var next_biome := get_biome_index(altitude_meters)
	if next_biome == current_biome:
		return

	current_biome = next_biome
	var gravity_multiplier := 1.0
	var drag_multiplier := 1.0
	if current_biome == 2:
		drag_multiplier = 0.25
	elif current_biome == 3:
		gravity_multiplier = 3.5
	player.set_biome_modifiers(gravity_multiplier, drag_multiplier)
	if current_biome > 0:
		spawn_biome_transition_platform()
	biome_banner.text = "%s  |  %d m" % [BIOME_NAMES[current_biome], int(altitude_meters)]
	biome_banner.visible = true
	biome_banner_timer.start()


func spawn_biome_transition_platform() -> void:
	var platform := PLATFORM_SCENE.instantiate() as Node2D
	platform.name = "BiomePlatform_%d" % current_biome
	platform.set("platform_type", PlatformType.STANDARD)
	platform.set("world_width", WORLD_WIDTH)
	platform.set("min_standard_width", FULL_PLATFORM_WIDTH)
	platform.set("max_standard_width", FULL_PLATFORM_WIDTH)
	highest_platform_y -= rng.randf_range(90.0, 110.0)
	platform.position = Vector2(WORLD_CENTER_X, highest_platform_y)
	platform.add_to_group("platform")
	add_child(platform)


func apply_biome_effects(delta: float) -> void:
	if current_biome == 1 and not player.is_on_floor():
		player.apply_wind(sin(run_time * 1.8) * 360.0, delta)
	biome_tint.color = biome_tint.color.lerp(BIOME_TINTS[current_biome], 1.0 - exp(-2.5 * delta))


func create_biome_ui() -> void:
	biome_tint = CanvasModulate.new()
	biome_tint.name = "BiomeTint"
	add_child(biome_tint)

	var biome_layer := CanvasLayer.new()
	biome_layer.name = "BiomeUI"
	biome_layer.layer = 1
	add_child(biome_layer)

	biome_banner = Label.new()
	biome_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	biome_banner.offset_left = 20.0
	biome_banner.offset_top = 58.0
	biome_banner.offset_right = -20.0
	biome_banner.offset_bottom = 102.0
	biome_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	biome_banner.add_theme_font_size_override("font_size", 24)
	biome_banner.add_theme_color_override("font_color", Color.WHITE)
	biome_banner.add_theme_color_override("font_shadow_color", Color(0.05, 0.08, 0.12, 0.8))
	biome_banner.add_theme_constant_override("shadow_offset_x", 2)
	biome_banner.add_theme_constant_override("shadow_offset_y", 2)
	biome_banner.visible = false
	biome_layer.add_child(biome_banner)

	biome_banner_timer = Timer.new()
	biome_banner_timer.one_shot = true
	biome_banner_timer.wait_time = 2.5
	biome_banner_timer.timeout.connect(func(): biome_banner.visible = false)
	add_child(biome_banner_timer)


func remove_distant_platforms() -> void:
	for platform in get_tree().get_nodes_in_group("platform"):
		if platform.global_position.y > player.global_position.y + CLEANUP_BELOW_PLAYER:
			platform.queue_free()


func create_acid_floor() -> void:
	acid_floor = Area2D.new()
	acid_floor.name = "AcidFloor"
	acid_floor.collision_layer = 0
	acid_floor.collision_mask = 2
	acid_floor.global_position = Vector2(WORLD_CENTER_X, player.global_position.y + 380.0)
	acid_floor.body_entered.connect(_on_acid_body_entered)
	add_child(acid_floor)

	var collision_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(WORLD_WIDTH + 24.0, 24.0)
	collision_shape.shape = rectangle
	acid_floor.add_child(collision_shape)

	var acid_visuals := Node2D.new()
	acid_visuals.name = "AcidVisuals"
	acid_visuals.z_index = -1
	acid_floor.add_child(acid_visuals)

	var acid_visual := Polygon2D.new()
	acid_visual.polygon = PackedVector2Array([
		Vector2(-(WORLD_WIDTH + 24.0) / 2.0, -12.0),
		Vector2((WORLD_WIDTH + 24.0) / 2.0, -12.0),
		Vector2((WORLD_WIDTH + 24.0) / 2.0, 12.0),
		Vector2(-(WORLD_WIDTH + 24.0) / 2.0, 12.0),
	])
	acid_visual.color = Color(0.55, 0.88, 0.2, 0.9)
	acid_visuals.add_child(acid_visual)


func create_game_over_overlay() -> void:
	var elements := create_dialog("ASCENT ENDED", "The acid caught up.")
	game_over_overlay = elements["layer"]
	game_over_details = elements["details"]
	add_dialog_button(elements["buttons"], "RETRY", retry_run, true)
	add_dialog_button(elements["buttons"], "MAIN MENU", return_to_menu)
	game_over_overlay.visible = false


func create_pause_overlay() -> void:
	var pause_input := Node.new()
	pause_input.set_script(PAUSE_INPUT_SCRIPT)
	add_child(pause_input)

	var elements := create_dialog("PAUSED", "Take a breather.")
	pause_overlay = elements["layer"]
	add_dialog_button(elements["buttons"], "RESUME", resume_run, true)
	add_dialog_button(elements["buttons"], "RETRY", retry_run)
	add_dialog_button(elements["buttons"], "MAIN MENU", return_to_menu)
	pause_overlay.visible = false


func create_dialog(title_text: String, detail_text: String) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 5
	add_child(layer)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0.015, 0.04, 0.05, 0.78)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.12, 0.14, 1.0)
	panel_style.border_color = Color(0.38, 0.82, 0.68)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 28
	panel_style.content_margin_right = 28
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	panel.add_child(buttons)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.46, 0.92, 0.75))
	buttons.add_child(title)

	var details := Label.new()
	details.text = detail_text
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_font_size_override("font_size", 17)
	buttons.add_child(details)

	var button_list := VBoxContainer.new()
	button_list.add_theme_constant_override("separation", 8)
	buttons.add_child(button_list)
	return {"layer": layer, "details": details, "buttons": button_list}


func add_dialog_button(container: VBoxContainer, text: String, action: Callable, primary := false) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	if primary:
		button.add_theme_stylebox_override("normal", dialog_button_style(Color(0.46, 0.92, 0.75)))
		button.add_theme_color_override("font_color", Color(0.04, 0.12, 0.13))
	else:
		button.add_theme_stylebox_override("normal", dialog_button_style(Color(0.12, 0.28, 0.29)))
	button.pressed.connect(action)
	container.add_child(button)


func dialog_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style


func resume_run() -> void:
	get_tree().paused = false
	is_paused = false
	pause_overlay.visible = false


func retry_run() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func toggle_pause() -> void:
	if game_over:
		return
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_overlay.visible = is_paused


func _on_acid_body_entered(body: Node2D) -> void:
	if body != player or game_over:
		return

	game_over = true
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	var height_meters := maxi(0, roundi((start_y - player.global_position.y) / PIXELS_PER_METER))
	var combo: int = player.get_combo_count()
	var run_record := LEADERBOARD_STORE.submit_run(height_meters, combo)
	game_over_details.text = "ALTITUDE  %d m\nSCORE  %d\nCOMBO  x%d" % [height_meters, int(run_record["score"]), combo]
	game_over_overlay.visible = true
