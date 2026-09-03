## An ordered run of chapters.
##
## One campaign exists today. It is loaded by path rather than autoloaded so a
## second one -- a harder run, a side story -- is a .tres and a menu entry.
class_name StoryCampaign
extends Resource

const DEFAULT_PATH := "res://src/story/campaign/the_registry.tres"

@export var title: String = ""
@export_multiline var premise: String = ""
## See the note in StoryChapter for why this is Array[Resource].
@export var chapters: Array[Resource] = []


static func load_default() -> StoryCampaign:
	return load(DEFAULT_PATH) as StoryCampaign


func size() -> int:
	return chapters.size()


func at(index: int) -> StoryChapter:
	if index < 0 or index >= chapters.size():
		return null
	return chapters[index] as StoryChapter
