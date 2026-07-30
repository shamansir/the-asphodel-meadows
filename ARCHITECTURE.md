# the ooo land — architecture

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

### Naming caution

"The Land of Ooo" is Adventure Time. Keep the repo name if you like it, but the in-world
proper nouns, character silhouettes, and title card should not read as a fan project.
Treat `bible/world.md` as the place to establish distinct identity early — it is much
cheaper to do before assets exist.

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

### `ooo-data` — this world

```
/
  README.md                     AI-disclosure text, how to read the raw script
  bible/
    world.md                    setting, rules, tone, what cannot happen
    style.md                    art direction, palette, line weight, bubble rules
    vocabulary.json             world verbs + their mapping to engine primitives
    characters/
      ch.oo.md                  character sheet: voice, silhouette, verbal tics
  memory/
    world/
      log.jsonl                 append-only, every event, never deleted, never compacted
      digest.md                 tiered summary for prompt use
      arcs.json                 open arcs with deadlines
    characters/
      ch.oo/
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
    rigs/ch.oo/{atlas.png, rig.json}
    locations/loc.market/{bg.webp, layers.json}
    fonts/{comic.woff2, metrics.json}
  .github/workflows/
    write.yml                   cron: generate + validate + commit + publish
    compact.yml                 weekly: memory compaction
    pages.yml                   publish seasons/ + assets/ to Pages with CORS
```

Published to Pages as a plain static content API. No build step — the repo contents
*are* the site.

### `ooo-engine` — the machinery

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
  "chunk": "0142",
  "t0": 1209600,
  "rev": 1,
  "scenes": [
    {
      "id": "s0142-001",
      "t0": 0,
      "dur": 96,
      "loc": "loc.market",
      "camera": { "shot": "wide", "move": "push", "to": [0.4, 0.55], "dur": 96 },
      "cast": [
        { "id": "ch.oo",  "at": [0.22, 0.7], "facing": "right" },
        { "id": "ch.zib", "at": [0.61, 0.7], "facing": "left"  }
      ],
      "beats": [
        { "t": 0,  "who": "ch.oo",  "act": "walk", "to": [0.45, 0.7], "dur": 4.0 },
        { "t": 4,  "who": "ch.oo",  "expr": "confused",
          "say": { "kind": "normal", "lines": ["WHERE IS", "MY HAT?"], "w": 118, "h": 62 },
          "dur": 2.8 },
        { "t": 7,  "who": "ch.zib", "pose": "shrug", "expr": "smug",
          "say": { "kind": "normal", "lines": ["WIND TOOK IT.", "TUESDAY PROBLEM."], "w": 164, "h": 62 },
          "dur": 3.2 }
      ],
      "emits": [
        { "id": "evt.hat_lost", "weight": 0.6,
          "text": "Oo lost the hat; Zib blamed the wind and did not help.",
          "witnesses": ["ch.oo", "ch.zib"] }
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

### 4.3 Vocabulary (closed set)

`bible/vocabulary.json` is the single source of truth, and it is a hard constraint on
the agent, checked by the compiler.

```json
{
  "acts":    ["walk","run","enter","exit","sit","stand","turn","pickUp","drop",
              "give","take","point","reach","push","fall","jump","wave"],
  "poses":   ["idle","shrug","armsCrossed","handsUp","slump","lean","crouch","hide"],
  "expr":    ["neutral","happy","sad","angry","shocked","smug","confused","crying",
              "laughing","tired"],
  "bubbles": ["normal","shout","whisper","thought","narration","offscreen"],
  "camera":  { "shot": ["wide","mid","close"], "move": ["hold","pan","push","pull","cut"] }
}
```

This is the whole trick for visual consistency. The agent is a *choreographer over a
finite alphabet*, not an illustrator. Adding a new pose is a human art task plus a
one-line vocabulary edit — and a vocabulary edit bumps `vocabularyHash`, which forces
clients to reload assets.

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
vocabulary.json                   ~0.4k
open arcs                         ~0.5k
per cast member: core + compacted ~1.5k each   (cast of 4–6 -> ~9k)
recent world digest               ~2k
episodic for cast, 14 days        ~8k
--------------------------------------------
target ceiling                    ~25k, hard cap 40k
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
| Cast bloat | Every scene a crowd | Cap active cast at 6; validator warns |
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
2. **Bible + vocabulary.** Write the world, then freeze the enums. The enums are the
   contract between art, agent, and renderer — freezing them early is what lets the
   other three tracks proceed in parallel.
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
