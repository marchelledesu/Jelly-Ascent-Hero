extends CharacterBody2D

# Phase 1 implementation aligned to the Jelly Ascent GDD.
# Core goals:
# - build lateral momentum rather than constant left/right speed
# - wall collisions convert horizontal speed into upward rebound
# - fast drop increases gravity for sharp impact timing

const MAX_HORIZONTAL_SPEED := 700.0
const HORIZONTAL_ACCELERATION := 1100.0
const HORIZONTAL_DRAG := 450.0
const BASE_GRAVITY := 1650.0
const FAST_DROP_GRAVITY := 6600.0
const FLOOR_JUMP_VELOCITY := -650.0
const WALL_BOUNCE_MIN_SPEED := 600.0
const WALL_BOUNCE_MAX_SPEED := 1200.0
const WALL_BOUNCE_SPEED_MULTIPLIER := 1.5
const WALL_BOUNCE_UPWARD_MULTIPLIER := 1.1
const WALL_BOUNCE_HORIZONTAL_RETAIN := 1.0
const WALL_BOUNCE_MOMENTUM_GRACE := 0.3
const CAMERA_WORLD_CENTER_X := 350.0
const CAMERA_VERTICAL_OFFSET := -100.0

var gravity_scale: float = BASE_GRAVITY
var biome_gravity_multiplier := 1.0
var biome_drag_multiplier := 1.0
var wall_bounce_cooldown := 0.0
var combo_count := 0
var supporting_platform: Node

@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	update_camera_tracking()


func _physics_process(delta: float) -> void:
	var fast_drop := Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)
	gravity_scale = FAST_DROP_GRAVITY if fast_drop else BASE_GRAVITY
	apply_gravity(delta)
	apply_horizontal_momentum(delta)
	handle_floor_jump()
	update_platform_pass_through()
	var incoming_velocity := velocity
	move_and_slide()
	resolve_platform_landing(incoming_velocity)
	handle_wall_bounce(incoming_velocity)
	wall_bounce_cooldown = max(0.0, wall_bounce_cooldown - delta)
	update_camera_tracking()


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity_scale * biome_gravity_multiplier * delta
		velocity.y = min(velocity.y, 1800.0)


func apply_horizontal_momentum(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		direction = -1.0
	elif Input.is_key_pressed(KEY_D):
		direction = 1.0

	if direction != 0.0:
		if wall_bounce_cooldown <= 0.0 or direction * velocity.x >= 0.0:
			var target_velocity := direction * MAX_HORIZONTAL_SPEED
			velocity.x = move_toward(velocity.x, target_velocity, HORIZONTAL_ACCELERATION * delta)
	else:
		var bounce_drag_scale := 0.2 if wall_bounce_cooldown > 0.0 else 1.0
		velocity.x = move_toward(velocity.x, 0.0, HORIZONTAL_DRAG * biome_drag_multiplier * bounce_drag_scale * delta)

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
	velocity.y = -jump_speed
	supporting_platform = null


func update_platform_pass_through() -> void:
	var moving_up := velocity.y < 0.0
	for platform in get_tree().get_nodes_in_group("platform"):
		platform.set_player_pass_through(self, moving_up)


func handle_wall_bounce(incoming_velocity: Vector2) -> void:
	if wall_bounce_cooldown > 0.0:
		return

	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var collider: Object = collision.get_collider()
		if get_platform_owner(collider) != null:
			continue

		var normal := collision.get_normal()
		var impact_speed := -incoming_velocity.dot(normal)
		if abs(normal.x) > 0.8 and abs(normal.y) < 0.2 and not is_on_floor() and impact_speed > WALL_BOUNCE_MIN_SPEED:
			var gravity_compensation := sqrt(biome_gravity_multiplier)
			var bounce_speed := clampf(abs(incoming_velocity.x) * WALL_BOUNCE_SPEED_MULTIPLIER * gravity_compensation, 300.0, WALL_BOUNCE_MAX_SPEED * gravity_compensation)
			velocity.x = normal.x * minf(bounce_speed * WALL_BOUNCE_HORIZONTAL_RETAIN, MAX_HORIZONTAL_SPEED)
			velocity.y = minf(velocity.y, -bounce_speed * WALL_BOUNCE_UPWARD_MULTIPLIER)
			wall_bounce_cooldown = WALL_BOUNCE_MOMENTUM_GRACE
			break


func resolve_platform_landing(incoming_velocity: Vector2) -> void:
	if incoming_velocity.y <= 0.0:
		return

	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var collider: Object = collision.get_collider()
		var platform := get_platform_owner(collider)
		if collision.get_normal().y < -0.35 and platform != null:
			supporting_platform = platform
			platform.resolve_landing(self, incoming_velocity, collision.get_normal())
			if velocity.y < -300.0:
				velocity *= sqrt(biome_gravity_multiplier)
			return


func get_platform_owner(collider: Object) -> Node:
	if collider.has_meta("platform_owner"):
		return collider.get_meta("platform_owner") as Node
	return null


func increment_combo() -> void:
	combo_count += 1


func get_combo_count() -> int:
	return combo_count


func reset_combo() -> void:
	combo_count = 0


func set_biome_modifiers(gravity_multiplier: float, drag_multiplier: float) -> void:
	biome_gravity_multiplier = gravity_multiplier
	biome_drag_multiplier = drag_multiplier


func get_biome_gravity_multiplier() -> float:
	return biome_gravity_multiplier


func apply_wind(acceleration: float, delta: float) -> void:
	velocity.x = clampf(velocity.x + acceleration * delta, -MAX_HORIZONTAL_SPEED, MAX_HORIZONTAL_SPEED)


func update_camera_tracking() -> void:
	camera.global_position = Vector2(CAMERA_WORLD_CENTER_X, global_position.y + CAMERA_VERTICAL_OFFSET)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
