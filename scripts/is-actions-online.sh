#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Wait for GitHub Actions (or any githubstatus.com component) to come back.
#
# Reads the public githubstatus.com API, so it needs no GitHub token, no `gh`
# login, and no API quota. Nothing is written anywhere. Meant to be run detached
# so an agent or a shell can block on a real recovery signal instead of polling
# by hand.
#
# Exit codes: 0 every watched component is operational, 2 the wait timed out,
# 3 the status API could not be read enough times in a row to trust the result,
# 64 bad usage.

set -uo pipefail

API='https://www.githubstatus.com/api/v2/components.json'

# The status API includes a pseudo-component named
# "Visit www.githubstatus.com for more information" that is a promotional
# footer, not a real service. This jq select expression filters it out wherever
# components are enumerated, so it never shows in --list and cannot be waited on.
JQ_NON_PROMO='select(.name | test("^Visit ") | not)'

interval=120
timeout=0
once=0
quiet=0
components=()

die() { printf '%s\n' "$*" >&2; exit 64; }

usage() {
  cat <<'EOF'
Usage: is-actions-online.sh [options] [component ...]

Waits until every named githubstatus.com component reports "operational".
Component names are matched exactly as GitHub spells them, for example
"Actions", "Pages", "API Requests", "Git Operations". Defaults to "Actions".

Options:
  -i, --interval SECONDS  seconds between polls (default 120, minimum 15)
  -t, --timeout SECONDS   give up after this long; 0 waits forever (default 0)
  -1, --once              report the current status and exit, do not wait
  -q, --quiet             only print the final line
  -l, --list              print every component and its status, then exit
  -h, --help              this text

Exit codes: 0 operational, 2 timed out, 3 status API unreadable, 64 bad usage.

Examples:
  is-actions-online.sh                      # block until Actions recovers
  is-actions-online.sh --once               # just ask, right now
  is-actions-online.sh -i 60 Actions Pages  # wait on both, poll each minute
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -i|--interval) [ $# -ge 2 ] || die "--interval needs a value"; interval=$2; shift 2 ;;
    -t|--timeout)  [ $# -ge 2 ] || die "--timeout needs a value";  timeout=$2;  shift 2 ;;
    -1|--once)     once=1; shift ;;
    -q|--quiet)    quiet=1; shift ;;
    -l|--list)     list=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; break ;;
    -*)            die "unknown option: $1 (try --help)" ;;
    *)             components+=("$1"); shift ;;
  esac
done
components+=("$@")

case $interval in *[!0-9]*|'') die "--interval must be a whole number of seconds" ;; esac
case $timeout  in *[!0-9]*|'') die "--timeout must be a whole number of seconds" ;; esac
# The status page is cached and shared; polling it hard helps nobody.
[ "$interval" -lt 15 ] && interval=15

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required"

[ ${#components[@]} -eq 0 ] && components=("Actions")

say() { [ "$quiet" -eq 1 ] || printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }

fetch() { curl -fsS --max-time 20 "$API" 2>/dev/null; }

if [ "${list:-0}" -eq 1 ]; then
  body=$(fetch) || { printf 'could not read %s\n' "$API" >&2; exit 3; }
  printf '%s' "$body" \
    | jq -r '.components[] | '"$JQ_NON_PROMO"' | "\(.status)\t\(.name)"' \
    | sort
  exit 0
fi

# Confirm every name exists before waiting on it, so a typo fails now rather
# than blocking forever on a component that will never report.
body=$(fetch) || { printf 'could not read %s\n' "$API" >&2; exit 3; }
for name in "${components[@]}"; do
  printf '%s' "$body" \
    | jq -e --arg n "$name" 'any(.components[] | '"$JQ_NON_PROMO"'; .name == $n)' >/dev/null 2>&1 \
    || die "no such component: $name (try --list)"
done

# Prints "status<TAB>name" for each watched component, worst first.
statuses() {
  printf '%s' "$1" | jq -r --args '
    [.components[] | '"$JQ_NON_PROMO"' | select(.name as $n | $ARGS.positional | index($n))]
    | sort_by(.status == "operational")
    | .[] | "\(.status)\t\(.name)"
  ' "${components[@]}"
}

all_green() {
  printf '%s' "$1" | jq -e --args '
    [.components[] | '"$JQ_NON_PROMO"' | select(.name as $n | $ARGS.positional | index($n))]
    | length > 0 and all(.[]; .status == "operational")
  ' "${components[@]}" >/dev/null 2>&1
}

started=$(date +%s)
consecutive_failures=0
last_report=''

while :; do
  body=$(fetch)
  if [ -z "$body" ]; then
    consecutive_failures=$((consecutive_failures + 1))
    if [ "$consecutive_failures" -ge 5 ]; then
      printf 'gave up: %s unreadable %d times in a row\n' "$API" "$consecutive_failures" >&2
      exit 3
    fi
    say "could not reach the status API (${consecutive_failures}/5), retrying"
  else
    consecutive_failures=0
    if all_green "$body"; then
      printf '%s %s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "operational: ${components[*]}"
      exit 0
    fi
    report=$(statuses "$body" | tr '\t' ' ' | paste -sd '; ' -)
    # Only reprint when something actually moved, so a long wait stays readable.
    if [ "$report" != "$last_report" ]; then
      say "$report"
      last_report=$report
    fi
  fi

  [ "$once" -eq 1 ] && exit 2

  if [ "$timeout" -gt 0 ]; then
    elapsed=$(( $(date +%s) - started ))
    if [ "$elapsed" -ge "$timeout" ]; then
      printf 'timed out after %ds still waiting on: %s\n' "$timeout" "$last_report" >&2
      exit 2
    fi
    remaining=$(( timeout - elapsed ))
    [ "$remaining" -lt "$interval" ] && interval=$remaining
  fi

  sleep "$interval"
done
