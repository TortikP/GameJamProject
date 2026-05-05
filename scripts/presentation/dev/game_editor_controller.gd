extends Control
## game_editor — UI for composing existing maps into a "game" (linear
## campaign). Spec 035-game-editor §2.
##
## Edits a single GameData in memory; persists via GameSerializer. Two side
## paths: explicit Save → user-named file in data/games/, autosave →
## __autosave_game__.game.json (recovery on next entry).

const ROW_SCENE: PackedScene = preload("res://scenes/dev/game_editor_level_row.tscn")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const MAPS_DIR: String = "res://data/maps/"
const GAMES_DIR: String = "res://data/games/"
const AUTOSAVE_NAME: String = "__autosave_game__.game.json"
const PLAYTEST_NAME: String = "__playtest_game__.game.json"
const AUTOSAVE_PATH: String = GAMES_DIR + AUTOSAVE_NAME
const PLAYTEST_PATH: String = GAMES_DIR + PLAYTEST_NAME
const AUTOSAVE_DEBOUNCE_SEC: float = 1.5
const AUTOSAVE_MAX_AGE_HOURS: int = 24

@onready var _name_input: LineEdit = $Margin/VBox/Header/NameInput
@onready var _save_btn: Button = $Margin/VBox/Header/SaveButton
@onready var _load_btn: Button = $Margin/VBox/Header/LoadButton
@onready var _playtest_btn: Button = $Margin/VBox/Header/PlaytestButton
@onready var _exit_btn: Button = $Margin/VBox/Header/ExitButton
@onready var _level_list: VBoxContainer = $Margin/VBox/Scroll/LevelList
@onready var _add_btn: Button = $Margin/VBox/AddLevelButton
@onready var _save_dialog: FileDialog = $SaveFileDialog
@onready var _load_dialog: FileDialog = $LoadFileDialog
@onready var _confirm_modal: Node = $ConfirmModal
@onready var _toast_layer: Node = $ToastLayer

var _game: GameData = null
var _map_paths: Array[String] = []
var _current_path: String = ""
var _dirty: bool = false
var _autosave_timer: Timer
# When true, mutator paths skip the autosave trigger (used during bulk
# re-bind so we don't fire 1 autosave per row in a list rebuild).
var _suppress_autosave: bool = false


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)

	_save_btn.pressed.connect(_on_save)
	_load_btn.pressed.connect(_on_load)
	_playtest_btn.pressed.connect(_on_playtest)
	_exit_btn.pressed.connect(_on_exit)
	_add_btn.pressed.connect(_on_add_level)
	_name_input.text_changed.connect(_on_name_changed)

	_save_dialog.file_selected.connect(_on_save_file_selected)
	_load_dialog.file_selected.connect(_on_load_file_selected)

	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DEBOUNCE_SEC
	_autosave_timer.timeout.connect(_do_autosave)
	add_child(_autosave_timer)

	_map_paths = _list_map_files()
	_game = GameData.new()

	# 035 v1.1 — when returning from Map Editor (the user clicked "Edit" on a
	# row earlier), reload the same game file. Skips the autosave-restore
	# prompt: this isn't a recovery, it's an explicit navigation return.
	if ActiveGame.has_queued_for_editor():
		var return_path: String = ActiveGame.consume_queued_for_editor()
		var loaded: GameData = GameSerializer.load_from(return_path)
		if loaded != null:
			_game = loaded
			# Don't promote the autosave path to a "real" current_path —
			# next Save would silently overwrite the autosave file.
			_current_path = "" if return_path == AUTOSAVE_PATH else return_path
			_dirty = false
		else:
			# Loading the return file failed — fall through to normal init,
			# leaving the user with an empty row to start over.
			_game.add_level(GameData.make_level_entry("", "", &"", true))
		_rebuild_rows()
		_name_input.text = _game.name
		return

	# Try to restore from autosave, else start with one empty row.
	if not await _try_restore_autosave():
		_game.add_level(GameData.make_level_entry("", "", &"", true))
	_rebuild_rows()
	_name_input.text = _game.name


func _apply_theme() -> void:
	for btn in [_save_btn, _load_btn, _playtest_btn, _exit_btn, _add_btn]:
		UiTheme.apply_button_styling(btn)


func _unhandled_input(event: InputEvent) -> void:
	# Esc → exit (with dirty check). Mirrors map editor.
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_exit()


# ── Map listing ─────────────────────────────────────────────────────────────

func _list_map_files() -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		return out
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			# Hide editor scratch files.
			if fname != "__autosave__.json" and fname != "__playtest__.json":
				out.append(MAPS_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# ── List rendering ──────────────────────────────────────────────────────────

func _rebuild_rows() -> void:
	_suppress_autosave = true
	# Clear existing rows.
	for child in _level_list.get_children():
		child.queue_free()
	# Re-add. Need to wait one frame for queue_free to complete? — _ready of
	# new rows fires before next frame so binding inline works.
	for i: int in range(_game.levels.size()):
		var row: PanelContainer = ROW_SCENE.instantiate()
		_level_list.add_child(row)
		row.bind(_map_paths, _game.levels[i], i)
		row.removed.connect(_on_row_removed.bind(row))
		row.moved_up.connect(_on_row_moved_up.bind(row))
		row.moved_down.connect(_on_row_moved_down.bind(row))
		row.changed.connect(_mark_dirty)
		row.intro_toggled.connect(_on_intro_toggled.bind(row))
		row.edit_requested.connect(_on_row_edit_requested.bind(row))
	_suppress_autosave = false


func _row_index(row: PanelContainer) -> int:
	return _level_list.get_children().find(row)


# ── Row operations ──────────────────────────────────────────────────────────

func _on_add_level() -> void:
	_game.add_level(GameData.make_level_entry("", "", &"", false))
	_rebuild_rows()
	_mark_dirty()


func _on_row_removed(row: PanelContainer) -> void:
	var idx: int = _row_index(row)
	if idx < 0:
		return
	if _game.levels.size() <= 1:
		_toast(Localization.t("ui_game_editor_only_level_blocked", "Cannot remove the only level"), &"warn")
		return
	_game.remove_at(idx)
	_rebuild_rows()
	_mark_dirty()


func _on_row_moved_up(row: PanelContainer) -> void:
	var idx: int = _row_index(row)
	if idx <= 0:
		return
	_game.swap(idx, idx - 1)
	_rebuild_rows()
	_mark_dirty()


func _on_row_moved_down(row: PanelContainer) -> void:
	var idx: int = _row_index(row)
	if idx < 0 or idx >= _game.levels.size() - 1:
		return
	_game.swap(idx, idx + 1)
	_rebuild_rows()
	_mark_dirty()


func _on_row_edit_requested(row: PanelContainer) -> void:
	# 035 v1.1 — open the row's map in the Map Editor and queue this game
	# file for return when the user exits Map Editor.
	var idx: int = _row_index(row)
	if idx < 0:
		return
	var entry: Dictionary = _game.levels[idx]
	var map_path: String = String(entry.get("map_path", ""))
	if map_path == "":
		_toast(Localization.t("ui_game_editor_pick_map_first", "Pick a map first"), &"warn")
		return
	if not FileAccess.file_exists(map_path):
		_toast(Localization.tf("ui_game_editor_map_file_missing", [map_path.get_file()], "Map file missing: %s"), &"error")
		return
	# Persist current state so we can restore it on return. If the user has
	# never saved the game, this writes to the autosave path — load on return
	# will pick that up.
	var save_path: String = _current_path
	if save_path == "":
		save_path = AUTOSAVE_PATH
	if not GameSerializer.save(_game, save_path):
		_toast(Localization.t("ui_game_editor_save_navigation_failed", "Save failed; aborting navigation"), &"error")
		return
	_dirty = false
	# Order matters: queue map first (Map Editor's _ready reads ActiveLevel),
	# then mark return path (Map Editor's Exit reads ActiveGame),
	# then change scene.
	ActiveLevel.queue(map_path)
	ActiveGame.queue_for_editor(save_path)
	get_tree().change_scene_to_file("res://scenes/dev/map_editor.tscn")


func _on_intro_toggled(pressed: bool, row: PanelContainer) -> void:
	var idx: int = _row_index(row)
	if idx < 0:
		return
	if pressed:
		# Exclusive: clear all others. set_intro mutates the dicts the rows
		# already hold references to; we just need rows to refresh their
		# checkbox visuals.
		_game.set_intro(idx)
		_refresh_intro_checkboxes()
	# (If user unchecked — we just leave that level without intro flag;
	# they can manually set another or none.)
	_mark_dirty()


func _refresh_intro_checkboxes() -> void:
	# Push checkbox state back from data → UI for every row, without firing
	# toggled. Cheaper than full rebuild.
	for i: int in range(_level_list.get_child_count()):
		var row = _level_list.get_child(i)
		var check: CheckBox = row.get_node("HBox/IntroCheck")
		check.set_pressed_no_signal(bool(_game.levels[i].get("is_intro", false)))


# ── Name field ──────────────────────────────────────────────────────────────

func _on_name_changed(new_text: String) -> void:
	_game.name = new_text
	_mark_dirty()


# ── Save / Load / Playtest / Exit ───────────────────────────────────────────

func _on_save() -> void:
	# Validate first; show warns as toasts but proceed if no REJECT.
	var msgs: Array[String] = _game.validate()
	for m: String in msgs:
		if m.begins_with("REJECT"):
			_toast(m, &"error")
			return
		else:
			_toast(m, &"warn")
	# Need to rebuild rows because validate() may have dropped invalid entries.
	_rebuild_rows()

	var initial: String = _current_path
	if initial == "":
		initial = GameSerializer.default_path_for(_game)
	_save_dialog.current_dir = GAMES_DIR
	_save_dialog.current_path = initial
	_save_dialog.popup_centered_ratio(0.6)


func _on_save_file_selected(path: String) -> void:
	# Force .game.json extension if user typed plain.
	if not path.ends_with(".game.json"):
		if path.ends_with(".json"):
			path = path.substr(0, path.length() - 5) + ".game.json"
		else:
			path += ".game.json"
	# Overwrite confirm
	if FileAccess.file_exists(path):
		var ok: bool = await _confirm_modal.ask(
			Localization.t("ui_game_editor_overwrite_title", "Overwrite?"),
			Localization.tf("ui_game_editor_overwrite_body", [path.get_file()], "%s already exists.\n\nReplace it?"),
			Localization.t("ui_game_editor_overwrite_confirm", "Overwrite"),
			Localization.t("ui_common_cancel", "Cancel"),
			true
		)
		if not ok:
			return
	if GameSerializer.save(_game, path):
		_current_path = path
		_dirty = false
		_toast(Localization.tf("ui_game_editor_saved", [path.get_file()], "Saved: %s"), &"success")
	else:
		_toast(Localization.t("ui_game_editor_save_failed", "Save failed (see log)"), &"error")


func _on_load() -> void:
	if _dirty:
		var ok: bool = await _confirm_modal.ask(
			Localization.t("ui_game_editor_unsaved_title", "Unsaved changes"),
			Localization.t("ui_game_editor_load_unsaved_body", "You have unsaved changes. Load another game and lose them?"),
			Localization.t("ui_game_editor_load_discard_confirm", "Discard & Load"),
			Localization.t("ui_common_cancel", "Cancel"),
			true
		)
		if not ok:
			return
	_load_dialog.current_dir = GAMES_DIR
	_load_dialog.popup_centered_ratio(0.6)


func _on_load_file_selected(path: String) -> void:
	var loaded: GameData = GameSerializer.load_from(path)
	if loaded == null:
		_toast(Localization.t("ui_game_editor_load_failed", "Load failed (see log)"), &"error")
		return
	_game = loaded
	_current_path = path
	_dirty = false
	_name_input.text = _game.name
	_rebuild_rows()
	_toast(Localization.tf("ui_game_editor_loaded", [path.get_file()], "Loaded: %s"), &"success")


func _on_playtest() -> void:
	# Validate; hard reject blocks playtest, warns proceed.
	var msgs: Array[String] = _game.validate()
	for m: String in msgs:
		if m.begins_with("REJECT"):
			_toast(m, &"error")
			return
	# Write a scratch playtest file (autosave path doesn't survive across
	# scene changes cleanly; explicit file is robust).
	if not GameSerializer.save(_game, PLAYTEST_PATH):
		_toast(Localization.t("ui_game_editor_playtest_write_failed", "Playtest write failed"), &"error")
		return
	if not ActiveGame.load_game(PLAYTEST_PATH):
		_toast(Localization.t("ui_game_editor_playtest_load_refused", "ActiveGame.load_game refused playtest file"), &"error")
		return
	get_tree().change_scene_to_file("res://scenes/dev/godmode.tscn")


func _on_exit() -> void:
	if _dirty:
		var ok: bool = await _confirm_modal.ask(
			Localization.t("ui_game_editor_unsaved_title", "Unsaved changes"),
			Localization.t("ui_game_editor_exit_unsaved_body", "Exit Game Editor and lose unsaved changes?"),
			Localization.t("ui_common_exit", "Exit"),
			Localization.t("ui_common_cancel", "Cancel"),
			true
		)
		if not ok:
			return
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ── Autosave ────────────────────────────────────────────────────────────────

func _mark_dirty() -> void:
	_dirty = true
	if _suppress_autosave:
		return
	_autosave_timer.start()  # restarts if already running (debounce)


func _do_autosave() -> void:
	if _game == null:
		return
	if not DirAccess.dir_exists_absolute(GAMES_DIR):
		DirAccess.make_dir_recursive_absolute(GAMES_DIR)
	# Don't validate before autosave — partial state is fine. The recovery
	# path will validate on load.
	GameSerializer.save(_game, AUTOSAVE_PATH)


func _try_restore_autosave() -> bool:
	if not FileAccess.file_exists(AUTOSAVE_PATH):
		return false
	# Skip if too old.
	var mod_time: int = FileAccess.get_modified_time(AUTOSAVE_PATH)
	var now: int = Time.get_unix_time_from_system()
	var age_hours: float = float(now - mod_time) / 3600.0
	if age_hours > AUTOSAVE_MAX_AGE_HOURS:
		return false

	# Wait one frame for the modal to be ready.
	await get_tree().process_frame
	var ok: bool = await _confirm_modal.ask(
		Localization.t("ui_game_editor_restore_title", "Restore session?"),
		Localization.t("ui_game_editor_restore_body", "An autosave from a previous Game Editor session was found.\nRestore it?"),
		Localization.t("ui_game_editor_restore_confirm", "Restore"),
		Localization.t("ui_game_editor_restore_discard", "Discard"),
		false
	)
	if not ok:
		# User declined → delete autosave so it doesn't pester next time.
		DirAccess.remove_absolute(AUTOSAVE_PATH)
		return false
	var loaded: GameData = GameSerializer.load_from(AUTOSAVE_PATH)
	if loaded == null:
		_toast(Localization.t("ui_game_editor_autosave_corrupt", "Autosave file corrupt; ignoring"), &"error")
		return false
	_game = loaded
	return true


# ── Toast helper ────────────────────────────────────────────────────────────

func _toast(text: String, level: StringName = &"info") -> void:
	# Strip REJECT/WARN prefix for cleaner UX; level conveys severity.
	var clean: String = text
	if clean.begins_with("REJECT: "):
		clean = clean.substr(8)
	elif clean.begins_with("WARN: "):
		clean = clean.substr(6)
	EventBus.ui_toast_requested.emit(clean, 2.5, level)
