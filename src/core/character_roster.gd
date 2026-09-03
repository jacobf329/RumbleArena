## The pickable roster, in select order.
##
## One list, so the character-select cycling and the default assignment cannot
## disagree about who exists or what order they come in.
class_name CharacterRoster

const PATHS: Array[String] = [
	"res://src/characters/roster/kurogane.tres",
	"res://src/characters/roster/null.tres",
	"res://src/characters/roster/jinsoku.tres",
	"res://src/characters/roster/yamabuki.tres",
]


static func size() -> int:
	return PATHS.size()


static func at(index: int) -> CharacterDef:
	return load(PATHS[wrapi(index, 0, PATHS.size())])


## Wraps in both directions, so cycling never dead-ends at either end.
static func step(index: int, direction: int) -> int:
	return wrapi(index + direction, 0, PATHS.size())


## Which seat number picks this ninja. Story chapters name their opponents by
## resource rather than by index -- an index in a .tres would silently mean
## somebody else the first time the roster is reordered.
static func index_of(definition: CharacterDef) -> int:
	if definition == null:
		return 0
	for i in PATHS.size():
		if at(i) == definition:
			return i
	# A second copy of the same resource is still that ninja.
	for i in PATHS.size():
		if at(i).display_name == definition.display_name:
			return i
	return 0
