---
name: is-actions-online
description: Check or wait for GitHub Actions to come back from an outage, using the public githubstatus.com API with no token and no API quota. Use when CI checks fail in job setup with "Failed to resolve action download info", "The job was not acquired by Runner", or "Service Unavailable"; when runs queue and never start; when pushes stop triggering workflow runs; or before rerunning a red check, so a platform outage is not mistaken for a repo problem.
---

# Is Actions online

## When a red check is not your fault

GitHub Actions outages do not announce themselves. They surface as failures that
read like repository bugs, and no code change fixes any of them:

- `Failed to resolve action download info. Error: Service Unavailable`
- `The job was not acquired by Runner of type hosted even after multiple attempts`
- Jobs sit queued and are then cancelled with no runner assigned and no steps
  run. Look for an empty runner name and an empty step list on the job.
- Every job in a run fails at the same offset from when it was queued, commonly
  15 minutes, and the same thing happens on unrelated branches.
- Pushes and pull requests stop launching runs at all. GitHub throttles webhook
  delivery during an incident, so a missing run is itself a symptom.

Two tells separate an outage from a repository problem. An outage hits **every**
workflow, including ones your change did not touch and scheduled runs on the
default branch. And it hits **other repositories** at the same time. Check a
second repository before you start bisecting.

Rerunning a red check during an outage costs minutes and proves nothing. Confirm
the platform first.

## Ask

```bash
scripts/is-actions-online.sh --once          # exit 0 operational, 2 degraded
scripts/is-actions-online.sh --list          # every component and its status
```

## Wait

Blocks until Actions reports operational, then exits 0:

```bash
scripts/is-actions-online.sh --interval 300
```

Run it detached rather than polling in a loop yourself. An agent that backgrounds
the call spends nothing while it blocks and is woken when it exits, which is the
whole point of the script. A plain shell can background it the usual way and
`wait` on it, or chain the next command with `&&`.

Other components, and a bounded wait:

```bash
scripts/is-actions-online.sh Actions Pages   # both must be green
scripts/is-actions-online.sh -t 3600         # give up after an hour
```

Names are matched as GitHub spells them (`Actions`, `Pages`, `API Requests`,
`Git Operations`, `Webhooks`, `Issues`, `Pull Requests`, `Packages`,
`Codespaces`, `Copilot`). A name that does not exist fails immediately rather
than blocking forever on a component that will never report, so check `--list`
if you are unsure.

Exit codes: `0` operational, `2` timed out or still degraded under `--once`,
`3` the status API could not be read five times in a row, `64` bad usage.

## While you wait

An outage blocks merging, not working.

- **Reviews still happen.** Review bots generally run outside Actions and keep
  reviewing pushes. Push your fixes and collect the review now, so the queue is
  ready to drain instead of only starting to be reviewed once CI returns.
- **Local checks still gate.** Run the same lint, format and test commands CI
  runs. A change that fails locally will not pass later.
- **Everything except runs.** Pushes, issues, pull requests and the API stay up
  in most Actions incidents. Confirm with `--list` rather than assuming.

Do not arm auto-merge to fire when CI returns unless the pull request is
genuinely finished. A queued auto-merge lands the moment checks pass, which can
be before a review you were waiting on arrives.

## Requirements

`curl` and `jq`. No GitHub token, no `gh` login, no authentication of any kind:
`https://www.githubstatus.com/api/v2/components.json` is public. Nothing is
written to disk. The minimum poll interval is clamped to 15 seconds because the
status page is a shared cache.
