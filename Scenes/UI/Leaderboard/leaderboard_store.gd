extends RefCounted


const TUNING = preload("res://Scenes/Gameplay/game_tuning.gd")
const SAVE_PATH := TUNING.SCORE_SAVE_PATH
const MAX_ENTRIES := TUNING.LEADERBOARD_MAX_ENTRIES
const HEIGHT_SCORE_PER_METER := TUNING.SCORE_HEIGHT_PER_METER
const COMBO_SCORE_PER_POINT := TUNING.SCORE_COMBO_PER_POINT


static func calculate_score(height_meters: int, combo_count: int) -> int:
	return height_meters * HEIGHT_SCORE_PER_METER + combo_count * COMBO_SCORE_PER_POINT


static func get_default_player_name() -> String:
	var entries := load_entries()
	if entries.is_empty():
		return "JELLY"
	return str(entries[0].get("name", "JELLY"))


static func load_entries() -> Array[Dictionary]:
	if not FileAccess.file_exists(SAVE_PATH):
		return []

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Array:
		return []

	var entries: Array[Dictionary] = []
	for item in parsed:
		if item is Dictionary:
			var entry: Dictionary = item.duplicate()
			var height_meters := maxi(0, int(entry.get("height_meters", 0)))
			var combo_count := maxi(0, int(entry.get("combo", 0)))
			entry["height_meters"] = height_meters
			entry["combo"] = combo_count
			entry["score"] = calculate_score(height_meters, combo_count)
			entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	return entries


static func submit_run(height_meters: int, combo_count: int, player_name: String) -> Dictionary:
	var score := calculate_score(height_meters, combo_count)
	var entry := {
		"name": player_name,
		"score": score,
		"height_meters": height_meters,
		"combo": combo_count,
		"date": Time.get_datetime_string_from_system(false, true),
	}
	var entries := load_entries()
	entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open local leaderboard for writing (error %d)." % FileAccess.get_open_error())
		entry["saved"] = false
		return entry

	file.store_string(JSON.stringify(entries, "\t"))
	var save_error := file.get_error()
	file.close()
	if save_error != OK:
		push_error("Failed to write local leaderboard (error %d)." % save_error)
		entry["saved"] = false
		return entry

	entry["saved"] = true
	return entry

const GLOBAL_BOARD_SLUG := "main"


static var _global_board_id: String = ""
static var _global_board_resolved: bool = false


static func _leadr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("Leadr"):
		return null
	return tree.root.get_node("Leadr")


static func is_global_available() -> bool:
	var leadr := _leadr()
	if leadr == null:
		return false
	return bool(leadr.call("is_initialized"))


static func _resolve_global_board_id() -> String:
	if _global_board_resolved:
		return _global_board_id
	_global_board_resolved = true
	var leadr := _leadr()
	if leadr == null or not bool(leadr.call("is_initialized")):
		return ""
	var result: Variant = await leadr.call("get_board", GLOBAL_BOARD_SLUG)
	if result == null or not bool(result.is_success):
		if result != null and result.error != null:
			push_warning("Could not resolve global leaderboard board '%s': %s" % [GLOBAL_BOARD_SLUG, str(result.error.message)])
		return ""
	var board: Variant = result.data
	if board == null:
		return ""
	_global_board_id = str(board.id)
	return _global_board_id


static func fetch_global_entries(limit: int = MAX_ENTRIES) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not is_global_available():
		return entries
	var leadr := _leadr()
	var board_id := await _resolve_global_board_id()
	if board_id.is_empty():
		return entries
	var result: Variant = await leadr.call("get_scores", board_id, limit)
	if result == null or not bool(result.is_success):
		if result != null and result.error != null:
			push_warning("Could not fetch global leaderboard: %s" % str(result.error.message))
		return entries
	var page: Variant = result.data
	if page == null:
		return entries
	for score in page.items:
		var height_meters := 0
		var combo := 0
		if score.metadata is Dictionary:
			height_meters = int(score.metadata.get("height_meters", 0))
			combo = int(score.metadata.get("combo", 0))
		var entry := {
			"name": str(score.player_name),
			"score": int(score.value),
			"height_meters": height_meters,
			"combo": combo,
			"rank": int(score.rank),
			"date": str(score.created_at),
			"global": true,
		}
		entries.append(entry)
	return entries


static func submit_global_run(height_meters: int, combo_count: int, player_name: String) -> Variant:
	if not is_global_available():
		return false
	var leadr := _leadr()
	var board_id := await _resolve_global_board_id()
	if board_id.is_empty():
		return false
	var score := calculate_score(height_meters, combo_count)
	var metadata := {"height_meters": height_meters, "combo": combo_count}
	var result: Variant = await leadr.call("submit_score", board_id, score, player_name, "", metadata)
	if result == null or not bool(result.is_success):
		if result != null and result.error != null:
			push_warning("Could not submit global score: %s" % str(result.error.message))
		return false
	return true

