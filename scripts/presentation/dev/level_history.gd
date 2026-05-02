class_name LevelHistory
extends RefCounted
## Snapshot-based undo/redo stack for the map editor. Each snapshot is the
## full LevelData serialized via to_dict() + var_to_bytes — small enough
## (~few KB per 25×25 map) that we don't bother with command-pattern deltas
## for jam scope. Stack capped at MAX_DEPTH; oldest dropped when exceeded.
##
## Two operation flavours:
##   begin_transaction(level) ... end_transaction(level) — for drag-paint
##     series. Baseline is captured once at begin; only pushed at end if
##     anything actually changed (no-op drags don't pollute the stack).
##   push(level) — single-shot mutations (RMB delete, replace_all, load,
##     tileset switch). Capture current state BEFORE applying the mutation.
##
## Any push (transactional or single-shot) clears the redo stack.
##
## Restore: undo(current_level) and redo(current_level) return the
## fully-deserialized LevelData. Caller is responsible for triggering a
## visual redraw after assigning the returned object back to its _level var.

const MAX_DEPTH: int = 50

var _undo: Array[PackedByteArray] = []
var _redo: Array[PackedByteArray] = []

var _txn_baseline: PackedByteArray = PackedByteArray()
var _txn_open: bool = false


# ── Transaction API ────────────────────────────────────────────────────────

func begin_transaction(level: LevelData) -> void:
	if _txn_open:
		# Defensive: previous transaction was never closed (likely lost LMB
		# release event). Discard the dangling baseline and restart.
		_txn_open = false
	_txn_baseline = _serialize(level)
	_txn_open = true


func end_transaction(level: LevelData) -> void:
	if not _txn_open:
		return
	_txn_open = false
	var current: PackedByteArray = _serialize(level)
	if current == _txn_baseline:
		return  # no-op transaction (clicked but didn't paint anything)
	_push_undo(_txn_baseline)
	_redo.clear()


# ── Single-shot API ────────────────────────────────────────────────────────

## Capture current state BEFORE the mutation. Caller mutates `level` after.
func push(level: LevelData) -> void:
	if _txn_open:
		# Inside a transaction — ignore single-shot pushes; the baseline
		# already covers everything until end_transaction.
		return
	_push_undo(_serialize(level))
	_redo.clear()


# ── Query / restore ────────────────────────────────────────────────────────

func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Pop the latest undo snapshot, push current state to redo, return restored
## LevelData. Caller assigns it back and redraws.
func undo(current: LevelData) -> LevelData:
	if _undo.is_empty():
		return current
	_redo.append(_serialize(current))
	if _redo.size() > MAX_DEPTH:
		_redo.pop_front()
	var snap: PackedByteArray = _undo.pop_back()
	return _deserialize(snap)


func redo(current: LevelData) -> LevelData:
	if _redo.is_empty():
		return current
	_push_undo(_serialize(current))
	var snap: PackedByteArray = _redo.pop_back()
	return _deserialize(snap)


# ── Internals ──────────────────────────────────────────────────────────────

func _push_undo(snap: PackedByteArray) -> void:
	_undo.append(snap)
	if _undo.size() > MAX_DEPTH:
		_undo.pop_front()


static func _serialize(level: LevelData) -> PackedByteArray:
	return var_to_bytes(level.to_dict())


static func _deserialize(snap: PackedByteArray) -> LevelData:
	var d: Variant = bytes_to_var(snap)
	if not (d is Dictionary):
		return LevelData.new()
	var ld: LevelData = LevelData.from_dict(d)
	return ld if ld != null else LevelData.new()
