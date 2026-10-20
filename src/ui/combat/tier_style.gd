class_name TierStyle
extends RefCounted
## Shared look for ability upgrade tiers (doc "Ability Upgrades"): base, silver,
## gold. Every surface that draws an ability — the combat card, the reward
## choice, the shop shelf, the loadout chits — reads its colours from here, so
## a silver ability looks silver everywhere.

const NAMES: Array[String] = ["", "Silver", "Gold"]

## Frame colours per tier. Base returns the panel's own gold trim, so an
## un-upgraded ability looks exactly as it always did.
const COLORS: Array[Color] = [
	Color(0.83, 0.69, 0.22),   # base: the standard trim
	Color(0.78, 0.83, 0.90),   # silver
	Color(1.00, 0.80, 0.25),   # gold
]


static func color(tier: int) -> Color:
	return COLORS[clampi(tier, 0, COLORS.size() - 1)]


## "Silver" / "Gold", or "" at base — used as a badge caption.
static func label(tier: int) -> String:
	return NAMES[clampi(tier, 0, NAMES.size() - 1)]


## A tier pip: nothing at base, then one or two filled diamonds. Chosen over a
## text label because it has to sit on a 90px loadout chit as well as a card.
static func pips(tier: int) -> String:
	return "◆".repeat(clampi(tier, 0, COLORS.size() - 1))


## The panel behind an ability at this tier: the standard felt, re-trimmed.
static func panel(tier: int, thickness: int = 3) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.13, 0.07, 0.09, 0.92)
	box.border_color = color(tier)
	box.set_border_width_all(thickness if tier > 0 else 2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(10)
	return box


## The doc's upgrade affordance: "a distinctive glowing border and an
## 'UPGRADE!' indicator positioned in the upper right corner". Returns the
## border; the caller places the badge.
static func upgrade_panel() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.16, 0.10, 0.05, 0.94)
	box.border_color = Color(1.0, 0.84, 0.35)
	box.set_border_width_all(4)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(10)
	box.shadow_color = Color(1.0, 0.78, 0.25, 0.55)
	box.shadow_size = 14
	return box


## The "UPGRADE!" flag for the top-right corner of an offer.
static func upgrade_badge(to_tier: int) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = color(to_tier)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(5)
	badge.add_theme_stylebox_override("panel", box)
	var label_node := Label.new()
	label_node.text = "UPGRADE!"
	label_node.add_theme_font_size_override("font_size", 15)
	label_node.add_theme_color_override("font_color", Color(0.16, 0.09, 0.03))
	badge.add_child(label_node)
	return badge


## The metal of the ability card's frame (patch 0.125): copper at base, silver
## after one upgrade, gold after two. `hi` is the bright end of the diagonal
## sheen, `mid` the body colour and `lo` the shadow. Separate from `color()`,
## which the other surfaces still use for their plain trim.
const METALS: Array[Dictionary] = [
	{"hi": Color(0.94, 0.72, 0.55), "mid": Color(0.75, 0.42, 0.25), "lo": Color(0.42, 0.19, 0.09),
		"title": Color(0.91, 0.74, 0.41), "up": "orange"},
	{"hi": Color(1.0, 1.0, 1.0), "mid": Color(0.71, 0.75, 0.79), "lo": Color(0.36, 0.40, 0.45),
		"title": Color(0.93, 0.95, 0.97), "up": "cyan"},
	{"hi": Color(1.0, 0.95, 0.66), "mid": Color(0.89, 0.69, 0.24), "lo": Color(0.55, 0.36, 0.05),
		"title": Color(1.0, 0.85, 0.42), "up": "gold"},
]


static func metal(tier: int) -> Dictionary:
	return METALS[clampi(tier, 0, METALS.size() - 1)]


## The doc's "distinctive glowing border" for an upgrade offer (patch 0.125): a
## ring in the tier's colour hung just outside the card it surrounds. Gold for
## the first upgrade's reward is silver, so the ring follows the tier shown.
static func glow_ring(to_tier: int) -> Control:
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.offset_left = -6.0
	ring.offset_top = -6.0
	ring.offset_right = 6.0
	ring.offset_bottom = 6.0
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(3)
	box.set_corner_radius_all(16)
	var tint: Color = metal(to_tier).hi if to_tier == 1 else Color(1.0, 0.83, 0.29)
	box.border_color = tint
	box.shadow_color = Color(tint, 0.6)
	box.shadow_size = 14
	ring.add_theme_stylebox_override("panel", box)
	return ring


## The shop's loadout panel (patch 0.125): the same teal as the ability cards, with
## the gold trim the felt panel had.
static func teal_panel() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.043, 0.239, 0.251, 0.97)
	box.border_color = Color(0.831, 0.686, 0.216, 0.9)
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.content_margin_left = 16.0
	box.content_margin_top = 12.0
	box.content_margin_right = 16.0
	box.content_margin_bottom = 12.0
	return box
