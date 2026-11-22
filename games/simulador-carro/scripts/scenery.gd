class_name Scenery
extends Node3D
## Cenário em volta da pista: relevo com colinas e montanhas, árvores
## variadas, arbustos, pedras, barreiras de pneus (com colisão), placas de
## frenagem, arquibancadas com público, pórtico de largada, faixas,
## postes, boxes e nuvens. Tudo gerado por código e agrupado em MultiMesh
## para pesar pouco na placa de vídeo.

const TERRAIN_SIZE := 1600.0
const TERRAIN_STEP := 10.0
const FLAT_RADIUS := 42.0    # até essa distância da pista o chão é plano

var track: Track
var tree_mms: Array[MultiMesh] = []

var _center := Vector2.ZERO
var _n := 0
var _heights := PackedFloat32Array()
var _dists := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func build(t: Track) -> void:
	track = t
	_rng.seed = 2026
	_build_terrain()
	_build_mountains()
	_build_vegetation()
	_build_barriers()
	_build_brake_boards()
	_build_grandstands()
	_build_start_gantry()
	_build_pits()
	_build_banners()
	_build_clouds()


# ---------------------------------------------------------------- utilidades

func _mat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _box_mesh(size: Vector3, mat: Material) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	return b


func _add_mesh(mesh: Mesh, xf: Transform3D, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _multimesh(mesh: Mesh, xforms: Array, colors: Array = [], shadows := true) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


## Ponto ao lado da pista: índice i, deslocamento lateral (positivo = direita).
func _side(i: int, offset: float) -> Vector3:
	return track.points[i] + track.rights[i] * offset


func _facing_track(i: int, offset: float) -> Basis:
	# Objeto olhando para a pista.
	var to_track := -track.rights[i] * signf(offset)
	return Basis.looking_at(to_track, Vector3.UP)


# ---------------------------------------------------------------- relevo

func _track_distance(x: float, z: float, coarse: PackedVector2Array) -> float:
	var best := 1e9
	for p in coarse:
		var d := (p.x - x) * (p.x - x) + (p.y - z) * (p.y - z)
		if d < best:
			best = d
	return sqrt(best)


func height_at(x: float, z: float) -> float:
	var gx := clampf((x - _center.x) / TERRAIN_STEP + _n * 0.5, 0.0, _n - 1.001)
	var gz := clampf((z - _center.y) / TERRAIN_STEP + _n * 0.5, 0.0, _n - 1.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - x0
	var fz := gz - z0
	var h00 := _heights[z0 * _n + x0]
	var h10 := _heights[z0 * _n + x0 + 1]
	var h01 := _heights[(z0 + 1) * _n + x0]
	var h11 := _heights[(z0 + 1) * _n + x0 + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func distance_at(x: float, z: float) -> float:
	var gx := clampi(int(round((x - _center.x) / TERRAIN_STEP + _n * 0.5)), 0, _n - 1)
	var gz := clampi(int(round((z - _center.y) / TERRAIN_STEP + _n * 0.5)), 0, _n - 1)
	return _dists[gz * _n + gx]


func _build_terrain() -> void:
	var minv := Vector2(INF, INF)
	var maxv := Vector2(-INF, -INF)
	var coarse := PackedVector2Array()
	for i in range(0, track.points.size(), 8):
		var p := track.points[i]
		coarse.append(Vector2(p.x, p.z))
		minv = minv.min(Vector2(p.x, p.z))
		maxv = maxv.max(Vector2(p.x, p.z))
	_center = (minv + maxv) * 0.5
	_n = int(TERRAIN_SIZE / TERRAIN_STEP) + 1
	_heights.resize(_n * _n)
	_dists.resize(_n * _n)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 11
	noise.frequency = 0.006
	noise.fractal_octaves = 4
	var half := TERRAIN_SIZE * 0.5
	for z in _n:
		for x in _n:
			var wx := _center.x - half + x * TERRAIN_STEP
			var wz := _center.y - half + z * TERRAIN_STEP
			var d := _track_distance(wx, wz, coarse)
			var k := z * _n + x
			_dists[k] = d
			var hills := (noise.get_noise_2d(wx, wz) * 0.5 + 0.5)
			var amp := smoothstep(FLAT_RADIUS, FLAT_RADIUS + 110.0, d) * 16.0 + smoothstep(250.0, 650.0, d) * 45.0
			_heights[k] = hills * amp

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass_a := Color(0.20, 0.36, 0.13)
	var grass_b := Color(0.30, 0.44, 0.17)
	var dry := Color(0.47, 0.46, 0.28)
	var rock := Color(0.42, 0.40, 0.37)
	var cnoise := FastNoiseLite.new()
	cnoise.frequency = 0.02
	for z in _n:
		for x in _n:
			var wx := _center.x - half + x * TERRAIN_STEP
			var wz := _center.y - half + z * TERRAIN_STEP
			var h := _heights[z * _n + x]
			var c := grass_a.lerp(grass_b, cnoise.get_noise_2d(wx, wz) * 0.5 + 0.5)
			c = c.lerp(dry, smoothstep(14.0, 30.0, h) * 0.6)
			c = c.lerp(rock, smoothstep(32.0, 48.0, h))
			st.set_color(c)
			st.set_uv(Vector2(wx, wz) / 12.0)
			st.add_vertex(Vector3(wx, h, wz))
	for z in _n - 1:
		for x in _n - 1:
			var i := z * _n + x
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + _n)
			st.add_index(i + 1)
			st.add_index(i + _n + 1)
			st.add_index(i + _n)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = track._noise_tex(Color(0.85, 0.85, 0.85), 0.18, 0.05)
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	_add_mesh(mesh, Transform3D(), false)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _build_mountains() -> void:
	# Anel de montanhas no horizonte (sem colisão).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 1.3
	var segs := 72
	var r_in := 950.0
	var r_out := 1500.0
	var tops: Array[Vector3] = []
	for s in segs + 1:
		var a := TAU * s / segs
		var hgt := 90.0 + (noise.get_noise_1d(float(s % segs)) * 0.5 + 0.5) * 230.0
		tops.append(Vector3(cos(a) * (r_in + r_out) * 0.5, hgt, sin(a) * (r_in + r_out) * 0.5))
	var c_low := Color(0.22, 0.30, 0.25)
	var c_top := Color(0.45, 0.48, 0.52)
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var in0 := Vector3(cos(a0) * r_in, 0, sin(a0) * r_in)
		var in1 := Vector3(cos(a1) * r_in, 0, sin(a1) * r_in)
		var out0 := Vector3(cos(a0) * r_out, 0, sin(a0) * r_out)
		var out1 := Vector3(cos(a1) * r_out, 0, sin(a1) * r_out)
		var t0 := tops[s]
		var t1 := tops[s + 1]
		for tri in [[in0, t0, in1], [in1, t0, t1], [t0, out0, t1], [t1, out0, out1]]:
			for v in tri:
				st.set_color(c_low.lerp(c_top, (v as Vector3).y / 320.0))
				st.add_vertex((v as Vector3) + Vector3(_center.x, -2.0, _center.y))
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_add_mesh(mesh, Transform3D(), false)


# ---------------------------------------------------------------- vegetação

func _build_vegetation() -> void:
	var half := TERRAIN_SIZE * 0.5 - 20.0
	var pines: Array = []
	var broad: Array = []
	var bushes: Array = []
	var rocks: Array = []
	var tries := 0
	# Bosques: árvores agrupadas em manchas, mais naturais que espalhadas.
	var clumps: Array[Vector2] = []
	for c in 70:
		clumps.append(Vector2(_center.x + _rng.randf_range(-half, half), _center.y + _rng.randf_range(-half, half)))
	while pines.size() + broad.size() < 1800 and tries < 40000:
		tries += 1
		var cl: Vector2 = clumps[_rng.randi() % clumps.size()]
		var p := cl + Vector2(_rng.randfn(0, 40), _rng.randfn(0, 40))
		if _rng.randf() < 0.25:
			p = Vector2(_center.x + _rng.randf_range(-half, half), _center.y + _rng.randf_range(-half, half))
		var d := distance_at(p.x, p.y)
		if d < 30.0:
			continue
		var h := height_at(p.x, p.y)
		if h > 40.0:
			continue
		var s := _rng.randf_range(0.8, 1.6)
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.3), s)), Vector3(p.x, h - 0.1, p.y))
		if h > 12.0 or _rng.randf() < 0.55:
			pines.append(xf)
		else:
			broad.append(xf)
	for k in 500:
		var p := Vector2(_center.x + _rng.randf_range(-half, half), _center.y + _rng.randf_range(-half, half))
		var d := distance_at(p.x, p.y)
		if d < 22.0 or d > 200.0:
			continue
		var s := _rng.randf_range(0.6, 1.4)
		bushes.append(Transform3D(Basis().scaled(Vector3(s * 1.3, s * 0.8, s * 1.3)), Vector3(p.x, height_at(p.x, p.y) + 0.3 * s, p.y)))
	for k in 260:
		var p := Vector2(_center.x + _rng.randf_range(-half, half), _center.y + _rng.randf_range(-half, half))
		if distance_at(p.x, p.y) < 25.0:
			continue
		var sv := Vector3(_rng.randf_range(0.6, 3.0), _rng.randf_range(0.4, 1.6), _rng.randf_range(0.6, 3.0))
		rocks.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(sv), Vector3(p.x, height_at(p.x, p.y), p.y)))

	# Pinheiro: tronco + 2 cones
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.24
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 1
	trunk.material = _mat(Color(0.33, 0.23, 0.15))
	var cone_a := CylinderMesh.new()
	cone_a.top_radius = 0.0
	cone_a.bottom_radius = 2.1
	cone_a.height = 4.2
	cone_a.radial_segments = 7
	cone_a.rings = 1
	var pine_mat := _mat(Color.WHITE)
	pine_mat.vertex_color_use_as_albedo = true
	cone_a.material = pine_mat
	var cone_b := cone_a.duplicate() as CylinderMesh
	cone_b.bottom_radius = 1.5
	cone_b.height = 3.4
	var pine_cols := []
	for i in pines.size():
		pine_cols.append(Color(0.11, 0.27, 0.14).lerp(Color(0.20, 0.36, 0.18), _rng.randf()))
	tree_mms.append(_multimesh(trunk, _offset_all(pines, Vector3(0, 1.5, 0))))
	tree_mms.append(_multimesh(cone_a, _offset_all(pines, Vector3(0, 4.4, 0)), pine_cols))
	tree_mms.append(_multimesh(cone_b, _offset_all(pines, Vector3(0, 6.6, 0)), pine_cols))

	# Árvore de copa redonda: tronco + esfera achatada
	var crown := SphereMesh.new()
	crown.radius = 2.4
	crown.height = 3.8
	crown.radial_segments = 8
	crown.rings = 4
	var crown_mat := _mat(Color.WHITE)
	crown_mat.vertex_color_use_as_albedo = true
	crown.material = crown_mat
	var broad_cols := []
	for i in broad.size():
		broad_cols.append(Color(0.24, 0.40, 0.14).lerp(Color(0.40, 0.48, 0.16), _rng.randf()))
	tree_mms.append(_multimesh(trunk, _offset_all(broad, Vector3(0, 1.5, 0))))
	tree_mms.append(_multimesh(crown, _offset_all(broad, Vector3(0, 4.3, 0)), broad_cols))

	var bush := SphereMesh.new()
	bush.radius = 0.9
	bush.height = 1.4
	bush.radial_segments = 7
	bush.rings = 3
	bush.material = _mat(Color(0.18, 0.33, 0.12))
	_multimesh(bush, bushes, [], false)
	var rock := SphereMesh.new()
	rock.radial_segments = 6
	rock.rings = 3
	rock.material = _mat(Color(0.48, 0.46, 0.43))
	_multimesh(rock, rocks, [], false)


func _offset_all(xforms: Array, offset: Vector3) -> Array:
	var out := []
	for t in xforms:
		var x: Transform3D = t
		out.append(Transform3D(x.basis, x.origin + x.basis * offset))
	return out


# ---------------------------------------------------------------- barreiras

func _build_barriers() -> void:
	# Pneus empilhados por fora da brita, com colisão por trecho.
	var tires: Array = []
	var cols: Array = []
	var body := StaticBody3D.new()
	add_child(body)
	var n := track.points.size()
	var off := Track.GRAVEL_OUT + 1.0
	for i in range(0, n, 1):
		if track.gravel[i] == 0:
			continue
		var sgn := 1.0 if track.outside_is_right(i) else -1.0
		var base := _side(i, sgn * off)
		var t := track.tangents[i]
		for row in 2:
			for k in 2:
				var p := base + t * (k * 1.0 - 0.5) + Vector3(0, 0.2 + row * 0.36, 0)
				tires.append(Transform3D(Basis(), p))
				var c := Color(0.08, 0.08, 0.08)
				if (i / 3) % 2 == 0 and row == 1:
					c = Color(0.85, 0.12, 0.12) if sgn > 0 else Color(0.95, 0.95, 0.95)
				cols.append(c)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 0.9, 2.2)
		shape.shape = box
		shape.transform = Transform3D(Basis.looking_at(t, Vector3.UP), base + Vector3(0, 0.45, 0))
		body.add_child(shape)
	var tire := CylinderMesh.new()
	tire.top_radius = 0.38
	tire.bottom_radius = 0.38
	tire.height = 0.34
	tire.radial_segments = 10
	tire.rings = 1
	var tm := _mat(Color.WHITE, 0.95)
	tm.vertex_color_use_as_albedo = true
	tire.material = tm
	_multimesh(tire, tires, cols)

	# Muretas de concreto na reta dos boxes
	var wall_mat := _mat(Color(0.58, 0.58, 0.56))
	for i in range(n - 60, n + 60, 4):
		var k := (i + n) % n
		for sgn in [-1.0, 1.0]:
			var p := _side(k, sgn * (Track.HALF_WIDTH + 4.0)) + Vector3(0, 0.5, 0)
			_add_mesh(_box_mesh(Vector3(0.4, 1.0, 8.1), wall_mat), Transform3D(Basis.looking_at(track.tangents[k], Vector3.UP), p))


func _build_brake_boards() -> void:
	# Placas 150/100/50 m antes das curvas onde se freia forte.
	var n := track.points.size()
	var prof := track.speed_profile
	var last := -1000
	for i in n:
		var prev := prof[(i - 1 + n) % n]
		var next := prof[(i + 1) % n]
		# Ponto mais lento de uma curva (mínimo local do perfil)
		if not (prof[i] <= prev and prof[i] < next):
			continue
		var top := 0.0
		for j in range(1, 100):
			top = maxf(top, prof[(i - j + n) % n])
		if top - prof[i] < 12.0 or i - last < 60:
			continue
		last = i
		# A frenagem começa onde a velocidade para de cair, voltando da curva.
		var apex := i
		var start := apex
		for j in range(1, 150):
			var a := (apex - j + n) % n
			if prof[a] >= prof[(a - 1 + n) % n] - 0.01:
				start = a
				break
		var sgn := 1.0 if track.outside_is_right(apex) else -1.0
		for dist in [150, 100, 50]:
			var k := (start + int((150 - dist) / Track.SPACING) - int(30 / Track.SPACING) + n) % n
			var basis := Basis.looking_at(track.tangents[k], Vector3.UP)
			var pos := _side(k, sgn * (Track.HALF_WIDTH + 3.5))
			_add_mesh(_box_mesh(Vector3(1.6, 1.1, 0.08), _mat(Color(0.95, 0.95, 0.95))),
				Transform3D(basis, pos + Vector3(0, 1.6, 0) + track.tangents[k] * 0.06))
			_add_mesh(_box_mesh(Vector3(0.12, 1.1, 0.12), _mat(Color(0.3, 0.3, 0.3))), Transform3D(Basis(), pos + Vector3(0, 0.55, 0)))
			var board := Label3D.new()
			board.text = str(dist)
			board.font_size = 160
			board.pixel_size = 0.006
			board.outline_size = 0
			board.modulate = Color(0.05, 0.05, 0.05)
			board.transform = Transform3D(basis, pos + Vector3(0, 1.6, 0))
			add_child(board)


# ---------------------------------------------------------------- arquibancadas

func _grandstand(i: int, offset: float, length: float) -> void:
	var basis := _facing_track(i, offset)
	var origin := _side(i, offset)
	var steel := _mat(Color(0.55, 0.57, 0.6), 0.6, 0.3)
	var roof_mat := _mat(Color(0.12, 0.28, 0.55), 0.5)
	var rows := 6
	var people: Array = []
	var cols: Array = []
	for r in rows:
		var step := Transform3D(basis, origin) * Transform3D(Basis(), Vector3(0, 0.5 + r * 0.6, 1.0 + r * 0.9))
		_add_mesh(_box_mesh(Vector3(length, 0.5, 0.9), steel), step)
		for k in int(length / 0.7):
			if _rng.randf() < 0.25:
				continue
			var px := -length * 0.5 + 0.35 + k * 0.7
			people.append(Transform3D(basis, origin) * Transform3D(Basis(), Vector3(px, 1.05 + r * 0.6, 1.0 + r * 0.9)))
			cols.append(Color.from_hsv(_rng.randf(), _rng.randf_range(0.4, 0.9), _rng.randf_range(0.5, 1.0)))
	var person := BoxMesh.new()
	person.size = Vector3(0.45, 0.75, 0.35)
	var pm := _mat(Color.WHITE)
	pm.vertex_color_use_as_albedo = true
	person.material = pm
	_multimesh(person, people, cols, false)
	var roof := Transform3D(basis, origin) * Transform3D(Basis.from_euler(Vector3(0.12, 0, 0)), Vector3(0, 0.6 + rows * 0.6 + 2.6, 0.9 + rows * 0.45))
	_add_mesh(_box_mesh(Vector3(length + 1.0, 0.25, rows * 0.9 + 2.5), roof_mat), roof)
	for k in 5:
		var px := -length * 0.5 + k * length / 4.0
		_add_mesh(_box_mesh(Vector3(0.25, 7.0, 0.25), steel), Transform3D(basis, origin) * Transform3D(Basis(), Vector3(px, 3.5, 1.0 + rows * 0.9)))


func _build_grandstands() -> void:
	var n := track.points.size()
	# Reta principal
	_grandstand(n - 30, -(Track.HALF_WIDTH + 10.0), 70.0)
	# Curva mais fechada (por fora)
	var best := 0
	for i in n:
		if absf(track.curvature[i]) > absf(track.curvature[best]):
			best = i
	var sgn := 1.0 if track.outside_is_right(best) else -1.0
	_grandstand(best, sgn * (Track.GRAVEL_OUT + 12.0), 40.0)
	# Meio da volta
	var mid := n / 2
	_grandstand(mid, -(Track.HALF_WIDTH + 18.0) * (1.0 if not track.outside_is_right(mid) else -1.0), 35.0)


func _build_start_gantry() -> void:
	var i := 0
	var basis := Basis.looking_at(track.tangents[i], Vector3.UP)
	var steel := _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
	var w := Track.HALF_WIDTH + 1.5
	for sgn in [-1.0, 1.0]:
		_add_mesh(_box_mesh(Vector3(0.5, 7.0, 0.5), steel), Transform3D(basis, _side(i, sgn * w) + Vector3(0, 3.5, 0)))
	_add_mesh(_box_mesh(Vector3(w * 2.0 + 0.5, 1.2, 0.6), steel), Transform3D(basis, track.points[i] + Vector3(0, 6.8, 0)))
	var red := _mat(Color(0.9, 0.1, 0.1), 0.3)
	red.emission_enabled = true
	red.emission = Color(0.7, 0.0, 0.0)
	for k in 5:
		var p := track.points[i] + track.rights[i] * (-2.4 + k * 1.2) + Vector3(0, 6.8, 0) - track.tangents[i] * 0.32
		var lamp := SphereMesh.new()
		lamp.radius = 0.22
		lamp.height = 0.44
		lamp.material = red
		_add_mesh(lamp, Transform3D(Basis(), p), false)
	var label := Label3D.new()
	label.text = "CONSOLE GODOT"
	label.font_size = 128
	label.pixel_size = 0.012
	label.modulate = Color(1, 1, 1)
	label.outline_size = 0
	label.position = track.points[i] + Vector3(0, 7.9, 0) - track.tangents[i] * 0.31
	label.basis = Basis.looking_at(track.tangents[i], Vector3.UP)
	add_child(label)


func _build_pits() -> void:
	var n := track.points.size()
	var i := n - 20
	var basis := _facing_track(i, 1.0)
	var origin := _side(i, Track.HALF_WIDTH + 22.0)
	var wall := _mat(Color(0.88, 0.88, 0.9), 0.7)
	var door_cols := [Color(0.85, 0.2, 0.15), Color(0.15, 0.35, 0.8), Color(0.95, 0.75, 0.1), Color(0.2, 0.6, 0.3)]
	_add_mesh(_box_mesh(Vector3(80, 5, 12), wall), Transform3D(basis, origin) * Transform3D(Basis(), Vector3(0, 2.5, 3)))
	_add_mesh(_box_mesh(Vector3(80, 3, 10), _mat(Color(0.3, 0.32, 0.36))), Transform3D(basis, origin) * Transform3D(Basis(), Vector3(-10, 6.5, 4)))
	for k in 8:
		var door := _box_mesh(Vector3(8, 3.6, 0.1), _mat(door_cols[k % door_cols.size()], 0.5))
		_add_mesh(door, Transform3D(basis, origin) * Transform3D(Basis(), Vector3(-35 + k * 10, 1.8, -3.05)))
	# Asfalto do pit lane
	var pit := _box_mesh(Vector3(80, 0.04, 14), _mat(Color(0.2, 0.2, 0.21)))
	_add_mesh(pit, Transform3D(basis, _side(i, Track.HALF_WIDTH + 12.0) + Vector3(0, 0.01, 0)), false)
	# Postes de luz
	var pole_mat := _mat(Color(0.4, 0.4, 0.42), 0.5, 0.6)
	for k in range(0, 120, 12):
		var kk := (n - 70 + k) % n
		var p := _side(kk, -(Track.HALF_WIDTH + 5.0))
		_add_mesh(_box_mesh(Vector3(0.25, 12, 0.25), pole_mat), Transform3D(Basis(), p + Vector3(0, 6, 0)))
		_add_mesh(_box_mesh(Vector3(1.6, 0.25, 0.6), pole_mat), Transform3D(Basis.looking_at(track.tangents[kk], Vector3.UP), p + Vector3(0, 12, 0) + track.rights[kk] * 0.6), false)


func _build_banners() -> void:
	var texts := ["CONSOLE GODOT", "GT 730 RACING", "PNEUS PACEJKA", "FÍSICA A 240 Hz", "GODOT ENGINE", "CURVA DO S"]
	var cols := [Color(0.85, 0.15, 0.1), Color(0.1, 0.3, 0.75), Color(0.1, 0.55, 0.3), Color(0.95, 0.7, 0.05)]
	var n := track.points.size()
	var k := 0
	for i in range(40, n, n / 12):
		var sgn := -1.0 if k % 2 == 0 else 1.0
		var off := sgn * (Track.HALF_WIDTH + (Track.GRAVEL_OUT + 3.0 if track.gravel[i] == 1 else 5.0))
		var basis := _facing_track(i, off)
		var pos := _side(i, off) + Vector3(0, 1.0, 0)
		var col: Color = cols[k % cols.size()]
		_add_mesh(_box_mesh(Vector3(9.0, 1.4, 0.1), _mat(col, 0.6)), Transform3D(basis, pos))
		var label := Label3D.new()
		label.text = texts[k % texts.size()]
		label.font_size = 96
		label.pixel_size = 0.01
		label.outline_size = 0
		label.modulate = Color.WHITE
		label.transform = Transform3D(basis, pos) * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.07))
		add_child(label)
		k += 1


func _build_clouds() -> void:
	var puffs: Array = []
	for c in 26:
		var center := Vector3(_center.x + _rng.randf_range(-900, 900), _rng.randf_range(160, 260), _center.y + _rng.randf_range(-900, 900))
		for p in 5:
			var s := _rng.randf_range(25, 55)
			puffs.append(Transform3D(Basis().scaled(Vector3(s * 1.6, s * 0.45, s)), center + Vector3(_rng.randf_range(-50, 50), _rng.randf_range(-6, 6), _rng.randf_range(-30, 30))))
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	sphere.material = m
	_multimesh(sphere, puffs, [], false)
