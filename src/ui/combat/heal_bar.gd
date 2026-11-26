class_name HealBar
extends Control
## A health bar for the rest screens: the health you have, then the stretch a rest
## adds drawn lighter beside it.

var _hp := 0
var _add := 0
var _max := 1


func setup(hp: int, add: int, max_hp: int) -> void:
	_hp = hp
	_add = add
	_max = maxi(1, max_hp)
	custom_minimum_size = Vector2(0, 22)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var round_box := StyleBoxFlat.new()
	round_box.bg_color = Color(0.1, 0.05, 0.11)
	round_box.border_color = Color(0.29, 0.16, 0.27)
	round_box.set_border_width_all(2)
	round_box.set_corner_radius_all(11)
	draw_style_box(round_box, rect)
	var inner := rect.grow(-2.0)
	var have := inner.size.x * clampf(float(_hp) / _max, 0.0, 1.0)
	var plus := inner.size.x * clampf(float(_add) / _max, 0.0, 1.0)
	if have > 0.0:
		draw_rect(Rect2(inner.position, Vector2(have, inner.size.y)), Color(0.9, 0.3, 0.45))
	if plus > 0.0:
		draw_rect(Rect2(inner.position + Vector2(have, 0.0), Vector2(plus, inner.size.y)),
			Color(1.0, 0.75, 0.82))
