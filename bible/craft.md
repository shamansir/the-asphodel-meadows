# Craft

How to write a chunk that is worth watching. `world.md` says what is true; this says what
makes it good.

Written to be dropped into the writer prompt whole — it is rules and checklists, not
essay. Budget ~1.8k tokens. If it grows past that, cut from the bottom: the last sections
are the least load-bearing.

---

## 1. What we are actually making

Two shows braided together:

- **Episodic** — a case, self-contained, resolved. This is what a viewer who arrives today
  gets. It must satisfy on its own.
- **Serial** — the season arc, advancing a few centimetres per case, never resolving.

A chunk that only does the first is filler. A chunk that only does the second is homework.
Every chunk does both, and the serial part is almost always *background*: a detail, a
refusal, a name.

---

## 2. The unit of writing is the scene, and every scene turns

A scene where nothing changes is not a scene, it is an establishing shot with dialogue.

Each scene must have a **turn**: something is true at the start and a different thing is
true at the end. Usually one of —

- new information changes what the problem is
- someone's position on someone else moves
- an attempt fails and closes off a route
- a lie is told, or stops working

Write the turn first, then the dialogue that gets there. If you cannot name the turn in one
clause, delete the scene.

**Enter late, leave early.** Start after the greeting, end before the goodbye. The audience
is smart and the clock is running.

---

## 3. The case shape

The seven beats are in `world.md`. This is the engine that drives them:

**Try / fail, three times.** Holmes does not proceed from confusion to solution in a
straight line. He proceeds by being wrong in increasingly interesting ways.

- attempt 1 fails because a **fact** is missing
- attempt 2 fails because an **assumption** is wrong ← this is the wrong idea, and it is
  the best scene in the case
- attempt 3 works because the reversal reframes what was already on screen

Distinguish an **obstacle** (a locked door — boring, solved by effort) from a
**complication** (the door is open and that is worse — interesting, changes the problem).
Prefer complications. This world has almost no locked doors; it has forms.

**The wrong idea must be excellent.** As well-constructed as the right one, and demolished
by evidence rather than by someone being cleverer. If the audience did not briefly believe
it, it has not done its job — and Holmes being wrong is what keeps him a person rather than
an oracle.

---

## 4. Fair play — the hard rules

Adapted from Knox (1929) and Van Dine (1928), which exist precisely because a detective
story is a game the audience must be able to win.

1. **Every clue used in the solution is on screen before the solution**, with an `insert`
   shot. Non-negotiable; the compiler checks it.
2. **The culprit appears in the first third** of the case and is not a stranger.
3. **No supernatural solutions.** In a world of literal gods this rule does more work than
   usual: divinity may cause a case and may never solve one.
4. **No new science, no undiscovered poison, no unheard-of custom.** The audience must be
   able to know what Holmes knows. Where a real historical detail is used — the rite of the
   mouth, the hundred years — say it in dialogue before it is load-bearing.
5. **No accident, no unmotivated confession.** The solution must be arrived at.
6. **The narrator may mislead but may not lie.** Hermes omits, embellishes, gets the order
   wrong, and tells you the ending first. He never states a falsehood as fact. This is the
   line that keeps him funny instead of cheap.
7. **No twin, no secret passage, no unknown sibling.** One coincidence per case, at the
   start, never at the end.

A solution the audience could not have reached is not a twist, it is a withheld fact.

---

## 5. Character

**Want vs. need.** What they are chasing this chunk vs. what they actually lack. Comedy
comes from the gap; the character never names the need.

- Holmes *wants* the case. He *needs* to know Watson is all right.
- Hermes *wants* to be the one who noticed first. He *needs* to be forgiven for not being
  Watson.
- Minos *wants* the docket clear. He *needs* one person to say he has done this well.

**The flaw generates the plot.** Do not write a problem and then assign someone to it —
find the character whose specific defect makes this problem worse, and put them in it.

**Refusals beat wants.** Every character file has a `Refuses` section, and it is the more
useful one. A character who will not do a thing is a wall the plot can push against; a
character who wants a thing just walks toward it.

**Cast discipline.** Five speaking parts maximum, three is better. Two-handers are the
strongest scenes in this show. A scene with everyone in it should happen once per case, at
the accusation.

---

## 6. Dialogue

**Characters speak to get something**, not to inform the audience. If a line exists to
explain, give the information to someone who resents having to say it.

**Subtext.** The most important thing in a scene is usually not said. Charon's *"I would
have said no"* is about being spared a decision, and says none of that.

**Nobody agrees immediately.** Friction on every exchange, even between allies. Especially
between allies.

**Voice test:** cover the names. If you cannot tell who is speaking, the scene is not
written yet. Each character's file has three verbal tics — three, not more, or they become
catchphrases.

**Bubble discipline:** three lines maximum, and short lines. This is a comic, not a novel.
A long speech is three bubbles with reactions between them — and the reactions are where
the scene actually happens.

---

## 7. Comedy

**Nobody knows they are in a comedy.** Every character is entirely serious about their own
concerns. That is the whole engine. The moment someone winks, the case stops mattering and
so do the jokes.

**Play the smallest thing with the largest gravity.** A stolen sandwich investigated with
the full apparatus of deduction. Never the reverse — a large thing played lightly reads as
the show not caring.

**Escalate in threes**, then break the pattern on the fourth.

**Callbacks are the memory system doing comedy.** A detail from three cases ago, returning
without explanation, is the funniest thing this format can do and it is nearly free.

**Never joke about the crossover.** No character finds a Victorian detective among Greek
gods unusual.

---

## 8. Serial craft

**Keep a promise ledger.** Every question raised is a debt. Track it in `arcs.json`:
what was promised, in which chunk, and when it must pay.

- pay small debts within one case
- pay medium debts within three
- the season debt pays at the finale, once

**Plant early, pay late, and let the audience be ahead.** Dramatic irony is stronger than
surprise in a format people dip into. The pleasure of the Sigerson beat is not that the
audience is confused — it is that they will work it out before Holmes does.

**One serial trace per chunk, maximum, in the background.** A serial thread that pushes
into the foreground stops being a thread and becomes the case.

**Write for the memory system.** A scene that emits nothing did not happen. Every scene
carries `emits` with an honest `weight` — that number decides what a character still knows
in three months, and inflating it is how the world ends up remembering everything, which
is the same as remembering nothing.

---

## 9. Writing for an always-on medium

Nothing in the craft books covers this. These constraints are specific to us and they
override anything above that conflicts.

**The viewer arrives mid-scene.** Not at the start. Mid-sentence, mid-gesture, mid-case.
So:

- **Every scene must be legible from its middle.** Within ~20 seconds of joining anywhere,
  a viewer should know who these people are to each other and what is at stake in this
  room. Re-state the question periodically — differently each time, never verbatim.
- **Stakes must be physical and present.** "The box is one coin over" is visible and
  re-statable. "The treaty expires next month" is not.
- **Position encodes relationship.** Who stands near whom, who is turned away, who is
  higher in frame. It reads instantly and it costs nothing.
- **No slow burns that require commitment.** Tension must be legible at every instant, not
  accumulated over ten minutes the viewer did not watch.

**Hermes's narration is the "previously on".** Use it at scene openings to catch people up
in-character. This is what he is for, structurally.

**Ninety seconds should be a complete small satisfaction.** A viewer who watches one scene
and leaves should have got a joke, a turn, and one piece of information.

**Reward re-watching with detail, not plot.** The same scene will be seen again by someone
who paused, rewound, or came back tomorrow. Put the rewards in behaviour and background —
never make a plot point depend on catching something once.

**No audio.** Silence is not available as a tool. **Stillness is** — everyone else moving
while one character holds perfectly still is the strongest beat this format has, and it is
worth spending sparingly.

---

## 10. On the hero's journey

It does not fit, and forcing it will hurt the show. The monomyth describes one character
transformed by one long arc. We are writing episodic mystery with a serial undertow, where
the lead is deliberately *resistant* to change — Holmes at the end of a case is Holmes at
the start of it, which is the genre's entire pleasure.

Take two things from it and leave the rest:

- **The refusal of the call.** Holmes turning down a case, then being pulled in by someone
  being confidently wrong, is a reliable opening.
- **The return with the elixir.** He comes back from each case having learned something
  about this world he did not want to know. That is the season arc, accumulating.

The change belongs to the *world* and the *supporting cast*, not the detective. Hermes is
the one on a journey. Watch him.

---

## 11. Failure smells

If a draft has any of these, it is not ready:

- a scene whose turn cannot be named in one clause
- Holmes right the first time
- a solution using something not previously on screen
- a god solving it
- anyone remarking on the crossover
- more than five speakers, or a five-hander that is not the accusation
- dialogue that explains rather than wants
- a bubble over three lines
- `emits` missing, or every weight above 0.7
- a case that could be set anywhere — if it does not need *this* world, it is not this
  show's case
- a joke that requires a character to know they are funny

---

## Sources

Knox's Decalogue (1929) and Van Dine's Twenty Rules (1928) are the origin of the fair-play
rules in §4; both are adapted here rather than quoted.

- [The "Rules" of Detective Fiction — Agatha Christie Wiki](https://agathachristie.fandom.com/wiki/The_%E2%80%9CRules%E2%80%9D_of_Detective_Fiction)
- [Twenty Rules for Writing Detective Stories — Van Dine](https://www.goodreads.com/author_blog_posts/3290942-twenty-rules-for-writing-detective-stories)
- [The Knox Decalogue: Legacy — The Invisible Event](https://theinvisibleevent.com/2021/07/27/the-knox-decalogue-legacy/)
