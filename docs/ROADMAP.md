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

## M3 — Stats and the interactive arena — **MOSTLY COMPLETE**
**Risk under test:** does stat-gated interaction read as cool rather than arbitrary?

- [x] `CharacterDef` resource with the six stats
- [x] `Interactable` base + permission rule (`required_stat` / `required_tier`)
- [x] Liftable: pick up, carry (movement penalty), throw for damage
- [x] Breakable, spawning debris anyone can then throw
- [x] Hackable turrets that fire on everyone but the hacker
- [x] Interaction probe + contextual prompt, **including denied prompts**
- [ ] Climbable: mantle, wall-climb — still outstanding

**Playable result:** the arena is a weapon, and which weapon depends on who you
picked.

### The permission matrix

Every interactable is gated to exactly one of the four staged characters, or to
everyone. That is the whole teaching design: you learn the system by being
refused, and learn the roster by seeing what you are refused.

| | Pillar (STR 4) | Rack (STR 2) | Turret (TECH 3) | Debris (STR 1) |
|---|---|---|---|---|
| **Kurogane** STR 5 / TECH 1 | ✓ | ✓ | — | ✓ |
| **Null** STR 1 / TECH 5 | — | — | ✓ | ✓ |
| **Jinsoku** STR 2 | — | ✓ | — | ✓ |
| **Yamabuki** STR 2 | — | ✓ | — | ✓ |

Null is the only character who can hack, and the only one who can neither lift a
pillar nor break a rack. A STRENGTH 1 fighter who loses every straight exchange
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
- **Carrying costs speed and your fists.** A pillar is a decision, not a free
  upgrade: you move at 62% speed and cannot attack until you throw it.
- **Dying returns what you were holding.** Otherwise a heavy prop could be
  removed from the match by carrying it off a ledge.

### What M3 turned up

- **A check that passed for the wrong reason.** "Kurogane cannot hack the
  turret" passed while the turret was unreachable by anyone — nothing on the
  floor could target something on the ceiling. It now asserts he is in range
  first, so the gate is what makes it pass.

---

## M4 — Vertical slice: Kurogane vs Null
**Risk under test:** is asymmetry fun, or just unbalanced?

- [ ] `Power` base class, meter cost, cast state
- [ ] Kurogane: Seismic Palm, Ogre Rampage
- [ ] Null: Blink Strike, System Seize
- [ ] Arena "The Server Shrine" built to spec (§6 of the GDD)
- [ ] Character select with join/ready flow
- [ ] Stock-based match flow, KO, victory screen
- [ ] 4-player HUD

**Playable result:** the full slice from §11 of the GDD. This is the go/no-go
gate for the whole project.

---

## M5 — Roster scale-out
Only after M4 is judged fun.

- [ ] Remaining six ninjas as data + power scripts
- [ ] 2–3 more arenas with distinct interactable themes
- [ ] AI bots to fill empty slots
- [ ] Balance pass across the matchup matrix
- [ ] Audio, real models, VFX polish

---

## Working practices

- **Headless validation every commit.** `./run_tests.sh` imports the project
  (catching script and scene parse errors) and then runs the smoke test. A commit
  that doesn't import cleanly doesn't get made.
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
