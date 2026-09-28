---
description: Sync every design doc against code via a resumable Workflow (one subagent per doc), then reconcile INDEX.md and surface obsolescence findings for plans/future/archive/sub-docs. Token-expensive: run occasionally.
argument-hint: "[--apply | --recommend-only] (default: apply content fixes in place, recommend structural changes)"
allowed-tools: Bash(find:*), Bash(ls:*), Bash(grep:*), Read, Edit, Write, Grep, Glob, Workflow
---

# Sync all design docs

Audit and update **every** doc under `designs/`. The heavy per-doc work runs as a
**resumable Workflow** (`sync-all-designs`) that fans out one subagent per doc; this command
does the parts a workflow can't (filesystem enumeration up front, INDEX.md + structural
reconciliation after).

Run **occasionally** (e.g. before an App Store release, or after a big feature lands): it spawns dozens
of subagents. If the run dies mid-way, you can resume it (see Step 3) and only the docs that
didn't finish re-run; the rest return cached.

Mode (from `$ARGUMENTS`):
- Default / `--apply`: subagents **edit their doc in place** for content drift, but only
  **recommend** structural changes (delete / move to `archive/` / promote to INDEX / rename).
- `--recommend-only`: subagents change nothing; all findings are reported for review first.

## Step 1: Enumerate and bucket (this command, before the workflow)

The workflow has no filesystem access, so build the doc list here:

1. `Read designs/INDEX.md`. Extract every doc it links via `→ Full doc: NAME.md` (and
   `[text](name.md)` links). This is the **INDEX-referenced** set (the discovery surface).
2. `Glob designs/**/*.md` for the full set; exclude `INDEX.md`.
3. Bucket each doc:
   - **referenced**: in INDEX.md.
   - **sub-doc**: not in INDEX but linked from another design doc (grep the other docs for
     its filename). Legitimate; synced like a referenced doc, plus a parent-link check.
   - **plans**: under `designs/plans/`.
   - **future**: under `designs/future/`.
   - **archive**: under `designs/archive/`.
   - **references**: under `designs/references/`. Operational reference data extracted from
     `.claude/skills/*/SKILL.md` (thresholds, incident background, data-model tables). These
     are deliberately **not** in INDEX.md: they're runbook support, not module architecture.
     Their "parent" is the skill that cites them, so check that citation still resolves rather
     than looking for a linking design doc.
   - **orphan**: not in INDEX, not linked anywhere, not under plans/future/archive/references.
     (Orphans should be rare; flag them loudly.)
4. `log`/print the bucket counts so the user sees the scope before the fan-out.

## Step 2: Run the resumable workflow

Invoke the `sync-all-designs` workflow, passing the bucketed list as `args`:

```
Workflow({
  name: 'sync-all-designs',
  args: { mode: 'apply' | 'recommend-only', docs: [ { path: 'designs/foo.md', bucket: 'referenced' }, ... ] }
})
```

`args.docs` is the list from Step 1. (The Workflow tool delivers `args` to the script as a
JSON string; the workflow parses it: pass a normal JSON object here.) The workflow spawns
one agent per doc (each edits ONLY its own file: no INDEX.md, no cross-doc edits: so
parallel writes can't collide) and returns `{ mode, total, reports, failed }`, where each
report has `{ doc, bucket, verdict, changed, indexAction, structural }`.

**Note the `runId` and the persisted `scriptPath`** from the tool result: needed to resume.

## Step 3: Resume if it died

If the workflow was killed / lost connection before finishing, relaunch with:

```
Workflow({ scriptPath: '<persisted path>', resumeFromRunId: '<runId>',
           args: { ...same args... } })
```

Docs that already completed return cached instantly; only `failed` / unfinished docs re-run.
Keep the same `args` so the cache matches.

## Step 4: Reconcile (this command, after the workflow)

Cross-cutting work the workflow deliberately left alone:

1. **INDEX.md**: collect every `indexAction` from the reports. In `apply` mode, edit INDEX.md
   to add missing referenced docs and fix/remove stale entries (entries pointing at docs that
   no longer exist, or whose description/`Key exports:` are now wrong). In `recommend-only`
   mode, list the proposed edits instead. Follow the INDEX.md Format in the `sync-designs`
   skill (`→ Full doc:` arrow notation is required for MCP discovery).
2. **Stale INDEX entries**: cross-check INDEX links against the Step-1 file list; flag any
   `→ Full doc:` pointing at a missing file.
3. Do NOT perform any delete / move / rename yourself.

## Step 5: Report

Summarize:
- bucket counts; how many docs were in-sync vs updated; any `failed` docs (and the resume
  command to retry them).
- INDEX.md changes made (or proposed, in recommend-only mode).
- a **structural action list**: every recommend-archive / recommend-delete /
  recommend-promote / orphan / wrongly-archived finding, grouped, each with its one-line
  justification: for the user to approve. Do not act on these without a go-ahead.

End with a one-line `result:` headline (e.g. `result: synced N design docs, M updated, K
structural changes proposed for review`).
