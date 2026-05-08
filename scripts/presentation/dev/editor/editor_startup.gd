class_name EditorStartup
extends RefCounted

## One-shot startup flow for the level editor: handoff from Game Editor,
## autosave-restore prompt, multi-wave warning. Pulled out of
## EditorController (Φ-6 of 060) to fit the controller's 300-line cap
## (AC33). All methods are static — no instance state.
##
## ## Flow
##
## 1. ActiveLevel.has_queued() → load that map (Game Editor handoff path).
##    Multi-wave maps emit a warn toast (AC37) — full wave editor is 061.
## 2. Else, check_autosave_on_ready: prompt_needed → ConfirmModal.
##    Yes → load __autosave__.json. No / no modal → clear and start fresh.
## 3. Else, blank slate (refresh empty grid).
##
## Returns the LevelData the controller should adopt as `_level`. The
## controller's _meta_panel.set_level_name and _io.refresh_grid_from_level
## are called as side-effects through _apply / _toast helpers — the
## controller doesn't need to do that bookkeeping itself.


## Entry point. Awaits the prompt path if reached. Returns the level
## the controller should adopt — never null (falls back to the supplied
## blank `level` if every load path fails).
static func run(io: EditorIO, level: LevelData, meta_panel: Node,
		confirm_modal: Node, tree: SceneTree) -> LevelData:
	if ActiveLevel.has_queued():
		return _load_queued(io, level, meta_panel)
	var info := io.check_autosave_on_ready()
	if info["prompt_needed"]:
		return await _prompt_restore(io, level, meta_panel, confirm_modal,
			tree, int(info["age_sec"]))
	io.refresh_grid_from_level(level)
	return level


static func _load_queued(io: EditorIO, fallback: LevelData,
		meta_panel: Node) -> LevelData:
	var path: String = ActiveLevel.consume()
	var loaded := io.load_from(path)
	if loaded == null:
		_toast("Load FAILED for queued path: " + path, &"error")
		io.refresh_grid_from_level(fallback)
		return fallback
	_apply(io, loaded, meta_panel)
	if loaded.waves.size() > 1:
		_toast(Localization.tf("ui_level_editor_multi_wave_warning",
			[str(loaded.waves.size())],
			"Multi-wave map (%s waves) loaded. Editing affects wave 0 only — full wave editor in 061."), &"warn")
	return loaded


static func _prompt_restore(io: EditorIO, fallback: LevelData,
		meta_panel: Node, confirm_modal: Node, tree: SceneTree,
		age_sec: int) -> LevelData:
	if confirm_modal == null:
		io.clear_autosave()
		io.refresh_grid_from_level(fallback)
		return fallback
	await tree.process_frame  # R6: settle ConfirmModal before .ask
	var minutes := int(age_sec / 60.0)
	var confirmed: bool = await confirm_modal.ask(
		Localization.t("ui_level_editor_autosave_restore_title", "Restore unsaved work?"),
		Localization.tf("ui_level_editor_autosave_restore_body", [str(minutes)],
			"Found unsaved work from %s minutes ago. Restore?"),
		Localization.t("ui_level_editor_autosave_restore_yes", "Restore"),
		Localization.t("ui_level_editor_autosave_restore_no", "Discard"))
	if confirmed:
		var loaded := io.load_from(EditorIO.AUTOSAVE_PATH)
		if loaded != null:
			_apply(io, loaded, meta_panel)
			return loaded
	io.clear_autosave()
	io.refresh_grid_from_level(fallback)
	return fallback


static func _apply(io: EditorIO, loaded: LevelData, meta_panel: Node) -> void:
	if meta_panel != null and meta_panel.has_method("set_level_name"):
		meta_panel.set_level_name(loaded.name)
	io.refresh_grid_from_level(loaded)


static func _toast(text: String, level: StringName) -> void:
	if EventBus != null:
		EventBus.ui_toast_requested.emit(text, 0.0, level)
