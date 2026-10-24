extends CharacterBody2D

# Phase 1 implementation aligned to the Jelly Ascent GDD.
# Core goals:
# - build lateral momentum rather than constant left/right speed
# - wall collisions convert horizontal speed into upward rebound
# - fast drop increases gravity for sharp impact timing

const TUNING = preload("res://Scenes/Gameplay/game_tuning.gd")
const MAX_HORIZONTAL_SPEED := TUNING.PLAYER_MAX_HORIZONTAL_SPEED
const HORIZONTAL_ACCELERATION := TUNING.PLAYER_HORIZONTAL_ACCELERATION
const AIR_CONTROL_MULTIPLIER := TUNING.PLAYER_AIR_CONTROL_MULTIPLIER
const AIR_COUNTERSTEER_MULTIPLIER := TUNING.PLAYER_AIR_COUNTERSTEER_MULTIPLIER
const HORIZONTAL_DRAG := TUNING.PLAYER_HORIZONTAL_DRAG
const BASE_GRAVITY := TUNING.PLAYER_BASE_GRAVITY
const FAST_DROP_GRAVITY := TUNING.PLAYER_FAST_DROP_GRAVITY
const FLOOR_JUMP_VELOCITY := TUNING.PLAYER_FLOOR_JUMP_VELOCITY
const RUN_JUMP_BONUS := TUNING.PLAYER_RUN_JUMP_BONUS
const WALL_BOUNCE_JUMP_BONUS := TUNING.PLAYER_WALL_BOUNCE_JUMP_BONUS
const WALL_BOUNCE_MIN_SPEED := TUNING.PLAYER_WALL_BOUNCE_MIN_SPEED
const WALL_BOUNCE_MAX_SPEED := TUNING.PLAYER_WALL_BOUNCE_MAX_SPEED
const WALL_BOUNCE_SPEED_MULTIPLIER := TUNING.PLAYER_WALL_BOUNCE_SPEED_MULTIPLIER
const WALL_BOUNCE_UPWARD_MULTIPLIER := TUNING.PLAYER_WALL_BOUNCE_UPWARD_MULTIPLIER
const WALL_BOUNCE_PERFECT_WINDOW_MSEC := TUNING.PLAYER_WALL_BOUNCE_PERFECT_WINDOW_MSEC
const WALL_BOUNCE_PERFECT_MOMENTUM := TUNING.PLAYER_WALL_BOUNCE_PERFECT_MOMENTUM
const WALL_BOUNCE_PERFECT_JUMP_BONUS := TUNING.PLAYER_WALL_BOUNCE_PERFECT_JUMP_BONUS
const WALL_BOUNCE_HORIZONTAL_RETAIN := TUNING.PLAYER_WALL_BOUNCE_HORIZONTAL_RETAIN
const WALL_BOUNCE_MOMENTUM_GRACE := TUNING.PLAYER_WALL_BOUNCE_MOMENTUM_GRACE
const COMBO_TIMEOUT := TUNING.PLAYER_COMBO_TIMEOUT
const STORED_JUMP_BONUS_TIMEOUT := TUNING.PLAYER_STORED_JUMP_BONUS_TIMEOUT
const CAMERA_WORLD_CENTER_X := TUNING.PLAYER_CAMERA_CENTER_X
const CAMERA_VERTICAL_OFFSET := TUNING.PLAYER_CAMERA_VERTICAL_OFFSET

var gravity_scale: float = BASE_GRAVITY
var biome_gravity_multiplier := 1.0
var biome_drag_multiplier := 1.0
var biome_control_multiplier := 1.0
var wall_bounce_cooldown := 0.0
var wall_bounce_jump_bonus := 0.0
var can_wall_bounce := true
var last_movement_press_direction := 0.0
var last_movement_press_msec := -WALL_BOUNCE_PERFECT_WINDOW_MSEC * 2
var wall_bounce_time_msec := 0
var wall_bounce_direction := 0.0
var wall_bounce_perfect_pending := false
var combo_count := 0
var combo_time_remaining := 0.0
var stored_jump_bonus_time_remaining := 0.0
var supporting_platform: Node
var last_landed_platform: Node
var platforms_passed_this_airtime: Dictionary = {}
var _sprite_base_position := Vector2.ZERO
var _sprite_base_scale := Vector2.ONE
var _idle_time := 0.0
var _was_airborne := false
var _landing_squish := 0.0
var _facing := -1.0
var _roll_timer := 0.0
var _roll_duration := 0.45
var _roll_direction := 1.0

@onready var camera: Camera2D = $Camera2D
@onready var character_sprite: Sprite2D = $SpriteSlots/CharacterSprite


func _ready() -> void:
	_sprite_base_position = character_sprite.position
	_sprite_base_scale = character_sprite.scale
	update_camera_tracking()


func _process(delta: float) -> void:
	_idle_time += delta
	_landing_squish = lerpf(_landing_squish, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if _roll_timer > 0.0:
		_roll_timer = max(0.0, _roll_timer - delta)
	var input_dir := get_horizontal_direction()
	if input_dir != 0.0:
		_facing = -input_dir
	var idle_bob := 0.0
	var breathe := 1.0 + sin(_idle_time * 2.1) * 0.01
	var lean := clampf(velocity.x / MAX_HORIZONTAL_SPEED, -1.0, 1.0) * 0.06
	var grounded := 1.0 if is_on_floor() else 0.0
	var ground_squish := 0.97 if grounded else 1.0
	var squish_y := (1.0 - _landing_squish) * ground_squish
	var squish_x := (1.0 + _landing_squish * 0.5) / ground_squish
	character_sprite.position = _sprite_base_position + Vector2(0.0, idle_bob)
	character_sprite.scale = _sprite_base_scale * Vector2(_facing * breathe * squish_x, breathe * squish_y)
	var roll_angle := 0.0
	if _roll_timer > 0.0:
		var roll_progress := 1.0 - (_roll_timer / _roll_duration)
		roll_angle = _roll_direction * roll_progress * TAU
	character_sprite.rotation = lean + roll_angle

func _physics_process(delta: float) -> void:
	var fast_drop := Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)
	gravity_scale = FAST_DROP_GRAVITY if fast_drop else BASE_GRAVITY
	if wall_bounce_perfect_pending and Time.get_ticks_msec() - wall_bounce_time_msec > WALL_BOUNCE_PERFECT_WINDOW_MSEC:
		wall_bounce_perfect_pending = false
	update_gameplay_timers(delta)
	apply_gravity(delta)
	apply_horizontal_momentum(delta)
	handle_floor_jump()
	update_platform_pass_through()
	var previous_y := global_position.y
	var incoming_velocity := velocity
	move_and_slide()
	if incoming_velocity.y < 0.0:
		record_platforms_passed_upward(previous_y, global_position.y)
	resolve_platform_landing(incoming_velocity)
	handle_wall_bounce(incoming_velocity)
	wall_bounce_cooldown = max(0.0, wall_bounce_cooldown - delta)
	if not is_on_floor():
		_was_airborne = true
	elif _was_airborne:
		_was_airborne = false
		_landing_squish = 0.25
	update_camera_tracking()


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity_scale * biome_gravity_multiplier * delta
		velocity.y = min(velocity.y, TUNING.PLAYER_MAX_FALL_SPEED)


func update_gameplay_timers(delta: float) -> void:
	if combo_count > 0:
		combo_time_remaining = maxf(0.0, combo_time_remaining - delta)
		if is_zero_approx(combo_time_remaining):
			combo_count = 0
	if wall_bounce_jump_bonus > 0.0:
		stored_jump_bonus_time_remaining = maxf(0.0, stored_jump_bonus_time_remaining - delta)
		if is_zero_approx(stored_jump_bonus_time_remaining):
			wall_bounce_jump_bonus = 0.0


func apply_horizontal_momentum(delta: float) -> void:
	var direction := get_horizontal_direction()

	if direction != 0.0:
		var target_velocity := direction * MAX_HORIZONTAL_SPEED
		var control_multiplier := biome_control_multiplier
		if not is_on_floor():
			control_multiplier *= AIR_COUNTERSTEER_MULTIPLIER if direction * velocity.x < 0.0 else AIR_CONTROL_MULTIPLIER
		elif is_instance_valid(supporting_platform) and supporting_platform.has_method("get_ground_movement_multiplier"):
			control_multiplier *= supporting_platform.get_ground_movement_multiplier()
		velocity.x = move_toward(velocity.x, target_velocity, HORIZONTAL_ACCELERATION * control_multiplier * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, HORIZONTAL_DRAG * biome_drag_multiplier * delta)

	if abs(velocity.x) > MAX_HORIZONTAL_SPEED:
		velocity.x = sign(velocity.x) * MAX_HORIZONTAL_SPEED


func handle_floor_jump() -> void:
	if not is_on_floor():
		supporting_platform = null
		return
	if not Input.is_action_just_pressed("ui_accept"):
		return

	var jump_speed := absf(FLOOR_JUMP_VELOCITY)
	if is_instance_valid(supporting_platform) and supporting_platform.has_method("get_manual_jump_speed"):
		jump_speed = supporting_platform.get_manual_jump_speed(self)
	velocity.y = -get_run_scaled_jump_speed(jump_speed)
	if is_instance_valid(supporting_platform) and supporting_platform.has_method("on_player_jumped_from"):
		supporting_platform.on_player_jumped_from()
	supporting_platform = null
	increment_combo()


func get_run_scaled_jump_speed(jump_speed: float) -> float:
	return jump_speed * get_landing_jump_multiplier()


func get_landing_jump_multiplier() -> float:
	var run_bonus := RUN_JUMP_BONUS * clampf(absf(velocity.x) / MAX_HORIZONTAL_SPEED, 0.0, 1.0)
	var jump_multiplier := (1.0 + run_bonus) * (1.0 + wall_bounce_jump_bonus)
	wall_bounce_jump_bonus = 0.0
	stored_jump_bonus_time_remaining = 0.0
	return jump_multiplier


func update_platform_pass_through() -> void:
	var moving_up := velocity.y < 0.0
	for platform in get_tree().get_nodes_in_group("platform"):
		platform.set_player_pass_through(self, moving_up)


func record_platforms_passed_upward(previous_y: float, current_y: float) -> void:
	for platform in get_tree().get_nodes_in_group("platform"):
		if not platform.has_method("was_passed_upward"):
			continue
		if platform.was_passed_upward(previous_y, current_y, global_position.x):
			platforms_passed_this_airtime[platform.get_instance_id()] = true


func handle_wall_bounce(incoming_velocity: Vector2) -> void:
	if wall_bounce_cooldown > 0.0 or not can_wall_bounce:
		return

	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var collider: Object = collision.get_collider()
		if get_platform_owner(collider) != null:
			continue

		var normal := collision.get_normal()
		var impact_speed := -incoming_velocity.dot(normal)
		if abs(normal.x) > TUNING.PLAYER_WALL_NORMAL_X_MIN and abs(normal.y) < TUNING.PLAYER_WALL_NORMAL_Y_MAX and not is_on_floor() and impact_speed > WALL_BOUNCE_MIN_SPEED:
			var gravity_compensation := sqrt(biome_gravity_multiplier)
			var bounce_speed := clampf(abs(incoming_velocity.x) * WALL_BOUNCE_SPEED_MULTIPLIER * gravity_compensation, TUNING.PLAYER_WALL_BOUNCE_MIN_RECOIL_SPEED, WALL_BOUNCE_MAX_SPEED * gravity_compensation)
			velocity.x = normal.x * minf(absf(incoming_velocity.x) * WALL_BOUNCE_HORIZONTAL_RETAIN, MAX_HORIZONTAL_SPEED)
			velocity.y = minf(velocity.y, -bounce_speed * WALL_BOUNCE_UPWARD_MULTIPLIER)
			wall_bounce_jump_bonus = WALL_BOUNCE_JUMP_BONUS * clampf(impact_speed / MAX_HORIZONTAL_SPEED, 0.0, 1.0)
			stored_jump_bonus_time_remaining = STORED_JUMP_BONUS_TIMEOUT
			can_wall_bounce = false
			wall_bounce_time_msec = Time.get_ticks_msec()
			wall_bounce_direction = signf(normal.x)
			wall_bounce_perfect_pending = true
			if last_movement_press_direction == wall_bounce_direction and wall_bounce_time_msec - last_movement_press_msec <= WALL_BOUNCE_PERFECT_WINDOW_MSEC:
				award_perfect_wall_bounce()
			wall_bounce_cooldown = WALL_BOUNCE_MOMENTUM_GRACE
			increment_combo()
			_roll_timer = _roll_duration
			_roll_direction = wall_bounce_direction
			break


func award_perfect_wall_bounce() -> void:
	velocity.x = clampf(
		velocity.x + wall_bounce_direction * WALL_BOUNCE_PERFECT_MOMENTUM,
		-MAX_HORIZONTAL_SPEED,
		MAX_HORIZONTAL_SPEED
	)
	wall_bounce_jump_bonus += WALL_BOUNCE_PERFECT_JUMP_BONUS
	wall_bounce_perfect_pending = false


func resolve_platform_landing(incoming_velocity: Vector2) -> void:
	if incoming_velocity.y <= 0.0:
		return

	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var collider: Object = collision.get_collider()
		var platform := get_platform_owner(collider)
		if collision.get_normal().y < -0.35 and platform != null:
			var landed_platform_id := platform.get_instance_id()
			platforms_passed_this_airtime.erase(landed_platform_id)
			if not platforms_passed_this_airtime.is_empty():
				increment_combo(platforms_passed_this_airtime.size())
			platforms_passed_this_airtime.clear()
			if is_instance_valid(last_landed_platform) and platform == last_landed_platform:
				reset_combo()
			last_landed_platform = platform
			supporting_platform = platform
			can_wall_bounce = true
			wall_bounce_perfect_pending = false
			var combo_before_landing := combo_count
			platform.resolve_landing(self, incoming_velocity, collision.get_normal())
			if velocity.y < -300.0 and combo_count == combo_before_landing:
				increment_combo()
			if velocity.y < -300.0:
				velocity *= sqrt(biome_gravity_multiplier)
			return


func get_horizontal_direction() -> float:
	var direction := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		direction = -1.0
	elif Input.is_key_pressed(KEY_D):
		direction = 1.0
	return direction


func get_platform_owner(collider: Object) -> Node:
	if collider.has_meta("platform_owner"):
		return collider.get_meta("platform_owner") as Node
	return null


func increment_combo(amount: int = 1) -> void:
	combo_count += amount
	combo_time_remaining = COMBO_TIMEOUT


func get_combo_count() -> int:
	return combo_count


func get_combo_time_remaining() -> float:
	return combo_time_remaining


func get_combo_timeout() -> float:
	return COMBO_TIMEOUT


func get_stored_jump_bonus_time_remaining() -> float:
	return stored_jump_bonus_time_remaining


func get_stored_jump_bonus_timeout() -> float:
	return STORED_JUMP_BONUS_TIMEOUT


func reset_combo() -> void:
	combo_count = 0
	combo_time_remaining = 0.0


func set_biome_modifiers(gravity_multiplier: float, drag_multiplier: float, control_multiplier: float = 1.0) -> void:
	biome_gravity_multiplier = gravity_multiplier
	biome_drag_multiplier = drag_multiplier
	biome_control_multiplier = control_multiplier


func get_biome_gravity_multiplier() -> float:
	return biome_gravity_multiplier


func apply_wind(acceleration: float, delta: float) -> void:
	velocity.x = clampf(velocity.x + acceleration * delta, -MAX_HORIZONTAL_SPEED, MAX_HORIZONTAL_SPEED)


func update_camera_tracking() -> void:
	camera.global_position = Vector2(CAMERA_WORLD_CENTER_X, global_position.y + CAMERA_VERTICAL_OFFSET)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey and event.echo:
		return

	var direction := 0.0
	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.keycode == KEY_A):
		direction = -1.0
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.keycode == KEY_D):
		direction = 1.0
	if direction == 0.0:
		return

	last_movement_press_direction = direction
	last_movement_press_msec = Time.get_ticks_msec()
	if wall_bounce_perfect_pending and direction == wall_bounce_direction and last_movement_press_msec - wall_bounce_time_msec <= WALL_BOUNCE_PERFECT_WINDOW_MSEC:
		award_perfect_wall_bounce()
