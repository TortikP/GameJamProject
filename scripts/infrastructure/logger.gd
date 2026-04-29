class_name Logger
extends RefCounted
## Logger — stateless tagged logging utility.
##
## Used as a static utility, not an autoload. Calling `Logger.info(...)`
## resolves to a static method on the class, which Godot 4's parser handles
## reliably (autoload references hit type-resolution bugs — see Known Godot
## 4.6 traps in CLAUDE.md).
##
## Usage:
##   Logger.info("Battle", "spell resolved")
##   Logger.warn("AudioDirector", "no clip for %s" % id)

enum Level { DEBUG, INFO, WARN, ERROR }


static func _log(level: int, tag: String, msg: String) -> void:
	var prefix := "[%s][%s]" % [Level.keys()[level], tag]
	print("%s %s" % [prefix, msg])


static func debug(tag: String, msg: String) -> void: _log(Level.DEBUG, tag, msg)
static func info(tag: String, msg: String) -> void: _log(Level.INFO, tag, msg)
static func warn(tag: String, msg: String) -> void: _log(Level.WARN, tag, msg)
static func error(tag: String, msg: String) -> void: _log(Level.ERROR, tag, msg)
