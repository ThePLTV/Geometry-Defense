class_name Balance
extends RefCounted

const KINDS = ["Minigun", "Laser", "Rocket", "Shockwave"]
static var cfg: Dictionary = {}

static func load_config() -> void:
	if cfg.is_empty():
		cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))

static func tower(kind: String) -> Dictionary:
	load_config()
	return cfg.towers[kind]

static func rounded5(value: float) -> int:
	return int(floor(value / 5.0 + 0.5)) * 5

static func upgrade_cost(kind: String, level: int) -> int:
	return rounded5(tower(kind).price * cfg.upgrade_base * pow(cfg.upgrade_growth, level - 1))

static func ultimate_cost(kind: String) -> int:
	return rounded5(tower(kind).price * cfg.ultimate_price)

static func damage(t: Dictionary) -> float:
	return tower(t.kind).damage * pow(cfg.damage_growth, t.d) * (2.0 if t.mega else 1.0)

static func rate(t: Dictionary) -> float:
	return tower(t.kind).rate * pow(cfg.rate_growth, t.s)

static func reach(t: Dictionary) -> float:
	return tower(t.kind).range + cfg.range_step * floor(float(t.d + t.s) / 5.0)

static func hp_multiplier(wave: int) -> float:
	load_config()
	# Piecewise products, O(number of tiers), with an overflow guard.
	var logarithm := 0.0
	var previous := 1
	for tier in cfg.hp_tiers:
		var count: int = maxi(0, mini(wave, int(tier[0])) - previous)
		logarithm += count * log(1.0 + float(tier[1]))
		previous = int(tier[0])
	return exp(minf(logarithm, 200.0))

static func reward_growth(wave: int) -> float:
	return 1.0 + 0.025 * (wave - 1) if wave <= 40 else 2.0 + 0.012 * (wave - 41)

static func boss(wave: int) -> Dictionary:
	var index: int = (int(wave / 5.0) - 1) % 4
	return [
		{"color":"82c99c", "name":"Зелёный", "immune":"Laser"},
		{"color":"eceff1", "name":"Белый", "immune":"Minigun"},
		{"color":"e57e78", "name":"Красный", "immune":"Rocket"},
		{"color":"79a9dc", "name":"Синий", "immune":"Shockwave"}
	][index]
