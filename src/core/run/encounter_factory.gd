class_name EncounterFactory
extends RefCounted
## Builds CombatSim configs from a run + chosen encounter option.
## Shared by the Game flow and the headless RunBot so rules never drift.
##
## Lineup stages follow the capabilities sheet: enc 1 -> 1, 2-3 -> 2, 4-5 -> 3,
## 6-7 -> 4, 8-9 -> 5, boss -> 6. An Elite ignores the ladder entirely and
## draws from the sheet's own Elites pool (patch 0.22). The chosen lineup's
## gold range rides along in the config for the reward screen.

const MAX_NORMAL_STAGE := 5


static func stage_for_encounter(encounter: int) -> int:
	if encounter <= 1:
		return 1
	return clampi(2 + (encounter - 2) / 2, 2, MAX_NORMAL_STAGE)


static func combat_config(db: ContentDB, run: RunState,
		rng: RandomNumberGenerator, option: Dictionary) -> Dictionary:
	var encounter := run.history.size()
	var lineup_stage := stage_for_encounter(encounter)
	var hp_mult := 1.0
	var dmg_mult := 1.0
	if option.type == &"boss":
		lineup_stage = ContentDB.BOSS_STAGE
	var lineups := db.elite_lineups() if option.type == &"elite" \
		else db.lineups_for_stage(lineup_stage)
	var lineup: Dictionary = lineups[rng.randi_range(0, lineups.size() - 1)]
	# A resumed encounter names the lineup it was fighting (0.0.111), so the
	# same fight comes back rather than a fresh roll.
	var pinned := StringName(str(option.get("lineup", "")))
	if pinned != &"":
		for candidate: Dictionary in db.all_lineups():
			if candidate.id == pinned:
				lineup = candidate
				break
	return {
		"lineup": lineup.id,
		"hero": run.hero_id,
		"hero_hp": run.hp,
		"abilities": run.equipped_ids,
		"ability_tiers": run.ability_tiers,
		"machine": run.machine,
		"enemies": lineup.enemies,
		"hp_mult": hp_mult,
		"dmg_mult": dmg_mult,
		"relics": run.relic_ids,
		"gold_min": lineup.gold_min,
		"gold_max": lineup.gold_max,
	}
