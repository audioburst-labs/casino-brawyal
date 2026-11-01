class_name IntroComicScript
extends RefCounted
## The opening comic (patch 0.129): Ace wins a hand, is shown the door, and walks
## back with a burning Ace of Spades. A two-page spread laid out on a 1920 x 1080
## stage, whose panels fade in one after another.
##
## Everything here is data and arithmetic so it can be tested. `IntroComic` draws
## it. The panels differ in size but share one even gutter (designer, 0.129).

const STAGE := Vector2(1920, 1080)
const GUTTER := 10.0
const PAGE_PADDING := 12.0
const PAGES: Array[Rect2] = [Rect2(60, 40, 880, 1000), Rect2(980, 40, 880, 1000)]
## How long one panel takes to fade in, and how long after it its caption follows.
const FADE := 0.45
const CAPTION_DELAY := 0.6

## The last panel is in and the logo has finished fading: the spread is at rest.
const COMPLETE_AT := 17.3
const LOGO_AT := 16.6
const LOGO_FADE := 0.7
## Skip hands over to Play once the last panel is arriving, and Play then swells
## and shrinks to say "this is the button".
const SKIP_FADE_AT := 16.0
const SKIP_FADE := 0.35
const PLAY_AT := 16.2
const PLAY_FADE := 0.35
const PULSE_PERIOD := 1.3
const PULSE_DEPTH := 0.07
## The neon logo flickers over the last panel, now and then dipping to this.
const FLICKER_DIM := 0.3

const LOGO := "res://assets/ui/title/logo_intro.png"
const BACKDROP := "res://assets/backgrounds/bg_title.png"
const MUSIC := &"story"
## Where the logo sits on the stage: the open sky of the last panel, clear of the flames.
const LOGO_RECT := Rect2(1536, 396, 290, 195)

const _PICTURE := "res://assets/story/intro/panel_%d.jpg"
## id, cell, fx, fy (where the crop sits in the picture), reveal time, caption.
const _CELLS: Array[Dictionary] = [
	{"rect": Rect2(72, 52, 520, 300), "fx": 0.5, "fy": 0.6, "reveal": 1.0,
		"caption": {"text": "Straight flush.", "pos": Vector2(344, 58), "size": 26}},
	{"rect": Rect2(602, 52, 326, 300), "fx": 0.35, "fy": 0.5, "reveal": 3.4,
		"caption": {"text": "The pot is his.", "pos": Vector2(608, 58), "size": 20}},
	{"rect": Rect2(72, 362, 856, 330), "fx": 0.5, "fy": 0.45, "reveal": 5.8,
		"caption": {"text": "Take him out.", "pos": Vector2(78, 368), "size": 26}},
	{"rect": Rect2(72, 702, 856, 326), "fx": 0.5, "fy": 0.4, "reveal": 8.2,
		"caption": {"text": "He never sees them coming.", "pos": Vector2(78, 708), "size": 26}},
	{"rect": Rect2(992, 52, 520, 330), "fx": 0.5, "fy": 0.5, "reveal": 11.0, "caption": {}},
	{"rect": Rect2(1522, 52, 326, 330), "fx": 0.5, "fy": 0.5, "reveal": 13.2, "caption": {}},
	{"rect": Rect2(992, 392, 856, 636), "fx": 0.2, "fy": 0.5, "reveal": 15.6,
		"caption": {"text": "He is not done.", "pos": Vector2(998, 968), "size": 26}},
]


## Each panel: id (1 to 7), rect (stage pixels), texture path, fx / fy, reveal
## (seconds from the start) and caption ({} for none, else text, pos, size).
static func panels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in _CELLS.size():
		var cell: Dictionary = _CELLS[i]
		out.append({
			"id": i + 1,
			"rect": cell.rect,
			"texture": _PICTURE % (i + 1),
			"fx": cell.fx,
			"fy": cell.fy,
			"reveal": cell.reveal,
			"caption": cell.caption,
		})
	return out


## 0 before `start`, 1 once `fade` seconds have passed.
static func alpha_at(t: float, start: float, fade: float) -> float:
	return clampf((t - start) / maxf(fade, 0.0001), 0.0, 1.0)


## Where a picture goes inside a cell so it covers the cell, keeping its shape.
## `fx` / `fy` pick which part is kept: 0 pins the left / top edge, 1 the right / bottom.
## The returned position is relative to the cell (zero or negative).
static func cover_rect(cell: Vector2, tex: Vector2, fx: float, fy: float) -> Rect2:
	var scale := maxf(cell.x / tex.x, cell.y / tex.y)
	var size := tex * scale
	return Rect2(Vector2((cell.x - size.x) * fx, (cell.y - size.y) * fy), size)


## The logo's brightness: lit, apart from short dips.
static func flicker(t: float) -> float:
	return FLICKER_DIM if sin(t * 47.0) * sin(t * 13.1) > 0.9 else 1.0


## How much bigger the Play button is than its resting size.
static func pulse(t: float) -> float:
	if t < PLAY_AT:
		return 1.0
	return 1.0 + PULSE_DEPTH * (1.0 - cos(TAU * (t - PLAY_AT) / PULSE_PERIOD))
