extends Node2D


const PLATFORM_SCENES: Array[PackedScene] = [
	preload("res://Scenes/Platforms/Standard/standard_platform.tscn"),
	preload("res://Scenes/Platforms/Trampoline/trampoline_platform.tscn"),
	preload("res://Scenes/Platforms/Slingshot/slingshot_platform.tscn"),
	preload("res://Scenes/Platforms/Fragile/fragile_platform.tscn"),
]
const TUNING = preload("res://Scenes/Gameplay/game_tuning.gd")
const MAIN_MENU_SCENE := "res://Scenes/UI/MainMenu/main_menu.tscn"
const LEADERBOARD_STORE = preload("res://Scenes/UI/Leaderboard/leaderboard_store.gd")
const PAUSE_INPUT_SCRIPT = preload("res://Scenes/Gameplay/pause_input.gd")
const DEV_TOOLS_SCRIPT = preload("res://Scenes/Gameplay/dev_tools.gd")

const WORLD_WIDTH := TUNING.WORLD_WIDTH
const WORLD_CENTER_X := WORLD_WIDTH / 2.0
const PLATFORM_X_MIN := TUNING.PLATFORM_X_MIN
const PLATFORM_X_MAX := WORLD_WIDTH - PLATFORM_X_MIN
const FULL_PLATFORM_WIDTH := WORLD_WIDTH
const CHUNK_COUNT := TUNING.CHUNK_COUNT
const SPAWN_AHEAD_DISTANCE := TUNING.SPAWN_AHEAD_DISTANCE
const CLEANUP_BELOW_PLAYER := TUNING.CLEANUP_BELOW_PLAYER
const PIXELS_PER_METER := TUNING.PIXELS_PER_METER
const BIOME_HEIGHT_METERS := TUNING.BIOME_HEIGHT_METERS
const ACID_INITIAL_OFFSET := TUNING.ACID_INITIAL_OFFSET
const BIOME_PLATFORM_CLEARANCE := TUNING.BIOME_PLATFORM_CLEARANCE
const BIOME_GAP_BONUSES := TUNING.BIOME_GAP_BONUSES
const BIOME_GAP_EXTRA_BONUSES := TUNING.BIOME_GAP_EXTRA_BONUSES
const WIND_GUST_ACCELERATION := TUNING.WIND_GUST_ACCELERATION
const BIOME_NAMES: Array[String] = TUNING.BIOME_NAMES
const BIOME_TINTS: Array[Color] = TUNING.BIOME_TINTS
const BIOME_CHALLENGES: Array[String] = TUNING.BIOME_CHALLENGES

const BIOME_BACKGROUNDS: Array[Color] = [
	Color(0.32, 0.38, 0.58, 1.0),
	Color(0.10, 0.12, 0.22, 1.0),
	Color(0.12, 0.18, 0.28, 1.0),
	Color(0.06, 0.04, 0.12, 1.0),
]

enum PlatformType {
	STANDARD,
	SUPER_TRAMPOLINE,
	SLINGSHOT_RAMP,
	FRAGILE,
}

enum ChunkPattern {
	STANDARD,
	LADDER,
	ZIG_ZAG,
	SLINGSHOT_GAP,
	FRAGILE_SPRINT,
}

@onready var player: CharacterBody2D = $Player
@onready var left_wall: StaticBody2D = $LeftWall
@onready var right_wall: StaticBody2D = $RightWall
@onready var world_visuals: Node2D = $WorldVisuals

var rng := RandomNumberGenerator.new()
var start_y := 0.0
var highest_player_y := 0.0
var best_combo := 0
var highest_platform_y := 0.0
var acid_floor: Area2D
var acid_speed := TUNING.ACID_INITIAL_SPEED
var acid_acceleration := TUNING.ACID_ACCELERATION
var acid_fall_follow_distance := 0.0
var acid_time := 0.0
var acid_surface: Polygon2D
var acid_body: Polygon2D
var acid_mid: Polygon2D
var background_layer: CanvasLayer
var standard_deco: Node2D
var background_rect: ColorRect
var hint_label: Label
var hint_particles: CPUParticles2D
var hint_base_position := Vector2.ZERO
var last_tip_platform_id := -1
var wind_timer := 0.0
var wind_direction := 1.0
var wind_indicator: Label
var same_platform_landings := 0
var player_was_airborne := true
var acid_paused := false
var acid_delay_remaining := 5.0
var game_over := false
var chunk_index := 0
var platforms_since_special := 0
var game_over_label: Label
var current_biome := -1
var run_time := 0.0
var biome_tint: CanvasModulate
var biome_banner: Label
var biome_status: Label
var biome_banner_timer: Timer
var biome_ambience: Array[Dictionary] = []
var dev_tools: CanvasLayer
var debug_biome_override := -1
var pause_overlay: CanvasLayer
var game_over_overlay: CanvasLayer
var game_over_details: Label
var game_over_name_input: LineEdit
var game_over_save_status: Label
var game_over_save_button: Button
var final_run_height := 0
var final_run_combo := 0
var leaderboard_saved := false
var global_leaderboard_submitted := false
var is_paused := false


func _ready() -> void:
	rng.randomize()
	start_y = player.global_position.y
	highest_player_y = start_y
	highest_platform_y = start_y
	for existing_platform in get_tree().get_nodes_in_group("platform"):
		highest_platform_y = minf(highest_platform_y, existing_platform.global_position.y)

	create_acid_floor()
	create_background()
	create_game_over_overlay()
	create_pause_overlay()
	create_biome_ui()
	create_dev_tools()
	create_mobile_controls()
	update_wall_positions()
	update_biome()
	spawn_chunks_ahead()


func _physics_process(delta: float) -> void:
	if game_over or get_tree().paused:
		return

	run_time += delta
	var on_floor := player.is_on_floor()
	if on_floor and player_was_airborne:
		var platform: Node = player.supporting_platform
		if not is_instance_valid(platform):
			platform = player.last_landed_platform
		if is_instance_valid(platform):
			var pid := platform.get_instance_id()
			if pid == last_tip_platform_id:
				same_platform_landings += 1
			else:
				last_tip_platform_id = pid
				same_platform_landings = 1
			var show_hint := same_platform_landings >= 3
			if is_instance_valid(hint_particles):
				hint_particles.emitting = show_hint
	player_was_airborne = not on_floor
	update_wall_positions()
	update_run_record()
	update_acid_floor(delta)
	update_biome()
	apply_biome_effects(delta)
	spawn_chunks_ahead()
	remove_distant_platforms()


func _process(delta: float) -> void:
	update_biome_ambience(delta)
	var show_hint := same_platform_landings >= 3
	if is_instance_valid(hint_label):
		var target_alpha := 0.85 if show_hint else 0.0
		hint_label.modulate.a = move_toward(hint_label.modulate.a, target_alpha, delta * 2.5)
		if hint_label.modulate.a <= 0.01 and not show_hint:
			hint_label.visible = false
		else:
			hint_label.visible = true
			var t := run_time
			hint_label.position = hint_base_position + Vector2(sin(t * 1.6) * 2.0, cos(t * 1.2) * 1.5)
			hint_label.rotation_degrees = sin(t * 1.0) * 1.0


func update_run_record() -> void:
	highest_player_y = minf(highest_player_y, player.global_position.y)
	best_combo = maxi(best_combo, player.get_combo_count())


func update_wall_positions() -> void:
	left_wall.global_position.y = player.global_position.y
	right_wall.global_position.y = player.global_position.y
	world_visuals.global_position.y = player.global_position.y


func update_acid_floor(delta: float) -> void:
	acid_time += delta
	if is_instance_valid(acid_surface):
		rebuild_acid_surface(acid_time)
	if acid_paused:
		return
	if acid_delay_remaining > 0.0:
		acid_delay_remaining -= delta
		return
	acid_speed = minf(
		acid_speed + acid_acceleration * delta,
		TUNING.ACID_MAX_CHASE_SPEED
	)
	var gap := acid_floor.global_position.y - player.global_position.y
	var chase_speed := minf(
		acid_speed + maxf(0.0, gap - TUNING.ACID_FOLLOW_DISTANCE) * TUNING.ACID_CHASE_SPEED_PER_PIXEL,
		TUNING.ACID_MAX_CHASE_SPEED
	)

	var is_falling := not player.is_on_floor() and player.velocity.y > 0.0
	if is_falling:
		if acid_fall_follow_distance < TUNING.ACID_FALL_FOLLOW_MAX_DISTANCE:
			acid_fall_follow_distance = minf(
				acid_fall_follow_distance + player.velocity.y * delta,
				TUNING.ACID_FALL_FOLLOW_MAX_DISTANCE
			)
			var target_y := player.global_position.y + TUNING.ACID_FALL_FOLLOW_DISTANCE
			var follow_speed := player.velocity.y + TUNING.ACID_FALL_FOLLOW_SPEED_BONUS
			acid_floor.global_position.y = move_toward(
				acid_floor.global_position.y,
				target_y,
				follow_speed * delta
			)
	else:
		acid_fall_follow_distance = 0.0
		acid_floor.global_position.y -= chase_speed * delta


func spawn_chunks_ahead() -> void:
	var chunks_spawned := 0
	while player.global_position.y < highest_platform_y + SPAWN_AHEAD_DISTANCE and chunks_spawned < TUNING.SPAWN_MAX_CHUNKS_PER_TICK:
		spawn_chunk()
		chunks_spawned += 1


func spawn_chunk() -> void:
	var altitude := maxf(0.0, start_y - highest_platform_y)
	var altitude_progress := clampf(altitude / (BIOME_HEIGHT_METERS * PIXELS_PER_METER * TUNING.PLATFORM_GAP_ALTITUDE_PROGRESS_RANGE), 0.0, 1.0)
	var biome_index := get_active_biome(altitude / PIXELS_PER_METER)
	var min_gap := lerpf(TUNING.PLATFORM_GAP_MIN_LOW_ALTITUDE, TUNING.PLATFORM_GAP_MIN_HIGH_ALTITUDE, altitude_progress)
	var max_gap := lerpf(TUNING.PLATFORM_GAP_MAX_LOW_ALTITUDE, TUNING.PLATFORM_GAP_MAX_HIGH_ALTITUDE, altitude_progress)
	min_gap += BIOME_GAP_BONUSES[biome_index]
	max_gap += BIOME_GAP_EXTRA_BONUSES[biome_index]
	var pattern := rng.randi_range(0, ChunkPattern.size() - 1)
	for platform_index in CHUNK_COUNT:
		var vertical_gap := rng.randf_range(min_gap, max_gap)
		var next_platform_y := highest_platform_y - vertical_gap
		var previous_platform_altitude := maxf(0.0, (start_y - highest_platform_y) / PIXELS_PER_METER)
		var next_platform_altitude := maxf(0.0, (start_y - next_platform_y) / PIXELS_PER_METER)
		var previous_platform_biome := get_biome_index(previous_platform_altitude)
		var next_platform_biome := get_biome_index(next_platform_altitude)
		var is_biome_transition := next_platform_biome > previous_platform_biome
		if is_biome_transition:
			next_platform_y = start_y - next_platform_biome * BIOME_HEIGHT_METERS * PIXELS_PER_METER
		highest_platform_y = next_platform_y

		var platform_type := PlatformType.STANDARD
		if not is_biome_transition:
			platform_type = choose_platform_type(pattern, platform_index, altitude_progress, biome_index)
		if platform_index == CHUNK_COUNT - 1 and platform_type == PlatformType.FRAGILE:
			platform_type = PlatformType.STANDARD
			platforms_since_special += 1
		var platform_x := WORLD_CENTER_X if is_biome_transition else choose_platform_x(pattern, platform_index, altitude_progress)
		var wall_attach_side := 0
		if not is_biome_transition and platform_type == PlatformType.STANDARD and rng.randf() < lerpf(
			TUNING.PLATFORM_WALL_ATTACH_CHANCE_LOW,
			TUNING.PLATFORM_WALL_ATTACH_CHANCE_HIGH,
			altitude_progress
		):
			wall_attach_side = 1 if rng.randf() < TUNING.PLATFORM_WALL_ATTACH_SIDE_CHANCE else 2
		var platform := PLATFORM_SCENES[platform_type].instantiate() as Node2D
		platform.set("platform_type", platform_type)
		platform.set("wall_attach_side", wall_attach_side)
		platform.set("world_width", WORLD_WIDTH)
		if is_biome_transition:
			platform.name = "BiomePlatform_%d" % next_platform_biome
			platform.set("min_standard_width", FULL_PLATFORM_WIDTH)
			platform.set("max_standard_width", FULL_PLATFORM_WIDTH)
			remove_platforms_near_transition(next_platform_y)
		if platform_type == PlatformType.SLINGSHOT_RAMP:
			var ramp_on_left := rng.randf() < TUNING.PLATFORM_RAMP_SIDE_CHANCE
			platform_x = PLATFORM_X_MIN if ramp_on_left else PLATFORM_X_MAX
			var ramp_angle := rng.randf_range(TUNING.PLATFORM_RAMP_MIN_ANGLE, TUNING.PLATFORM_RAMP_MAX_ANGLE)
			if ramp_on_left:
				platform.set("slingshot_rotation_degrees", ramp_angle)
			else:
				platform.set("slingshot_rotation_degrees", -ramp_angle)
			platform.set("slingshot_mirror", not ramp_on_left)
		platform.position = Vector2(platform_x, highest_platform_y)
		platform.add_to_group("platform")
		add_child(platform)
	chunk_index += 1


func remove_platforms_near_transition(transition_y: float) -> void:
	for existing_platform in get_tree().get_nodes_in_group("platform"):
		if absf(existing_platform.global_position.y - transition_y) < BIOME_PLATFORM_CLEARANCE:
			existing_platform.queue_free()



func choose_platform_x(pattern: int, platform_index: int, altitude_progress: float) -> float:
	var horizontal_offset := lerpf(TUNING.PLATFORM_HORIZONTAL_OFFSET_LOW, TUNING.PLATFORM_HORIZONTAL_OFFSET_HIGH, altitude_progress)
	var wall_spawn_chance := lerpf(TUNING.PLATFORM_WALL_SPAWN_CHANCE_LOW, TUNING.PLATFORM_WALL_SPAWN_CHANCE_HIGH, altitude_progress)
	if rng.randf() < wall_spawn_chance:
		return PLATFORM_X_MIN if rng.randf() < TUNING.PLATFORM_WALL_SPAWN_SIDE_CHANCE else PLATFORM_X_MAX

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


func choose_platform_type(pattern: int, platform_index: int, altitude_progress: float, biome_index: int) -> PlatformType:
	platforms_since_special += 1
	var standard_streak := roundi(lerpf(TUNING.BIOME_STANDARD_STREAK_LOW_ALTITUDE, TUNING.BIOME_STANDARD_STREAK_HIGH_ALTITUDE, altitude_progress))
	if platforms_since_special <= standard_streak:
		return PlatformType.STANDARD

	var preferred_type := -1
	if pattern == ChunkPattern.SLINGSHOT_GAP and platform_index == TUNING.PLATFORM_CHUNK_PREFERRED_SLOT:
		preferred_type = PlatformType.SLINGSHOT_RAMP
	elif pattern == ChunkPattern.FRAGILE_SPRINT and platform_index == TUNING.PLATFORM_CHUNK_PREFERRED_SLOT:
		preferred_type = PlatformType.FRAGILE
	elif pattern == ChunkPattern.LADDER and platform_index == TUNING.PLATFORM_CHUNK_PREFERRED_SLOT:
		preferred_type = PlatformType.SUPER_TRAMPOLINE

	var special_chance := lerpf(TUNING.PLATFORM_SPECIAL_CHANCE_LOW_ALTITUDE, TUNING.PLATFORM_SPECIAL_CHANCE_HIGH_ALTITUDE, altitude_progress)
	match biome_index:
		1:
			special_chance += TUNING.BIOME_POWER_UP_CHANCE_WINDY
		2:
			special_chance += TUNING.BIOME_POWER_UP_CHANCE_FROSTED
		3:
			special_chance += TUNING.BIOME_POWER_UP_CHANCE_ABYSS
	if preferred_type != -1:
		special_chance = minf(special_chance * TUNING.BIOME_PREFERRED_SPECIAL_CHANCE_MULTIPLIER, TUNING.BIOME_PREFERRED_SPECIAL_CHANCE_CAP)
	special_chance = minf(special_chance, TUNING.BIOME_SPECIAL_CHANCE_CAP)
	if rng.randf() >= special_chance:
		return PlatformType.STANDARD

	platforms_since_special = 0
	if rng.randf() < TUNING.BIOME_SPECIAL_POWER_UP_SHARE * altitude_progress:
		if biome_index == 1 or (biome_index == 2 and rng.randf() < TUNING.BIOME_POWER_UP_TYPE_SPLIT):
			return PlatformType.SLINGSHOT_RAMP
		return PlatformType.SUPER_TRAMPOLINE

	var type_roll := rng.randf()
	if preferred_type != -1 and type_roll < TUNING.PLATFORM_PREFERRED_SPECIAL_SELECTION_CHANCE:
		return preferred_type as PlatformType
	match biome_index:
		1:
			if type_roll < TUNING.PLATFORM_WINDY_TRAMPOLINE_WEIGHT:
				return PlatformType.SUPER_TRAMPOLINE
			if type_roll < TUNING.PLATFORM_WINDY_SLINGSHOT_WEIGHT:
				return PlatformType.SLINGSHOT_RAMP
			if type_roll < TUNING.PLATFORM_WINDY_FRAGILE_WEIGHT:
				return PlatformType.FRAGILE
		2:
			if type_roll < TUNING.PLATFORM_FROST_TRAMPOLINE_WEIGHT:
				return PlatformType.SUPER_TRAMPOLINE
			if type_roll < TUNING.PLATFORM_FROST_SLINGSHOT_WEIGHT:
				return PlatformType.SLINGSHOT_RAMP
			if type_roll < TUNING.PLATFORM_FROST_FRAGILE_WEIGHT:
				return PlatformType.FRAGILE
		3:
			if type_roll < TUNING.PLATFORM_ABYSS_TRAMPOLINE_WEIGHT:
				return PlatformType.SUPER_TRAMPOLINE
			if type_roll < TUNING.PLATFORM_ABYSS_SLINGSHOT_WEIGHT:
				return PlatformType.SLINGSHOT_RAMP
			if type_roll < TUNING.PLATFORM_ABYSS_FRAGILE_WEIGHT:
				return PlatformType.FRAGILE
		_:
			if type_roll < TUNING.PLATFORM_STANDARD_TRAMPOLINE_WEIGHT:
				return PlatformType.SUPER_TRAMPOLINE
			if type_roll < TUNING.PLATFORM_STANDARD_SLINGSHOT_WEIGHT:
				return PlatformType.SLINGSHOT_RAMP
			if type_roll < TUNING.PLATFORM_STANDARD_FRAGILE_WEIGHT:
				return PlatformType.FRAGILE
	platforms_since_special += 1
	return PlatformType.STANDARD


func get_biome_index(altitude_meters: float) -> int:
	return mini(floori(altitude_meters / BIOME_HEIGHT_METERS), BIOME_NAMES.size() - 1)


func get_active_biome(altitude_meters: float) -> int:
	if debug_biome_override >= 0:
		return debug_biome_override
	return get_biome_index(altitude_meters)


func update_biome() -> void:
	var altitude_meters := maxf(0.0, (start_y - player.global_position.y) / PIXELS_PER_METER)
	var next_biome := get_active_biome(altitude_meters)
	if next_biome == current_biome:
		return

	current_biome = next_biome
	var gravity_multiplier := 1.0
	var drag_multiplier := 1.0
	var control_multiplier := 1.0
	if current_biome == 2:
		drag_multiplier = TUNING.FROSTED_DRAG_MULTIPLIER
		control_multiplier = TUNING.FROSTED_CONTROL_MULTIPLIER
	elif current_biome == 3:
		gravity_multiplier = TUNING.ABYSS_GRAVITY_MULTIPLIER
		control_multiplier = TUNING.ABYSS_CONTROL_MULTIPLIER
	player.set_biome_modifiers(gravity_multiplier, drag_multiplier, control_multiplier)
	if current_biome == 1:
		wind_timer = 3.0
		wind_direction = 1.0
	set_biome_ambience(current_biome)
	biome_status.add_theme_color_override("font_color", BIOME_TINTS[current_biome].lightened(0.18))
	biome_banner.text = "%s  |  %s  |  %d m" % [
		BIOME_NAMES[current_biome],
		BIOME_CHALLENGES[current_biome],
		int(altitude_meters),
	]
	biome_status.text = "ZONE: %s - %s" % [BIOME_NAMES[current_biome], BIOME_CHALLENGES[current_biome]]
	biome_banner.visible = true
	if wind_indicator != null:
		wind_indicator.visible = (current_biome == 1)
	biome_banner_timer.start()


func apply_biome_effects(delta: float) -> void:
	if current_biome == 1:
		wind_timer -= delta
		if wind_timer <= 0.0:
			wind_direction = -wind_direction
			wind_timer = 3.0
		if not player.is_on_floor():
			player.apply_wind(wind_direction * WIND_GUST_ACCELERATION * 0.5, delta)
		if wind_indicator != null:
			wind_indicator.text = "WIND: " + ("->" if wind_direction > 0 else "<-")
	biome_tint.color = biome_tint.color.lerp(BIOME_TINTS[current_biome], 1.0 - exp(-TUNING.BIOME_TINT_TRANSITION_SPEED * delta))
	if background_rect != null:
		background_rect.color = background_rect.color.lerp(BIOME_BACKGROUNDS[current_biome], 1.0 - exp(-TUNING.BIOME_TINT_TRANSITION_SPEED * delta))
	if hint_label != null:
		var target_hint_color := BIOME_BACKGROUNDS[current_biome].lightened(0.35)
		target_hint_color.a = 0.85 if same_platform_landings >= 3 else hint_label.modulate.a
		hint_label.modulate = hint_label.modulate.lerp(target_hint_color, 1.0 - exp(-TUNING.BIOME_TINT_TRANSITION_SPEED * delta))


func create_biome_ambience(container: CanvasLayer) -> void:
	var viewport_size := get_viewport_rect().size
	for index in TUNING.WIND_STREAK_COUNT:
		var streak := Line2D.new()
		streak.width = 1.5
		streak.default_color = Color(0.72, 0.88, 1.0, 0.3)
		streak.points = PackedVector2Array([
			Vector2.ZERO,
			Vector2(rng.randf_range(TUNING.WIND_STREAK_MIN_LENGTH, TUNING.WIND_STREAK_MAX_LENGTH), 0.0),
		])
		container.add_child(streak)
		biome_ambience.append({
			"node": streak,
			"biome": 1,
			"style": 0,
			"speed": rng.randf_range(TUNING.WIND_STREAK_MIN_SPEED, TUNING.WIND_STREAK_MAX_SPEED),
			"phase": rng.randf_range(0.0, TAU),
		})

	for index in TUNING.SNOW_PARTICLE_COUNT:
		var snowflake := Polygon2D.new()
		var size := rng.randf_range(TUNING.SNOW_PARTICLE_MIN_SIZE, TUNING.SNOW_PARTICLE_MAX_SIZE)
		snowflake.polygon = PackedVector2Array([
			Vector2(0.0, -size),
			Vector2(size * TUNING.SNOW_PARTICLE_SHAPE_RATIO, 0.0),
			Vector2(0.0, size),
			Vector2(-size * TUNING.SNOW_PARTICLE_SHAPE_RATIO, 0.0),
		])
		snowflake.color = Color(0.84, 0.95, 1.0, rng.randf_range(TUNING.SNOW_PARTICLE_ALPHA_MIN, TUNING.SNOW_PARTICLE_ALPHA_MAX))
		container.add_child(snowflake)
		biome_ambience.append({
			"node": snowflake,
			"biome": 2,
			"style": 1,
			"speed": rng.randf_range(TUNING.SNOW_PARTICLE_MIN_SPEED, TUNING.SNOW_PARTICLE_MAX_SPEED),
			"phase": rng.randf_range(0.0, TAU),
		})

	for index in TUNING.ABYSS_MOTE_COUNT:
		var ember := Polygon2D.new()
		var size := rng.randf_range(TUNING.ABYSS_MOTE_MIN_SIZE, TUNING.ABYSS_MOTE_MAX_SIZE)
		ember.polygon = PackedVector2Array([
			Vector2(0.0, -size),
			Vector2(size * TUNING.ABYSS_MOTE_SHAPE_RATIO, 0.0),
			Vector2(0.0, size),
			Vector2(-size * TUNING.ABYSS_MOTE_SHAPE_RATIO, 0.0),
		])
		ember.color = Color(0.81, 0.64, 1.0, rng.randf_range(TUNING.ABYSS_MOTE_ALPHA_MIN, TUNING.ABYSS_MOTE_ALPHA_MAX))
		container.add_child(ember)
		biome_ambience.append({
			"node": ember,
			"biome": 3,
			"style": 2,
			"speed": rng.randf_range(TUNING.ABYSS_MOTE_MIN_SPEED, TUNING.ABYSS_MOTE_MAX_SPEED),
			"phase": rng.randf_range(0.0, TAU),
		})

	# Forest leaves (biome 0)
	for index in 16:
		var leaf := Polygon2D.new()
		var size := rng.randf_range(2.0, 4.5)
		leaf.polygon = PackedVector2Array([
			Vector2(0.0, -size),
			Vector2(size * 0.7, 0.0),
			Vector2(0.0, size * 0.6),
			Vector2(-size * 0.7, 0.0),
		])
		leaf.color = Color(rng.randf_range(0.2, 0.45), rng.randf_range(0.55, 0.85), rng.randf_range(0.15, 0.4), rng.randf_range(0.4, 0.75))
		container.add_child(leaf)
		biome_ambience.append({
			"node": leaf,
			"biome": 0,
			"style": 3,
			"speed": rng.randf_range(40.0, 90.0),
			"phase": rng.randf_range(0.0, TAU),
		})

	# Fireflies (biome 0)
	for index in 12:
		var fly := Polygon2D.new()
		var size := rng.randf_range(1.2, 2.4)
		var pts := PackedVector2Array()
		for i in 6:
			var a := TAU * float(i) / 6.0
			pts.append(Vector2(cos(a), sin(a)) * size)
		fly.polygon = pts
		fly.color = Color(0.85, 1.0, 0.55, rng.randf_range(0.5, 0.9))
		container.add_child(fly)
		biome_ambience.append({
			"node": fly,
			"biome": 0,
			"style": 4,
			"speed": rng.randf_range(12.0, 30.0),
			"phase": rng.randf_range(0.0, TAU),
		})

	# Dust motes (biome 1)
	for index in 14:
		var dust := Polygon2D.new()
		var size := rng.randf_range(0.8, 1.8)
		dust.polygon = PackedVector2Array([
			Vector2(-size, -size), Vector2(size, -size),
			Vector2(size, size), Vector2(-size, size),
		])
		dust.color = Color(0.85, 0.92, 1.0, rng.randf_range(0.2, 0.45))
		container.add_child(dust)
		biome_ambience.append({
			"node": dust,
			"biome": 1,
			"style": 5,
			"speed": rng.randf_range(60.0, 140.0),
			"phase": rng.randf_range(0.0, TAU),
		})

	# Ice sparkles (biome 2)
	for index in 12:
		var spark := Polygon2D.new()
		var size := rng.randf_range(1.0, 2.2)
		spark.polygon = PackedVector2Array([
			Vector2(0.0, -size), Vector2(size * 0.35, 0.0),
			Vector2(0.0, size), Vector2(-size * 0.35, 0.0),
		])
		spark.color = Color(0.9, 0.95, 1.0, rng.randf_range(0.4, 0.85))
		container.add_child(spark)
		biome_ambience.append({
			"node": spark,
			"biome": 2,
			"style": 6,
			"speed": rng.randf_range(0.0, 0.0),
			"phase": rng.randf_range(0.0, TAU),
		})

	# Purple wisps (biome 3)
	for index in 10:
		var wisp := Polygon2D.new()
		var size := rng.randf_range(1.5, 3.0)
		wisp.polygon = PackedVector2Array([
			Vector2(0.0, -size * 1.6), Vector2(size * 0.5, 0.0),
			Vector2(0.0, size * 1.6), Vector2(-size * 0.5, 0.0),
		])
		wisp.color = Color(0.75, 0.55, 1.0, rng.randf_range(0.25, 0.55))
		container.add_child(wisp)
		biome_ambience.append({
			"node": wisp,
			"biome": 3,
			"style": 7,
			"speed": rng.randf_range(20.0, 45.0),
			"phase": rng.randf_range(0.0, TAU),
		})


	for ambience in biome_ambience:
		var node: Node2D = ambience["node"]
		node.position = Vector2(rng.randf_range(0.0, viewport_size.x), rng.randf_range(0.0, viewport_size.y))
		node.visible = false


func set_biome_ambience(biome_index: int) -> void:
	for ambience in biome_ambience:
		var node: Node2D = ambience["node"]
		node.visible = int(ambience["biome"]) == biome_index
	if standard_deco != null:
		standard_deco.visible = (biome_index == 0)


func update_biome_ambience(delta: float) -> void:
	if biome_ambience.is_empty():
		return
	var viewport_size := get_viewport_rect().size
	for ambience in biome_ambience:
		var node: Node2D = ambience["node"]
		if not node.visible:
			continue
		var ambience_position := node.position
		var speed := float(ambience["speed"])
		var phase := float(ambience["phase"])
		match int(ambience["style"]):
			0:
				ambience_position.x += speed * wind_direction * delta
				ambience_position.y += sin(run_time * TUNING.WIND_STREAK_DRIFT_FREQUENCY + phase) * TUNING.WIND_STREAK_DRIFT_AMPLITUDE * delta
				if ambience_position.x < -TUNING.BIOME_AMBIENCE_VIEWPORT_MARGIN:
					ambience_position.x = viewport_size.x + TUNING.BIOME_AMBIENCE_VIEWPORT_MARGIN
				elif ambience_position.x > viewport_size.x + TUNING.BIOME_AMBIENCE_VIEWPORT_MARGIN:
					ambience_position.x = -TUNING.BIOME_AMBIENCE_VIEWPORT_MARGIN
			1:
				ambience_position.y += speed * delta
				ambience_position.x += sin(run_time * TUNING.SNOW_PARTICLE_SWAY_FREQUENCY + phase) * TUNING.SNOW_PARTICLE_SWAY_AMPLITUDE * delta
				if ambience_position.y > viewport_size.y + TUNING.BIOME_PARTICLE_VERTICAL_MARGIN:
					ambience_position.y = -TUNING.BIOME_PARTICLE_VERTICAL_MARGIN
			2:
				ambience_position.y -= speed * delta
				ambience_position.x += sin(run_time * TUNING.ABYSS_MOTE_SWAY_FREQUENCY + phase) * TUNING.ABYSS_MOTE_SWAY_AMPLITUDE * delta
				if ambience_position.y < -TUNING.BIOME_PARTICLE_VERTICAL_MARGIN:
					ambience_position.y = viewport_size.y + TUNING.BIOME_PARTICLE_VERTICAL_MARGIN
			3:
				ambience_position.y += speed * delta
				ambience_position.x += sin(run_time * 1.1 + phase) * 14.0 * delta
				if ambience_position.y > viewport_size.y + TUNING.BIOME_PARTICLE_VERTICAL_MARGIN:
					ambience_position.y = -TUNING.BIOME_PARTICLE_VERTICAL_MARGIN
					ambience_position.x = rng.randf_range(0.0, viewport_size.x)
			4:
				ambience_position.x += sin(run_time * 0.7 + phase) * speed * delta * 0.5
				ambience_position.y += cos(run_time * 0.9 + phase) * speed * delta * 0.5
				if ambience_position.x < -10.0:
					ambience_position.x = viewport_size.x + 10.0
				elif ambience_position.x > viewport_size.x + 10.0:
					ambience_position.x = -10.0
				if ambience_position.y < -10.0:
					ambience_position.y = viewport_size.y + 10.0
				elif ambience_position.y > viewport_size.y + 10.0:
					ambience_position.y = -10.0
				var twinkle: float = 0.5 + 0.5 * sin(run_time * 2.0 + phase)
				node.modulate.a = twinkle
			5:
				ambience_position.x += speed * delta
				ambience_position.y += sin(run_time * 1.3 + phase) * 8.0 * delta
				if ambience_position.x > viewport_size.x + TUNING.BIOME_AMBIENCE_VIEWPORT_MARGIN:
					ambience_position.x = -TUNING.BIOME_AMBIENCE_VIEWPORT_MARGIN
					ambience_position.y = rng.randf_range(0.0, viewport_size.y)
			6:
				var pulse: float = 0.4 + 0.6 * abs(sin(run_time * 2.5 + phase))
				node.modulate.a = pulse
				ambience_position.x += sin(run_time * 0.6 + phase) * 6.0 * delta
				ambience_position.y += cos(run_time * 0.8 + phase) * 6.0 * delta
				if ambience_position.x < -10.0 or ambience_position.x > viewport_size.x + 10.0:
					ambience_position.x = rng.randf_range(0.0, viewport_size.x)
				if ambience_position.y < -10.0 or ambience_position.y > viewport_size.y + 10.0:
					ambience_position.y = rng.randf_range(0.0, viewport_size.y)
			7:
				ambience_position.y -= speed * delta
				ambience_position.x += sin(run_time * 1.0 + phase) * 12.0 * delta
				if ambience_position.y < -TUNING.BIOME_PARTICLE_VERTICAL_MARGIN:
					ambience_position.y = viewport_size.y + TUNING.BIOME_PARTICLE_VERTICAL_MARGIN
					ambience_position.x = rng.randf_range(0.0, viewport_size.x)
		node.position = ambience_position


func create_background() -> void:
	background_layer = CanvasLayer.new()
	background_layer.name = "BackgroundLayer"
	background_layer.layer = -2
	add_child(background_layer)

	var viewport_size := get_viewport_rect().size
	background_rect = ColorRect.new()
	background_rect.name = "BackgroundRect"
	background_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_rect.color = BIOME_BACKGROUNDS[0]
	background_layer.add_child(background_rect)

	# Standard biome: sky + mountain + trees backdrop.
	standard_deco = Node2D.new()
	standard_deco.name = "StandardDeco"
	background_layer.add_child(standard_deco)

	# Foggy, hazy backdrop.
	for layer_index in 4:
		var fog := ColorRect.new()
		fog.position = Vector2.ZERO
		fog.size = viewport_size
		var t := float(layer_index) / 3.0
		fog.color = Color(
			lerpf(0.42, 0.58, t),
			lerpf(0.48, 0.62, t),
			lerpf(0.62, 0.78, t),
			0.14 + t * 0.1
		)
		standard_deco.add_child(fog)

	# Soft sun glow.
	var sun := Polygon2D.new()
	var sun_radius := minf(viewport_size.x, viewport_size.y) * 0.18
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)) * sun_radius)
	sun.polygon = pts
	sun.position = Vector2(viewport_size.x * 0.72, viewport_size.y * 0.22)
	sun.color = Color(0.95, 0.85, 0.55, 0.12)
	standard_deco.add_child(sun)

	standard_deco.visible = (current_biome == 0)
	# Background hint text.
	hint_label = Label.new()
	hint_label.text = "you can always wall bounce!"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.position = viewport_size * 0.5 - Vector2(300, 18)
	hint_label.size = Vector2(600, 40)
	hint_label.add_theme_font_size_override("font_size", 22)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	hint_label.modulate = BIOME_BACKGROUNDS[0].lightened(0.35)
	hint_label.modulate.a = 0.85
	hint_base_position = hint_label.position
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(hint_label)
	hint_label.visible = false

	# Particles to draw attention to the tip.
	hint_particles = CPUParticles2D.new()
	hint_particles.emitting = false
	hint_particles.amount = 24
	hint_particles.lifetime = 1.2
	hint_particles.explosiveness = 0.0
	hint_particles.randomness = 0.8
	hint_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	hint_particles.emission_rect_extents = Vector2(260, 12)
	hint_particles.position = viewport_size * 0.5
	hint_particles.direction = Vector2(0, -1)
	hint_particles.spread = 60.0
	hint_particles.initial_velocity_min = 10.0
	hint_particles.initial_velocity_max = 40.0
	hint_particles.gravity = Vector2(0, -20)
	hint_particles.scale_amount_min = 1.0
	hint_particles.scale_amount_max = 2.5
	hint_particles.color = Color(1.0, 0.95, 0.7, 0.8)
	background_layer.add_child(hint_particles)
	hint_particles.visible = false



	# Subtle horizon gradient overlay for depth.
	var horizon := ColorRect.new()
	horizon.name = "HorizonGlow"
	horizon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	horizon.color = Color(1.0, 1.0, 1.0, 0.04)
	background_layer.add_child(horizon)


func create_biome_ui() -> void:
	biome_tint = CanvasModulate.new()
	biome_tint.name = "BiomeTint"
	add_child(biome_tint)

	var biome_layer := CanvasLayer.new()
	biome_layer.name = "BiomeUI"
	biome_layer.layer = 1
	add_child(biome_layer)
	create_biome_ambience(biome_layer)

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

	biome_status = Label.new()
	biome_status.position = Vector2(18.0, 132.0)
	biome_status.add_theme_font_size_override("font_size", 13)
	biome_status.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.9))
	biome_status.add_theme_color_override("font_shadow_color", Color(0.04, 0.06, 0.12, 0.9))
	biome_status.add_theme_constant_override("shadow_offset_x", 1)
	biome_status.add_theme_constant_override("shadow_offset_y", 1)
	wind_indicator = Label.new()
	wind_indicator.position = Vector2(18.0, 150.0)
	wind_indicator.add_theme_font_size_override("font_size", 13)
	wind_indicator.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.9))
	wind_indicator.add_theme_color_override("font_shadow_color", Color(0.04, 0.06, 0.12, 0.9))
	wind_indicator.add_theme_constant_override("shadow_offset_x", 1)
	wind_indicator.add_theme_constant_override("shadow_offset_y", 1)
	wind_indicator.visible = false
	biome_layer.add_child(wind_indicator)
	biome_layer.add_child(biome_status)

	biome_banner_timer = Timer.new()
	biome_banner_timer.one_shot = true
	biome_banner_timer.wait_time = TUNING.BIOME_BANNER_DURATION
	biome_banner_timer.timeout.connect(func(): biome_banner.visible = false)
	add_child(biome_banner_timer)


func create_dev_tools() -> void:
	dev_tools = DEV_TOOLS_SCRIPT.new() as CanvasLayer
	add_child(dev_tools)
	dev_tools.call("setup", self)
	dev_tools.connect("platform_requested", dev_spawn_platform)
	dev_tools.connect("biome_requested", dev_set_biome)
	dev_tools.connect("reset_biome_requested", dev_reset_biome)
	dev_tools.connect("launch_requested", dev_test_jump)
	dev_tools.connect("wall_bounce_requested", dev_test_wall_bounce)
	dev_tools.connect("combo_requested", dev_add_combo)
	dev_tools.connect("stored_bonus_requested", dev_grant_stored_bonus)
	dev_tools.connect("end_run_requested", dev_end_run)
	dev_tools.connect("acid_pause_requested", dev_toggle_acid_pause)


func dev_spawn_platform(platform_type: int) -> void:
	if game_over or platform_type < PlatformType.STANDARD or platform_type > PlatformType.FRAGILE:
		return
	var platform := PLATFORM_SCENES[platform_type].instantiate() as Node2D
	platform.set("platform_type", platform_type)
	platform.set("world_width", WORLD_WIDTH)
	var spawn_x := clampf(player.global_position.x, PLATFORM_X_MIN, PLATFORM_X_MAX)
	if platform_type == PlatformType.SLINGSHOT_RAMP:
		var ramp_on_left := spawn_x <= WORLD_CENTER_X
		spawn_x = PLATFORM_X_MIN if ramp_on_left else PLATFORM_X_MAX
		if ramp_on_left:
			platform.set("slingshot_rotation_degrees", TUNING.PLATFORM_RAMP_DEFAULT_ANGLE)
		else:
			platform.set("slingshot_rotation_degrees", -TUNING.PLATFORM_RAMP_DEFAULT_ANGLE)
		platform.set("slingshot_mirror", not ramp_on_left)
	platform.position = Vector2(spawn_x, player.global_position.y - TUNING.DEV_TEST_PLATFORM_VERTICAL_OFFSET)
	add_child(platform)


func dev_set_biome(biome_index: int) -> void:
	if game_over or biome_index < 0 or biome_index >= BIOME_NAMES.size():
		return
	debug_biome_override = biome_index
	update_biome()


func dev_reset_biome() -> void:
	debug_biome_override = -1
	update_biome()


func dev_test_jump() -> void:
	if game_over:
		return
	player.velocity.y = -TUNING.DEV_TEST_JUMP_SPEED
	player.can_wall_bounce = true
	player.increment_combo()


func dev_test_wall_bounce() -> void:
	if game_over:
		return
	var bounce_direction := 1.0 if player.global_position.x < WORLD_CENTER_X else -1.0
	player.velocity = Vector2(bounce_direction * TUNING.DEV_TEST_WALL_BOUNCE_SPEED, -TUNING.DEV_TEST_WALL_BOUNCE_VERTICAL_SPEED)
	player.wall_bounce_direction = bounce_direction
	player.wall_bounce_jump_bonus = TUNING.DEV_TEST_STORED_JUMP_BONUS
	player.stored_jump_bonus_time_remaining = player.get_stored_jump_bonus_timeout()
	player.can_wall_bounce = false
	player.increment_combo()
	player.award_perfect_wall_bounce()


func dev_add_combo() -> void:
	if not game_over:
		player.increment_combo(TUNING.DEV_TEST_COMBO_POINTS)


func dev_grant_stored_bonus() -> void:
	if game_over:
		return
	player.wall_bounce_jump_bonus = TUNING.DEV_TEST_STORED_JUMP_BONUS
	player.stored_jump_bonus_time_remaining = player.get_stored_jump_bonus_timeout()



func dev_toggle_acid_pause() -> void:
	acid_paused = not acid_paused


func dev_end_run() -> void:
	if game_over:
		return
	update_run_record()
	end_run()


func remove_distant_platforms() -> void:
	for platform in get_tree().get_nodes_in_group("platform"):
		if platform.global_position.y > player.global_position.y + CLEANUP_BELOW_PLAYER:
			platform.queue_free()


func create_acid_floor() -> void:
	acid_floor = Area2D.new()
	acid_floor.name = "AcidFloor"
	acid_floor.collision_layer = 0
	acid_floor.collision_mask = 2
	acid_floor.global_position = Vector2(WORLD_CENTER_X, player.global_position.y + ACID_INITIAL_OFFSET)
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

	acid_body = Polygon2D.new()
	acid_body.polygon = PackedVector2Array([
		Vector2(-(WORLD_WIDTH + 24.0) / 2.0, -4.0),
		Vector2((WORLD_WIDTH + 24.0) / 2.0, -4.0),
		Vector2((WORLD_WIDTH + 24.0) / 2.0, 2000.0),
		Vector2(-(WORLD_WIDTH + 24.0) / 2.0, 2000.0),
	])
	acid_body.color = Color(0.12, 0.42, 0.12, 0.95)
	acid_visuals.add_child(acid_body)

	acid_mid = Polygon2D.new()
	acid_mid.color = Color(0.2, 0.62, 0.16, 0.9)
	acid_visuals.add_child(acid_mid)

	acid_surface = Polygon2D.new()
	acid_surface.color = Color(0.32, 0.85, 0.22, 0.95)
	rebuild_acid_surface(0.0)
	acid_visuals.add_child(acid_surface)

	# Bubbles for flowing-water texture.
	var bubbles := CPUParticles2D.new()
	bubbles.name = "AcidBubbles"
	bubbles.amount = 36
	bubbles.lifetime = 2.2
	bubbles.speed_scale = 1.0
	bubbles.explosiveness = 0.0
	bubbles.randomness = 1.0
	bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	bubbles.emission_rect_extents = Vector2((WORLD_WIDTH + 24.0) / 2.0, 2.0)
	bubbles.direction = Vector2(0.0, -1.0)
	bubbles.spread = 18.0
	bubbles.initial_velocity_min = 6.0
	bubbles.initial_velocity_max = 22.0
	bubbles.gravity = Vector2(0.0, -4.0)
	bubbles.scale_amount_min = 0.6
	bubbles.scale_amount_max = 1.8
	bubbles.color = Color(0.75, 1.0, 0.45, 0.55)
	bubbles.position = Vector2(0.0, -14.0)
	acid_visuals.add_child(bubbles)


func rebuild_acid_surface(time: float) -> void:
	var half := (WORLD_WIDTH + 24.0) / 2.0
	var segments := 20
	var top_points := PackedVector2Array()
	var bottom_y := -4.0
	for i in range(segments + 1):
		var x := -half + (half * 2.0) * float(i) / float(segments)
		var wave := sin(time * 2.3 + float(i) * 0.7) * 3.0 + sin(time * 1.1 + float(i) * 1.3) * 1.5
		top_points.append(Vector2(x, -12.0 + wave))
	var poly := PackedVector2Array()
	for p in top_points:
		poly.append(p)
	for i in range(segments, -1, -1):
		var x := -half + (half * 2.0) * float(i) / float(segments)
		poly.append(Vector2(x, bottom_y))
	acid_surface.polygon = poly

	# Mid layer: slower, deeper wave for texture.
	var mid_top := PackedVector2Array()
	for i in range(segments + 1):
		var x := -half + (half * 2.0) * float(i) / float(segments)
		var wave := sin(time * 1.4 + float(i) * 0.9 + 1.7) * 2.0 + sin(time * 0.7 + float(i) * 1.6) * 1.0
		mid_top.append(Vector2(x, -8.0 + wave))
	var mid_poly := PackedVector2Array()
	for p in mid_top:
		mid_poly.append(p)
	for i in range(segments, -1, -1):
		var x := -half + (half * 2.0) * float(i) / float(segments)
		mid_poly.append(Vector2(x, bottom_y + 6.0))
	acid_mid.polygon = mid_poly

func create_game_over_overlay() -> void:
	var elements := create_dialog("GAME OVER", "The acid caught up.")
	game_over_overlay = elements["layer"]
	game_over_details = elements["details"]
	var content: VBoxContainer = elements["content"]
	var name_label := Label.new()
	name_label.text = "PLAYER NAME"
	name_label.add_theme_font_size_override("font_size", 13)
	content.add_child(name_label)
	content.move_child(name_label, 2)

	game_over_name_input = LineEdit.new()
	game_over_name_input.max_length = 16
	game_over_name_input.placeholder_text = "Enter a name"
	game_over_name_input.text = LEADERBOARD_STORE.get_default_player_name()
	game_over_name_input.text_submitted.connect(func(_text: String): save_game_over_score())
	content.add_child(game_over_name_input)
	content.move_child(game_over_name_input, 3)

	game_over_save_status = Label.new()
	game_over_save_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_save_status.add_theme_font_size_override("font_size", 13)
	content.add_child(game_over_save_status)
	content.move_child(game_over_save_status, 4)

	game_over_save_button = add_dialog_button(elements["buttons"], "SAVE SCORE", save_game_over_score, true)
	add_dialog_button(elements["buttons"], "RETRY", retry_after_game_over)
	add_dialog_button(elements["buttons"], "MAIN MENU", return_to_menu_after_game_over)
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
	dimmer.color = Color(0.06, 0.04, 0.10, 0.78)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.05, 0.12, 1.0)
	panel_style.border_color = Color(0.85, 0.8, 0.95)
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
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0))
	buttons.add_child(title)

	var details := Label.new()
	details.text = detail_text
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_font_size_override("font_size", 17)
	buttons.add_child(details)

	var button_list := VBoxContainer.new()
	button_list.add_theme_constant_override("separation", 8)
	buttons.add_child(button_list)
	return {"layer": layer, "details": details, "buttons": button_list, "content": buttons}


func add_dialog_button(container: VBoxContainer, text: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 42)
	button.text = text
	if primary:
		button.add_theme_stylebox_override("normal", dialog_button_style(Color(0.9, 0.85, 1.0)))
		button.add_theme_color_override("font_color", Color(0.08, 0.05, 0.12))
	else:
		button.add_theme_stylebox_override("normal", dialog_button_style(Color(0.18, 0.12, 0.25)))
	button.pressed.connect(action)
	container.add_child(button)
	return button

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


func save_game_over_score() -> bool:
	var player_name := game_over_name_input.text.strip_edges()
	if player_name.is_empty():
		game_over_save_status.text = "Enter a name to save your score."
		game_over_name_input.grab_focus()
		return false

	var run_record: Dictionary = LEADERBOARD_STORE.submit_run(final_run_height, final_run_combo, player_name)
	if not bool(run_record.get("saved", false)):
		game_over_save_status.text = "Could not save the leaderboard. Try again."
		return false

	leaderboard_saved = true
	game_over_name_input.editable = false
	game_over_save_button.disabled = true
	game_over_save_status.text = "Score saved for %s." % player_name

	if not global_leaderboard_submitted and LEADERBOARD_STORE.is_global_available():
		global_leaderboard_submitted = true
		call_deferred("_submit_global_score_async", final_run_height, final_run_combo, player_name)

	return true


func _submit_global_score_async(height_meters: int, combo_count: int, player_name: String) -> void:
	await LEADERBOARD_STORE.submit_global_run(height_meters, combo_count, player_name)


func retry_after_game_over() -> void:
	if not leaderboard_saved and not save_game_over_score():
		return
	retry_run()


func return_to_menu_after_game_over() -> void:
	if not leaderboard_saved and not save_game_over_score():
		return
	return_to_menu()


func toggle_pause() -> void:
	if game_over:
		return
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_overlay.visible = is_paused


func _on_acid_body_entered(body: Node2D) -> void:
	if body != player or game_over:
		return

	update_run_record()
	end_run()


func end_run() -> void:
	if game_over:
		return

	game_over = true
	if is_instance_valid(dev_tools):
		dev_tools.visible = false
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	final_run_height = maxi(0, roundi((start_y - highest_player_y) / PIXELS_PER_METER))
	final_run_combo = best_combo
	var final_score: int = LEADERBOARD_STORE.calculate_score(final_run_height, final_run_combo)
	game_over_details.text = "The acid caught up.\nALTITUDE  %d m\nSCORE  %d\nBEST COMBO  x%d" % [
		final_run_height,
		final_score,
		final_run_combo,
	]
	game_over_overlay.visible = true
func create_mobile_controls() -> void:
	var viewport_size := get_viewport_rect().size
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var alpha := 0.35
	var make_button := func(text: String, pos: Vector2, size: Vector2, on_down: Callable, on_up: Callable) -> Button:
		var btn := Button.new()
		btn.text = text
		btn.position = pos
		btn.size = size
		btn.modulate.a = alpha
		btn.button_down.connect(on_down)
		btn.button_up.connect(on_up)
		root.add_child(btn)
		return btn

	var btn_size := Vector2(96, 96)
	var bottom := viewport_size.y - btn_size.y - 24.0
	make_button.call("<", Vector2(24.0, bottom), btn_size,
		Callable(self, "_mobile_press_left"), Callable(self, "_mobile_release_left"))
	make_button.call(">", Vector2(132.0, bottom), btn_size,
		Callable(self, "_mobile_press_right"), Callable(self, "_mobile_release_right"))
	make_button.call("JUMP", Vector2(viewport_size.x - 120.0, bottom), btn_size,
		Callable(self, "_mobile_press_jump"), Callable(self, "_mobile_release_jump"))
	make_button.call("DROP", Vector2(viewport_size.x - 228.0, bottom), btn_size,
		Callable(self, "_mobile_press_drop"), Callable(self, "_mobile_release_drop"))

	var pause_btn := Button.new()
	pause_btn.text = "||"
	pause_btn.position = Vector2(viewport_size.x - 72.0, 24.0)
	pause_btn.size = Vector2(48.0, 48.0)
	pause_btn.modulate.a = alpha
	pause_btn.pressed.connect(toggle_pause)
	root.add_child(pause_btn)


func _mobile_press_left() -> void:
	_mobile_send_action("ui_left", true)

func _mobile_release_left() -> void:
	_mobile_send_action("ui_left", false)

func _mobile_press_right() -> void:
	_mobile_send_action("ui_right", true)

func _mobile_release_right() -> void:
	_mobile_send_action("ui_right", false)

func _mobile_press_jump() -> void:
	_mobile_send_action("ui_accept", true)

func _mobile_release_jump() -> void:
	_mobile_send_action("ui_accept", false)

func _mobile_press_drop() -> void:
	_mobile_send_action("ui_down", true)

func _mobile_release_drop() -> void:
	_mobile_send_action("ui_down", false)

func _mobile_send_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
