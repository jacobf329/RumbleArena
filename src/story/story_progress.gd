## How far through the campaign this machine has got.
##
## Stored as a single number -- chapters cleared -- rather than a set of flags.
## The campaign is a ladder, so "cleared 3" says everything "cleared 1, 2 and 3"
## would, and a save file with one integer in it cannot get into a state where a
## later chapter is open and an earlier one is not.
##
## Lives in user:// so it survives an update: the whole point of the updater is
## that it overwrites the game folder, and a save kept next to the executable
## would be wiped by the thing meant to improve it.
class_name StoryProgress
extends RefCounted

const SAVE_PATH := "user://story_progress.cfg"
const SECTION := "campaign"
const KEY_CLEARED := "chapters_cleared"

## Tests turn this off. A headless run that stamps on a real player's progress
## is a test with a side effect, and the one thing worse than a suite that fails
## is a suite that deletes something.
static var persist := true

## -1 until read. Cached so the screens can ask every frame without touching the
## disk every frame.
static var _cleared := -1


static func cleared_count() -> int:
	if _cleared < 0:
		_cleared = _read() if persist else 0
	return _cleared


## True if the player is allowed to start this chapter: everything up to and
## including the first one they have not cleared.
static func is_unlocked(index: int) -> bool:
	return index <= cleared_count()


static func is_cleared(index: int) -> bool:
	return index < cleared_count()


## Clearing chapter 2 when 5 are already done is not a step backwards.
static func mark_cleared(index: int) -> void:
	if index + 1 <= cleared_count():
		return
	_cleared = index + 1
	if persist:
		_write(_cleared)


static func reset() -> void:
	_cleared = 0
	if persist:
		_write(0)


## Forgets the cache without touching the file, so a test can run against a
## known number and leave the player's save alone.
static func set_for_testing(count: int) -> void:
	_cleared = maxi(count, 0)


static func _read() -> int:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return 0
	return maxi(int(config.get_value(SECTION, KEY_CLEARED, 0)), 0)


static func _write(count: int) -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)  # keep anything else that ends up in this file later
	config.set_value(SECTION, KEY_CLEARED, count)
	config.save(SAVE_PATH)
