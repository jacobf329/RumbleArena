# RumbleArena

A 4-player local versus arena brawler in Godot 4.3. Named ninjas with super
powers tear each other — and the arena itself — apart.

Spiritually a *Marvel Nemesis: Rise of the Imperfects* clone: asymmetric
super-powered fighters in interactive, destructible arenas where what you can
lift, climb, break, or hack is gated by your character's stats.

## Status

**M1 complete** — four players can join with gamepads or keyboard and run, jump,
double-jump and dash around a grey-box arena under a single shared camera.
Combat starts at M2. See [`docs/ROADMAP.md`](docs/ROADMAP.md).

![Four players in the Proving Ground](docs/images/m1-four-players.png)

The camera frames everyone and pushes in when the fight closes up:

![The camera pushing in](docs/images/m1-camera-close.png)

## Design

- **[`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md)** — pillars, stat system,
  roster, combat, arena interaction, camera, input, architecture, risks.
- **[`docs/ROADMAP.md`](docs/ROADMAP.md)** — milestones and working practices.

## The short version

Six stats (Strength, Speed, Agility, Tech, Focus, Toughness) rated 1–5 act as
**permission checks** on the world, not just damage multipliers. A concrete
pillar declares "STRENGTH 3" — the bruiser rips it out and throws it, the hacker
sees the prompt greyed out and learns what she isn't. Every character has at
least one stat at 4+ and one at 2 or below. There are no well-rounded ninjas.

## Running it

Open the project folder in Godot 4.3 and press play. Press **A** on a gamepad or
**Space** on the keyboard to take a seat; up to four can join at any time, and a
pad can be unplugged and plugged back in without losing its fighter.

Each seat gets a different stat block, so the movement asymmetry is apparent
immediately: Kurogane is heavy and cannot double jump at all, Jinsoku is quick,
Yamabuki jumps highest.

| | Gamepad | Keyboard |
|---|---|---|
| Move | Left stick | WASD |
| Jump | A (hold for height) | Space |
| Dash | Left trigger | Shift |
| Light / Heavy / Launcher | X / Y / RB | J / K / L |
| Grab / Block | B / LB | U / Ctrl |
| Interact / Signature / Ultimate | D-pad up / RT / D-pad down | E / Q / R |

F5 returns everyone to their spawn. Combat buttons are wired through to the
input layer but do nothing yet — that is M2.

## Testing

```sh
GODOT=/path/to/godot ./run_tests.sh
```

Imports the project to surface script and scene parse errors, then runs a
36-check smoke test that drives real fighters through the real main scene using
scripted input sources. Because fighters only ever read an `InputFrame`, the
whole movement system is testable headlessly with no hardware.

## Repo layout

| Path | Contents |
|---|---|
| `docs/` | Design document and roadmap |
| `src/core/` | Match flow, game state, player management |
| `src/input/` | `InputSource` / `InputFrame` abstraction (keyboard + gamepad) |
| `src/characters/` | `CharacterDef` resources, fighter, state machine, roster |
| `src/powers/` | Power base class and per-character powers |
| `src/interactables/` | Liftable, Climbable, Hackable, Breakable, Hazard |
| `src/camera/` | Shared smart arena camera |
| `src/ui/` | HUD, character select, contextual prompts |
| `src/arenas/` | Arena scenes |
| `tests/` | Headless validation scenes |
