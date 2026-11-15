extends Node
class_name MahdiaSaveManager

const SAVE_PATH := "user://mahdia_save.json"
const TEMP_PATH := "user://mahdia_save.tmp"
const BACKUP_PATH := "user://mahdia_save.bak"

static func save_progress(data: Dictionary) -> Error:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_PATH)
	var had_previous := FileAccess.file_exists(SAVE_PATH)
	if had_previous:
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.remove_absolute(backup_absolute)
		var backup_error := DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_absolute)
			return backup_error

	var result := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if result != OK:
		if had_previous and FileAccess.file_exists(BACKUP_PATH):
			DirAccess.rename_absolute(backup_absolute, save_absolute)
		return result
	return OK

static func load_progress() -> Dictionary:
	if FileAccess.file_exists(SAVE_PATH):
		var current := _read_dictionary(SAVE_PATH)
		if not current.is_empty():
			return current
	if FileAccess.file_exists(BACKUP_PATH):
		return _read_dictionary(BACKUP_PATH)
	return {}

static func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
