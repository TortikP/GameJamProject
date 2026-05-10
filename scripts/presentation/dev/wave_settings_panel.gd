class_name WaveSettingsPanel
extends TabbedBasePanel

## WaveSettings (Spec 061 + tabbed rework). Hosts three section-tabs:
##   Q · Wave        — fields of the active wave (is_special, ttn, ...)
##   W · Skill Offer — post-wave skill offer config
##   E · Level       — level name + dialogue triggers CRUD (level-scoped)
##
## (Spawners had a tab through F-061-IMPL-5; removed post-smoke per UX
## feedback — only `timer` was a useful per-spawner field, moved to the
## SpawnerPalette as a single SpinBox applied to newly-placed spawners.
## `amount`/`delay` remain in schema but are not editable from UI.)
##
## The wave switcher (which wave is active) lives in a separate small
## WavePickerPanel — there's no room for a sticky switcher in the tab
## chrome, and a separate panel lets the designer tear it off too.
##
## All section signals bubble unchanged to EditorController via this hub
## so the controller doesn't need to know about the section split.

const WaveSection := preload("res://scripts/presentation/dev/wave_settings/wave_section.gd")
const SkillOfferSection := preload("res://scripts/presentation/dev/wave_settings/skill_offer_section.gd")
const LevelSection := preload("res://scripts/presentation/dev/wave_settings/level_section.gd")

# ── Re-emitted section signals (contract preserved from monolith) ───────────

signal wave_field_changed(idx: int, field: String, value: Variant)
signal trigger_created(trigger_dict: Dictionary)
signal trigger_updated(old_id: StringName, trigger_dict: Dictionary)
signal trigger_deleted(trigger_id: StringName)
signal skill_offer_changed(idx: int, offer: Variant)
signal skill_offer_preview_requested(idx: int)

var _level: LevelData = null
var _active_wave: int = 0

var _wave_section: WaveSettingsWaveSection
var _skill_offer_section: WaveSettingsSkillOfferSection
var _level_section: WaveSettingsLevelSection


func _ready() -> void:
	# super._ready() (TabbedBasePanel) sets up the tab bar, hides the title
	# label, etc. Tab content must be added AFTER it returns.
	super._ready()
	_build_tabs()


# ── Public API (preserved from monolith) ───────────────────────────────────

func bind_level(level: LevelData) -> void:
	_level = level
	if level != null:
		_active_wave = level.get_active_wave_index()
	for s in _all_sections():
		if s != null:
			s.bind_level(level)


func set_active_wave(idx: int) -> void:
	_active_wave = idx
	for s in _all_sections():
		if s != null and s.has_method("set_active_wave"):
			s.set_active_wave(idx)


## External call to focus a specific trigger by id — delegates to the
## Level section. Used when wave-mirror or other UI selects a trigger.
func select_trigger(tid: StringName) -> void:
	if _level_section != null:
		_level_section.select_trigger(tid)


# ── Build ───────────────────────────────────────────────────────────────────

func _build_tabs() -> void:
	_wave_section = WaveSection.new()
	_wave_section.wave_field_changed.connect(
		func(i: int, f: String, v: Variant) -> void:
			wave_field_changed.emit(i, f, v))
	add_tab(_wave_section, &"wave",
		&"ui_wavesettings_tab_wave", "Wave")

	_skill_offer_section = SkillOfferSection.new()
	_skill_offer_section.skill_offer_changed.connect(
		func(idx: int, offer: Variant) -> void:
			skill_offer_changed.emit(idx, offer))
	_skill_offer_section.skill_offer_preview_requested.connect(
		func(idx: int) -> void:
			skill_offer_preview_requested.emit(idx))
	add_tab(_skill_offer_section, &"skill_offer",
		&"ui_wavesettings_tab_skill_offer", "Skill Offer")

	_level_section = LevelSection.new()
	_level_section.trigger_created.connect(
		func(d: Dictionary) -> void: trigger_created.emit(d))
	_level_section.trigger_updated.connect(
		func(old_id: StringName, d: Dictionary) -> void:
			trigger_updated.emit(old_id, d))
	_level_section.trigger_deleted.connect(
		func(tid: StringName) -> void: trigger_deleted.emit(tid))
	add_tab(_level_section, &"level",
		&"ui_wavesettings_tab_level", "Level")


func _all_sections() -> Array[Node]:
	return [_wave_section, _skill_offer_section, _level_section]
