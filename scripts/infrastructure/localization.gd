extends Node
## Loads data/localization/*.json into Godot Translation resources.
##
## This keeps the editable source files simple (en.json / ru.json), while the
## game uses the normal Godot translation flow: TranslationServer + tr().

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const LOCALE_DIR := "res://data/localization/"
const DEFAULT_LOCALE := "en"

signal locale_changed(locale: String)

var _available_locales: Array[String] = []


func _ready() -> void:
	reload()
	var desired := _normalize_locale(TranslationServer.get_locale())
	if not _available_locales.has(desired):
		desired = DEFAULT_LOCALE
	set_locale(desired)


func reload() -> void:
	_available_locales.clear()
	var fallback_data := _load_locale_file(DEFAULT_LOCALE)
	var files := _find_locale_files()
	if not files.has(DEFAULT_LOCALE):
		files.push_front(DEFAULT_LOCALE)
	for locale in files:
		var data := _load_locale_file(locale)
		if data.is_empty() and locale != DEFAULT_LOCALE:
			continue
		_register_translation(locale, data, fallback_data)
	GameLogger.info("Localization", "loaded locales: %s" % str(_available_locales))


func set_locale(locale: String) -> void:
	var normalized := _normalize_locale(locale)
	if normalized == "":
		normalized = DEFAULT_LOCALE
	if not _available_locales.has(normalized):
		GameLogger.warn("Localization", "unknown locale '%s', using '%s'" % [locale, DEFAULT_LOCALE])
		normalized = DEFAULT_LOCALE
	TranslationServer.set_locale(normalized)
	locale_changed.emit(normalized)


func current_locale() -> String:
	return _normalize_locale(TranslationServer.get_locale())


func available_locales() -> Array:
	return _available_locales.duplicate()


func t(key_or_source: String, fallback: String = "") -> String:
	if key_or_source == "":
		return fallback
	var translated := String(TranslationServer.translate(StringName(key_or_source)))
	if translated == key_or_source and fallback != "":
		return fallback
	return translated


func tf(key_or_source: String, args: Array, fallback: String = "") -> String:
	return t(key_or_source, fallback) % args


func _register_translation(locale: String, data: Dictionary, fallback_data: Dictionary) -> void:
	var translation := Translation.new()
	translation.locale = locale
	var keys := {}
	for key in fallback_data.keys():
		keys[String(key)] = true
	for key in data.keys():
		keys[String(key)] = true

	for key in keys.keys():
		var source_text := String(fallback_data.get(key, ""))
		var translated_text := String(data.get(key, ""))
		if translated_text == "":
			translated_text = source_text if source_text != "" else key

		# Key-based lookup for data defs: tr("bush_name") -> "Bush".
		translation.add_message(StringName(key), StringName(translated_text))

		# Source-text lookup for ordinary Godot controls with text="Settings".
		# This lets scene files keep classic literal text and still auto-translate.
		if source_text != "" and source_text != key:
			translation.add_message(StringName(source_text), StringName(translated_text))

	TranslationServer.add_translation(translation)
	if not _available_locales.has(locale):
		_available_locales.append(locale)


func _find_locale_files() -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(LOCALE_DIR)
	if dir == null:
		GameLogger.warn("Localization", "locale dir not found: %s" % LOCALE_DIR)
		return files
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json") and not fname.begins_with("_"):
			files.append(fname.get_basename())
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


func _load_locale_file(locale: String) -> Dictionary:
	var path := LOCALE_DIR + locale + ".json"
	if not FileAccess.file_exists(path):
		GameLogger.warn("Localization", "missing locale file: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("Localization", "bad locale JSON: %s" % path)
		return {}
	return parsed as Dictionary


func _normalize_locale(locale: String) -> String:
	if locale == "":
		return ""
	var normalized := locale.replace("-", "_")
	return normalized.get_slice("_", 0)
