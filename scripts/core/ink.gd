class_name Ink
extends RefCounted

## Central palette + geometry/material factory. All painted surfaces in the
## game go through here so the outline and paper treatment stay consistent.

const SURFACE_SHADER: Shader = preload("res://shaders/ink_surface.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/ink_outline.gdshader")
const WALL_SHADER: Shader = preload("res://shaders/ink_wall.gdshader")
const VIEW_SHADER: Shader = preload("res://shaders/ink_viewmodel.gdshader")

const INK := Color("15130f")
const INK_SOFT := Color("27231d")
const PAPER := Color("e9e1cb")
const PAPER_DARK := Color("d7cbb0")
const BONE := Color("ddd5bf")
const CINNABAR := Color("a93226")
const CINNABAR_DARK := Color("6f1d16")
const CINNABAR_BRIGHT := Color("c94a32")
const INDIGO := Color("2c3b4a")
const INDIGO_LIGHT := Color("46596b")
const JADE := Color("556b58")
const JADE_DARK := Color("334538")
const OCHRE := Color("b08a52")
const OCHRE_DARK := Color("7a5c33")
const ASH := Color("736f64")
const ASH_DARK := Color("4a4740")
const GOLD := Color("c9a44f")
const PLAYER_COAT := Color("28596d")
const PLAYER_TRIMS := [Color("54bfc4"), Color("70a9e0"), Color("7ccab0"), Color("a199de")]

static var _surfaces: Dictionary = {}
static var _outlines: Dictionary = {}
static var _walls: Dictionary = {}
static var _views: Dictionary = {}
static var _meshes: Dictionary = {}


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

static func surface(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var wobble: float = float(opts.get("wobble", 0.0))
	var outline_w: float = float(opts.get("outline", 0.0070))
	var wash: float = float(opts.get("wash", 0.34))
	var hatch: float = float(opts.get("hatch", 0.55))
	var rim: float = float(opts.get("rim", 0.10))
	var pool: float = float(opts.get("pool", 0.26))
	var grain: float = float(opts.get("grain", 0.24))
	var scale: float = float(opts.get("scale", 0.42))
	var shade: Color = opts.get("shade", Color(0.42, 0.45, 0.47))
	var time_offset: float = float(opts.get("time", 0.0))
	var key := "%s|%.4f|%.4f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%s|%.2f" % [
		color.to_html(), wobble, outline_w, wash, hatch, rim, pool, grain, scale,
		shade.to_html(), time_offset
	]
	if _surfaces.has(key):
		return _surfaces[key]
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("wash_strength", wash)
	mat.set_shader_parameter("wash_scale", scale)
	mat.set_shader_parameter("grain_strength", grain)
	mat.set_shader_parameter("hatch_strength", hatch)
	mat.set_shader_parameter("rim_strength", rim)
	mat.set_shader_parameter("rim_color", PAPER)
	mat.set_shader_parameter("pool_strength", pool)
	mat.set_shader_parameter("wobble_amp", wobble)
	mat.set_shader_parameter("wobble_freq", 2.2)
	mat.set_shader_parameter("wobble_speed", 7.0)
	mat.set_shader_parameter("time_offset", time_offset)
	mat.set_shader_parameter("shade_tint", shade)
	if outline_w > 0.0:
		mat.next_pass = _outline(outline_w, wobble, time_offset)
	_surfaces[key] = mat
	return mat


static func _outline(width: float, wobble: float, time_offset: float = 0.0) -> ShaderMaterial:
	var key := "%.5f|%.4f|%.3f" % [width, wobble, time_offset]
	if _outlines.has(key):
		return _outlines[key]
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mat.set_shader_parameter("outline_color", INK)
	mat.set_shader_parameter("width", width)
	mat.set_shader_parameter("wobble_amp", wobble)
	mat.set_shader_parameter("wobble_freq", 2.2)
	mat.set_shader_parameter("wobble_speed", 7.0)
	mat.set_shader_parameter("time_offset", time_offset)
	mat.set_shader_parameter("thickness_variation", 0.65)
	_outlines[key] = mat
	return mat


static func wall(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var outline_w: float = float(opts.get("outline", 0.009))
	var wobble: float = float(opts.get("wobble", 0.002))
	var moss: float = float(opts.get("moss", 0.55))
	var hatch: float = float(opts.get("hatch", 0.45))
	var pool: float = float(opts.get("pool", 0.3))
	var bw: float = float(opts.get("block_w", 1.15))
	var bh: float = float(opts.get("block_h", 0.56))
	var time_offset: float = float(opts.get("time", 0.0))
	var key := "%s|%.3f|%.3f|%.2f|%.2f|%.2f|%.2f|%.2f" % [
		color.to_html(), outline_w, wobble, moss, hatch, pool, bw, bh
	]
	if _walls.has(key):
		return _walls[key]
	var mat := ShaderMaterial.new()
	mat.shader = WALL_SHADER
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("mortar_color", INK)
	mat.set_shader_parameter("moss_color", Color("46503f"))
	mat.set_shader_parameter("dust_color", PAPER_DARK)
	mat.set_shader_parameter("block_w", bw)
	mat.set_shader_parameter("block_h", bh)
	mat.set_shader_parameter("moss_amount", moss)
	mat.set_shader_parameter("wobble_amp", wobble)
	mat.set_shader_parameter("hatch_strength", hatch)
	mat.set_shader_parameter("pool_strength", pool)
	mat.set_shader_parameter("time_offset", time_offset)
	if outline_w > 0.0:
		mat.next_pass = _outline(outline_w, wobble, time_offset)
	_walls[key] = mat
	return mat


static func view_material(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var outline_w: float = float(opts.get("outline", 0.0042))
	var wobble: float = float(opts.get("wobble", 0.0015))
	var grain: float = float(opts.get("grain", 0.12))
	var rim: float = float(opts.get("rim", 0.06))
	var key := "%s|%.4f|%.4f|%.3f|%.3f" % [color.to_html(), outline_w, wobble, grain, rim]
	if _views.has(key):
		return _views[key]
	var mat := ShaderMaterial.new()
	mat.shader = VIEW_SHADER
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("grain", grain)
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("rim_color", PAPER)
	if outline_w > 0.0:
		mat.next_pass = _outline(outline_w, wobble, 0.0)
	_views[key] = mat
	return mat


static func unlit(color: Color, additive: bool = false, billboard: bool = false,
		no_depth: bool = false, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.no_depth_test = no_depth
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	if texture:
		mat.albedo_texture = texture
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
	return mat


static func glow(color: Color, additive: bool = true, billboard: bool = true) -> StandardMaterial3D:
	var mat := unlit(color, additive, billboard)
	mat.albedo_texture = ProcTex.soft_circle(96)
	return mat


# --------------------------------------------------------------------------
# Primitive meshes
# --------------------------------------------------------------------------

static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box_%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		m.subdivide_width = 0
		m.subdivide_height = 0
		m.subdivide_depth = 0
		_meshes[key] = m
	return _meshes[key]


static func sphere_mesh(radius: float, segments: int = 14, rings: int = 8) -> SphereMesh:
	var key := "sph_%.3f_%d_%d" % [radius, segments, rings]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segments
		m.rings = rings
		_meshes[key] = m
	return _meshes[key]


static func capsule_mesh(radius: float, height: float, segments: int = 10, rings: int = 4) -> CapsuleMesh:
	var h := maxf(height, radius * 2.0 + 0.01)
	var key := "cap_%.3f_%.3f_%d_%d" % [radius, h, segments, rings]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = h
		m.radial_segments = segments
		m.rings = rings
		_meshes[key] = m
	return _meshes[key]


static func cylinder_mesh(top_radius: float, bottom_radius: float, height: float,
		segments: int = 12) -> CylinderMesh:
	var key := "cyl_%.3f_%.3f_%.3f_%d" % [top_radius, bottom_radius, height, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top_radius
		m.bottom_radius = bottom_radius
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		m.cap_top = true
		m.cap_bottom = true
		_meshes[key] = m
	return _meshes[key]


static func prism_mesh(size: Vector3) -> PrismMesh:
	var key := "pri_%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


# --------------------------------------------------------------------------
# Node helpers
# --------------------------------------------------------------------------

static func part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = surface(color, opts)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if opts.get("viewmodel", false):
		mi.layers = 2
	if opts.get("no_shadow", false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func add_box(parent: Node3D, size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	return part(parent, box_mesh(size), color, pos, rot_deg, opts)


static func add_sphere(parent: Node3D, radius: float, color: Color, pos: Vector3 = Vector3.ZERO,
		scale: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO,
		opts: Dictionary = {}) -> MeshInstance3D:
	var mi := part(parent, sphere_mesh(radius), color, pos, rot_deg, opts)
	mi.scale = scale
	return mi


static func add_capsule(parent: Node3D, radius: float, height: float, color: Color,
		pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO,
		opts: Dictionary = {}) -> MeshInstance3D:
	return part(parent, capsule_mesh(radius, height), color, pos, rot_deg, opts)


static func add_cylinder(parent: Node3D, top_radius: float, bottom_radius: float,
		height: float, color: Color, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	return part(parent, cylinder_mesh(top_radius, bottom_radius, height), color, pos, rot_deg, opts)


static func add_prism(parent: Node3D, size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	return part(parent, prism_mesh(size), color, pos, rot_deg, opts)


static func add_quad(parent: Node3D, size: Vector2, material: Material,
		pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func add_label(parent: Node3D, text: String, font: Font, size: int, color: Color,
		pos: Vector3 = Vector3.ZERO, pixel_size: float = 0.005,
		rot_deg: Vector3 = Vector3.ZERO, no_depth: bool = false) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.pixel_size = pixel_size
	label.modulate = color
	label.position = pos
	label.rotation_degrees = rot_deg
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = no_depth
	label.double_sided = true
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.outline_size = 0
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)
	return label
