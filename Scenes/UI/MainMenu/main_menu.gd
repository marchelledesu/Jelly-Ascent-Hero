extends Control


const LEVEL_SCENE := "res://Scenes/Gameplay/gameplay.tscn"
const LEADERBOARD_STORE = preload("res://Scenes/UI/Leaderboard/leaderboard_store.gd")

var main_page: Control
var tutorial_page: Control
var leaderboard_page: Control
var leaderboard_rows: VBoxContainer

var bg_time := 0.0
var acid_surface: Polygon2D
var floating_platforms: Array[Dictionary] = []
var jelly_sprite: TextureRect



func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_background()
	build_main_page()
	build_tutorial_page()
	build_leaderboard_page()
	show_page(tutorial_page)




func _process(delta: float) -> void:
	bg_time += delta
	var viewport_size := get_viewport_rect().size
	if is_instance_valid(acid_surface):
		rebuild_acid_wave(viewport_size)
	for entry in floating_platforms:
		var node := entry["node"] as TextureRect
		var base_x: float = viewport_size.x * float(entry["x_frac"])
		var base_y: float = viewport_size.y * float(entry["y_frac"])
		node.position = Vector2(base_x, base_y + sin(bg_time * 0.9 + float(entry["phase"])) * 6.0)
	if is_instance_valid(jelly_sprite):
		jelly_sprite.position = Vector2(viewport_size.x * 0.4, viewport_size.y * 0.46 + sin(bg_time * 1.6) * 4.0)


func build_background() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.10, 0.20)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# Soft fog layers for depth (biome 0 sky).
	for layer_index in 4:
		var fog := ColorRect.new()
		fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := float(layer_index) / 3.0
		fog.color = Color(
			lerpf(0.30, 0.50, t),
			lerpf(0.36, 0.52, t),
			lerpf(0.55, 0.72, t),
			0.10 + t * 0.08
		)
		add_child(fog)

	# Rising acid pool at the bottom.
	acid_surface = Polygon2D.new()
	add_child(acid_surface)
	rebuild_acid_wave(get_viewport_rect().size)

	# Floating platforms echoing the climb.
	var platform_texture := preload("res://Assets/standard platform.png")
	var scales := [0.7, 0.55, 0.8, 0.6, 0.75]
	var fracs := [
		Vector2(0.13, 0.40), Vector2(0.74, 0.31), Vector2(0.43, 0.52),
		Vector2(0.20, 0.65), Vector2(0.67, 0.59)
	]
	for i in fracs.size():
		var platform := TextureRect.new()
		platform.texture = platform_texture
		platform.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		platform.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		platform.custom_minimum_size = Vector2(128, 32) * float(scales[i])
		platform.size = Vector2(128, 32) * float(scales[i])
		platform.mouse_filter = Control.MOUSE_FILTER_IGNORE
		platform.modulate = Color(1, 1, 1, 0.85)
		add_child(platform)
		floating_platforms.append({
			"node": platform,
			"x_frac": fracs[i].x,
			"y_frac": fracs[i].y,
			"phase": float(i) * 1.3
		})

	# Jelly hero resting on a ledge.
	var player_texture := preload("res://Assets/playerJAH.png")
	jelly_sprite = TextureRect.new()
	jelly_sprite.texture = player_texture
	jelly_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	jelly_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	jelly_sprite.size = Vector2(64, 64)
	jelly_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(jelly_sprite)

	# Ambient particles for life.
	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5

	var bubbles := CPUParticles2D.new()
	bubbles.amount = 36
	bubbles.lifetime = 2.6
	bubbles.preprocess = 1.0
	bubbles.speed_scale = 1.0
	bubbles.explosiveness = 0.0
	bubbles.randomness = 0.6
	bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	bubbles.emission_rect_extents = Vector2(viewport_size.x * 0.5, 12)
	bubbles.position = Vector2(center.x, viewport_size.y - 60)
	bubbles.direction = Vector2(0, -1)
	bubbles.spread = 18.0
	bubbles.initial_velocity_min = 20.0
	bubbles.initial_velocity_max = 55.0
	bubbles.gravity = Vector2(0, -8)
	bubbles.scale_amount_min = 1.0
	bubbles.scale_amount_max = 3.0
	bubbles.color = Color(0.55, 0.95, 0.45, 0.7)
	add_child(bubbles)

	var motes := CPUParticles2D.new()
	motes.amount = 28
	motes.lifetime = 4.0
	motes.preprocess = 2.0
	motes.speed_scale = 0.8
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5)
	motes.position = center
	motes.direction = Vector2(0, 0)
	motes.spread = 180.0
	motes.initial_velocity_min = 2.0
	motes.initial_velocity_max = 12.0
	motes.gravity = Vector2(0, -4)
	motes.scale_amount_min = 0.8
	motes.scale_amount_max = 2.0
	motes.color = Color(0.75, 0.95, 0.85, 0.5)
	add_child(motes)

	# Minecraft-style tip on the background.
	var tip_label := Label.new()
	tip_label.text = "Tip: you can always wall bounce!"
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tip_label.offset_top = -40.0
	tip_label.offset_bottom = -12.0
	tip_label.add_theme_font_size_override("font_size", 16)
	tip_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85, 0.65))
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip_label)


func rebuild_acid_wave(viewport_size: Vector2) -> void:
	var base_y := viewport_size.y - 90.0
	var points := PackedVector2Array()
	points.append(Vector2(0, viewport_size.y))
	for i in 25:
		var x := viewport_size.x * float(i) / 24.0
		var wave := sin(bg_time * 2.2 + float(i) * 0.6) * 8.0
		points.append(Vector2(x, base_y + wave))
	points.append(Vector2(viewport_size.x, viewport_size.y))
	acid_surface.polygon = points
	acid_surface.color = Color(0.22, 0.72, 0.20, 0.9)


func build_main_page() -> void:
	main_page = create_page()
	add_heading(main_page, "JELLY ASCENT", 46)
	add_subheading(main_page, "CLIMB THE TOWER", 15)
	add_spacer(main_page, 12)
	add_menu_button(main_page, "START ASCENT", func(): get_tree().change_scene_to_file(LEVEL_SCENE), true)
	add_menu_button(main_page, "TUTORIAL", func(): show_page(tutorial_page))
	add_menu_button(main_page, "LEADERBOARD", func(): show_leaderboard())
	add_menu_button(main_page, "QUIT", func(): get_tree().quit())


func build_tutorial_page() -> void:
	tutorial_page = create_page()
	add_heading(tutorial_page, "FIELD NOTES", 34)
	add_subheading(tutorial_page, "REACH THE NEXT LEDGE", 14)
	add_spacer(tutorial_page, 10)
	var instructions := Label.new()
	instructions.text = "A / D or arrows    Move and build momentum\nS or Down             Fast drop\nSpace                   Test jump\nP or Esc               Pause\n\nBounce upward through platforms from below.\nLand on top to launch again. Reach higher ground\nbefore the rising acid catches you."
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 17)
	tutorial_page.add_child(instructions)
	add_spacer(tutorial_page, 12)
	add_menu_button(tutorial_page, "BACK", func(): show_page(main_page))


func build_leaderboard_page() -> void:
	leaderboard_page = create_page()
	add_heading(leaderboard_page, "HIGH ASCENTS", 34)
	add_subheading(leaderboard_page, "LOCAL TOP 10", 14)
	add_spacer(leaderboard_page, 8)
	leaderboard_rows = VBoxContainer.new()
	leaderboard_rows.add_theme_constant_override("separation", 8)
	leaderboard_page.add_child(leaderboard_rows)
	add_spacer(leaderboard_page, 8)
	add_menu_button(leaderboard_page, "BACK", func(): show_page(main_page))


func create_page() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.12, 0.14, 0.94)
	panel_style.border_color = Color(0.38, 0.82, 0.68)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 30
	panel_style.content_margin_right = 30
	panel_style.content_margin_top = 28
	panel_style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	panel.add_child(page)
	return page


func add_heading(page: Control, text: String, font_size: int) -> void:
	var heading := Label.new()
	heading.text = text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", font_size)
	heading.add_theme_color_override("font_color", Color(0.46, 0.92, 0.75))
	page.add_child(heading)


func add_subheading(page: Control, text: String, font_size: int) -> void:
	var subheading := Label.new()
	subheading.text = text
	subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subheading.add_theme_font_size_override("font_size", font_size)
	subheading.add_theme_color_override("font_color", Color(0.77, 0.89, 0.85))
	page.add_child(subheading)


func add_spacer(page: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	page.add_child(spacer)


func add_menu_button(page: Control, text: String, action: Callable, primary := false) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 16)
	button.focus_mode = Control.FOCUS_ALL
	if primary:
		button.add_theme_color_override("font_color", Color(0.04, 0.12, 0.13))
		button.add_theme_stylebox_override("normal", create_button_style(Color(0.46, 0.92, 0.75)))
		button.add_theme_stylebox_override("hover", create_button_style(Color(0.62, 1.0, 0.85)))
	else:
		button.add_theme_stylebox_override("normal", create_button_style(Color(0.12, 0.28, 0.29)))
		button.add_theme_stylebox_override("hover", create_button_style(Color(0.18, 0.4, 0.38)))
	button.pressed.connect(action)
	page.add_child(button)


func create_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func show_page(page: Control) -> void:
	for candidate in [main_page, tutorial_page, leaderboard_page]:
		if candidate != null:
			candidate.get_parent().get_parent().visible = candidate == page


func show_leaderboard() -> void:
	for child in leaderboard_rows.get_children():
		child.queue_free()

	var loading_label := Label.new()
	loading_label.text = "Loading global leaderboard..." if LEADERBOARD_STORE.is_global_available() else "Loading leaderboard..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leaderboard_rows.add_child(loading_label)

	call_deferred("_refresh_leaderboard_async")
	show_page(leaderboard_page)


func _refresh_leaderboard_async() -> void:
	var entries: Array[Dictionary] = []
	if LEADERBOARD_STORE.is_global_available():
		entries = await LEADERBOARD_STORE.fetch_global_entries()
	if entries.is_empty():
		entries = LEADERBOARD_STORE.load_entries()

	if not is_instance_valid(self) or not is_instance_valid(leaderboard_rows):
		return

	for child in leaderboard_rows.get_children():
		child.queue_free()

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No ascents recorded yet"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		leaderboard_rows.add_child(empty_label)
	else:
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var row := Label.new()
			var rank := int(entry.get("rank", index + 1))
			row.text = "%02d  %s  %d pts  %d m  x%d" % [
				rank,
				str(entry.get("name", "JELLY")),
				int(entry.get("score", 0)),
				int(entry.get("height_meters", 0)),
				int(entry.get("combo", 0)),
			]
			row.add_theme_font_size_override("font_size", 15)
			leaderboard_rows.add_child(row)
