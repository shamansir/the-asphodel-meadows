# clock spike

Step 1 of ARCHITECTURE.md §12. It exists to prove one thing:

```
frame = render(timeline, wallClock)
```

If that holds, joining late, backgrounded tabs, pause, rewind and "everyone sees the
same moment" all fall out of it for free. If it does not hold, the rest of the design
does not work.

## Run it

```bash
elm make src/Main.elm --output=main.js
cd .. && python3 -m http.server 8123
```

Then open <http://localhost:8123/app/index.html>.

It must be served over HTTP, not opened as a `file://` URL — the client reads the
server's `Date` response header to correct for a wrong local clock (§1).

| key | |
|---|---|
| `space` | pause / resume (resume snaps back to live) |
| `←` `→` | seek ∓10s |
| `L` | return to live |
| `S` | toggle 12fps stepped sampling — the difference is the whole cartoon feel |
| `D` | toggle the detail readout |

## Check it without a browser

```bash
elm make src/Probe.elm --output=probe.js && node probe.mjs
```

`Probe.elm` runs the same `Fold` the renderer uses and checks the three properties the
architecture rests on: seek-anywhere, determinism (`state(t) == state(t + cycle)`, the
same guarantee that makes two browsers agree), and continuity (nothing teleports between
adjacent frames — the failure you get if a beat is ever treated as a delta).

## What to look for

- Reload at any moment. You land mid-gesture and mid-sentence, never at a scene start.
- Open it in two browsers at once. Same frame, same wiggle, same half-typed word.
- Background the tab for a few minutes, come back. It is where it should be, with no
  fast-forward.
- `←` a few times, then `L`. That is §13 rewind, in full.

## What is real and what is placeholder

**Real** — the clock, `Fold`, seek, skew correction, keyframe semantics, deterministic
incidental motion, the script format itself.

**Placeholder** — the fixture, the characters, the rig, the pose table, the faces. All of
that is hardcoded in `Render.elm` and belongs in `rig.json` in the data repo once the
engine goes world-agnostic (§4.3).

The fixture loops via its `cycle` field so the clock always has something to show. The
real client walks a manifest and never wraps.

## Known rough edges

- The loop seam is visible: scene 3 ends with the cast scattered and scene 1 restarts
  them at their opening marks. Real chunks carry position continuity across the boundary
  (the compiler checks it, §8).
- Poses outlive the acts that accompany them — an actor left in `handsUp` stays that way
  until a later beat says otherwise. That is correct keyframe behaviour and an authoring
  lesson for the writer prompt, not a bug.
- No device-pixel-ratio handling, so it is soft on retina displays.
