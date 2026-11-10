class_name RunRules
extends RefCounted

## Session tuning is shared by the wave director, combat and UI.
const TARGET_WAVES := 10
const ENEMY_SPEED_MULTIPLIER := 1.18
const IMPACT_SLOW_DURATION := 0.28
const DIFFICULTIES := {
	"story": {"name": "初入墨境", "budget": 0.8, "enemy_health": 0.85,
		"incoming_damage": 0.65, "recovery": 0.18, "reserve_refill": 0.5},
	"standard": {"name": "守夜人", "budget": 1.0, "enemy_health": 1.0,
		"incoming_damage": 1.0, "recovery": 0.12, "reserve_refill": 0.4},
	"ordeal": {"name": "墨潮试炼", "budget": 1.18, "enemy_health": 1.12,
		"incoming_damage": 1.25, "recovery": 0.08, "reserve_refill": 0.3},
}

static func difficulty(id: String) -> Dictionary:
	return DIFFICULTIES.get(id, DIFFICULTIES.standard)

static func wave_plan(wave: int, difficulty_id: String) -> Dictionary:
	var boss_wave := wave % 5 == 0
	var budget := 6.0 + float(wave) * 4.2 + pow(float(wave), 1.2) * 0.6
	if boss_wave:
		budget = 6.0 + float(wave) * 1.65
	return {"boss": boss_wave, "budget": budget * float(difficulty(difficulty_id).budget),
		"alive_cap": mini(6 + wave, 20), "spawn_interval": maxf(0.5, 1.3 - float(wave) * 0.06),
		"opening_delay": 2.6 if wave == 1 else 1.7}
