class_name Track
extends Node3D
## Circuito gerado por código a partir de pontos de controle (spline
## Catmull-Rom fechada). Gera asfalto, zebras, faixas, grama, árvores,
## linha de largada, uma grade de superfície (aderência por posição) e um
## perfil de velocidade usado pelo piloto automático.

const HALF_WIDTH := 6.0
const KERB_WIDTH := 1.2
const SPACING := 2.0
const CELL := 1.0
const MU_ASPHALT := 1.0
const MU_KERB := 0.9
const MU_GRASS := 0.55
const ROLL_GRASS := 5.0

## Pontos de controle (x, z) em metros.
const CONTROL := [
	Vector2(0, 0), Vector2(250, 0), Vector2(330, 30), Vector2(350, 110), Vector2(310, 170),
	Vector2(230, 185), Vector2(180, 235), Vector2(195, 320), Vector2(265, 360), Vector2(300, 430),
	Vector2(250, 500), Vector2(140, 510), Vector2(60, 460), Vector2(20, 380), Vector2(-40, 335),
	Vector2(-120, 345), Vector2(-190, 300), Vector2(-200, 200), Vector2(-150, 120), Vector2(-80, 50),
]

var points := PackedVector3Array()
var tangents := PackedVector3Array()
var rights := PackedVector3Array()
var curvature := PackedFloat32Array()
var speed_profile := PackedFloat32Array()
var length := 0.0

var _grid_origin := Vector2.ZERO
var _grid_w := 0
var _grid_h := 0
var _grid_dist := PackedFloat32Array()
var _grid_idx := PackedInt32Array()
var _kerb := PackedByteArray()


func build(tree_count := 700) -> void:
	_sample_spline()
	_compute_curvature()
	_build_grid()
	_build_speed_profile()
	_build_ground()
	_build_road()
	_build_start_line()
	_build_trees(tree_count)
	_build_scenery()


# ---------------------------------------------------------------- geometria

func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _sample_spline() -> void:
	var dense: Array[Vector2] = []
	var n := CONTROL.size()
	for i in n:
		var p0: Vector2 = CONTROL[(i - 1 + n) % n]
		var p1: Vector2 = CONTROL[i]
		var p2: Vector2 = CONTROL[(i + 1) % n]
		var p3: Vector2 = CONTROL[(i + 2) % n]
		for k in 60:
			dense.append(_catmull(p0, p1, p2, p3, k / 60.0))
	# Reamostra com espaçamento constante.
	var out: Array[Vector2] = [dense[0]]
	var acc := 0.0
	for i in range(1, dense.size() + 1):
		var a: Vector2 = dense[i - 1]
		var b: Vector2 = dense[i % dense.size()]
		var seg := a.distance_to(b)
		while acc + seg >= SPACING:
			var t := (SPACING - acc) / seg
			var p := a.lerp(b, t)
			out.append(p)
			seg -= SPACING - acc
			a = p
			acc = 0.0
		acc += seg
	if out.size() > 2 and out[out.size() - 1].distance_to(out[0]) < SPACING * 0.5:
		out.remove_at(out.size() - 1)
	points.resize(out.size())
	for i in out.size():
		points[i] = Vector3(out[i].x, 0.0, out[i].y)
	length = out.size() * SPACING
	tangents.resize(points.size())
	rights.resize(points.size())
	for i in points.size():
		var t := (points[(i + 1) % points.size()] - points[(i - 1 + points.size()) % points.size()]).normalized()
		tangents[i] = t
		rights[i] = t.cross(Vector3.UP).normalized()


func _compute_curvature() -> void:
	var n := points.size()
	curvature.resize(n)
	for i in n:
		var a := tangents[(i - 3 + n) % n]
		var b := tangents[(i + 3) % n]
		var ang := atan2(a.cross(b).y, a.dot(b))
		curvature[i] = ang / (6.0 * SPACING)  # 1/m, sinal: positivo = curva à esquerda


func index_ahead(i: int, meters: float) -> int:
	return (i + int(meters / SPACING)) % points.size()


# ---------------------------------------------------------------- superfície

func _build_grid() -> void:
	var minv := Vector2(INF, INF)
	var maxv := Vector2(-INF, -INF)
	for p in points:
		minv = minv.min(Vector2(p.x, p.z))
		maxv = maxv.max(Vector2(p.x, p.z))
	var margin := 40.0
	_grid_origin = minv - Vector2(margin, margin)
	_grid_w = int((maxv.x - minv.x + 2 * margin) / CELL) + 1
	_grid_h = int((maxv.y - minv.y + 2 * margin) / CELL) + 1
	_grid_dist.resize(_grid_w * _grid_h)
	_grid_dist.fill(1e9)
	_grid_idx.resize(_grid_w * _grid_h)
	_grid_idx.fill(-1)
	var r := int(ceil(16.0 / CELL))
	for i in points.size():
		var p := points[i]
		var cx := int((p.x - _grid_origin.x) / CELL)
		var cz := int((p.z - _grid_origin.y) / CELL)
		for dz in range(-r, r + 1):
			var z := cz + dz
			if z < 0 or z >= _grid_h:
				continue
			for dx in range(-r, r + 1):
				var x := cx + dx
				if x < 0 or x >= _grid_w:
					continue
				var wx := _grid_origin.x + (x + 0.5) * CELL
				var wz := _grid_origin.y + (z + 0.5) * CELL
				var d := Vector2(wx - p.x, wz - p.z).length()
				var k := z * _grid_w + x
				if d < _grid_dist[k]:
					_grid_dist[k] = d
					_grid_idx[k] = i
	_kerb.resize(points.size())
	for i in points.size():
		_kerb[i] = 1 if absf(curvature[i]) > 1.0 / 140.0 else 0


## Retorna {dist, idx} do ponto da pista mais próximo (dist grande = longe).
func lookup(pos: Vector3) -> Dictionary:
	var x := int((pos.x - _grid_origin.x) / CELL)
	var z := int((pos.z - _grid_origin.y) / CELL)
	if x < 0 or z < 0 or x >= _grid_w or z >= _grid_h:
		return {"dist": 1e9, "idx": -1}
	var k := z * _grid_w + x
	return {"dist": _grid_dist[k], "idx": _grid_idx[k]}


## Aderência (μ) e fator de resistência ao rolamento numa posição.
func surface_at(pos: Vector3) -> Vector2:
	var l := lookup(pos)
	var d: float = l.dist
	if d <= HALF_WIDTH:
		return Vector2(MU_ASPHALT, 1.0)
	if d <= HALF_WIDTH + KERB_WIDTH and l.idx >= 0 and _kerb[l.idx] == 1:
		return Vector2(MU_KERB, 1.5)
	return Vector2(MU_GRASS, ROLL_GRASS)


func _build_speed_profile() -> void:
	var n := points.size()
	speed_profile.resize(n)
	for i in n:
		var k := maxf(absf(curvature[i]), 1e-4)
		speed_profile[i] = minf(sqrt(0.82 * 9.81 / k), 60.0)
	# Frenagem (de trás para a frente) e aceleração, duas voltas para fechar o laço.
	for rep in 2:
		for j in range(n - 1, -1, -1):
			var nxt := speed_profile[(j + 1) % n]
			speed_profile[j] = minf(speed_profile[j], sqrt(nxt * nxt + 2.0 * 6.5 * SPACING))
		for j in n:
			var prv := speed_profile[(j - 1 + n) % n]
			speed_profile[j] = minf(speed_profile[j], sqrt(prv * prv + 2.0 * 3.2 * SPACING))


# ---------------------------------------------------------------- visual

func _noise_tex(base: Color, variation: float, freq: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = freq
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var grad := Gradient.new()
	grad.set_color(0, base.darkened(variation))
	grad.set_color(1, base.lightened(variation))
	tex.color_ramp = grad
	return tex


func _build_ground() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)

	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_tex(Color(0.22, 0.38, 0.14), 0.14, 0.02)
	mat.uv1_scale = Vector3(300, 300, 1)
	mat.roughness = 0.95
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	add_child(mi)


func _ribbon(offset_a: float, offset_b: float, y: float, color_fn: Callable, mat: Material, only := Callable()) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var n := points.size()
	var vdist := 0.0
	for i in n:
		var j := (i + 1) % n
		if only.is_valid() and not only.call(i):
			vdist += SPACING
			continue
		var a0 := points[i] + rights[i] * offset_a + Vector3(0, y, 0)
		var a1 := points[i] + rights[i] * offset_b + Vector3(0, y, 0)
		var b0 := points[j] + rights[j] * offset_a + Vector3(0, y, 0)
		var b1 := points[j] + rights[j] * offset_b + Vector3(0, y, 0)
		var c: Color = color_fn.call(i)
		var v0 := vdist / 8.0
		var v1 := (vdist + SPACING) / 8.0
		for vert in [[a0, Vector2(0, v0)], [b0, Vector2(0, v1)], [a1, Vector2(1, v0)],
				[a1, Vector2(1, v0)], [b0, Vector2(0, v1)], [b1, Vector2(1, v1)]]:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(vert[1])
			st.add_vertex(vert[0])
		vdist += SPACING
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_road() -> void:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = _noise_tex(Color(0.17, 0.17, 0.18), 0.10, 0.35)
	asphalt.uv1_scale = Vector3(3, 2, 1)
	asphalt.vertex_color_use_as_albedo = true
	asphalt.roughness = 0.95
	asphalt.metallic_specular = 0.15
	_ribbon(-HALF_WIDTH, HALF_WIDTH, 0.02, func(_i: int) -> Color: return Color.WHITE, asphalt)

	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.roughness = 0.7
	var white := func(_i: int) -> Color: return Color(0.92, 0.92, 0.92)
	_ribbon(-HALF_WIDTH + 0.3, -HALF_WIDTH + 0.5, 0.03, white, plain)
	_ribbon(HALF_WIDTH - 0.5, HALF_WIDTH - 0.3, 0.03, white, plain)

	var kerb_color := func(i: int) -> Color: return Color(0.85, 0.1, 0.1) if (i / 2) % 2 == 0 else Color(0.95, 0.95, 0.95)
	var is_kerb := func(i: int) -> bool: return _kerb[i] == 1
	_ribbon(-HALF_WIDTH - KERB_WIDTH, -HALF_WIDTH, 0.04, kerb_color, plain, is_kerb)
	_ribbon(HALF_WIDTH, HALF_WIDTH + KERB_WIDTH, 0.04, kerb_color, plain, is_kerb)


func _build_start_line() -> void:
	var img := Image.create(16, 4, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 4:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF_WIDTH * 2.0, 1.5)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = points[0] + Vector3(0, 0.05, 0)
	mi.basis = Basis.looking_at(rights[0], Vector3.UP)
	add_child(mi)


func _build_trees(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xforms: Array[Transform3D] = []
	var tries := 0
	while xforms.size() < count and tries < count * 30:
		tries += 1
		var p := Vector3(rng.randf_range(_grid_origin.x - 150, _grid_origin.x + _grid_w * CELL + 150), 0,
			rng.randf_range(_grid_origin.y - 150, _grid_origin.y + _grid_h * CELL + 150))
		if lookup(p).dist < 1e8:
			continue
		var s := rng.randf_range(0.8, 1.6)
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), p))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.25
	trunk.height = 3.0
	trunk.radial_segments = 6
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.36, 0.25, 0.16)
	trunk.material = tm
	var top := CylinderMesh.new()
	top.top_radius = 0.0
	top.bottom_radius = 1.9
	top.height = 5.5
	top.radial_segments = 7
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.16, 0.36, 0.17)
	top.material = lm
	for pair in [[trunk, 1.5], [top, 5.2]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			var t := xforms[i]
			mm.set_instance_transform(i, Transform3D(t.basis, t.origin + t.basis * Vector3(0, pair[1], 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _build_scenery() -> void:
	# Arquibancada e boxes perto da largada (só visual).
	var base := points[0] - rights[0] * (HALF_WIDTH + 14.0)
	var stand := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 6, 10)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.57, 0.6)
	bm.material = m
	stand.mesh = bm
	stand.position = base + Vector3(30, 3, 0) - rights[0] * 5.0
	add_child(stand)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(62, 0.4, 13)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.15, 0.3, 0.55)
	rm.material = rmat
	roof.mesh = rm
	roof.position = stand.position + Vector3(0, 6.5, 0)
	add_child(roof)
	var pit := points[0] + rights[0] * (HALF_WIDTH + 18.0)
	for k in 6:
		var box := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(9, 4, 8)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.85, 0.85, 0.88) if k % 2 == 0 else Color(0.8, 0.3, 0.2)
		b.material = bmat
		box.mesh = b
		box.position = pit + Vector3(-10 + k * 9.5, 2, 6)
		add_child(box)
