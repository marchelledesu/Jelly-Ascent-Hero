extends CanvasLayer
class_name DevTools

signal platform_requested(platform_type: int)
signal biome_requested(biome_index: int)
signal reset_biome_requested
signal launch_requested
signal wall_bounce_requested
signal combo_requested
signal stored_bonus_requested
signal end_run_requested

var controller: Node
var command_input: LineEdit
var command_hint: Label
var tools_panel: PanelContainer


func setup(level_controller: Node) -> void:
	controller = level_controller
	build_ui()


func build_ui() -> void:
	command_input = LineEdit.new()
	command_input.name = "DevCommandInput"
	command_input.placeholder_text = "Type /dev and press Enter"
	command_input.max_length = 16
	command_input.visible = false
	command_input.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	command_input.position = Vector2(-150.0, -64.0)
	command_input.size = Vector2(300.0, 36.0)
	command_input.text_submitted.connect(_on_command_submitted)
	add_child(command_input)

	command_hint = Label.new()
	command_hint.text = "Enter /dev to open developer tools"
	command_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	command_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	command_hint.position = Vector2(-170.0, -90.0)
	command_hint.size = Vector2(340.0, 24.0)
	add_child(command_hint)

	tools_panel = build_tools_panel()
	add_child(tools_panel)
	tools_panel.visible = false


func build_tools_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "DeveloperTools"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -332.0
	panel.offset_top = 18.0
	panel.offset_right = -18.0
	panel.offset_bottom = 0.0
	panel.custom_minimum_size.x = 314.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.07, 0.075, 0.96)
	panel_style.border_color = Color(0.46, 0.92, 0.75, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", panel_style)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(290.0, 560.0)
	panel.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "DEVELOPER TEST TOOLS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.46, 0.92, 0.75))
	header.add_child(title)
	add_tool_button(header, "CLOSE", func(): toggle_tools())

	add_section_title(content, "PLATFORMS")
	var platform_grid := GridContainer.new()
	platform_grid.columns = 2
	content.add_child(platform_grid)
	add_platform_button(platform_grid, "Standard", 0)
	add_platform_button(platform_grid, "Super-Trampoline", 1)
	add_platform_button(platform_grid, "Slingshot Ramp", 2)
	add_platform_button(platform_grid, "Fragile", 3)
	add_platform_button(platform_grid, "Sticky Dough", 4)

	add_section_title(content, "BIOME CONDITIONS")
	var biome_grid := GridContainer.new()
	biome_grid.columns = 2
	content.add_child(biome_grid)
	add_biome_button(biome_grid, "Standard Tower", 0)
	add_biome_button(biome_grid, "Gale-Force Winds", 1)
	add_biome_button(biome_grid, "Frosted Peaks", 2)
	add_biome_button(biome_grid, "Crushing Abyss", 3)
	add_tool_button(content, "Return to altitude biome", func(): reset_biome_requested.emit())

	add_section_title(content, "PLAYER & SCORING")
	add_tool_button(content, "Test upward jump", func(): launch_requested.emit())
	add_tool_button(content, "Test wall bounce", func(): wall_bounce_requested.emit())
	add_tool_button(content, "Add 10 combo points", func(): combo_requested.emit())
	add_tool_button(content, "Grant stored jump bonus", func(): stored_bonus_requested.emit())

	add_section_title(content, "RUN FLOW")
	add_tool_button(content, "End run (score/name/leaderboard)", func(): end_run_requested.emit())
	return panel


func add_section_title(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.58, 0.78, 0.78))
	container.add_child(label)


func add_platform_button(container: GridContainer, text: String, platform_type: int) -> void:
	add_tool_button(container, text, _emit_platform_requested.bind(platform_type))


func add_biome_button(container: GridContainer, text: String, biome_index: int) -> void:
	add_tool_button(container, text, _emit_biome_requested.bind(biome_index))


func add_tool_button(container: Container, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 32.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	container.add_child(button)


func _emit_platform_requested(platform_type: int) -> void:
	platform_requested.emit(platform_type)


func _emit_biome_requested(biome_index: int) -> void:
	biome_requested.emit(biome_index)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not is_instance_valid(controller) or bool(controller.get("game_over")) or controller.get_tree().paused:
		return
	if event.keycode != KEY_SLASH and event.unicode != 47:
		return
	command_input.text = "/"
	command_input.visible = true
	command_hint.text = "Type /dev and press Enter"
	command_input.caret_column = command_input.text.length()
	command_input.grab_focus()
	get_viewport().set_input_as_handled()


func _on_command_submitted(command: String) -> void:
	command_input.release_focus()
	command_input.visible = false
	if command.strip_edges().to_lower() == "/dev":
		toggle_tools()
	else:
		command_hint.text = "Unknown command. Type /dev to open developer tools"


func toggle_tools() -> void:
	tools_panel.visible = not tools_panel.visible
	command_hint.visible = not tools_panel.visible
