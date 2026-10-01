extends Control


const LEVEL_SCENE := "res://Scenes/Level_1.tscn"
const LEADERBOARD_STORE = preload("res://Scenes/local_leaderboard.gd")

var main_page: Control
var tutorial_page: Control
var leaderboard_page: Control
var leaderboard_rows: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_background()
	build_main_page()
	build_tutorial_page()
	build_leaderboard_page()
	show_page(main_page)


func build_background() -> void:
	var background := ColorRect.new()
	background.color = Color(0.035, 0.12, 0.14)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var horizon := Polygon2D.new()
	horizon.polygon = PackedVector2Array([
		Vector2(0, 510), Vector2(1152, 410), Vector2(1152, 648), Vector2(0, 648),
	])
	horizon.color = Color(0.07, 0.2, 0.2)
	add_child(horizon)


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


func add_heading(page: Control, text: String, size: int) -> void:
	var heading := Label.new()
	heading.text = text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", size)
	heading.add_theme_color_override("font_color", Color(0.46, 0.92, 0.75))
	page.add_child(heading)


func add_subheading(page: Control, text: String, size: int) -> void:
	var subheading := Label.new()
	subheading.text = text
	subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subheading.add_theme_font_size_override("font_size", size)
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

	var entries := LEADERBOARD_STORE.load_entries()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No ascents recorded yet"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		leaderboard_rows.add_child(empty_label)
	else:
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var row := Label.new()
			row.text = "%02d     %8d pts     %4d m     x%d" % [index + 1, int(entry.get("score", 0)), int(entry.get("height_meters", 0)), int(entry.get("combo", 0))]
			row.add_theme_font_size_override("font_size", 15)
			leaderboard_rows.add_child(row)
	show_page(leaderboard_page)
