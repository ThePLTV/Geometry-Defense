class_name HexMap
extends RefCounted

const DIRS = [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,-1)]
var cells: Dictionary = {}
var occupied: Dictionary = {}
var distances: Dictionary = {}
var spawn := Vector2i.ZERO
var goal := Vector2i(8,6)
var revision := 0

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map.json"))
	spawn = unpack(data.spawn)
	goal = unpack(data.goal)
	for cell in data.walkable:
		cells[unpack(cell)] = true
	rebuild()

static func unpack(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))

static func pack(cell: Vector2i) -> Array:
	return [cell.x, cell.y]

static func point(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * sqrt(3.0) / 2.0, cell.y + cell.x * 0.5)

func field(extra: Vector2i = Vector2i(999,999)) -> Dictionary:
	var result: Dictionary = {goal:0}
	var queue: Array[Vector2i] = [goal]
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for direction in DIRS:
			var neighbour: Vector2i = current + direction
			if cells.has(neighbour) and not occupied.has(neighbour) and neighbour != extra and not result.has(neighbour):
				result[neighbour] = int(result[current]) + 1
				queue.append(neighbour)
	return result

func rebuild() -> void:
	distances = field()
	revision += 1

func next_cell(cell: Vector2i) -> Vector2i:
	var best := cell
	var best_distance: int = int(distances.get(cell, 100000))
	for direction in DIRS:
		var neighbour: Vector2i = cell + direction
		var candidate: int = int(distances.get(neighbour, 100000))
		if candidate < best_distance:
			best = neighbour
			best_distance = candidate
	return best

func route(start: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [start]
	if not distances.has(start):
		return []
	while result.back() != goal and result.size() < cells.size() + 1:
		var next := next_cell(result.back())
		if next == result.back():
			return []
		result.append(next)
	return result

func validate_build(cell: Vector2i, enemies: Array) -> String:
	if not cells.has(cell) or cell == spawn or cell == goal:
		return "Здесь строить нельзя"
	if occupied.has(cell):
		return "Клетка занята"
	for enemy in enemies:
		if not enemy.dead and (enemy.cell == cell or (enemy.progress > 0.0 and enemy.next == cell)):
			return "Клетка занята врагом"
	var candidate := field(cell)
	if not candidate.has(spawn):
		return "Нельзя перекрыть путь"
	for enemy in enemies:
		if not enemy.dead and not candidate.has(enemy.next if enemy.progress > 0.0 else enemy.cell):
			return "Нельзя отрезать врагов"
	return ""
