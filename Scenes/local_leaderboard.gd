extends RefCounted


const SAVE_PATH := "user://leaderboard.save"
const MAX_ENTRIES := 10


static func load_entries() -> Array[Dictionary]:
	if not FileAccess.file_exists(SAVE_PATH):
		return []

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Array:
		return []

	var entries: Array[Dictionary] = []
	for item in parsed:
		if item is Dictionary:
			entries.append(item)
	return entries


static func submit_run(height_meters: int, combo_count: int) -> Dictionary:
	var score := height_meters * 100 + combo_count * 25
	var entry := {
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
	if file != null:
		file.store_string(JSON.stringify(entries, "\t"))
	return entry
