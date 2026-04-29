extends RefCounted
## Logger — stateless tagged logging utility.
##
## NOT registered as class_name (collides with internal Godot Logger class)
## and NOT registered as autoload (Godot 4 static analyzer bugs with both).
## Consumers preload this script explicitly:
##
##   const Logger = preload("res://scripts/infrastructure/logger.gd")
##   Logger.info("Battle", "spell resolved")

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
