extends VBoxContainer
## Teclado virtual navegável pelo controle (para senha de Wi-Fi etc.).
## Atalhos: X apaga, Y espaço, Start confirma, B cancela.

signal submitted(text: String)
signal cancelled

const LAYOUTS := {
	"lower": ["1234567890", "qwertyuiop", "asdfghjklç", "zxcvbnm-_."],
	"upper": ["1234567890", "QWERTYUIOP", "ASDFGHJKLÇ", "ZXCVBNM-_."],
	"symbols": ["!@#$%&*()=", "+[]{}<>/\\|", "'\";:,?~^`´", "áéíóúãõâêô"],
}

var secret := true
var _mode := "lower"
var _field: LineEdit
var _title: Label
var _keys_box: VBoxContainer
var _toggle_secret: Button


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_title = UiTheme.label("", 30, UiTheme.TEXT_DIM)
	add_child(_title)
	_field = LineEdit.new()
	_field.focus_mode = Control.FOCUS_NONE
	_field.editable = false
	_field.custom_minimum_size = Vector2(0, 76)
	add_child(_field)
	_keys_box = VBoxContainer.new()
	_keys_box.add_theme_constant_override("separation", 8)
	add_child(_keys_box)
	_build_keys()


func open(title: String, is_secret := true, initial := "") -> void:
	_title.text = title
	secret = is_secret
	_field.secret = secret
	_field.text = initial
	_mode = "lower"
	_build_keys()
	show()
	_focus_first.call_deferred()


func _focus_first() -> void:
	var row := _keys_box.get_child(1) as HBoxContainer
	if row and row.get_child_count() > 0:
		(row.get_child(0) as Control).grab_focus()


func _key(text: String, width := 92) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 76)
	b.add_theme_font_size_override("font_size", 32)
	return b


func _build_keys() -> void:
	if _keys_box == null:
		return
	for c in _keys_box.get_children():
		_keys_box.remove_child(c)
		c.queue_free()
	for row_text in LAYOUTS[_mode]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		for ch in row_text:
			var b := _key(ch)
			b.pressed.connect(_type.bind(ch))
			row.add_child(b)
		_keys_box.add_child(row)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	var shift := _key("Maiúsc.", 170)
	shift.pressed.connect(_set_mode.bind("lower" if _mode == "upper" else "upper"))
	var sym := _key("abc" if _mode == "symbols" else "?#@", 130)
	sym.pressed.connect(_set_mode.bind("lower" if _mode == "symbols" else "symbols"))
	var space := _key("Espaço", 260)
	space.pressed.connect(_type.bind(" "))
	var back := _key("Apagar", 160)
	back.pressed.connect(_backspace)
	_toggle_secret = _key("Ocultar" if not secret else "Mostrar", 160)
	_toggle_secret.pressed.connect(_toggle)
	var ok := _key("OK", 120)
	ok.pressed.connect(_submit)
	var cancel := _key("Cancelar", 170)
	cancel.pressed.connect(_cancel)
	for b in [shift, sym, space, back, _toggle_secret, ok, cancel]:
		actions.add_child(b)
	_keys_box.add_child(actions)
	# O separador vazio no topo mantém _focus_first apontando para a 1ª linha de letras.
	var spacer := Control.new()
	_keys_box.add_child(spacer)
	_keys_box.move_child(spacer, 0)


func _set_mode(mode: String) -> void:
	_mode = mode
	_build_keys()
	_focus_first.call_deferred()


func _type(ch: String) -> void:
	_field.text += ch
	if _mode == "upper":
		# Como num celular: Maiúsc. vale para uma letra.
		_mode = "lower"
		var focused := get_viewport().gui_get_focus_owner()
		var idx := focused.get_index() if focused else 0
		var row_idx := focused.get_parent().get_index() if focused else 1
		_build_keys()
		_refocus.call_deferred(row_idx, idx)


func _refocus(row_idx: int, idx: int) -> void:
	if row_idx < _keys_box.get_child_count():
		var row := _keys_box.get_child(row_idx)
		if idx < row.get_child_count():
			(row.get_child(idx) as Control).grab_focus()
			return
	_focus_first()


func _backspace() -> void:
	_field.text = _field.text.substr(0, max(0, _field.text.length() - 1))


func _toggle() -> void:
	secret = not secret
	_field.secret = secret
	_toggle_secret.text = "Ocultar" if not secret else "Mostrar"


func _submit() -> void:
	hide()
	submitted.emit(_field.text)


func _cancel() -> void:
	hide()
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			_submit()
		elif k.keycode == KEY_BACKSPACE:
			_backspace()
		elif k.keycode == KEY_ESCAPE:
			_cancel()
		elif k.unicode > 31:
			_field.text += char(k.unicode)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("console_delete"):
		_backspace()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("console_space"):
		_type(" ")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("console_menu"):
		_submit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
