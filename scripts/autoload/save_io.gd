## 存档读写（DECISIONS T15、ARCHITECTURE §4）。
## 只存状态，不存场景：读档是"按数据把世界重建一遍"，不是恢复节点树。
extends Node

const SAVE_VERSION := 1
const SAVE_PATH := "user://save_1.json"

signal saved(path: String)
signal loaded(data: Dictionary)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save(data: Dictionary) -> bool:
	data["save_version"] = SAVE_VERSION
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveIO: cannot open %s for writing (%d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	# 不压缩：可读的存档在灰盒阶段值这点体积。
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	saved.emit(SAVE_PATH)
	return true

## 读不出来时返回空字典，并且**不**删除玩家的存档——宁可报错也不要静默丢档。
func load_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_error("SaveIO: cannot open %s for reading" % SAVE_PATH)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveIO: save file is not a JSON object; refusing to load")
		return {}
	var data: Dictionary = parsed
	data = _migrate(data)
	if data.is_empty():
		return {}
	loaded.emit(data)
	return data

## 版本迁移（ARCHITECTURE §4.3）。现在只有 v1，但分支先留好：
## 存档格式一旦发出去就改不动了，迁移路径要从第一天就存在。
func _migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("save_version", 0))
	if v == SAVE_VERSION:
		return data
	if v > SAVE_VERSION:
		push_error("SaveIO: save is from a newer version (%d > %d); refusing to load" % [v, SAVE_VERSION])
		return {}
	# 将来：while v < SAVE_VERSION: data = _migrate_v{v}_to_v{v+1}(data); v += 1
	push_error("SaveIO: no migration path from version %d" % v)
	return {}

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
