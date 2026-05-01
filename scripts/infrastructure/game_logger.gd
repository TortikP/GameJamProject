extends RefCounted
## GameLogger — stateless tagged logging utility.
##
## Renamed from Logger because that name collides with Godot's internal C++
## class `Logger` (core/io/logger.h) and the parser resolves to that, ignoring
## the user-defined version. Don't rename this back to Logger.
##
## Used via explicit preload (no class_name, no autoload):
##
##   const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
##   GameLogger.info("Battle", "spell resolved")

enum Level { DEBUG, INFO, WARN, ERROR }


static func _write(level: int, tag: String, msg: String) -> void:
	var prefix: String = "[%s][%s]" % [Level.keys()[level], tag]
	print("%s %s" % [prefix, msg])


static func debug(tag: String, msg: String) -> void:
	_write(Level.DEBUG, tag, msg)


static func info(tag: String, msg: String) -> void:
	_write(Level.INFO, tag, msg)


static func warn(tag: String, msg: String) -> void:
	_write(Level.WARN, tag, msg)


static func error(tag: String, msg: String) -> void:
	_write(Level.ERROR, tag, msg)
