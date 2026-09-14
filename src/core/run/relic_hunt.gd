class_name RelicHunt
extends RefCounted
## The Casino's "Find the Relic" (doc v0.120): five cards — one blank, three
## holding [Encounter Number x 5] gold, and one holding a random unowned relic.
## The player shuffles them face down, picks one, and takes what is on it; the
## other four are revealed a moment later.
##
## Pure logic — the screen deals, shuffles and flips; this owns the deck.

enum Kind { BLANK, GOLD, RELIC }

const GOLD_PER_ENCOUNTER := 5
const CARDS := 5

## One entry per card, in their (shuffled) table order:
## {"kind": Kind, "value": int, "relic": StringName}
var cards: Array[Dictionary] = []
var revealed := -1


## Builds the five cards for this visit. With no unowned relic left the relic
## card pays gold instead, so the table is never short a card.
static func build(db: ContentDB, run: RunState, rng: RandomNumberGenerator) -> RelicHunt:
	var hunt := RelicHunt.new()
	var gold := GOLD_PER_ENCOUNTER * run.encounter_number()
	hunt.cards.append({"kind": Kind.BLANK, "value": 0, "relic": &""})
	for i in 3:
		hunt.cards.append({"kind": Kind.GOLD, "value": gold, "relic": &""})
	var relic := Rewards.random_unowned_relic(db, run, rng)
	if relic == &"":
		hunt.cards.append({"kind": Kind.GOLD, "value": gold, "relic": &""})
	else:
		hunt.cards.append({"kind": Kind.RELIC, "value": 0, "relic": relic})
	return hunt


## Fisher-Yates, so the player cannot follow a card by where it started.
func shuffle(rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cards[i]
		cards[i] = cards[j]
		cards[j] = swap
	revealed = -1


func has_relic() -> bool:
	return cards.any(func(card: Dictionary) -> bool: return int(card.kind) == Kind.RELIC)


## Turns one card face up. Only the first pick counts.
func reveal(index: int) -> Dictionary:
	if revealed >= 0 or index < 0 or index >= cards.size():
		return {}
	revealed = index
	return cards[index]


## Applies the revealed card and returns the line to show for it.
func claim(db: ContentDB, run: RunState) -> String:
	if revealed < 0:
		return ""
	var card: Dictionary = cards[revealed]
	match int(card.kind):
		Kind.GOLD:
			run.coins += int(card.value)
			return "+%d coins" % int(card.value)
		Kind.RELIC:
			var relic: StringName = card.relic
			run.relic_ids.append(relic)
			var def := db.get_relic(relic)
			return "Relic: %s!" % (def.name if def else String(relic))
	return "Nothing but table felt."
