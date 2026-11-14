class_name ConfigData
extends RefCounted
## Loads tunables from res://config/*.json. All gameplay numbers live there.

const CONFIG_DIR := "res://config/"


static func load_file(name: String) -> Dictionary:
	var path := CONFIG_DIR + name + ".json"
	assert(FileAccess.file_exists(path), "Missing config file: " + path)
	var text := FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "Empty config file: " + path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "Config file is not a JSON object: " + path)
	return parsed as Dictionary
