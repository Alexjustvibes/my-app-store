# Writing-Fuel Wiki

A personal, LLM-maintained knowledge base built on Andrej Karpathy's
[LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f),
tuned for one job: **turning what I read into things I can publish.**

The agent reads my sources, maintains an interlinked wiki, and — the part that makes this
mine and not a generic second brain — spins up *seeds*: potential X Notes, newsletters, and
videos, following my proven format (overlooked person + counterintuitive claim + argument).

## How it works

- **`raw/`** — I drop sources here (clipped articles, book notes, transcripts). Never edited.
- **`wiki/`** — the agent owns this. Sources, thinkers, concepts, frameworks, and **seeds**.
- **`CLAUDE.md`** — the schema. The load-bearing file. Tells the agent how to behave.
- **`index.md`** — catalog of every page. The agent reads this first on any query.
- **`log.md`** — append-only timeline of ingests, queries, and lint passes.

## Daily use (with Claude Code or similar)

1. **Ingest:** drop a source in `raw/`, say *"ingest this."* The agent summarizes it,
   updates relevant pages, and proposes seeds.
2. **Query:** ask anything. *"What does Deutsch say about this that Taleb would reject?"*
   Good answers get filed back as pages.
3. **Lint:** weekly-ish, say *"lint the wiki."* It flags contradictions and stale pages —
   and tells me which seeds are ripe to ship, and whether I'm hoarding input without output.

## The rule that keeps it honest

The value is in *using* this, not building it. If a week of ingests produces zero seeds
that move toward `newsletter` or `video`, the wiki is failing at its only job. Input that
never becomes output is the exact pattern this repo exists to break.

It's just a git repo of markdown. Version history, Obsidian graph view, and portability
come free.
