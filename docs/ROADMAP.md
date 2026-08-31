# RumbleArena — Roadmap

Milestones are ordered so that the riskiest assumptions get tested earliest.
Each milestone ends in something playable, not just compilable.

---

## M1 — Foundation: one fighter, one box, one camera — **COMPLETE**
**Risk under test:** does the shared camera work, and does moving feel good?

- [x] Godot 4.3 project skeleton, headless-validated
- [x] `InputSource` / `InputFrame` abstraction; keyboard + gamepad
- [x] `PlayerManager` with join-by-button-press and 4 slots
- [x] `Fighter` CharacterBody3D with state machine (Idle/Run/Air/Dash)
- [x] Movement tuning: accel, air control, variable jump height, coyote time,
      jump buffering, dash with cooldown — all derived from the stat block
- [x] `ArenaCamera` framing 1–4 fighters with asymmetric smoothing
- [x] Grey-box test arena with two traversal tiers
- [x] 36-check headless smoke test driving real fighters through the real scene

**Playable result:** four capsules run, jump and dash around a grey-box arena
while one camera keeps them all framed. Verdict on feel is the player's to give.

### What M1 turned up

Three bugs that only a running build would have shown:

1. **The sun pointed at the sky.** A `.tscn` `Transform3D` literal is row-major
   while `basis.x/y/z` are columns, so a matrix authored as columns silently
   becomes its own inverse. Both ramps also sloped away from the platform they
   feed. Now covered by an orientation regression check.
2. **Perimeter walls blocked the fight.** Fighters pressed against an arena edge
   push the camera outside the arena looking back in, and the 7-unit walls stood
   between the camera and the action. The boundary is now collision-only: an
   invisible barrier on its own physics layer, plus a decorative low lip. A
   raycast test now asserts the camera can see fighters at the edge.
3. **The camera zoomed out roughly twice as far as needed**, because it fitted a
   world-space horizontal span into the *vertical* field of view. Targets are now
   projected onto the camera's own right and up axes before being measured.

Point 2 is the one worth carrying into M3 arena design: **nothing tall may sit on
an arena's perimeter.**

---

## M2 — Combat core — **COMPLETE**
**Risk under test:** does hitting someone feel good with no animation?

- [x] `AttackDef` frame-data resource driving startup / active / recovery
- [x] Hitboxes as direct shape queries rather than `Area3D` overlaps
- [x] Light chain, heavy and launcher, with confirm cancels gated on connecting
- [x] Hitstun, knockback scaled by STR vs TGH, launch angles
- [x] Block with chip damage, stamina cost, blockstun and a front-only arc
- [x] Dodge with invulnerability frames, knockdown and tech
- [x] Wall splat
- [x] Game feel: hitstop, screen shake, hit sparks, hit flash
- [x] Health / Power / Stamina meters per player
- [x] 51-check headless combat test

**Playable result:** fighters can actually fight, and the impact reads.

### Decisions worth remembering

- **Hitboxes are shape queries, not `Area3D` overlaps.** Area overlaps only
  settle on the next physics step, which would smear every active window by a
  frame. A direct query is live on exactly the ticks the frame data says.
- **Hitstop is per-fighter; screen shake is global.** In a four-player game a
  global freeze would stutter the fight between the two players who were not
  involved. Shake is shared on purpose: it reads as the arena reacting.
- **A wall splat cancels the pending knockdown.** Any hit hard enough to splat
  is also hard enough to knock down, and a splat that just put the victim on the
  floor would be a *worse* outcome than a normal hit. The splat wins, and buys
  the attacker a juggle instead.
- **Frame data is authored once and scaled by SPEED.** Startup and recovery
  answer to the stat; active frames never do, so a hitbox is live for the same
  length of time for everyone and only the commitment around it changes.

### What M2 turned up

Three bugs, all of which would have shipped as "combat feels unreliable" rather
than as anything a reader would spot:

1. **Every cancel was silently swallowed.** The state machine suppressed
   transitions into the state it was already in, and cancelling one attack into
   another is a transition from ATTACK to ATTACK. Chains and confirms simply
   never fired. States already return `STAY` to mean "no change", so the guard
   was both redundant and harmful.
2. **Presses during hitstop were dropped.** Hitstop lands exactly when a player
   is inputting the next hit of a combo, so eating those presses made every
   chain feel like it had dropped. Input is now captured during the freeze, and
   the buffer does not age while frozen — otherwise hitstop would shorten its
   own cancel window.
3. **Respawning preserved queued intent**, so a fighter could come back and
   immediately act on a button pressed before it went down.

---

## M2.5 — Character model, animation and rhythm — **COMPLETE**
**Risk under test:** does one shared model read as four distinct players, and
does timing a combo feel better than mashing it?

- [x] Shared ninja model with ten animation clips
- [x] Per-player recolour by hue rotation, targeting the crimson only
- [x] Locomotion driven by actual speed; attack clips aligned to frame data
- [x] Rhythm windows: timing a cancel earns flow, speed and damage
- [x] Punch, punch, kick as the basic chain

### Asset pipeline

Every clip the model tool exports carries its own copy of the character mesh and
a 2048x2048 texture -- 6.3 MB per animation, of which only the animation is
wanted. `tools/strip_animation_glb.py` rewrites a clip to keep the node
hierarchy, the skin and the animation, substituting a single degenerate skinned
triangle for the mesh so Godot still builds the same `Skeleton3D` and still
produces bone tracks rather than node-path tracks. Ten clips went from 64 MB to
630 KB, and each new animation now costs tens of kilobytes instead of six
megabytes.

`tools/build_animation_library.gd` then folds every clip into one
`AnimationLibrary`, flattening horizontal root motion: the fighter's position is
owned by the physics body and the knockback system, and an animation that also
slides the character would fight it. Vertical motion is kept, because that is the
crouch and the leap.

**Adding a clip:** drop the `.glb` in, run the stripper, re-run the library
builder. Naming a slice of it in an `AttackDef` is all that connects it to a move.

### Decisions worth remembering

- **One texture, recoloured by saturation rather than hue.** A flat hue rotation
  would recolour the skin along with the armour and give every player but one a
  green face. Measuring the atlas showed the crimson at hue 0.0 / saturation
  0.68, skin at 0.07 / 0.35 and the dark armour below 0.2 -- so *saturation* is
  what separates them. The shader rotates only pixels above the threshold.
- **Frame data wins; the animation is scaled to fit.** Each `AttackDef` names a
  clip plus the moment of contact within it, and playback is scaled so that
  moment lands on the active frames -- with the wind-up and the follow-through
  scaled separately, because frame data and animation rarely divide a move the
  same way. Contact points were measured, not guessed: `tools/analyse_impacts.gd`
  samples the pose every frame and reports peaks in how far the hands and feet
  reach from the hips, which is where a punch connects.
- **Rhythm rewards, never punishes.** Mashing still combos; it just earns
  nothing. Timing the cancel to the moment a move becomes cancellable scores
  "on beat", which grants faster startup, more damage, and a flow streak that
  compounds while the chain stays clean. Punishing a masher would make the game
  worse for the player least equipped to handle it.
- **Hitstop does not count against your timing.** The input buffer is frozen
  during hitstop, so the freeze never eats the window -- which matters, because
  hitstop is exactly when the next press happens.

### What this turned up

- **The model faces +Z.** Godot's forward is -Z, so it needed a 180-degree flip.
  Determined from the skeleton rather than by eye: the toe bone extends +Z from
  the foot.
- **`rigify_clip.glb` imports as 0.07s** despite being 3.03s in the source file.
  It is excluded from the moveset; worth re-exporting.

---

## M3 — Stats and the interactive arena — **COMPLETE**
**Risk under test:** does stat-gated interaction read as cool rather than arbitrary?

- [x] `CharacterDef` resource with the six stats
- [x] `Interactable` base + permission rule (`required_stat` / `required_tier`)
- [x] Liftable: pick up, carry (movement penalty), throw for damage
- [x] Breakable, spawning debris anyone can then throw
- [x] Hackable turrets that fire on everyone but the hacker
- [x] Interaction probe + contextual prompt, **including denied prompts**
- [x] Climbable walls with a mantle at the top

**Playable result:** the arena is a weapon, and which weapon depends on who you
picked.

### The permission matrix

Every interactable is gated to exactly one of the four staged characters, or to
everyone. That is the whole teaching design: you learn the system by being
refused, and learn the roster by seeing what you are refused.

| | Pillar (STR 4) | Rack (STR 2) | Turret (TECH 3) | Tower (AGI 4) | Debris (STR 1) |
|---|---|---|---|---|---|
| **Kurogane** STR 5 / AGI 2 / TECH 1 | ✓ | ✓ | — | — | ✓ |
| **Null** STR 1 / AGI 3 / TECH 5 | — | — | ✓ | — | ✓ |
| **Jinsoku** STR 2 / AGI 3 | — | ✓ | — | — | ✓ |
| **Yamabuki** STR 2 / AGI 5 | — | ✓ | — | ✓ | ✓ |

Each of the three specialists owns exactly one verb nobody else has: Kurogane
lifts, Null hacks, Yamabuki climbs. Null is also the only one who can neither
lift a pillar nor break a rack. A STRENGTH 1 fighter who loses every straight exchange
can still turn the room's turrets on everyone else, which is what makes the
stat spread worth playing rather than merely worth reading.

### Decisions worth remembering

- **`can_use` and `is_offered` are separate questions.** An object a fighter
  cannot use is still targeted and still shows its prompt, greyed out, naming the
  requirement. Hiding it would have been less code and a worse game: being
  refused is how the player learns both the stat system and what the other
  ninjas can do.
- **Mass class *is* the STRENGTH tier.** "How heavy is it" and "who can lift it"
  are one number rather than two that can drift apart.
- **Breaking is not a prompt.** You destroy scenery by hitting it, so a Breakable
  is deliberately not an Interactable. The refusal still has to read, though, so
  a fighter too weak to break something gets a dull grey spark rather than
  silence.
- **Turrets are hacked at range.** They hang from the ceiling, and requiring the
  hacker to climb up and touch one would be bad fiction and — as the tests
  caught — physically unreachable for the one character meant to use them.
- **Climbing is pitched at AGILITY 4, not 3.** Double jumping already keys off
  AGILITY 3, so gating the climb there would have given three of the four
  characters a taller version of what they already had. At 4 it belongs to the
  acrobat alone, and the comms tower is 7m — beyond any double jump from the
  floor — so the thing on top of it is reachable one way only.
- **Carrying costs speed and your fists.** A pillar is a decision, not a free
  upgrade: you move at 62% speed and cannot attack until you throw it.
- **Dying returns what you were holding.** Otherwise a heavy prop could be
  removed from the match by carrying it off a ledge.

### What M3 turned up

- **Climbing fought the body solver.** A tick of climbing covers less ground
  than `move_and_slide`'s floor-snap distance, so snapping dragged the fighter
  back down every frame and the climb went nowhere. Climbing sets the transform
  directly, so it now skips the solver outright.
- **The press that starts a climb also ended it.** The same INTERACT edge that
  put a fighter on the wall was still just-pressed when the climb state read it
  as "let go", so the fighter bounced straight off. The state ignores that input
  on its entry tick.
- **A mantle has to place you, not launch you.** Popping the fighter up and
  forward with velocity lost its forward momentum to air drag within three ticks
  of a neutral stick, dropping them back down the wall. The mantle now puts them
  on the surface.
- **A check that passed for the wrong reason.** "Kurogane cannot hack the
  turret" passed while the turret was unreachable by anyone — nothing on the
  floor could target something on the ceiling. It now asserts he is in range
  first, so the gate is what makes it pass.

---

## M4 — Match flow and the first playtest pass — **IN PROGRESS**
**Risk under test:** is asymmetry fun, or just unbalanced?

- [x] Stock-based match flow: countdown, KO, elimination, victory, rematch
- [x] 4-player HUD: stock pips, match clock, countdown and result banner
- [x] Fireball cast by the punch-punch-kick chain, paid for out of the meter
- [x] Grabs and throws, which beat a guard
- [x] First playtest tuning pass (speed, hit recoil, hitstun)
- [x] `Power` base class for the signature and ultimate buttons
- [x] Kurogane: Seismic Palm, Ogre Rampage
- [x] Null: Blink Strike, System Seize
- [ ] Arena "The Server Shrine" built to spec (§6 of the GDD)
- [x] Character select with join/ready flow

### Character select

There is no separate menu scene. Players are already standing in the arena
warming up, so they pick there: **left and right cycle the roster, jump locks
in** -- the same button that got them a seat, which is the one they already have
a finger on. A match starts only once *everyone who has joined* is ready, and a
late join puts the countdown back to choosing rather than dropping somebody into
a fight mid-decision.

- **Seats default to different ninjas**, so a group that just mashes A still
  gets the asymmetry the game is about without touching select.
- **Swapping is done in place**, not by respawning the fighter. Respawning would
  mean re-registering with the camera, the HUD and the match for what is really
  just a different stat block.
- **Cycling is on the bumpers, not the movement stick.** The first version read
  left and right off the stick, which meant a player changed ninja every time
  they took a step while warming up. Six tests caught it at once, all of them
  failing because moving a fighter had quietly swapped who it was.

### Powers

`Power` extends `AttackDef` rather than sitting beside it, so a power inherits
frame data, hitboxes, animation alignment and cancel rules for free and only has
to describe what makes it special. A power that is purely a strike needs no
script at all beyond its numbers.

| | Signature | Ultimate |
|---|---|---|
| **Kurogane** | **Seismic Palm** (40) — a shockwave that cracks the floor into debris | **Ogre Rampage** (90) — 8s of armour: small hits land but do not interrupt |
| **Null** | **Blink Strike** (35) — teleports behind the nearest fighter and hits their back | **System Seize** (100) — every turret in the arena answers to her at once |

Jinsoku and Yamabuki have **empty power slots** rather than borrowed ones, so
their buttons do nothing instead of lying about who they are. Their own powers
belong to the roster scale-out in M5.

- **Powers resolve before their own hitbox.** Blink Strike repositions the
  caster, and it has to land the strike from where it arrived rather than from
  where it started.
- **Charged on commit, not on connect.** A whiffed special costs you the meter,
  which is what stops a signature being a free poke.
- **Ogre Rampage is armour, not invulnerability.** He still takes the damage; he
  just does not flinch, so chip and spacing stop working and the only answer is
  to hit him hard enough to break through.
- **System Seize skips the TECH check** the turret normally applies. The
  ultimate has already been paid for, and re-testing the stat would only deny it
  to the one character who can cast it.

### Match rules

A match needs two players and starts on a countdown that **restarts whenever
somebody else joins**, so nobody is locked out for being a moment late. Three
stocks each; a knockout costs one and respawns you with a moment of
invulnerability, because otherwise whoever is standing on the spawn point takes
the next stock too. Spending your last stock takes you off the field. Last one
standing wins; if the clock runs out, most stocks wins and an exact tie is a
draw rather than an arbitrary winner. Knockouts before the bell cost nothing.

**Fighters do not decide their own fate.** A fighter reports that it was
defeated and stops there; the MatchManager decides whether that costs a stock, a
respawn, or the match. Keeping that in one place is what makes "last ninja
standing" a rule rather than something smeared across the fighter class.

### First playtest pass

Changes made off the back of actually playing it:

- **Movement is about a quarter slower.** The original top speed put a SPEED 5
  fighter above a real sprinter, which read as skating and left no time to react
  to anyone.
- **Hitstun is up roughly 40%**, so a combo genuinely holds the opponent still.
  Before, a jab left the attacker free four ticks before the victim -- too slim a
  margin to feel like control, which is where "they can still hit me back"
  came from.
- **Hit recoil.** With no hit-reaction clip yet, the model is knocked back and
  tipped away from the blow, easing home over the next few ticks. That is what
  makes a hit read as landing *on somebody* rather than just moving them.
- **A fireball on the chain finisher.** Punch, punch, kick ends in a projectile
  if the power meter can pay for it, which finally gives the meter a purpose.
  Running dry is not a failure state; you just get the kick.
- **Grabs.** Short range, and they ignore a guard entirely: grab beats block,
  block beats strike, strike beats grab. A whiffed grab has the longest recovery
  of any move, because a move that beats guarding has to be the worst thing to
  throw out at random.

### What this turned up

- **Debris was being parented to the wrong container.** Seismic Palm spawned its
  rubble under the fighter's own parent rather than the arena's interactables,
  where a match reset would have taken it with them. Arenas now expose where
  dynamically created props belong.
- **The fireball was paying for itself.** The finisher's own connect credited
  power on the same tick the cost was checked, so the move funded its own
  projectile and the meter meant nothing. The cast now resolves before hits do.

---

## M5 — Roster scale-out
Only after M4 is judged fun.

- [x] AI bots to fill empty slots
- [x] Full kits for the pickable roster (Jinsoku, Yamabuki)
- [ ] The remaining four ninjas as data + power scripts
- [ ] 2–3 more arenas with distinct interactable themes
- [ ] Balance pass across the matchup matrix
- [ ] Audio, real models, VFX polish

### Bots

Because a bot is just another `InputSource`, the AI cost about 180 lines and
gets no special privileges: it fills an `InputFrame` and the fighter consumes it
without knowing the difference. It cannot reach past a rule it does not like,
and anything a bot does, a player can do with the same buttons. This is the
whole return on the M1 decision never to let fighters poll `Input` — a decision
that looked like pointless ceremony at the time.

A bot picks a target, closes, circles at range, guards when it sees a wind-up,
**grabs a guard rather than beating on it**, and spends its meter on its
signature. Skill is one float: reaction time, how often it guards, and how close
its combo timing sits to the cancel window. A bench comes in at different skill
levels rather than three copies of the same opponent.

Bots are ready the moment they sit down and stay ready through a rematch, since
a bot has no way to press the lock-in button and a seat that never readies would
stall every countdown forever.

### What this turned up

Four bots on one shared camera is exactly the question the camera was always
going to live or die on, and one minute of them fighting each other answered it
better than an hour of asserting things:

- **Nearest-target picking splits four bots into two duels in opposite corners.**
  Obviously right, and the one thing a single shared camera cannot frame. Bots
  now score targets by distance *plus* how far that target is from the centre of
  everyone else, so they gravitate to the scrum the way a player drawn to the
  action does. Time spent with the fight spread over 20 m fell from as much as
  37% of a match to 5–10%.
- **Bots walked into the scenery and stayed there.** With no navigation mesh,
  "walk at your target" works until a ramp or a pillar is in the way — two bots
  spent thirty seconds pushing into the same wall. They now notice that they are
  asking to move and not moving, jump, and commit to going around for a moment.
  Wedged time dropped by roughly 5x.
- **Neither of those was visible from the test suite.** Every assertion passed
  the whole time. They came out of a probe that asserts nothing and just
  measures — `tests/bot_brawl_probe.tscn` — which is now the tool for the
  balance pass too.

Still open: bots ignore the interactables entirely. They do not climb, throw or
hack, which quietly makes the environment a human-only advantage — the opposite
of pillar P2.

### Full kits for everyone you can pick

Half the pickable roster had empty signature and ultimate slots. With four
players on a couch that is not a missing feature anybody diagnoses — it is two
of them concluding their controller is broken. The old test asserted the empty
slots were *deliberate*, which was the right rule while the roster was
half-built and the wrong one to leave standing; it now asserts the opposite,
that anyone on the roster has both buttons wired to different moves.

- **Jinsoku** — Afterimage Flurry dashes her through you and leaves a decoy
  standing where she was; hitting it bursts it. Hundred Steps is 7s of moving
  and swinging much faster. Deliberately a different axis from Ogre Rampage:
  his answer is to hit harder, hers is to cover space.
- **Yamabuki** — Grapple Line rides her to the nearest high ground. Dragnet
  hauls everyone in the arena to her feet on a solved arc, doing almost no
  damage: an AGILITY character's ultimate should create the situation, not
  finish it.

### What this turned up

- **Three separate systems delete a velocity you meant.** Attack drift, hitstun
  drag and air control settling toward zero all exist to stop a fighter
  sliding, and all three are correct right up until a power deliberately threw
  somebody somewhere. Yamabuki's grapple arc died in two ticks; Dragnet's haul
  died to hitstun drag with the victims a metre from where they started. Fixed
  once, as `apply_launch` — velocity a power meant, protected for a set number
  of ticks — rather than three times as exceptions. The mantle bug in M3 was
  the same shape and was fixed locally; it should have been this.
- **`bool(null)` is a runtime error in GDScript**, not `false`. The bot's
  "is this target still there?" check read `is_eliminated` off the node so a
  decoy — which has no such property — could occupy the slot. `Object.get`
  returns null for a missing property, the cast threw, and the call fell out
  into the function's default of `false`. It type-checked, it imported clean,
  and every decoy read as "not there": bots stood still, staring at one.
  Comparing `!= true` instead is both correct and cheaper.
- **Reusing the hue shader for the decoy produced coloured noise.** Near-grey
  pixels have a numerically meaningless hue, which is harmless while the
  saturation mask leaves them alone and explodes the moment you raise
  saturation across the whole texture to make a dark ninja visible on a pale
  floor. The decoy is a flat silhouette in the player's colour now, which is
  also the better answer to what it is for: it has to read at a glance,
  mid-fight, and detail would only make it harder to tell from the real one.
- **A test can pass because the thing it was watching timed out.** The first
  version of "the bot walks up and pops the decoy" waited 240 ticks for a decoy
  with a 150-tick lifetime. It passed before the fix and after it, for the same
  wrong reason. Anything with a timer in it needs the timer set beyond the
  window the test is watching.

---

## Props, and a button doing two things at once

Throwing was implemented and tested from the start, and did not work on a
gamepad. B is deliberately both INTERACT and GRAB -- both mean "engage with
what is in front of me", and ten actions do not fit in eight good button
positions. Attacking is refused while your hands are full, which quietly
covered the pick-up; but a throw empties them on the very tick it fires, so the
grab then passed that check and every throw was followed by a whiffed grab --
the longest recovery in the game, landing exactly where the player expects to be
free again. It read as "I can't throw things".

An INTERACT press that did something now consumes the buffered attack with it.
A shared button should resolve to exactly one thing per press.

The suite could not see it because every existing test pressed INTERACT alone.
There is now one that presses the button the way the hardware does, with both
actions on the same edge.

Props added at the same time:

- **Supply crate** (STRENGTH 2) and **steel girder** (STRENGTH 5). The ladder
  went 1, 4 before: two of the four staged characters had nothing in the only
  arena they could pick up except rubble, which made a third of the design's
  signature verb invisible in play. The girder is also the reason Kurogane's
  STRENGTH 5 means anything the pillars did not already say.
- **Fuel barrel** (STRENGTH 1), which detonates. Deliberately the lightest
  thing in the arena rather than the heaviest: the ninja who can lift nothing
  else is the one holding the most dangerous object in the room. The fuse is
  what makes it a decision rather than a free grenade -- picking one up starts
  a three-second clock and it goes off in your hands when that runs out. No
  friendly-fire exemption; it is the one object here that does not care whose
  it was.

## Bots that use the arena

Half the game was the arena, and bots played the other half. Nothing stopped
them picking things up except that nobody had told them to, which quietly made
every prop a human-only advantage -- the exact opposite of what pillar P2 is
for. They now fetch what they qualify for and throw it at whoever they are
fighting, throw a carried barrel before the fuse gets them, and walk away from
somebody else's.

Two things fell out of it, one of them a bug in the game rather than the AI:

- **A thrown object hit the thrower.** It leaves your hands 0.9m in front of
  your chest and its 0.7m contact sphere still reaches back inside your own
  hurtbox, so every throw connected with the person who threw it on its first
  or second frame and dropped at their feet. The existing "a thrown pillar
  hurts" test passed by about three centimetres of geometry -- the one staged
  throw in the suite happened to start just outside the sphere. A throw now
  ignores its thrower for 0.4s, a window rather than an exemption so that
  throwing something straight up still lands it on your own head.
- **The first version of fetching wrecked the game.** Scoring props by "is it
  near me" sent four bots orbiting the corners: the fight was spread over
  twenty metres a hundred percent of the match and they attacked a third as
  often. Props are scored by how far they add to the trip the bot was already
  making, so one between it and its target is nearly free and one behind it is
  not worth having. Back to 5-14% and roughly the old attack rate.

Neither showed up in a test. The first hid behind a passing assertion; the
second only exists as a shape you can see in aggregate. `bot_brawl_probe`
caught the second within a minute of running it, and now also counts props
picked up and thrown -- because tuning a fetch rule until the brawl metrics
look healthy could equally mean tuning it until bots never touch anything.

Two things about the suite itself came out of this:

- **A parse error in a test hangs the run rather than failing it.** Renaming a
  bot method left one call site with the wrong arity; the test script would not
  compile, the awaited coroutine never resumed, and the suite sat there
  reporting nothing for a quarter of an hour. Worth knowing the signature: a
  suite that stops printing has usually not got slow, it has died.
- **Test helpers that can return null are the same hazard.** A null dereference
  inside an awaited coroutine aborts that function without resuming its caller,
  so it hangs too. The helper that finds a liftable now spawns one rather than
  returning null, because whether a given prop is free depends on what the
  checks before it left mid-flight.

## Air attacks, and why throwing still looked broken

- **Jump kick** (light, airborne) carries you forward, and further if you were
  already running. **Slam** (heavy, airborne) fires you at the floor rather than
  dropping you toward it, and bursts on impact. It holds its active window open
  for the whole descent, so a dive whose target moved is still a live attack
  instead of a fighter falling with an animation attached.
- The kick's forward drive was eaten by attack drift on the first try -- 5.2 m/s
  of lunge became half a metre of travel. Attack drift exists to stop a
  *grounded* fighter sliding out of a lunge; in the air it simply deletes the
  jump-in. An airborne step now keeps its momentum, reusing the same protection
  the grapple and the haul needed. Third time that trap has come up, and the
  first time the fix was already sitting there.

Throwing had been fixed once and still read as broken, for two reasons that had
nothing to do with the throw:

- **The prompt named the action and never the button.** "Throw Concrete Pillar"
  tells you something is possible and not how to do it. It now reads
  "[B] Throw Concrete Pillar", asked of the seat's own device rather than
  hardcoded -- four seats can be on four different devices at once, and naming
  the wrong button is worse than naming none.
- **Character select covered it completely.** The select prompt won outright
  over the interaction prompt, so through the entire warm-up -- exactly when
  people pick something up for the first time -- the "Throw" line was never on
  screen. They share the space now, contextual line first.

One process note: the edit that was supposed to fix the second of those did
nothing. A string replace missed on a line with mangled whitespace and failed
silently, the test passed anyway because it runs with character select disabled,
and only running the actual game showed the prompt unchanged. A test that agrees
with a change which was never applied is worth less than one look at the screen.

## Two installs that looked like a broken game

The same failure has now shipped twice, and it is worth writing down because
neither time was it a bug in the game.

Godot keeps a global class cache in `.godot`. Without an entry for a
`class_name`, every script referencing that name fails to *compile* — which
takes the autoloads with it. The arena is scene data, so it still renders; the
input system is script, so it is simply gone. The result is a game that draws
perfectly and ignores the controller, with nothing on screen to say why.

- **First time:** a fresh download has no `.godot` at all. Fixed by having the
  launchers run an import pass when the cache was missing.
- **Second time:** a folder updated by hand kept its old `.godot`. The launchers
  saw a cache, said "assets already prepared", and started the game anyway. The
  guard was testing the wrong thing: a cache only means the assets are prepared
  if it **matches the scripts on disk**. It now checks that every `class_name`
  the project declares is actually in the cache, and re-imports if not.

What made this expensive both times is that no test could see it. The suite's
first step is an import pass, which builds the very cache whose absence is the
bug — so the tests were always run against a project that had just been made
correct. `tools/check_cold_start.sh` covers the missing-cache case and
`tools/check_cache_guard.sh` the stale-cache one, both by deliberately breaking
the thing the suite would otherwise silently repair.

And because a class-cache failure means no code of ours is running to report it,
the HUD scene now authors a warning label *visible*, which the HUD script takes
down on every frame that `PlayerManager` exists. If the scripts do not load, the
label is still there and the failure explains itself. That is the only kind of
error message that survives its own cause.

## Working practices

- **Headless validation every commit.** `./run_tests.sh` imports the project
  (catching script and scene parse errors) and then runs the smoke test. A commit
  that doesn't import cleanly doesn't get made.
- **A check that the test setup would repair is not a check.** Anything about
  installing or launching has to break the state deliberately first, because the
  suite's own import pass fixes exactly the conditions those failures need.
- **Nothing tall on an arena's perimeter.** The shared camera has to be able to
  sit outside the arena to frame fighters pressed against an edge. Boundaries are
  collision-only.
- **No character-specific code in `fighter.gd`.** If a new ninja needs it, the
  abstraction is wrong — fix the abstraction.
- **Fighters never poll `Input` directly.** Everything goes through `InputFrame`.
- **Tune numbers in resources, not code.** Frame data, movement constants, and
  stats are data so they can be changed without a code review.
- **Prefer a direct observable to inferred timing in tests.** Telling a real
  cancel from "waited out the recovery" by clock arithmetic is confounded by
  hitstop freezing the attack's internal clock; a counter on the fighter answers
  it exactly.
