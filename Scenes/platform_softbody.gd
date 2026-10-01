extends SoftBody2D


func _ready() -> void:
	pass


func initialize_for_platform() -> void:
	create_softbody2d(true)
	_update_vars()
