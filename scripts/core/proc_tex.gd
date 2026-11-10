class_name ProcTex
extends RefCounted

## Small procedural textures used by VFX and UI. Everything is generated at
## runtime so the project has no external art dependencies.

static var _cache: Dictionary = {}


static func soft_circle(size: int = 96) -> Texture2D:
	var key := "soft_%d" % size
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func splat(variant: int = 0, size: int = 128) -> Texture2D:
	var key := "splat_%d_%d" % [variant, size]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + variant * 977
	var half := size * 0.5
	var blobs: Array[Vector4] = [] # x, y, radius, strength
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.08) * size
		blobs.append(Vector4(half + cos(a) * d, half + sin(a) * d,
			size * rng.randf_range(0.06, 0.12), rng.randf_range(0.7, 1.0)))
	for i in rng.randi_range(24, 36):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.06, 0.37) * size
		blobs.append(Vector4(half + cos(a) * d, half + sin(a) * d,
			size * rng.randf_range(0.008, 0.055), rng.randf_range(0.3, 0.9)))
	var starts: Array[Vector2] = []
	var ends: Array[Vector2] = []
	var widths: Array[float] = []
	for i in rng.randi_range(3, 6):
		var a := rng.randf() * TAU
		var ln := size * rng.randf_range(0.18, 0.42)
		var s := Vector2(half + cos(a) * size * 0.04, half + sin(a) * size * 0.04)
		starts.append(s)
		ends.append(s + Vector2(cos(a) * ln, sin(a) * ln))
		widths.append(size * rng.randf_range(0.008, 0.022))
	var holes: Array[Vector3] = []
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.05, 0.22) * size
		holes.append(Vector3(half + cos(a) * d, half + sin(a) * d, size * rng.randf_range(0.02, 0.06)))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var m := 0.0
			for b in blobs:
				var d := Vector2(px - b.x, py - b.y).length()
				var v := 1.0 - smoothstep(b.z * 0.25, b.z, d)
				m = maxf(m, v * b.w)
			var p := Vector2(px, py)
			for i in starts.size():
				var dist := _point_segment_distance(p, starts[i], ends[i])
				var v := 1.0 - smoothstep(widths[i] * 0.3, widths[i], dist)
				m = maxf(m, v * 0.82)
			for hole in holes:
				var d := Vector2(px - hole.x, py - hole.y).length()
				m *= 1.0 - (1.0 - smoothstep(hole.z * 0.4, hole.z, d)) * 0.9
			var alpha := clampf(m, 0.0, 1.0)
			if alpha > 0.02:
				alpha = pow(alpha, 0.7)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.dot(ab)
	if denom < 0.00001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func brush_stroke(size: int = 128, variant: int = 0) -> Texture2D:
	var key := "stroke_%d_%d" % [variant, size]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 913 + variant * 131
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cy := size * 0.5
	for x in size:
		var t := float(x) / float(size)
		var taper := sin(t * PI)
		var width := size * 0.10 * clampf(taper, 0.0, 1.0) * rng.randf_range(0.6, 1.1)
		var offset := sin(t * 9.0 + variant) * size * 0.012
		for y in size:
			var dy := float(y) - (cy + offset)
			var edge := 1.0 - smoothstep(width * 0.45, width, abs(dy))
			if edge > 0.02:
				var a := edge * (0.55 + 0.45 * sin(t * 47.0 + variant * 2.0) * 0.5 + 0.225)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func paper_grain(size: int = 256) -> Texture2D:
	var key := "paper_%d" % size
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8081
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := 0.86 + rng.randf() * 0.14
			# Sparse paper fibres.
			if rng.randf() > 0.9965:
				v = 0.62
			img.set_pixel(x, y, Color(v, v * 0.985, v * 0.93, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
