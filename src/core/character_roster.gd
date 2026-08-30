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
