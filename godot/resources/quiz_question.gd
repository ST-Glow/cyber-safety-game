class_name QuizQuestion
extends Resource

@export var title: String = ""
@export_multiline var prompt: String = ""
@export var options: PackedStringArray = PackedStringArray()
@export_range(0, 2) var correct_index: int = 0
@export_multiline var explanation: String = ""

