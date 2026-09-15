#!/usr/bin/env bash

# Run one command under a deadline and record how it ended. Issue #329 is work
# that never returns, so a killed command is the result this script looks for,
# not an error that should fail the job.

set -uo pipefail

label="$1"
deadline="$2"
shift 2

start=$SECONDS
timeout --signal=KILL "$deadline" "$@"
code=$?
elapsed=$((SECONDS - start))

case "$code" in
    0) verdict="finished in ${elapsed}s" ;;
    124 | 137) verdict="HUNG, killed after ${deadline}s" ;;
    *) verdict="failed with exit ${code} after ${elapsed}s" ;;
esac

echo "verdict: ${label}: ${verdict}"
echo "- \`${label}\`: ${verdict}" >> "$GITHUB_STEP_SUMMARY"

# A killed `quarto` leaves the notebook server running, and a killed probe
# leaves kaleido running. Quarto 1.7.17 has no `quarto call engine julia kill`,
# so go through the process list.
if command -v taskkill > /dev/null; then
    taskkill //F //IM julia.exe || true
    taskkill //F //IM kaleido.exe || true
else
    pkill -f QuartoNotebookRunner || true
    pkill -f kaleido || true
fi

exit 0
