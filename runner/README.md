# Realm Runner

A medieval endless runner — Subway Surfers' shape, a castle causeway instead of
a rail yard. One self-contained HTML file: no build step, no assets, no network.
Everything (the runner, the guard, the carts, the gate arches) is drawn
procedurally on a 2D canvas through a hand-rolled perspective projection.

## Play

Open `index.html` in any browser. On a phone, save the file and open it, or
serve the folder and visit it:

```sh
python3 -m http.server 8000   # then http://<your-computer-ip>:8000/runner/
```

## Controls

| Action | Touch | Keyboard |
| --- | --- | --- |
| Change lane | swipe left / right | ← → or A D |
| Vault | swipe up, or tap | ↑ W or Space |
| Roll | swipe down | ↓ S |
| Pause | the button, top right | P or Esc |
| Mute | — | M |

## Rules

Three lanes. Barrels, haystacks and crates are vaulted; a dropped portcullis is
rolled under; standing stones can only be dodged. Covered wagons are lane-wide —
change lanes early, or vault onto the canvas and run along the top. Gold is
score. Three relics drop along the road:

- **Warding shield** — eats one mistake and shoves the obstacle aside.
- **Lodestone** — drags nearby gold to you for nine seconds.
- **Swift boots** — a third again the speed, and the score that comes with it.

The road speeds up the longer you last. Miss, and the guard behind you closes.
Best score is kept in `localStorage`.
