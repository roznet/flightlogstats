---
name: sync-designs
description: Create or sync design docs under designs/ against the code, and keep designs/INDEX.md accurate. Use after a feature lands, when a doc may have drifted, or when starting a doc for a new module. For a bulk pass over every doc, use the /sync-all-designs command, which runs this skill once per doc.
---

# Sync design docs

Design docs exist so a future session (human or Claude) learns a module's
architecture, key types and non-obvious decisions **faster than by grepping**.
They are written Claude-to-Claude: dense, factual, pointing at code rather than
restating it. A doc that disagrees with the code is worse than no doc, because
it is believed.

## Layout

```
designs/
  INDEX.md        one entry per module; the discovery surface (read it first)
  <module>.md     as-built design of a module; the source of truth for intent
  plans/          accepted work not yet (fully) built; has a Status line
  future/         proposals and brainstorms; nothing decided until promoted
  archive/        historical plans kept for the "why"; never synced to code
  references/     runbook data cited by .claude skills; not in INDEX
```

A doc moves `future/ → plans/ → <module>.md (+ INDEX entry) → archive/` for the
plan it came from. Moving, renaming and deleting are **structural** actions:
recommend them, and only do them with the user's go-ahead.

## Doc philosophy

- **Under ~300 lines.** Split a growing doc into a parent plus sub-docs, and
  link sub-docs from the parent.
- **Intent first.** Open with a one-line `>` summary, then what the module is
  for and what it must never become.
- **Decisions with reasons.** A `Decision | Choice | Why` table beats prose. Keep
  the rejected alternative when it is likely to be re-proposed.
- **Key exports** table: file → types/functions. These are the names a reader
  greps for next.
- **Gotchas** section for anything learned the hard way (a silent failure, a
  unit trap, a Core Data or iCloud quirk). This is usually the most valuable part.
- **Point at code, do not paste it.** `File.swift:123` links, short signatures,
  at most a few lines of pseudo-code. No full listings.
- **Present tense for what is built, explicit status for what is not.** Mark
  planned parts `(planned)` or keep them in `plans/`/`future/`.
- **Dated snapshots stay dated.** A review or decision log records what was true
  then. Mark resolved items; do not rewrite history.
- No long dashes in prose; use commas, colons or parentheses.

## INDEX.md format

Each module entry, grouped under `##` area headings (presentational only):

```
### <module-name> [optional tag, e.g. planned]
One to three lines: what it does and the decisions a reader must know.
Key exports: `TypeA`, `TypeB`, `function(_:)`
→ Full doc: <module>.md
```

The `→ Full doc:` arrow line is **required**: tooling and the bulk sync discover
docs through it. `plans/`, `future/` and `archive/` docs are not INDEX entries;
they are linked from the relevant module doc or from the INDEX "Plans" section.

## Sync workflow (one doc)

1. **Read the doc** and list every concrete claim: file paths, type and function
   names, behaviours, numbers, the Key exports line in INDEX.md.
2. **Verify against code.** Glob/Grep/Read each claim. In this repo the app is
   `flightlogstats/Source/*.swift` (flat folder), tests are
   `flightlogstatsTests/`, the Core Data model is
   `flightlogstats/Source/FlightLogModel.xcdatamodeld`, Python tooling is
   `python/`, and shared libraries come from SPM (`rzflight`, `rzutils`), so a
   missing type may live in a package: check `project.pbxproj` and the package
   before calling it gone.
3. **Fix drift in place**: renamed types, moved files, changed behaviour, stale
   line numbers (prefer linking a symbol over a line when lines churn). Keep the
   doc's voice and structure; do not grow it past ~300 lines.
4. **Bucket-specific checks**
   - module doc: Key exports accurate; parent links for sub-docs still resolve.
   - `plans/`: implemented? Fold the durable parts into the module doc and
     recommend archiving. Partly built: update the Status line with what is left.
   - `future/`: still intended? Built: recommend promotion. Superseded:
     recommend archive.
   - `archive/`: do not sync. Flag loudly if it actually describes current truth.
   - `references/`: confirm the skill that cites it still does.
5. **Update INDEX.md** if the description or Key exports changed, or add an
   entry for a new module doc. (The bulk workflow's per-doc agents must NOT edit
   INDEX.md; the orchestrating command does it once at the end.)
6. **Report**: in-sync / updated (what changed) / structural recommendation.

## Creating a new module doc

Read the code first, then write: summary line, intent, decisions table, key
exports table, data flow (a small ASCII diagram is fine), gotchas, and links to
related docs. Add the INDEX entry in the same change.

## When to run

- After a feature that touched a module with a doc: sync that doc in the same PR.
- Before starting work guided by a doc you suspect is stale.
- Occasionally, the whole set via `/sync-all-designs` (token-heavy).
