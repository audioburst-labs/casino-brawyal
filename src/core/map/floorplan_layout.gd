class_name FloorplanLayout
extends RefCounted
## Where everything sits on the Act I floorplan map (build 1.29): a long
## promenade with the Grand Lobby at its left end and Mr. Moneybags' penthouse at
## the right, and a pair of rooms off every stop from 2 to 9, one above the
## promenade and one below. Positions are in the painting's own pixels
## (`assets/map/act1_floorplan.jpg`, 1920 x 1072), measured off the art.
##
## Pure data and arithmetic so it can be tested; `FloorplanMap` draws it. The
## Act I rules are untouched: a path is still ten stops with a pair at each of 2
## to 9, and the game only ever asks which of the pair the player takes.

const STAGE := Vector2(1920, 1072)
const FIRST_STOP := 1
const LAST_STOP := 10
const PAIR_FIRST := 2
const PAIR_LAST := 9

## The promenade's centre line, and where it starts and ends.
const HALL_Y := 562.0
const HALL_START_X := 190.0
const HALL_END_X := 1650.0

## Stops 2 to 9 are eight columns of rooms, 175 px apart.
const COLUMN_X0 := 345.0
const COLUMN_STEP := 175.0
const ROOM_WIDTH := 150.0
const TOP_ROOM_Y := 112.0
const TOP_ROOM_HEIGHT := 325.0
const BOTTOM_ROOM_Y := 682.0
const BOTTOM_ROOM_HEIGHT := 216.0
const TOP_TOKEN_Y := 385.0
const BOTTOM_TOKEN_Y := 748.0
## Where a room's doorway meets the promenade.
const TOP_DOOR_Y := 437.0
const BOTTOM_DOOR_Y := 636.0

const LOBBY_TOKEN := Vector2(180, 540)
const PENTHOUSE_TOKEN := Vector2(1776, 540)
const LOBBY_RECT := Rect2(38, 326, 216, 428)
const PENTHOUSE_RECT := Rect2(1668, 298, 214, 484)


static func is_pair_stop(stop: int) -> bool:
	return stop >= PAIR_FIRST and stop <= PAIR_LAST


## One room at stops 1 (the lobby) and 10 (the penthouse), two in between.
static func slot_count(stop: int) -> int:
	return 2 if is_pair_stop(stop) else 1


## The x of the promenade in front of a stop's doors: where Ace stands to choose.
static func column_x(stop: int) -> float:
	if stop <= FIRST_STOP:
		return HALL_START_X
	if stop >= LAST_STOP:
		return HALL_END_X
	return COLUMN_X0 + COLUMN_STEP * float(stop - PAIR_FIRST)


static func ace_position(stop: int) -> Vector2:
	return Vector2(column_x(stop), HALL_Y)


## The room's floor on the painting (slot 0 above the promenade, 1 below).
static func room_rect(stop: int, slot: int) -> Rect2:
	if stop <= FIRST_STOP:
		return LOBBY_RECT
	if stop >= LAST_STOP:
		return PENTHOUSE_RECT
	var x := column_x(stop) - ROOM_WIDTH * 0.5
	if slot == 0:
		return Rect2(x, TOP_ROOM_Y, ROOM_WIDTH, TOP_ROOM_HEIGHT)
	return Rect2(x, BOTTOM_ROOM_Y, ROOM_WIDTH, BOTTOM_ROOM_HEIGHT)


## Where the room's marker sits: near the doorway, so a pair reads as two doors.
static func token_position(stop: int, slot: int) -> Vector2:
	if stop <= FIRST_STOP:
		return LOBBY_TOKEN
	if stop >= LAST_STOP:
		return PENTHOUSE_TOKEN
	return Vector2(column_x(stop), TOP_TOKEN_Y if slot == 0 else BOTTOM_TOKEN_Y)


## The doorway on the promenade side of a room.
static func door_position(stop: int, slot: int) -> Vector2:
	if not is_pair_stop(stop):
		return Vector2(column_x(stop), HALL_Y)
	return Vector2(column_x(stop), TOP_DOOR_Y if slot == 0 else BOTTOM_DOOR_Y)


## Which slot of `pair` a visited type was. A pair never repeats a type, so the
## first match is the room; an unknown type falls back to the top room.
static func slot_of(pair: Array, type: StringName) -> int:
	for slot in pair.size():
		if StringName(str(pair[slot])) == type:
			return slot
	return 0
