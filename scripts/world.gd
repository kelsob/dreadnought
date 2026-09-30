class_name World
extends Node

## Black-and-white map. White is open, anything else is closed.
## Width and height come from the image. One pixel is one world unit.
## The hull's position stays fractional. A cell is only the square under that point.
## The radar mask is a signed distance, clamped to ±SHORE_SPAN. Walking still uses the hard cells.

## How far the radar distance field keeps, in pixels. Must match terrain_span in the radar shader.
const SHORE_SPAN := 8.0

## Column and row of the starting cell. (0, 0) is the top-left pixel.
@export var start_cell := Vector2i.ZERO
## Starting facing, in degrees. 0 faces up the image. Positive turns toward the right edge.
@export var start_heading_degrees := 0.0
@export var map: Texture2D

var _open: PackedByteArray = PackedByteArray()
var _size := Vector2i.ZERO
var _mask: ImageTexture


func _ready() -> void:
	_read_map()
	if has_map() and not is_open(get_start_position()):
		push_error("World: start cell %s is closed." % start_cell)


func has_map() -> bool:
	return _size.x > 0 and _size.y > 0 and not _open.is_empty()


func get_pixel_size() -> Vector2i:
	return _size


func get_mask_texture() -> Texture2D:
	return _mask


## Center of the starting cell. The hull is not snapped here again after this.
func get_start_position() -> Vector2:
	return Vector2(start_cell) + Vector2(0.5, 0.5)


func get_start_heading_degrees() -> float:
	return start_heading_degrees


## True when the continuous point sits in an open cell. Off the image is closed.
func is_open(world_pos: Vector2) -> bool:
	if not has_map():
		return true
	var cell := _cell_at(world_pos)
	if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
		return false
	return _open[cell.y * _size.x + cell.x] == 1


## True when every cell the step enters is open. End position is not snapped.
func accepts_step(from_pos: Vector2, to_pos: Vector2) -> bool:
	if not has_map():
		return true
	var span := to_pos - from_pos
	var dist := span.length()
	var samples := maxi(ceili(dist * 2.0), 1)
	for i in range(1, samples + 1):
		if not is_open(from_pos + span * (float(i) / float(samples))):
			return false
	return true


func _cell_at(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x), floori(world_pos.y))


func _read_map() -> void:
	_open = PackedByteArray()
	_size = Vector2i.ZERO
	_mask = null
	if map == null:
		return
	var image := map.get_image()
	if image == null:
		push_error("World: could not read the map image. Import it as Lossless, with mipmaps off.")
		return
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	_size = image.get_size()
	_open.resize(_size.x * _size.y)
	for y in _size.y:
		for x in _size.x:
			var pixel := image.get_pixel(x, y)
			var lum := maxf(pixel.r, maxf(pixel.g, pixel.b))
			var open := pixel.a > 0.5 and lum > 0.5
			_open[y * _size.x + x] = 1 if open else 0
	var sdf := _signed_distance()
	var mask := Image.create(_size.x, _size.y, false, Image.FORMAT_L8)
	for i in _open.size():
		var encoded := clampf(sdf[i] / (SHORE_SPAN * 2.0) + 0.5, 0.0, 1.0)
		mask.set_pixel(i % _size.x, int(float(i) / float(_size.x)), Color(encoded, encoded, encoded))
	_mask = ImageTexture.create_from_image(mask)


## Positive inside open cells, negative inside closed. Units are pixels.
## Outside the image counts as closed. Walking does not read this.
func _signed_distance() -> PackedFloat32Array:
	var count := _open.size()
	var to_closed := PackedFloat32Array()
	var to_open := PackedFloat32Array()
	to_closed.resize(count)
	to_open.resize(count)
	to_closed.fill(0.0)
	to_open.fill(0.0)
	var w := _size.x
	var h := _size.y
	var far := float(w + h)
	for i in count:
		if _open[i] == 1:
			to_closed[i] = far
		else:
			to_open[i] = far
	for x in w:
		_note_outside(to_closed, x, 0, w)
		_note_outside(to_closed, x, h - 1, w)
	for y in h:
		_note_outside(to_closed, 0, y, w)
		_note_outside(to_closed, w - 1, y, w)
	_chamfer(to_closed, w, h)
	_chamfer(to_open, w, h)
	var sdf := PackedFloat32Array()
	sdf.resize(count)
	sdf.fill(0.0)
	for i in count:
		sdf[i] = to_closed[i] if _open[i] == 1 else -to_open[i]
	return sdf


func _note_outside(dist: PackedFloat32Array, x: int, y: int, w: int) -> void:
	var i := y * w + x
	if _open[i] == 1:
		dist[i] = minf(dist[i], 1.0)


func _chamfer(dist: PackedFloat32Array, w: int, h: int) -> void:
	var ortho := 1.0
	var diag := 1.41421356
	for y in h:
		for x in w:
			var i := y * w + x
			var d := dist[i]
			if x > 0:
				d = minf(d, dist[i - 1] + ortho)
			if y > 0:
				d = minf(d, dist[i - w] + ortho)
				if x > 0:
					d = minf(d, dist[i - w - 1] + diag)
				if x + 1 < w:
					d = minf(d, dist[i - w + 1] + diag)
			dist[i] = d
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var d := dist[i]
			if x + 1 < w:
				d = minf(d, dist[i + 1] + ortho)
			if y + 1 < h:
				d = minf(d, dist[i + w] + ortho)
				if x > 0:
					d = minf(d, dist[i + w - 1] + diag)
				if x + 1 < w:
					d = minf(d, dist[i + w + 1] + diag)
			dist[i] = d
