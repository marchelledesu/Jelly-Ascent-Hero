extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != KEY_ESCAPE and event.keycode != KEY_P:
		return

	var controller := get_parent()
	if controller.has_method("toggle_pause"):
		controller.toggle_pause()
		get_viewport().set_input_as_handled()
