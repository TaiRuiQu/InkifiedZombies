class_name UpgradeDB
extends RefCounted

## Roguelite choice pool. `effects` keys are merged into the player's stat
## dictionary by Player.apply_upgrade().

const RARITY_NAMES := ["凡品", "妙品", "绝品", "神品"]
const RARITY_COLORS := [Color("8a8273"), Color("49687c"), Color("a93226"), Color("c9a44f")]
const RARITY_WEIGHTS := [1.0, 0.55, 0.22, 0.055]

static var LIST := [
	# ---------------- Common ----------------
	{"id": "damage", "name": "锋毫", "icon": "锋", "rarity": 0, "tag": "攻伐",
		"desc": "毫尖再利三分。\n所有武器伤害 +12%。", "weight": 12, "max_stack": 8,
		"effects": {"damage_mult_add": 0.12}},
	{"id": "speed", "name": "疾步", "icon": "疾", "rarity": 0, "tag": "身法",
		"desc": "身随墨走。\n移动速度 +7%。", "weight": 9, "max_stack": 5,
		"effects": {"move_speed_mult_add": 0.07}},
	{"id": "health", "name": "铁骨", "icon": "骨", "rarity": 0, "tag": "护体",
		"desc": "以骨为笔架。\n血上限 +20，并立即回复 20 点。", "weight": 10, "max_stack": 6,
		"effects": {"max_health_add": 20.0, "heal_flat": 20.0}},
	{"id": "shield", "name": "护体墨甲", "icon": "护", "rarity": 0, "tag": "护体",
		"desc": "墨凝成甲。\n获得 20 点护体，护体会自行恢复。", "weight": 9, "max_stack": 5,
		"effects": {"shield_add": 20.0}},
	{"id": "reload", "name": "快装", "icon": "装", "rarity": 0, "tag": "兵刃",
		"desc": "换墨如风。\n装填速度 +12%。", "weight": 9, "max_stack": 5,
		"effects": {"reload_mult_add": 0.12}},
	{"id": "mag", "name": "广匣", "icon": "匣", "rarity": 0, "tag": "兵刃",
		"desc": "匣中另有天地。\n弹匣容量 +15%。", "weight": 8, "max_stack": 5,
		"effects": {"mag_mult_add": 0.15}},
	{"id": "steady", "name": "沉稳", "icon": "稳", "rarity": 0, "tag": "攻伐",
		"desc": "心静，手稳。\n散布 -10%，后坐力 -12%。", "weight": 8, "max_stack": 4,
		"effects": {"spread_mult_add": -0.10, "recoil_mult_add": -0.12}},
	{"id": "scavenge", "name": "拾荒", "icon": "拾", "rarity": 0, "tag": "兵刃",
		"desc": "战场处处是墨。\n备弹上限 +25%。", "weight": 7, "max_stack": 3,
		"effects": {"reserve_mult_add": 0.25}},
	{"id": "regen_kill", "name": "回血", "icon": "血", "rarity": 0, "tag": "护体",
		"desc": "杀敌补血。\n每次击杀回复 3 血。", "weight": 8, "max_stack": 5,
		"effects": {"heal_on_kill_add": 3.0}},
	{"id": "heal_now", "name": "小憩", "icon": "息", "rarity": 0, "tag": "护体",
		"desc": "暂歇片刻。\n立即回复 35% 血。", "weight": 5, "max_stack": 99,
		"effects": {"heal_percent": 0.35}},
	{"id": "melee", "name": "笔力", "icon": "力", "rarity": 0, "tag": "攻伐",
		"desc": "以笔当棍。\n近战伤害 +80%，击退更强。", "weight": 6, "max_stack": 4,
		"effects": {"melee_mult_add": 0.8, "melee_push_add": 3.0}},

	# ---------------- Rare ----------------
	{"id": "crit", "name": "朱砂", "icon": "朱", "rarity": 1, "tag": "攻伐",
		"desc": "点朱成煞。\n暴击率 +8%，暴击伤害 +20%。", "weight": 10, "max_stack": 4,
		"effects": {"crit_chance_add": 0.08, "crit_mult_add": 0.2}},
	{"id": "pierce", "name": "穿墨", "icon": "穿", "rarity": 1, "tag": "攻伐",
		"desc": "墨锋透纸。\n子弹额外穿透 1 个敌人。", "weight": 8, "max_stack": 3,
		"effects": {"pierce_add": 1}},
	{"id": "ice", "name": "冰墨", "icon": "冰", "rarity": 1, "tag": "术法",
		"desc": "寒墨凝滞。\n命中使敌人减速 25%，持续 2 秒。", "weight": 8, "max_stack": 2,
		"effects": {"slow_on_hit_add": 0.25}},
	{"id": "lifesteal", "name": "吸血", "icon": "血", "rarity": 1, "tag": "护体",
		"desc": "墨血同源。\n造成伤害的 3% 转化为血。", "weight": 7, "max_stack": 4,
		"effects": {"lifesteal_add": 0.03}},
	{"id": "dash", "name": "疾风步", "icon": "风", "rarity": 1, "tag": "身法",
		"desc": "踏墨无痕。\n解锁身法：按 E 疾冲，冲刺时无敌。", "weight": 9, "max_stack": 1,
		"effects": {"unlock": "dash"}},
	{"id": "nova", "name": "墨爆", "icon": "爆", "rarity": 1, "tag": "术法",
		"desc": "泼墨成雷。\n解锁术法：按 Q 以自身为中心爆开墨环。", "weight": 9, "max_stack": 1,
		"effects": {"unlock": "nova"}},
	{"id": "talisman", "name": "火符", "icon": "符", "rarity": 1, "tag": "术法",
		"desc": "符纸离手，业火随行。\n解锁术法：按 G 掷出爆炸火符。", "weight": 8, "max_stack": 1,
		"effects": {"unlock": "talisman"}},
	{"id": "firerate", "name": "弹雨", "icon": "雨", "rarity": 1, "tag": "兵刃",
		"desc": "笔走龙蛇。\n射速 +15%。", "weight": 9, "max_stack": 4,
		"effects": {"fire_rate_mult_add": 0.15}},
	{"id": "thorns", "name": "反震", "icon": "震", "rarity": 1, "tag": "护体",
		"desc": "墨甲有刺。\n近战攻击你的敌人受到 8 点伤害。", "weight": 6, "max_stack": 3,
		"effects": {"thorns_add": 8.0}},
	{"id": "chain", "name": "雷咒", "icon": "雷", "rarity": 1, "tag": "术法",
		"desc": "墨中藏雷。\n射击时会周期性引下连锁闪电，最多跳跃三次。", "weight": 7, "max_stack": 2,
		"effects": {"chain_add": 1}},
	{"id": "ammo_regen", "name": "归元", "icon": "元", "rarity": 1, "tag": "兵刃",
		"desc": "墨自虚空来。\n每秒回复 1.5 点备弹。", "weight": 6, "max_stack": 2,
		"effects": {"ammo_regen_add": 1.5}},
	{"id": "shield_blast", "name": "裂甲", "icon": "甲", "rarity": 1, "tag": "护体",
		"desc": "甲碎之时，墨浪反噬。\n护体被击破时引发爆炸。", "weight": 6, "max_stack": 1,
		"requires_shield": true, "effects": {"shield_break_blast_add": 1}},
	{"id": "dash_mastery", "name": "踏风", "icon": "踏", "rarity": 1, "tag": "身法",
		"desc": "身在风中，刃亦随风。\n疾冲冷却 -30%，疾冲造成伤害。", "weight": 7, "max_stack": 1,
		"requires_unlock": "dash", "effects": {"dash_cd_mult_add": -0.3, "dash_damage_add": 45.0}},
	{"id": "nova_mastery", "name": "墨海", "icon": "海", "rarity": 1, "tag": "术法",
		"desc": "一滴墨，倾作海。\n墨爆范围 +2，伤害 +40%。", "weight": 6, "max_stack": 1,
		"requires_unlock": "nova", "effects": {"nova_radius_add": 2.0, "nova_damage_mult_add": 0.4}},
	{"id": "talisman_mastery", "name": "焚符", "icon": "焚", "rarity": 1, "tag": "术法",
		"desc": "符火连天。\n火符范围 +2，伤害 +50%。", "weight": 6, "max_stack": 1,
		"requires_unlock": "talisman", "effects": {"talisman_radius_add": 2.0, "talisman_damage_mult_add": 0.5}},

	# ---------------- Weapons ----------------
	{"id": "w_shotgun", "name": "泼墨铳", "icon": "铳", "rarity": 1, "tag": "兵刃",
		"desc": "近距离泼出一整砚墨。\n解锁新武器，立即装备。", "weight": 16, "max_stack": 1,
		"weapon": "ink_shotgun", "effects": {"weapon": "ink_shotgun"}},
	{"id": "w_smg", "name": "狼毫", "icon": "狼", "rarity": 1, "tag": "兵刃",
		"desc": "笔锋如狼群扑食。\n解锁高射速冲锋枪。", "weight": 14, "max_stack": 1,
		"weapon": "wolf_smg", "effects": {"weapon": "wolf_smg"}},
	{"id": "w_rifle", "name": "朱砂步枪", "icon": "砂", "rarity": 2, "tag": "兵刃",
		"desc": "一笔朱砂，贯骨透纸。\n解锁高伤害穿透步枪。", "weight": 10, "max_stack": 1,
		"weapon": "cinnabar_rifle", "effects": {"weapon": "cinnabar_rifle"}},
	{"id": "w_launcher", "name": "泼墨炮", "icon": "炮", "rarity": 2, "tag": "兵刃",
		"desc": "把一池浓墨砸在地上。\n解锁范围爆破武器。", "weight": 8, "max_stack": 1,
		"weapon": "ink_launcher", "effects": {"weapon": "ink_launcher"}},
	{"id": "w_crossbow", "name": "雷纹弩", "icon": "弩", "rarity": 2, "tag": "兵刃",
		"desc": "弩矢绘着雷纹，可贯一列。\n解锁高穿透武器。", "weight": 8, "max_stack": 1,
		"weapon": "thunder_crossbow", "effects": {"weapon": "thunder_crossbow"}},

	# ---------------- Epic ----------------
	{"id": "big", "name": "大器", "icon": "器", "rarity": 2, "tag": "攻伐",
		"desc": "重笔之下，纸无完卵。\n伤害 +28%，但散布 +12%。", "weight": 7, "max_stack": 2,
		"effects": {"damage_mult_add": 0.28, "spread_mult_add": 0.12}},
	{"id": "crit2", "name": "会心", "icon": "心", "rarity": 2, "tag": "攻伐",
		"desc": "笔意通神。\n暴击率 +15%，暴击伤害 +40%。", "weight": 6, "max_stack": 2,
		"effects": {"crit_chance_add": 0.15, "crit_mult_add": 0.4}},
	{"id": "multishot", "name": "多锋", "icon": "多", "rarity": 2, "tag": "攻伐",
		"desc": "一笔化双锋。\n每次射击额外射出一发弹丸。", "weight": 6, "max_stack": 2,
		"effects": {"multishot_add": 1}},
	{"id": "frenzy", "name": "狂墨", "icon": "狂", "rarity": 2, "tag": "兵刃",
		"desc": "墨走狂草。\n射速 +25%，后坐力 +12%。", "weight": 6, "max_stack": 2,
		"effects": {"fire_rate_mult_add": 0.25, "recoil_mult_add": 0.12}},
	{"id": "endless", "name": "无尽", "icon": "尽", "rarity": 2, "tag": "兵刃",
		"desc": "墨池不竭。\n每秒回复 3 点备弹。", "weight": 5, "max_stack": 1,
		"effects": {"ammo_regen_add": 3.0}},
	{"id": "kill_nova", "name": "墨龙", "icon": "龙", "rarity": 2, "tag": "术法",
		"desc": "杀意积成墨龙。\n每累计 10 次击杀，释放一次墨环。", "weight": 5, "max_stack": 1,
		"effects": {"kill_nova_add": 1}},
	{"id": "explosive", "name": "裂帛", "icon": "裂", "rarity": 2, "tag": "攻伐",
		"desc": "命中之处，纸裂墨溅。\n子弹命中时引发小范围爆炸。", "weight": 5, "max_stack": 1,
		"effects": {"explosive_add": 1}},

	# ---------------- Legendary ----------------
	{"id": "godbrush", "name": "神笔", "icon": "神", "rarity": 3, "tag": "攻伐",
		"desc": "此笔非人间物。\n伤害 +40%，射速 +15%，装填 +20%。", "weight": 3, "max_stack": 1,
		"effects": {"damage_mult_add": 0.40, "fire_rate_mult_add": 0.15, "reload_mult_add": 0.20}},
	{"id": "immortal", "name": "不灭", "icon": "灭", "rarity": 3, "tag": "护体",
		"desc": "墨尽，魂不灭。\n每局一次：致死伤害改为回复 50% 血并震退敌人。", "weight": 2, "max_stack": 1,
		"effects": {"revive_add": 1}},
	{"id": "allpierce", "name": "万墨归宗", "icon": "宗", "rarity": 3, "tag": "攻伐",
		"desc": "万法归一，一墨万形。\n所有武器额外穿透 1 个敌人，并多射出一发。", "weight": 2, "max_stack": 1,
		"effects": {"pierce_add": 1, "multishot_add": 1}},
]


static func rarity_name(rarity: int) -> String:
	return RARITY_NAMES[clampi(rarity, 0, 3)]


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, 3)]


static func _available(player) -> Array:
	var out := []
	for u in LIST:
		var taken: int = player.upgrade_counts.get(u.id, 0)
		if taken >= int(u.max_stack):
			continue
		if u.effects.has("unlock") and player.skills.get(u.effects.unlock, false):
			continue
		if u.has("weapon") and player.owned_weapons.has(u.weapon):
			continue
		if u.has("requires_unlock") and not player.skills.get(u.requires_unlock, false):
			continue
		if u.has("requires_shield") and player.get_shield_max() <= 0.01:
			continue
		out.append(u)
	return out


static func _weight(u: Dictionary, wave: int) -> float:
	var r: int = int(u.rarity)
	var base: float = float(u.weight) * RARITY_WEIGHTS[r]
	if r >= 1:
		base *= 1.0 + minf(float(wave) * 0.02, 0.8)
	if r >= 2:
		base *= 1.0 + minf(float(wave) * 0.012, 0.5)
	return maxf(base, 0.01)


static func _pick_index(pool: Array, wave: int) -> int:
	var total := 0.0
	for u in pool:
		total += _weight(u, wave)
	var roll := randf() * total
	for i in pool.size():
		roll -= _weight(pool[i], wave)
		if roll <= 0.0:
			return i
	return maxi(pool.size() - 1, 0)


static func roll(player, wave: int, count: int = 3, previous: Array = []) -> Array:
	var pool := _available(player)
	# Prefer new cards without discarding prerequisite or stack restrictions.
	var fresh := pool.filter(func(u): return not _has_id(previous, u.id))
	if fresh.size() >= count:
		pool = fresh
	var picks: Array = []
	if pool.is_empty():
		return picks

	# Guarantee a new weapon until the player has a real primary.
	if player.owned_weapons.size() < 2:
		var weapon_pool := []
		for u in pool:
			if u.has("weapon"):
				weapon_pool.append(u)
		if not weapon_pool.is_empty():
			var idx := _pick_index(weapon_pool, wave)
			picks.append(weapon_pool[idx])
			var chosen_id: String = weapon_pool[idx].id
			for i in range(pool.size() - 1, -1, -1):
				if pool[i].id == chosen_id:
					pool.remove_at(i)
					break

	while picks.size() < count and not pool.is_empty():
		var idx := _pick_index(pool, wave)
		picks.append(pool[idx])
		pool.remove_at(idx)

	# Fallback filler so the screen always has three choices.
	if picks.size() < count and not _has_id(picks, "heal_now"):
		for u in LIST:
			if u.id == "heal_now":
				picks.append(u)
				break
	while picks.size() < count:
		for u in LIST:
			if not _has_id(picks, u.id):
				picks.append(u)
				break
		if picks.size() >= count:
			break
		break
	return picks


static func _has_id(arr: Array, id: String) -> bool:
	for u in arr:
		if u.id == id:
			return true
	return false
