extends HBoxContainer
## ChoiceButtonRow — horizontal row of buttons, one per choice. Click → emit
## choice_picked(index).
##
## Extracted from dialogue_panel._show_choices() for reuse outside dialogue
## (run-summary "play again", confirm modals etc.). DialoguePanel stays
## working as-is — when DialogueManager wires the new component, swap there.

signal choice_picked(index: int)


func _ready() -> void:
	add_theme_constant_override("separation", UiTheme.SP_3)


## Replace the row contents with buttons for each label. Pressing button i
## emits choice_picked(i). Existing buttons are freed.
func set_choices(labels: Array[String]) -> void:
	clear_choices()
	for i in labels.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.focus_mode = Control.FOCUS_ALL
		UiTheme.apply_button_styling(btn)
		var idx := i
		btn.pressed.connect(func(): choice_picked.emit(idx))
		add_child(btn)


func clear_choices() -> void:
	for c in get_children():
		c.queue_free()
