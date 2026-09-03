## One fight in the campaign, with the words around it.
##
## Everything a chapter is -- who you fight, how hard, how much rope you get,
## and what is said before and after -- is data. Adding a chapter is authoring a
## .tres, the same rule the roster follows: if a new chapter needs a code change,
## the abstraction is wrong.
class_name StoryChapter
extends Resource

@export var title: String = ""
## Where it happens. Shown under the title; the arena is the same room every
## time, so the name is doing the work the level geometry is not doing yet.
@export var location: String = ""
@export_multiline var briefing: String = ""
@export_multiline var victory: String = ""
@export_multiline var defeat: String = ""
@export_range(1, 9) var player_stocks: int = 3

## Typed Array[Resource] rather than Array[StoryOpponent] deliberately: the
## opponents are sub-resources of a hand-written .tres, and a hand-written typed
## array of a script class is exactly the kind of thing that loads as an empty
## array without saying so. Resource is what the file actually holds; the cast
## happens once, here.
@export var opponents: Array[Resource] = []


func get_opponents() -> Array[StoryOpponent]:
	var out: Array[StoryOpponent] = []
	for entry in opponents:
		var opponent := entry as StoryOpponent
		if opponent != null and opponent.character != null:
			out.append(opponent)
	return out


func opponent_count() -> int:
	return get_opponents().size()


## "Jinsoku x1" or "Jinsoku x1, Yamabuki x1" -- the shape of the fight in one
## line, for the chapter list where the full briefing does not fit.
func lineup() -> String:
	var parts: Array[String] = []
	for opponent in get_opponents():
		parts.append("%s x%d" % [opponent.display_name(), opponent.stocks])
	return ", ".join(parts)
