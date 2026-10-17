class_name Balance
extends RefCounted

const KINDS = ["Minigun","Laser","Rocket","Shockwave"]
static var cfg: Dictionary = {}

static func load_config() -> void:
	if cfg.is_empty():
		cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))

static func tower(kind: String) -> Dictionary:
	load_config()
	return cfg.towers[kind]

static func level(t: Dictionary) -> int:
	return clampi(int(t.get("level",1)),1,10)

static func upgrade_cost(kind: String, target_level: int) -> int:
	return maxi(1,int(round(tower(kind).price*cfg.upgrade_price_fraction*pow(cfg.upgrade_growth,maxi(0,target_level-2)))))

static func ultimate_cost(kind: String) -> int:
	return int(tower(kind).ultimate_cost)

static func damage(t: Dictionary) -> float:
	var data := tower(t.kind)
	return data.damage*pow(data.damage_growth,level(t)-1)*(2.0 if t.mega else 1.0)

static func rate(t: Dictionary) -> float:
	var data := tower(t.kind)
	return data.rate*(1.0+data.rate_growth*(level(t)-1))

static func reach(t: Dictionary) -> float:
	var data := tower(t.kind)
	var value: float = data.range+data.range_growth*(level(t)-1)
	if t.kind == "Laser" and t.ultimate:
		value *= 2.0
	if t.mega:
		value *= cfg.mega_range_multiplier
	return value

static func volley(t: Dictionary) -> int:
	return level(t) if t.kind == "Rocket" else 1

static func boss(wave: int) -> Dictionary:
	return [
		{"color":"f4f6f8","name":"Белый","immune":"Minigun"},
		{"color":"58ed66","name":"Зелёный","immune":"Laser"},
		{"color":"f04749","name":"Красный","immune":"Rocket"},
		{"color":"39b4f6","name":"Синий","immune":"Shockwave"}
	][(int(wave/5.0)-1)%4]
