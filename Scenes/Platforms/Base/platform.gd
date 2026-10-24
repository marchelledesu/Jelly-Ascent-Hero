extends Node2D


enum PlatformType {
	STANDARD,
	SUPER_TRAMPOLINE,
	SLINGSHOT_RAMP,
	FRAGILE,
	STICKY_DOUGH,
}

const TUNING = preload("res://Scenes/Gameplay/game_tuning.gd")
const PLATFORM_HALF_HEIGHT := TUNING.PLATFORM_HALF_HEIGHT
const STICKY_GROUND_MOVEMENT_MULTIPLIER := TUNING.PLATFORM_STICKY_GROUND_MOVEMENT_MULTIPLIER
const SUPER_TRAMPOLINE_JUMP_SPEED := TUNING.PLATFORM_SUPER_TRAMPOLINE_JUMP_SPEED
const PLAYER_HALF_HEIGHT := TUNING.PLAYER_HALF_HEIGHT
const LANDING_HORIZONTAL_RETAIN := TUNING.PLATFORM_LANDING_HORIZONTAL_RETAIN
const LANDING_COLLISION_MARGIN := TUNING.PLATFORM_LANDING_COLLISION_MARGIN

@export var platform_type: PlatformType = PlatformType.STANDARD
@export var base_bounce_speed := TUNING.PLATFORM_STANDARD_BOUNCE_SPEED
@export var slingshot_rotation_degrees := -TUNING.PLATFORM_RAMP_DEFAULT_ANGLE
@export_range(TUNING.PLATFORM_WIDTH_MIN_EXPORT, TUNING.PLATFORM_WIDTH_MAX_EXPORT, TUNING.PLATFORM_WIDTH_MIN_EXPORT_STEP) var min_standard_width := TUNING.PLATFORM_DEFAULT_WIDTH_MIN
@export_range(TUNING.PLATFORM_WIDE_WIDTH_MIN_EXPORT, TUNING.PLATFORM_WIDE_WIDTH_MAX_EXPORT, TUNING.PLATFORM_WIDE_WIDTH_EXPORT_STEP) var max_standard_width := TUNING.PLATFORM_DEFAULT_WIDTH_MAX
@export_enum("None", "Left", "Right") var wall_attach_side := 0
@export var world_width := TUNING.WORLD_WIDTH
@export var slingshot_mirror := false

@onready var softbody: SoftBody2D = $SoftBody
@onready var rigid_platform: RigidBody2D = $RigidPlatform
@onready var platform_visuals: Node2D = $PlatformVisuals
@onready var rigid_visual: Polygon2D = $PlatformVisuals/RigidPlatformVisual
@onready var rigid_collision_shape: CollisionShape2D = $RigidPlatform/CollisionShape2D
@onready var platform_sprite: TileMapLayer = $SpriteSlots/PlatformSprite
@onready var collapse_timer: Timer = $CollapseTimer

var players_passing_through: Dictionary = {}
var fragile_used := false


func _ready() -> void:
	add_to_group("platform")
	var uses_softbody := is_softbody_platform()
	softbody.visible = uses_softbody
	platform_visuals.visible = not uses_softbody
	rigid_platform.visible = not uses_softbody
	rigid_collision_shape.disabled = uses_softbody and platform_type != PlatformType.STICKY_DOUGH
	rigid_platform.set_meta("platform_owner", self)
	apply_physics_materials()
	if not uses_softbody:
		rigid_visual.color = get_platform_color()
		var platform_width := 120.0
		var atlas_path := "res://Assets/standard platform.png"
		if platform_type == PlatformType.FRAGILE:
			atlas_path = "res://Assets/red platform.png"
		if platform_type == PlatformType.STANDARD:
			platform_width = randf_range(minf(min_standard_width, max_standard_width), maxf(min_standard_width, max_standard_width))
			if wall_attach_side == 1:
				position.x = TUNING.PLATFORM_WORLD_EDGE_INSET + platform_width / 2.0
			elif wall_attach_side == 2:
				position.x = world_width - TUNING.PLATFORM_WORLD_EDGE_INSET - platform_width / 2.0
			var wide_shape := rigid_collision_shape.shape.duplicate() as RectangleShape2D
			wide_shape.size.x = platform_width
			rigid_collision_shape.shape = wide_shape
			rigid_visual.polygon = PackedVector2Array([
				Vector2(-platform_width / 2.0, -PLATFORM_HALF_HEIGHT),
				Vector2(platform_width / 2.0, -PLATFORM_HALF_HEIGHT),
				Vector2(platform_width / 2.0, PLATFORM_HALF_HEIGHT),
				Vector2(-platform_width / 2.0, PLATFORM_HALF_HEIGHT),
			])
		rigid_visual.visible = false
		var tile_count := maxi(1, int(ceil(platform_width / 32.0)))
		platform_sprite.atlas_texture = load(atlas_path)
		platform_sprite.position = Vector2(-tile_count * 16.0, -16.0)
		platform_sprite.build_tiles(tile_count)
		if platform_type == PlatformType.FRAGILE:
			collapse_timer.wait_time = TUNING.PLATFORM_FRAGILE_COLLAPSE_DELAY
			collapse_timer.timeout.connect(_on_collapse_timeout)
		return

	softbody.color = get_platform_color()
	if platform_type == PlatformType.SLINGSHOT_RAMP:
		rotation = deg_to_rad(slingshot_rotation_degrees)
		if slingshot_mirror:
			softbody.scale.x = -1.0
	softbody.vertex_interval = TUNING.PLATFORM_SOFTBODY_VERTEX_INTERVAL
	softbody.mass = TUNING.PLATFORM_SOFTBODY_MASS
	configure_softbody()
	(softbody as SoftBody2D).initialize_for_platform()
	for body_data in softbody.get_rigid_bodies():
		body_data.rigidbody.set_meta("platform_owner", self)
		if platform_type == PlatformType.STICKY_DOUGH:
			body_data.rigidbody.collision_layer = 0
	anchor_softbody_ends()


func _process(_delta: float) -> void:
	if platform_type != PlatformType.FRAGILE or fragile_used:
		return
	if collapse_timer.is_stopped():
		return
	var player := get_tree().current_scene.get_node_or_null("Player") if get_tree() != null and get_tree().current_scene != null else null
	if player == null or player.supporting_platform != self:
		collapse_timer.stop()

func resolve_landing(player: CharacterBody2D, impact_velocity: Vector2, surface_normal: Vector2) -> void:
	if impact_velocity.y <= 0.0:
		return
	if platform_type == PlatformType.FRAGILE and fragile_used:
		return

	var impact_speed := maxf(0.0, impact_velocity.dot(-surface_normal))
	player.velocity.x *= LANDING_HORIZONTAL_RETAIN
	match platform_type:
		PlatformType.STANDARD:
			settle_or_jump(player, get_manual_jump_speed(player))
		PlatformType.SUPER_TRAMPOLINE:
			var launch_speed := SUPER_TRAMPOLINE_JUMP_SPEED
			if player.has_method("get_run_scaled_jump_speed"):
				launch_speed = player.get_run_scaled_jump_speed(launch_speed)
			player.velocity = surface_normal * launch_speed
			if player.has_method("increment_combo"):
				player.increment_combo()
		PlatformType.SLINGSHOT_RAMP:
			var horizontal_direction := 1.0 if global_position.x < world_width / 2.0 else -1.0
			var launch_direction := Vector2(
				horizontal_direction * TUNING.PLATFORM_RAMP_LAUNCH_HORIZONTAL_RATIO,
				-TUNING.PLATFORM_RAMP_LAUNCH_VERTICAL_RATIO
			).normalized()
			var launch_speed := clampf(
				maxf(base_bounce_speed * TUNING.PLATFORM_RAMP_MIN_LAUNCH_MULTIPLIER, impact_speed * TUNING.PLATFORM_RAMP_IMPACT_MULTIPLIER),
				base_bounce_speed,
				TUNING.PLATFORM_RAMP_MAX_LAUNCH_SPEED
			)
			player.velocity = launch_direction * launch_speed
			if player.has_method("get_run_scaled_jump_speed"):
				player.velocity.y = -player.get_run_scaled_jump_speed(absf(player.velocity.y))
		PlatformType.FRAGILE:
			settle_or_jump(player, get_manual_jump_speed(player))
			if player.velocity.y < 0.0:
				collapse_timer.stop()
			elif not fragile_used and collapse_timer.is_stopped():
				collapse_timer.start()
		PlatformType.STICKY_DOUGH:
			player.velocity.x *= TUNING.PLATFORM_STICKY_LANDING_HORIZONTAL_RETAIN
			settle_or_jump(player, get_manual_jump_speed(player))
			if player.has_method("reset_combo"):
				player.reset_combo()


func on_player_jumped_from() -> void:
	if platform_type != PlatformType.FRAGILE or fragile_used:
		return
	collapse_timer.stop()


func settle_or_jump(player: CharacterBody2D, jump_speed: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		var launch_speed := jump_speed
		if player.has_method("get_run_scaled_jump_speed"):
			launch_speed = player.get_run_scaled_jump_speed(jump_speed)
		player.velocity.y = -launch_speed
	else:
		player.velocity.y = 0.0


func get_manual_jump_speed(player: CharacterBody2D) -> float:
	var gravity_compensation := sqrt(player.get_biome_gravity_multiplier())
	match platform_type:
		PlatformType.STANDARD:
			return base_bounce_speed * gravity_compensation
		PlatformType.FRAGILE:
			return minf(base_bounce_speed * TUNING.PLATFORM_FRAGILE_JUMP_MULTIPLIER, TUNING.PLATFORM_FRAGILE_MAX_JUMP_SPEED) * gravity_compensation
		PlatformType.STICKY_DOUGH:
			return base_bounce_speed * gravity_compensation
		_:
			return TUNING.PLATFORM_DEFAULT_SPECIAL_JUMP_SPEED * gravity_compensation


func get_ground_movement_multiplier() -> float:
	if platform_type == PlatformType.STICKY_DOUGH:
		return STICKY_GROUND_MOVEMENT_MULTIPLIER
	return 1.0


func get_platform_color() -> Color:
	match platform_type:
		PlatformType.SUPER_TRAMPOLINE:
			return TUNING.PLATFORM_COLOR_TRAMPOLINE
		PlatformType.SLINGSHOT_RAMP:
			return TUNING.PLATFORM_COLOR_SLINGSHOT
		PlatformType.FRAGILE:
			return TUNING.PLATFORM_COLOR_FRAGILE
		PlatformType.STICKY_DOUGH:
			return TUNING.PLATFORM_COLOR_STICKY
		_:
			return TUNING.PLATFORM_COLOR_STANDARD


func configure_softbody() -> void:
	match platform_type:
		PlatformType.SUPER_TRAMPOLINE:
			softbody.stiffness = TUNING.PLATFORM_SUPER_TRAMPOLINE_STIFFNESS
			softbody.damping = TUNING.PLATFORM_SUPER_TRAMPOLINE_DAMPING
		PlatformType.SLINGSHOT_RAMP:
			softbody.stiffness = TUNING.PLATFORM_SLINGSHOT_STIFFNESS
			softbody.damping = TUNING.PLATFORM_SLINGSHOT_DAMPING
		PlatformType.FRAGILE:
			softbody.stiffness = TUNING.PLATFORM_FRAGILE_STIFFNESS
			softbody.damping = TUNING.PLATFORM_FRAGILE_DAMPING
		PlatformType.STICKY_DOUGH:
			softbody.stiffness = TUNING.PLATFORM_STICKY_STIFFNESS
			softbody.damping = TUNING.PLATFORM_STICKY_DAMPING
		_:
			softbody.stiffness = TUNING.PLATFORM_STANDARD_STIFFNESS
			softbody.damping = TUNING.PLATFORM_STANDARD_DAMPING


func apply_physics_materials() -> void:
	var softbody_material := softbody.physics_material_override.duplicate() as PhysicsMaterial
	softbody_material.friction = TUNING.PLATFORM_RIGID_FRICTION
	softbody_material.bounce = TUNING.PLATFORM_RIGID_BOUNCE
	softbody.physics_material_override = softbody_material
	var rigid_material := rigid_platform.physics_material_override.duplicate() as PhysicsMaterial
	rigid_material.friction = TUNING.PLATFORM_RIGID_FRICTION
	rigid_material.bounce = TUNING.PLATFORM_RIGID_BOUNCE
	rigid_platform.physics_material_override = rigid_material


func is_softbody_platform() -> bool:
	return platform_type in [PlatformType.SUPER_TRAMPOLINE, PlatformType.SLINGSHOT_RAMP, PlatformType.STICKY_DOUGH]


func get_platform_collision_bodies() -> Array[PhysicsBody2D]:
	var collision_bodies: Array[PhysicsBody2D] = []
	if is_softbody_platform() and platform_type != PlatformType.STICKY_DOUGH:
		for body_data in softbody.get_rigid_bodies():
			collision_bodies.append(body_data.rigidbody)
	if not is_softbody_platform() or platform_type == PlatformType.STICKY_DOUGH:
		collision_bodies.append(rigid_platform)
	return collision_bodies


func set_player_pass_through(player: CharacterBody2D, moving_up: bool) -> void:
	var player_local_y := to_local(player.global_position).y
	var is_above_landing_surface := player_local_y <= -PLATFORM_HALF_HEIGHT - PLAYER_HALF_HEIGHT + LANDING_COLLISION_MARGIN
	var should_pass_through := moving_up or not is_above_landing_surface
	var player_id := player.get_instance_id()
	if players_passing_through.has(player_id) and players_passing_through[player_id] == should_pass_through:
		return

	players_passing_through[player_id] = should_pass_through
	for rigid_body in get_platform_collision_bodies():
		if should_pass_through:
			player.add_collision_exception_with(rigid_body)
		else:
			player.remove_collision_exception_with(rigid_body)


func was_passed_upward(previous_player_y: float, current_player_y: float, player_global_x: float) -> bool:
	var previous_bottom := to_local(Vector2(player_global_x, previous_player_y + PLAYER_HALF_HEIGHT))
	var current_bottom := to_local(Vector2(player_global_x, current_player_y + PLAYER_HALF_HEIGHT))
	if previous_bottom.y <= -PLATFORM_HALF_HEIGHT or current_bottom.y > -PLATFORM_HALF_HEIGHT:
		return false

	var local_player_x := to_local(Vector2(player_global_x, current_player_y)).x
	var platform_min_x := -60.0
	var platform_max_x := 60.0
	if is_softbody_platform():
		var polygon_points := softbody.polygon
		if polygon_points.is_empty():
			return false
		platform_min_x = polygon_points[0].x
		platform_max_x = polygon_points[0].x
		for point in polygon_points:
			platform_min_x = minf(platform_min_x, point.x)
			platform_max_x = maxf(platform_max_x, point.x)
	else:
		var rectangle := rigid_collision_shape.shape as RectangleShape2D
		if rectangle == null:
			return false
		platform_min_x = -rectangle.size.x / 2.0
		platform_max_x = rectangle.size.x / 2.0

	return local_player_x + PLAYER_HALF_HEIGHT >= platform_min_x and local_player_x - PLAYER_HALF_HEIGHT <= platform_max_x


func anchor_softbody_ends() -> void:
	var bodies: Array = softbody.get_rigid_bodies()
	if bodies.size() < 2:
		return

	var leftmost_body: PhysicsBody2D = bodies[0].rigidbody
	var rightmost_body: PhysicsBody2D = leftmost_body
	for body in bodies:
		var rigid_body: PhysicsBody2D = body.rigidbody
		rigid_body.set_meta("platform_owner", self)
		if rigid_body.global_position.x < leftmost_body.global_position.x:
			leftmost_body = rigid_body
		if rigid_body.global_position.x > rightmost_body.global_position.x:
			rightmost_body = rigid_body

	anchor_body(leftmost_body, "LeftAnchor")
	if rightmost_body != leftmost_body:
		anchor_body(rightmost_body, "RightAnchor")


func anchor_body(rigid_body: PhysicsBody2D, anchor_name: String) -> void:
	var anchor := StaticBody2D.new()
	anchor.name = anchor_name
	add_child(anchor)
	anchor.global_position = rigid_body.global_position

	var joint := PinJoint2D.new()
	joint.name = anchor_name + "Joint"
	add_child(joint)
	joint.global_position = rigid_body.global_position
	joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(rigid_body)
	joint.softness = 0.25


func _on_collapse_timeout() -> void:
	rigid_visual.color = rigid_visual.color.darkened(0.35)
	platform_sprite.modulate = platform_sprite.modulate.darkened(0.35)
	queue_free()
