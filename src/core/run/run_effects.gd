class_name RunEffects
extends RefCounted
## Applies run-level effect ops (story choices, combat pending_rewards) to a
## RunState. Returns human-readable summary lines for the UI to show.


const SUITS: Array[StringName] = [&"spade", &"heart", &"club", &"diamond"]


## The sheet prices most story outcomes as "[Encounter Value X n]", so the
## same card is worth more the deeper you take it. Encounter 1 still pays,
## which is why this multiplies rather than using (n - 1).
static func _scaled(effect: Dictionary, run: RunState) -> int:
	return int(effect.get("per_encounter", 0)) * run.encounter_number()


static func apply(effects: Array, db: ContentDB, run: RunState,
		rng: RandomNumberGenerator) -> Array[String]:
	var lines: Array[String] = []
	for effect: Dictionary in effects:
		match str(effect.get("op", "")):
			"gain_coins":
				var amount := rng.randi_range(int(effect.get("min", 0)), int(effect.get("max", 0)))
				if effect.has("amount"):
					amount = int(effect.get("amount"))
				if effect.has("per_encounter"):
					amount = _scaled(effect, run)
				run.coins += amount
				lines.append("+%d coins" % amount)
			"lose_coins":
				var cost := _scaled(effect, run) if effect.has("per_encounter") \
					else int(effect.get("amount", 0))
				var loss: int = mini(run.coins, cost)
				run.coins -= loss
				lines.append("-%d coins" % loss)
			"lose_hp":
				var hp_loss := _scaled(effect, run) if effect.has("per_encounter") \
					else int(effect.get("amount", 0))
				run.hp = maxi(1, run.hp - hp_loss)  # story wounds never kill outright
				lines.append("-%d HP" % hp_loss)
			"grant_sticker":
				var suit := StringName(str(effect.get("suit", "random")))
				if suit == &"random":
					suit = SUITS[rng.randi_range(0, SUITS.size() - 1)]
				run.sticker_inventory.append(suit)
				lines.append("Sticker: %s" % String(suit).capitalize())
			"casino_spin":
				# The sheet's note on Lost Soul: the reward IS a pull on the
				# Casino's prize table, so it resolves here rather than routing
				# to the casino screen for a visit the player did not spend.
				lines.append_array(CasinoGame.spin(db, run, rng).lines)
			"heal_pct":
				var heal := int(ceil(run.max_hp * float(effect.get("pct", 0.0))))
				var healed: int = mini(heal, run.max_hp - run.hp)
				run.hp += healed
				lines.append("+%d HP" % healed)
			"gain_max_hp":
				var bonus := int(effect.get("amount", 0))
				run.max_hp += bonus
				run.hp += bonus
				lines.append("+%d max HP" % bonus)
			"grant_relic":
				var relic := Rewards.random_unowned_relic(db, run, rng)
				if relic != &"":
					run.relic_ids.append(relic)
					lines.append("Relic: %s" % db.get_relic(relic).name)
				else:
					lines.append("No relics left to find")
			var other:
				push_warning("RunEffects: op '%s' has no run-level meaning" % other)
	return lines
