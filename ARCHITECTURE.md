# Asphodel Meadows — architecture

A always-on, comic-styled 2D animated web page. The world runs on a shared clock, so
every viewer sees the same moment at the same time. What happens is written ahead of
time by an agent that reads the world's memory, and published as static files.

Nobody watches an episode. People drop in on a world that has been running without them.

---

## 0. Decisions already made

| Question | Decision |
|---|---|
| Visuals | AI-generated location backgrounds (one-time, per location) + hand-rigged sprite characters animated procedurally |
| Client | Elm + canvas (`joakin/elm-canvas`) |
| Editorial control | Agent publishes directly. Human can edit any scene that has not aired yet, via a local editor. Missed mistakes ship. Page discloses that it is AI-run. |
| Hosting | GitHub Pages, static only, no backend |
| Openness | Fully open. Script, memory, and bible are published as they are written. No encryption, no time-gating, no spoiler defence — leaks are treated as engagement, not damage. See §13. |
| Repo split | Two repos: **data** (this world) and **engine** (renderer, compiler, agent, plus a sample world for rehearsal). See §13. |
| Universe | Sherlock Holmes × Greek myth, in one world. Season 1 is *The Great Hiatus* — the three years Doyle never explained. Both sources fully public domain, so there is no IP exposure at all. Tone: *Knives Out*. See `bible/world.md`. |

### The name

**Asphodel Meadows** — the grey endless field of the ordinary dead, and the largest part
of this world. Short namespace: `asphodel`.

It is a place rather than a person, so it survives the season resets in §6 that replace
the entire cast. And it comes from inside the world rather than commenting on it: the
title deliberately does not wink at the Holmes-among-the-gods premise, because
`bible/world.md` rule 7 forbids any character from finding that premise remarkable. A
title that makes the joke undercuts the show before the first frame.

---

## 1. The time model

This is the load-bearing idea. Everything else is downstream of it.

The show is **not** simulated live. There is no server tick, no socket, no per-viewer
state. There is a precomputed timeline and a clock.

```
worldTime : Seconds
worldTime = (now - EPOCH) / 1000

frame = render (timeline, worldTime)
```

Rendering is a pure function of the timeline and the wall clock. Consequences:

- **No drift.** Every frame recomputes state from absolute `t`. A backgrounded tab that
  gets rAF-throttled for ten minutes resumes correct, with no catch-up logic.
- **No join cost.** Opening the page late is the same operation as playing: find the
  scene containing `t`, seek into it.
- **Shared moment.** Two people in different cities see the same beat. This is the
  social hook — "did you see what the mayor did at 14:20 today".
- **Pause is a local clock offset.** Resume snaps back to wall clock and skips what was
  missed. The skipped scenes really did happen; the world log records them.

### Seek-anywhere constraint

Because a viewer can land at any offset inside a scene, scene state must be computable
without simulating frames. Therefore:

> **Every beat is a keyframe assignment, never a delta.**

`walk to stall` means "position interpolates from wherever the last position keyframe
put me, to `stall`, over `dur` seconds". It does not mean "add velocity". To seek to
`localT`, fold all beats with `t < localT` instantly, then interpolate the ones still
in flight. O(beats-in-scene), microseconds.

Same rule for speech: a bubble is visible over `[t, t + dur]`. Joining mid-bubble shows
the typewriter reveal at the correct offset, not from the start.

### Clock skew

Client clocks are wrong sometimes. On boot, read the `Date` response header from the
manifest fetch (`Http.expectStringResponse` exposes `metadata.headers`), compute
`skew = serverDate - clientNow`, and apply it to every `worldTime` call. Re-measure on
each manifest poll. Without this, a viewer with a 4-minute-fast clock silently watches
a different scene than everyone else.

### Determinism of the incidental

Idle sway, blink timing, background crowd, leaf drift — none of it is in the script, but
all of it must match across viewers or the "same moment" promise leaks. Seed a
hash-based PRNG (splitmix64) from `(sceneId, actorId, floor(t / bucket))`. Same inputs,
same wiggle, everywhere.

---

## 2. Layers

```
  bible/         world rules, cast, art direction, closed vocabulary   [human]
      |
  memory/        world log + per-character memory, compacted over time [agent-written]
      |
  writer agent   cron: bible + memory + open arcs -> next chunk JSON   [agent]
      |
  compiler       validate, lay out text, resolve assets, emit chunk    [CI, deterministic]
      |
  seasons/       published chunks + manifest                           [static files]
      |
  Elm client     seek by wall clock, render canvas                     [browser]
```

The compiler sits between the agent and the world on purpose. The agent writes
*intent*; the compiler turns intent into something the renderer can execute, and
refuses anything the renderer cannot execute. The agent never touches pixels, never
invents an asset, never picks a font size.

---

## 3. Repository layout

Two repositories, split by concern (§13): **data** is one world, **engine** runs any
world.

### `asphodel-data` — this world

```
/
  README.md                     AI-disclosure text, how to read the raw script
  bible/
    world.md                    setting, rules, tone, what cannot happen
    style.md                    art direction, palette, line weight, bubble rules
    vocabulary.json             world verbs + their mapping to engine primitives
    characters/
      ch.holmes.md              character sheet: voice, silhouette, verbal tics
  memory/
    world/
      log.jsonl                 append-only, every event, never deleted, never compacted
      digest.md                 tiered summary for prompt use
      arcs.json                 open arcs with deadlines
    characters/
      ch.holmes/
        core.json               traits, relationships, voice params
        episodic.jsonl          recent events in detail
        compacted.md            older events, salience-summarized
        beliefs.json            what THEY think is true (may be wrong)
  seasons/
    s01/
      manifest.json             chunk index, revisions, hashes, epoch
      index.json                aired-scene index: t0, loc, cast, one-line summary
      chunks/0001.json
  assets/
    rigs/ch.holmes/{atlas.png, rig.json}
    locations/loc.bank/{bg.webp, layers.json}
    fonts/{comic.woff2, metrics.json}
  .github/workflows/
    write.yml                   cron: generate + validate + commit + publish
    compact.yml                 weekly: memory compaction
    pages.yml                   publish seasons/ + assets/ to Pages with CORS
```

Published to Pages as a plain static content API. No build step — the repo contents
*are* the site.

### `asphodel-engine` — the machinery

```
/
  ARCHITECTURE.md
  app/                          Elm client: fetch, seek, render, inspect panel
  editor/                       local scene editor (renderer + form UI + tiny writer server)
  compiler/
    schema/chunk.schema.json
    src/                        validate, text layout, asset resolution
  agent/
    prompts/{write.md, compact.md, finale.md}
    src/
  demo-world/                   sample world: rehearsal fixture, test data, fork template
  .github/workflows/
    build.yml                   Elm build + test + Pages deploy of the app shell
```

`demo-world/` earns its place three times over: it lets a contributor run the whole
thing without the data repo, it is the fixture for `foldBeats` property tests and
screenshot diffs, and it is the "fork this and make your own world" starting point.

Everything either repo is made of is a file in git. The script's revision history is
free, diffable, and revertable — worth a lot when an agent publishes unsupervised.

---

## 4. Data formats

### 4.1 Manifest

```json
{
  "season": "s01",
  "epoch": "2026-08-01T00:00:00Z",
  "vocabularyHash": "sha256:8f3c…",
  "chunks": [
    { "id": "0141", "t0": 1123200, "t1": 1209600, "rev": 3, "url": "chunks/0141.json", "hash": "sha256:…" },
    { "id": "0142", "t0": 1209600, "t1": 1296000, "rev": 1, "url": "chunks/0142.json", "hash": "sha256:…" }
  ],
  "generatedAt": "2026-08-14T03:00:12Z"
}
```

`t0`/`t1` are world-seconds since epoch. Clients poll this every ~5 minutes (long-lived
tabs are the norm here) and prefetch the chunk that will be current in ~10 minutes.

### 4.2 Chunk

```json
{
  "chunk": "s01-case001",
  "t0": 1209600,
  "rev": 1,
  "scenes": [
    {
      "id": "s002",
      "t0": 100,
      "dur": 105,
      "loc": "loc.bank",
      "cast": [
        { "id": "ch.holmes", "at": [0.35, 0.79], "facing":  1, "pose": "stoop", "expr": "neutral" },
        { "id": "ch.hermes", "at": [0.60, 0.80], "facing": -1, "pose": "idle",  "expr": "confused" }
      ],
      "beats": [
        { "t": 8,  "dur": 0.4, "cam": { "to": [0.5, 0.30], "zoom": 2.4, "shot": "insert" } },
        { "t": 9,  "dur": 15,  "ann": { "kind": "circle", "at": [0.5, 0.30], "r": 0.05, "label": "THE OBOL" } },
        { "t": 12, "who": "ch.holmes", "dur": 6,
          "say": { "kind": "deduction",
                   "lines": ["IT BENDS UNDER THE NAIL.", "STRUCK METAL DOES NOT."],
                   "w": 328, "h": 82 } },
        { "t": 25, "dur": 0.4, "cam": { "to": [0.45, 0.52], "zoom": 1.2, "shot": "mid" } },
        { "t": 26, "who": "ch.hermes", "expr": "shocked", "dur": 4.5,
          "say": { "kind": "normal",
                   "lines": ["Foil isn't— that's not", "money. That's not money!"],
                   "w": 322, "h": 76 } }
      ],
      "emits": [
        { "id": "evt.coin_is_foil", "weight": 0.7,
          "text": "The surplus coin is gold foil, never legal fare. It was placed to correct the count, concealing an unpaid crossing.",
          "witnesses": ["ch.holmes", "ch.hermes", "ch.charon"] }
      ]
    }
  ]
}
```

Notes on the shape:

- `at` / `to` are normalized stage coordinates, resolution-independent.
- `say.lines`, `w`, `h` are **precomputed by the compiler**, not by the browser.
  `elm-canvas` has no `measureText`, and even if it did, cross-browser text metrics
  would break the shared-moment guarantee. The compiler wraps text using the shipped
  font metrics table, so every viewer gets byte-identical bubble geometry.
- `emits` is how a scene writes to memory. `weight` is the agent's own estimate of
  emotional significance, 0–1, and it drives forgetting later. `witnesses` decides who
  gets the memory — anyone not listed genuinely does not know.

### 4.3 Vocabulary — closed set, and the engine boundary

`bible/vocabulary.json` is the single source of truth for what the agent may write, and
it is enforced by the compiler.

It is also the **contract between the two repos**, so it carries a second job. The
engine must be able to run *any* world — including your own next season, whose verbs
will differ. So the engine knows only a small fixed set of **primitives**:

```
tween      transform a rig root over time (translate / rotate / scale)
blend      interpolate toward a named pose in the rig
express    swap the face layer
bubble     draw a balloon with pre-laid-out lines, typewriter-revealed
camera     tween the view transform
annotate   draw an ink overlay above the stage
```

`annotate` is the sixth, added once the universe was chosen: a detective show has to
render *reasoning made visible*, and the first five primitives cover only bodies and
speech. It draws circles, arrows and link lines over the stage in one accent colour.
The full deduction grammar — `insert` shot, annotation, `deduction` bubble, `dawning`
expression — is in `bible/style.md`.

Finding this before rig art started is exactly why §12 orders the vocabulary ahead of
the drawing.

World verbs are *data that compiles to primitives*, never Elm constructors:

```json
{
  "acts": {
    "walk": { "prim": "tween", "curve": "easeInOut", "cycle": "walkCycle", "speed": 0.09 },
    "fall": { "prim": "tween", "curve": "easeIn", "pose": "slump", "rot": 90 },
    "give": { "prim": "blend", "pose": "reach", "hold": 0.4, "attach": "hand.r" }
  },
  "poses":   ["idle","shrug","armsCrossed","handsUp","slump","lean","crouch","hide"],
  "expr":    ["neutral","happy","sad","angry","shocked","smug","confused","crying",
              "laughing","tired"],
  "bubbles": ["normal","shout","whisper","thought","narration","offscreen"],
  "camera":  { "shot": ["wide","mid","close"], "move": ["hold","pan","push","pull","cut"] }
}
```

If `act` were an Elm custom type, adding a verb would mean an engine release, and the
engine could never run someone else's world. As data, adding `"clamber"` is a rig pose
plus four lines of JSON in the data repo, with no engine change at all.

The closed set is still the whole trick for visual consistency: the agent is a
*choreographer over a finite alphabet*, never an illustrator. A vocabulary edit bumps
`vocabularyHash` in the manifest, which tells clients to drop and reload assets.

---

## 5. Memory and forgetting

Two separate things that must never be conflated:

- **World log** (`memory/world/log.jsonl`) — objective, append-only, never forgotten.
  This is the writers' room record and your own reference as an author.
- **Character memory** — subjective, lossy, and allowed to be *wrong*.

The gap between the two is the single best source of free drama in the system. A
character who misremembers who helped them is a plot, not a bug.

### Tiers, per character

| Tier | Content | Lifetime |
|---|---|---|
| `core.json` | traits, relationships, voice, standing goals | persists across the season, drifts slowly |
| `episodic.jsonl` | full-detail events | ~14 world-days |
| `compacted.md` | salience-weighted prose summary | rest of season |
| `beliefs.json` | asserted facts the character holds, with confidence | until contradicted in-scene |

### Salience

```
salience = 0.45 * weight            # agent's emotional weight, 0..1
         + 0.20 * log(1 + repeats)  # reinforced by recurrence
         + 0.25 * recency           # exp(-age / halfLife), halfLife ~ 10 world-days
         + 0.10 * involvesCore      # touches a core relationship or goal
```

### Compaction job (weekly, or when a budget trips)

1. Take the oldest slice of `episodic.jsonl` beyond the 14-day window.
2. Score each event.
3. Above `keepThreshold`: fold into `compacted.md`, preserving concrete detail —
   names, objects, the actual line said. Specific memories are what make a character
   feel like a person.
4. Below `dropThreshold`: **forget**. Delete from character memory. Still in the world
   log, so you can always see what they lost.
5. Middle band: keep the *feeling*, lose the *fact* — "someone helped when the roof
   went, can't recall who". This band produces the most interesting behaviour.
6. **Distortion pass**, ~5% of retained memories: mutate one detail (attribution, place,
   wording). Log every distortion to `memory/world/distortions.jsonl` so you can trace
   why a character is behaving oddly three weeks later.

### Personality drift

The writer agent may propose deltas to `core.json` — a trait shifting a few points, a
relationship warming or souring — but only with a cited event id as justification, and
clamped to a small per-week magnitude. Unbounded drift turns everyone into the same
character within a month. The clamp is the thing that keeps the cast recognizable.

### Prompt budget

```
bible/world.md + style.md         ~2k tokens   (fixed)
bible/craft.md                    ~1.8k        (fixed)
vocabulary.json                   ~0.4k
open arcs                         ~0.5k
per cast member: core + compacted ~1.5k each   (cast of 4–6 -> ~9k)
recent world digest               ~2k
episodic for cast, 14 days        ~8k
--------------------------------------------
target ceiling                    ~27k, hard cap 40k
```

When post-compaction totals stay above the ceiling, that is the season-pressure signal.

---

## 6. Seasons and reset

Rather than degrading forever, the world ends on purpose.

**Triggers:** compacted memory still over budget after compaction; open arcs stagnant
for N chunks; cast size drift; or manual.

**Finale:** the writer agent gets `prompts/finale.md` and one instruction — resolve
every open arc within the remaining chunks. Nothing new opens.

**New season:** new directory, new epoch, new cast, fresh memory. Prior cast survives
only as `bible/lore/` — legends, references, one returning character if you want the
continuity. The lore file is small and fixed-size, which is exactly why this bounds
context growth forever.

Seasons are the reason this can run for years rather than months.

---

## 7. The writer agent

Runs on cron (`write.yml`), daily or weekly, always keeping a **buffer of at least
3 days of timeline ahead of `now`**. The buffer is what makes editing possible and what
prevents a viewer from ever reaching the end of the world.

Pipeline:

1. **Gather** — bible, vocabulary, open arcs, cast memory, recent world digest.
2. **Plan** — emit an arc-level outline first: which arcs advance, which beats land,
   what changes by the end of the chunk. Cheap to validate, cheap to regenerate.
3. **Write** — expand the outline into chunk JSON against `chunk.schema.json`.
4. **Validate** (see §8). On failure, return errors to the model and retry, max 3.
   On total failure, fall back to ambient filler (§10) and open a GitHub issue.
5. **Emit memory** — append `emits` to world log and to each witness's episodic file.
6. **Commit + deploy.**

Constraints in the prompt, enforced by the validator where possible:

- Advance at least one open arc per chunk; never open more than two new ones.
- Every character acts only on what is in *their* memory. If they know something they
  shouldn't, that is a validation error worth catching by cross-referencing `witnesses`.
- Closed vocabulary only.
- Line length cap per bubble (the compiler enforces the real limit anyway).
- Pacing: mix scene lengths. A chunk of 90-second two-handers is death.

---

## 8. Compiler and validation

Deterministic, runs in CI, no model involved. This is your safety net given that
publishing is unsupervised.

Checks:

- JSON Schema conformance.
- Every `act`/`pose`/`expr`/`bubble`/`camera` value exists in the vocabulary.
- Every `ch.*`, `loc.*`, asset id resolves in the asset manifest.
- Scene timing: beats within `[0, dur]`, no negative durations, no cast member in two
  places, `t0 + dur` chains contiguously across the chunk with no gaps.
- Knowledge check: a character references an event id they were not a witness to and
  have no memory of → error.
- Text layout: wrap all speech with the font metrics table, emit `lines`/`w`/`h`,
  reject any bubble that cannot fit its allowed screen box.
- Continuity: characters' positions and states carry correctly from the previous chunk's
  final scene.

Output: the published chunk plus a human-readable diff summary in the commit message.

---

## 9. The Elm client

### Model

```elm
type alias Model =
    { manifest  : Manifest
    , chunks    : Dict ChunkId Chunk   -- current + prefetched next
    , skewMs    : Float                -- server clock - client clock
    , clock     : Clock                -- Live | Paused Float | Offset Float
    , assets    : AssetStore           -- Canvas.Texture, keyed
    , viewport  : { w : Float, h : Float }
    }

type Msg
    = Frame Time.Posix                 -- Browser.Events.onAnimationFrame
    | PollManifest
    | GotManifest (Result Http.Error ( Manifest, Maybe Time.Posix ))
    | GotChunk ChunkId (Result Http.Error Chunk)
    | TextureLoaded AssetId (Maybe Texture)
    | UserPaused | UserResumed
```

Use `onAnimationFrame` (absolute Posix), not `onAnimationFrameDelta`. Deltas invite
accumulation, and accumulation is drift.

### Frame path

```
worldTime  = (posix + skew - epoch) / 1000
scene      = binarySearch chunk.scenes worldTime
localT     = worldTime - scene.t0
state      = foldBeats scene.beats localT      -- keyframes, then interpolate in-flight
renderables = layout state scene.camera viewport
```

`foldBeats` is the core function and the one worth property-testing: for any `localT`,
folding from scratch must equal folding incrementally. That test is what keeps
seek-anywhere honest as the beat vocabulary grows.

### Rendering

- Static background: composite each location's layers into one `Texture` once, on first
  entry, then draw as a single blit per frame. Do not re-composite per frame.
- Characters: rigs are part trees. A pose is a set of part transforms; blending two
  poses is per-part lerp on translation/rotation/scale. Draw order from `rig.json`.
- Bubbles: pre-wrapped lines from the chunk; the client only draws the balloon path,
  tail, and glyphs. Typewriter reveal is a character-count function of `localT`.
- Comic feel: slightly stepped animation (sample poses at 12fps while the canvas runs at
  60) reads far more like animation than smooth interpolation does. Cheap, big payoff.
- Keep the renderable list small. `elm-canvas` rebuilds it every frame; a few hundred
  items is comfortable, a few thousand is not. Atlas-blit characters, batch aggressively.

### Immutable past, mutable future

Clients hold a timeline that may be revised under them.

> A chunk revision only applies to scenes starting after `worldTime + 120s`. Anything
> already aired or airing is history and is never retroactively swapped.

Poll the manifest every ~5 minutes. On a `rev` bump: fetch the new chunk, splice in only
its future scenes, keep the current scene running untouched. On `vocabularyHash` change:
drop the asset store and reload.

This rule is what makes the editor safe — you can be editing a scene while people are
watching, and nobody sees a jump.

### Accessibility and disclosure

- Prefers-reduced-motion: hold the camera still, keep the beats.
- Ship a text transcript of the current scene behind a toggle. It costs nothing — the
  script is already text — and it makes the page indexable, quotable, and shareable.
- The AI-disclosure line lives in the always-visible chrome, not only in the README.

---

## 10. Failure modes

| Failure | Consequence | Mitigation |
|---|---|---|
| Agent produces invalid JSON | No new chunk | Schema + retry ×3; ambient filler fallback; GitHub issue |
| Cron fails silently for days | Viewer runs off the end of the timeline | 3-day buffer; client falls back to ambient generator seeded by `t`; disclose "the world is idling" |
| Model quality degrades | Boring or incoherent world | Arc-advance requirement; weekly human read of the world digest |
| Character omniscience | Continuity breaks | Witness cross-check in validator |
| Cast bloat | Every scene a crowd | 6 active memory files, 5 speaking parts per scene; validator warns |
| Agent introduces a held-back character | Season arc spent early | `status: dormant` in the character file; compiler rejects any scene casting one |
| Bubble overflow | Unreadable | Compiler-side layout with real font metrics |
| Client clock skew | Viewers desynced | `Date` header skew correction |
| Long-lived tab misses revisions | Stale timeline | 5-minute manifest poll |
| Season never resets | Context rot, incoherence | Budget-tripped finale |

---

## 11. Cost

- Hosting: free (GitHub Pages, all static).
- Writer agent: one run per day at ~25–40k input tokens plus output. Single-digit
  dollars per month.
- Backgrounds: one-time image generation per location, plus cleanup. Reused forever.
- Rigs: the real cost, and it is your time, not money. Budget one character rig as a
  meaningful chunk of art work; the second is much faster because the vocabulary is
  already fixed.

Compute is not the constraint here. Art vocabulary and taste are.

---

## 12. Build order

1. **Spike the clock.** Hardcoded chunk JSON, two stick figures, one location, speech
   bubbles. Prove seek-anywhere: open the page at three random times, confirm state is
   correct and identical across two browsers. Everything else depends on this working.
2. **Bible + vocabulary.** Write the world, then freeze the vocabulary. It is the
   contract between art, agent, renderer, *and the two repos* — freezing it early is
   what lets all those tracks proceed in parallel. The spike from step 1 becomes
   `demo-world/`.
3. **Rigs and one real location.** Replace the stick figures.
4. **Compiler + schema.** Text layout, validation, asset resolution.
5. **Writer agent, human-run.** Generate chunks by hand invocation, read every one,
   tune the prompts until the output is consistently shippable.
6. **Memory + compaction.** Only meaningful once there is history to compact.
7. **Cron.** Hand the keys over.
8. **Editor.** Renderer plus a timeline scrubber and a beat form; a tiny local server
   writes the chunk file and you push. Runs locally, so no auth story, no backend.
9. **Season machinery.** Not needed until roughly month three.

Steps 1 and 2 answer the only questions that can kill the project. Do them first, and
do not start on rig art before the vocabulary is frozen.

---

## 13. Rewind (DVR mode)

Viewers can step back in time. Implementation is nearly free — playback is already a
pure function of `(timeline, t)`, so rewind is a negative clock offset and nothing else.
No simulation, no state to rebuild.

```elm
type Clock
    = Live               -- t = wallClock
    | Paused Float       -- t frozen
    | Rewound Float      -- t = wallClock - offset
```

The right mental model is **DVR on a livestream**, not a scrubber on a video file.

### Rules

- **Bounded to the season epoch.** Before a reset the cast, assets, and vocabulary are
  all different. Crossing that boundary is an archive browser — a separate, later
  product — not rewind.
- **Loud mode indicator, always-visible RETURN TO LIVE.** Rewind is the one feature that
  breaks the shared-moment promise, so leaving it must be obvious. A viewer who forgets
  they rewound concludes the world has stalled.
- **Needs an index.** Jumping requires knowing what is where. `seasons/s01/index.json`
  holds one row per aired scene: `t0`, location, cast, one-line summary. Generated
  incrementally by the same job that publishes chunks.
- **Assets must reload on jump.** A jump to an unvisited location needs its background
  and any rigs not currently resident. Show the scene from its start once loaded rather
  than dropping the viewer mid-beat into a blank stage.

The index is worth building even without rewind: it is also the "what you missed"
summary, the searchable transcript, and the only thing on the site a search engine can
usefully read.

---

## 14. Openness

The project is open from the start. Script, memory, bible, and assets are published as
they are written. **No encryption, no time-gating, no spoiler defence.**

This is a deliberate reversal of the obvious instinct, on three grounds:

1. Client-side encryption cannot work here anyway. The client must decrypt, so the
   client has the key, so a determined viewer reads the script. Any scheme is
   obfuscation with extra steps.
2. Time-gating *does* work, but it costs a release pipeline, a delivery-block layer
   below the chunk, and a lead time tuned around GitHub Actions' cron drift — real
   complexity, all of it in service of a secret that has little value.
3. Leaks are the engagement. A world that can be datamined is a world worth digging
   into. The interesting artifact here is not the animation, it is the machinery
   underneath it — and hiding the machinery hides the point.

The one thing genuinely lost is simultaneous reveal: someone can read ahead and post
"the mayor dies at 15:00". For an ambient, always-on world that is an acceptable trade.
For a world built around scheduled dramatic beats it would not be, and that is the
signal to revisit this decision — not before.

### Consequences

- No delivery blocks. The chunk is both the authoring unit and the delivery unit.
- No release job, no lead time, no private-source / public-mirror secrecy split.
- Publishing is `git push`. The data repo's contents *are* the content API.
- **The future-only revision rule from §9 stays.** It was never about secrecy — it stops
  a scene from mutating under a viewer who is mid-watch.

### The two repos

The split that remains is by concern, not by secrecy:

| | `asphodel-data` | `asphodel-engine` |
|---|---|---|
| Contains | one world: bible, memory, script, assets | renderer, compiler, agent, editor, `demo-world/` |
| Changes | daily, by agent | rarely, by humans |
| Deploys | Pages, static content API with CORS | Pages, the app shell |
| License | content licence, e.g. CC BY-SA | code licence, e.g. MIT |

**Coupling is at runtime, not build time.** The app fetches `manifest.json` and chunks
from the data repo's Pages origin. A submodule or package dependency would weld the two
deploy cadences together, and they should not be welded — the engine ships monthly, the
world ships daily.

This split is also what forces the engine to stay world-agnostic (§4.3), which is what
makes `demo-world/` possible, which is what lets anyone run or fork the machinery
without your world's data. The three properties hold each other up.

### Showing the bones

Since nothing is hidden, make that a feature rather than a footnote: an in-page inspect
panel over the running scene, showing the raw beat JSON, which arc this scene advances,
and the memory delta it emits — plus links to the same content in git.

The data is already loaded in the client, so this costs a panel and a keyboard shortcut.
It is plausibly the most compelling thing on the page.

---

## Appendix: open questions worth deciding before step 3

- **World time scale.** Does one real second equal one world second? A compressed clock
  (1 real day = 1 world week) gives arcs room to breathe but makes "same moment" harder
  to talk about. Recommend 1:1 for the first season.
- **Day/night.** Tying scene lighting to the viewer's local time is a strong effect but
  breaks the shared moment. Tying it to world time keeps the promise. Recommend world
  time.
- **Sound.** Deliberately out of scope now, but leave a `sfx` field slot in the beat
  schema so adding it later is not a migration.
- **Persistence across visits.** Does a returning viewer get "here's what you missed"?
  It is a nice hook and cheap — the script is text and the world log already exists.
