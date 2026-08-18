class_name RunEffects
extends RefCounted
## Applies run-level effect ops (story choices, combat pending_rewards) to a
## RunState. Returns human-readable summary lines for the UI to show.


static func apply(effects: Array, db: ContentDB, run: RunState,
		rng: RandomNumberGenerator) -> Array[String]:
	var lines: Array[String] = []
	for effect: Dictionary in effects:
		match str(effect.get("op", "")):
			"gain_coins":
				var amount := rng.randi_range(int(effect.get("min", 0)), int(effect.get("max", 0)))
				if effect.has("amount"):
					amount = int(effect.get("amount"))
				run.coins += amount
				lines.append("+%d coins" % amount)
			"lose_coins":
				var loss: int = mini(run.coins, int(effect.get("amount", 0)))
				run.coins -= loss
				lines.append("-%d coins" % loss)
			"lose_hp":
				var hp_loss := int(effect.get("amount", 0))
				run.hp = maxi(1, run.hp - hp_loss)  # story wounds never kill outright
				lines.append("-%d HP" % hp_loss)
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
