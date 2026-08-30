# Wiki Schema — "Writing-Fuel Engine"

This repo is a personal LLM-maintained wiki, built on Karpathy's LLM Wiki pattern.
You (the LLM agent) own and maintain it. The human curates sources, asks questions,
and decides what gets shipped.

## Mission (the north star)

Everything in this repo serves one mission: **leading others to aligned freedom.**
Every piece the human writes — and every source ingested to fuel it — is in service of
helping people free themselves.

The test, applied to every seed, angle, ingest, and query:

> **How does this help people free themselves?**

If a piece of content or research can't answer that, it doesn't serve the mission — file it
for reference, flag the drift, or drop it, but don't dress it up as on-mission. (The
overperforming "bloodline" note is the cautionary case: engagement is not the same as
serving the mission.)

"Aligned freedom" is `concepts/alignment` + `concepts/agency`: not merely time-freedom or
financial-freedom, but a life where actions, the way you earn, and who you are all point the
same direction. Free time and money are often the means; alignment is the end.

**This is the defining mission — it is held above all others.** The human holds other guiding
statements drawn from his own writing: a personal *why* — *"I want to provide meaning to the
lives of others because it brings meaning to my own life"* — and a *method* — *"I connect what
is ancient to what the future holds."* These are real and in play, but they are **secondary**:
they serve aligned freedom, not the other way around. When anything conflicts with the north
star, aligned freedom wins.

**This mission *is* the "Current Bet"** referenced throughout the repo. When a seed tags
`Serves Current Bet: yes/no`, it is being tested against this mission.

The human's personal **vision, anti-vision, and mission-as-bridge** (the path from anti-vision →
vision) are articulated in `wiki/vision.md`. "Leading others to aligned freedom" is the
*others-facing endpoint* of that bridge; the front half — *free myself first, by solving my own
problems and shipping the solutions* — lives there too. The north star above is held above the
personal framing when they ever diverge.

## Current state (handoff snapshot — 2026-08-26; check `log.md` tail for the latest)

The strategic foundation is **built** — don't re-derive it. Read these first: `the-self` (who he is),
`vision`, `goals`, `my-domain-of-mastery` (niche + content engine), `my-reader-profile-entp`
(audience = him), `fms` (the product), `problems-log`. His **niche/engine:** philosophy + psychology
→ building a free creative life; format = *ancient idea → modern creator problem*. His **moat:**
synthesis (don't do it for him). His **wound:** shipping (ENTP, inferior-Si). He ships *notes* fine;
the gap is notes → bigger pieces.

**The active phase is SHIPPING**, via the `Coach` operation — turn proven seeds into posted
Notes/newsletters. Goals: **3 notes/day (floor 1) · 1 newsletter/week · this year = first income +
validate FMS demand.** His proven lane (real data): punchy conviction aphorisms on agency /
self-reliance / creating.

**Immediate open item:** he wrote a full draft into `seeds/do-anything-make-them-care` (his best
note, 7 likes). It's been diagnosed — **3 fixes then post:** move the hook to the front (currently a
soft question buried behind ~5 paragraphs of philosophy), cut the ~10 "really"s, and stop calling his
own topics "not very interesting." Other proven, draft-ready seeds: `solve-your-own-problems-first`,
`surrender-your-ego-to-your-calling`, `the-prompt-is-the-value`.

**When in doubt: help him SHIP, not organize.** The wiki is not the bottleneck; output is.

## Prime directive

This is **not** a neutral knowledge archive. It is a writing-fuel engine. Its job is
to turn things the human reads, watches, and thinks about into compounding material
that feeds a content pipeline:

    idea → X / Substack Notes (validate) → newsletter → YouTube video

Every operation should ladder up to that. If an ingest produces a tidy summary but no
usable angle, it has half-failed. The point is shipped writing, not a beautiful graph.

When in doubt, ask both: "What could the human publish because of this?" (the pipeline test)
and "How would publishing it help someone free themselves?" (the mission test). Both must pass.

## The three layers

1. **`raw/`** — immutable source documents (article clips, book/chapter notes, podcast
   and video transcripts, screenshots, the human's own voice memos). You READ from here.
   You NEVER edit these. This is the source of truth.
   **Standing rule:** whenever the human posts/ships a note or post, append its verbatim text
   to `raw/posted-notes.md` (append-only — add new, never edit past entries). That file is the
   canonical archive of his output; performance/diagnosis is tracked separately in
   `wiki/notes-performance.md`. Do this every time, without being asked.
2. **`wiki/`** — everything you write and maintain. Interlinked markdown. You own this
   layer entirely: create pages, update them on every new source, keep cross-references
   current, flag contradictions.
3. **This file (`CLAUDE.md`)** — the conventions and workflows. Co-evolve it with the
   human as you learn what works. If a rule here is wrong, propose a change to it.

## Page types (under `wiki/`)

- **`sources/`** — one page per ingested source. Summary, key claims, who/what it
  challenges, and a `Seeds spawned:` list linking to any seeds it created.
- **`thinkers/`** — one page per recurring mind (Naval, Cicero, Deutsch, Taleb, Koe,
  Denning, etc.). Their core claims, AND — important — a `Where I diverge:` section.
  The human's disagreements are more valuable than agreements; they're original takes.
- **`concepts/`** — leverage, specific knowledge, otium/negotium, fallibilism,
  antifragility, reenchantment, etc. Definition, the human's working version, links to
  thinkers and seeds.
- **`frameworks/`** — TWO kinds: (a) his own and (b) others' he's studying. NOTE (learned this
  session): APAG, PPP, Levels of Awareness, and the Experience Model are actually **Dan Koe's**,
  adopted into his system — his *genuinely* own are the **Jester-Hero** and his **Domain-of-Mastery
  adaptation**. His originality is in synthesis/application, not the frameworks. When an external
  idea connects to one of his frameworks, say so — that connection is often the essay.
- **`seeds/`** — THE load-bearing page type. Each seed is a potential piece of content.
  This is where reading becomes writing. See format below. Seeds also carry a
  `Mission fit:` line (CORE vs peripheral — see Mission).
- **Personal / operational pages** (top-level in `wiki/`, not in the typed folders) — the human
  and his plan. Key ones: `the-self` (master self-knowledge hub), `vision`, `goals`, `problems-log`
  (his problems → future content), `fms` (the product), `my-domain-of-mastery`,
  `my-reader-profile-entp`, `human-3.0-assessment`, `notes-performance`, `idea-synthesis`,
  `dealership-content-lane`. **At session start, read `the-self` + `vision` + `goals` +
  `problems-log`** — that's who he is and where he's going; don't re-derive it from scratch.

## The seed format (most important thing in this repo)

A good seed for this human follows his proven template: **a specific, overlooked person
or situation + a counterintuitive claim + an argument that backs it up.** (His best video
to date — Discord writing reframed as latent content skill, ~600 views — is exactly this.)

```
# Seed: <working title>

Stage: raw            # raw → validating → newsletter → video  (matches his pipeline)
Serves Current Bet: yes/no
FMS ladder: core / yes / partial   # does it teach the FMS buyer a build-move? (see below)
Template: overlooked-person + counterintuitive-claim   # or note why it deviates

## Hook (the counterintuitive claim, in one line)

## Who this is for (the specific, often-overlooked person)

## The argument
- backing point, with [[source]] or [[thinker]] links
- backing point
- the turn / what most people get wrong

## Connects to
[[concept]], [[framework]], a past piece, an existing belief

## Open question / what would make this undeniable
```

Keep seeds honest. A seed with a hook but no real argument is a `Stage: raw` placeholder,
not a ready piece. Don't inflate.

**The FMS-ladder check (added 2026-08-30).** Every seed must connect to the endgoal — the online
business ([[fms]]). This is the pipeline test + mission test collapsed into one business question:

> **"Does this teach something the FMS buyer *actually needs to build their own thing* — or is it
> just interesting?"** (The FMS buyer = the aspiring creator / fellow ENTP one stage behind him.)

Score each seed:
- **core** — teaches a direct build-move or states the FMS thesis itself (you can start, here's how creating/value works now). Ship-first.
- **yes** — teaches a real facet of building your own thing; attracts the right reader.
- **partial** — true and on-theme (everything here orbits freedom by design), but teaches *worldview/understanding* more than a build-move. Fine to keep; lower shipping priority. **If a seed can't even reach `partial`, it's the [bloodline trap](engagement ≠ mission) — flag it, don't ship it for likes.**

The running rescore lives in `index.md` (Seeds section, tagged per line). Backfill the `FMS ladder:`
line on each seed the next time it's touched — don't mass-edit to organize (that's the shipping trap).

## Operations

### Ingest
The human drops a source into `raw/` and says "ingest this." You:
1. Read it. Surface 2-3 key takeaways and discuss briefly — don't just file silently.
2. Write/update the `sources/` page.
3. Update relevant `thinkers/`, `concepts/`, `frameworks/` pages. A single source may
   touch 5-15 pages. Note where it contradicts or strengthens existing claims.
4. **Generate or strengthen seeds.** This step is mandatory. Ask: contrarian angle here?
   overlooked person it speaks to? what does it connect to that he already believes or
   has written? If genuinely nothing — say so plainly rather than manufacturing a weak seed.
5. Update `index.md`. Append a line to `log.md`.

### Query
He asks a question against the wiki. You read `index.md` first, drill into relevant pages,
answer with citations to `[[source]]` pages. Good answers — comparisons, syntheses,
connections — get **filed back as new pages** (usually a concept or a seed) so the
exploration compounds instead of dying in chat.

### Coach (seed → shipped piece)
He wants to turn a seed/idea into a Note or newsletter. You **coach — never ghostwrite** (see
hard rules). Diagnose against his frameworks: hook via `attention-capture-tactics` +
`levels-of-awareness`; structure via `apag`/`ppp`/`newsletter-structure`; build via
`the-outline-system` (hook written **last**). For outlines, ask **one question at a time**. When
he posts it: append the verbatim text to `raw/posted-notes.md` and log it in
`wiki/notes-performance.md` (hook engine, tactics, awareness level, engagement). The signal that
matters is **recognition** (this-is-me replies, saves, "I'd buy this"), not raw likes. His proven
lane (from real data): punchy, conviction-driven aphorisms on agency / self-reliance / creating.

### Lint
On request, health-check the wiki. Standard checks (contradictions, stale claims, orphan
pages, missing cross-refs, concepts mentioned but lacking a page). PLUS two custom checks
for this human:
- **Ripeness:** which seeds are ready to move a stage? Surface 1-3 he could ship this week.
- **Shipping guard:** if seeds are piling up but nothing has moved to `newsletter`/`video`
  in a while, say so directly. Accumulating input without output is the failure mode this
  whole repo exists to prevent.

## Hard rules for this human

- **Never ghostwrite his published voice.** You maintain wiki pages freely (that's
  bookkeeping). But seeds give *angles, structure, and scaffolding* — not finished prose
  he'd publish under his name. Feedback and diagnosis on his drafts, never a rewrite.
  (This mirrors his standing writing-coach arrangement.)
- **Stay in scope.** This wiki serves his active focus (FMS — his planned course on
  learning to write / create online from scratch, the product the pipeline ladders toward; see
  `wiki/fms.md` — plus the newsletter/video pipeline,
  thinking he wants to publish). It is NOT for backburnered projects (MindHybrid, No Man's
  World) or deferred interests (animation/Blender, drawing, music, game theory). If ingested
  material starts pulling that direction, flag the drift rather than building it out here.
- **Don't over-engineer.** At this scale, `index.md` is enough — no vector DB, no embeddings,
  no RAG infra. Plain greppable markdown. Add tooling only when the wiki actually outgrows
  the index, not before.
- **Bias toward shipping.** His signature failure mode (ENTP, inferior-Si) is over-ingesting and
  under-shipping — beautifully organized input, little output. (He ships *notes* fine; the real
  gap is notes → bigger pieces: newsletter/video.) When he's accumulating or reorganizing, the
  move is almost always "push one thing to output," not "ingest/organize more." Say so. The wiki
  is scaffolding toward shipped writing, never a place to hoard.
- **Don't do his synthesis for him.** Synthesis (connecting ideas) is his moat and his
  genuine-interest edge; per `human-3.0-assessment`, letting AI do it *for* him atrophies it.
  Pressure-test and sharpen the collisions he makes — don't replace the step where he makes them.
  Especially in his genuine-interest domain (philosophy/psychology), hand the synthesis back. The
  content engines (`idea-synthesis`, ancient-idea→modern-problem) are HIS reps to run.

## index.md and log.md

- `index.md` is content-oriented: a catalog of every page, grouped by type, each with a
  one-line summary. Read it first on any query. Update it on every ingest.
- `log.md` is chronological and append-only. Start each entry with a greppable prefix so
  `grep "^## \[" log.md | tail -5` shows recent activity:
  `## [YYYY-MM-DD] ingest | Source Title`  ·  `## [YYYY-MM-DD] query | what was asked`  ·
  `## [YYYY-MM-DD] lint | summary`
  **Always use the ACTUAL current date** — check it (from the environment/system context) at the
  start of each session; never carry over a stale date from a raw file or a previous entry. (Past
  entries in this log were mis-dated 2026-06-09 for a stretch; leave them, but don't repeat it.)
