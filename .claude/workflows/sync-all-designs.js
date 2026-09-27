export const meta = {
  name: 'sync-all-designs',
  description: 'Fan out one subagent per design doc to sync each against code and review unreferenced docs for obsolescence. Resumable.',
  whenToUse: 'Bulk design-doc sync. Run occasionally: token-heavy. Invoked by the /sync-all-designs command, which enumerates docs and passes them as args.',
  phases: [
    { title: 'Sync', detail: 'one agent per design doc: sync against code, bucket-specific obsolescence review' },
  ],
}

// args shape (built by the /sync-all-designs command, which has filesystem access):
//   { mode: 'apply' | 'recommend-only', docs: [ { path, bucket } ] }
// bucket ∈ referenced | sub-doc | plans | future | archive | orphan
//
// The workflow itself has NO filesystem access: enumeration and INDEX.md / structural
// reconciliation happen in the command (main thread), before and after this run.

// The Workflow tool delivers `args` to the script as a JSON STRING, not a parsed object -
// parse it (and tolerate it already being an object, for safety).
let INPUT = args
if (typeof INPUT === 'string') {
  try { INPUT = JSON.parse(INPUT) } catch (e) { INPUT = null }
}

const MODE = (INPUT && INPUT.mode) || 'apply'
const DOCS = (INPUT && INPUT.docs) || []

if (!DOCS.length) {
  log('No docs passed in args: nothing to sync. (The /sync-all-designs command builds the list.)')
  return { reports: [], mode: MODE, note: 'empty doc list' }
}

const REPORT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    doc: { type: 'string', description: 'the doc path, echoed back' },
    bucket: { type: 'string' },
    verdict: {
      type: 'string',
      enum: [
        'in-sync',
        'updated',
        'needs-content-fix',          // recommend-only: drift found, not applied
        'recommend-promote-to-index',
        'recommend-archive',
        'recommend-delete',
        'recommend-keep',
        'orphan',
        'wrongly-archived',
      ],
    },
    changed: { type: 'string', description: '1-3 line summary of edits made, or "none"' },
    indexAction: {
      type: 'string',
      description: 'INDEX.md action: "none", or "add: <desc>" / "fix-stale: <what>" with a suggested one-line description + Key exports line if adding',
    },
    structural: {
      type: 'string',
      description: 'structural recommendation (delete/move/promote/rename) + one-line justification, or "none"',
    },
  },
  required: ['doc', 'bucket', 'verdict', 'changed', 'indexAction', 'structural'],
}

function buildPrompt(doc) {
  return `You are syncing a SINGLE design doc: \`${doc.path}\` (bucket: \`${doc.bucket}\`, mode: \`${MODE}\`).

First read \`.claude/skills/sync-designs/SKILL.md\` (repo root) for the design-doc philosophy and Sync Workflow, then apply it to this ONE doc:

1. Read the doc. Identify the components / files / exports it describes.
2. Grep/Glob/Read the actual code to verify each claim (paths exist, exports still named that, behavior matches, "Key exports" accurate).
3. CONTENT DRIFT (doc describes code inaccurately): if mode is \`apply\`, fix it in place: keep the doc < 300 lines, Claude-to-Claude tone, no code dumps. If mode is \`recommend-only\`, describe the fix instead of making it.
4. BUCKET-SPECIFIC REVIEW:
   - referenced / sub-doc: as above. For sub-doc, also confirm the parent design doc still links it; if not, note it.
   - plans: has the plan been implemented? Fully built -> recommend folding durable parts into the relevant design doc and moving the plan to archive/. Partly built -> update status, note what's left. Abandoned -> recommend archive or delete.
   - future: still a relevant future direction? Been (partly) built -> recommend promoting to a real design doc + INDEX entry. Superseded / no longer intended -> recommend archive/delete. Otherwise confirm it's still a live idea.
   - archive: do NOT sync against code. Skim only to confirm it's still genuinely historical. If it actually describes CURRENT truth (wrongly archived), flag loudly (verdict wrongly-archived).
   - decision/review/known-issue snapshots (dated reviews, decision logs): do not rewrite history. Check whether findings are now resolved or still open; note resolved items; keep the record.
5. NEVER delete, move, or rename a file, and NEVER edit INDEX.md or any other doc. Those are structural actions handled by the orchestrator after user approval. Edit ONLY \`${doc.path}\`.

Return the structured report. The 'doc' field MUST be exactly \`${doc.path}\`. Choose the single best-fitting verdict. Put any INDEX.md need in 'indexAction' and any delete/move/promote/rename recommendation in 'structural' (both default to "none").`
}

log(`Syncing ${DOCS.length} design docs (mode: ${MODE}): one agent per doc.`)

const reports = await parallel(
  DOCS.map((doc) => () =>
    agent(buildPrompt(doc), {
      label: `sync:${doc.path.replace(/^designs\//, '').replace(/\.md$/, '')}`,
      phase: 'Sync',
      schema: REPORT_SCHEMA,
    }),
  ),
)

const ok = reports.filter(Boolean)
const failed = DOCS.filter((_, i) => !reports[i]).map((d) => d.path)
if (failed.length) {
  log(`${failed.length} doc(s) did not return (re-run with resumeFromRunId to retry just these): ${failed.join(', ')}`)
}

return { mode: MODE, total: DOCS.length, reports: ok, failed }
