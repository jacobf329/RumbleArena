## Physics layers used across the game.
##
## Keeping BARRIER off WORLD is what lets anything ask "is the view of this
## fighter blocked?" by querying WORLD alone -- the boundary stops fighters
## without ever counting as something you can see.
class_name Layers

const WORLD := 1      ## Visible arena geometry.
const FIGHTER := 2    ## Fighter bodies.
const BARRIER := 4    ## Invisible containment; blocks movement, never sight.
const HURTBOX := 8    ## What an attack's hitbox query looks for.
const INTERACTABLE := 16  ## Things a fighter's interaction probe can find.
const BREAKABLE := 32     ## Scenery an attack can damage, alongside fighters.
