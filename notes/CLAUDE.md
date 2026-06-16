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
- **`frameworks/`** — TWO kinds: (a) the human's own — APAG, PPP, Levels of Awareness,
  the Outline System, Idea Compiling, the Experience Model; (b) others' he's studying.
  When an external idea connects to one of his frameworks, say so explicitly. That
  connection is often the essay.
- **`seeds/`** — THE load-bearing page type. Each seed is a potential piece of content.
  This is where reading becomes writing. See format below.

## The seed format (most important thing in this repo)

A good seed for this human follows his proven template: **a specific, overlooked person
or situation + a counterintuitive claim + an argument that backs it up.** (His best video
to date — Discord writing reframed as latent content skill, ~600 views — is exactly this.)

```
# Seed: <working title>

Stage: raw            # raw → validating → newsletter → video  (matches his pipeline)
Serves Current Bet: yes/no
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
- **Stay in scope.** This wiki serves his active focus (FMS, the newsletter/video pipeline,
  thinking he wants to publish). It is NOT for backburnered projects (MindHybrid, No Man's
  World) or deferred interests (animation/Blender, drawing, music, game theory). If ingested
  material starts pulling that direction, flag the drift rather than building it out here.
- **Don't over-engineer.** At this scale, `index.md` is enough — no vector DB, no embeddings,
  no RAG infra. Plain greppable markdown. Add tooling only when the wiki actually outgrows
  the index, not before.

## index.md and log.md

- `index.md` is content-oriented: a catalog of every page, grouped by type, each with a
  one-line summary. Read it first on any query. Update it on every ingest.
- `log.md` is chronological and append-only. Start each entry with a greppable prefix so
  `grep "^## \[" log.md | tail -5` shows recent activity:
  `## [YYYY-MM-DD] ingest | Source Title`  ·  `## [YYYY-MM-DD] query | what was asked`  ·
  `## [YYYY-MM-DD] lint | summary`
