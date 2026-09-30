class_name Roman
extends Object

## Subtractive Roman numerals for any positive integer.
## 4000 and above are runs of M (MMMM is 4000). Overlines are not used;
## they depend on the font and are easy to misread as a smaller value.
## Zero and negatives have no numeral and return an empty string.

const _STEPS: Array[int] = [
	1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1,
]
const _GLYPHS: PackedStringArray = [
	"m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i",
]

static var _cache: Dictionary = {}


static func to_roman(value: int) -> String:
	if value <= 0:
		return ""
	if _cache.has(value):
		return _cache[value]
	var text := _convert(value)
	_cache[value] = text
	return text


static func _convert(value: int) -> String:
	var text := ""
	for i in _STEPS.size():
		var step := _STEPS[i]
		var glyph: String = _GLYPHS[i]
		while value >= step:
			text += glyph
			value -= step
	return text
