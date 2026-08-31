# Experiment event and summary interface

The Godot DigComp build exposes an anonymous event stream through the
`ExperimentSession` autoload. The browser bridge persists consented events and
recording chunks to IndexedDB, then uploads them after the full task suite.

## Event envelope (schema v2)

The append-only JSONL event envelope remains compatible with the previous study:

- `schema_version`: `2`
- `session_id`: locally generated anonymous run identifier
- `condition`: `unassigned`, `active`, or `passive`
- `event_name`, `level_id`, `elapsed_msec`, `payload`

Core events include the original level/run/quiz events plus DigComp hub and task
events for selection, progress, result recording and four-task completion.
Scaffolding events include `scaffold_eligible`, `scaffold_triggered`,
`scaffold_invitation_shown`, `scaffold_accepted`, `scaffold_rejected`,
`scaffold_dismissed`, `choice_before_scaffold`, `choice_after_scaffold`,
`support_started`, `support_ended`, and `level_time_summary`.

`active` can invite on idle, no progress, quiz error, repeated failure, or repeated
ineffective strategy. `passive` calls the same server profile only after the
participant opens the assistant manually. AI state is a per-level numeric
allowlist; client `instruction`, correct answers, puzzle coordinates, matching
solutions and raw current choices are discarded by the server.

## DigComp summary (schema v3)

`summary.json` uses schema v3 and includes:

- deployment/study/build metadata and anonymous signed-ticket fields
- results for all four top-level DigComp tasks
- the five-domain DigComp profile
- AI invitation, acceptance and interaction counts
- recording codec, size, duration/status and degradation reason
- event count and timing summaries

The JSONL event schema remains v2 so existing analysis can continue reading the
stream while v3-aware analysis consumes the richer DigComp summary.

## Persistence and completion

The bridge records only the Godot Canvas at about 1.5 Mbps and 30 FPS. Recording
chunks are periodically stored in IndexedDB alongside events and the pending
session. Refresh/retry may resume the pending upload. The bridge creates JSONL,
summary and recording/status objects, retries through the fallback API, and waits
for the server-authored `manifest.json`. It deletes local events and recording
chunks and shows final success only after that manifest is confirmed.
