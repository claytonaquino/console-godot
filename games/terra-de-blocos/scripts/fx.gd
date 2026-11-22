class_name Fx
extends Node3D
## Efeitos: pecinhas voando, números de dano, avisos de ataque no chão e
## anéis de impacto. Tudo leve (sem partículas de GPU).

var _debris: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _rings: Array[Dictionary] = []


func debris(pos: Vector3, color: Color, count := 8, power := 5.0) -> void:
	for i in count:
		if _debris.size() > 160:
			break
		var mi := MeshInstance3D.new()
		mi.mesh = Bricks.box_mesh()
		var s := randf_range(0.12, 0.32)
		mi.scale = Vector3(s, s * 0.6, s)
		mi.material_override = Bricks.plastic(color)
		mi.position = pos
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)).normalized()
		_debris.append({"n": mi, "v": dir * power * randf_range(0.6, 1.2), "spin": Vector3(randf(), randf(), randf()) * 12.0, "t": 1.4})


func popup(pos: Vector3, text: String, color := Color.WHITE, size := 72) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	add_child(l)
	_popups.append({"n": l, "t": 0.9})


## Aviso de ataque: disco vermelho que enche até o impacto.
func telegraph(pos: Vector3, radius: float, duration: float) -> void:
	var outer := _disc(radius, Color(1, 0.15, 0.1, 0.25))
	outer.position = Vector3(pos.x, 0.06, pos.z)
	add_child(outer)
	var inner := _disc(radius, Color(1, 0.25, 0.1, 0.55))
	inner.position = Vector3(pos.x, 0.07, pos.z)
	inner.scale = Vector3(0.01, 1, 0.01)
	add_child(inner)
	_rings.append({"n": outer, "inner": inner, "t": duration, "total": duration, "kind": "tele"})


## Anel que se expande (onda de choque, explosão).
func ring(pos: Vector3, radius: float, color: Color) -> void:
	var r := _disc(1.0, Color(color, 0.6))
	r.position = Vector3(pos.x, 0.08, pos.z)
	r.scale = Vector3(0.2, 1, 0.2)
	add_child(r)
	_rings.append({"n": r, "t": 0.35, "total": 0.35, "kind": "ring", "radius": radius})


func _disc(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	cyl.radial_segments = 32
	cyl.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = m
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _process(delta: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var d := _debris[i]
		var n: MeshInstance3D = d.n
		d.t -= delta
		var v: Vector3 = d.v
		v.y -= 14.0 * delta
		n.position += v * delta
		if n.position.y < 0.08:
			n.position.y = 0.08
			v = Vector3(v.x * 0.5, absf(v.y) * 0.3, v.z * 0.5)
		d.v = v
		n.rotation += (d.spin as Vector3) * delta
		if d.t < 0.3:
			n.scale *= 0.9
		if d.t <= 0.0:
			n.queue_free()
			_debris.remove_at(i)
	for i in range(_popups.size() - 1, -1, -1):
		var p := _popups[i]
		var l: Label3D = p.l if p.has("l") else p.n
		p.t -= delta
		l.position.y += delta * 2.2
		l.modulate.a = clampf(p.t / 0.4, 0.0, 1.0)
		if p.t <= 0.0:
			l.queue_free()
			_popups.remove_at(i)
	for i in range(_rings.size() - 1, -1, -1):
		var r := _rings[i]
		r.t -= delta
		var k: float = 1.0 - r.t / r.total
		var n: MeshInstance3D = r.n
		if r.kind == "tele":
			var inner: MeshInstance3D = r.inner
			inner.scale = Vector3(maxf(0.01, k), 1, maxf(0.01, k))
			if r.t <= 0.0:
				inner.queue_free()
		else:
			var s: float = lerpf(0.2, r.radius, k)
			n.scale = Vector3(s, 1, s)
			(n.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = 0.6 * (1.0 - k)
		if r.t <= 0.0:
			n.queue_free()
			_rings.remove_at(i)
