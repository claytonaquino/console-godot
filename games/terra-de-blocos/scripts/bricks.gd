class_name Bricks
extends RefCounted
## Kit de blocos de brinquedo: blocos estáticos agrupados num único MultiMesh
## (uma chamada de desenho para o cenário inteiro) e peças avulsas para
## personagens e máquinas animados.

const STUD_PITCH := 1.0
const STUD_R := 0.28
const STUD_H := 0.16

static var _box: BoxMesh
static var _stud: CylinderMesh
static var _batch_mat: StandardMaterial3D
static var _mats := {}

var _xforms: Array[Transform3D] = []
var _colors: Array[Color] = []
var _stud_xforms: Array[Transform3D] = []
var _stud_colors: Array[Color] = []


static func box_mesh() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
	return _box


static func stud_mesh() -> CylinderMesh:
	if _stud == null:
		_stud = CylinderMesh.new()
		_stud.top_radius = STUD_R
		_stud.bottom_radius = STUD_R
		_stud.height = STUD_H
		_stud.radial_segments = 10
		_stud.rings = 1
	return _stud


static func batch_material() -> StandardMaterial3D:
	if _batch_mat == null:
		_batch_mat = StandardMaterial3D.new()
		_batch_mat.vertex_color_use_as_albedo = true
		_batch_mat.vertex_color_is_srgb = true
		_batch_mat.roughness = 0.7
		_batch_mat.metallic_specular = 0.25
	return _batch_mat


## Material de plástico brilhante (com cache por cor).
static func plastic(color: Color, emissive := false) -> StandardMaterial3D:
	var key := color.to_html() + ("e" if emissive else "")
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.4
		m.metallic_specular = 0.6
		if emissive:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 1.4
		_mats[key] = m
	return _mats[key]


## Adiciona um bloco (pos = centro). Pinos no topo se studs = true.
func add(pos: Vector3, size: Vector3, color: Color, studs := true, rot_y := 0.0) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	_xforms.append(Transform3D(basis.scaled(size), pos))
	_colors.append(color)
	if not studs:
		return
	var nx := maxi(1, int(round(size.x / STUD_PITCH)))
	var nz := maxi(1, int(round(size.z / STUD_PITCH)))
	for ix in nx:
		for iz in nz:
			var local := Vector3((ix + 0.5) * size.x / nx - size.x * 0.5, size.y * 0.5 + STUD_H * 0.5, (iz + 0.5) * size.z / nz - size.z * 0.5)
			_stud_xforms.append(Transform3D(Basis(), pos + basis * local))
			_stud_colors.append(color)


func count() -> int:
	return _xforms.size()


## Cria os nós de desenho dentro de parent.
func build(parent: Node3D, shadows := true) -> void:
	if _xforms.is_empty():
		return
	parent.add_child(_mm(box_mesh(), _xforms, _colors, shadows))
	if not _stud_xforms.is_empty():
		parent.add_child(_mm(stud_mesh(), _stud_xforms, _stud_colors, false))


func _mm(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = batch_material()
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Peça avulsa (para partes animadas). Retorna o MeshInstance3D.
static func piece(parent: Node3D, pos: Vector3, size: Vector3, color: Color, studs := false, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh()
	mi.scale = size
	mi.position = pos
	mi.material_override = plastic(color, emissive)
	parent.add_child(mi)
	if studs:
		var nx := maxi(1, int(round(size.x / 0.5)))
		var nz := maxi(1, int(round(size.z / 0.5)))
		for ix in nx:
			for iz in nz:
				var s := MeshInstance3D.new()
				s.mesh = stud_mesh()
				s.material_override = plastic(color)
				# Filho de "mi" herda a escala; compensamos.
				s.scale = Vector3(0.45 / size.x, 0.6 / size.y, 0.45 / size.z)
				s.position = Vector3((ix + 0.5) / nx - 0.5, 0.5 + 0.3 / size.y * 0.16, (iz + 0.5) / nz - 0.5)
				mi.add_child(s)
	return mi


## Nó vazio para articulações (ombro, quadril...).
static func joint(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n
