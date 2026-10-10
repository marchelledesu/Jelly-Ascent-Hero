extends RefCounted


const TUNING = preload("res://Scenes/game_tuning.gd")
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
