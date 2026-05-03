extends RefCounted
## SkillIconResolver — static helper for resolving Skill.icon (StringName) to
## Texture2D. Single source of truth so TelegraphHex, HexTooltip,
## EnemyDetailsPanel, and SkillOfferCard all hit the same lookup logic.
##
## Usage (no class_name, no autoload — explicit preload):
##   const SkillIconResolver = preload("res://scripts/presentation/skill_icon_resolver.gd")
##   var tex: Texture2D = SkillIconResolver.resolve(skill)
##
## Patterns from data/skills/*.json:
##   "res://full/path.png"          → loaded as-is
##   "icons/skills/foo.png"         → "res://assets/icons/skills/foo.png"
##   "skills/foo.png"               → "res://assets/skills/foo.png"
##   "" / null                      → null
##
## Returns null on any failure (skill null, icon empty, file missing, wrong
## type). Caller is responsible for deciding the fallback (letter draw, hide
## icon slot, etc.).


## Resolve a Skill's icon to a Texture2D, or null. Static.
## Duck-types `skill.icon` so legacy non-Skill inputs (`null`, bare Ability
## without `icon` field) return null safely.
static func resolve(skill) -> Texture2D:
	if skill == null or not "icon" in skill:
		return null
	var icon_str: String = String(skill.icon)
	if icon_str == "":
		return null
	var candidates: Array[String] = [
		icon_str if icon_str.begins_with("res://") else "",
		"res://assets/" + icon_str,
		"res://" + icon_str,
	]
	for path in candidates:
		if path == "":
			continue
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				return tex
	return null
