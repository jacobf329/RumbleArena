## One fighter standing on the other side of a story chapter.
##
## A story opponent is not a special kind of enemy: it is a seat, a ninja from
## the same roster the player picks from, and a skill number handed to the same
## BotInputSource that fills a versus bench. Difficulty is authored by choosing
## who shows up, how sharp they are, and how many stocks they get -- not by
## giving the AI a private set of rules the player cannot see.
class_name StoryOpponent
extends Resource

@export var character: CharacterDef
## 0 is clumsy, 1 is sharp. Passed straight through to the bot.
@export_range(0.0, 1.0) var skill: float = 0.5
@export_range(1, 9) var stocks: int = 1
## A line about them on the briefing, so a lineup reads as people rather than
## as a difficulty curve.
@export var note: String = ""


func display_name() -> String:
	return character.display_name if character != null else "?"
