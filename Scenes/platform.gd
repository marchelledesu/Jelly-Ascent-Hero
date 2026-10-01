extends Node2D


enum PlatformType {
	STANDARD,
	SUPER_TRAMPOLINE,
	SLINGSHOT_RAMP,
	FRAGILE,
	STICKY_DOUGH,
}

const PLATFORM_HALF_HEIGHT := 6.0
const STICKY_JUMP_SPEED := 500.0
const SUPER_TRAMPOLINE_JUMP_SPEED := 1100.0
const PLAYER_HALF_HEIGHT := 17.5

@export var platform_type: PlatformType = PlatformType.STANDARD
@export var base_bounce_speed := 680.0
@export var slingshot_rotation_degrees := -18.0
@export_range(120.0, 220.0, 10.0) var min_standard_width := 150.0
@export_range(180.0, 320.0, 10.0) var max_standard_width := 270.0
@export_enum("None", "Left", "Right") var wall_attach_side := 0
@export var world_width := 700.0

@onready var softbody: SoftBody2D = $SoftBody
@onready var rigid_platform: RigidBody2D = $RigidPlatform
@onready var platform_visuals: Node2D = $PlatformVisuals
@onready var rigid_visual: Polygon2D = $PlatformVisuals/RigidPlatformVisual
@onready var rigid_collision_shape: CollisionShape2D = $RigidPlatform/CollisionShape2D
@onready var collapse_timer: Timer = $CollapseTimer

var players_passing_through: Dictionary = {}


func _ready() -> void:
	add_to_group("platform")
	var uses_softbody := is_softbody_platform()
	softbody.visible = uses_softbody
	platform_visuals.visible = not uses_softbody
	rigid_platform.visible = not uses_softbody
	rigid_collision_shape.disabled = uses_softbody
	rigid_platform.set_meta("platform_owner", self)
	if not uses_softbody:
		rigid_visual.color = get_platform_color()
		if platform_type == PlatformType.STANDARD:
			var random_width := randf_range(minf(min_standard_width, max_standard_width), maxf(min_standard_width, max_standard_width))
			if wall_attach_side == 1:
				position.x = 12.0 + random_width / 2.0
			elif wall_attach_side == 2:
				position.x = world_width - 12.0 - random_width / 2.0
			var wide_shape := rigid_collision_shape.shape.duplicate() as RectangleShape2D
			wide_shape.size.x = random_width
			rigid_collision_shape.shape = wide_shape
			rigid_visual.polygon = PackedVector2Array([
				Vector2(-random_width / 2.0, -PLATFORM_HALF_HEIGHT),
				Vector2(random_width / 2.0, -PLATFORM_HALF_HEIGHT),
				Vector2(random_width / 2.0, PLATFORM_HALF_HEIGHT),
				Vector2(-random_width / 2.0, PLATFORM_HALF_HEIGHT),
			])
		return

	softbody.color = get_platform_color()
	if platform_type == PlatformType.SLINGSHOT_RAMP:
		rotation = deg_to_rad(slingshot_rotation_degrees)
	configure_softbody()
	(softbody as SoftBody2D).initialize_for_platform()
	for body_data in softbody.get_rigid_bodies():
		body_data.rigidbody.set_meta("platform_owner", self)
	anchor_softbody_ends()
	collapse_timer.timeout.connect(_on_collapse_timeout)


func resolve_landing(player: CharacterBody2D, impact_velocity: Vector2, surface_normal: Vector2) -> void:
	if impact_velocity.y <= 0.0:
		return

	var impact_speed := maxf(0.0, impact_velocity.dot(-surface_normal))
	match platform_type:
		PlatformType.STANDARD:
			settle_or_jump(player, get_manual_jump_speed(player))
		PlatformType.SUPER_TRAMPOLINE:
			player.velocity = surface_normal * SUPER_TRAMPOLINE_JUMP_SPEED
			if player.has_method("increment_combo"):
				player.increment_combo()
		PlatformType.SLINGSHOT_RAMP:
			var horizontal_direction := signf(player.velocity.x)
			if is_zero_approx(horizontal_direction):
				horizontal_direction = 1.0
			var launch_direction := Vector2(horizontal_direction * 0.65, -0.76).normalized()
			var launch_speed := clampf(maxf(base_bounce_speed * 1.4, impact_speed * 0.65), base_bounce_speed, 1250.0)
			player.velocity = launch_direction * launch_speed
		PlatformType.FRAGILE:
			settle_or_jump(player, get_manual_jump_speed(player))
			collapse_timer.start(0.2)
			rigid_visual.color = rigid_visual.color.darkened(0.35)
		PlatformType.STICKY_DOUGH:
			player.velocity.x *= 0.1
			settle_or_jump(player, get_manual_jump_speed(player))
			if player.has_method("reset_combo"):
				player.reset_combo()


func settle_or_jump(player: CharacterBody2D, jump_speed: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		player.velocity.y = -jump_speed
	else:
		player.velocity.y = 0.0


func get_manual_jump_speed(player: CharacterBody2D) -> float:
	var gravity_compensation := sqrt(player.get_biome_gravity_multiplier())
	match platform_type:
		PlatformType.STANDARD:
			return base_bounce_speed * gravity_compensation
		PlatformType.FRAGILE:
			return minf(base_bounce_speed * 0.8, 680.0) * gravity_compensation
		PlatformType.STICKY_DOUGH:
			return STICKY_JUMP_SPEED * gravity_compensation
		_:
			return 750.0 * gravity_compensation


func get_platform_color() -> Color:
	match platform_type:
		PlatformType.SUPER_TRAMPOLINE:
			return Color(0.25, 0.8, 0.35)
		PlatformType.SLINGSHOT_RAMP:
			return Color(0.25, 0.55, 0.95)
		PlatformType.FRAGILE:
			return Color(0.9, 0.25, 0.25)
		PlatformType.STICKY_DOUGH:
			return Color(0.95, 0.78, 0.2)
		_:
			return Color(0.55, 0.58, 0.62)


func configure_softbody() -> void:
	match platform_type:
		PlatformType.SUPER_TRAMPOLINE:
			softbody.stiffness = 12.0
			softbody.damping = 1.2
		PlatformType.SLINGSHOT_RAMP:
			softbody.stiffness = 28.0
			softbody.damping = 2.5
		PlatformType.FRAGILE:
			softbody.stiffness = 12.0
			softbody.damping = 1.5
		PlatformType.STICKY_DOUGH:
			softbody.stiffness = 16.0
			softbody.damping = 14.0
		_:
			softbody.stiffness = 24.0
			softbody.damping = 4.0


func is_softbody_platform() -> bool:
	return platform_type in [PlatformType.SUPER_TRAMPOLINE, PlatformType.SLINGSHOT_RAMP, PlatformType.STICKY_DOUGH]


func get_platform_collision_bodies() -> Array[PhysicsBody2D]:
	var collision_bodies: Array[PhysicsBody2D] = []
	if is_softbody_platform():
		for body_data in softbody.get_rigid_bodies():
			collision_bodies.append(body_data.rigidbody)
	else:
		collision_bodies.append(rigid_platform)
	return collision_bodies


func set_player_pass_through(player: CharacterBody2D, moving_up: bool) -> void:
	var surface_top_y := to_global(Vector2(0.0, -PLATFORM_HALF_HEIGHT)).y
	var body_clear_threshold := surface_top_y + PLAYER_HALF_HEIGHT * 2.0 * 0.1
	var should_pass_through := moving_up and player.global_position.y + PLAYER_HALF_HEIGHT > body_clear_threshold
	var player_id := player.get_instance_id()
	if players_passing_through.has(player_id) and players_passing_through[player_id] == should_pass_through:
		return

	players_passing_through[player_id] = should_pass_through
	for rigid_body in get_platform_collision_bodies():
		if should_pass_through:
			player.add_collision_exception_with(rigid_body)
		else:
			player.remove_collision_exception_with(rigid_body)


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
	queue_free()
