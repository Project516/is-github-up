# is-github-up

Check or wait for GitHub services to come back from an outage, without spending a
token or an API call.

A GitHub outage does not announce itself in the failure text. Checks fail in job
setup with `Failed to resolve action download info. Error: Service Unavailable`,
or the API returns 503 with `No server is currently available to service your
request`. Both read like a repository problem, and rerunning them tells you
nothing. This asks the status page instead.

## Use

```bash
scripts/github-status.sh --once          # exit 0 operational, 2 degraded
scripts/github-status.sh --list          # every component and its status
scripts/github-status.sh --json --once   # JSON output for scripts
scripts/github-status.sh --interval 300  # block until everything recovers
scripts/github-status.sh Actions Pages   # wait on more than one
scripts/github-status.sh -t 3600         # give up after an hour
```

Exit codes: `0` operational, `2` timed out or still degraded under `--once`,
`3` the status API could not be read five times in a row, `64` bad usage.

Run the waiting form detached, so nothing is spent while it blocks:

```bash
scripts/github-status.sh --interval 300 &
```

## As an agent skill
`SKILL.md` is written for coding agents. It carries the outage signatures worth
recognizing, how to tell a platform outage from a repository bug, and what is
still worth doing while GitHub is down. Point your agent's skill directory at
this repo, or copy `SKILL.md` and `scripts/` into it.

It is agent-harness agnostic: nothing in it assumes a particular language,
toolchain, CI configuration or vendor.

## Backwards compatibility
`scripts/is-actions-online.sh` is a symlink to `github-status.sh` for backwards
compatibility. Existing workflows and skills that reference the old name keep
working.

## Requirements
`curl` and `jq`. No GitHub token and no `gh` login:
[`githubstatus.com/api/v2/components.json`](https://www.githubstatus.com/api/v2/components.json)
is public. Nothing is written to disk. The poll interval is clamped to a 15
second minimum, since the status page is a shared cache.

## License
AGPL-3.0-or-later. See [LICENSE](LICENSE).
