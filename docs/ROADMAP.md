# RumbleArena — Roadmap

Milestones are ordered so that the riskiest assumptions get tested earliest.
Each milestone ends in something playable, not just compilable.

---

## M1 — Foundation: one fighter, one box, one camera
**Risk under test:** does the shared camera work, and does moving feel good?

- [ ] Godot 4.3 project skeleton, headless-validated in CI
- [ ] `InputSource` / `InputFrame` abstraction; keyboard + gamepad
- [ ] `PlayerManager` with join-by-button-press and 4 slots
- [ ] `Fighter` CharacterBody3D with state machine (Idle/Run/Jump/Fall)
- [ ] Movement tuning: accel, air control, jump arc, dash
- [ ] `ArenaCamera` framing 1–4 fighters with asymmetric smoothing
- [ ] Grey-box test arena

**Playable result:** 4 capsules run and jump around a box, camera keeps them all
on screen. Boring, but it either feels good or it doesn't — and we find out now.

---

## M2 — Combat core
**Risk under test:** does hitting someone feel good with no animation?

- [ ] Frame-data resource + hitbox/hurtbox `Area3D` activation
- [ ] Light chain, heavy, launcher, grab/throw
- [ ] Hitstun, knockback scaled by STR vs TGH, juggle state
- [ ] Block, directional dodge with i-frames, knockdown tech
- [ ] Wall-splat
- [ ] Game feel pass: hitstop, screen shake, hit particles, freeze frames
- [ ] Health / Power / Stamina meters

**Playable result:** two capsules can actually fight, and it has impact.

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

- **Headless validation every commit.** Godot 4.3 runs headless in this
  environment; scripts and scenes get parsed before anything is pushed. A commit
  that doesn't import cleanly doesn't get made.
- **No character-specific code in `fighter.gd`.** If a new ninja needs it, the
  abstraction is wrong — fix the abstraction.
- **Fighters never poll `Input` directly.** Everything goes through `InputFrame`.
- **Tune numbers in resources, not code.** Frame data, movement constants, and
  stats are data so they can be changed without a code review.
