# RumbleArena

A 4-player local versus arena brawler in Godot 4.3. Named ninjas with super
powers tear each other — and the arena itself — apart.

Spiritually a *Marvel Nemesis: Rise of the Imperfects* clone: asymmetric
super-powered fighters in interactive, destructible arenas where what you can
lift, climb, break, or hack is gated by your character's stats.

## Status

**M2 complete, plus the character model and rhythm combos** — four players join
with gamepads or keyboard and fight in a grey-box arena under a single shared
camera: punch-punch-kick chains, heavy and launcher confirms, blocking, dodging,
juggles, knockdowns and wall splats, with timing-based rhythm bonuses.
Stat-gated environmental interaction starts at M3. See
[`docs/ROADMAP.md`](docs/ROADMAP.md).

One mesh, one texture, four players — the shader rotates the hue of the crimson
only, so skin and armour stay put:

![The four players](docs/images/roster.png)

![Kurogane landing a heavy](docs/images/m2-impact.png)

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

## Playing it

1. **Install Godot 4.3** from [godotengine.org/download](https://godotengine.org/download).
   Take the standard version, not .NET. It is a single executable — there is no
   installer to run.
2. **Get this branch:** `git clone` the repo and `git checkout claude/godot-ninja-game-96kjrj`,
   or pull if you already have it.
3. **Double-click a launcher** in the project folder:
   - Windows → `Play RumbleArena.bat`
   - macOS → `Play RumbleArena.command` (first time: right-click → Open, to get
     past Gatekeeper)
   - Linux → `play.sh`

The launcher looks for Godot on your PATH, beside the project, in the usual
install folders, and in Downloads. If it cannot find it, create a file called
`godot_path.txt` next to the launcher whose only line is the full path to your
Godot executable.

**If it complains about Vulkan**, your GPU or its drivers cannot run the default
renderer. Run the launcher with `--compat` to use OpenGL instead.

You can also just open the project folder in Godot and press play.

Press **A** on a gamepad or **Space** on the keyboard to take a seat; up to four
can join at any time, and a pad can be unplugged and plugged back in without
losing its fighter.

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

F5 returns everyone to their spawn.

Light chains **punch, punch, kick**; heavy and launcher are confirms that only
cancel out of a move that actually connected, so whiffing a heavy costs you the
full recovery. Block covers the front only. Dodge has invulnerability frames and
costs stamina. Knocking someone into a wall splats them and hands you a juggle.

**Rhythm.** Mashing combos fine — it just earns nothing. Time each follow-up to
the moment the previous move becomes cancellable and it scores *on beat*: faster
startup, more damage, and a flow streak that compounds while the chain stays
clean. The window is about a quarter of a second, and hitstop is frozen out of
it, so the freeze never eats your timing.

### What is rough, so you know it is not your setup

- **There is no idle animation yet** — standing still plays the walk cycle
  slowly, so fighters march on the spot.
- **No hit-reaction clip**, so a fighter freezes on whatever pose it was caught
  in when hit. It reads as stunned, which is nearly right, but it is a
  placeholder.
- **Knockdown tips the model over** rather than animating to the floor.
- **A defeated fighter respawns at full health** so playtesting continues;
  stocks and match flow arrive with M4.
- **Space both joins and jumps**, so joining on the keyboard hops once.
- `rigify_clip.glb` imports as 0.07s despite being 3.03s in the source, so it is
  unused. Worth re-exporting.

A hit-reaction, an idle and a knockdown/getup clip would be the three most
valuable animations to add next.

## Testing

```sh
GODOT=/path/to/godot ./run_tests.sh
```

Imports the project to surface script and scene parse errors, then runs the
suites: 36 movement, input and camera checks, and 51 combat checks. Every test
drives real fighters through the real main scene using scripted input sources.
Because fighters only ever read an `InputFrame`, the whole game is testable
headlessly with no hardware.

## Repo layout

| Path | Contents |
|---|---|
| `docs/` | Design document and roadmap |
| `src/core/` | Match flow, game state, player management |
| `src/input/` | `InputSource` / `InputFrame` abstraction (keyboard + gamepad) |
| `src/characters/` | `CharacterDef` resources, fighter, state machine, roster |
| `assets/characters/` | Ninja model, stripped animation clips, hue shader |
| `src/combat/` | Frame data, movesets, hit resolution, damage formulas |
| `src/powers/` | Power base class and per-character powers |
| `src/interactables/` | Liftable, Climbable, Hackable, Breakable, Hazard |
| `src/camera/` | Shared smart arena camera |
| `src/ui/` | HUD, character select, contextual prompts |
| `src/arenas/` | Arena scenes |
| `tests/` | Headless validation scenes |
| `tools/` | Asset pipeline: GLB stripper, animation library builder, impact analysis |
