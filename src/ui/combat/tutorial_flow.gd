class_name TutorialFlow
extends Node
## The scripted first fight, as a script (doc "Tutorial"). The combat screen
## hands it the round-1 events and notifies it of what the player does; it
## decides what the teacher says next and drives `TutorialDirector`.
##
## The rules underneath are the real rules. `TutorialScript` fixes the dice and
## the Bouncer's opening move; this class only fixes the ORDER in which the
## screen reveals things and refuses drops that are not the one being taught.
##
## Steps (the doc's numbering in brackets):
##   banter  [2]  Ace / Bouncer / Ace, three seconds apiece
##   machine [3]  dimmed screen, reels turning, "let's get started with some chips"
##   sling   [5]  chip tray + Card Sling lit, ghost hand: Club onto Card Sling
##   quick   [7]  Bouncer + Quick Maneuvers + tray lit: Diamond onto Quick Maneuvers
##   final   [8]  "Final chip, where should it go?" with an arrow to the tray
##   pass    [9]  "Round's up, go next" beside Pass
##   free    [10] ordinary combat; the round-3 jackpot hint is the one exception

enum Step { BANTER, MACHINE, SLING, QUICK, FINAL, PASS, FREE }

const LINE_ACE_1 := "Move aside, Mr. Moneybags is gonna pay."
const LINE_BOUNCER := "No way pal, get lost, or I'll make you leave."
const LINE_ACE_2 := "Hard way it is. Let's play."
const LINE_START := "Let's get started with some chips."
const LINE_SLING := "Let's try that."
const LINE_QUICK := "This is gonna hurt. Let's get some protection going."
const LINE_FINAL := "Final chip, where should it go?"
const LINE_PASS := "Round's up, go next."
const LINE_JACKPOT := "JACKPOT! Triple hearts for a bonus one!"
const BEAT := 3.0                         # the doc's "after 3 seconds"

var screen: Node = null                   # the combat screen
var director: TutorialDirector = null
var step: Step = Step.BANTER


func begin(combat_screen: Node) -> void:
	screen = combat_screen
	director = TutorialDirector.new()
	screen.add_child(director)


# ------------------------------------------------------ targets (late-bound)

func _machine() -> Control:
	return screen.tutorial_target(&"machine")


func _tray() -> Control:
	return screen.tutorial_target(&"tray")


func _hero() -> Control:
	return screen.tutorial_target(&"hero")


func _bouncer() -> Control:
	return screen.tutorial_target(&"enemy")


func _pass_button() -> Control:
	return screen.tutorial_target(&"pass")


func _card(id: StringName) -> Control:
	return screen.tutorial_card(id)


# ------------------------------------------------------------- round one

## Plays round 1's events with the teacher in the gaps. Returns when the
## player's first prompt is on screen, so the caller can open the board.
func play_opening(events: Array[CombatEvent]) -> void:
	var intents_at := _index_of(events, &"intents_shown")
	var spin_at := _index_of(events, &"spin_resolved")
	if intents_at < 0 or spin_at < 0 or spin_at < intents_at:
		# Not the shape this script was written for: play it plainly.
		await screen.tutorial_play(events)
		step = Step.FREE
		return
	# Everything before the intents (the round banner, relic beats...).
	await screen.tutorial_play(events.slice(0, intents_at))

	# [2] The banter. Ace's first line stays up while the Bouncer answers.
	step = Step.BANTER
	director.say("ace", LINE_ACE_1, false, _hero, "right")
	await _wait(BEAT)
	director.say("bouncer", LINE_BOUNCER, false, _bouncer, "left")
	await _wait(BEAT)
	director.hush("ace")
	director.say("ace2", LINE_ACE_2, false, _hero, "right")
	await _wait(BEAT)
	director.hush_all()
	await _wait(0.35)

	# [3] The machine, still turning. The Bouncer shows what he means to do.
	step = Step.MACHINE
	director.spotlight([_machine])
	screen.tutorial_idle_spin()
	director.say("machine", LINE_START, true, _machine, "right")
	await screen.tutorial_play(events.slice(intents_at, spin_at))
	await _wait(BEAT)
	director.hush("machine")

	# [4] It stops and pays 2 Clubs and a Diamond.
	await screen.tutorial_play(events.slice(spin_at))
	await _wait(0.25)
	_enter_sling()


func _index_of(events: Array[CombatEvent], type: StringName) -> int:
	for i in events.size():
		if events[i].type == type:
			return i
	return -1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ----------------------------------------------------------------- steps

func _enter_sling() -> void:
	step = Step.SLING
	director.spotlight([_tray, func() -> Control: return _card(&"card_sling")])
	director.say("sling", LINE_SLING, true, func() -> Control: return _card(&"card_sling"), "above")
	director.demo_drag(func() -> Control: return screen.tutorial_chip(&"club"),
		func() -> Control: return _socket(&"card_sling"), &"club")


func _enter_quick() -> void:
	step = Step.QUICK
	director.spotlight([_bouncer, _tray, func() -> Control: return _card(&"quick_maneuvers")])
	director.say("quick", LINE_QUICK, true,
		func() -> Control: return _card(&"quick_maneuvers"), "above")
	director.demo_drag(func() -> Control: return screen.tutorial_chip(&"diamond"),
		func() -> Control: return _socket(&"quick_maneuvers"), &"diamond")


func _enter_final() -> void:
	step = Step.FINAL
	director.say("final", LINE_FINAL, true, _machine, "right")
	director.arrow("final", _tray)


func _enter_pass() -> void:
	step = Step.PASS
	director.say("pass", LINE_PASS, true, _pass_button, "left")


func _socket(id: StringName) -> Control:
	var card: Variant = _card(id)
	if card != null and card.has_method("socket_button"):
		return card.socket_button(0)
	return null


# --------------------------------------------------- what the player does

## May this chip go here right now? Only the placement being taught is
## accepted while a step is waiting for it; everything else is free.
func allows_drop(ability_id: StringName, suit: StringName) -> bool:
	match step:
		Step.BANTER, Step.MACHINE:
			return false
		Step.SLING:
			return ability_id == &"card_sling" and suit == &"club"
		Step.QUICK:
			return ability_id == &"quick_maneuvers" and suit == &"diamond"
	return true


func allows_pass() -> bool:
	return step == Step.PASS or step == Step.FREE


## A chip went into a socket (before its events play).
func on_chip_assigned() -> void:
	match step:
		Step.SLING:
			director.stop_demo()
			director.hush("sling")
			director.lights_up()
		Step.QUICK:
			director.stop_demo()
			director.hush("quick")
			director.lights_up()
		Step.FINAL:
			director.hush("final")
			director.clear_arrow()
	if director.has_bubble("jackpot"):
		director.hush("jackpot")
		director.clear_arrow()


## The events of that placement have finished playing: on to the next prompt.
func on_resolved() -> void:
	match step:
		Step.SLING:
			_enter_quick()
		Step.QUICK:
			_enter_final()
		Step.FINAL:
			_enter_pass()


func on_pass() -> void:
	if step == Step.PASS:
		director.hush("pass")
		step = Step.FREE


## A spin has finished showing. Round 3 is the Hearts: a bonus chip is on
## the table and the teacher points at it.
func on_spin_shown(round_number: int) -> void:
	if round_number != 3:
		return
	director.say("jackpot", LINE_JACKPOT, true, _machine, "right")
	director.arrow("jackpot", _machine)
