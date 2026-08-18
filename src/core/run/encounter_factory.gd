class_name EncounterFactory
extends RefCounted
## Builds CombatSim configs from a run + chosen encounter option.
## Shared by the Game flow and the headless RunBot so rules never drift.
## Stage bands: encounters 1-3 -> stage 1, 4-6 -> 2, 7-9 -> 3, boss -> 99.
## Hard Combat: "advanced" draws from stage+1, "buffed" applies x1.25 HP/dmg.


static func combat_config(db: ContentDB, run: RunState,
		rng: RandomNumberGenerator, option: Dictionary) -> Dictionary:
	var encounter := run.history.size()
	var stage := clampi(((encounter - 1) / 3) + 1, 1, 3)
	var lineup_stage := stage
	var hp_mult := 1.0
	var dmg_mult := 1.0
	if option.type == &"boss":
		lineup_stage = ContentDB.BOSS_STAGE
	elif option.type == &"hard_combat":
		if str(option.get("variant", "buffed")) == "advanced":
			lineup_stage = mini(stage + 1, 3)
		else:
			hp_mult = 1.25
			dmg_mult = 1.25
	var lineups := db.lineups_for_stage(lineup_stage)
	var lineup: Dictionary = lineups[rng.randi_range(0, lineups.size() - 1)]
	return {
		"hero": run.hero_id,
		"hero_hp": run.hp,
		"abilities": run.ability_ids,
		"machine": run.machine,
		"enemies": lineup.enemies,
		"hp_mult": hp_mult,
		"dmg_mult": dmg_mult,
		"relics": run.relic_ids,
	}
