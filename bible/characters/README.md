# Cast

One file per character. The writer agent reads the `active` files every chunk, plus
whichever `recurring` ones a scene needs.

## Roster — Season 1

| id | who | status | function |
|---|---|---|---|
| `ch.holmes` | Sherlock Holmes | active | the detective; the only one who cannot cheat |
| `ch.hermes` | Hermes | active | chronicler — the world log is his account |
| `ch.hades` | Hades | active | the client; tired middle management of the cosmos |
| `ch.persephone` | Persephone | active (seasonal) | the only one who keeps up; the world's calendar |
| `ch.minos` | Minos | active | judge of the dead; the official channel |
| `ch.charon` | Charon | active | ferryman; every witness passes through him |
| `ch.sisyphus` | Sisyphus | recurring | the permanent, unreliable witness |
| `ch.cerberus` | Cerberus | recurring, mute | the gate; physical comedy |
| `ch.mycroft` | Mycroft Holmes | dormant — letters only | the single channel to the living |
| `ch.watson` | Dr Watson | dormant | the absence the season is built on |
| `ch.hudson` | Mrs Hudson | dormant | the specificity of the life he lost |
| `ch.moriarty` | Professor Moriarty | dormant | the season arc |

Six active memory files, five speaking parts per scene maximum, three is better
(`vocabulary.json` → `constraints`).

## Status values

**`active`** — has live memory files under `memory/characters/<id>/`, is in the writer's
prompt every chunk, may be cast freely.

**`recurring`** — no live memory files. May appear in scenes without being in the prompt's
cast list. Their file is the whole of what the writer knows about them, so it does not
drift.

**`dormant`** — may not be introduced by the agent under any circumstances. A human moves
the file to `active`. Each dormant file states exactly what the agent *may* do with the
character in the meantime, which is usually "leave traces" or "nothing".

## File schema

```
---
id, name, status, role, source, accent
---

## Silhouette        how the rig reads in frame — shape first, detail never
## Voice             rhythm and register, not vocabulary lists
## Core traits       behavioural rules, each one usable as a scene decision
## Wants / Refuses   the engine; refusals generate more plot than wants do
## Relationships     directional — what A thinks of B, not "they are friends"
## Canon anchors     what stays true no matter how far the season drifts
## Drift allowance   what may change, and the explicit floor it may not cross
## Verbal tics       at most three, or they become catchphrases
```

`Canon anchors` and `Drift allowance` are not decoration — they are the clamp for the
personality-drift mechanism in ARCHITECTURE.md §5. The writer agent may propose changes to
a character's `core.json` only within the drift allowance, only with a cited event id, and
only in small per-week increments. Anchors are never proposable.

## Adding a character

1. Write the file. Every section, including the ones that feel obvious.
2. Decide the status honestly. Most new characters should start `recurring`.
3. If `active`, create `memory/characters/<id>/` with `core.json`, `episodic.jsonl`,
   `compacted.md`, `beliefs.json`.
4. If the character needs a pose or verb the vocabulary lacks, add it to
   `vocabulary.json` — which is a rig art task first and a JSON edit second.
