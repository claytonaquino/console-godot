extends Button
## Cartão de um jogo na biblioteca. Mostra a capa (cover.png) ou,
## se não houver, um cartão colorido com a inicial do jogo.

signal selected(card: Button)

const CARD_SIZE := Vector2(340, 460)
const ROUNDED := preload("res://shaders/rounded.gdshader")

var game: Dictionary = {}
var accent := Color(0.16, 0.45, 0.65)
var _tween: Tween
var _frame: Panel


func setup(g: Dictionary) -> void:
	game = g
	accent = Color.from_string(str(g.get("color", "#2a6f97")), accent)
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	text = ""

	var normal := UiTheme.box(accent.darkened(0.35), 26, 0)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", UiTheme.box(accent.darkened(0.25), 26, 0))
	add_theme_stylebox_override("pressed", UiTheme.box(accent, 26, 0))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var title := str(g.get("title", "Jogo"))
	var cover_path := str(g.get("dir", "")).path_join(str(g.get("cover", "cover.png")))
	var tex := _load_cover(cover_path)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = ROUNDED
		mat.set_shader_parameter("rect_size", CARD_SIZE)
		tr.material = mat
		add_child(tr)
	else:
		var initial := UiTheme.label(title.substr(0, 1).to_upper(), 260, Color(1, 1, 1, 0.18))
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.offset_bottom = -60
		add_child(initial)

	# Faixa escura com o título, na parte de baixo do cartão.
	var band := Panel.new()
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = Color(0, 0, 0, 0.45)
	band_style.corner_radius_bottom_left = 26
	band_style.corner_radius_bottom_right = 26
	band.add_theme_stylebox_override("panel", band_style)
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -96
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var name_label := UiTheme.label(title, 30)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -96
	name_label.offset_left = 22
	name_label.offset_right = -22
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)

	# Moldura de foco por cima da capa (o estilo "focus" do botão ficaria embaixo).
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0), 26, 6, Color.WHITE))
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.hide()
	add_child(_frame)

	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	mouse_entered.connect(grab_focus)
	resized.connect(func() -> void: pivot_offset = size / 2.0)
	pivot_offset = CARD_SIZE / 2.0


func _load_cover(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _on_focus(focused: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * (1.08 if focused else 1.0), 0.18)
	z_index = 1 if focused else 0
	_frame.visible = focused
	if focused:
		selected.emit(self)
