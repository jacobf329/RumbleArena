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

## M3 — Stats and the interactive arena
**Risk under test:** does stat-gated interaction read as cool rather than arbitrary?

- [ ] `CharacterDef` resource with the six stats
- [ ] `Interactable` base + permission rule (`required_stat` / `required_tier`)
- [ ] Liftable: pick up, carry (movement penalty), throw
- [ ] Breakable, spawning debris
- [ ] Climbable: mantle, wall-climb
- [ ] Hackable + Hazard: turrets that can be re-targeted
- [ ] `InteractionProbe` + contextual prompt UI, **including denied prompts**

**Playable result:** the arena is a weapon. Different stats visibly open
different options.

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
