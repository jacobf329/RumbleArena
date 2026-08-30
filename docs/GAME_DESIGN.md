# RumbleArena — Game Design Document

A 4-player local versus arena brawler. Named ninjas with super powers tear each
other, and the arena itself, apart. Spiritually a *Marvel Nemesis: Rise of the
Imperfects* clone: asymmetric super-powered fighters in fully interactive
destructible arenas, where what you can pick up, climb, break, or hack is gated
by your character's stats.

---

## 1. Design pillars

Every feature decision gets checked against these three. If it doesn't serve a
pillar, it doesn't go in.

### P1 — Asymmetric power fantasy
Characters are not reskins. A super-strength bruiser and a teleporting hacker
should not share a moveset, a movement model, or a way of reading the arena.
When you switch character, you re-learn the game a little. Balance is a
*matchup* problem, not a "make everyone equal" problem.

### P2 — The arena is a weapon
The environment is the second half of the combat system. Pillars get ripped out
and thrown, walls get climbed, turrets get hacked and turned on the room.
Fighting in an empty box should feel like you left most of your kit at home.

### P3 — Readable chaos
Four super-powered fighters on one screen is inherently noisy. Every system —
camera, silhouette, color, hit feedback, UI — exists to keep the player able to
answer "where am I, who's hitting me, what can I grab" at a glance.

---

## 2. Locked technical decisions

| Decision | Choice | Why |
|---|---|---|
| Engine | Godot 4.3 (GDScript) | Validated headless in CI; GDScript keeps iteration fast |
| Perspective | 3D arena, single shared smart camera | True Nemesis feel; one TV, no 4x render cost |
| Multiplayer | Local 4-player couch only | Fastest path to a fun prototype; no netcode complexity |
| Art | Placeholder primitives behind a swappable visual resource | Combat feel is the risk, not art; models drop in later as data |
| First milestone | Vertical slice: 2 ninjas, 1 arena | Prove it's fun before scaling the roster |

**Consequence of the shared camera:** arenas must be compact and vertical rather
than sprawling. Players cannot roam far apart. This is a constraint on level
design, not a bug — arenas are designed as *rooms*, roughly 40x40 units with
strong verticality, not open fields.

**Consequence of local-only:** input is read per-device and gameplay state is
authoritative on one machine. We are not building netcode, but we keep one
discipline that makes it possible later: **all gameplay state changes flow
through the fighter's state machine driven by an `InputFrame` struct**, never
directly from raw `Input` polling scattered across scripts. If online is ever
added, `InputFrame` is the thing that goes over the wire.

---

## 3. Stats — the spine of the game

Stats are the single mechanism that ties characters (P1) to the environment
(P2). They are not just damage multipliers; they are **permission checks**.

Six stats, each rated **1–5**:

| Stat | Combat effect | Environmental permission |
|---|---|---|
| **STRENGTH** | Damage, knockback, throw distance | Mass class of objects you can lift/throw/break |
| **SPEED** | Move speed, dash charges, attack startup | Traversal gaps, outrunning hazards |
| **AGILITY** | Air control, jump count | Wall-climb, ledge grab, pole swing |
| **TECH** | — | Hack terminals, turrets, doors, traps |
| **FOCUS** | Power meter size and regen rate | Duration/range of powers |
| **TOUGHNESS** | Max HP, hitstun resistance, armor frames | Surviving environmental hazards |

### The permission rule
Every interactable in the world declares `required_stat` and `required_tier`.
A fighter may interact if `fighter.stats[required_stat] >= required_tier`.

This gives us the Nemesis-like moment for free: the strength character walks up
to a concrete pillar and rips it out of the floor; the hacker walks up to the
same pillar and simply cannot. **Crucially, the prompt still shows** — greyed
out, with the requirement visible ("STRENGTH 4"). Players learn the stat system
by being denied, and learn what the *other* characters can do by seeing what
they themselves can't. This is a deliberate teaching mechanism, not a UI
oversight.

Every character has at least one stat at 4+ and at least one at 2 or below.
No well-rounded characters — that's P1.

---

## 4. Roster

Eight ninjas at full scope. Two are fully built in the vertical slice.

### Vertical slice characters

**Kurogane — "Ironjaw"** *(super strength bruiser)*
> A defector from a clan of forge-smiths, his body is more iron than man.

| STR | SPD | AGI | TECH | FOC | TGH |
|---|---|---|---|---|---|
| **5** | 2 | 2 | 1 | 3 | **5** |

- **Signature — Seismic Palm:** a short-range shockwave that launches on hit and
  cracks the floor, creating a debris object anyone can then throw.
- **Ultimate — Ogre Rampage:** armor frames on all attacks for 8s; can lift
  mass-class 4 objects (normally 3) and throw *players* as projectiles.
- **Plays like:** slow, unstoppable, wants the arena cluttered with heavy things.
  Cannot climb. Cannot hack. Reaches high ground by throwing something at it.

**Null** *(teleportation + hacking)*
> No face, no name in any registry. Deletes herself from rooms.

| STR | SPD | AGI | TECH | FOC | TGH |
|---|---|---|---|---|---|
| 1 | 4 | 3 | **5** | **4** | 2 |

- **Signature — Blink Strike:** teleport behind the nearest fighter within range
  and strike. Whiffs into a vulnerable recovery if the target moves — high risk.
- **Ultimate — System Seize:** hacks *every* hazard in the arena at once and
  turns them hostile to everyone but her, for 10s.
- **Plays like:** fragile, mobile, wins by controlling the arena rather than the
  opponent. Dies instantly to Kurogane if she stands still.

The slice matchup is deliberately lopsided in *style*: an unkillable slow bruiser
versus a fragile arena-manipulator. If those two are fun against each other, the
combat core is sound.

### Built since

| Name | Concept | Standout stat | Signature | Ultimate |
|---|---|---|---|---|
| **Jinsoku** | Super speed | SPD 5 | Afterimage Flurry — dash through, leave a decoy | Hundred Steps — move and attack far faster |
| **Yamabuki** | Grappling / traversal | AGI 5 | Grapple Line — a ride to the nearest high ground | Dragnet — haul the whole arena to her feet |

Yamabuki's line was designed here as "grapple to any climbable surface" and
built against the arena's *geometry* instead. Keying it to Climbable nodes
would have made the power a property of how a level happened to be decorated —
the Proving Ground has one climbable wall, so AGILITY 5 would have had exactly
one place in the level to use its own verb. Anything she could stand on is a
valid anchor, which makes the power a reading of the room.

### Remaining roster (designed but not built)

| Name | Concept | Standout stat | Signature power |
|---|---|---|---|
| **Shirayuki** | Telekinesis | FOC 5 | Pull/throw objects and players at range |
| **Kagerou** | Shadow / invisibility | AGI 5 | Fade — invisible while not attacking |
| **Raiden-Maru** | Lightning | FOC 4, SPD 4 | Chain arc between grounded fighters |
| **Mokushi** | Regenerating tank | TGH 5, STR 4 | Second Wind — revive once per stock |

---

## 5. Combat system

Ground-based 3D brawler, juggle-oriented.

**Core loop:** poke → confirm → launch → juggle → wall-splat or environmental
finish. Environmental objects are the extender that makes juggles interesting.

- **Attacks:** light, heavy, launcher, grab. Light chains into itself (3 hits),
  heavy is the confirm, launcher starts the juggle.
- **Defense:** block (chip damage), directional dodge (i-frames, costs stamina),
  tech on knockdown.
- **Hitboxes:** `Area3D` enabled/disabled by the attack state's frame data.
  Frame data lives in a resource, not hardcoded — placeholder art means we tune
  numbers, not animations.
- **Hitstun & knockback:** scaled by attacker STRENGTH vs defender TOUGHNESS.
  Knockback into a wall causes **wall-splat** (extended stun, free juggle).
- **Meters:** Health, Power (spends on signature/ultimate, regenerates by FOCUS),
  Stamina (dodges).
- **Win condition:** stock-based (3 stocks) with a match timer fallback.

---

## 6. The arena as a weapon (P2)

An `Interactable` base class with a declared permission and a mass class.

| Type | Verb | Typical gate |
|---|---|---|
| **Liftable** | Pick up, carry, throw | STRENGTH ≥ mass class |
| **Climbable** | Wall-run, mantle, hang | AGILITY ≥ 3 |
| **Hackable** | Turn hostile to others, disable | TECH ≥ 3 |
| **Breakable** | Destroy, may spawn Liftable debris | STRENGTH ≥ tier |
| **Hazard** | Damages anyone; hackable to re-target | — |

A fighter carries an `InteractionProbe` (Area3D) that picks the nearest valid
target each frame and drives the contextual prompt. Denied interactions still
display — see the permission rule in §3.

**Slice arena — "The Server Shrine":** a compact temple retrofitted with server
racks. Concrete pillars (Liftable, mass 3 — Kurogane only), a climbable outer
wall (AGI 3 — not Kurogane), two hackable ceiling turrets (TECH 3 — Null only),
and breakable server racks that spawn light debris anyone can throw. Every
interactable in the slice is gated to exactly one of the two slice characters,
or to neither — so the stat system is legible from the first match.

---

## 7. Camera — the shared smart camera

The riskiest system, because it can single-handedly kill P3.

1. Compute the AABB of all living fighters each frame.
2. Position the camera to frame that AABB with padding, clamped to `[min_zoom,
   max_zoom]` and to the arena bounds.
3. **Smoothing is asymmetric:** zoom out fast, zoom in slow. Snapping in on a
   KO and back out is nauseating.
4. **Soft leash:** a fighter approaching the frame edge at max zoom gets an
   off-screen indicator and a gentle inward force. Arenas are compact enough
   (§2) that this should rarely fire.

---

## 8. Input — 4 controllers, one machine

**Not** Godot's InputMap with `p1_*`/`p2_*` duplicated actions. That approach
requires 4x action definitions and makes device hot-join painful.

Instead, an `InputSource` abstraction:

- `KeyboardInputSource` — one player, WASD + keys.
- `GamepadInputSource(device_id)` — reads `Input.get_joy_axis/is_joy_button_pressed`
  directly for its own device.

Each produces an **`InputFrame`** each tick: `{move: Vector2, aim: Vector2,
light, heavy, launcher, grab, block, dodge, jump, interact, signature, ultimate}`
with pressed/just-pressed/released state.

A `PlayerManager` maps player slot → `InputSource`, handles join-by-button-press
at the character select screen, and handles device disconnect gracefully
(pause + "reconnect controller P3"). Fighters consume only `InputFrame` — they
never poll `Input` directly. This is the discipline noted in §2 that keeps a
future online port possible.

---

## 9. Architecture

```
project.godot
docs/            GAME_DESIGN.md, ROADMAP.md
src/
  core/          match_manager, game_state, player_manager
  input/         input_source, keyboard_input, gamepad_input, input_frame
  characters/    character_def (Resource), fighter, states/, roster/*.tres
  powers/        power (base), individual power scripts
  interactables/ interactable base + Liftable/Climbable/Hackable/Breakable/Hazard
  camera/        arena_camera
  ui/            hud, player_hud, character_select, prompt
  arenas/        arena base + server_shrine
scenes/          composed .tscn files
tests/           GUT-style headless test scenes
```

**Data-driven roster.** A `CharacterDef` Resource holds stats, colors, display
name, and scene references for powers. Adding ninja #3 should be authoring a
`.tres` plus one or two power scripts — not touching the fighter class. If
adding a character requires editing `fighter.gd`, the abstraction has failed.

**State machine per fighter.** Explicit states (Idle, Run, Jump, Fall, Attack,
Hitstun, Knockdown, Carrying, Climbing, Blocking, Dodging, PowerCast). States own
their transitions. This is the single biggest defense against the
"if-statement soup" that kills brawler codebases.

---

## 10. Risks

| Risk | Why it's real | Mitigation |
|---|---|---|
| **Shared camera fails at 4P** | Players naturally spread out; it's the #1 reason this genre uses split-screen | Compact arenas by design; build the camera in Milestone 1, not last; fall back to split-screen is a known escape hatch |
| **Combat feel is flat with primitives** | No animation means no anticipation or impact | Lean hard on hitstop, screen shake, knockback, and particle hits — feel from code, not art |
| **Stat gating feels arbitrary** | Being denied is frustrating if unexplained | Always show denied prompts with the requirement; gate every slice interactable to exactly one slice character |
| **Scope** | 8 characters x unique powers is a lot | Roster is data-driven; slice proves the core before any of it is built |

---

## 11. What "done" looks like for the slice

Four controllers plugged in, two of the four picking Kurogane and Null, fighting
in The Server Shrine. Kurogane rips out a pillar and throws it. Null blinks
behind him and hacks a turret to shoot him. The camera keeps both readable.
Someone loses their last stock and the match ends.

If that is fun, we scale the roster. If it isn't, we fix it before building six
more characters on top of it.
