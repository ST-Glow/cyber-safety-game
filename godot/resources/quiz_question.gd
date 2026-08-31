class_name QuizQuestion
extends Resource

@export var title: String = ""
@export_multiline var prompt: String = ""
@export var options: PackedStringArray = PackedStringArray()
@export_range(0, 2) var correct_index: int = 0
@export_multiline var explanation: String = ""
@export var task_id: String = ""
@export var digcomp_area_id: String = ""
@export var competence_id: String = ""
@export var learning_outcome_id: String = ""
var display_order: PackedInt32Array = PackedInt32Array()


func randomized(seed_key: String) -> QuizQuestion:
	var copy := duplicate(true) as QuizQuestion
	copy.display_order = PackedInt32Array()
	for index in range(options.size()):
		copy.display_order.append(index)
	if DisplayServer.get_name() == "headless" or options.size() < 2:
		return copy
	var random := RandomNumberGenerator.new()
	random.seed = hash("%s|%s" % [seed_key, task_id])
	var order: Array[int] = []
	for index in range(options.size()):
		order.append(index)
	for index in range(order.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var value := order[index]
		order[index] = order[swap_index]
		order[swap_index] = value
	var shuffled := PackedStringArray()
	copy.display_order = PackedInt32Array()
	for original_index in order:
		shuffled.append(options[original_index])
		copy.display_order.append(original_index)
	copy.options = shuffled
	copy.correct_index = order.find(correct_index)
	return copy
