class_name Level
extends Node3D
## Constrói uma fase a partir de um mapa de caracteres (Levels.MAPS).
## Cenário estático vira poucos MultiMesh (rápido na GT 730); colisões são
## caixas simples. Guarda os objetos interativos: alavancas, portão,
## parede quebrável, baús, artefato, placas e saída.

signal lever_pulled(index: int, total: int)
signal wall_broken
signal chest_opened(pos: Vector3)

const CELL := 2.0
const BLOCKING := "#TPrRHGBC~LOMb"

var map_id := ""
var rows: PackedStringArray = []
var width := 0
var height := 0
var markers := {}          # caractere -> Array[Vector3]
var start_pos := Vector3.ZERO
var levers: Array[Dictionary] = []
var breakables: Array[Dictionary] = []
var chests: Array[Dictionary] = []
var gate_open := false
var artifact: Node3D
var exit_pad: Node3D
var exit_active := false
var blocked := {}          # Vector2i -> true (para o robô de teste)

var _gate_bars: Array[Node3D] = []
var _gate_body: StaticBody3D
var _static: StaticBody3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func build(id: String) -> void:
	map_id = id
	_rng.seed = hash(id)
	rows = PackedStringArray(Levels.MAPS[id])
	height = rows.size()
	width = rows[0].length()
	_static = StaticBody3D.new()
	_static.collision_layer = 1
	add_child(_static)
	# Chão: uma caixa grande
	_box_shape(_static, Vector3(width * CELL * 0.5, -0.5, height * CELL * 0.5), Vector3(width * CELL, 1.0, height * CELL))

	# Terreno além dos muros (sem pinos, só para não ver o "vazio")
	var outside := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	outside.mesh = pm
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.28, 0.48, 0.22) if id != "vila" else Color(0.33, 0.52, 0.25)
	outside.material_override = om
	outside.position = center() + Vector3(0, -0.42, 0)
	outside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outside)
	var b := Bricks.new()       # blocos com sombra
	var g := Bricks.new()       # chão (sem sombra própria)
	var theme := _theme()
	for r in height:
		var line := rows[r]
		for c in width:
			var ch := line[c]
			var p := cell_pos(c, r)
			_ground(g, ch, p, c, r, theme)
			if BLOCKING.contains(ch):
				blocked[Vector2i(c, r)] = true
			if not markers.has(ch):
				markers[ch] = []
			markers[ch].append(p)
			match ch:
				"#": _wall(b, p, c, r, theme)
				"T": _tree(b, p)
				"P": _pine(b, p)
				"r": _ruin(b, p)
				"R": _rock(b, p)
				"b": _bush(b, p)
				"f": _flowers(g, p)
				"H": _house(b, p)
				"S": start_pos = p
				"G": _gate_cell(p)
				"L": _lever(p)
				"B": _breakable(p)
				"C": _chest(p)
				"A": _artifact(p)
				"X": _exit(p)
				"i": _sign(b, p)
				"M": _board(b, p)
				"O": _workshop(b, p)
				"~":
					_box_shape(_static, p + Vector3(0, 0.25, 0), Vector3(CELL, 0.5, CELL))
	# Floresta do lado de fora dos muros
	for r in range(-6, height + 6):
		for c in range(-6, width + 6):
			if r >= 0 and r < height and c >= 0 and c < width:
				continue
			if _rng.randf() < 0.45:
				var p := cell_pos(c, r)
				if _rng.randf() < 0.5:
					_pine(b, p, false)
				else:
					_tree(b, p, false)
	# Casas ocupam um pouco das casas vizinhas.
	for hp in cells("H"):
		var hc := pos_cell(hp)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				blocked[hc + Vector2i(dx, dy)] = true
	_merge_wall_collisions()
	g.build(self, false)
	b.build(self, true)


func cell_pos(c: int, r: int) -> Vector3:
	return Vector3(c * CELL + CELL * 0.5, 0, r * CELL + CELL * 0.5)


func pos_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func center() -> Vector3:
	return Vector3(width * CELL * 0.5, 0, height * CELL * 0.5)


func cells(ch: String) -> Array:
	return markers.get(ch, [])


func is_free(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		return false
	if blocked.has(c):
		if rows[c.y][c.x] == "G" and gate_open:
			return true
		if rows[c.y][c.x] == "B":
			for w in breakables:
				if not w.alive and pos_cell(w.pos) == c:
					return true
		return false
	return true


# ---------------------------------------------------------------- visual

func _theme() -> Dictionary:
	match map_id:
		"m1":
			return {"grass": Color(0.36, 0.62, 0.28), "grass2": Color(0.32, 0.56, 0.25), "path": Color(0.72, 0.58, 0.38),
				"wall": Color(0.52, 0.52, 0.56), "wall2": Color(0.45, 0.46, 0.5)}
		"m2":
			return {"grass": Color(0.45, 0.68, 0.3), "grass2": Color(0.4, 0.62, 0.27), "path": Color(0.78, 0.64, 0.42),
				"wall": Color(0.62, 0.48, 0.34), "wall2": Color(0.55, 0.42, 0.3)}
		_:
			return {"grass": Color(0.47, 0.7, 0.32), "grass2": Color(0.43, 0.65, 0.29), "path": Color(0.8, 0.66, 0.44),
				"wall": Color(0.64, 0.5, 0.36), "wall2": Color(0.57, 0.44, 0.31)}


func _ground(g: Bricks, ch: String, p: Vector3, c: int, r: int, theme: Dictionary) -> void:
	if ch == "#":
		return
	if ch == "~":
		g.add(p + Vector3(0, -0.35, 0), Vector3(CELL, 0.3, CELL), Color(0.2, 0.5, 0.85) if (c + r) % 2 == 0 else Color(0.22, 0.55, 0.9), false)
		return
	var col: Color = theme.grass if (c + r) % 2 == 0 else theme.grass2
	if ch in [",", "S", "X", "M", "O"]:
		col = theme.path if (c + r) % 2 == 0 else (theme.path as Color).darkened(0.06)
	if ch in ["r", "A", "G"] and map_id == "m1":
		col = Color(0.6, 0.6, 0.62) if (c + r) % 2 == 0 else Color(0.55, 0.55, 0.58)
	g.add(p + Vector3(0, -0.2, 0), Vector3(CELL, 0.4, CELL), col, true)


func _wall(b: Bricks, p: Vector3, c: int, r: int, theme: Dictionary) -> void:
	# Muros do lado da câmera (sul e oeste) são baixos para não esconder os heróis.
	var low := r == height - 1 or c == 0
	var interior := r > 0 and r < height - 1 and c > 0 and c < width - 1
	var h := 0.8 if low else (1.6 if interior else 2.4)
	var layers := int(h / 0.8)
	for k in layers:
		var col: Color = theme.wall if (k + c + r) % 2 == 0 else theme.wall2
		b.add(p + Vector3(0, 0.4 + k * 0.8, 0), Vector3(CELL, 0.8, CELL), col, k == layers - 1)


func _tree(b: Bricks, p: Vector3, solid := true) -> void:
	var o := Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
	b.add(p + o + Vector3(0, 0.8, 0), Vector3(0.6, 1.6, 0.6), Color(0.45, 0.3, 0.17), false)
	var green := Color(0.2, 0.55, 0.22).lerp(Color(0.35, 0.65, 0.2), _rng.randf())
	b.add(p + o + Vector3(0, 2.0, 0), Vector3(2.0, 1.0, 2.0), green, true)
	b.add(p + o + Vector3(0, 2.8, 0), Vector3(1.4, 0.7, 1.4), green.lightened(0.08), true)
	if solid:
		_box_shape(_static, p + o + Vector3(0, 1.0, 0), Vector3(0.9, 2.0, 0.9))


func _pine(b: Bricks, p: Vector3, solid := true) -> void:
	b.add(p + Vector3(0, 0.5, 0), Vector3(0.5, 1.0, 0.5), Color(0.4, 0.27, 0.15), false)
	var green := Color(0.12, 0.42, 0.25).lerp(Color(0.18, 0.5, 0.28), _rng.randf())
	var sizes := [2.0, 1.5, 1.0, 0.5]
	var hgt := _rng.randf_range(0.9, 1.15)
	for k in sizes.size():
		var s: float = sizes[k]
		b.add(p + Vector3(0, (1.2 + k * 0.7) * hgt, 0), Vector3(s, 0.7 * hgt, s), green.lightened(k * 0.04), true)
	if solid:
		_box_shape(_static, p + Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 1.0))


func _ruin(b: Bricks, p: Vector3) -> void:
	var n := _rng.randi_range(1, 4)
	var stone := Color(0.6, 0.6, 0.63)
	for k in n:
		var w := 1.4 - k * 0.15
		b.add(p + Vector3(_rng.randf_range(-0.1, 0.1), 0.35 + k * 0.7, _rng.randf_range(-0.1, 0.1)), Vector3(w, 0.7, w),
			stone.darkened(_rng.randf() * 0.15), k == n - 1, _rng.randf_range(-0.2, 0.2))
	if _rng.randf() < 0.4:
		b.add(p + Vector3(0.7, 0.15, 0.6), Vector3(0.6, 0.3, 0.4), Color(0.5, 0.5, 0.55), true, 0.6)  # caco caído
	if _rng.randf() < 0.3:
		b.add(p + Vector3(0, 0.71 * n + 0.05, 0), Vector3(0.3, 0.1, 0.3), Color(0.15, 0.85, 0.95), false)  # luzinha antiga
	_box_shape(_static, p + Vector3(0, 0.7 * n * 0.5, 0), Vector3(1.4, 0.7 * n, 1.4))


func _rock(b: Bricks, p: Vector3) -> void:
	b.add(p + Vector3(0, 0.45, 0), Vector3(1.6, 0.9, 1.4), Color(0.5, 0.5, 0.52), true, _rng.randf_range(-0.4, 0.4))
	b.add(p + Vector3(0.2, 1.05, 0.1), Vector3(0.9, 0.4, 0.8), Color(0.56, 0.56, 0.58), true, _rng.randf_range(-0.4, 0.4))
	_box_shape(_static, p + Vector3(0, 0.6, 0), Vector3(1.6, 1.2, 1.4))


func _bush(b: Bricks, p: Vector3) -> void:
	var green := Color(0.25, 0.6, 0.22)
	b.add(p + Vector3(0, 0.4, 0), Vector3(1.4, 0.8, 1.2), green, true)
	b.add(p + Vector3(0.2, 0.95, 0), Vector3(0.8, 0.4, 0.8), green.lightened(0.1), true)
	if _rng.randf() < 0.5:
		b.add(p + Vector3(-0.4, 0.9, 0.4), Vector3(0.2, 0.2, 0.2), Color(0.9, 0.15, 0.2), false)
	_box_shape(_static, p + Vector3(0, 0.5, 0), Vector3(1.4, 1.0, 1.2))


func _flowers(g: Bricks, p: Vector3) -> void:
	var cols := [Color(0.95, 0.85, 0.2), Color(0.95, 0.35, 0.45), Color(0.95, 0.95, 0.95), Color(0.65, 0.45, 0.95)]
	for k in 5:
		var o := Vector3(_rng.randf_range(-0.75, 0.75), 0, _rng.randf_range(-0.75, 0.75))
		g.add(p + o + Vector3(0, 0.12, 0), Vector3(0.08, 0.24, 0.08), Color(0.2, 0.5, 0.2), false)
		g.add(p + o + Vector3(0, 0.3, 0), Vector3(0.22, 0.12, 0.22), cols[_rng.randi() % cols.size()], false)


func _house(b: Bricks, p: Vector3) -> void:
	var wall: Color = [Color(0.95, 0.92, 0.82), Color(0.85, 0.75, 0.55), Color(0.75, 0.85, 0.95)][_rng.randi() % 3]
	var roof: Color = [Color(0.8, 0.22, 0.15), Color(0.2, 0.4, 0.75), Color(0.3, 0.55, 0.25)][_rng.randi() % 3]
	for k in 3:
		b.add(p + Vector3(0, 0.4 + k * 0.8, 0), Vector3(3.6, 0.8, 3.2), wall if k != 1 else wall.darkened(0.05), false)
	b.add(p + Vector3(0, 0.8, 1.62), Vector3(0.9, 1.6, 0.06), Color(0.45, 0.28, 0.15), false)  # porta
	b.add(p + Vector3(1.82, 1.4, 0), Vector3(0.06, 0.7, 0.9), Color(0.5, 0.8, 1.0), false)     # janela
	b.add(p + Vector3(-1.82, 1.4, 0), Vector3(0.06, 0.7, 0.9), Color(0.5, 0.8, 1.0), false)
	b.add(p + Vector3(0, 2.75, 0), Vector3(4.0, 0.3, 3.6), roof, true)
	b.add(p + Vector3(0, 3.15, 0), Vector3(3.0, 0.5, 3.6), roof.darkened(0.08), true)
	b.add(p + Vector3(0, 3.6, 0), Vector3(1.8, 0.4, 3.6), roof.darkened(0.15), true)
	b.add(p + Vector3(1.0, 3.8, -0.8), Vector3(0.5, 1.0, 0.5), Color(0.6, 0.35, 0.3), true)   # chaminé
	_box_shape(_static, p + Vector3(0, 1.5, 0), Vector3(3.6, 3.0, 3.2))


func _sign(b: Bricks, p: Vector3) -> void:
	b.add(p + Vector3(0, 0.5, 0), Vector3(0.2, 1.0, 0.2), Color(0.45, 0.3, 0.17), false)
	b.add(p + Vector3(0, 1.15, 0), Vector3(1.2, 0.6, 0.15), Color(0.85, 0.7, 0.45), true, PI / 4.0)
	var l := Label3D.new()
	l.text = "!"
	l.font_size = 96
	l.pixel_size = 0.01
	l.modulate = Color(1, 0.9, 0.3)
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = p + Vector3(0, 2.0, 0)
	add_child(l)


func _board(b: Bricks, p: Vector3) -> void:
	for sx in [-0.8, 0.8]:
		b.add(p + Vector3(sx, 0.8, 0), Vector3(0.2, 1.6, 0.2), Color(0.45, 0.3, 0.17), false)
	b.add(p + Vector3(0, 1.5, 0), Vector3(2.0, 1.1, 0.2), Color(0.6, 0.42, 0.25), true)
	for k in 3:
		b.add(p + Vector3(-0.55 + k * 0.55, 1.5, 0.12), Vector3(0.4, 0.5, 0.04), Color(0.95, 0.95, 0.85), false)
	_box_shape(_static, p + Vector3(0, 1.0, 0), Vector3(2.0, 2.0, 0.5))
	_float_label(p + Vector3(0, 2.8, 0), "Missões", Color(1, 0.9, 0.4))


func _workshop(b: Bricks, p: Vector3) -> void:
	b.add(p + Vector3(0, 0.5, 0), Vector3(2.4, 1.0, 1.2), Color(0.55, 0.35, 0.2), true)   # bancada
	b.add(p + Vector3(-0.6, 1.2, 0), Vector3(0.6, 0.4, 0.4), Color(0.7, 0.7, 0.75), true)  # bigorna
	b.add(p + Vector3(0.6, 1.15, 0.1), Vector3(0.3, 0.3, 0.3), Color(0.95, 0.75, 0.2), true)
	b.add(p + Vector3(0.9, 1.1, -0.2), Vector3(0.4, 0.2, 0.3), Color(0.2, 0.6, 0.9), true)
	_box_shape(_static, p + Vector3(0, 0.6, 0), Vector3(2.4, 1.2, 1.2))
	_float_label(p + Vector3(0, 2.4, 0), "Oficina", Color(0.5, 0.9, 1.0))


func _float_label(p: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = p
	add_child(l)


# ---------------------------------------------------------------- objetos

func _gate_cell(p: Vector3) -> void:
	if _gate_body == null:
		_gate_body = StaticBody3D.new()
		_gate_body.collision_layer = 1
		add_child(_gate_body)
	_box_shape(_gate_body, p + Vector3(0, 1.5, 0), Vector3(CELL, 3.0, 0.8))
	var bars := Node3D.new()
	bars.position = p
	add_child(bars)
	Bricks.piece(bars, Vector3(0, 2.6, 0), Vector3(2.0, 0.3, 0.5), Color(0.35, 0.35, 0.4), true)
	for k in 4:
		Bricks.piece(bars, Vector3(-0.75 + k * 0.5, 1.25, 0), Vector3(0.18, 2.5, 0.18), Color(0.5, 0.5, 0.55))
	Bricks.piece(bars, Vector3(0, 1.3, 0.1), Vector3(0.4, 0.4, 0.1), Color(1.0, 0.3, 0.2), false, true)
	_gate_bars.append(bars)


func open_gate() -> void:
	if gate_open:
		return
	gate_open = true
	if _gate_body:
		_gate_body.queue_free()
		_gate_body = null
	for bars in _gate_bars:
		var tw := create_tween()
		tw.tween_property(bars, "position:y", -2.6, 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _lever(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	Bricks.piece(root, Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 1.0), Color(0.4, 0.4, 0.45), true)
	var arm := Bricks.joint(root, Vector3(0, 0.6, 0))
	Bricks.piece(arm, Vector3(0, 0.6, 0), Vector3(0.16, 1.2, 0.16), Color(0.3, 0.3, 0.3))
	var knob := Bricks.piece(arm, Vector3(0, 1.25, 0), Vector3(0.36, 0.36, 0.36), Color(1.0, 0.3, 0.2), false, true)
	arm.rotation.z = 0.6
	var body := StaticBody3D.new()
	add_child(body)
	_box_shape(body, p + Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 1.0))
	levers.append({"pos": p, "on": false, "arm": arm, "knob": knob})


## Testa se um ataque (esfera) alcança alguma alavanca/parede/baú.
func hit_props(center: Vector3, r: float, dmg: float) -> bool:
	var any := false
	for i in levers.size():
		var lv: Dictionary = levers[i]
		if lv.on:
			continue
		if _flat_dist(center, lv.pos) <= r + 0.8:
			lv.on = true
			any = true
			var tw := create_tween()
			tw.tween_property(lv.arm, "rotation:z", -0.6, 0.25)
			(lv.knob as MeshInstance3D).material_override = Bricks.plastic(Color(0.3, 1.0, 0.4), true)
			var n := 0
			for l2 in levers:
				if l2.on:
					n += 1
			lever_pulled.emit(n, levers.size())
	for w in breakables:
		if not w.alive:
			continue
		if _flat_dist(center, w.pos) <= r + 1.1:
			w.hp -= dmg
			any = true
			if w.hp <= 0:
				w.alive = false
				(w.node as Node3D).queue_free()
				(w.body as Node).queue_free()
				wall_broken.emit()
	return any


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _breakable(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	for k in 3:
		for j in 2:
			Bricks.piece(root, Vector3(-0.5 + j * 1.0 + (0.25 if k == 1 else 0.0), 0.35 + k * 0.7, 0), Vector3(0.95, 0.68, 1.8),
				Color(0.62, 0.58, 0.52).darkened(0.08 * ((k + j) % 2)), k == 2)
	Bricks.piece(root, Vector3(0.1, 1.1, 0.92), Vector3(0.1, 1.4, 0.04), Color(0.2, 0.18, 0.15))  # rachadura
	Bricks.piece(root, Vector3(-0.2, 0.6, 0.92), Vector3(0.5, 0.08, 0.04), Color(0.2, 0.18, 0.15))
	var body := StaticBody3D.new()
	add_child(body)
	_box_shape(body, p + Vector3(0, 1.1, 0), Vector3(CELL, 2.2, CELL))
	breakables.append({"pos": p, "hp": 30.0, "alive": true, "node": root, "body": body})


func _chest(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	Bricks.piece(root, Vector3(0, 0.35, 0), Vector3(1.2, 0.7, 0.8), Color(0.6, 0.38, 0.18), false)
	Bricks.piece(root, Vector3(0, 0.36, 0.41), Vector3(0.2, 0.25, 0.04), Color(1.0, 0.8, 0.2), false, true)
	var lid := Bricks.joint(root, Vector3(0, 0.7, -0.4))
	Bricks.piece(lid, Vector3(0, 0.12, 0.4), Vector3(1.25, 0.25, 0.85), Color(0.7, 0.45, 0.2), true)
	var body := StaticBody3D.new()
	add_child(body)
	_box_shape(body, p + Vector3(0, 0.4, 0), Vector3(1.2, 0.8, 0.8))
	chests.append({"pos": p, "opened": false, "lid": lid})


func open_chest(ch: Dictionary) -> void:
	if ch.opened:
		return
	ch.opened = true
	var tw := create_tween()
	tw.tween_property(ch.lid, "rotation:x", -1.9, 0.4).set_trans(Tween.TRANS_BACK)
	chest_opened.emit(ch.pos)


func _artifact(p: Vector3) -> void:
	artifact = Node3D.new()
	artifact.position = p + Vector3(0, 1.3, 0)
	add_child(artifact)
	Bricks.piece(artifact, Vector3.ZERO, Vector3(0.7, 0.7, 0.7), Color(0.2, 0.9, 1.0), true, true)
	Bricks.piece(artifact, Vector3.ZERO, Vector3(0.8, 0.2, 0.8), Color(0.15, 0.15, 0.2))
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.9, 1.0)
	light.light_energy = 2.0
	light.omni_range = 6.0
	artifact.add_child(light)
	# Pedestal
	var b := Bricks.new()
	b.add(p + Vector3(0, 0.3, 0), Vector3(1.4, 0.6, 1.4), Color(0.55, 0.55, 0.6), true)
	b.build(self)


func _exit(p: Vector3) -> void:
	exit_pad = Node3D.new()
	exit_pad.position = p
	add_child(exit_pad)
	Bricks.piece(exit_pad, Vector3(0, 0.05, 0), Vector3(1.8, 0.1, 1.8), Color(0.3, 0.9, 0.5), true, true)
	var l := Label3D.new()
	l.text = "Saída"
	l.font_size = 72
	l.pixel_size = 0.01
	l.outline_size = 14
	l.modulate = Color(0.5, 1.0, 0.6)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 2.2, 0)
	exit_pad.add_child(l)
	exit_pad.visible = false


func set_exit_active(on: bool) -> void:
	exit_active = on
	if exit_pad:
		exit_pad.visible = on


func _process(delta: float) -> void:
	_t += delta
	if artifact and is_instance_valid(artifact):
		var q := floorf(_t * 12.0) / 12.0
		artifact.rotation.y = q * 1.5
		artifact.position.y = 1.3 + sin(q * 3.0) * 0.15
	if exit_pad and exit_pad.visible:
		exit_pad.scale = Vector3.ONE * (1.0 + sin(_t * 5.0) * 0.05)


# ---------------------------------------------------------------- colisões

var _wall_cells := {}


func _merge_wall_collisions() -> void:
	# Junta muros vizinhos da mesma linha numa caixa só.
	for r in height:
		var c := 0
		while c < width:
			if rows[r][c] == "#":
				var c0 := c
				while c < width and rows[r][c] == "#":
					c += 1
				var a := cell_pos(c0, r)
				var bpos := cell_pos(c - 1, r)
				_box_shape(_static, (a + bpos) * 0.5 + Vector3(0, 2.0, 0), Vector3((c - c0) * CELL, 4.0, CELL))
			else:
				c += 1


func _box_shape(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)
