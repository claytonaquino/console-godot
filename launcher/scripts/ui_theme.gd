extends Node
## Tema visual do launcher, montado em código para ficar fácil de ajustar.

const ACCENT := Color(0.30, 0.79, 0.94)
const TEXT := Color(0.95, 0.97, 1.0)
const TEXT_DIM := Color(0.70, 0.76, 0.86)
const PANEL := Color(0.05, 0.07, 0.11, 0.97)


func box(bg: Color, radius := 18, border := 0, border_color := ACCENT, pad := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = pad + 8
	s.content_margin_right = pad + 8
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.anti_aliasing = true
	return s


func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30

	# Botões: o estilo "focus" é desenhado por cima do normal.
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.07)))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.12)))
	t.set_stylebox("pressed", "Button", box(Color(1, 1, 1, 0.20)))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.03)))
	t.set_stylebox("focus", "Button", box(Color(ACCENT, 0.16), 18, 4))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.5))
	t.set_constant("h_separation", "Button", 14)

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 28, 2, Color(1, 1, 1, 0.08), 28))

	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.35), 14, 2, Color(1, 1, 1, 0.15)))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), 14, 3))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_font_size("font_size", "LineEdit", 36)

	var slider := box(Color(1, 1, 1, 0.12), 8, 0, ACCENT, 6)
	var slider_fill := box(ACCENT, 8, 0, ACCENT, 6)
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	t.set_stylebox("focus", "HSlider", box(Color(0, 0, 0, 0), 10, 3))

	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.10), 10, 0, ACCENT, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 10, 0, ACCENT, 0))
	return t


## Etiqueta pronta com tamanho e cor.
func label(text: String, size := 30, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## "Pílula" com o nome de um botão do controle, usada na barra de dicas.
func hint(button: String, action: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var pill := PanelContainer.new()
	var sb := box(Color(1, 1, 1, 0.9), 14, 0, ACCENT, 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	pill.add_theme_stylebox_override("panel", sb)
	pill.add_child(label(button, 22, Color(0.05, 0.07, 0.11)))
	h.add_child(pill)
	h.add_child(label(action, 26, TEXT_DIM))
	return h
