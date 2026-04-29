extends Node
## Logger — simple tagged logging. Wraps `print()` with level + tag.
##
## Usage:
##   Logger.info("Battle", "spell resolved")
##   Logger.warn("AudioDirector", "no clip for %s" % id)

enum Level { DEBUG, INFO, WARN, ERROR }


func log(level: int, tag: String, msg: String) -> void:
	var prefix := "[%s][%s]" % [Level.keys()[level], tag]
	print("%s %s" % [prefix, msg])


func debug(tag: String, msg: String) -> void: log(Level.DEBUG, tag, msg)
func info(tag: String, msg: String) -> void: log(Level.INFO, tag, msg)
func warn(tag: String, msg: String) -> void: log(Level.WARN, tag, msg)
func error(tag: String, msg: String) -> void: log(Level.ERROR, tag, msg)
