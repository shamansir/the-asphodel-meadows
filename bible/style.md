# Art direction

## The look

Rubber-hose cartooning — 1920s–30s animation grammar — applied to a Victorian detective
story set in a Greek underworld. Noodle limbs, round caps, generous squash and stretch,
poses held a beat too long.

The style is doing real work, not decoration. It is what makes a closed verb vocabulary
sufficient: a pose is a handful of angles, so the writer agent choreographs from a finite
alphabet instead of inventing artwork. It also undercuts the setting exactly as much as the
tone needs — nobody can take a filing dispute too seriously when the filer's arms are made
of hose.

Animate on twos, sampled at 12fps against a 60fps canvas. Smooth interpolation reads as a
slideshow of tweens; stepping reads as animation.

## Palette

Three families, and they must not blend.

**The House** — cold, administrative. Slate, ash, ink, jaundiced lamplight. Desaturated
except for the lamps, which are the only warm thing and are always slightly too orange.

**The Fields** — endless soft grey-green. Pleasant, and that is the problem with them. Flat,
low contrast, no horizon detail.

**London** — sepia, high contrast, over-warm. Always looks like a memory of itself, because
it is one. Slightly wrong on purpose: a door on the wrong side, a street too short.

Gods carry a single saturated accent colour each, and it is the only saturation in most
frames. Holmes has none — he is the one grey figure in a room of colour, which is the whole
composition of the season.

## Line

Heavy, uniform, slightly wobbling. Ink that looks brushed rather than plotted. No line
weight variation for depth — use value and overlap instead.

Backgrounds are painted flats with no outline. Characters are outlined. The separation
should be obvious and unapologetic.

## Bubbles

- `normal` — soft ellipse, black line
- `shout` — spiked, thicker line, larger type
- `whisper` — dashed line, smaller type, higher transparency
- `thought` — cloud lobes, grey line, bubble-trail tail
- `narration` — a hard rectangle, no tail, top of frame. Hermes only.
- `deduction` — see below

All text is pre-wrapped by the compiler using shipped font metrics. The browser never
measures text (§4.2), so bubble geometry is identical for every viewer.

## The deduction grammar

The one thing this show has to render that no other cartoon does: **reasoning made
visible**. The trait the audience is here for is Holmes's inference, so it needs a visual
form of its own, not just dialogue.

Four elements, used together:

**`insert` shot.** A hard cut to the clue, filling frame, flat background. Every clue used
in a solution must have had an insert before the solution. No off-screen deductions.

**`annotate` overlay.** Drawn *over* the stage, in a single accent colour, hand-inked: a
circle around a detail, an arrow between two, a link line, a short label. It appears with a
scratchy draw-on, holds, and does not fade — it is wiped by the next cut.

**`deduction` bubble.** Not an ellipse. A ruled rectangle with a hairline border, mono-ish
type, left-aligned, revealing line by line rather than character by character. It reads as
a different register of speech: this is not conversation, this is the machine running.

**`dawning` expression.** The listener's face, held. The punctuation at the end of a chain.
Use it on whoever is *not* speaking — the deduction lands on a face, not in a bubble.

Sequence:

```
camera insert   →  annotate circle   →  deduction bubble   →  camera mid  →  expr dawning
```

Keep chains to three or four links on screen. Longer inferences get broken across shots.
A chain that fills the frame stops reading as thought and starts reading as a diagram.

## What to avoid

- Torment, fire, screaming. The underworld is a bureaucracy; the horror is procedural.
- Toga-and-sandal classicism. These are civil servants who have been in post a very long
  time. Dress them accordingly, in whatever era they stopped paying attention.
- Any visual joke about the crossover being a crossover.
- Holmes in the deerstalker. He is not on the moors and he never wore it in town.
